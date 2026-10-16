// =====================================================================
//  FINANCIAL STATEMENTS SYNC (P&L, Balance Sheet, Trial Balance, Expenses)
//  ---------------------------------------------------------------------
//  Light on Tally by design. Tally does not recalculate any report here.
//  Every sync may send only LIGHT requests (masters, no balances):
//    1. the group tree (names, parents, Revenue / Deemed-positive /
//       Affects-gross-profit flags), once a day;
//    2. the books-beginning date (Company) and the items' opening values
//       (StockItem OPENINGVALUE, as typed in the masters), once a day.
//  The server then starts from the ledger OPENING balances it already has
//  (ledger masters) and adds the synced vouchers — no balances from Tally.
//
//  Closing stock on past dates (month and year ends) can only come from
//  Tally's stock valuation, which is HEAVY on large companies (it once
//  kept Tally busy for 30 minutes). It is therefore OFF unless switched on
//  (FIN_STOCK_FROM_TALLY=1, after tools/fin-probe.cjs showed it is quick),
//  and then: one such request per sync, a 90-second limit, and a 7-day
//  pause if Tally is slow. Never for dates before the books begin. Order:
//  year ends (each year's opening stock), yesterday (one value per day from
//  then on), month ends newest first. Paced: at most one per 30 minutes
//  (4 hours after one that took over 15 s), only when Tally answers a tiny
//  request at once (isIdle), and optionally only inside given hours
//  (heavyHours, e.g. "13-14"; default any time — office PCs are off at night).
//
//  Optional (FIN_TALLY_ANCHOR=1): when the synced vouchers begin after the
//  books begin, one ledger-balance request on the day before they begin.
//  Read-only towards Tally; existing sync steps are not touched.
// =====================================================================
"use strict";

const ROWS_PER_POST = 2000;
const DAY_MS = 86400000;
const MAX_HEAVY = 1; // heavy Tally requests per sync
const HEAVY_TIMEOUT_MS = 90000; // a heavy request that takes longer: pause
const LIGHT_TIMEOUT_MS = 120000;
const PAUSE_AFTER_SLOW_MS = 7 * DAY_MS;
// Pace of heavy requests (stock values): one per 30 minutes; after one that
// took over 15 s, the next waits 4 hours.
const HEAVY_EVERY_MS = 30 * 60 * 1000;
const HEAVY_SLOW_MS = 15000;
const HEAVY_SLOW_EVERY_MS = 4 * 60 * 60 * 1000;
// A company whose Tally did not answer a heavy request in time this many
// times (each followed by the 7-day pause): heavy requests are switched off
// for it for good (the Agent decides; nothing to set on the PC).
const MAX_HEAVY_TIMEOUTS = 2;
const DAILY_MS = 24 * 3600 * 1000;
const ANCHOR_REFRESH_MS = 7 * DAY_MS;
const RECENT_STOCK_REFRESH_MS = 7 * DAY_MS;

/** Date → "YYYY-MM-DD" (local calendar date). */
function iso(d) {
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}
const tallyDate = (s) => s.replace(/-/g, "");
const yearBefore = (s) => `${Number(s.slice(0, 4)) - 1}${s.slice(4)}`;
const yearAfter = (s) => `${Number(s.slice(0, 4)) + 1}${s.slice(4)}`;

function addDays(s, n) {
  const d = new Date(`${s}T00:00:00`);
  d.setDate(d.getDate() + n);
  return iso(d);
}

/** "20250401" / "1-Apr-2025" / ISO → "2025-04-01" (or null). */
function isoFromTally(v) {
  const s = String(v || "").trim();
  if (/^\d{8}$/.test(s)) return `${s.slice(0, 4)}-${s.slice(4, 6)}-${s.slice(6, 8)}`;
  if (/^\d{4}-\d{2}-\d{2}/.test(s)) return s.slice(0, 10);
  const d = new Date(s);
  return Number.isNaN(d.getTime()) ? null : iso(d);
}

/** Month ends from [from] up to [last] (inclusive, YYYY-MM-DD). */
function monthEnds(from, last) {
  const out = [];
  const start = new Date(`${from}T00:00:00`);
  for (let i = 0; i < 240; i++) {
    const end = iso(new Date(start.getFullYear(), start.getMonth() + i + 1, 0));
    if (end > last) break;
    out.push(end);
  }
  return out;
}

/** Start of the financial year holding [d] (years start on [fyFrom]'s MM-DD). */
function fyStartOf(d, fyFrom) {
  const md = fyFrom.slice(5);
  const same = `${d.slice(0, 4)}-${md}`;
  return same <= d ? same : yearBefore(same);
}

/**
 * The heavy work this sync may do, most useful first:
 *   year ends (each later year needs its opening stock), then month ends,
 *   newest first; the two newest month ends re-checked weekly.
 * [booksFrom] null → nothing (the books date comes first).
 */
function planHeavy({ fyFrom, booksFrom, syncStart, today, state, nowMs, stockFromTally, tallyAnchor, daily = true }) {
  const st = state || {};
  const items = [];
  if (!booksFrom || !fyFrom) return items;
  if (st.fin_paused_until && nowMs < st.fin_paused_until) return items;
  const yesterday = addDays(today, -1);
  // Vouchers begin after the books: Tally's balances the day before.
  if (tallyAnchor && syncStart && syncStart > booksFrom && syncStart <= today) {
    const asOn = addDays(syncStart, -1);
    const done = (st.fin_anchors || {})[asOn];
    if (!done || nowMs - done >= ANCHOR_REFRESH_MS) {
      items.push({ kind: "anchor", asOn, fyFrom: fyStartOf(asOn, fyFrom) });
    }
  }
  if (stockFromTally) {
    const stock = st.fin_stock || {};
    const ends = [];
    // Year ends after the books begin, up to yesterday.
    for (let f = yearAfter(fyStartOf(booksFrom, fyFrom)); addDays(f, -1) <= yesterday; f = yearAfter(f)) {
      ends.push({ asOn: addDays(f, -1), yearEnd: true });
    }
    for (const d of monthEnds(booksFrom, yesterday)) {
      if (!ends.some((x) => x.asOn === d)) ends.push({ asOn: d, yearEnd: false });
    }
    // Yesterday's closing stock, once per day: from now on every day gets
    // Tally's own value, so reports can be shown for any later date.
    if (daily && yesterday >= booksFrom && !ends.some((x) => x.asOn === yesterday)) {
      ends.push({ asOn: yesterday, yearEnd: false, daily: true });
    }
    ends.sort((a, b) => (a.yearEnd !== b.yearEnd ? (a.yearEnd ? -1 : 1) : a.asOn < b.asOn ? 1 : -1));
    // The two newest MONTH ends are re-read weekly (late entries); a day's
    // value is read once.
    const recent = ends.filter((e) => !e.yearEnd && !e.daily).slice(0, 2).map((e) => e.asOn);
    for (const e of ends) {
      if (e.asOn < booksFrom) continue;
      const done = stock[e.asOn];
      const stale = recent.includes(e.asOn) && done && nowMs - done >= RECENT_STOCK_REFRESH_MS;
      if (!done || stale) items.push({ kind: "stock", asOn: e.asOn, fyFrom: fyStartOf(e.asOn, fyFrom), ...(e.daily ? { daily: true } : {}) });
    }
  }
  return items;
}

/**
 * Is [date] inside the hours heavy requests may run ("20-8" = 20:00 to
 * 08:00, "9-18" = 09:00 to 18:00, "all" / empty = any time)?
 */
function inHeavyHours(date, spec) {
  const m = /^\s*(\d{1,2})\s*-\s*(\d{1,2})\s*$/.exec(String(spec || ""));
  if (!m) return true;
  const start = Number(m[1]) % 24;
  const end = Number(m[2]) % 24;
  const h = date.getHours();
  if (start === end) return true;
  return start < end ? h >= start && h < end : h >= start || h < end;
}

/** Is it a timeout (axios / our own)? */
const isTimeout = (e) => e && (e.code === "ECONNABORTED" || /timeout/i.test(String(e.message || "")));

/**
 * @param {object} deps
 * @param {(xml: string, timeoutMs?: number) => Promise<{data: string}>} deps.tallyPost
 * @param {(xml: string) => Promise<object>} deps.parseXml   sanitising, explicitArray false
 * @param {(val: any) => number} deps.parseNumber            Tally amount → number (Dr negative)
 * @param {(path: string, body: object) => Promise<{data: any}>} deps.post
 * @param {(msg: string) => void} [deps.log]
 * @param {() => number} [deps.clock]  how long a heavy request took
 */
function createFinancialSync({ tallyPost, parseXml, parseNumber, post, log = () => {}, clock = () => Date.now() }) {
  const text = (v) => {
    if (v == null) return "";
    if (typeof v === "string") return v.trim();
    if (typeof v === "object" && v._ != null) return String(v._).trim();
    return String(v).trim();
  };
  const yes = (v) => /^yes$/i.test(text(v));
  const list = (v) => (v == null ? [] : Array.isArray(v) ? v : [v]);
  const nameOf = (o) => text(o?.$?.NAME) || text(o?.NAME);

  function collectionXml(company, type, fetch, { from, to, filter } = {}) {
    const period =
      from && to ? `\n    <SVFROMDATE>${tallyDate(from)}</SVFROMDATE>\n    <SVTODATE>${tallyDate(to)}</SVTODATE>` : "";
    const filterTag = filter ? `\n      <FILTERS>TCFinFilter</FILTERS>` : "";
    const formula = filter ? `\n     <SYSTEM TYPE="Formulae" NAME="TCFinFilter">${filter}</SYSTEM>` : "";
    return `
<ENVELOPE>
 <HEADER>
  <VERSION>1</VERSION>
  <TALLYREQUEST>Export Data</TALLYREQUEST>
  <TYPE>Collection</TYPE>
  <ID>TCFin${type}</ID>
 </HEADER>
 <BODY>
  <DESC>
   <STATICVARIABLES>
    <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
    <SVCURRENTCOMPANY>${company}</SVCURRENTCOMPANY>${period}
   </STATICVARIABLES>
   <TDL>
    <TDLMESSAGE>
     <COLLECTION NAME="TCFin${type}">
      <TYPE>${type}</TYPE>
      <FETCH>${fetch}</FETCH>${filterTag}
     </COLLECTION>${formula}
    </TDLMESSAGE>
   </TDL>
  </DESC>
 </BODY>
</ENVELOPE>`;
  }

  async function collection(company, type, fetch, opts = {}) {
    const res = await tallyPost(collectionXml(company, type, fetch, opts), opts.timeoutMs || LIGHT_TIMEOUT_MS);
    const parsed = await parseXml(res.data);
    return list(parsed?.ENVELOPE?.BODY?.DATA?.COLLECTION?.[type.toUpperCase()]);
  }

  // ------------------------------------------------------------ light
  /** Group masters only (no balances). */
  async function fetchGroups(company) {
    return (await collection(company, "Group", "NAME, PARENT, ISREVENUE, ISDEEMEDPOSITIVE, AFFECTSGROSSPROFIT"))
      .map((g) => ({
        name: nameOf(g),
        parent: text(g.PARENT) || "Primary",
        is_revenue: yes(g.ISREVENUE),
        is_deemed_positive: yes(g.ISDEEMEDPOSITIVE),
        affects_gross_profit: yes(g.AFFECTSGROSSPROFIT),
      }))
      .filter((g) => g.name);
  }

  /** The books-beginning date (Company master). */
  async function fetchBooksFrom(company) {
    const rows = await collection(company, "Company", "NAME, STARTINGFROM");
    const want = String(company || "").toLowerCase();
    const c = rows.find((x) => nameOf(x).toLowerCase() === want) || rows.find((x) => nameOf(x).toLowerCase().includes(want)) || rows[0];
    return c ? isoFromTally(text(c.STARTINGFROM)) : null;
  }

  /** Opening stock on the books' first day: the items' opening values as typed in the masters. */
  async function fetchOpeningStock(company) {
    const rows = await collection(company, "StockItem", "NAME, OPENINGVALUE");
    let sum = 0;
    for (const r of rows) sum += parseNumber(r.OPENINGVALUE ?? "0") || 0;
    return Math.round(Math.abs(sum) * 100) / 100;
  }

  // ------------------------------------------------------------ heavy
  /** Stock-in-Hand value on [asOn] (Tally values the stock: heavy). */
  async function fetchStock(company, fyFrom, asOn) {
    const rows = await collection(company, "Group", "NAME, CLOSINGBALANCE", {
      from: fyFrom,
      to: asOn,
      filter: `$Name = $$GroupStock OR $Name = "Stock-in-Hand"`,
      timeoutMs: HEAVY_TIMEOUT_MS,
    });
    const g = rows.find((x) => /^stock[\s-]*in[\s-]*hand$/i.test(nameOf(x))) || rows[0];
    return g ? parseNumber(g.CLOSINGBALANCE ?? "0") : 0;
  }

  /** Every ledger's closing balance on [asOn] (heavy; only with FIN_TALLY_ANCHOR). */
  async function fetchLedgerBalances(company, fyFrom, asOn) {
    return (
      await collection(company, "Ledger", "NAME, GUID, PARENT, CLOSINGBALANCE", { from: fyFrom, to: asOn, timeoutMs: HEAVY_TIMEOUT_MS })
    )
      .map((l) => ({
        name: nameOf(l),
        guid: text(l.GUID) || null,
        parent: text(l.PARENT) || "Primary",
        closing: parseNumber(l.CLOSINGBALANCE ?? "0"),
        opening: 0,
      }))
      .filter((l) => l.name);
  }

  async function uploadAnchor(companyGuid, asOn, fyFrom, ledgers) {
    const b = await post("/api/financial/agent/snapshot/begin", { company_guid: companyGuid, as_on: asOn, fy_from: fyFrom, kind: "anchor" });
    const batchId = b.data?.batch_id;
    if (!batchId) throw new Error("financial upload: no batch id from the server");
    for (let i = 0; i < ledgers.length; i += ROWS_PER_POST) {
      await post("/api/financial/agent/snapshot/rows", { batch_id: batchId, ledgers: ledgers.slice(i, i + ROWS_PER_POST), groups: [] });
    }
    await post("/api/financial/agent/snapshot/commit", { batch_id: batchId, ledger_count: ledgers.length, group_count: 0 });
  }

  /**
   * One run for the active company.
   * @param {{companyGuid: string, companyName: string, fyFrom: string,
   *   syncStart?: string, state: object, saveState: (s: object) => void,
   *   now?: Date, stopRequested?: () => boolean,
   *   stockFromTally?: boolean, tallyAnchor?: boolean}} opts
   */
  async function run({
    companyGuid,
    companyName,
    fyFrom,
    syncStart,
    state,
    saveState,
    now = new Date(),
    stopRequested = () => false,
    stockFromTally = false,
    tallyAnchor = false,
    heavyHours = "all",
    isIdle = null,
    heavyEveryMs = HEAVY_EVERY_MS,
    heavySlowMs = HEAVY_SLOW_MS,
    heavySlowEveryMs = HEAVY_SLOW_EVERY_MS,
    forceHeavy = false,
  }) {
    const today = iso(now);
    const nowMs = now.getTime();
    const done = [];
    if (!fyFrom) return { done, left: 0, skipped: "Tally's financial year is not known yet" };

    // ---- light, once a day
    if (!state.fin_groups_at || nowMs - state.fin_groups_at >= DAILY_MS) {
      const groups = await fetchGroups(companyName);
      if (!groups.length) return { done, left: 0, skipped: "Tally returned no groups" };
      await post("/api/financial/agent/groups", { company_guid: companyGuid, groups });
      state.fin_groups_at = nowMs;
      saveState(state);
      done.push("groups");
    }
    if (stopRequested()) return { done, left: 0, skipped: null };
    if (!state.fin_books_at || nowMs - state.fin_books_at >= DAILY_MS) {
      const booksFrom = await fetchBooksFrom(companyName);
      if (!booksFrom) return { done, left: 0, skipped: "Tally did not give the books-beginning date" };
      const openingStock = await fetchOpeningStock(companyName);
      await post("/api/financial/agent/books", {
        company_guid: companyGuid,
        books_from: booksFrom,
        vouchers_from: syncStart || null,
        opening_stock: openingStock,
        fy_from: fyStartOf(booksFrom, fyFrom),
      });
      state.fin_books_from = booksFrom;
      state.fin_books_at = nowMs;
      saveState(state);
      done.push("books");
    }

    // ---- heavy, at most MAX_HEAVY, only when switched on
    // Switched off for this company by the Agent itself (Tally too slow
    // MAX_HEAVY_TIMEOUTS times) — unless forced on.
    if (state.fin_heavy_off_at && !forceHeavy && (stockFromTally || tallyAnchor)) {
      return { done, left: 0, skipped: null, off: true };
    }
    const plan = () =>
      planHeavy({ fyFrom, booksFrom: state.fin_books_from, syncStart, today, state, nowMs, stockFromTally, tallyAnchor });
    // Heavy requests make Tally value stock: only in the allowed hours and
    // only when Tally answers a tiny request at once (nobody is keeping it
    // busy). Otherwise nothing heavy is sent this sync.
    const pending = plan().length;
    // Paced: one heavy request per heavyEveryMs (longer after a slow one),
    // not one per sync — the Agent runs in office hours too.
    if (pending && state.fin_heavy_next_at && nowMs < state.fin_heavy_next_at) {
      const at = new Date(state.fin_heavy_next_at);
      const hhmm = `${String(at.getHours()).padStart(2, "0")}:${String(at.getMinutes()).padStart(2, "0")}`;
      return { done, left: pending, skipped: null, waiting: `next stock value from Tally after ${hhmm}` };
    }
    if (pending && !inHeavyHours(now, heavyHours)) {
      return { done, left: pending, skipped: null, waiting: `stock values from Tally run only between ${heavyHours} h` };
    }
    if (pending && !stopRequested() && typeof isIdle === "function" && !(await isIdle())) {
      return { done, left: pending, skipped: null, waiting: "Tally is busy right now — stock values next sync" };
    }
    let heavy = 0;
    for (const it of plan()) {
      if (heavy >= MAX_HEAVY || stopRequested()) break;
      heavy++;
      const startedAt = clock();
      try {
        if (it.kind === "anchor") {
          const ledgers = await fetchLedgerBalances(companyName, it.fyFrom, it.asOn);
          await uploadAnchor(companyGuid, it.asOn, it.fyFrom, ledgers);
          state.fin_anchors = { ...(state.fin_anchors || {}), [it.asOn]: nowMs };
          done.push(`anchor ${it.asOn}`);
        } else {
          const v = await fetchStock(companyName, it.fyFrom, it.asOn);
          await post("/api/financial/agent/stock-values", { company_guid: companyGuid, values: [{ as_on: it.asOn, value: Math.abs(v) }] });
          state.fin_stock = { ...(state.fin_stock || {}), [it.asOn]: nowMs };
          done.push(`stock ${it.asOn}`);
        }
        const took = clock() - startedAt;
        const slow = took > heavySlowMs;
        state.fin_heavy_next_at = nowMs + (slow ? heavySlowEveryMs : heavyEveryMs);
        state.fin_heavy_timeouts = 0; // answered in time: earlier misses are forgiven
        if (slow) {
          log(
            `🐢 Tally took ${Math.round(took / 1000)} s for the ${it.kind === "anchor" ? "ledger balances" : "closing stock"} of ${it.asOn} — ` +
              `the next one waits ${Math.round(heavySlowEveryMs / 3600000)} h.`
          );
        }
        saveState(state);
      } catch (e) {
        if (!isTimeout(e)) throw e;
        state.fin_paused_until = nowMs + PAUSE_AFTER_SLOW_MS;
        state.fin_heavy_timeouts = Number(state.fin_heavy_timeouts || 0) + 1;
        const what = it.kind === "anchor" ? "ledger balances" : "closing stock";
        if (state.fin_heavy_timeouts >= MAX_HEAVY_TIMEOUTS && !forceHeavy) {
          state.fin_heavy_off_at = nowMs;
          saveState(state);
          log(
            `⛔ Tally did not answer the ${what} of ${it.asOn} within ${HEAVY_TIMEOUT_MS / 1000}s again ` +
              `(${state.fin_heavy_timeouts} times). Stock values from Tally are switched OFF for this company.`
          );
          return { done, left: 0, skipped: "Tally too slow for stock values; switched off for this company" };
        }
        saveState(state);
        log(
          `⚠️ Tally took longer than ${HEAVY_TIMEOUT_MS / 1000}s for the ${what} ` +
            `of ${it.asOn}. Heavy financial requests are paused for 7 days (Tally may stay busy for a while).`
        );
        return { done, left: 0, skipped: "Tally was slow; paused for 7 days" };
      }
    }
    return { done, left: plan().length, skipped: null };
  }

  return { run, fetchGroups, fetchBooksFrom, fetchOpeningStock, fetchStock, fetchLedgerBalances };
}

module.exports = {
  createFinancialSync,
  planHeavy,
  inHeavyHours,
  monthEnds,
  fyStartOf,
  addDays,
  yearBefore,
  isoFromTally,
  iso,
  DAY_MS,
  MAX_HEAVY,
  HEAVY_TIMEOUT_MS,
  HEAVY_EVERY_MS,
  HEAVY_SLOW_MS,
  HEAVY_SLOW_EVERY_MS,
  MAX_HEAVY_TIMEOUTS,
};
