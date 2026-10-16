"use strict";
// Bill-wise allocations of vouchers (Tally's BILLALLOCATIONS.LIST on the
// party line: New Ref / Agst Ref / Advance / On Account) for the cash flow
// forecast: which receipt / payment settled which bill, and when. Read from
// the vouchers the Agent already fetches, then uploaded to
// POST /api/cashflow/agent/settlements (replaced per voucher on the server).
// Nothing here talks to Tally or changes another sync.

/** Agent's value extractor shape (string or {_: text}). */
function text(v, extract) {
  const x = extract ? extract(v) : v;
  if (x === null || x === undefined) return "";
  if (typeof x === "object") return String(x._ ?? "").trim();
  return String(x).trim();
}

const clean = (s) => String(s || "").replace(/[\x00-\x08\x0B\x0C\x0E-\x1F]/g, "").trim();
const asList = (v) => (Array.isArray(v) ? v : v ? [v] : []);

/** Tally YYYYMMDD → YYYY-MM-DD (null when not a date). */
function isoDate(raw) {
  const s = String(raw || "").trim();
  if (/^\d{8}$/.test(s)) return `${s.slice(0, 4)}-${s.slice(4, 6)}-${s.slice(6, 8)}`;
  if (/^\d{4}-\d{2}-\d{2}/.test(s)) return s.slice(0, 10);
  return null;
}

/** "30 Days" / {_: "30 Days"} / "45" → 30 / 45; null when none. */
function creditDays(raw) {
  const s = typeof raw === "object" && raw !== null ? String(raw._ ?? raw.$?.P ?? "") : String(raw ?? "");
  const m = /-?\d+/.exec(s);
  if (!m) return null;
  const n = Number(m[0]);
  return Number.isFinite(n) && n >= 0 && n <= 3650 ? n : null;
}

/** "Agst Ref" / "New Ref" / "Advance" / "On Account" (as Tally names them). */
function refType(raw) {
  const s = clean(raw).toLowerCase();
  if (s.startsWith("agst")) return "Agst Ref";
  if (s.startsWith("new")) return "New Ref";
  if (s.startsWith("adv")) return "Advance";
  if (s.startsWith("on acc")) return "On Account";
  return s ? clean(raw).slice(0, 30) : "";
}

/**
 * The bill allocations of one voucher (raw Tally object, as the voucher
 * sync reads it: fields are arrays, `extract` reads a value).
 * amount keeps Tally's sign (debit negative, credit positive).
 * → [{voucher_guid, voucher_date, voucher_type, voucher_no, ledger_name,
 *     bill_name, ref_type, amount, credit_days}]
 */
function allocationsOf(src, extract, meta = {}) {
  if (!src || typeof src !== "object") return [];
  const guid = meta.voucher_guid || text(src.GUID?.[0], extract);
  const date = meta.voucher_date || isoDate(text(src.DATE?.[0], extract));
  if (!guid || !date) return [];
  const type = meta.voucher_type || text(src.VOUCHERTYPENAME?.[0], extract);
  const no = meta.voucher_no || text(src.VOUCHERNUMBER?.[0], extract);
  const lines = asList(src["ALLLEDGERENTRIES.LIST"] ?? src["LEDGERENTRIES.LIST"]);
  const byKey = new Map();
  for (const le of lines) {
    if (!le || typeof le !== "object") continue;
    const ledger = clean(text(le.LEDGERNAME?.[0], extract));
    if (!ledger) continue;
    for (const a of asList(le["BILLALLOCATIONS.LIST"])) {
      if (!a || typeof a !== "object") continue;
      const bill = clean(text(a.NAME?.[0], extract));
      const kind = refType(text(a.BILLTYPE?.[0], extract));
      const amount = Number(text(a.AMOUNT?.[0], extract));
      if (!bill || !kind || !Number.isFinite(amount) || amount === 0) continue;
      const key = `${ledger}\u0001${bill}\u0001${kind}`;
      const cur = byKey.get(key);
      if (cur) {
        cur.amount = Math.round((cur.amount + amount) * 100) / 100;
        continue;
      }
      byKey.set(key, {
        voucher_guid: guid,
        voucher_date: date,
        voucher_type: type.slice(0, 100),
        voucher_no: no.slice(0, 200),
        ledger_name: ledger.slice(0, 300),
        bill_name: bill.slice(0, 300),
        ref_type: kind,
        amount: Math.round(amount * 100) / 100,
        credit_days: creditDays(a.BILLCREDITPERIOD?.[0]),
      });
    }
  }
  return [...byKey.values()].filter((r) => r.amount !== 0);
}

/**
 * Collects allocations while vouchers are read and uploads them in batches.
 * Vouchers without allocations are sent too (as an empty list), so an edit
 * that removed them clears the old rows. A server without the route (404)
 * turns uploading off for this run.
 */
function createSettlementSink({ post, log = console, batchSize = 400, maxWaiting = 20000 }) {
  let rows = [];
  let guids = new Set();
  let off = false;
  let sent = 0;
  let retry = []; // [{company, guids, rows}] uploads that failed

  return {
    /** Adds one voucher's allocations (raw Tally voucher). */
    add(src, extract, meta) {
      if (off) return;
      const guid = meta?.voucher_guid || text(src?.GUID?.[0], extract);
      if (!guid) return;
      guids.add(guid);
      rows.push(...allocationsOf(src, extract, meta));
    },
    pending: () => guids.size,
    sentRows: () => sent,
    disabled: () => off,
    /** Uploads still waiting after a failure (vouchers). */
    waiting: () => retry.reduce((a, x) => a + x.guids.length, 0),
    /**
     * Uploads what was collected for [companyGuid], plus earlier uploads
     * that failed; never throws. failed > 0: something is still waiting.
     */
    async flush(companyGuid) {
      if (off || !companyGuid) {
        rows = [];
        guids = new Set();
        return { sent: 0, failed: 0 };
      }
      const parts = retry.filter((x) => x.company === companyGuid);
      retry = retry.filter((x) => x.company !== companyGuid);
      const allGuids = [...guids];
      const allRows = rows;
      rows = [];
      guids = new Set();
      for (let i = 0; i < allGuids.length; i += batchSize) {
        const part = new Set(allGuids.slice(i, i + batchSize));
        parts.push({ company: companyGuid, guids: [...part], rows: allRows.filter((r) => part.has(r.voucher_guid)) });
      }
      let n = 0;
      let failed = 0;
      let lastStatus = null;
      for (let i = 0; i < parts.length; i++) {
        const p = parts[i];
        try {
          await post({ company_guid: p.company, voucher_guids: p.guids, rows: p.rows });
          n += p.rows.length;
        } catch (e) {
          const status = e?.response?.status;
          if (status === 404) {
            off = true;
            retry = [];
            log.log?.("ℹ️ Bill settlements: the server has no /api/cashflow route yet — skipped.");
            return { sent: n, failed: 0 };
          }
          lastStatus = status || e.message;
          // Kept and sent again with the next upload (while the Agent runs).
          retry.push(...parts.slice(i));
          failed = parts.length - i;
          break;
        }
      }
      // Never let a long outage grow without limit: oldest dropped first.
      while (retry.reduce((a, x) => a + x.guids.length, 0) > maxWaiting && retry.length) retry.shift();
      if (failed) {
        log.warn?.(
          `⚠️ Bill settlements upload failed (${lastStatus})` +
            (lastStatus === 503 ? " — the server's cash flow tables are not set up yet (run the Phase 2 SQL)" : "") +
            ` — ${failed} batch(es) kept, sent again next time.`
        );
      }
      sent += n;
      return { sent: n, failed };
    },
  };
}

module.exports = { allocationsOf, createSettlementSink, creditDays, isoDate, refType };
