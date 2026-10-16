/* =========================================================
   CASH FLOW FORECAST — routes (factory; database passed in). Read-only.

   GET /api/cashflow/forecast?weeks=13&mode=adjusted|due&doubtful=0|1
       13 weeks (Monday–Sunday): opening, money in, money out, closing;
       receivables moved by each party's usual payment delay (mode
       adjusted) or on their due dates (mode due).
   GET /api/cashflow/week?start=YYYY-MM-DD&mode=…&doubtful=…
       the bills expected in one of those weeks.
   POST /api/cashflow/agent/settlements   (Agent, Phase 2) bill-wise
       allocations of vouchers → exact payment delays
   POST /api/cashflow/agent/bill-signs    (Agent, Phase 2) Dr / Cr of each
       current bill → advances are left out
   Phase 2 tables missing (SQL not run yet): the Phase 1 estimate is used.

   Who: the account admin, and team members the admin allowed to see
   financial reports (same rule as /api/financial/*). Active company only.

   Data (already synced; Phase 2 adds bill_settlements / bill_balance_signs):
     bills           open bills (pending_amount > 0), due dates
     voucher_entries each party's invoices and payments (delays)
     vouchers        voucher numbers → which bill an invoice is (due date)
     financial data  cash + bank balance today (createFinancialData)
========================================================= */
import express from "express";

import {
  WINDOW_DAYS,
  addDays,
  advanceKeys,
  allocationPayments,
  buildForecast,
  creditDays,
  delayFor,
  delayStats,
  fifoPayments,
  dayNum,
} from "./cashflowCore.js";

class HttpError extends Error {
  constructor(status, message, code) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

/** Today as YYYY-MM-DD in India time. */
export function todayIst(now = new Date()) {
  return new Date(now.getTime() + 330 * 60000).toISOString().slice(0, 10);
}

/** Same rules as the financial reports' figures. */
const SIGNED = "CASE WHEN ve.is_debit THEN ve.amount ELSE -ve.amount END"; // Cr +, Dr −
const NON_ACCOUNTING = "(memorandum|reversing journal|optional)";
const COUNTED = `COALESCE(ve.is_active, TRUE) = TRUE AND COALESCE(ve.voucher_type, '') !~* '${NON_ACCOUNTING}'`;

/**
 * A ledger name as Tally compares it (capitals ignored, line breaks and
 * repeated spaces = one space): voucher lines, bills and ledger masters can
 * spell the same ledger differently. SQL and JS give the same key.
 */
const NAME_KEY = (col) => `lower(btrim(regexp_replace(${col}, '[[:space:]]+', ' ', 'g')))`;
const nameKey = (s) =>
  String(s ?? "")
    .replace(/[ \t\r\n\f\v]+/g, " ")
    .trim()
    .toLowerCase();

/** Tally's cash / bank groups (sub-groups count too). */
const CASH_GROUPS = new Set(["cash-in-hand", "bank accounts", "bank od a/c", "bank occ a/c"]);
const norm = (s) =>
  String(s ?? "")
    .replace(/[\u0000-\u001f]/g, "")
    .trim()
    .toLowerCase();

export function isCashLedger(parent, groups) {
  const up = new Map((groups || []).map((g) => [norm(g.name), norm(g.parent)]));
  let g = norm(parent);
  const seen = new Set();
  while (g && !seen.has(g)) {
    if (CASH_GROUPS.has(g)) return true;
    seen.add(g);
    g = up.get(g) || "";
  }
  return false;
}

const iso = (d) => (d instanceof Date ? d.toISOString().slice(0, 10) : d ? String(d).slice(0, 10) : null);
const STATS_TTL_MS = 6 * 60 * 60 * 1000;

/**
 * @param {object} deps
 * @param {{query: Function}} deps.db
 * @param {Function} deps.auth
 * @param {object|null} [deps.financialData]  createFinancialData(db) (opening balance)
 * @param {() => Date} [deps.now]
 */
export function createCashflowRouter({ db, auth, financialData = null, log = console, now = () => new Date() }) {
  const router = express.Router();
  const statsCache = new Map(); // `${adminId}|${company}` → {at, stats}

  const handle = (fn) => async (req, res) => {
    try {
      await fn(req, res);
    } catch (err) {
      if (err instanceof HttpError) {
        return res.status(err.status).json({ success: false, message: err.message, ...(err.code ? { code: err.code } : {}) });
      }
      if (err?.code === "42P01") {
        // A Phase 2 table is missing: the SQL was not run on this database.
        log.error("cashflow: table missing — run sql/2026-10-17_cashflow_phase2.sql:", err?.message || err);
        return res.status(503).json({
          success: false,
          code: "not_set_up",
          message: "Cash flow tables are not set up on the server yet (run the Phase 2 SQL).",
        });
      }
      log.error("cashflow error:", err?.message || err);
      if (!res.headersSent) res.status(500).json({ success: false, message: "Server error" });
    }
  };

  const adminIdOf = (u) => u?.adminId ?? (u?.role === "ADMIN" ? u?.id : null);

  /** Admin, or a team member allowed to see financial reports. */
  async function readScope(req) {
    const u = req.user || {};
    if (!u.id) throw new HttpError(401, "Unauthorized");
    const adminId = adminIdOf(u);
    if (!adminId) throw new HttpError(403, "Access denied", "forbidden");
    if (u.role !== "ADMIN") {
      const a = await db.query(`SELECT 1 FROM financial_report_access WHERE admin_id = $1 AND user_id = $2`, [adminId, u.id]);
      if (!a.rowCount) throw new HttpError(403, "Ask your admin for access to financial reports.", "no_access");
    }
    const c = await db.query(
      `SELECT ac.company_guid, c.name AS company_name
         FROM active_company ac
         LEFT JOIN companies c ON c.company_guid = ac.company_guid AND c.admin_id = ac.admin_id
        WHERE ac.admin_id = $1 LIMIT 1`,
      [adminId]
    );
    const company = c.rows[0]?.company_guid;
    if (!company) throw new HttpError(409, "No company is selected for this account.", "no_company");
    return { adminId, company, companyName: c.rows[0]?.company_name || "" };
  }

  /* ------------------------------------------- agent: uploads (Phase 2) */
  /** The account admin's Agent, for one of its companies. */
  async function agentScope(req, companyGuid) {
    const u = req.user || {};
    if (u.role !== "ADMIN") throw new HttpError(403, "Only the account admin's agent can upload", "forbidden");
    const adminId = adminIdOf(u);
    const g = String(companyGuid || "").trim();
    if (!g || g.length > 100) throw new HttpError(400, "company_guid is required");
    const c = await db.query(`SELECT 1 FROM companies WHERE company_guid = $1 AND admin_id = $2`, [g, adminId]);
    if (!c.rowCount) throw new HttpError(403, "This company does not belong to this account", "forbidden");
    return { adminId, company: g };
  }

  /** One SQL transaction when the pool supports it (pg). */
  async function tx(fn) {
    if (typeof db.connect !== "function") return fn(db);
    const client = await db.connect();
    try {
      await client.query("BEGIN");
      const out = await fn(client);
      await client.query("COMMIT");
      return out;
    } catch (e) {
      await client.query("ROLLBACK").catch(() => {});
      throw e;
    } finally {
      client.release?.();
    }
  }

  const str = (v, max) => String(v ?? "").trim().slice(0, max);
  const REF_TYPES = new Set(["Agst Ref", "New Ref", "Advance", "On Account"]);

  /**
   * POST /api/cashflow/agent/settlements
   * {company_guid, voucher_guids: [...], rows: [{voucher_guid, voucher_date,
   *  voucher_type, voucher_no, ledger_name, bill_name, ref_type, amount,
   *  credit_days}]} — the listed vouchers' allocations are replaced.
   */
  router.post(
    "/api/cashflow/agent/settlements",
    auth,
    handle(async (req, res) => {
      const b = req.body || {};
      const s = await agentScope(req, b.company_guid);
      const guids = [...new Set((Array.isArray(b.voucher_guids) ? b.voucher_guids : []).map((g) => str(g, 120)).filter(Boolean))];
      if (!guids.length) throw new HttpError(400, "voucher_guids is required");
      if (guids.length > 2000) throw new HttpError(413, "At most 2000 vouchers per upload");
      const allowed = new Set(guids);
      const rows = [];
      const seen = new Set();
      for (const r of Array.isArray(b.rows) ? b.rows : []) {
        const row = {
          voucher_guid: str(r?.voucher_guid, 120),
          voucher_date: str(r?.voucher_date, 10),
          voucher_type: str(r?.voucher_type, 100),
          voucher_no: str(r?.voucher_no, 200),
          ledger_name: str(r?.ledger_name, 300),
          bill_name: str(r?.bill_name, 300),
          ref_type: str(r?.ref_type, 30),
          amount: Math.round(Number(r?.amount) * 100) / 100,
          credit_days: Number.isInteger(r?.credit_days) && r.credit_days >= 0 && r.credit_days <= 3650 ? r.credit_days : null,
        };
        if (!allowed.has(row.voucher_guid) || !row.ledger_name || !row.bill_name) continue;
        if (!/^\d{4}-\d{2}-\d{2}$/.test(row.voucher_date) || !REF_TYPES.has(row.ref_type)) continue;
        if (!Number.isFinite(row.amount) || row.amount === 0) continue;
        const key = `${row.voucher_guid}\u0001${row.ledger_name}\u0001${row.bill_name}\u0001${row.ref_type}`;
        if (seen.has(key)) continue;
        seen.add(key);
        rows.push(row);
      }
      await tx(async (q) => {
        await q.query(
          `DELETE FROM bill_settlements WHERE admin_id = $1 AND company_guid = $2 AND voucher_guid = ANY($3::text[])`,
          [s.adminId, s.company, guids]
        );
        if (rows.length) {
          await q.query(
            `INSERT INTO bill_settlements
               (admin_id, company_guid, voucher_guid, voucher_date, voucher_type, voucher_no,
                ledger_name, bill_name, ref_type, amount, credit_days)
             SELECT $1, $2, x.voucher_guid, x.voucher_date::date, x.voucher_type, x.voucher_no,
                    x.ledger_name, x.bill_name, x.ref_type, x.amount, x.credit_days
               FROM jsonb_to_recordset($3::jsonb) AS x(
                    voucher_guid text, voucher_date text, voucher_type text, voucher_no text,
                    ledger_name text, bill_name text, ref_type text, amount numeric, credit_days int)`,
            [s.adminId, s.company, JSON.stringify(rows)]
          );
        }
      });
      statsCache.delete(`${s.adminId}|${s.company}`);
      res.json({ success: true, vouchers: guids.length, rows: rows.length });
    })
  );

  /**
   * POST /api/cashflow/agent/bill-signs
   * {company_guid, bill_type: RECEIVABLE | PAYABLE, bills: [{ledger_name,
   *  bill_name, raw_amount}]} — Tally's signed amount of every current
   * bill of that kind (replaces the previous list).
   */
  router.post(
    "/api/cashflow/agent/bill-signs",
    auth,
    handle(async (req, res) => {
      const b = req.body || {};
      const s = await agentScope(req, b.company_guid);
      const type = String(b.bill_type || "").toUpperCase();
      if (type !== "RECEIVABLE" && type !== "PAYABLE") throw new HttpError(400, "bill_type must be RECEIVABLE or PAYABLE");
      const list = Array.isArray(b.bills) ? b.bills : [];
      if (list.length > 100000) throw new HttpError(413, "Too many bills in one upload");
      const byKey = new Map();
      for (const x of list) {
        const ledger = str(x?.ledger_name, 300);
        const bill = str(x?.bill_name, 300);
        const raw = Math.round(Number(x?.raw_amount) * 100) / 100;
        if (!ledger || !bill || !Number.isFinite(raw)) continue;
        byKey.set(`${ledger}\u0001${bill}`, { ledger_name: ledger, bill_name: bill, raw_amount: raw });
      }
      const rows = [...byKey.values()];
      await tx(async (q) => {
        await q.query(`DELETE FROM bill_balance_signs WHERE admin_id = $1 AND company_guid = $2 AND bill_type = $3`, [
          s.adminId,
          s.company,
          type,
        ]);
        if (rows.length) {
          await q.query(
            `INSERT INTO bill_balance_signs (admin_id, company_guid, bill_type, ledger_name, bill_name, raw_amount)
             SELECT $1, $2, $3, x.ledger_name, x.bill_name, x.raw_amount
               FROM jsonb_to_recordset($4::jsonb) AS x(ledger_name text, bill_name text, raw_amount numeric)`,
            [s.adminId, s.company, type, JSON.stringify(rows)]
          );
        }
      });
      res.json({ success: true, bills: rows.length });
    })
  );

  /* ------------------------------------------------ opening balance */
  /**
   * Cash + bank today: the newest date the financial figures cover, plus
   * the cash / bank vouchers after it. null when those figures are not
   * synced (the forecast is then shown without balances).
   */
  async function openingCash(s, today) {
    if (!financialData) return { amount: null, reason: "financial_unavailable" };
    const ctx = await financialData.context(s);
    if (!ctx.groups.length || !ctx.anchors.length) return { amount: null, reason: "financial_not_synced" };
    const dates = (await financialData.offeredDates(ctx)).filter((x) => x.as_on <= today);
    if (!dates.length) return { amount: null, reason: "financial_not_synced" };
    const basedOn = dates[0].as_on;
    const snap = await financialData.snapshotAt(s, ctx, basedOn);
    if (!snap) return { amount: null, reason: "financial_not_synced" };
    const cash = snap.ledgers.filter((l) => isCashLedger(l.parent, ctx.groups));
    const keys = [...new Set(cash.map((l) => nameKey(l.name)))];
    const mv = new Map(); // name key → net (Cr +)
    if (keys.length && basedOn < today) {
      const r = await db.query(
        `SELECT ${NAME_KEY("ve.ledger_name")} AS name, SUM(${SIGNED}) AS net
           FROM voucher_entries ve
          WHERE ve.admin_id = $1 AND ve.company_guid = $2 AND ${COUNTED}
            AND ve.voucher_date > $3::date AND ve.voucher_date <= $4::date
            AND ${NAME_KEY("ve.ledger_name")} = ANY($5::text[])
          GROUP BY 1`,
        [s.adminId, s.company, basedOn, today, keys]
      );
      for (const x of r.rows) mv.set(nameKey(x.name), (mv.get(nameKey(x.name)) || 0) + Number(x.net || 0));
    }
    // Tally sign: Dr (money held) is negative → balance = −(closing + later).
    const accounts = cash
      .map((l) => ({ name: l.name, group: l.parent, balance: Math.round(-(Number(l.closing) + (mv.get(nameKey(l.name)) || 0)) * 100) / 100 }))
      .filter((a) => Math.abs(a.balance) >= 0.01)
      .sort((a, b) => b.balance - a.balance);
    const amount = Math.round(accounts.reduce((a, x) => a + x.balance, 0) * 100) / 100;
    return { amount, based_on: basedOn, accounts };
  }

  /* ---------------------------------------------- payment delays */
  /**
   * Each party's payment delay from its vouchers (first in, first out),
   * for receivables and payables; kept 6 hours per company.
   */
  async function delayTables(s, today, refresh) {
    const key = `${s.adminId}|${s.company}`;
    const hit = statsCache.get(key);
    if (!refresh && hit && now().getTime() - hit.at < STATS_TTL_MS && hit.today === today) return hit.stats;

    const billRows = await db.query(
      `SELECT ledger_name, bill_name, due_date, bill_type
         FROM bills WHERE admin_id = $1 AND company_guid = $2`,
      [s.adminId, s.company]
    );
    const kindOf = new Map(); // party → 'recv' | 'pay'
    const dueOf = new Map(); // party@bill → due
    for (const b of billRows.rows) {
      const party = String(b.ledger_name || "").trim();
      if (!party) continue;
      const kind = String(b.bill_type || "").toUpperCase() === "PAYABLE" ? "pay" : "recv";
      if (!kindOf.has(party)) kindOf.set(party, kind);
      const due = iso(b.due_date);
      if (due) dueOf.set(`${party}@${String(b.bill_name || "").trim()}`, due);
    }
    const parties = [...kindOf.keys()];
    const empty = { recv: new Map(), pay: new Map(), company: { recv: null, pay: null }, credit: { recv: null, pay: null } };
    if (!parties.length) {
      statsCache.set(key, { at: now().getTime(), today, stats: empty });
      return empty;
    }
    // Voucher lines / masters are matched by name key, then named as the bill.
    const partyOfKey = new Map();
    for (const p of parties) if (!partyOfKey.has(nameKey(p))) partyOfKey.set(nameKey(p), p);
    const partyKeys = [...partyOfKey.keys()];
    const asParty = (name) => partyOfKey.get(nameKey(name)) ?? String(name);

    const from = addDays(today, -2 * WINDOW_DAYS);
    const [histRaw, beforeRaw, mastersRaw, allocs] = await Promise.all([
      db.query(
        `SELECT ${NAME_KEY("ve.ledger_name")} AS party, ve.voucher_guid AS guid,
                MIN(ve.voucher_date)::text AS date,
                MAX(COALESCE(ve.voucher_type, '')) AS type,
                SUM(${SIGNED}) AS net,
                MAX(v.reference_no) AS ref
           FROM voucher_entries ve
           LEFT JOIN vouchers v
             ON v.admin_id = ve.admin_id AND v.company_guid = ve.company_guid AND v.voucher_guid = ve.voucher_guid
          WHERE ve.admin_id = $1 AND ve.company_guid = $2 AND ${COUNTED}
            AND ${NAME_KEY("ve.ledger_name")} = ANY($3::text[])
            AND ve.voucher_date >= $4::date AND ve.voucher_date <= $5::date
          GROUP BY 1, ve.voucher_guid`,
        [s.adminId, s.company, partyKeys, from, today]
      ),
      db.query(
        `SELECT ${NAME_KEY("ve.ledger_name")} AS party, SUM(${SIGNED}) AS net
           FROM voucher_entries ve
          WHERE ve.admin_id = $1 AND ve.company_guid = $2 AND ${COUNTED}
            AND ${NAME_KEY("ve.ledger_name")} = ANY($3::text[]) AND ve.voucher_date < $4::date
          GROUP BY 1`,
        [s.adminId, s.company, partyKeys, from]
      ),
      db.query(
        `SELECT name, opening_balance FROM ledgers
          WHERE admin_id = $1 AND company_guid = $2 AND ${NAME_KEY("name")} = ANY($3::text[])`,
        [s.adminId, s.company, partyKeys]
      ),
      // Phase 2: Tally's bill-wise allocations (table missing → none).
      db
        .query(
          `SELECT ledger_name, bill_name, ref_type, voucher_type, voucher_date::text AS date, amount, credit_days
             FROM bill_settlements
            WHERE admin_id = $1 AND company_guid = $2 AND voucher_date >= $3::date`,
          [s.adminId, s.company, from]
        )
        .catch((e) => {
          if (e?.code !== "42P01") log.error("cashflow settlements:", e?.message || e);
          return { rows: [] };
        }),
    ]);
    const hist = { rows: histRaw.rows.map((x) => ({ ...x, party: asParty(x.party) })) };
    const before = { rows: beforeRaw.rows.map((x) => ({ ...x, party: asParty(x.party) })) };
    const masters = { rows: mastersRaw.rows.map((x) => ({ ...x, name: asParty(x.name) })) };

    // Balance before the window (Cr +): ledger opening + older vouchers.
    const startNet = new Map();
    for (const m of masters.rows) startNet.set(String(m.name), Number(m.opening_balance || 0));
    for (const b of before.rows) startNet.set(String(b.party), (startNet.get(String(b.party)) || 0) + Number(b.net || 0));

    // Invoices / payments per party, owed-amount sign per side.
    const byParty = new Map();
    const pairs = { recv: [], pay: [] };
    const partyPairs = new Map();
    for (const x of hist.rows) {
      const party = String(x.party);
      const kind = kindOf.get(party);
      if (!kind) continue;
      const net = Number(x.net || 0);
      const owed = kind === "recv" ? -net : net; // receivable: Dr raises it
      if (Math.abs(owed) < 0.005) continue;
      const type = String(x.type || "");
      const date = iso(x.date);
      const ev = owed > 0
        ? { date, amount: owed, side: "charge", due: dueOf.get(`${party}@${String(x.ref || "").trim()}`) || null }
        : { date, amount: -owed, side: "settle", cash: kind === "recv" ? /receipt/i.test(type) : /payment/i.test(type) };
      if (ev.side === "charge" && ev.due) {
        pairs[kind].push({ date, due: ev.due });
        if (!partyPairs.has(party)) partyPairs.set(party, []);
        partyPairs.get(party).push({ date, due: ev.due });
      }
      if (!byParty.has(party)) byParty.set(party, []);
      byParty.get(party).push(ev);
    }

    // Invoices with no matching bill: due = invoice date + usual credit days.
    const credit = { recv: creditDays(pairs.recv), pay: creditDays(pairs.pay) };
    const since = addDays(today, -WINDOW_DAYS);
    const out = { recv: new Map(), pay: new Map(), company: { recv: null, pay: null }, credit };
    const all = { recv: [], pay: [] };
    const creditOf = (party, kind) => creditDays(partyPairs.get(party) || []) ?? credit[kind] ?? null;
    // Exact payments from Tally's bill-wise receipts / payments (Phase 2).
    const exact = allocationPayments(
      allocs.rows.map((r) => ({ ...r, date: iso(r.date), amount: Number(r.amount) })),
      {
        kindOf: (party) => kindOf.get(party),
        dueOf: (party, bill) => dueOf.get(`${party}@${String(bill || "").trim()}`) || null,
        creditOf,
      }
    );
    for (const party of new Set([...byParty.keys(), ...exact.keys()])) {
      const kind = kindOf.get(party) || exact.get(party)?.kind;
      if (!kind) continue;
      const cd = creditOf(party, kind) ?? 0;
      const sure = (exact.get(party)?.payments || []).filter((p) => p.date >= since);
      let pays;
      let method;
      if (sure.length) {
        pays = sure;
        method = "alloc";
      } else {
        const events = byParty.get(party) || [];
        for (const e of events) if (e.side === "charge" && !e.due) e.due = addDays(e.date, cd);
        const net0 = startNet.get(party) || 0;
        const opening = kind === "recv" ? -net0 : net0;
        // Bill ids are per party: made unique for the company figures.
        pays = fifoPayments(events, { opening, openingDate: addDays(from, -1) }).map((p) => ({
          ...p,
          bill: `${party}#${p.bill}`,
        }));
        method = "fifo";
      }
      all[kind].push(...pays);
      const st = delayStats(pays, { since });
      if (st) out[kind].set(party, { ...st, credit_days: cd, method });
    }
    out.company.recv = delayStats(all.recv, { since });
    out.company.pay = delayStats(all.pay, { since });
    statsCache.set(key, { at: now().getTime(), today, stats: out });
    return out;
  }

  /* ---------------------------------------------------- forecast */
  async function forecastFor(req) {
    const s = await readScope(req);
    const today = todayIst(now());
    const weeks = Math.min(26, Math.max(1, Number.parseInt(req.query.weeks, 10) || 13));
    const mode = req.query.mode === "due" ? "due" : "adjusted";
    const includeDoubtful = req.query.doubtful === "1";
    const refresh = req.query.refresh === "1";

    const [bills, opening, delays, signs] = await Promise.all([
      db.query(
        `SELECT ledger_name, bill_name, due_date, pending_amount, bill_type
           FROM bills
          WHERE admin_id = $1 AND company_guid = $2 AND pending_amount > 0`,
        [s.adminId, s.company]
      ),
      openingCash(s, today).catch((e) => {
        log.error("cashflow opening balance:", e?.message || e);
        return { amount: null, reason: "financial_error" };
      }),
      delayTables(s, today, refresh),
      // Phase 2: Dr / Cr of each current bill (table missing → none).
      db
        .query(
          `SELECT bill_type, ledger_name, bill_name, raw_amount
             FROM bill_balance_signs WHERE admin_id = $1 AND company_guid = $2`,
          [s.adminId, s.company]
        )
        .catch((e) => {
          if (e?.code !== "42P01") log.error("cashflow bill signs:", e?.message || e);
          return { rows: [] };
        }),
    ]);
    const advances = advanceKeys(signs.rows);
    const receivables = [];
    const payables = [];
    for (const b of bills.rows) {
      const row = {
        party: String(b.ledger_name || "").trim(),
        bill: String(b.bill_name || "").trim(),
        due: iso(b.due_date),
        amount: Number(b.pending_amount || 0),
      };
      if (!row.party) continue;
      (String(b.bill_type || "").toUpperCase() === "PAYABLE" ? payables : receivables).push(row);
    }
    const delayOf = (party) => delayFor(delays.recv.get(party) || null, delays.company.recv);
    const f = buildForecast({
      today,
      weeks,
      opening: opening.amount,
      receivables,
      payables,
      delayOf,
      mode,
      includeDoubtful,
      isAdvance: (kind, party, bill) => advances.has(`${kind}|${party}@${bill}`),
    });
    return { s, today, f, opening, delays, delayOf, signsSynced: signs.rows.length > 0 };
  }

  /** Who owes the most in the forecast, with the delay used. */
  function topParties(f, delays, delayOf, n = 8) {
    const sums = new Map();
    for (const l of f.lines.inflows) sums.set(l.party, (sums.get(l.party) || 0) + l.amount);
    return [...sums.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, n)
      .map(([party, amount]) => {
        const st = delays.recv.get(party);
        const d = delayOf(party);
        return {
          party,
          amount: Math.round(amount * 100) / 100,
          delay_days: d.days,
          delay_source: d.source,
          history_bills: st?.bills || 0,
          on_time_pct: st?.on_time_pct ?? null,
          // 'alloc': from Tally's bill-wise receipts; 'fifo': estimated.
          method: st?.method ?? null,
        };
      });
  }

  router.get(
    "/api/cashflow/forecast",
    auth,
    handle(async (req, res) => {
      const { s, today, f, opening, delays, delayOf, signsSynced } = await forecastFor(req);
      const { lines, ...rest } = f;
      const methods = [...delays.recv.values()].map((x) => x.method);
      const exactParties = methods.filter((m) => m === "alloc").length;
      res.json({
        success: true,
        data: {
          company: s.companyName,
          as_on: today,
          generated_at: now().toISOString(),
          ...rest,
          opening,
          advances_checked: signsSynced,
          delays: {
            // 'alloc': all from bill-wise receipts, 'fifo': all estimated.
            method: !methods.length || exactParties === 0 ? "fifo" : exactParties === methods.length ? "alloc" : "mixed",
            parties_exact: exactParties,
            window_days: WINDOW_DAYS,
            company_median: delays.company.recv?.median ?? null,
            company_bills: delays.company.recv?.bills ?? 0,
            company_on_time_pct: delays.company.recv?.on_time_pct ?? null,
            parties_with_history: delays.recv.size,
          },
          top_receivables: topParties(f, delays, delayOf),
          counts: { receivable_bills: lines.inflows.length, payable_bills: lines.outflows.length },
        },
      });
    })
  );

  router.get(
    "/api/cashflow/week",
    auth,
    handle(async (req, res) => {
      const start = String(req.query.start || "");
      if (!/^\d{4}-\d{2}-\d{2}$/.test(start) || Number.isNaN(dayNum(start))) {
        throw new HttpError(400, "start must be a YYYY-MM-DD date");
      }
      const { s, f } = await forecastFor(req);
      const i = f.weeks.findIndex((w) => w.start === start);
      if (i < 0) throw new HttpError(404, "That week is not in the forecast.", "no_week");
      const w = f.weeks[i];
      res.json({
        success: true,
        data: {
          company: s.companyName,
          ...w,
          inflows: f.lines.inflows.filter((l) => l.week === i).map(({ week, ...l }) => l),
          outflows: f.lines.outflows.filter((l) => l.week === i).map(({ week, ...l }) => l),
        },
      });
    })
  );

  return router;
}
