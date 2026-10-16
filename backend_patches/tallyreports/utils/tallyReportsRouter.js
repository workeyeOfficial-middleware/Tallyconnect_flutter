/* =========================================================
   OFFICIAL TALLY REPORTS — routes (factory; database passed in)

   Agent (account admin's Agent):
     POST /api/tally-reports/agent/snapshot
          Tally's own figures fetched in small pieces (ledger balances,
          stock values, cash / bank months) → all four reports are built
          and stored for that period
     POST /api/tally-reports/agent/:report  (one ready-made report)
          {company_guid, period_from, period_to, rows, report_name,
           fetch_seconds, content_hash}  → replaces that period's figures
   App (admin, or team members allowed financial reports):
     GET  /api/tally-reports/periods             what is available
     GET  /api/tally-reports/:report?from=&to=   one report (default: the
                                                 newest period)
   :report = trial_balance | profit_loss | balance_sheet | cash_flow
   One table per report (sql/2026-10-18_tally_reports.sql). Everything is
   scoped to the account and the active company.
========================================================= */
import express from "express";

import { REPORTS, buildFromPieces, checksFor, validateSnapshot, validateUpload, withLedgers } from "./tallyReportsCore.js";

class HttpError extends Error {
  constructor(status, message, code) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

const iso = (d) => (d instanceof Date ? d.toISOString().slice(0, 10) : d ? String(d).slice(0, 10) : null);
const parse = (v) => (typeof v === "string" ? JSON.parse(v) : v);

/**
 * @param {object} deps
 * @param {{balanceSheet: Function, profitLoss: Function}} [deps.builders]
 *   from financialCore.js (loaded from ./financialCore.js when not given)
 */
export function createTallyReportsRouter({ db, auth, log = console, builders = null }) {
  const router = express.Router();
  let core = builders;
  async function reportBuilders() {
    if (!core) core = await import("./financialCore.js");
    return core;
  }

  const handle = (fn) => async (req, res) => {
    try {
      await fn(req, res);
    } catch (err) {
      if (err instanceof HttpError) {
        return res.status(err.status).json({ success: false, message: err.message, ...(err.code ? { code: err.code } : {}) });
      }
      if (err?.code === "42P01") {
        log.error("tally-reports: table missing — run sql/2026-10-18_tally_reports.sql:", err?.message || err);
        return res.status(503).json({
          success: false,
          code: "not_set_up",
          message: "Tally report tables are not set up on the server yet (run the SQL).",
        });
      }
      log.error("tally-reports error:", err?.message || err);
      if (!res.headersSent) res.status(500).json({ success: false, message: "Server error" });
    }
  };

  const adminIdOf = (u) => u?.adminId ?? (u?.role === "ADMIN" ? u?.id : null);
  const reportOf = (req) => {
    const r = String(req.params.report || "");
    if (!REPORTS[r]) throw new HttpError(404, "Unknown report", "unknown_report");
    return r;
  };

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

  /* ------------------------------------------------- agent: upload */
  /** One row per company + period; a new upload replaces it. */
  async function save(q, report, s, from, to, rows, meta) {
    await q.query(
      `INSERT INTO ${REPORTS[report].table}
         (admin_id, company_guid, period_from, period_to, rows, report_name, fetch_seconds, content_hash, fetched_at)
       VALUES ($1, $2, $3::date, $4::date, $5::jsonb, $6, $7, $8, NOW())
       ON CONFLICT (admin_id, company_guid, period_from, period_to) DO UPDATE SET
         rows = EXCLUDED.rows,
         report_name = EXCLUDED.report_name,
         fetch_seconds = EXCLUDED.fetch_seconds,
         content_hash = EXCLUDED.content_hash,
         fetched_at = NOW()`,
      [s.adminId, s.company, from, to, JSON.stringify(rows), meta.report_name, meta.fetch_seconds, meta.content_hash || null]
    );
  }

  /**
   * POST /api/tally-reports/agent/snapshot — the Agent's small pieces of
   * Tally's own figures for one period: {company_guid, period_from,
   * period_to, ledgers: [{name, parent, opening, closing}], stock:
   * {opening, closing} | null, cash_months: [{from, to, opening, closing}],
   * pieces, fetch_seconds}. The four reports are built from them with the
   * statements' rules and Tally's group tree.
   */
  router.post(
    "/api/tally-reports/agent/snapshot",
    auth,
    handle(async (req, res) => {
      const s = await agentScope(req, req.body?.company_guid);
      const v = validateSnapshot(req.body);
      if (v.error) throw new HttpError(400, v.error);
      const x = v.value;
      const groups = (
        await db
          .query(
            `SELECT name, parent, is_revenue, is_deemed_positive, affects_gross_profit
               FROM tally_groups WHERE admin_id = $1 AND company_guid = $2`,
            [s.adminId, s.company]
          )
          .catch(() => ({ rows: [] }))
      ).rows;
      let built;
      try {
        built = buildFromPieces(x, groups, await reportBuilders());
      } catch (e) {
        log.error("tally-reports build:", e?.message || e);
        built = buildFromPieces(x, [], { balanceSheet: null, profitLoss: null }); // Trial Balance / Cash Flow still
      }
      const meta = {
        report_name: `Tally figures (${x.pieces ?? "?"} pieces)`,
        fetch_seconds: x.fetch_seconds,
      };
      const saved = [];
      for (const report of ["trial_balance", "balance_sheet", "profit_loss", "cash_flow"]) {
        if (!built[report] || !built[report].length) continue;
        await save(db, report, s, x.from, x.to, built[report], meta);
        saved.push(report);
      }
      res.json({ success: true, saved, groups: groups.length });
    })
  );

  router.post(
    "/api/tally-reports/agent/:report",
    auth,
    handle(async (req, res) => {
      const report = reportOf(req);
      const s = await agentScope(req, req.body?.company_guid);
      const v = validateUpload(report, req.body);
      if (v.error) throw new HttpError(400, v.error);
      const x = v.value;
      // One row per company + period; a new fetch replaces the old one.
      await db.query(
        `INSERT INTO ${REPORTS[report].table}
           (admin_id, company_guid, period_from, period_to, rows, report_name, fetch_seconds, content_hash, fetched_at)
         VALUES ($1, $2, $3::date, $4::date, $5::jsonb, $6, $7, $8, NOW())
         ON CONFLICT (admin_id, company_guid, period_from, period_to) DO UPDATE SET
           rows = EXCLUDED.rows,
           report_name = EXCLUDED.report_name,
           fetch_seconds = EXCLUDED.fetch_seconds,
           content_hash = EXCLUDED.content_hash,
           fetched_at = NOW()`,
        [s.adminId, s.company, x.from, x.to, JSON.stringify(x.rows), x.report_name, x.fetch_seconds, x.content_hash]
      );
      res.json({ success: true, rows: x.rows.length });
    })
  );

  /* ---------------------------------------------- app: read */
  router.get(
    "/api/tally-reports/periods",
    auth,
    handle(async (req, res) => {
      const s = await readScope(req);
      const reports = {};
      for (const [key, meta] of Object.entries(REPORTS)) {
        const r = await db
          .query(
            `SELECT period_from::text AS period_from, period_to::text AS period_to, fetched_at
               FROM ${meta.table} WHERE admin_id = $1 AND company_guid = $2
              ORDER BY period_to DESC, period_from ASC`,
            [s.adminId, s.company]
          )
          .catch((e) => {
            if (e?.code === "42P01") return { rows: [], missing: true };
            throw e;
          });
        reports[key] = r.rows.map((x) => ({ from: iso(x.period_from), to: iso(x.period_to), fetched_at: x.fetched_at }));
      }
      res.json({ success: true, company: s.companyName, reports });
    })
  );

  router.get(
    "/api/tally-reports/:report",
    auth,
    handle(async (req, res) => {
      const report = reportOf(req);
      const s = await readScope(req);
      const table = REPORTS[report].table;
      const from = String(req.query.from || "");
      const to = String(req.query.to || "");
      const cols = `period_from::text AS period_from, period_to::text AS period_to, rows, report_name, fetch_seconds, fetched_at`;
      const r =
        from && to
          ? await db.query(
              `SELECT ${cols} FROM ${table} WHERE admin_id = $1 AND company_guid = $2 AND period_from = $3::date AND period_to = $4::date`,
              [s.adminId, s.company, from, to]
            )
          : await db.query(
              `SELECT ${cols} FROM ${table} WHERE admin_id = $1 AND company_guid = $2
                ORDER BY period_to DESC, period_from ASC LIMIT 1`,
              [s.adminId, s.company]
            );
      const row = r.rows[0];
      if (!row) {
        throw new HttpError(
          404,
          `No ${REPORTS[report].label} from Tally for this period yet. The TallyConnect Agent fetches one report at a time; check again later.`,
          "not_fetched"
        );
      }
      let rows = parse(row.rows) || [];
      if (report === "balance_sheet" || report === "profit_loss") {
        // Group drill-down: ledgers from the Trial Balance of the same period.
        const [tb, groups] = await Promise.all([
          db
            .query(
              `SELECT rows FROM tally_trial_balance
                WHERE admin_id = $1 AND company_guid = $2 AND period_from = $3::date AND period_to = $4::date`,
              [s.adminId, s.company, iso(row.period_from), iso(row.period_to)]
            )
            .catch(() => ({ rows: [] })),
          db
            .query(`SELECT name, parent FROM tally_groups WHERE admin_id = $1 AND company_guid = $2`, [s.adminId, s.company])
            .catch(() => ({ rows: [] })),
        ]);
        rows = withLedgers(rows, parse(tb.rows[0]?.rows) || [], groups.rows);
      }
      res.json({
        success: true,
        data: {
          report,
          label: REPORTS[report].label,
          company: s.companyName,
          period_from: iso(row.period_from),
          period_to: iso(row.period_to),
          fetched_at: row.fetched_at,
          fetch_seconds: row.fetch_seconds === null ? null : Number(row.fetch_seconds),
          report_name: row.report_name,
          source: "tally",
          rows,
          checks: checksFor(report, parse(row.rows) || []),
        },
      });
    })
  );

  return router;
}
