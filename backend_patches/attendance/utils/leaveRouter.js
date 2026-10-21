/* =========================================================
   LEAVE MANAGEMENT — routes (factory; dependencies passed in)

   Account admin (Leave settings — everything is set here):
     GET  /api/leave/settings?date=           settings, types, holidays of that leave year
     PUT  /api/leave/settings                 {enabled?, year_start_month?, weekly_off?,
                                               half_day?, backdate_days?, max_request_days?}
     POST /api/leave/types                    {name, yearly_quota?, paid?, carry_forward?, max_carry?}
     POST /api/leave/types/defaults           adds Casual / Sick / Unpaid when there are none
     PUT  /api/leave/types/:id                any of the fields, active (false = hidden)
     POST /api/leave/holidays                 {date, name} (same date again = renamed)
     DELETE /api/leave/holidays/:date
     GET  /api/leave/requests?status=&user_id=&from=&to=
     POST /api/leave/requests/:id/approve     {note?}
     POST /api/leave/requests/:id/reject      {note?}
     GET  /api/leave/team/:userId?date=       a member's balances and requests
   Team member (every team login of the account; not the admin):
     GET  /api/leave/me?date=                 on? balances, requests, holidays, today
     POST /api/leave/requests                 {type_id, from, to?, half_day?, reason?, idempotency_key?}
   Both:
     POST /api/leave/requests/:id/cancel      member: own pending; admin: pending or approved
     GET  /api/leave/calendar?from=&to=       approved leave, holidays, weekly off
                                              (member: own; admin: the team)

   Every query is limited to the login's own account (admin_id from the
   sign-in token, never from the request). Days are India (IST) dates.
========================================================= */
import express from "express";
import { cleanNote, isIsoDate, istDate } from "./attendanceCore.js";
import {
  DEFAULT_TYPES,
  HOLDING,
  STATUSES,
  balances,
  calendarRange,
  cleanHoliday,
  cleanRequest,
  cleanSettings,
  cleanType,
  dayKind,
  leaveYear,
  overlaps,
  requestDays,
  requestOut,
  settingsOut,
  typeOut,
} from "./leaveCore.js";

class HttpError extends Error {
  constructor(status, message, code) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

const REQ_COLS = `r.id, r.admin_id, r.user_id, r.leave_type_id, r.from_date::text AS from_date,
  r.to_date::text AS to_date, r.half_day, r.days, r.reason, r.status, r.decided_by, r.decided_at,
  r.decision_note, r.idempotency_key, r.created_at, t.name AS type_name, u.username`;
const REQ_FROM = `leave_requests r
  JOIN leave_types t ON t.id = r.leave_type_id
  LEFT JOIN users u ON u.id = r.user_id`;
const TYPE_COLS = `id, name, yearly_quota, paid, carry_forward, max_carry, active, created_at`;

export function createLeaveRouter({ db, auth, log = console, now = () => new Date() }) {
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
      log.error("leave error:", err?.message || err);
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
    return { adminId, userId: Number(p.id), isAdmin: p.role === "ADMIN" };
  }

  async function adminOf(req) {
    const p = await personOf(req);
    if (!p.isAdmin) throw new HttpError(403, "Admin access required", "forbidden");
    return p;
  }

  const idParam = (raw, what = "id") => {
    const id = Number.parseInt(raw, 10);
    if (!Number.isInteger(id) || id <= 0 || String(id) !== raw) throw new HttpError(400, `Invalid ${what}`);
    return id;
  };

  const dateParam = (v, today) => {
    const d = v === undefined || v === "" ? today : String(v);
    if (!isIsoDate(d)) throw new HttpError(400, "Dates must be YYYY-MM-DD");
    return d;
  };

  async function settingsOf(adminId) {
    const r = await db.query(
      `SELECT enabled, year_start_month, weekly_off, half_day, backdate_days, max_request_days
         FROM leave_settings WHERE admin_id = $1`,
      [adminId]
    );
    return settingsOut(r.rows[0]);
  }

  const typesOf = async (adminId) =>
    (await db.query(`SELECT ${TYPE_COLS} FROM leave_types WHERE admin_id = $1 ORDER BY id`, [adminId])).rows;

  const holidaysIn = async (adminId, from, to) =>
    (
      await db.query(
        `SELECT date::text AS date, name FROM leave_holidays
          WHERE admin_id = $1 AND date BETWEEN $2::date AND $3::date ORDER BY date`,
        [adminId, from, to]
      )
    ).rows.map((h) => ({ date: String(h.date).slice(0, 10), name: h.name }));

  /** A person's requests that hold days (pending + approved), every year. */
  const holdingOf = async (adminId, userId) =>
    (
      await db.query(
        `SELECT ${REQ_COLS} FROM ${REQ_FROM}
          WHERE r.admin_id = $1 AND r.user_id = $2 AND r.status IN ('pending', 'approved')
          ORDER BY r.from_date`,
        [adminId, userId]
      )
    ).rows;

  /** A person's requests touching one leave year (any status), newest first. */
  const requestsIn = async (adminId, userId, from, to) =>
    (
      await db.query(
        `SELECT ${REQ_COLS} FROM ${REQ_FROM}
          WHERE r.admin_id = $1 AND r.user_id = $2 AND r.to_date >= $3::date AND r.from_date <= $4::date
          ORDER BY r.from_date DESC, r.id DESC`,
        [adminId, userId, from, to]
      )
    ).rows;

  const requestById = async (adminId, id) =>
    (await db.query(`SELECT ${REQ_COLS} FROM ${REQ_FROM} WHERE r.admin_id = $1 AND r.id = $2`, [adminId, id])).rows[0] || null;

  async function teamOf(adminId) {
    const r = await db.query(
      `SELECT u.id, u.username, u.email
         FROM users u
        WHERE u.admin_id = $1 AND u.role <> 'ADMIN'`,
      [adminId]
    );
    return r.rows.map((x) => ({ id: Number(x.id), username: x.username, email: x.email }));
  }

  /** Balances, requests and holidays of one person's leave year holding [date]. */
  async function yearOf(adminId, userId, settings, date) {
    const year = leaveYear(date, settings.year_start_month);
    const [types, holding, list, holidays] = await Promise.all([
      typesOf(adminId),
      holdingOf(adminId, userId),
      requestsIn(adminId, userId, year.from, year.to),
      holidaysIn(adminId, year.from, year.to),
    ]);
    return {
      year,
      balances: balances(types, holding, settings, year.from),
      requests: list.map(requestOut),
      holidays,
    };
  }

  /* ----------------------------------------------------- settings */
  router.get(
    "/api/leave/settings",
    auth,
    handle(async (req, res) => {
      const p = await adminOf(req);
      const settings = await settingsOf(p.adminId);
      const year = leaveYear(dateParam(req.query.date, istDate(now())), settings.year_start_month);
      const [types, holidays] = await Promise.all([typesOf(p.adminId), holidaysIn(p.adminId, year.from, year.to)]);
      res.json({ success: true, settings, year, types: types.map(typeOut), holidays });
    })
  );

  router.put(
    "/api/leave/settings",
    auth,
    handle(async (req, res) => {
      const p = await adminOf(req);
      const c = cleanSettings(req.body, await settingsOf(p.adminId));
      if (!c.ok) throw new HttpError(400, c.message);
      const s = c.value;
      await db.query(
        `INSERT INTO leave_settings
           (admin_id, enabled, year_start_month, weekly_off, half_day, backdate_days, max_request_days, updated_by, updated_at)
         VALUES ($1, $2, $3, $4::smallint[], $5, $6, $7, $8, NOW())
         ON CONFLICT (admin_id) DO UPDATE SET
           enabled = EXCLUDED.enabled, year_start_month = EXCLUDED.year_start_month,
           weekly_off = EXCLUDED.weekly_off, half_day = EXCLUDED.half_day,
           backdate_days = EXCLUDED.backdate_days, max_request_days = EXCLUDED.max_request_days,
           updated_by = EXCLUDED.updated_by, updated_at = NOW()`,
        [p.adminId, s.enabled, s.year_start_month, s.weekly_off, s.half_day, s.backdate_days, s.max_request_days, p.userId]
      );
      res.json({ success: true, settings: s });
    })
  );

  /* -------------------------------------------------------- types */
  const nameTaken = (err) => err?.code === "23505";

  router.post(
    "/api/leave/types",
    auth,
    handle(async (req, res) => {
      const p = await adminOf(req);
      const c = cleanType(req.body);
      if (!c.ok) throw new HttpError(400, c.message);
      const t = c.value;
      try {
        const r = await db.query(
          `INSERT INTO leave_types (admin_id, name, yearly_quota, paid, carry_forward, max_carry, active)
           VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING ${TYPE_COLS}`,
          [p.adminId, t.name, t.yearly_quota, t.paid, t.carry_forward, t.max_carry, t.active]
        );
        res.status(201).json({ success: true, type: typeOut(r.rows[0]) });
      } catch (err) {
        if (nameTaken(err)) throw new HttpError(409, "A leave type with this name exists", "name_taken");
        throw err;
      }
    })
  );

  router.post(
    "/api/leave/types/defaults",
    auth,
    handle(async (req, res) => {
      const p = await adminOf(req);
      if ((await typesOf(p.adminId)).length) {
        throw new HttpError(409, "Leave types are already set up", "types_exist");
      }
      for (const t of DEFAULT_TYPES) {
        await db.query(
          `INSERT INTO leave_types (admin_id, name, yearly_quota, paid, carry_forward, max_carry, active)
           VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING ${TYPE_COLS}`,
          [p.adminId, t.name, t.yearly_quota, t.paid, t.carry_forward, t.max_carry, true]
        );
      }
      res.status(201).json({ success: true, types: (await typesOf(p.adminId)).map(typeOut) });
    })
  );

  router.put(
    "/api/leave/types/:id",
    auth,
    handle(async (req, res) => {
      const p = await adminOf(req);
      const id = idParam(req.params.id);
      const c = cleanType(req.body, true);
      if (!c.ok) throw new HttpError(400, c.message);
      const keys = Object.keys(c.value);
      const sets = keys.map((k, i) => `${k} = $${i + 3}`).join(", ");
      try {
        const r = await db.query(
          `UPDATE leave_types SET ${sets} WHERE admin_id = $1 AND id = $2 RETURNING ${TYPE_COLS}`,
          [p.adminId, id, ...keys.map((k) => c.value[k])]
        );
        if (!r.rows[0]) throw new HttpError(404, "Leave type not found");
        res.json({ success: true, type: typeOut(r.rows[0]) });
      } catch (err) {
        if (nameTaken(err)) throw new HttpError(409, "A leave type with this name exists", "name_taken");
        throw err;
      }
    })
  );

  /* ----------------------------------------------------- holidays */
  router.post(
    "/api/leave/holidays",
    auth,
    handle(async (req, res) => {
      const p = await adminOf(req);
      const c = cleanHoliday(req.body);
      if (!c.ok) throw new HttpError(400, c.message);
      await db.query(
        `INSERT INTO leave_holidays (admin_id, date, name) VALUES ($1, $2::date, $3)
         ON CONFLICT (admin_id, date) DO UPDATE SET name = EXCLUDED.name`,
        [p.adminId, c.value.date, c.value.name]
      );
      res.status(201).json({ success: true, holiday: c.value });
    })
  );

  router.delete(
    "/api/leave/holidays/:date",
    auth,
    handle(async (req, res) => {
      const p = await adminOf(req);
      if (!isIsoDate(req.params.date)) throw new HttpError(400, "Dates must be YYYY-MM-DD");
      const r = await db.query(`DELETE FROM leave_holidays WHERE admin_id = $1 AND date = $2::date`, [p.adminId, req.params.date]);
      if (!(r.rowCount || 0)) throw new HttpError(404, "Holiday not found");
      res.json({ success: true });
    })
  );

  /* ------------------------------------------------------- member */
  router.get(
    "/api/leave/me",
    auth,
    handle(async (req, res) => {
      const p = await personOf(req);
      const settings = await settingsOf(p.adminId);
      const today = istDate(now());
      const base = {
        success: true,
        enabled: settings.enabled,
        is_admin: p.isAdmin,
        settings,
      };
      // The admin approves; leave is applied by team members.
      if (!settings.enabled || p.isAdmin) return res.json(base);
      const y = await yearOf(p.adminId, p.userId, settings, dateParam(req.query.date, today));
      const holidaysToday = new Set(
        (await holidaysIn(p.adminId, today, today)).map((h) => h.date)
      );
      const todayLeave = (await holdingOf(p.adminId, p.userId))
        .filter((r) => r.status === "approved" && String(r.from_date) <= today && String(r.to_date) >= today)
        .map(requestOut)[0] || null;
      res.json({
        ...base,
        ...y,
        today: { date: today, kind: dayKind(today, settings, holidaysToday), leave: todayLeave },
      });
    })
  );

  router.post(
    "/api/leave/requests",
    auth,
    handle(async (req, res) => {
      const p = await personOf(req);
      if (p.isAdmin) throw new HttpError(403, "Leave is applied by team members; the admin approves it.", "not_on_team");
      const settings = await settingsOf(p.adminId);
      if (!settings.enabled) throw new HttpError(403, "Leave management is off for this account.", "leave_off");
      const c = cleanRequest(req.body, settings, istDate(now()));
      if (!c.ok) throw new HttpError(400, c.message);
      const q = c.value;

      const replay = async () => {
        if (!q.key) return null;
        const r = await db.query(
          `SELECT ${REQ_COLS} FROM ${REQ_FROM} WHERE r.user_id = $1 AND r.idempotency_key = $2`,
          [p.userId, q.key]
        );
        return r.rows[0] || null;
      };
      const again = await replay();
      if (again) return res.json({ success: true, replayed: true, request: requestOut(again) });

      const types = await typesOf(p.adminId);
      const type = types.find((t) => Number(t.id) === q.type_id && t.active);
      if (!type) throw new HttpError(400, "Choose a leave type", "bad_type");

      const holidays = new Set((await holidaysIn(p.adminId, q.from, q.to)).map((h) => h.date));
      const d = requestDays(q, settings, holidays);
      if (!d.ok) throw new HttpError(400, d.message, "no_working_days");

      const holding = await holdingOf(p.adminId, p.userId);
      const clash = holding.find((r) =>
        overlaps(q, { from: String(r.from_date), to: String(r.to_date), half_day: r.half_day })
      );
      if (clash) {
        throw new HttpError(
          409,
          `You already have ${clash.status} leave from ${String(clash.from_date)} to ${String(clash.to_date)}`,
          "overlap"
        );
      }

      const year = leaveYear(q.from, settings.year_start_month);
      const bal = balances([type], holding, settings, year.from)[0];
      if (bal.available !== null && d.days > bal.available) {
        throw new HttpError(
          409,
          `Only ${bal.available} day(s) of ${type.name} left in ${year.label}`,
          "insufficient_balance"
        );
      }

      try {
        const r = await db.query(
          `INSERT INTO leave_requests
             (admin_id, user_id, leave_type_id, from_date, to_date, half_day, days, reason, idempotency_key)
           VALUES ($1, $2, $3, $4::date, $5::date, $6, $7, $8, $9)
           RETURNING id`,
          [p.adminId, p.userId, q.type_id, q.from, q.to, q.half_day, d.days, q.reason, q.key]
        );
        res.status(201).json({ success: true, request: requestOut(await requestById(p.adminId, Number(r.rows[0].id))) });
      } catch (err) {
        if (err?.code !== "23505") throw err;
        // Two taps at once: the first one won.
        const won = await replay();
        if (won) return res.json({ success: true, replayed: true, request: requestOut(won) });
        throw err;
      }
    })
  );

  /* ------------------------------------------------- decisions */
  /** Moves a request from one of [fromStatuses] to [status]; 409 when it has moved on. */
  async function decide(req, res, { status, fromStatuses, who }) {
    const p = who === "admin" ? await adminOf(req) : await personOf(req);
    const id = idParam(req.params.id);
    const note = cleanNote(req.body?.note);
    if (!note.ok) throw new HttpError(400, note.message);
    const cur = await requestById(p.adminId, id);
    if (!cur) throw new HttpError(404, "Leave request not found");
    let allowed = fromStatuses;
    if (who === "either" && !p.isAdmin) {
      // A team member cancels only their own request, while it waits.
      if (Number(cur.user_id) !== p.userId) throw new HttpError(404, "Leave request not found");
      allowed = ["pending"];
    }
    if (!allowed.includes(cur.status)) {
      throw new HttpError(409, `This request is already ${cur.status}`, "not_pending");
    }
    const r = await db.query(
      `UPDATE leave_requests
          SET status = $3, decided_by = $4, decided_at = $5, decision_note = COALESCE($6, decision_note), updated_at = $5
        WHERE admin_id = $1 AND id = $2 AND status = ANY($7::text[])
        RETURNING id`,
      [p.adminId, id, status, p.userId, now(), note.value, allowed]
    );
    // Someone else decided in between.
    if (!r.rows[0]) throw new HttpError(409, "This request was changed meanwhile; refresh", "not_pending");
    res.json({ success: true, request: requestOut(await requestById(p.adminId, id)) });
  }

  router.post(
    "/api/leave/requests/:id/approve",
    auth,
    handle((req, res) => decide(req, res, { status: "approved", fromStatuses: ["pending"], who: "admin" }))
  );
  router.post(
    "/api/leave/requests/:id/reject",
    auth,
    handle((req, res) => decide(req, res, { status: "rejected", fromStatuses: ["pending"], who: "admin" }))
  );
  router.post(
    "/api/leave/requests/:id/cancel",
    auth,
    handle((req, res) => decide(req, res, { status: "cancelled", fromStatuses: HOLDING, who: "either" }))
  );

  /* -------------------------------------------------------- admin */
  router.get(
    "/api/leave/requests",
    auth,
    handle(async (req, res) => {
      const p = await adminOf(req);
      const status = req.query.status === undefined || req.query.status === "" ? "pending" : String(req.query.status);
      if (status !== "all" && !STATUSES.includes(status)) throw new HttpError(400, "Unknown status");
      const where = ["r.admin_id = $1"];
      const args = [p.adminId];
      if (status !== "all") {
        args.push(status);
        where.push(`r.status = $${args.length}`);
      }
      if (req.query.user_id !== undefined && req.query.user_id !== "") {
        args.push(idParam(String(req.query.user_id), "user id"));
        where.push(`r.user_id = $${args.length}`);
      }
      if (req.query.from) {
        args.push(dateParam(req.query.from));
        where.push(`r.to_date >= $${args.length}::date`);
      }
      if (req.query.to) {
        args.push(dateParam(req.query.to));
        where.push(`r.from_date <= $${args.length}::date`);
      }
      const r = await db.query(
        `SELECT ${REQ_COLS} FROM ${REQ_FROM} WHERE ${where.join(" AND ")}
          ORDER BY r.from_date ${status === "pending" ? "ASC" : "DESC"}, r.id DESC LIMIT 500`,
        args
      );
      res.json({ success: true, status, requests: r.rows.map(requestOut) });
    })
  );

  router.get(
    "/api/leave/team/:userId",
    auth,
    handle(async (req, res) => {
      const p = await adminOf(req);
      const userId = idParam(req.params.userId, "user id");
      const m = (await teamOf(p.adminId)).find((x) => x.id === userId);
      if (!m) throw new HttpError(404, "Team member not found");
      const settings = await settingsOf(p.adminId);
      const y = await yearOf(p.adminId, userId, settings, dateParam(req.query.date, istDate(now())));
      res.json({ success: true, member: { user_id: m.id, username: m.username, email: m.email }, settings, ...y });
    })
  );

  router.get(
    "/api/leave/calendar",
    auth,
    handle(async (req, res) => {
      const p = await personOf(req);
      const range = calendarRange(req.query, istDate(now()));
      if (!range.ok) throw new HttpError(400, range.message);
      const settings = await settingsOf(p.adminId);
      const args = [p.adminId, range.from, range.to];
      const mine = p.isAdmin ? "" : " AND r.user_id = $4";
      if (!p.isAdmin) args.push(p.userId);
      const [holidays, leaves] = await Promise.all([
        holidaysIn(p.adminId, range.from, range.to),
        db.query(
          `SELECT ${REQ_COLS} FROM ${REQ_FROM}
            WHERE r.admin_id = $1 AND r.status = 'approved' AND r.to_date >= $2::date AND r.from_date <= $3::date${mine}
            ORDER BY r.from_date`,
          args
        ),
      ]);
      res.json({
        success: true,
        from: range.from,
        to: range.to,
        weekly_off: settings.weekly_off,
        holidays,
        leaves: leaves.rows.map(requestOut),
      });
    })
  );

  return router;
}
