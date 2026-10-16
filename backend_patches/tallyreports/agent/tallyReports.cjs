"use strict";
// =====================================================================
//  OFFICIAL TALLY FIGURES — in SMALL PIECES, so Tally never hangs
//  ---------------------------------------------------------------------
//  Tally's own report screens (Balance Sheet, P&L, Cash Flow) make Tally
//  recalculate everything at once — on a big company that freezes Tally.
//  They are NEVER requested. Instead the Agent asks for small pieces of
//  Tally's own figures and the server builds the reports from them:
//    1. ledger balances      — about 40 ledgers per request
//    2. stock item values    — about 15 items per request (closing at the
//                              period end, opening at the year start)
//    3. cash / bank balances — one month per request (Cash Flow)
//  Then one upload: POST /api/tally-reports/agent/snapshot.
//
//  Rules (all adjustable, see DEFAULTS):
//   - a rest before the first piece and a gap between pieces;
//   - only a few pieces per sync run; progress is saved after every
//     piece, so the next run carries on where this one stopped;
//   - a tiny "is Tally answering?" check first — slow → nothing this run;
//   - a short time limit per piece; a slow piece makes the next pieces
//     smaller; a timeout makes them much smaller and rests Tally for a
//     while (Tally keeps working after we give up);
//   - nothing changed in Tally since the last full set → nothing asked.
//  Read-only towards Tally.
// =====================================================================

const DEFAULTS = {
  piecesPerRun: 6, // small requests per sync run
  pauseMs: 10000, // rest before the first piece
  gapMs: 8000, // gap between pieces
  pieceTimeoutMs: 30000, // per piece
  slowMs: 5000, // slower than this → next pieces half the size
  coolMs: 30 * 60 * 1000, // after a timeout: no piece for 30 min
  pingTimeoutMs: 15000, // "is Tally answering?"
  ledgerChunk: 40, // ledgers per piece (start; adapts)
  stockChunk: 15, // stock items per piece (start; adapts)
  refreshMs: 6 * 60 * 60 * 1000, // today's figures at most every 6 h
  prevYearEveryMs: 30 * 24 * 60 * 60 * 1000, // last year's close
};
const MIN_CHUNK = { ledger: 5, stock: 3 };
const MAX_CHUNK = { ledger: 120, stock: 50 };
const CASH_GROUPS = new Set(["cash-in-hand", "bank accounts", "bank od a/c", "bank occ a/c"]);

const esc = (s) =>
  String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
const tallyDate = (iso) => String(iso).replace(/-/g, "");
const pad = (n) => String(n).padStart(2, "0");
const isoOf = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const addDaysIso = (iso, n) => {
  const [y, m, d] = iso.split("-").map(Number);
  return isoOf(new Date(y, m - 1, d + n));
};
const norm = (s) =>
  String(s ?? "")
    .replace(/[\u0000-\u001f]/g, "")
    .trim()
    .toLowerCase();

/** Start of the financial year holding [iso] (years start on [fyMd] "MM-DD"). */
function fyStartOf(iso, fyMd = "04-01") {
  const same = `${iso.slice(0, 4)}-${fyMd}`;
  return same <= iso ? same : `${Number(iso.slice(0, 4)) - 1}-${fyMd}`;
}

/** Calendar months of [from, to]: [{from, to}] (last one ends on [to]). */
function monthsOf(from, to) {
  const out = [];
  let [y, m] = from.split("-").map(Number);
  let start = from;
  while (start <= to) {
    const end = isoOf(new Date(y, m, 0));
    out.push({ from: start, to: end < to ? end : to });
    m += 1;
    if (m > 12) {
      m = 1;
      y += 1;
    }
    start = `${y}-${pad(m)}-01`;
  }
  return out;
}

// ------------------------------------------------------------ requests
/** A TDL filter for exactly these names ($Name = "a" OR $Name = "b" …). */
function nameFilter(names) {
  return names.map((n) => `$Name = "${esc(String(n).replace(/"/g, ""))}"`).join(" OR ");
}

function collectionXml(id, type, fetch, company, from, to, names) {
  return `
<ENVELOPE>
 <HEADER>
  <VERSION>1</VERSION>
  <TALLYREQUEST>Export Data</TALLYREQUEST>
  <TYPE>Collection</TYPE>
  <ID>${id}</ID>
 </HEADER>
 <BODY>
  <DESC>
   <STATICVARIABLES>
    <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
    <SVCURRENTCOMPANY>${esc(company)}</SVCURRENTCOMPANY>
    <SVFROMDATE>${tallyDate(from)}</SVFROMDATE>
    <SVTODATE>${tallyDate(to)}</SVTODATE>
   </STATICVARIABLES>
   <TDL>
    <TDLMESSAGE>
     <COLLECTION NAME="${id}">
      <TYPE>${type}</TYPE>
      <FETCH>${fetch}</FETCH>
      <FILTERS>TCPick</FILTERS>
     </COLLECTION>
     <SYSTEM TYPE="Formulae" NAME="TCPick">${nameFilter(names)}</SYSTEM>
    </TDLMESSAGE>
   </TDL>
  </DESC>
 </BODY>
</ENVELOPE>`;
}

/** Balances of these ledgers for [from, to] (Tally computes them). */
const ledgersXml = (company, from, to, names) =>
  collectionXml("TCLedgerPiece", "Ledger", "NAME, PARENT, OPENINGBALANCE, CLOSINGBALANCE", company, from, to, names);

/** Closing value of these stock items on [to] (period [from, to]). */
const stockXml = (company, from, to, names) =>
  collectionXml("TCStockPiece", "StockItem", "NAME, CLOSINGVALUE", company, from, to, names);

/** Tiny request: the company's last-change markers ("is Tally answering?"). */
function versionXml(company) {
  return `
<ENVELOPE>
 <HEADER>
  <VERSION>1</VERSION>
  <TALLYREQUEST>Export Data</TALLYREQUEST>
  <TYPE>Collection</TYPE>
  <ID>TCReportsVersion</ID>
 </HEADER>
 <BODY>
  <DESC>
   <STATICVARIABLES>
    <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
    <SVCURRENTCOMPANY>${esc(company)}</SVCURRENTCOMPANY>
   </STATICVARIABLES>
   <TDL>
    <TDLMESSAGE>
     <COLLECTION NAME="TCReportsVersion">
      <TYPE>Company</TYPE>
      <FETCH>NAME, ALTVCHID, ALTMSTID</FETCH>
     </COLLECTION>
    </TDLMESSAGE>
   </TDL>
  </DESC>
 </BODY>
</ENVELOPE>`;
}

// ------------------------------------------------------------- reading
const ENTITY = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'" };
function decode(s) {
  return String(s ?? "")
    .replace(/&(amp|lt|gt|quot|apos);/g, (_, k) => ENTITY[k])
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCharCode(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCharCode(Number(d)))
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, "")
    .trim();
}

/** Tally amount text → number (Dr / brackets / leading minus negative). */
function amountOf(t) {
  const s = String(t ?? "").trim();
  if (!s) return 0;
  const neg = /^-/.test(s) || /^\(.*\)$/.test(s.replace(/\s*(Dr|Cr)$/i, "")) || /\bDr$/i.test(s);
  const n = Number(s.replace(/[^0-9.]/g, ""));
  return Number.isFinite(n) ? Math.round((neg ? -n : n) * 100) / 100 : 0;
}

function objects(xml, tag) {
  const out = [];
  const re = new RegExp(`<${tag}\\b([^>]*)>([\\s\\S]*?)</${tag}>`, "g");
  let m;
  while ((m = re.exec(String(xml || "")))) {
    const body = m[2];
    const field = (f) => {
      const r = new RegExp(`<${f}\\b[^>]*>([^<]*)</${f}>`).exec(body);
      return r ? decode(r[1]) : "";
    };
    const name = decode((/\bNAME="([^"]*)"/.exec(m[1]) || [])[1] || "") || field("NAME");
    if (name) out.push({ name, field });
  }
  return out;
}

/** Ledger piece → [{name, parent, opening, closing}] (Dr negative). */
const readLedgers = (xml) =>
  objects(xml, "LEDGER").map((o) => ({
    name: o.name.slice(0, 300),
    parent: (o.field("PARENT") || "Primary").slice(0, 300),
    opening: amountOf(o.field("OPENINGBALANCE")),
    closing: amountOf(o.field("CLOSINGBALANCE")),
  }));

/** Stock piece → total closing value (positive). */
const readStockValue = (xml) =>
  Math.round(objects(xml, "STOCKITEM").reduce((a, o) => a + Math.abs(amountOf(o.field("CLOSINGVALUE"))), 0) * 100) / 100;

/** Why Tally refused, or null. */
function tallyRefusal(xml) {
  const s = String(xml || "");
  const err = /<LINEERROR>([\s\S]*?)<\/LINEERROR>/i.exec(s);
  if (err) return `Tally: ${decode(err[1]).slice(0, 200)}`;
  if (!/<ENVELOPE/i.test(s)) return "not an XML answer";
  return null;
}

function readVersion(xml, company) {
  const want = norm(company);
  const all = objects(xml, "COMPANY");
  const pick = all.find((o) => norm(o.name) === want) || all[0];
  if (!pick) return null;
  const v = [pick.field("ALTVCHID"), pick.field("ALTMSTID")];
  return v.some(Boolean) ? v.join(":") : null;
}

/** Ledgers under Cash-in-Hand / Bank Accounts / Bank OD (sub-groups too). */
function cashLedgers(ledgers, groups) {
  const up = new Map((groups || []).map((g) => [norm(g.name), norm(g.parent)]));
  const isCash = (parent) => {
    let g = norm(parent);
    const seen = new Set();
    while (g && !seen.has(g)) {
      if (CASH_GROUPS.has(g)) return true;
      seen.add(g);
      g = up.get(g) || "";
    }
    return false;
  };
  return ledgers.filter((l) => isCash(l.parent)).map((l) => l.name);
}

const isTimeout = (e) => !!e && (e.code === "ECONNABORTED" || /timeout/i.test(String(e.message || "")));

/**
 * A new set of pieces for one period: ledgers (sorted by group), stock items
 * (closing at [to]; opening = closing the day before [from], unless already
 * known), and cash / bank months.
 */
function newJob({ kind, from, to, ledgers, stockItems, cashNames, knownStock, version }) {
  const names = [...new Set(ledgers.map((l) => l.name).filter(Boolean))];
  const items = [...new Set((stockItems || []).map((s) => (typeof s === "string" ? s : s?.name)).filter(Boolean))];
  const openOn = addDaysIso(from, -1);
  const queue = [];
  for (const n of names) queue.push({ t: "ledger", name: n });
  for (const n of items) queue.push({ t: "stockClose", name: n });
  if (items.length && knownStock?.[openOn] === undefined) for (const n of items) queue.push({ t: "stockOpen", name: n });
  if (cashNames.length) for (const mo of monthsOf(from, to)) queue.push({ t: "cash", from: mo.from, to: mo.to });
  return {
    kind,
    from,
    to,
    version,
    queue,
    total: queue.length,
    cashNames,
    ledgers: [],
    stockClose: 0,
    stockOpen: items.length ? knownStock?.[openOn] ?? 0 : 0,
    hasStock: items.length > 0,
    cash: [],
    pieces: 0,
    seconds: 0,
    started: Date.now(),
  };
}

/**
 * @param {object} deps
 * @param {(xml: string, timeoutMs: number) => Promise<{data: string}>} deps.tallyPost
 * @param {(path: string, body: object) => Promise<any>} deps.post
 * @param {(ms: number) => Promise<void>} [deps.sleep]
 * @param {(msg: string) => void} [deps.log]
 */
function createTallyReports({ tallyPost, post, sleep = (ms) => new Promise((r) => setTimeout(r, ms)), log = () => {}, clock = () => Date.now() }) {
  /**
   * One run for one company: at most cfg.piecesPerRun small requests.
   * ledgers: [{name, parent}]; stockItems: [{name}] | [name];
   * getGroups: async () => [{name, parent}] (for cash / bank ledgers).
   * → {done: number, finished: string | null, skipped: string | null}
   */
  async function run({
    companyGuid,
    companyName,
    fyMd = "04-01",
    ledgers = [],
    stockItems = [],
    getGroups = async () => [],
    state,
    saveState,
    now = new Date(),
    stopRequested = () => false,
    config = {},
  }) {
    const cfg = { ...DEFAULTS, ...config };
    // Wall time during this run (clock() only measures how long pieces take).
    const runStart = clock();
    const nowMs = () => now.getTime() + (clock() - runStart);
    const st = (state.tally_reports2 = state.tally_reports2 || { last: {}, size: {}, knownStock: {} });
    st.last = st.last || {};
    st.size = st.size || {};
    st.knownStock = st.knownStock || {};
    const t = now.getTime();
    const out = { done: 0, finished: null, skipped: null };
    if (st.off_until && t < st.off_until) return { ...out, skipped: "server not ready (tried again later)" };
    if (st.cool_until && t < st.cool_until) return { ...out, skipped: "Tally resting after a slow piece" };
    if (!ledgers.length) return { ...out, skipped: "no ledger list from Tally this run" };

    // 1. Is Tally answering quickly? (and has anything changed?)
    let version = null;
    try {
      const v = await tallyPost(versionXml(companyName), cfg.pingTimeoutMs);
      version = readVersion(v.data, companyName);
    } catch (e) {
      return { ...out, skipped: isTimeout(e) ? "Tally is busy (did not answer a tiny request)" : `Tally not reachable: ${e.message}` };
    }

    // 2. What to fetch: today's figures, or last year's close.
    const today = isoOf(now);
    const fy = fyStartOf(today, fyMd);
    if (!st.job) {
      const lastToday = st.last.today;
      const todayDue =
        !lastToday ||
        lastToday.to !== today ||
        (t - lastToday.at >= cfg.refreshMs && (!version || version !== lastToday.version));
      const prevEnd = addDaysIso(fy, -1);
      const prevFrom = fyStartOf(prevEnd, fyMd);
      const lastPrev = st.last.prev;
      const prevDue = !lastPrev || lastPrev.to !== prevEnd || t - lastPrev.at >= cfg.prevYearEveryMs;
      let kind = null;
      let from;
      let to;
      if (todayDue && !(lastToday && lastToday.to === today && version && version === lastToday.version)) {
        kind = "today";
        from = fy;
        to = today;
      } else if (prevDue) {
        kind = "prev";
        from = prevFrom;
        to = prevEnd;
      }
      if (!kind) {
        if (lastToday && version && version === lastToday.version) lastToday.at = t; // unchanged: still valid
        saveState(state);
        return { ...out, skipped: null };
      }
      let groups = [];
      try {
        groups = await getGroups();
      } catch {
        groups = [];
      }
      st.job = newJob({
        kind,
        from,
        to,
        ledgers,
        stockItems,
        cashNames: cashLedgers(ledgers, groups || []),
        knownStock: st.knownStock,
        version,
      });
      saveState(state);
      log(`📑 Tally figures ${from}–${to}: ${st.job.total} small pieces to fetch (a few per sync).`);
    }

    // 3. A few small pieces, with gaps.
    const job = st.job;
    const size = (k) => Math.max(MIN_CHUNK[k], Math.min(MAX_CHUNK[k], st.size[k] || (k === "ledger" ? cfg.ledgerChunk : cfg.stockChunk)));
    let pieces = 0;
    while (job.queue.length && pieces < cfg.piecesPerRun) {
      if (stopRequested()) break;
      await sleep(pieces === 0 ? cfg.pauseMs : cfg.gapMs);
      if (stopRequested()) break;
      const head = job.queue[0];
      let take;
      let xml;
      if (head.t === "cash") {
        take = [head];
        xml = ledgersXml(companyName, head.from, head.to, job.cashNames);
      } else {
        const k = head.t === "ledger" ? "ledger" : "stock";
        take = [];
        for (const q of job.queue) {
          if (q.t !== head.t || take.length >= size(k)) break;
          take.push(q);
        }
        const names = take.map((q) => q.name);
        xml =
          head.t === "ledger"
            ? ledgersXml(companyName, job.from, job.to, names)
            : head.t === "stockClose"
            ? stockXml(companyName, job.from, job.to, names)
            : stockXml(companyName, fyStartOf(addDaysIso(job.from, -1), fyMd), addDaysIso(job.from, -1), names);
      }
      const started = clock();
      let res;
      try {
        res = await tallyPost(xml, cfg.pieceTimeoutMs);
      } catch (e) {
        const k = head.t === "ledger" ? "ledger" : head.t === "cash" ? null : "stock";
        if (isTimeout(e)) {
          // Tally keeps working after we give up: let it finish; much smaller pieces.
          st.cool_until = nowMs() + cfg.coolMs;
          if (k) st.size[k] = Math.max(MIN_CHUNK[k], Math.floor(size(k) / 4));
          log(`⏳ Tally figures: a piece took over ${Math.round(cfg.pieceTimeoutMs / 1000)} s — resting Tally ${Math.round(cfg.coolMs / 60000)} min; next pieces smaller.`);
        } else {
          st.cool_until = nowMs() + 5 * 60 * 1000;
          log(`⚠️ Tally figures: ${e.message} — tried again later.`);
        }
        saveState(state);
        return { ...out, done: pieces };
      }
      const ms = clock() - started;
      const refused = tallyRefusal(res.data);
      if (refused) {
        st.cool_until = nowMs() + 60 * 60 * 1000;
        log(`⚠️ Tally figures: ${refused} — tried again in 1 h.`);
        saveState(state);
        return { ...out, done: pieces };
      }
      if (head.t === "ledger") job.ledgers.push(...readLedgers(res.data));
      else if (head.t === "stockClose") job.stockClose = Math.round((job.stockClose + readStockValue(res.data)) * 100) / 100;
      else if (head.t === "stockOpen") job.stockOpen = Math.round((job.stockOpen + readStockValue(res.data)) * 100) / 100;
      else {
        const rows = readLedgers(res.data);
        job.cash.push({
          from: head.from,
          to: head.to,
          opening: Math.round(rows.reduce((a, r) => a + r.opening, 0) * 100) / 100,
          closing: Math.round(rows.reduce((a, r) => a + r.closing, 0) * 100) / 100,
        });
      }
      job.queue.splice(0, take.length);
      job.pieces += 1;
      job.seconds = Math.round((job.seconds + ms / 1000) * 10) / 10;
      pieces += 1;
      // Adapt the piece size to how fast this Tally answered.
      if (head.t !== "cash") {
        const k = head.t === "ledger" ? "ledger" : "stock";
        if (ms > cfg.slowMs) st.size[k] = Math.max(MIN_CHUNK[k], Math.floor(size(k) / 2));
        else if (ms < cfg.slowMs / 5) st.size[k] = Math.min(MAX_CHUNK[k], size(k) + Math.ceil(size(k) / 4));
      }
      saveState(state);
      if (ms > cfg.slowMs) {
        log(`🐢 Tally figures: a piece took ${(ms / 1000).toFixed(1)} s — smaller pieces next time; stopping for this sync.`);
        break;
      }
    }
    out.done = pieces;

    // 4. All pieces in: one upload; the server builds the reports.
    if (!job.queue.length) {
      try {
        await post("/api/tally-reports/agent/snapshot", {
          company_guid: companyGuid,
          period_from: job.from,
          period_to: job.to,
          ledgers: job.ledgers,
          stock: job.hasStock ? { opening: job.stockOpen, closing: job.stockClose } : null,
          cash_months: job.cash,
          pieces: job.pieces,
          fetch_seconds: job.seconds,
        });
      } catch (e) {
        const status = e?.response?.status;
        st.off_until = nowMs() + 60 * 60 * 1000;
        log(
          `ℹ️ Tally figures: upload ${status === 404 ? "— the server has no /api/tally-reports route yet" : status === 503 ? "— tables not set up on the server (run the SQL)" : `failed (${status || e.message})`}; tried again in 1 h.`
        );
        saveState(state);
        return out;
      }
      if (job.hasStock) {
        st.knownStock[job.to] = job.stockClose;
        st.knownStock[addDaysIso(job.from, -1)] = job.stockOpen;
      }
      st.last[job.kind] = { at: t, to: job.to, version: job.version, pieces: job.pieces, seconds: job.seconds };
      out.finished = `${job.from}–${job.to}`;
      log(`📑 Tally figures ${job.from}–${job.to}: complete (${job.pieces} pieces, ${job.seconds} s of Tally time) — uploaded.`);
      st.job = null;
      saveState(state);
    }
    return out;
  }

  return { run };
}

module.exports = {
  DEFAULTS,
  createTallyReports,
  ledgersXml,
  stockXml,
  versionXml,
  nameFilter,
  readLedgers,
  readStockValue,
  readVersion,
  tallyRefusal,
  cashLedgers,
  amountOf,
  monthsOf,
  fyStartOf,
  newJob,
};
