/* =========================================================
   MULTI-COMPANY SYNC — selection, per-company lock and progress
   (factory; dependencies passed in). Mounted under /company.

   GET  /company/agent-config        this account's companies: name,
                                      enabled, order, sync start (+ ?limit=1:
                                      the plan's company limit); the Agent
                                      reads it before every sync loop
   PUT  /company/selection           {companies:[{company_guid, enabled,
                                      sync_order?}]} — admin only; the
                                      plan's company limit counts ENABLED
                                      companies; a company is never deleted
                                      (that would cascade to its data)
   POST /company/sync-lock           {company_guid, agent_id, action:
                                      acquire|renew|release, ttl_sec?}
                                      one Agent per account + company at a
                                      time; an expired lock can be taken over
   POST /company/sync-progress       {company_guid, state, step?, percent?,
                                      error?, agent_id?} — per-company status
   GET  /company/sync-status         every company's status (app / Agent UI)

   Everything is scoped to the login's account (admin_id).
========================================================= */
import express from "express";

export const STATES = ["idle", "syncing", "synced", "error", "not_open", "waiting", "locked"];
const GUID_RE = /^[A-Za-z0-9._:{}-]{1,100}$/;
const AGENT_RE = /^[A-Za-z0-9._:-]{4,100}$/;
const STALE_MS = 5 * 60 * 1000; // "syncing" with no news for 5 min → stalled

class HttpError extends Error {
  constructor(status, message, code, extra) {
    super(message);
    this.status = status;
    this.code = code;
    this.extra = extra;
  }
}

/**
 * @param {object} deps
 * @param {{query: Function}} deps.db
 * @param {Function} deps.auth
 * @param {(email: string) => Promise<number|null>} [deps.getCompanyLimit]  plan's company limit (null: none)
 * @param {(user: object, added: number) => Promise<void>} [deps.onCompaniesAdded]  licence heartbeat
 * @param {object} [deps.log]
 * @param {() => Date} [deps.now]
 */
export function createCompanySyncRouter({
  db,
  auth,
  getCompanyLimit = async () => null,
  onCompaniesAdded = async () => {},
  log = console,
  now = () => new Date(),
}) {
  const router = express.Router();

  const handle = (fn) => async (req, res) => {
    try {
      await fn(req, res);
    } catch (err) {
      if (err instanceof HttpError) {
        return res.status(err.status).json({ success: false, message: err.message, ...(err.code ? { code: err.code } : {}), ...(err.extra || {}) });
      }
      log.error("company sync error:", err?.message || err);
      if (!res.headersSent) res.status(500).json({ success: false, message: "Server error" });
    }
  };

  function account(req, { admin = false } = {}) {
    const u = req.user || {};
    if (!u.id) throw new HttpError(401, "Unauthorized");
    const adminId = u.adminId ?? (u.role === "ADMIN" ? u.id : null);
    if (!adminId) throw new HttpError(403, "Access denied");
    if (admin && u.role !== "ADMIN") throw new HttpError(403, "Admin only", "admin_only");
    return { adminId, user: u };
  }

  async function ownCompany(adminId, guid) {
    if (typeof guid !== "string" || !GUID_RE.test(guid)) throw new HttpError(400, "company_guid required");
    const r = await db.query(`SELECT 1 FROM companies WHERE admin_id = $1 AND company_guid = $2`, [adminId, guid]);
    if (!r.rowCount) throw new HttpError(403, "Company not found in this account", "no_company");
  }

  /** This account's companies with selection state, Agent order first. */
  async function companiesOf(adminId) {
    const r = await db.query(
      `SELECT c.company_guid, c.name,
              (sc.company_guid IS NOT NULL) AS selected,
              COALESCE(sc.enabled, FALSE) AS enabled,
              sc.sync_order, sc.starting_from, sc.updated_at
         FROM companies c
         LEFT JOIN selected_companies sc ON sc.admin_id = c.admin_id AND sc.company_guid = c.company_guid
        WHERE c.admin_id = $1
        ORDER BY (sc.company_guid IS NULL), sc.sync_order NULLS LAST, sc.selected_at ASC NULLS LAST, c.name ASC`,
      [adminId]
    );
    return r.rows.map((x) => ({
      company_guid: x.company_guid,
      name: x.name,
      selected: !!x.selected,
      enabled: !!x.enabled,
      sync_order: x.sync_order == null ? null : Number(x.sync_order),
      starting_from: x.starting_from || null,
      updated_at: x.updated_at || null,
    }));
  }

  router.get(
    "/agent-config",
    auth,
    handle(async (req, res) => {
      const { adminId, user } = account(req);
      const [companies, active] = await Promise.all([
        companiesOf(adminId),
        db.query(`SELECT company_guid FROM active_company WHERE admin_id = $1`, [adminId]),
      ]);
      const version = companies
        .map((c) => `${c.company_guid}:${c.enabled ? 1 : 0}:${c.sync_order ?? ""}:${c.starting_from ?? ""}`)
        .join("|");
      res.json({
        success: true,
        companies,
        active_company_guid: active.rows[0]?.company_guid || null,
        version,
        ...(req.query.limit === "1" ? { company_limit: await getCompanyLimit(user.email) } : {}),
      });
    })
  );

  router.put(
    "/selection",
    auth,
    handle(async (req, res) => {
      const { adminId, user } = account(req, { admin: true });
      const list = Array.isArray(req.body?.companies) ? req.body.companies : null;
      if (!list || !list.length || list.length > 200) throw new HttpError(400, "companies must be a list (1–200)");
      const current = await companiesOf(adminId);
      const byGuid = new Map(current.map((c) => [c.company_guid, c]));
      const changes = new Map();
      for (const x of list) {
        const g = x?.company_guid;
        if (typeof g !== "string" || !byGuid.has(g)) throw new HttpError(400, `Unknown company: ${String(g).slice(0, 60)}`, "unknown_company");
        if (typeof x.enabled !== "boolean") throw new HttpError(400, "enabled must be true or false");
        const order = x.sync_order == null ? null : Number(x.sync_order);
        if (order !== null && (!Number.isInteger(order) || order < 0 || order > 10000)) throw new HttpError(400, "sync_order must be a whole number");
        changes.set(g, { enabled: x.enabled, order });
      }
      // The plan's limit counts the companies enabled after this change.
      const enabledAfter = current.filter((c) => (changes.has(c.company_guid) ? changes.get(c.company_guid).enabled : c.enabled)).length;
      const added = [...changes].filter(([g, c]) => c.enabled && !byGuid.get(g).selected).length;
      const turningOn = [...changes].some(([g, c]) => c.enabled && !byGuid.get(g).enabled);
      if (turningOn) {
        const limit = await getCompanyLimit(user.email);
        if (limit !== null && limit !== undefined && enabledAfter > Number(limit)) {
          throw new HttpError(
            403,
            `Your plan allows ${limit} ${Number(limit) === 1 ? "company" : "companies"}. Turn another company off first, or upgrade your plan.`,
            "company_limit",
            { company_limit: Number(limit), enabled: enabledAfter }
          );
        }
      }
      for (const [g, c] of changes) {
        await db.query(
          `INSERT INTO selected_companies (admin_id, company_guid, enabled, sync_order, updated_at)
           VALUES ($1, $2, $3, $4, NOW())
           ON CONFLICT (admin_id, company_guid)
           DO UPDATE SET enabled = EXCLUDED.enabled,
                         sync_order = COALESCE(EXCLUDED.sync_order, selected_companies.sync_order),
                         updated_at = NOW()`,
          [adminId, g, c.enabled, c.order]
        );
      }
      // The app shows one company: keep it on an enabled one.
      const after = await companiesOf(adminId);
      const firstOn = after.find((c) => c.enabled);
      const act = await db.query(`SELECT company_guid FROM active_company WHERE admin_id = $1`, [adminId]);
      const activeGuid = act.rows[0]?.company_guid || null;
      if (firstOn && (!activeGuid || !after.some((c) => c.enabled && c.company_guid === activeGuid))) {
        await db.query(
          `INSERT INTO active_company (admin_id, company_guid) VALUES ($1, $2)
           ON CONFLICT (admin_id) DO UPDATE SET company_guid = EXCLUDED.company_guid, updated_at = NOW()`,
          [adminId, firstOn.company_guid]
        );
      }
      if (added > 0) {
        await onCompaniesAdded(user, added).catch((e) => log.error("licence heartbeat failed:", e?.message || e));
      }
      res.json({ success: true, companies: after });
    })
  );

  router.post(
    "/sync-lock",
    auth,
    handle(async (req, res) => {
      const { adminId } = account(req);
      const { company_guid: g, agent_id: agent, action } = req.body || {};
      if (typeof agent !== "string" || !AGENT_RE.test(agent)) throw new HttpError(400, "agent_id required");
      await ownCompany(adminId, g);
      const ttl = Math.min(600, Math.max(30, Number.parseInt(req.body?.ttl_sec ?? 180, 10) || 180));
      const expires = new Date(now().getTime() + ttl * 1000);
      if (action === "release") {
        await db.query(`DELETE FROM company_sync_locks WHERE admin_id = $1 AND company_guid = $2 AND agent_id = $3`, [adminId, g, agent]);
        return res.json({ success: true, released: true });
      }
      if (action === "renew") {
        const r = await db.query(
          `UPDATE company_sync_locks SET expires_at = $4
            WHERE admin_id = $1 AND company_guid = $2 AND agent_id = $3 RETURNING expires_at`,
          [adminId, g, agent, expires]
        );
        if (!r.rowCount) throw new HttpError(409, "The lock is no longer held by this Agent", "lock_lost");
        return res.json({ success: true, expires_at: r.rows[0].expires_at });
      }
      if (action !== "acquire") throw new HttpError(400, "action must be acquire, renew or release");
      // Take it when free, already ours, or expired; else tell who holds it.
      const r = await db.query(
        `INSERT INTO company_sync_locks (admin_id, company_guid, agent_id, acquired_at, expires_at)
         VALUES ($1, $2, $3, $5, $4)
         ON CONFLICT (admin_id, company_guid)
         DO UPDATE SET agent_id = EXCLUDED.agent_id, acquired_at = EXCLUDED.acquired_at, expires_at = EXCLUDED.expires_at
          WHERE company_sync_locks.agent_id = EXCLUDED.agent_id OR company_sync_locks.expires_at < $5
         RETURNING agent_id, expires_at`,
        [adminId, g, agent, expires, now()]
      );
      if (!r.rowCount) {
        const held = await db.query(`SELECT agent_id, expires_at FROM company_sync_locks WHERE admin_id = $1 AND company_guid = $2`, [adminId, g]);
        throw new HttpError(409, "Another Agent is syncing this company", "locked", {
          held_by: held.rows[0]?.agent_id || null,
          expires_at: held.rows[0]?.expires_at || null,
        });
      }
      res.json({ success: true, acquired: true, expires_at: r.rows[0].expires_at });
    })
  );

  router.post(
    "/sync-progress",
    auth,
    handle(async (req, res) => {
      const { adminId } = account(req);
      const b = req.body || {};
      await ownCompany(adminId, b.company_guid);
      if (!STATES.includes(b.state)) throw new HttpError(400, `state must be one of ${STATES.join(", ")}`);
      const pct = b.percent == null ? null : Math.max(0, Math.min(100, Math.round(Number(b.percent))));
      if (b.percent != null && !Number.isFinite(Number(b.percent))) throw new HttpError(400, "percent must be a number");
      await db.query(
        `INSERT INTO agent_status (admin_id, company_guid, sync_in_progress, state, step, percent, last_error, agent_id, progress_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())
         ON CONFLICT (admin_id, company_guid)
         DO UPDATE SET sync_in_progress = EXCLUDED.sync_in_progress, state = EXCLUDED.state, step = EXCLUDED.step,
                       percent = EXCLUDED.percent, last_error = EXCLUDED.last_error,
                       agent_id = COALESCE(EXCLUDED.agent_id, agent_status.agent_id), progress_at = NOW()`,
        [
          adminId,
          b.company_guid,
          b.state === "syncing",
          b.state,
          b.step == null ? null : String(b.step).slice(0, 60),
          pct,
          b.state === "error" ? String(b.error || "Sync failed").slice(0, 500) : null,
          typeof b.agent_id === "string" && AGENT_RE.test(b.agent_id) ? b.agent_id : null,
        ]
      );
      res.json({ success: true });
    })
  );

  router.get(
    "/sync-status",
    auth,
    handle(async (req, res) => {
      const { adminId } = account(req);
      const r = await db.query(
        `SELECT c.company_guid, c.name, COALESCE(sc.enabled, FALSE) AS enabled,
                s.state, s.step, s.percent, s.last_error, s.last_sync_at, s.progress_at, s.sync_in_progress
           FROM companies c
           LEFT JOIN selected_companies sc ON sc.admin_id = c.admin_id AND sc.company_guid = c.company_guid
           LEFT JOIN agent_status s ON s.admin_id = c.admin_id AND s.company_guid = c.company_guid
          WHERE c.admin_id = $1
          ORDER BY (sc.company_guid IS NULL), sc.sync_order NULLS LAST, c.name ASC`,
        [adminId]
      );
      const t = now().getTime();
      res.json({
        success: true,
        companies: r.rows.map((x) => {
          let state = x.state || (x.last_sync_at ? "synced" : "idle");
          const at = x.progress_at ? new Date(x.progress_at).getTime() : 0;
          if (state === "syncing" && t - at > STALE_MS) state = "stalled";
          return {
            company_guid: x.company_guid,
            name: x.name,
            enabled: !!x.enabled,
            state,
            step: x.step || null,
            percent: x.percent == null ? null : Number(x.percent),
            last_error: x.last_error || null,
            last_sync_at: x.last_sync_at || null,
            progress_at: x.progress_at || null,
          };
        }),
      });
    })
  );

  return router;
}
