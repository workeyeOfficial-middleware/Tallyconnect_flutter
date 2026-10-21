// Tests for leave management (node --test). No database or network: an
// in-memory fake pg pool, a stub login and a settable clock. Needs only
// `express` installed next to the files.
import { test, describe, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import express from "express";

import {
  DEFAULT_SETTINGS,
  balances,
  calendarRange,
  cleanHoliday,
  cleanRequest,
  cleanSettings,
  cleanType,
  leaveYear,
  monthEnd,
  overlaps,
  requestDays,
} from "../utils/leaveCore.js";
import { createLeaveRouter } from "../utils/leaveRouter.js";

const S = (over = {}) => ({ ...DEFAULT_SETTINGS, enabled: true, ...over });

/* ------------------------------------------------------------ core */
describe("core", () => {
  test("leave year from the admin's start month", () => {
    assert.deepEqual(leaveYear("2026-10-19", 4), { from: "2026-04-01", to: "2027-03-31", label: "2026-27" });
    assert.deepEqual(leaveYear("2026-03-31", 4), { from: "2025-04-01", to: "2026-03-31", label: "2025-26" });
    assert.deepEqual(leaveYear("2026-10-19", 1), { from: "2026-01-01", to: "2026-12-31", label: "2026" });
    assert.equal(monthEnd("2026-02-10"), "2026-02-28");
    assert.equal(monthEnd("2026-12-05"), "2026-12-31");
  });

  test("working days: weekly off and holidays left out, half day 0.5", () => {
    const hol = new Set(["2026-10-21"]);
    // Mon 19 → Mon 26: 8 dates, Sunday 25 off, holiday 21 → 6
    assert.deepEqual(requestDays({ from: "2026-10-19", to: "2026-10-26" }, S(), hol), { ok: true, days: 6 });
    // Saturday off too → 5
    assert.equal(requestDays({ from: "2026-10-19", to: "2026-10-26" }, S({ weekly_off: [0, 6] }), hol).days, 5);
    assert.deepEqual(requestDays({ from: "2026-10-19", to: "2026-10-19", half_day: "first" }, S(), hol), { ok: true, days: 0.5 });
    assert.equal(requestDays({ from: "2026-10-25", to: "2026-10-25", half_day: "first" }, S(), hol).ok, false);
    assert.equal(requestDays({ from: "2026-10-25", to: "2026-10-25" }, S(), hol).ok, false); // only a Sunday
  });

  test("settings: every field optional, checked", () => {
    const cur = S();
    assert.deepEqual(cleanSettings({ weekly_off: [6, 0, 6] }, cur).value.weekly_off, [0, 6]);
    assert.equal(cleanSettings({ weekly_off: [0, 1, 2, 3, 4, 5, 6] }, cur).ok, false);
    assert.equal(cleanSettings({ weekly_off: [7] }, cur).ok, false);
    assert.equal(cleanSettings({ year_start_month: 13 }, cur).ok, false);
    assert.equal(cleanSettings({ enabled: "yes" }, cur).ok, false);
    assert.equal(cleanSettings({ year_start_month: 1, half_day: false }, cur).value.year_start_month, 1);
    assert.equal(cleanSettings({}, cur).value.backdate_days, 7);
  });

  test("leave types and holidays", () => {
    assert.deepEqual(cleanType({ name: "  Casual   Leave ", yearly_quota: 12 }).value, {
      name: "Casual Leave", yearly_quota: 12, max_carry: null, paid: true, carry_forward: false, active: true,
    });
    assert.equal(cleanType({ name: "" }).ok, false);
    assert.equal(cleanType({ name: "X", yearly_quota: 1.3 }).ok, false); // half days only
    assert.equal(cleanType({ name: "X", yearly_quota: 1.5 }).ok, true);
    assert.equal(cleanType({ name: "X", yearly_quota: -1 }).ok, false);
    assert.deepEqual(cleanType({ active: false }, true).value, { active: false });
    assert.equal(cleanType({}, true).ok, false);
    assert.equal(cleanHoliday({ date: "2026-11-08", name: "Diwali" }).ok, true);
    assert.equal(cleanHoliday({ date: "2026-02-30", name: "x" }).ok, false);
  });

  test("requests: dates, half day, back-dated limit, one leave year, max days", () => {
    const today = "2026-10-19";
    const ok = cleanRequest({ type_id: 1, from: "2026-10-20" }, S(), today);
    assert.deepEqual(ok.value, { type_id: 1, from: "2026-10-20", to: "2026-10-20", half_day: null, reason: null, key: null });
    assert.equal(cleanRequest({ type_id: 0, from: "2026-10-20" }, S(), today).ok, false);
    assert.equal(cleanRequest({ type_id: 1, from: "2026-10-21", to: "2026-10-20" }, S(), today).ok, false);
    assert.equal(cleanRequest({ type_id: 1, from: "2026-10-20", to: "2026-10-21", half_day: "first" }, S(), today).ok, false);
    assert.equal(cleanRequest({ type_id: 1, from: "2026-10-20", half_day: "first" }, S({ half_day: false }), today).ok, false);
    assert.equal(cleanRequest({ type_id: 1, from: "2026-10-12" }, S(), today).ok, true); // 7 days back
    assert.equal(cleanRequest({ type_id: 1, from: "2026-10-11" }, S(), today).ok, false);
    assert.match(cleanRequest({ type_id: 1, from: "2026-10-18" }, S({ backdate_days: 0 }), today).message, /before today/);
    assert.match(cleanRequest({ type_id: 1, from: "2027-03-30", to: "2027-04-02" }, S(), today).message, /each leave year/);
    assert.equal(cleanRequest({ type_id: 1, from: "2026-10-20", to: "2026-11-30" }, S(), today).ok, false); // > 30 days
  });

  test("overlaps: two halves of one date do not clash", () => {
    assert.equal(overlaps({ from: "2026-10-20", to: "2026-10-22" }, { from: "2026-10-22", to: "2026-10-23" }), true);
    assert.equal(overlaps({ from: "2026-10-20", to: "2026-10-21" }, { from: "2026-10-22", to: "2026-10-23" }), false);
    assert.equal(overlaps({ from: "2026-10-20", to: "2026-10-20", half_day: "first" }, { from: "2026-10-20", to: "2026-10-20", half_day: "second" }), false);
    assert.equal(overlaps({ from: "2026-10-20", to: "2026-10-20", half_day: "first" }, { from: "2026-10-20", to: "2026-10-20", half_day: "first" }), true);
    assert.equal(overlaps({ from: "2026-10-20", to: "2026-10-20", half_day: "first" }, { from: "2026-10-19", to: "2026-10-21" }), true);
  });

  test("balances: used, pending, carry forward capped, no limit", () => {
    const types = [
      { id: 1, name: "Earned", yearly_quota: "12.0", paid: true, carry_forward: true, max_carry: "5.0", active: true, created_at: "2024-05-01" },
      { id: 2, name: "Sick", yearly_quota: "6.0", paid: true, carry_forward: false, max_carry: null, active: true, created_at: "2024-05-01" },
      { id: 3, name: "Unpaid", yearly_quota: null, paid: false, carry_forward: false, max_carry: null, active: true, created_at: "2024-05-01" },
      { id: 4, name: "Old", yearly_quota: "2.0", paid: true, carry_forward: false, max_carry: null, active: false, created_at: "2024-05-01" },
    ];
    const req = (t, from, days, status) => ({ leave_type_id: t, from_date: from, days: String(days), status });
    const requests = [
      req(1, "2024-06-10", 10, "approved"), // 2024-25: 12 − 10 = 2 left → 2 carried
      req(1, "2025-06-10", 4, "approved"), // 2025-26: 12 + 2 − 4 = 10 left → capped to 5
      req(1, "2026-06-10", 3, "approved"),
      req(1, "2026-11-02", 1.5, "pending"),
      req(2, "2026-07-01", 2, "approved"),
      req(3, "2026-08-01", 4, "approved"),
    ];
    const b = balances(types, requests, S(), "2026-04-01");
    assert.deepEqual(b.map((x) => x.name), ["Earned", "Sick", "Unpaid"]); // inactive without use: hidden
    assert.deepEqual(b[0], {
      type_id: 1, name: "Earned", paid: true, active: true, quota: 12, carried: 5, entitled: 17, used: 3, pending: 1.5, available: 12.5,
    });
    assert.equal(b[1].carried, 0);
    assert.equal(b[1].available, 4);
    assert.equal(b[2].available, null); // no limit
    assert.equal(b[2].used, 4);
    // A type added this year: nothing carried from before.
    const fresh = balances([{ ...types[0], created_at: "2026-10-01" }], [], S(), "2026-04-01")[0];
    assert.equal(fresh.carried, 0);
    assert.equal(fresh.available, 12);
  });

  test("calendar range: default this month, at most 92 days", () => {
    assert.deepEqual(calendarRange({}, "2026-10-19"), { ok: true, from: "2026-10-01", to: "2026-10-31" });
    assert.equal(calendarRange({ from: "2026-01-01", to: "2026-12-31" }, "2026-10-19").ok, false);
  });
});

/* ------------------------------------------------------- fake db */
class FakeDb {
  constructor() {
    this.users = [
      { id: 7, admin_id: 7, role: "ADMIN", username: "ravi", email: "ravi@x.in" },
      { id: 21, admin_id: 7, role: "USER", username: "asha", email: "asha@x.in" },
      { id: 22, admin_id: 7, role: "USER", username: "vik", email: "vik@x.in" },
      { id: 8, admin_id: 8, role: "ADMIN", username: "zed", email: "z@x.in" },
      { id: 31, admin_id: 8, role: "USER", username: "omar", email: "o@x.in" },
    ];
    this.settings = new Map();
    this.types = [];
    this.holidays = [];
    this.requests = [];
    this.nextType = 1;
    this.nextReq = 1;
  }

  out(rows) {
    return { rows: rows.map((r) => ({ ...r })), rowCount: rows.length };
  }

  reqRow(r) {
    return {
      ...r,
      type_name: this.types.find((t) => t.id === r.leave_type_id)?.name ?? null,
      username: this.users.find((u) => u.id === r.user_id)?.username ?? null,
    };
  }

  /** WHERE … of a leave_requests query, condition by condition. */
  whereRequests(s, p) {
    const w = s.split(" WHERE ")[1].split(/ ORDER BY | RETURNING /)[0];
    const conds = w.split(" AND ").map((c) => c.trim());
    const arg = (tok) => (tok.startsWith("$") ? p[Number(tok.slice(1).split("::")[0]) - 1] : tok.replace(/'/g, ""));
    return (row) =>
      conds.every((c) => {
        let m;
        if ((m = c.match(/^(?:r\.)?(\w+) = ANY\((\$\d+)::text\[\]\)$/))) return arg(m[2]).includes(row[m[1]]);
        if ((m = c.match(/^(?:r\.)?(\w+) IN \(([^)]*)\)$/))) return m[2].split(",").map((x) => x.trim().replace(/'/g, "")).includes(row[m[1]]);
        if ((m = c.match(/^(?:r\.)?(\w+) (=|>=|<=) (\$\d+(?:::date)?|'\w+')$/))) {
          const v = arg(m[3]);
          const x = row[m[1]];
          return m[2] === "=" ? x === v : m[2] === ">=" ? x >= v : x <= v;
        }
        throw new Error(`FakeDb: condition ${c}`);
      });
  }

  async query(sql, params = []) {
    const s = sql.replace(/\s+/g, " ").trim();
    const p = params;
    if (s.includes("FROM users u") && s.includes("WHERE u.id = $1 AND u.admin_id = $2")) {
      return this.out(this.users.filter((u) => u.id === p[0] && u.admin_id === p[1]));
    }
    if (s.includes("FROM users u") && s.includes("WHERE u.admin_id = $1 AND u.role <> 'ADMIN'")) {
      return this.out(this.users.filter((u) => u.admin_id === p[0] && u.role !== "ADMIN"));
    }
    /* settings */
    if (s.includes("FROM leave_settings WHERE admin_id = $1")) {
      const r = this.settings.get(p[0]);
      return this.out(r ? [r] : []);
    }
    if (s.startsWith("INSERT INTO leave_settings")) {
      const [admin_id, enabled, year_start_month, weekly_off, half_day, backdate_days, max_request_days] = p;
      this.settings.set(admin_id, { enabled, year_start_month, weekly_off, half_day, backdate_days, max_request_days });
      return this.out([]);
    }
    /* types */
    if (s.includes("FROM leave_types WHERE admin_id = $1 ORDER BY id")) {
      return this.out(this.types.filter((t) => t.admin_id === p[0]));
    }
    const taken = (adminId, name, id = null) =>
      this.types.some((t) => t.admin_id === adminId && t.id !== id && t.name.toLowerCase() === name.toLowerCase());
    if (s.startsWith("INSERT INTO leave_types")) {
      if (taken(p[0], p[1])) throw Object.assign(new Error("dup"), { code: "23505" });
      const q = (v) => (v === null ? null : `${Number(v).toFixed(1)}`);
      const row = {
        id: this.nextType++, admin_id: p[0], name: p[1], yearly_quota: q(p[2]), paid: p[3], carry_forward: p[4],
        max_carry: q(p[5]), active: p[6], created_at: new Date("2026-10-01T00:00:00Z"),
      };
      this.types.push(row);
      return this.out([row]);
    }
    if (s.startsWith("UPDATE leave_types SET")) {
      const t = this.types.find((x) => x.admin_id === p[0] && x.id === p[1]);
      if (!t) return this.out([]);
      const keys = [...s.matchAll(/(\w+) = \$(\d+)/g)].filter((m) => Number(m[2]) >= 3);
      const next = { ...t };
      for (const [, k, i] of keys) next[k] = p[Number(i) - 1];
      if (next.name !== t.name && taken(p[0], next.name, t.id)) throw Object.assign(new Error("dup"), { code: "23505" });
      Object.assign(t, next);
      return this.out([t]);
    }
    /* holidays */
    if (s.includes("FROM leave_holidays WHERE admin_id = $1 AND date BETWEEN")) {
      return this.out(
        this.holidays.filter((h) => h.admin_id === p[0] && h.date >= p[1] && h.date <= p[2]).sort((a, b) => a.date.localeCompare(b.date))
      );
    }
    if (s.startsWith("INSERT INTO leave_holidays")) {
      const h = this.holidays.find((x) => x.admin_id === p[0] && x.date === p[1]);
      if (h) h.name = p[2];
      else this.holidays.push({ admin_id: p[0], date: p[1], name: p[2] });
      return this.out([]);
    }
    if (s.startsWith("DELETE FROM leave_holidays")) {
      const before = this.holidays.length;
      this.holidays = this.holidays.filter((x) => !(x.admin_id === p[0] && x.date === p[1]));
      return { rows: [], rowCount: before - this.holidays.length };
    }
    /* requests */
    const R = this.requests;
    if (s.startsWith("INSERT INTO leave_requests")) {
      if (p[8] && R.some((x) => x.user_id === p[1] && x.idempotency_key === p[8])) throw Object.assign(new Error("dup"), { code: "23505" });
      const row = {
        id: this.nextReq++, admin_id: p[0], user_id: p[1], leave_type_id: p[2], from_date: p[3], to_date: p[4],
        half_day: p[5], days: Number(p[6]).toFixed(1), reason: p[7], status: "pending", decided_by: null,
        decided_at: null, decision_note: null, idempotency_key: p[8], created_at: new Date("2026-10-19T04:00:00Z"),
      };
      R.push(row);
      return this.out([{ id: row.id }]);
    }
    if (s.startsWith("UPDATE leave_requests SET status = $3")) {
      const ok = this.whereRequests(s, p);
      const hit = R.filter(ok);
      for (const x of hit) {
        Object.assign(x, { status: p[2], decided_by: p[3], decided_at: p[4], decision_note: p[5] ?? x.decision_note });
      }
      return this.out(hit.map((x) => ({ id: x.id })));
    }
    if (s.includes("FROM leave_requests r")) {
      const ok = this.whereRequests(s, p);
      const desc = / ORDER BY r\.from_date DESC/.test(s);
      const rows = R.filter(ok)
        .map((r) => this.reqRow(r))
        .sort((a, b) => (desc ? b.from_date.localeCompare(a.from_date) || b.id - a.id : a.from_date.localeCompare(b.from_date)));
      return this.out(rows);
    }
    throw new Error(`FakeDb: unhandled SQL ${s}`);
  }
}

const stubAuth = (req, res, next) => {
  const u = req.headers["x-test-user"];
  if (!u) return res.status(401).json({ message: "Unauthorized" });
  req.user = JSON.parse(u);
  next();
};

const ADMIN = { id: 7, adminId: 7, role: "ADMIN" };
const ASHA = { id: 21, adminId: 7, role: "USER" };
const VIK = { id: 22, adminId: 7, role: "USER" };
const OTHER_ADMIN = { id: 8, adminId: 8, role: "ADMIN" };
const OMAR = { id: 31, adminId: 8, role: "USER" };

/* ---------------------------------------------------------- routes */
describe("routes", () => {
  let db, server, base, clock;
  const quiet = { error: () => {} };

  beforeEach(async () => {
    db = new FakeDb();
    clock = new Date("2026-10-19T04:00:00Z"); // Monday 09:30 IST
    const app = express();
    app.use(express.json());
    app.use(createLeaveRouter({ db, auth: stubAuth, log: quiet, now: () => clock }));
    await new Promise((resolve) => {
      server = app.listen(0, resolve);
    });
    base = `http://127.0.0.1:${server.address().port}`;
  });
  afterEach(() => new Promise((resolve) => server.close(resolve)));

  const call = async (method, path, user, body) => {
    const r = await fetch(base + path, {
      method,
      headers: { "content-type": "application/json", ...(user ? { "x-test-user": JSON.stringify(user) } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    return { status: r.status, body: await r.json() };
  };

  /** The admin turns leave on, adds the default types and a holiday. */
  const setUp = async () => {
    assert.equal((await call("PUT", "/api/leave/settings", ADMIN, { enabled: true })).status, 200);
    const d = await call("POST", "/api/leave/types/defaults", ADMIN, {});
    assert.equal(d.status, 201);
    assert.equal((await call("POST", "/api/leave/holidays", ADMIN, { date: "2026-10-21", name: "Dussehra" })).status, 201);
    return Object.fromEntries(d.body.types.map((t) => [t.name, t.id]));
  };

  test("every route needs a login", async () => {
    for (const [m, p] of [
      ["GET", "/api/leave/settings"],
      ["PUT", "/api/leave/settings"],
      ["POST", "/api/leave/types"],
      ["POST", "/api/leave/types/defaults"],
      ["PUT", "/api/leave/types/1"],
      ["POST", "/api/leave/holidays"],
      ["DELETE", "/api/leave/holidays/2026-10-21"],
      ["GET", "/api/leave/me"],
      ["POST", "/api/leave/requests"],
      ["GET", "/api/leave/requests"],
      ["POST", "/api/leave/requests/1/approve"],
      ["POST", "/api/leave/requests/1/reject"],
      ["POST", "/api/leave/requests/1/cancel"],
      ["GET", "/api/leave/team/21"],
      ["GET", "/api/leave/calendar"],
    ]) {
      assert.equal((await call(m, p, null, m === "GET" || m === "DELETE" ? undefined : {})).status, 401, `${m} ${p}`);
    }
  });

  test("settings are the admin's: defaults first, then saved", async () => {
    assert.equal((await call("GET", "/api/leave/settings", ASHA)).status, 403);
    assert.equal((await call("PUT", "/api/leave/settings", ASHA, { enabled: true })).status, 403);
    let g = await call("GET", "/api/leave/settings", ADMIN);
    assert.equal(g.body.settings.enabled, false);
    assert.deepEqual(g.body.settings.weekly_off, [0]);
    assert.equal(g.body.year.label, "2026-27");
    const bad = await call("PUT", "/api/leave/settings", ADMIN, { weekly_off: [0, 1, 2, 3, 4, 5, 6] });
    assert.equal(bad.status, 400);
    const put = await call("PUT", "/api/leave/settings", ADMIN, { enabled: true, year_start_month: 1, weekly_off: [6, 0] });
    assert.equal(put.status, 200);
    g = await call("GET", "/api/leave/settings", ADMIN);
    assert.equal(g.body.settings.enabled, true);
    assert.deepEqual(g.body.settings.weekly_off, [0, 6]);
    assert.equal(g.body.settings.backdate_days, 7); // untouched fields keep their value
    assert.equal(g.body.year.label, "2026");
    // Another account sees its own (default) settings.
    assert.equal((await call("GET", "/api/leave/settings", OTHER_ADMIN)).body.settings.enabled, false);
  });

  test("leave types and holidays: add, rename, hide; names unique; defaults once", async () => {
    const ids = await setUp();
    assert.deepEqual(Object.keys(ids), ["Casual Leave", "Sick Leave", "Unpaid Leave"]);
    assert.equal((await call("POST", "/api/leave/types/defaults", ADMIN, {})).body.code, "types_exist");
    const e = await call("POST", "/api/leave/types", ADMIN, { name: "Earned Leave", yearly_quota: 15, carry_forward: true, max_carry: 10 });
    assert.equal(e.status, 201);
    assert.equal(e.body.type.max_carry, 10);
    assert.equal((await call("POST", "/api/leave/types", ADMIN, { name: "casual leave" })).body.code, "name_taken");
    const ren = await call("PUT", `/api/leave/types/${ids["Sick Leave"]}`, ADMIN, { name: "Medical Leave", yearly_quota: 8 });
    assert.equal(ren.body.type.name, "Medical Leave");
    assert.equal(ren.body.type.yearly_quota, 8);
    assert.equal((await call("PUT", `/api/leave/types/${ids["Sick Leave"]}`, ADMIN, { name: "Casual Leave" })).status, 409);
    assert.equal((await call("PUT", `/api/leave/types/${ids["Sick Leave"]}`, OTHER_ADMIN, { active: false })).status, 404);
    assert.equal((await call("PUT", "/api/leave/types/abc", ADMIN, { active: false })).status, 400);
    // Holidays: same date again renames; delete.
    await call("POST", "/api/leave/holidays", ADMIN, { date: "2026-10-21", name: "Vijayadashami" });
    let g = await call("GET", "/api/leave/settings", ADMIN);
    assert.deepEqual(g.body.holidays, [{ date: "2026-10-21", name: "Vijayadashami" }]);
    assert.equal((await call("DELETE", "/api/leave/holidays/2026-10-21", ADMIN)).status, 200);
    assert.equal((await call("DELETE", "/api/leave/holidays/2026-10-21", ADMIN)).status, 404);
  });

  test("leave off: members see it off and cannot apply", async () => {
    const me = await call("GET", "/api/leave/me", ASHA);
    assert.equal(me.body.enabled, false);
    assert.equal(me.body.balances, undefined);
    const r = await call("POST", "/api/leave/requests", ASHA, { type_id: 1, from: "2026-10-20" });
    assert.equal(r.status, 403);
    assert.equal(r.body.code, "leave_off");
  });

  test("apply → working days counted; retry safe; overlaps refused; halves of one day fit", async () => {
    const ids = await setUp();
    // Mon 19 → Mon 26: Sunday 25 and the holiday on 21 are not leave days.
    const a = await call("POST", "/api/leave/requests", ASHA, {
      type_id: ids["Casual Leave"], from: "2026-10-19", to: "2026-10-26", reason: "Family function", idempotency_key: "lv-0000001",
    });
    assert.equal(a.status, 201);
    assert.equal(a.body.request.days, 6);
    assert.equal(a.body.request.status, "pending");
    assert.equal(a.body.request.type_name, "Casual Leave");
    const again = await call("POST", "/api/leave/requests", ASHA, {
      type_id: ids["Casual Leave"], from: "2026-10-19", to: "2026-10-26", idempotency_key: "lv-0000001",
    });
    assert.equal(again.body.replayed, true);
    assert.equal(db.requests.length, 1);
    const clash = await call("POST", "/api/leave/requests", ASHA, { type_id: ids["Sick Leave"], from: "2026-10-26" });
    assert.equal(clash.status, 409);
    assert.equal(clash.body.code, "overlap");
    // Two halves of 28 Oct.
    const h1 = await call("POST", "/api/leave/requests", ASHA, { type_id: ids["Sick Leave"], from: "2026-10-28", half_day: "first" });
    const h2 = await call("POST", "/api/leave/requests", ASHA, { type_id: ids["Casual Leave"], from: "2026-10-28", half_day: "second" });
    assert.equal(h1.body.request.days, 0.5);
    assert.equal(h2.status, 201);
    assert.equal((await call("POST", "/api/leave/requests", ASHA, { type_id: ids["Casual Leave"], from: "2026-10-28", half_day: "first" })).status, 409);
    // Only a Sunday: nothing to take.
    const sun = await call("POST", "/api/leave/requests", ASHA, { type_id: ids["Casual Leave"], from: "2026-11-08" });
    assert.equal(sun.body.code, "no_working_days");
    // Another person's dates are their own.
    assert.equal((await call("POST", "/api/leave/requests", VIK, { type_id: ids["Casual Leave"], from: "2026-10-20" })).status, 201);
  });

  test("balance: pending counts, more than left is refused, unpaid has no limit", async () => {
    const ids = await setUp();
    // Casual 12: 6 pending → 6 left; 7 more is refused.
    await call("POST", "/api/leave/requests", ASHA, { type_id: ids["Casual Leave"], from: "2026-10-19", to: "2026-10-26" });
    const over = await call("POST", "/api/leave/requests", ASHA, { type_id: ids["Casual Leave"], from: "2026-11-02", to: "2026-11-09" });
    assert.equal(over.status, 409);
    assert.equal(over.body.code, "insufficient_balance");
    assert.match(over.body.message, /Only 6 day\(s\) of Casual Leave left in 2026-27/);
    const unpaid = await call("POST", "/api/leave/requests", ASHA, { type_id: ids["Unpaid Leave"], from: "2026-11-02", to: "2026-11-30" });
    assert.equal(unpaid.status, 201);
    const me = await call("GET", "/api/leave/me", ASHA);
    const casual = me.body.balances.find((b) => b.name === "Casual Leave");
    assert.deepEqual([casual.entitled, casual.used, casual.pending, casual.available], [12, 0, 6, 6]);
    assert.equal(me.body.balances.find((b) => b.name === "Unpaid Leave").available, null);
    assert.equal(me.body.requests.length, 2);
    assert.deepEqual(me.body.holidays, [{ date: "2026-10-21", name: "Dussehra" }]);
  });

  test("a hidden leave type cannot be chosen; the admin does not apply", async () => {
    const ids = await setUp();
    await call("PUT", `/api/leave/types/${ids["Sick Leave"]}`, ADMIN, { active: false });
    assert.equal((await call("POST", "/api/leave/requests", ASHA, { type_id: ids["Sick Leave"], from: "2026-10-20" })).body.code, "bad_type");
    const adm = await call("POST", "/api/leave/requests", ADMIN, { type_id: ids["Casual Leave"], from: "2026-10-20" });
    assert.equal(adm.status, 403);
    assert.equal((await call("POST", "/api/leave/requests", OMAR, { type_id: ids["Casual Leave"], from: "2026-10-20" })).status, 403); // other account: leave off there
  });

  test("admin approves / rejects; member cancels while pending; admin cancels approved", async () => {
    const ids = await setUp();
    const a = (await call("POST", "/api/leave/requests", ASHA, { type_id: ids["Casual Leave"], from: "2026-10-20" })).body.request;
    const b = (await call("POST", "/api/leave/requests", ASHA, { type_id: ids["Casual Leave"], from: "2026-10-22" })).body.request;
    const c = (await call("POST", "/api/leave/requests", ASHA, { type_id: ids["Casual Leave"], from: "2026-10-23" })).body.request;

    let list = await call("GET", "/api/leave/requests", ADMIN);
    assert.deepEqual(list.body.requests.map((r) => r.from), ["2026-10-20", "2026-10-22", "2026-10-23"]);
    assert.equal(list.body.requests[0].username, "asha");
    assert.equal((await call("GET", "/api/leave/requests", ASHA)).status, 403);

    assert.equal((await call("POST", `/api/leave/requests/${a.id}/approve`, ASHA, {})).status, 403);
    const ok = await call("POST", `/api/leave/requests/${a.id}/approve`, ADMIN, { note: "Enjoy" });
    assert.equal(ok.body.request.status, "approved");
    assert.equal(ok.body.request.decision_note, "Enjoy");
    assert.equal(ok.body.request.decided_by, 7);
    assert.equal((await call("POST", `/api/leave/requests/${a.id}/reject`, ADMIN, {})).body.code, "not_pending");
    assert.equal((await call("POST", `/api/leave/requests/${b.id}/reject`, ADMIN, { note: "Month end" })).body.request.status, "rejected");

    // The member: own pending only.
    assert.equal((await call("POST", `/api/leave/requests/${a.id}/cancel`, ASHA, {})).body.code, "not_pending");
    assert.equal((await call("POST", `/api/leave/requests/${c.id}/cancel`, VIK, {})).status, 404);
    assert.equal((await call("POST", `/api/leave/requests/${c.id}/cancel`, ASHA, {})).body.request.status, "cancelled");
    // Another account cannot touch it.
    assert.equal((await call("POST", `/api/leave/requests/${a.id}/cancel`, OTHER_ADMIN, {})).status, 404);

    let me = await call("GET", "/api/leave/me", ASHA);
    let casual = me.body.balances.find((x) => x.name === "Casual Leave");
    assert.deepEqual([casual.used, casual.pending, casual.available], [1, 0, 11]);
    assert.equal((await call("POST", `/api/leave/requests/${a.id}/cancel`, ADMIN, { note: "Needed at work" })).body.request.status, "cancelled");
    me = await call("GET", "/api/leave/me", ASHA);
    casual = me.body.balances.find((x) => x.name === "Casual Leave");
    assert.equal(casual.available, 12);

    list = await call("GET", "/api/leave/requests?status=all&user_id=21", ADMIN);
    assert.equal(list.body.requests.length, 3);
    assert.equal((await call("GET", "/api/leave/requests?status=maybe", ADMIN)).status, 400);
  });

  test("today on leave; the calendar; a member's page for the admin", async () => {
    const ids = await setUp();
    const a = (await call("POST", "/api/leave/requests", ASHA, { type_id: ids["Casual Leave"], from: "2026-10-19", to: "2026-10-20" })).body.request;
    const v = (await call("POST", "/api/leave/requests", VIK, { type_id: ids["Casual Leave"], from: "2026-10-27" })).body.request;
    let me = await call("GET", "/api/leave/me", ASHA);
    assert.equal(me.body.today.leave, null); // pending is not leave yet
    assert.equal(me.body.today.kind, "working");
    await call("POST", `/api/leave/requests/${a.id}/approve`, ADMIN, {});
    await call("POST", `/api/leave/requests/${v.id}/approve`, ADMIN, {});
    me = await call("GET", "/api/leave/me", ASHA);
    assert.equal(me.body.today.leave.id, a.id);

    const mine = await call("GET", "/api/leave/calendar", ASHA);
    assert.deepEqual([mine.body.from, mine.body.to], ["2026-10-01", "2026-10-31"]);
    assert.deepEqual(mine.body.leaves.map((r) => r.user_id), [21]); // own only
    assert.deepEqual(mine.body.weekly_off, [0]);
    assert.deepEqual(mine.body.holidays.map((h) => h.date), ["2026-10-21"]);
    const team = await call("GET", "/api/leave/calendar?from=2026-10-01&to=2026-10-31", ADMIN);
    assert.deepEqual(team.body.leaves.map((r) => r.user_id), [21, 22]);
    assert.equal((await call("GET", "/api/leave/calendar?from=2026-01-01&to=2026-12-31", ADMIN)).status, 400);

    const page = await call("GET", "/api/leave/team/21", ADMIN);
    assert.equal(page.body.member.username, "asha");
    assert.equal(page.body.balances.find((x) => x.name === "Casual Leave").used, 2);
    assert.equal((await call("GET", "/api/leave/team/31", ADMIN)).status, 404); // other account
    assert.equal((await call("GET", "/api/leave/team/21", ASHA)).status, 403);
  });
});
