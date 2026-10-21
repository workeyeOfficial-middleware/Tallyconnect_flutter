// Tests for the sales team attendance API (node --test). No database or
// network: an in-memory fake pg pool, a stub login and a settable clock.
// Needs only `express` installed next to the files.
import { test, describe, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import express from "express";

import {
  ACTIVE_MINUTES,
  cleanKey,
  cleanNote,
  dayStatus,
  historyDays,
  historyRange,
  istDate,
  minutesOf,
  statusCounts,
} from "../utils/attendanceCore.js";
import { closeForgotten, createAttendanceRouter } from "../utils/attendanceRouter.js";

const at = (s) => new Date(s);

/* ------------------------------------------------------------ core */
describe("core", () => {
  test("India dates: the day turns at 00:00 IST (18:30 UTC)", () => {
    assert.equal(istDate(at("2026-10-19T18:29:59Z")), "2026-10-19");
    assert.equal(istDate(at("2026-10-19T18:30:00Z")), "2026-10-20");
  });

  test("notes, retry keys, history ranges", () => {
    assert.deepEqual(cleanNote("  Met\nMehta  "), { ok: true, value: "Met Mehta" });
    assert.deepEqual(cleanNote("   "), { ok: true, value: null });
    assert.equal(cleanNote(5).ok, false);
    assert.equal(cleanNote("x".repeat(301)).ok, false);
    assert.equal(cleanKey("abc").ok, false);
    assert.equal(cleanKey("ci-1234567").value, "ci-1234567");
    assert.equal(cleanKey("bad key!!").ok, false);
    assert.deepEqual(historyRange({}, "2026-10-19"), { ok: true, from: "2026-09-20", to: "2026-10-19" });
    assert.equal(historyRange({ from: "2026-10-20", to: "2026-10-19" }, "2026-10-19").ok, false);
    assert.equal(historyRange({ from: "2026-01-01", to: "2026-10-19" }, "2026-10-19").ok, false);
    assert.equal(historyRange({ from: "2026-02-30" }, "2026-10-19").ok, false);
  });

  test("status: active / idle / checked out / absent; totals", () => {
    const now = at("2026-10-19T08:00:00Z");
    const done = { check_in_at: at("2026-10-19T03:30:00Z"), check_out_at: at("2026-10-19T05:00:00Z"), work_date: "2026-10-19" };
    const open = { check_in_at: at("2026-10-19T07:00:00Z"), check_out_at: null, last_seen_at: at("2026-10-19T07:50:00Z"), work_date: "2026-10-19" };
    assert.equal(minutesOf(done, now), 90);
    assert.equal(minutesOf(open, now), 60);
    const d = dayStatus([open, done], now);
    assert.equal(d.status, "active");
    assert.equal(d.total_minutes, 150);
    assert.equal(d.first_in, "2026-10-19T03:30:00.000Z");
    assert.equal(d.last_out, null); // still checked in
    const idle = dayStatus([{ ...open, last_seen_at: at(now.getTime() - (ACTIVE_MINUTES + 1) * 60000) }], now);
    assert.equal(idle.status, "idle");
    assert.equal(dayStatus([done], now).status, "checked_out");
    assert.equal(dayStatus([done], now).last_out, "2026-10-19T05:00:00.000Z");
    assert.equal(dayStatus([], now).status, "absent");
    const days = historyDays([done, { ...done, work_date: "2026-10-18" }], now);
    assert.deepEqual(days.map((x) => x.date), ["2026-10-19", "2026-10-18"]);
    assert.deepEqual(statusCounts([{ status: "active" }, { status: "idle" }, { status: "absent" }]), {
      active: 1, idle: 1, checked_out: 0, absent: 1, checked_in: 2, total: 3,
    });
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
    this.access = [{ admin_id: 7, user_id: 21 }, { admin_id: 8, user_id: 31 }];
    this.active = { 7: "CO-1", 8: "CO-9" };
    this.companies = [
      { admin_id: 7, company_guid: "CO-1", name: "Ravi Traders" },
      { admin_id: 7, company_guid: "CO-2", name: "Ravi Exports" },
      { admin_id: 8, company_guid: "CO-9", name: "Other Account" },
    ];
    this.sessions = [];
    this.nextId = 1;
  }

  user(u) {
    const enabled = this.access.some((a) => a.admin_id === u.admin_id && a.user_id === u.id);
    return { id: u.id, username: u.username, email: u.email, role: u.role, enabled };
  }

  out(rows) {
    return { rows: rows.map((r) => ({ ...r })), rowCount: rows.length };
  }

  async query(sql, params = []) {
    const s = sql.replace(/\s+/g, " ").trim();
    const p = params;
    if (s.includes("FROM active_company ac")) {
      const g = this.active[p[0]];
      const c = this.companies.find((x) => x.admin_id === p[0] && x.company_guid === g);
      return { rows: g ? [{ company_guid: g, company_name: c?.name ?? null }] : [] };
    }
    if (s.includes("FROM users u") && s.includes("WHERE u.id = $1 AND u.admin_id = $2")) {
      return this.out(this.users.filter((u) => u.id === p[0] && u.admin_id === p[1]).map((u) => this.user(u)));
    }
    if (s.includes("FROM users u") && s.includes("WHERE u.admin_id = $1 AND u.role <> 'ADMIN'")) {
      return this.out(this.users.filter((u) => u.admin_id === p[0] && u.role !== "ADMIN").map((u) => this.user(u)));
    }
    if (s.startsWith("INSERT INTO attendance_access")) {
      if (!this.access.some((a) => a.admin_id === p[0] && a.user_id === p[1])) this.access.push({ admin_id: p[0], user_id: p[1] });
      return this.out([]);
    }
    if (s.startsWith("DELETE FROM attendance_access")) {
      this.access = this.access.filter((a) => !(a.admin_id === p[0] && a.user_id === p[1]));
      return this.out([]);
    }

    /* sessions */
    const S = this.sessions;
    if (s.startsWith("UPDATE attendance_sessions SET check_out_at = GREATEST")) {
      const hit = S.filter((x) => !x.check_out_at && x.work_date < p[0] && (p.length < 2 || x.admin_id === p[1]));
      for (const x of hit) {
        const end = new Date(`${x.work_date}T23:59:00+05:30`);
        x.check_out_at = end < x.check_in_at ? x.check_in_at : end;
        x.closed_by = "auto";
      }
      return { rows: [], rowCount: hit.length };
    }
    if (s.startsWith("INSERT INTO attendance_sessions")) {
      if (S.some((x) => x.user_id === p[2] && !x.check_out_at)) throw Object.assign(new Error("dup"), { code: "23505" });
      if (p[6] && S.some((x) => x.user_id === p[2] && x.idempotency_key === p[6])) {
        throw Object.assign(new Error("dup"), { code: "23505" });
      }
      const row = {
        id: this.nextId++, admin_id: p[0], company_guid: p[1], user_id: p[2], work_date: p[3],
        check_in_at: p[4], last_seen_at: p[4], check_out_at: null, in_note: p[5], out_note: null,
        closed_by: null, idempotency_key: p[6],
      };
      S.push(row);
      return this.out([row]);
    }
    if (s.startsWith("UPDATE attendance_sessions SET check_out_at = $3")) {
      const x = S.find((r) => r.admin_id === p[0] && r.user_id === p[1] && !r.check_out_at);
      if (!x) return this.out([]);
      Object.assign(x, { check_out_at: p[2], last_seen_at: p[2], out_note: p[3], closed_by: "user" });
      return this.out([x]);
    }
    if (s.startsWith("UPDATE attendance_sessions SET last_seen_at = $3")) {
      const x = S.find((r) => r.admin_id === p[0] && r.user_id === p[1] && !r.check_out_at);
      if (x) x.last_seen_at = p[2];
      return this.out(x ? [{ id: x.id }] : []);
    }
    if (s.includes("FROM attendance_sessions WHERE user_id = $1 AND idempotency_key = $2")) {
      return this.out(S.filter((x) => x.user_id === p[0] && x.idempotency_key === p[1]));
    }
    if (s.includes("FROM attendance_sessions WHERE admin_id = $1 AND user_id = $2 AND check_out_at IS NULL")) {
      return this.out(S.filter((x) => x.admin_id === p[0] && x.user_id === p[1] && !x.check_out_at));
    }
    if (s.includes("WHERE admin_id = $1 AND user_id = $2 AND work_date = $3::date")) {
      return this.out(S.filter((x) => x.admin_id === p[0] && x.user_id === p[1] && x.work_date === p[2]));
    }
    if (s.includes("WHERE admin_id = $1 AND user_id = $2 AND work_date BETWEEN $3::date AND $4::date")) {
      return this.out(S.filter((x) => x.admin_id === p[0] && x.user_id === p[1] && x.work_date >= p[2] && x.work_date <= p[3]));
    }
    if (s.includes("WHERE admin_id = $1 AND company_guid = $2 AND work_date = $3::date")) {
      return this.out(S.filter((x) => x.admin_id === p[0] && x.company_guid === p[1] && x.work_date === p[2]));
    }
    if (s.includes("WHERE admin_id = $1 AND company_guid = $2 AND user_id = $3 AND work_date BETWEEN $4::date AND $5::date")) {
      return this.out(
        S.filter((x) => x.admin_id === p[0] && x.company_guid === p[1] && x.user_id === p[2] && x.work_date >= p[3] && x.work_date <= p[4])
      );
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
const ASHA = { id: 21, adminId: 7, role: "USER" }; // on the sales team
const VIK = { id: 22, adminId: 7, role: "USER" }; // not on it
const OTHER_ADMIN = { id: 8, adminId: 8, role: "ADMIN" };
const OMAR = { id: 31, adminId: 8, role: "USER" }; // other account's sales member

/* ---------------------------------------------------------- routes */
describe("routes", () => {
  let db, server, base, clock;
  const quiet = { error: () => {} };

  beforeEach(async () => {
    db = new FakeDb();
    clock = at("2026-10-19T04:00:00Z"); // 09:30 IST
    const app = express();
    app.use(express.json());
    app.use(createAttendanceRouter({ db, auth: stubAuth, log: quiet, now: () => clock }));
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
  const later = (min) => {
    clock = new Date(clock.getTime() + min * 60000);
  };

  test("every route needs a login", async () => {
    for (const [m, p] of [
      ["GET", "/api/attendance/me"],
      ["POST", "/api/attendance/check-in"],
      ["POST", "/api/attendance/check-out"],
      ["POST", "/api/attendance/ping"],
      ["GET", "/api/attendance/me/history"],
      ["GET", "/api/attendance/team"],
      ["GET", "/api/attendance/team/21/history"],
    ]) {
      assert.equal((await call(m, p, null, m === "GET" ? undefined : {})).status, 401, p);
    }
  });

  test("check in → ping → check out; one open session; server time", async () => {
    let me = await call("GET", "/api/attendance/me", ASHA);
    assert.equal(me.body.enabled, true);
    assert.equal(me.body.status, "absent");
    assert.equal(me.body.date, "2026-10-19");

    const ci = await call("POST", "/api/attendance/check-in", ASHA, { note: "Field visit", idempotency_key: "ci-0000001" });
    assert.equal(ci.status, 201);
    assert.equal(ci.body.session.check_in_at, "2026-10-19T04:00:00.000Z");
    assert.equal(ci.body.session.in_note, "Field visit");
    assert.equal(db.sessions[0].company_guid, "CO-1"); // the active company
    // The same tap retried: the same session, no second row.
    const again = await call("POST", "/api/attendance/check-in", ASHA, { idempotency_key: "ci-0000001" });
    assert.equal(again.status, 200);
    assert.equal(again.body.replayed, true);
    assert.equal(again.body.session.id, ci.body.session.id);
    // A new tap while checked in: refused.
    const dup = await call("POST", "/api/attendance/check-in", ASHA, { idempotency_key: "ci-0000002" });
    assert.equal(dup.status, 409);
    assert.equal(dup.body.code, "already_checked_in");
    assert.equal(db.sessions.length, 1);

    later(20);
    assert.equal((await call("POST", "/api/attendance/ping", ASHA, {})).body.open, true);
    assert.equal(db.sessions[0].last_seen_at.getTime(), clock.getTime());

    later(100);
    const co = await call("POST", "/api/attendance/check-out", ASHA, { note: "Done" });
    assert.equal(co.status, 200);
    assert.equal(co.body.session.minutes, 120);
    assert.equal(co.body.session.closed_by, "user");
    assert.equal((await call("POST", "/api/attendance/check-out", ASHA, {})).body.code, "not_checked_in");
    assert.equal((await call("POST", "/api/attendance/ping", ASHA, {})).body.open, false);

    // A second session the same day adds to the total.
    await call("POST", "/api/attendance/check-in", ASHA, {});
    later(10);
    me = await call("GET", "/api/attendance/me", ASHA);
    assert.equal(me.body.status, "active");
    assert.equal(me.body.sessions.length, 2);
    assert.equal(me.body.total_minutes, 130);
    assert.ok(me.body.open);
  });

  test("every team member checks in; the admin does not; bad input refused", async () => {
    // No switch needed: any team login of the account.
    assert.equal((await call("GET", "/api/attendance/me", VIK)).body.enabled, true);
    assert.equal((await call("POST", "/api/attendance/check-in", VIK, {})).status, 201);
    const a = await call("POST", "/api/attendance/check-in", ADMIN, {});
    assert.equal(a.status, 403);
    assert.equal(a.body.code, "not_on_team");
    assert.equal((await call("GET", "/api/attendance/me", ADMIN)).body.enabled, false);
    assert.equal((await call("GET", "/api/attendance/me", ADMIN)).body.is_admin, true);
    assert.equal((await call("POST", "/api/attendance/check-in", ASHA, { note: 5 })).status, 400);
    assert.equal((await call("POST", "/api/attendance/check-in", ASHA, { idempotency_key: "x" })).status, 400);
    // A login whose user row is gone (deleted member) is refused.
    assert.equal((await call("GET", "/api/attendance/me", { id: 99, adminId: 7, role: "USER" })).status, 403);
    // No company selected.
    delete db.active[7];
    assert.equal((await call("POST", "/api/attendance/check-in", ASHA, {})).body.code, "no_company");
    assert.equal(db.sessions.filter((s) => s.user_id === 21).length, 0);
  });

  test("forgotten check-out: closed at 23:59 IST of its day, marked auto", async () => {
    await call("POST", "/api/attendance/check-in", ASHA, {});
    clock = at("2026-10-20T03:00:00Z"); // next morning, 08:30 IST
    const me = await call("GET", "/api/attendance/me", ASHA);
    assert.equal(me.body.status, "absent"); // a new day, nothing open
    assert.equal(db.sessions[0].closed_by, "auto");
    assert.equal(db.sessions[0].check_out_at.toISOString(), "2026-10-19T18:29:00.000Z"); // 23:59 IST
    const h = await call("GET", "/api/attendance/me/history?from=2026-10-19&to=2026-10-20", ASHA);
    assert.equal(h.body.days[0].date, "2026-10-19");
    assert.equal(h.body.days[0].auto_closed, true);
    // Then a normal check-in today.
    assert.equal((await call("POST", "/api/attendance/check-in", ASHA, {})).status, 201);
    // The cron's job (every account): nothing left to close.
    assert.equal(await closeForgotten(db, clock), 0);
  });

  test("admin dashboard: every member; active / idle / checked out / absent", async () => {
    await call("POST", "/api/attendance/check-in", ASHA, {});
    let team = await call("GET", "/api/attendance/team", ADMIN);
    assert.equal(team.status, 200);
    assert.equal(team.body.company, "Ravi Traders");
    assert.deepEqual(team.body.members.map((m) => [m.user_id, m.status]), [[21, "active"], [22, "absent"]]);
    later(ACTIVE_MINUTES + 1); // app closed: no ping
    team = await call("GET", "/api/attendance/team", ADMIN);
    assert.equal(team.body.members[0].status, "idle");
    assert.equal(team.body.counts.checked_in, 1);
    await call("POST", "/api/attendance/ping", ASHA, {});
    assert.equal((await call("GET", "/api/attendance/team", ADMIN)).body.members[0].status, "active");
    await call("POST", "/api/attendance/check-out", ASHA, {});
    team = await call("GET", "/api/attendance/team", ADMIN);
    assert.deepEqual(team.body.counts, { active: 0, idle: 0, checked_out: 1, absent: 1, checked_in: 0, total: 2 });
    assert.equal(team.body.members[0].total_minutes, ACTIVE_MINUTES + 1);
    // Another day / bad date.
    assert.equal((await call("GET", "/api/attendance/team?date=2026-10-18", ADMIN)).body.counts.absent, 2);
    assert.equal((await call("GET", "/api/attendance/team?date=19-10-2026", ADMIN)).status, 400);
    // Members cannot see the dashboard.
    assert.equal((await call("GET", "/api/attendance/team", ASHA)).status, 403);
  });

  test("company: the dashboard shows the active company's check-ins", async () => {
    await call("POST", "/api/attendance/check-in", ASHA, {});
    db.active[7] = "CO-2";
    const team = await call("GET", "/api/attendance/team", ADMIN);
    assert.equal(team.body.company, "Ravi Exports");
    assert.equal(team.body.members[0].status, "absent");
    db.active[7] = "CO-1";
    assert.equal((await call("GET", "/api/attendance/team", ADMIN)).body.members[0].status, "active");
  });

  test("accounts are kept apart", async () => {
    await call("POST", "/api/attendance/check-in", ASHA, {});
    await call("POST", "/api/attendance/check-in", OMAR, {});
    const b = await call("GET", "/api/attendance/team", OTHER_ADMIN);
    assert.deepEqual(b.body.members.map((m) => m.user_id), [31]);
    // Another account's member: not found, history refused.
    assert.equal((await call("GET", "/api/attendance/team/21/history", OTHER_ADMIN)).status, 404);
    // A forged adminId in a member's token does not match the user row.
    assert.equal((await call("GET", "/api/attendance/me", { id: 21, adminId: 8, role: "USER" })).status, 403);
    // Each member's own history has only their sessions.
    const h = await call("GET", "/api/attendance/me/history", OMAR);
    assert.equal(h.body.days[0].sessions.length, 1);
    assert.equal(db.sessions.find((s) => s.user_id === 31).admin_id, 8);
  });

  test("member history for the admin", async () => {
    await call("POST", "/api/attendance/check-in", ASHA, {});
    later(60);
    await call("POST", "/api/attendance/check-out", ASHA, {});
    const h = await call("GET", "/api/attendance/team/21/history?from=2026-10-01&to=2026-10-19", ADMIN);
    assert.equal(h.status, 200);
    assert.equal(h.body.member.username, "asha");
    assert.equal(h.body.days[0].total_minutes, 60);
    assert.equal((await call("GET", "/api/attendance/team/7/history", ADMIN)).status, 404); // the admin
    assert.equal((await call("GET", "/api/attendance/team/abc/history", ADMIN)).status, 400);
    assert.equal((await call("GET", "/api/attendance/team/21/history?from=2026-01-01", ADMIN)).status, 400);
    // A member cannot see others' history.
    assert.equal((await call("GET", "/api/attendance/team/22/history", ASHA)).status, 403);
  });
});
