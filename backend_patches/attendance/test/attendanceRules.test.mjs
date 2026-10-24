// Tests for who checks in (positions, exempt list, per-person rule) and the
// admin's range summary per member (node --test). No database or network:
// an in-memory fake pg pool and a stub login. Today is Mon 19 Oct 2026
// (India time); Sunday is the weekly off; 15 Oct is a holiday.
import { test, describe, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import express from "express";

import { checkInRule, cleanExempt, cleanPosition, memberSummary } from "../utils/attendanceRules.js";
import { createAttendanceRouter } from "../utils/attendanceRouter.js";

/* ------------------------------------------------------------ rules */
describe("rules", () => {
  test("by position, the admin's choice per person wins", () => {
    const ex = ["Manager", "Director"];
    assert.deepEqual(checkInRule({ position: "Sales Executive", rule: "auto" }, ex), { required: true, reason: "default" });
    assert.deepEqual(checkInRule({ position: " manager ", rule: "auto" }, ex), { required: false, reason: "position" });
    assert.deepEqual(checkInRule({ position: "Manager", rule: "required" }, ex), { required: true, reason: "rule" });
    assert.deepEqual(checkInRule({ position: "Sales Executive", rule: "exempt" }, ex), { required: false, reason: "rule" });
    assert.deepEqual(checkInRule({}, ex), { required: true, reason: "default" });
    assert.deepEqual(checkInRule(null, []), { required: true, reason: "default" });
  });

  test("positions and the exempt list are cleaned", () => {
    assert.deepEqual(cleanPosition("  Sales   Manager "), { ok: true, value: "Sales Manager" });
    assert.deepEqual(cleanPosition(""), { ok: true, value: null });
    assert.equal(cleanPosition("x".repeat(41)).ok, false);
    assert.equal(cleanPosition(5).ok, false);
    assert.deepEqual(cleanExempt(["Manager", "manager", " Director ", ""]).value, ["Manager", "Director"]);
    assert.equal(cleanExempt("Manager").ok, false);
    assert.equal(cleanExempt(Array.from({ length: 21 }, (_, i) => `P${i}`)).ok, false);
  });

  test("summary: present, hours, leave, absent working days, averages", () => {
    const s = (d, inH, outH) => ({
      work_date: d,
      check_in_at: new Date(`${d}T${inH}:00+05:30`),
      check_out_at: outH ? new Date(`${d}T${outH}:00+05:30`) : null,
    });
    const r = memberSummary({
      from: "2026-10-12",
      to: "2026-10-25", // runs past today: later days are not counted
      today: "2026-10-19",
      now: new Date("2026-10-19T12:00:00+05:30"),
      sessions: [s("2026-10-12", "09:30", "18:30"), s("2026-10-13", "10:30", "18:30"), s("2026-10-19", "09:00", null)],
      leaves: [{ from: "2026-10-14", to: "2026-10-14", half_day: null }, { from: "2026-10-16", to: "2026-10-16", half_day: "first" }],
      settings: { weekly_off: [0] },
      holidays: new Set(["2026-10-15"]),
    });
    // 12–19 Oct: Sun 18 off, Thu 15 holiday → 6 working days (12,13,14,16,17,19).
    assert.equal(r.working_days, 6);
    assert.equal(r.weekly_off, 1);
    assert.equal(r.holidays, 1);
    assert.equal(r.present_days, 3);
    assert.equal(r.leave_days, 1.5);
    // 16 (half leave, no check-in) and 17 count; 14 is leave; 19 is today.
    assert.equal(r.absent_days, 2);
    assert.equal(r.total_minutes, 9 * 60 + 8 * 60 + 3 * 60);
    assert.equal(r.avg_in, "09:40");
    assert.equal(r.avg_out, "18:30"); // the open day is left out
  });
});

/* ---------------------------------------------------------- fake db */
class FakeDb {
  constructor() {
    this.users = [
      { id: 7, admin_id: 7, role: "ADMIN", username: "ravi", email: "ravi@x.in" },
      { id: 21, admin_id: 7, role: "USER", username: "asha", email: "asha@x.in" },
      { id: 22, admin_id: 7, role: "USER", username: "vik", email: "vik@x.in" },
      { id: 23, admin_id: 7, role: "USER", username: "meera", email: "m@x.in" },
      { id: 31, admin_id: 8, role: "USER", username: "omar", email: "o@x.in" },
    ];
    this.settings = [];
    this.members = [];
    this.sessions = [];
    this.leaves = [
      { admin_id: 7, user_id: 21, from_date: "2026-10-14", to_date: "2026-10-14", half_day: null, status: "approved" },
      { admin_id: 7, user_id: 22, from_date: "2026-10-13", to_date: "2026-10-13", half_day: null, status: "pending" },
    ];
    this.nextId = 1;
  }

  async query(sql, p = []) {
    const s = sql.replace(/\s+/g, " ").trim();
    const out = (rows) => ({ rows: rows.map((r) => ({ ...r })), rowCount: rows.length });
    if (s.includes("FROM active_company ac")) return out([{ company_guid: "CO-1", company_name: "Ravi Traders" }]);
    if (s.includes("FROM users u") && s.includes("WHERE u.id = $1 AND u.admin_id = $2")) {
      return out(this.users.filter((u) => u.id === p[0] && u.admin_id === p[1]));
    }
    if (s.includes("FROM users u") && s.includes("u.role <> 'ADMIN'")) {
      return out(this.users.filter((u) => u.admin_id === p[0] && u.role !== "ADMIN"));
    }
    if (s.startsWith("UPDATE attendance_sessions SET check_out_at = GREATEST")) return { rows: [], rowCount: 0 };
    if (s.includes("FROM attendance_settings")) return out(this.settings.filter((x) => x.admin_id === p[0]));
    if (s.includes("FROM attendance_members")) return out(this.members.filter((x) => x.admin_id === p[0]));
    if (s.startsWith("INSERT INTO attendance_settings")) {
      this.settings = this.settings.filter((x) => x.admin_id !== p[0]);
      this.settings.push({ admin_id: p[0], exempt_positions: p[1] });
      return out([]);
    }
    if (s.startsWith("INSERT INTO attendance_members")) {
      this.members = this.members.filter((x) => !(x.admin_id === p[0] && x.user_id === p[1]));
      this.members.push({ admin_id: p[0], user_id: p[1], position: p[2], rule: p[3] });
      return out([]);
    }
    if (s.includes("FROM leave_settings")) return out([]);
    if (s.includes("FROM leave_holidays")) return out([{ date: "2026-10-15" }]);
    if (s.includes("FROM leave_requests")) {
      return out(
        this.leaves.filter((x) => x.admin_id === p[0] && x.status === "approved" && x.to_date >= p[1] && x.from_date <= p[2])
      );
    }
    if (s.startsWith("INSERT INTO attendance_sessions")) {
      const row = {
        id: this.nextId++, admin_id: p[0], company_guid: p[1], user_id: p[2], work_date: p[3],
        check_in_at: p[4], last_seen_at: p[4], check_out_at: null, closed_by: null, idempotency_key: p[6],
      };
      this.sessions.push(row);
      return out([row]);
    }
    if (s.includes("FROM attendance_sessions WHERE user_id = $1 AND idempotency_key = $2")) return out([]);
    if (s.includes("FROM attendance_sessions WHERE admin_id = $1 AND user_id = $2 AND check_out_at IS NULL")) {
      return out(this.sessions.filter((x) => x.admin_id === p[0] && x.user_id === p[1] && !x.check_out_at));
    }
    if (s.includes("WHERE admin_id = $1 AND user_id = $2 AND work_date = $3::date")) {
      return out(this.sessions.filter((x) => x.admin_id === p[0] && x.user_id === p[1] && x.work_date === p[2]));
    }
    if (s.includes("WHERE admin_id = $1 AND company_guid = $2 AND work_date = $3::date")) {
      return out(this.sessions.filter((x) => x.admin_id === p[0] && x.work_date === p[2]));
    }
    if (s.includes("WHERE admin_id = $1 AND company_guid = $2 AND work_date BETWEEN $3::date AND $4::date")) {
      return out(this.sessions.filter((x) => x.admin_id === p[0] && x.work_date >= p[2] && x.work_date <= p[3]));
    }
    throw new Error(`FakeDb: unhandled SQL ${s}`);
  }
}

const ADMIN = { id: 7, adminId: 7, role: "ADMIN" };
const ASHA = { id: 21, adminId: 7, role: "USER" };
const VIK = { id: 22, adminId: 7, role: "USER" };
const OMAR = { id: 31, adminId: 8, role: "USER" };

describe("routes", () => {
  let db, server, base;
  beforeEach(async () => {
    db = new FakeDb();
    const app = express();
    app.use(express.json());
    app.use(
      createAttendanceRouter({
        db,
        auth: (req, res, next) => {
          const u = req.headers["x-test-user"];
          if (!u) return res.status(401).json({ message: "Unauthorized" });
          req.user = JSON.parse(u);
          next();
        },
        log: { error: () => {} },
        now: () => new Date("2026-10-19T10:00:00+05:30"),
      })
    );
    await new Promise((r) => (server = app.listen(0, r)));
    base = `http://127.0.0.1:${server.address().port}`;
  });
  afterEach(() => new Promise((r) => server.close(r)));

  const call = async (method, path, user, body) => {
    const r = await fetch(base + path, {
      method,
      headers: { "content-type": "application/json", ...(user ? { "x-test-user": JSON.stringify(user) } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    return { status: r.status, body: await r.json() };
  };

  test("admin sets positions and the exempt list; members follow", async () => {
    let r = await call("GET", "/api/attendance/settings", ADMIN);
    assert.equal(r.status, 200);
    assert.deepEqual(r.body.exempt_positions, []);
    assert.equal(r.body.members.every((m) => m.required), true); // as before: everyone
    assert.ok(r.body.positions.includes("Manager"));
    assert.equal((await call("GET", "/api/attendance/settings", ASHA)).status, 403);
    assert.equal((await call("PUT", "/api/attendance/settings", ASHA, { exempt_positions: [] })).status, 403);

    await call("PUT", "/api/attendance/members/22", ADMIN, { position: "Sales Manager" });
    await call("PUT", "/api/attendance/members/23", ADMIN, { position: "Accountant", rule: "exempt" });
    r = await call("PUT", "/api/attendance/settings", ADMIN, { exempt_positions: ["Sales Manager", "Director"] });
    const by = Object.fromEntries(r.body.members.map((m) => [m.username, m]));
    assert.deepEqual([by.asha.required, by.vik.required, by.meera.required], [true, false, false]);
    assert.deepEqual([by.vik.reason, by.meera.reason], ["position", "rule"]);
    assert.ok(r.body.positions.includes("Sales Manager"));
    // Another account's member, a bad rule, a long position: refused.
    assert.equal((await call("PUT", "/api/attendance/members/31", ADMIN, { position: "X" })).status, 404);
    assert.equal((await call("PUT", "/api/attendance/members/22", ADMIN, { rule: "sometimes" })).status, 400);
    assert.equal((await call("PUT", "/api/attendance/members/22", ADMIN, { position: "x".repeat(41) })).status, 400);

    // The exempt manager is not asked to check in and cannot; Asha can.
    let me = await call("GET", "/api/attendance/me", VIK);
    assert.deepEqual([me.body.enabled, me.body.exempt, me.body.position], [false, true, "Sales Manager"]);
    const ci = await call("POST", "/api/attendance/check-in", VIK, {});
    assert.equal(ci.status, 403);
    assert.equal(ci.body.code, "exempt");
    assert.match(ci.body.message, /Sales Manager/);
    assert.equal((await call("POST", "/api/attendance/check-in", ASHA, {})).status, 201);
    me = await call("GET", "/api/attendance/me", ASHA);
    assert.deepEqual([me.body.enabled, me.body.exempt], [true, false]);

    // Required for one manager: checks in after all.
    await call("PUT", "/api/attendance/members/22", ADMIN, { rule: "required" });
    assert.equal((await call("GET", "/api/attendance/me", VIK)).body.enabled, true);

    // The day: exempt members are "exempt", never absent.
    const day = await call("GET", "/api/attendance/team", ADMIN);
    const st = Object.fromEntries(day.body.members.map((m) => [m.username, m.status]));
    assert.deepEqual(st, { asha: "active", vik: "absent", meera: "exempt" });
    assert.equal(day.body.counts.exempt, 1);
    assert.equal(day.body.counts.absent, 1);
  });

  test("range summary per member (admin only)", async () => {
    await call("PUT", "/api/attendance/members/23", ADMIN, { rule: "exempt" });
    db.sessions.push(
      { id: 90, admin_id: 7, company_guid: "CO-1", user_id: 21, work_date: "2026-10-12",
        check_in_at: new Date("2026-10-12T09:30:00+05:30"), check_out_at: new Date("2026-10-12T18:30:00+05:30"),
        last_seen_at: new Date("2026-10-12T18:30:00+05:30") }
    );
    const r = await call("GET", "/api/attendance/summary?from=2026-10-12&to=2026-10-18", ADMIN);
    assert.equal(r.status, 200);
    const by = Object.fromEntries(r.body.members.map((m) => [m.username, m]));
    // 12–18 Oct: Sun off, 15 holiday → 5 working days.
    assert.equal(by.asha.working_days, 5);
    assert.equal(by.asha.present_days, 1);
    assert.equal(by.asha.leave_days, 1); // the approved day; Vik's pending one is not leave
    assert.equal(by.asha.absent_days, 3);
    assert.equal(by.asha.total_minutes, 540);
    assert.equal(by.asha.avg_in, "09:30");
    assert.equal(by.vik.leave_days, 0);
    assert.equal(by.vik.absent_days, 5);
    assert.equal(by.meera.required, false);
    assert.equal(by.meera.absent_days, 0); // exempt: never absent
    assert.equal(r.body.members.at(-1).username, "meera"); // exempt last
    assert.equal((await call("GET", "/api/attendance/summary?from=2026-01-01&to=2026-10-18", ADMIN)).status, 400);
    assert.equal((await call("GET", "/api/attendance/summary", ASHA)).status, 403);
    assert.equal((await call("GET", "/api/attendance/summary", OMAR)).status, 403);
  });

  test("before the SQL: everyone checks in, settings explain", async () => {
    const real = db.query.bind(db);
    db.query = async (sql, p) => {
      if (/attendance_settings|attendance_members/.test(sql)) {
        throw Object.assign(new Error("relation does not exist"), { code: "42P01" });
      }
      return real(sql, p);
    };
    assert.equal((await call("GET", "/api/attendance/me", VIK)).body.enabled, true);
    const s = await call("GET", "/api/attendance/settings", ADMIN);
    assert.equal(s.body.ready, false);
    const put = await call("PUT", "/api/attendance/settings", ADMIN, { exempt_positions: ["Manager"] });
    assert.equal(put.status, 503);
    assert.equal(put.body.code, "not_ready");
  });
});
