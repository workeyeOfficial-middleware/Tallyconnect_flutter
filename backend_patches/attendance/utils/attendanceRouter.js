/* =========================================================
   SALES TEAM ATTENDANCE — routes (factory; dependencies passed in)

   Team member (every team login of the account; not the admin):
     GET  /api/attendance/me                    may check in? today's sessions
     POST /api/attendance/check-in              {note?, idempotency_key?}
     POST /api/attendance/check-out             {note?}
     POST /api/attendance/ping                  the app is open (last seen)
     GET  /api/attendance/me/history?from=&to=  own days and sessions
   Account admin:
     GET  /api/attendance/team?date=            every member's status that day
     GET  /api/attendance/team/:userId/history?from=&to=

   Every query is limited to the login's own account (admin_id from the
   sign-in token, never from the request). Check-ins record the account's
   ACTIVE company; the admin views see that company. Times are the server's
   clock; days are India (IST) dates. A session left open past its day is
   closed at 23:59 IST (closed_by 'auto') — by the cron job and before any
   request of that account, so it never depends on the cron alone.
========================================================= */
import express from "express";
import {
  cleanKey,
  cleanNote,
  dayStatus,
  historyDays,
  historyRange,
  isIsoDate,
  istDate,
  sessionOut,
  statusCounts,
} from "./attendanceCore.js";

class HttpError extends Error {
  constructor(status, message, code) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

const COLS = `id, admin_id, company_guid, user_id, work_date::text AS work_date, check_in_at,
  check_out_at, last_seen_at, in_note, out_note, closed_by, idempotency_key`;

const ORDER = { active: 0, idle: 1, checked_out: 2, absent: 3 };

/**
 * Closes sessions still open from an earlier India day at 23:59 IST of
 * their own day (only [adminId]'s when given). Returns how many.
 */
export async function closeForgotten(db, now = new Date(), adminId = null) {
  const r = await db.query(
    `UPDATE attendance_sessions
        SET check_out_at = GREATEST(check_in_at, (work_date::timestamp + INTERVAL '23 hours 59 minutes') AT TIME ZONE 'Asia/Kolkata'),
            closed_by = 'auto'
      WHERE check_out_at IS NULL AND work_date < $1::date${adminId === null ? "" : " AND admin_id = $2"}`,
    adminId === null ? [istDate(now)] : [istDate(now), adminId]
  );
  return r.rowCount || 0;
}

export function createAttendanceRouter({ db, auth, log = console, now = () => new Date() }) {
  const router = express.Router();

  const handle = (fn) => async (req, res) => {
    try {
      await fn(req, res);
    } catch (err) {
      if (err instanceof HttpError) {
        return res.status(err.status).json({
          success: false,
          message: err.message,
          ...(err.code ? { code: err.code } : {}),
        });
      }
      log.error("attendance error:", err?.message || err);
      if (!res.headersSent) res.status(500).json({ success: false, message: "Server error" });
    }
  };

  const adminIdOf = (u) => u?.adminId ?? (u?.role === "ADMIN" ? u?.id : null);

  /** The signed-in person, checked against the database (still in this account). */
  async function personOf(req) {
    const u = req.user || {};
    if (!u.id) throw new HttpError(401, "Unauthorized");
    const adminId = adminIdOf(u);
    if (!adminId) throw new HttpError(403, "Access denied", "forbidden");
    const r = await db.query(
      `SELECT u.id, u.username, u.email, u.role
         FROM users u
        WHERE u.id = $1 AND u.admin_id = $2`,
      [u.id, adminId]
    );
    const p = r.rows[0];
    if (!p) throw new HttpError(403, "Access denied", "forbidden");
    await closeForgotten(db, now(), adminId);
    // Every team member checks in and out; the admin sees the team.
    const isAdmin = p.role === "ADMIN";
    return { adminId, userId: Number(p.id), isAdmin, enabled: !isAdmin };
  }

  /** The account's active company. */
  async function companyOf(adminId) {
    const c = await db.query(
      `SELECT ac.company_guid, c.name AS company_name
         FROM active_company ac
         LEFT JOIN companies c ON c.company_guid = ac.company_guid AND c.admin_id = ac.admin_id
        WHERE ac.admin_id = $1 LIMIT 1`,
      [adminId]
    );
    const company = c.rows[0]?.company_guid;
    if (!company) throw new HttpError(409, "No company is selected for this account.", "no_company");
    return { company, companyName: c.rows[0]?.company_name || "" };
  }

  async function adminOf(req) {
    const p = await personOf(req);
    if (!p.isAdmin) throw new HttpError(403, "Admin access required", "forbidden");
    return p;
  }

  /** A team member (not the admin) of this account, or 404. */
  const memberId = (raw) => {
    const id = Number.parseInt(raw, 10);
    if (!Number.isInteger(id) || id <= 0 || String(id) !== raw) throw new HttpError(400, "Invalid user id");
    return id;
  };

  async function teamOf(adminId) {
    const r = await db.query(
      `SELECT u.id, u.username, u.email
         FROM users u
        WHERE u.admin_id = $1 AND u.role <> 'ADMIN'`,
      [adminId]
    );
    return r.rows.map((x) => ({ id: Number(x.id), username: x.username, email: x.email }));
  }

  const openOf = async (p) =>
    (
      await db.query(`SELECT ${COLS} FROM attendance_sessions WHERE admin_id = $1 AND user_id = $2 AND check_out_at IS NULL`, [
        p.adminId,
        p.userId,
      ])
    ).rows[0] || null;

  /* ------------------------------------------------------- member */
  router.get(
    "/api/attendance/me",
    auth,
    handle(async (req, res) => {
      const p = await personOf(req);
      const t = now();
      const today = istDate(t);
      const r = await db.query(
        `SELECT ${COLS} FROM attendance_sessions
          WHERE admin_id = $1 AND user_id = $2 AND work_date = $3::date ORDER BY check_in_at`,
        [p.adminId, p.userId, today]
      );
      const d = dayStatus(r.rows, t);
      const open = d.sessions.find((s) => s.open) || null;
      res.json({
        success: true,
        enabled: p.enabled,
        is_admin: p.isAdmin,
        server_time: t.toISOString(),
        date: today,
        status: d.status,
        open,
        sessions: d.sessions,
        total_minutes: d.total_minutes,
      });
    })
  );

  router.post(
    "/api/attendance/check-in",
    auth,
    handle(async (req, res) => {
      const p = await personOf(req);
      if (!p.enabled) {
        throw new HttpError(403, "Check-in is for team members; the admin sees the team.", "not_on_team");
      }
      const note = cleanNote(req.body?.note);
      if (!note.ok) throw new HttpError(400, note.message);
      const key = cleanKey(req.body?.idempotency_key);
      if (!key.ok) throw new HttpError(400, key.message);
      const replay = async () => {
        if (!key.value) return null;
        const r = await db.query(
          `SELECT ${COLS} FROM attendance_sessions WHERE user_id = $1 AND idempotency_key = $2`,
          [p.userId, key.value]
        );
        return r.rows[0] || null;
      };
      const t = now();
      const again = await replay();
      if (again) return res.json({ success: true, replayed: true, session: sessionOut(again, t) });
      const open = await openOf(p);
      if (open) throw new HttpError(409, "You are already checked in.", "already_checked_in");
      const { company } = await companyOf(p.adminId);
      try {
        const r = await db.query(
          `INSERT INTO attendance_sessions
             (admin_id, company_guid, user_id, work_date, check_in_at, last_seen_at, in_note, idempotency_key)
           VALUES ($1, $2, $3, $4::date, $5, $5, $6, $7)
           RETURNING ${COLS}`,
          [p.adminId, company, p.userId, istDate(t), t, note.value, key.value]
        );
        res.status(201).json({ success: true, session: sessionOut(r.rows[0], t) });
      } catch (err) {
        if (err?.code !== "23505") throw err;
        // Two taps at once: the first one won.
        const won = await replay();
        if (won) return res.json({ success: true, replayed: true, session: sessionOut(won, t) });
        throw new HttpError(409, "You are already checked in.", "already_checked_in");
      }
    })
  );

  router.post(
    "/api/attendance/check-out",
    auth,
    handle(async (req, res) => {
      const p = await personOf(req);
      if (p.isAdmin) throw new HttpError(403, "Only sales team members check in and out.", "not_on_team");
      const note = cleanNote(req.body?.note);
      if (!note.ok) throw new HttpError(400, note.message);
      const t = now();
      const r = await db.query(
        `UPDATE attendance_sessions
            SET check_out_at = $3, last_seen_at = $3, out_note = $4, closed_by = 'user'
          WHERE admin_id = $1 AND user_id = $2 AND check_out_at IS NULL
          RETURNING ${COLS}`,
        [p.adminId, p.userId, t, note.value]
      );
      if (!r.rows[0]) throw new HttpError(409, "You are not checked in.", "not_checked_in");
      res.json({ success: true, session: sessionOut(r.rows[0], t) });
    })
  );

  router.post(
    "/api/attendance/ping",
    auth,
    handle(async (req, res) => {
      const p = await personOf(req);
      const r = await db.query(
        `UPDATE attendance_sessions SET last_seen_at = $3
          WHERE admin_id = $1 AND user_id = $2 AND check_out_at IS NULL RETURNING id`,
        [p.adminId, p.userId, now()]
      );
      res.json({ success: true, open: (r.rowCount || r.rows.length) > 0 });
    })
  );

  router.get(
    "/api/attendance/me/history",
    auth,
    handle(async (req, res) => {
      const p = await personOf(req);
      const t = now();
      const range = historyRange(req.query, istDate(t));
      if (!range.ok) throw new HttpError(400, range.message);
      const r = await db.query(
        `SELECT ${COLS} FROM attendance_sessions
          WHERE admin_id = $1 AND user_id = $2 AND work_date BETWEEN $3::date AND $4::date ORDER BY check_in_at`,
        [p.adminId, p.userId, range.from, range.to]
      );
      res.json({ success: true, from: range.from, to: range.to, days: historyDays(r.rows, t) });
    })
  );

  /* -------------------------------------------------------- admin */
  router.get(
    "/api/attendance/team",
    auth,
    handle(async (req, res) => {
      const p = await adminOf(req);
      const t = now();
      const date = req.query.date === undefined || req.query.date === "" ? istDate(t) : String(req.query.date);
      if (!isIsoDate(date)) throw new HttpError(400, "Dates must be YYYY-MM-DD");
      const { company, companyName } = await companyOf(p.adminId);
      const [team, ses] = await Promise.all([
        teamOf(p.adminId),
        db.query(
          `SELECT ${COLS} FROM attendance_sessions
            WHERE admin_id = $1 AND company_guid = $2 AND work_date = $3::date ORDER BY check_in_at`,
          [p.adminId, company, date]
        ),
      ]);
      const byUser = new Map();
      for (const s of ses.rows) {
        const k = Number(s.user_id);
        if (!byUser.has(k)) byUser.set(k, []);
        byUser.get(k).push(s);
      }
      // Every team member of the account.
      const members = team
        .map((m) => ({ user_id: m.id, username: m.username, email: m.email, ...dayStatus(byUser.get(m.id) || [], t) }))
        .sort((a, b) => ORDER[a.status] - ORDER[b.status] || String(a.username).localeCompare(String(b.username)));
      res.json({ success: true, date, company: companyName, counts: statusCounts(members), members });
    })
  );

  router.get(
    "/api/attendance/team/:userId/history",
    auth,
    handle(async (req, res) => {
      const p = await adminOf(req);
      const userId = memberId(req.params.userId);
      const m = (await teamOf(p.adminId)).find((x) => x.id === userId);
      if (!m) throw new HttpError(404, "Team member not found");
      const t = now();
      const range = historyRange(req.query, istDate(t));
      if (!range.ok) throw new HttpError(400, range.message);
      const { company, companyName } = await companyOf(p.adminId);
      const r = await db.query(
        `SELECT ${COLS} FROM attendance_sessions
          WHERE admin_id = $1 AND company_guid = $2 AND user_id = $3 AND work_date BETWEEN $4::date AND $5::date
          ORDER BY check_in_at`,
        [p.adminId, company, userId, range.from, range.to]
      );
      res.json({
        success: true,
        member: { user_id: m.id, username: m.username, email: m.email },
        company: companyName,
        from: range.from,
        to: range.to,
        days: historyDays(r.rows, t),
      });
    })
  );

  return router;
}
