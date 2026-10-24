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
     GET  /api/attendance/summary?from=&to=     each member's days, hours, leave, absences
     GET  /api/attendance/settings              who checks in: positions, exempt list
     PUT  /api/attendance/settings              {exempt_positions: [..]}
     PUT  /api/attendance/members/:userId       {position?, rule?: auto|required|exempt}

   Who checks in: every team member, except those whose position is on the
   admin's exempt list (Manager, Director…) or whom the admin exempted one
   by one ("required" overrides an exempt position). Exempt members are
   not asked to check in and never count as absent.

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
import {
  POSITION_SUGGESTIONS,
  RULES,
  checkInRule,
  cleanExempt,
  cleanPosition,
  memberSummary,
} from "./attendanceRules.js";
import { settingsOut } from "./leaveCore.js";

class HttpError extends Error {
  constructor(status, message, code) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

const COLS = `id, admin_id, company_guid, user_id, work_date::text AS work_date, check_in_at,
  check_out_at, last_seen_at, in_note, out_note, closed_by, idempotency_key`;

const ORDER = { active: 0, idle: 1, checked_out: 2, absent: 3, exempt: 4 };

// A table not created yet (its SQL not run): what it would hold is empty.
const noTable = (err) => err?.code === "42P01";

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

  /** Who checks in: the exempt positions and each member's position / rule. */
  async function rulesOf(adminId) {
    try {
      const [s, m] = await Promise.all([
        db.query(`SELECT exempt_positions FROM attendance_settings WHERE admin_id = $1`, [adminId]),
        db.query(`SELECT user_id, position, rule FROM attendance_members WHERE admin_id = $1`, [adminId]),
      ]);
      return {
        ready: true,
        exempt: s.rows[0]?.exempt_positions || [],
        members: new Map(m.rows.map((r) => [Number(r.user_id), { position: r.position, rule: r.rule }])),
      };
    } catch (err) {
      if (noTable(err)) return { ready: false, exempt: [], members: new Map() };
      throw err;
    }
  }

  /** A member's position / rule and whether they check in. */
  const ruleFor = (rules, userId) => {
    const m = rules.members.get(Number(userId)) || { position: null, rule: "auto" };
    return { position: m.position || null, rule: m.rule || "auto", ...checkInRule(m, rules.exempt) };
  };

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
    // Team members check in and out (unless exempt); the admin sees the team.
    const isAdmin = p.role === "ADMIN";
    const rr = isAdmin ? null : ruleFor(await rulesOf(adminId), p.id);
    return {
      adminId,
      userId: Number(p.id),
      isAdmin,
      enabled: !isAdmin && rr.required,
      position: rr?.position ?? null,
      exempt: !isAdmin && !rr.required,
    };
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
        exempt: p.exempt,
        position: p.position,
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
      if (p.exempt) {
        throw new HttpError(
          403,
          `Check-in is not needed for your position${p.position ? ` (${p.position})` : ""}.`,
          "exempt"
        );
      }
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
      const [team, ses, rules] = await Promise.all([
        teamOf(p.adminId),
        db.query(
          `SELECT ${COLS} FROM attendance_sessions
            WHERE admin_id = $1 AND company_guid = $2 AND work_date = $3::date ORDER BY check_in_at`,
          [p.adminId, company, date]
        ),
        rulesOf(p.adminId),
      ]);
      const byUser = new Map();
      for (const s of ses.rows) {
        const k = Number(s.user_id);
        if (!byUser.has(k)) byUser.set(k, []);
        byUser.get(k).push(s);
      }
      // Every team member of the account.
      // An exempt member who did not check in is "exempt", never absent.
      const members = team
        .map((m) => {
          const r = ruleFor(rules, m.id);
          const d = dayStatus(byUser.get(m.id) || [], t);
          return {
            user_id: m.id,
            username: m.username,
            email: m.email,
            position: r.position,
            required: r.required,
            ...d,
            status: !r.required && d.status === "absent" ? "exempt" : d.status,
          };
        })
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

  /* ------------------------------------------- who checks in (admin) */
  async function settingsBody(adminId) {
    const [team, rules] = await Promise.all([teamOf(adminId), rulesOf(adminId)]);
    const used = new Set();
    const members = team
      .map((m) => {
        const r = ruleFor(rules, m.id);
        if (r.position) used.add(r.position);
        return { user_id: m.id, username: m.username, email: m.email, ...r };
      })
      .sort((a, b) => String(a.username).localeCompare(String(b.username)));
    const suggestions = [...new Set([...POSITION_SUGGESTIONS, ...used])];
    return { success: true, ready: rules.ready, exempt_positions: rules.exempt, positions: suggestions, rules: RULES, members };
  }

  router.get(
    "/api/attendance/settings",
    auth,
    handle(async (req, res) => {
      const p = await adminOf(req);
      res.json(await settingsBody(p.adminId));
    })
  );

  router.put(
    "/api/attendance/settings",
    auth,
    handle(async (req, res) => {
      const p = await adminOf(req);
      const v = cleanExempt(req.body?.exempt_positions);
      if (!v.ok) throw new HttpError(400, v.message);
      try {
        await db.query(
          `INSERT INTO attendance_settings (admin_id, exempt_positions, updated_by, updated_at)
           VALUES ($1, $2::text[], $3, NOW())
           ON CONFLICT (admin_id) DO UPDATE SET
             exempt_positions = EXCLUDED.exempt_positions, updated_by = EXCLUDED.updated_by, updated_at = NOW()`,
          [p.adminId, v.value, p.userId]
        );
      } catch (err) {
        if (noTable(err)) throw new HttpError(503, "Check-in settings are not available on the server yet.", "not_ready");
        throw err;
      }
      res.json(await settingsBody(p.adminId));
    })
  );

  router.put(
    "/api/attendance/members/:userId",
    auth,
    handle(async (req, res) => {
      const p = await adminOf(req);
      const userId = memberId(req.params.userId);
      if (!(await teamOf(p.adminId)).some((x) => x.id === userId)) throw new HttpError(404, "Team member not found");
      const rules = await rulesOf(p.adminId);
      const cur = rules.members.get(userId) || { position: null, rule: "auto" };
      let position = cur.position || null;
      let rule = cur.rule || "auto";
      if (req.body?.position !== undefined) {
        const v = cleanPosition(req.body.position);
        if (!v.ok) throw new HttpError(400, v.message);
        position = v.value;
      }
      if (req.body?.rule !== undefined) {
        if (!RULES.includes(req.body.rule)) throw new HttpError(400, "rule must be auto, required or exempt");
        rule = req.body.rule;
      }
      try {
        await db.query(
          `INSERT INTO attendance_members (admin_id, user_id, position, rule, updated_by, updated_at)
           VALUES ($1, $2, $3, $4, $5, NOW())
           ON CONFLICT (admin_id, user_id) DO UPDATE SET
             position = EXCLUDED.position, rule = EXCLUDED.rule, updated_by = EXCLUDED.updated_by, updated_at = NOW()`,
          [p.adminId, userId, position, rule, p.userId]
        );
      } catch (err) {
        if (noTable(err)) throw new HttpError(503, "Check-in settings are not available on the server yet.", "not_ready");
        throw err;
      }
      res.json(await settingsBody(p.adminId));
    })
  );

  /* ---------------------------------------- range summary (admin) */
  /** Approved leave, leave settings and holidays (none before the leave SQL). */
  async function leaveOf(adminId, from, to) {
    try {
      const [s, h, l] = await Promise.all([
        db.query(
          `SELECT enabled, year_start_month, weekly_off, half_day, backdate_days, max_request_days
             FROM leave_settings WHERE admin_id = $1`,
          [adminId]
        ),
        db.query(
          `SELECT date::text AS date FROM leave_holidays WHERE admin_id = $1 AND date BETWEEN $2::date AND $3::date`,
          [adminId, from, to]
        ),
        db.query(
          `SELECT user_id, from_date::text AS from_date, to_date::text AS to_date, half_day
             FROM leave_requests
            WHERE admin_id = $1 AND status = 'approved' AND to_date >= $2::date AND from_date <= $3::date`,
          [adminId, from, to]
        ),
      ]);
      return {
        settings: settingsOut(s.rows[0]),
        holidays: new Set(h.rows.map((x) => String(x.date).slice(0, 10))),
        leaves: l.rows.map((x) => ({
          user_id: Number(x.user_id),
          from: String(x.from_date).slice(0, 10),
          to: String(x.to_date).slice(0, 10),
          half_day: x.half_day || null,
        })),
      };
    } catch (err) {
      if (noTable(err)) return { settings: settingsOut(null), holidays: new Set(), leaves: [] };
      throw err;
    }
  }

  router.get(
    "/api/attendance/summary",
    auth,
    handle(async (req, res) => {
      const p = await adminOf(req);
      const t = now();
      const today = istDate(t);
      const range = historyRange(req.query, today);
      if (!range.ok) throw new HttpError(400, range.message);
      const { company, companyName } = await companyOf(p.adminId);
      const [team, rules, ses, lv] = await Promise.all([
        teamOf(p.adminId),
        rulesOf(p.adminId),
        db.query(
          `SELECT ${COLS} FROM attendance_sessions
            WHERE admin_id = $1 AND company_guid = $2 AND work_date BETWEEN $3::date AND $4::date
            ORDER BY check_in_at`,
          [p.adminId, company, range.from, range.to]
        ),
        leaveOf(p.adminId, range.from, range.to),
      ]);
      const sesBy = new Map();
      for (const s of ses.rows) {
        const k = Number(s.user_id);
        if (!sesBy.has(k)) sesBy.set(k, []);
        sesBy.get(k).push(s);
      }
      const members = team
        .map((m) => {
          const r = ruleFor(rules, m.id);
          const sum = memberSummary({
            from: range.from,
            to: range.to,
            today,
            now: t,
            sessions: sesBy.get(m.id) || [],
            leaves: lv.leaves.filter((x) => x.user_id === m.id),
            settings: lv.settings,
            holidays: lv.holidays,
          });
          // Exempt: not expected to check in, so never absent.
          if (!r.required) sum.absent_days = 0;
          return { user_id: m.id, username: m.username, email: m.email, position: r.position, required: r.required, ...sum };
        })
        .sort((a, b) => Number(b.required) - Number(a.required) || String(a.username).localeCompare(String(b.username)));
      res.json({ success: true, company: companyName, from: range.from, to: range.to, today, members });
    })
  );

  return router;
}
