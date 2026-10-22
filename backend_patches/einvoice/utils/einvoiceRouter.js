/* =========================================================
   E-INVOICE (Basic) — routes (factory; dependencies passed in)

   Agent (the account admin's login), beside the normal voucher sync — the
   voucher sync itself is not touched:
     POST /api/einvoice/agent/sync   {company_guid, rows: [...]}
          each sales / purchase invoice's e-invoice details as Tally saved
          them (IRN, ack no / date, signed QR, e-way bill); upserted by GUID.

   App (the account admin, and team members allowed to see financial
   reports — same rule as /api/financial/*; the active company):
     GET  /api/einvoice/list?from=&to=&status=
          counts and the invoices (status: all | pending | done | cancelled |
          not_needed | alerts)
     GET  /api/einvoice/voucher/:guid
          one invoice with its signed QR (invoice screen / PDF)

   The e-invoice itself is created in TallyPrime; this only shows and
   tracks it. Vouchers deleted in Tally (inactive) are left out.
========================================================= */
import express from "express";
import { MAX_ROWS, STATUSES, cleanRow, listRange, rowOut, statusOf, summarize, alertsOf } from "./einvoiceCore.js";

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

const COLS = `e.voucher_guid, e.voucher_date::text AS voucher_date, e.voucher_type, e.voucher_no, e.party_name,
  e.party_gstin, e.registration_type, e.company_gstin, e.place_of_supply, e.amount, e.is_sale, e.is_optional,
  e.is_cancelled, e.gst_applicable, e.irn, e.ack_no, e.ack_date::text AS ack_date, e.irn_cancelled,
  e.eway_applicable, e.eway`;
/** Vouchers deleted in Tally are inactive in `vouchers`: left out. */
const FROM = `einvoices e
  LEFT JOIN vouchers v
    ON v.admin_id = e.admin_id AND v.company_guid = e.company_guid AND v.voucher_guid = e.voucher_guid`;
const LIVE = `COALESCE(v.is_active, TRUE) = TRUE`;

export function createEinvoiceRouter({ db, auth, log = console, now = () => new Date() }) {
  const router = express.Router();

  const handle = (fn) => async (req, res) => {
    try {
      await fn(req, res);
    } catch (err) {
      if (err instanceof HttpError) {
        return res.status(err.status).json({ success: false, message: err.message, ...(err.code ? { code: err.code } : {}) });
      }
      if (err?.code === "42P01") {
        log.error("einvoice: table missing — run sql/2026-10-21_einvoice.sql:", err?.message || err);
        return res.status(503).json({
          success: false,
          code: "not_set_up",
          message: "E-invoice tracking is not set up on the server yet.",
        });
      }
      log.error("einvoice error:", err?.message || err);
      if (!res.headersSent) res.status(500).json({ success: false, message: "Server error" });
    }
  };

  const adminIdOf = (u) => u?.adminId ?? (u?.role === "ADMIN" ? u?.id : null);

  /** Admin, or a team member allowed to see financial reports; the active company. */
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

  /* --------------------------------------------------------- agent */
  router.post(
    "/api/einvoice/agent/sync",
    auth,
    handle(async (req, res) => {
      const b = req.body || {};
      const s = await agentScope(req, b.company_guid);
      const raw = Array.isArray(b.rows) ? b.rows : [];
      if (raw.length > MAX_ROWS) throw new HttpError(413, `At most ${MAX_ROWS} invoices per upload`);
      // One row per voucher (the last one sent wins).
      const byGuid = new Map();
      let skipped = 0;
      for (const x of raw) {
        const r = cleanRow(x);
        if (r) byGuid.set(r.voucher_guid, r);
        else skipped += 1;
      }
      const rows = [...byGuid.values()];
      if (rows.length) {
        await db.query(
          `INSERT INTO einvoices (admin_id, company_guid, voucher_guid, voucher_date, voucher_type, voucher_no,
                                 party_name, party_gstin, registration_type, company_gstin, place_of_supply, amount,
                                 is_sale, is_optional, is_cancelled, gst_applicable, irn, ack_no, ack_date, signed_qr,
                                 irn_cancelled, eway_applicable, eway, synced_at)
           SELECT $1, $2, x.voucher_guid, x.voucher_date::date, x.voucher_type, x.voucher_no,
                  x.party_name, x.party_gstin, x.registration_type, x.company_gstin, x.place_of_supply, x.amount,
                  x.is_sale, x.is_optional, x.is_cancelled, x.gst_applicable, x.irn, x.ack_no,
                  NULLIF(x.ack_date, '')::date, x.signed_qr, x.irn_cancelled, x.eway_applicable, x.eway, NOW()
             FROM jsonb_to_recordset($3::jsonb) AS x(
                  voucher_guid text, voucher_date text, voucher_type text, voucher_no text, party_name text,
                  party_gstin text, registration_type text, company_gstin text, place_of_supply text, amount numeric,
                  is_sale boolean, is_optional boolean, is_cancelled boolean, gst_applicable boolean, irn text,
                  ack_no text, ack_date text, signed_qr text, irn_cancelled boolean, eway_applicable boolean,
                  eway jsonb)
           ON CONFLICT (admin_id, company_guid, voucher_guid) DO UPDATE SET
             voucher_date = EXCLUDED.voucher_date, voucher_type = EXCLUDED.voucher_type,
             voucher_no = EXCLUDED.voucher_no, party_name = EXCLUDED.party_name,
             party_gstin = EXCLUDED.party_gstin, registration_type = EXCLUDED.registration_type,
             company_gstin = EXCLUDED.company_gstin, place_of_supply = EXCLUDED.place_of_supply,
             amount = EXCLUDED.amount, is_sale = EXCLUDED.is_sale, is_optional = EXCLUDED.is_optional,
             is_cancelled = EXCLUDED.is_cancelled, gst_applicable = EXCLUDED.gst_applicable,
             irn = EXCLUDED.irn, ack_no = EXCLUDED.ack_no, ack_date = EXCLUDED.ack_date,
             signed_qr = EXCLUDED.signed_qr, irn_cancelled = EXCLUDED.irn_cancelled,
             eway_applicable = EXCLUDED.eway_applicable, eway = EXCLUDED.eway, synced_at = NOW()`,
          [s.adminId, s.company, JSON.stringify(rows)]
        );
      }
      res.json({ success: true, saved: rows.length, skipped });
    })
  );

  /* ----------------------------------------------------------- app */
  router.get(
    "/api/einvoice/list",
    auth,
    handle(async (req, res) => {
      const s = await readScope(req);
      const today = todayIst(now());
      const range = listRange(req.query, today);
      if (!range.ok) throw new HttpError(400, range.message);
      const status = req.query.status ? String(req.query.status) : "all";
      if (!STATUSES.includes(status)) throw new HttpError(400, "Unknown status");
      const r = await db.query(
        `SELECT ${COLS} FROM ${FROM}
          WHERE e.admin_id = $1 AND e.company_guid = $2
            AND e.voucher_date BETWEEN $3::date AND $4::date AND ${LIVE}
          ORDER BY e.voucher_date DESC, e.voucher_no DESC`,
        [s.adminId, s.company, range.from, range.to]
      );
      const keep =
        status === "all"
          ? () => true
          : status === "alerts"
            ? (x) => alertsOf(x, today).length > 0
            : (x) => statusOf(x) === status;
      const list = r.rows.filter(keep);
      res.json({
        success: true,
        company: s.companyName,
        from: range.from,
        to: range.to,
        status,
        summary: summarize(r.rows, today),
        rows: list.slice(0, 500).map((x) => rowOut(x, today)),
        truncated: list.length > 500,
      });
    })
  );

  router.get(
    "/api/einvoice/voucher/:guid",
    auth,
    handle(async (req, res) => {
      const s = await readScope(req);
      const guid = String(req.params.guid || "").trim();
      if (!guid || guid.length > 120) throw new HttpError(400, "Invalid voucher");
      const r = await db.query(
        `SELECT ${COLS}, e.signed_qr FROM ${FROM}
          WHERE e.admin_id = $1 AND e.company_guid = $2 AND e.voucher_guid = $3 AND ${LIVE}`,
        [s.adminId, s.company, guid]
      );
      if (!r.rows[0]) throw new HttpError(404, "No e-invoice details for this voucher", "not_found");
      res.json({ success: true, invoice: rowOut(r.rows[0], todayIst(now()), true) });
    })
  );

  return router;
}
