// Tests for the multi-company routes (node --test): selection + plan
// limit, per-company lock, per-company progress, account isolation.
// In-memory fake database, stub login.
import { test, describe, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import express from "express";

import { createCompanySyncRouter } from "../utils/companySyncRouter.js";

class FakeDb {
  constructor() {
    this.companies = [
      { admin_id: 7, company_guid: "CO-1", name: "GI Apr 25-26" },
      { admin_id: 7, company_guid: "CO-2", name: "Ravi Traders" },
      { admin_id: 7, company_guid: "CO-3", name: "Old Co 2019" },
      // The same Tally company in another account: its own row.
      { admin_id: 8, company_guid: "CO-1", name: "GI Apr 25-26" },
    ];
    this.selected = [{ admin_id: 7, company_guid: "CO-1", enabled: true, sync_order: null, selected_at: 1, starting_from: "2025-04" }];
    this.active = { 7: "CO-1" };
    this.locks = [];
    this.status = [];
    this.sql = [];
  }
  async query(sql, p = []) {
    const s = sql.replace(/\s+/g, " ").trim();
    this.sql.push(s);
    const sel = (a, g) => this.selected.find((x) => x.admin_id === a && x.company_guid === g);
    if (s.startsWith("SELECT 1 FROM companies")) {
      const r = this.companies.filter((c) => c.admin_id === p[0] && c.company_guid === p[1]);
      return { rows: r, rowCount: r.length };
    }
    if (s.startsWith("SELECT c.company_guid, c.name, (sc.company_guid IS NOT NULL) AS selected")) {
      const rows = this.companies
        .filter((c) => c.admin_id === p[0])
        .map((c) => {
          const x = sel(c.admin_id, c.company_guid);
          return { company_guid: c.company_guid, name: c.name, selected: !!x, enabled: x ? x.enabled : false, sync_order: x?.sync_order ?? null, starting_from: x?.starting_from ?? null, _at: x?.selected_at ?? 1e9 };
        })
        .sort((a, b) => (a.selected === b.selected ? (a.sync_order ?? 1e9) - (b.sync_order ?? 1e9) || a._at - b._at : a.selected ? -1 : 1));
      return { rows };
    }
    if (s.startsWith("SELECT company_guid FROM active_company")) {
      return { rows: this.active[p[0]] ? [{ company_guid: this.active[p[0]] }] : [] };
    }
    if (s.startsWith("INSERT INTO active_company")) {
      this.active[p[0]] = p[1];
      return { rows: [] };
    }
    if (s.startsWith("INSERT INTO selected_companies")) {
      const x = sel(p[0], p[1]);
      if (x) {
        x.enabled = p[2];
        if (p[3] !== null) x.sync_order = p[3];
      } else this.selected.push({ admin_id: p[0], company_guid: p[1], enabled: p[2], sync_order: p[3], selected_at: this.selected.length + 1 });
      return { rows: [] };
    }
    if (s.startsWith("DELETE FROM company_sync_locks")) {
      this.locks = this.locks.filter((l) => !(l.admin_id === p[0] && l.company_guid === p[1] && l.agent_id === p[2]));
      return { rows: [] };
    }
    if (s.startsWith("UPDATE company_sync_locks SET expires_at")) {
      const l = this.locks.find((x) => x.admin_id === p[0] && x.company_guid === p[1] && x.agent_id === p[2]);
      if (!l) return { rows: [], rowCount: 0 };
      l.expires_at = p[3];
      return { rows: [{ expires_at: l.expires_at }], rowCount: 1 };
    }
    if (s.startsWith("INSERT INTO company_sync_locks")) {
      const [a, g, agent, exp, nowAt] = p;
      const l = this.locks.find((x) => x.admin_id === a && x.company_guid === g);
      if (!l) {
        this.locks.push({ admin_id: a, company_guid: g, agent_id: agent, expires_at: exp });
        return { rows: [{ agent_id: agent, expires_at: exp }], rowCount: 1 };
      }
      if (l.agent_id === agent || l.expires_at < nowAt) {
        Object.assign(l, { agent_id: agent, expires_at: exp });
        return { rows: [{ agent_id: agent, expires_at: exp }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    }
    if (s.startsWith("SELECT agent_id, expires_at FROM company_sync_locks")) {
      return { rows: this.locks.filter((x) => x.admin_id === p[0] && x.company_guid === p[1]) };
    }
    if (s.startsWith("INSERT INTO agent_status")) {
      const [a, g, inProg, state, step, pct, err, agent] = p;
      let x = this.status.find((y) => y.admin_id === a && y.company_guid === g);
      if (!x) {
        x = { admin_id: a, company_guid: g };
        this.status.push(x);
      }
      Object.assign(x, { sync_in_progress: inProg, state, step, percent: pct, last_error: err, agent_id: agent ?? x.agent_id, progress_at: this.clock });
      return { rows: [] };
    }
    if (s.startsWith("SELECT c.company_guid, c.name, COALESCE(sc.enabled, FALSE) AS enabled, s.state")) {
      return {
        rows: this.companies
          .filter((c) => c.admin_id === p[0])
          .map((c) => {
            const x = sel(c.admin_id, c.company_guid);
            const st = this.status.find((y) => y.admin_id === c.admin_id && y.company_guid === c.company_guid) || {};
            return { company_guid: c.company_guid, name: c.name, enabled: x ? x.enabled : false, ...st };
          }),
      };
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
const ADMIN = { id: 7, adminId: 7, role: "ADMIN", email: "ravi@x.in" };
const USER = { id: 21, adminId: 7, role: "USER", email: "asha@x.in" };
const OTHER = { id: 8, adminId: 8, role: "ADMIN", email: "ca@x.in" };

describe("multi-company routes", () => {
  let db, server, base, limit, added, clock;
  beforeEach(async () => {
    db = new FakeDb();
    limit = 2;
    added = [];
    clock = new Date("2026-10-16T10:00:00Z");
    db.clock = clock;
    const app = express();
    app.use(express.json());
    app.use(
      "/company",
      createCompanySyncRouter({
        db,
        auth: stubAuth,
        getCompanyLimit: async () => limit,
        onCompaniesAdded: async (u, n) => added.push([u.email, n]),
        log: { error: () => {} },
        now: () => clock,
      })
    );
    await new Promise((r) => {
      server = app.listen(0, r);
    });
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

  test("agent-config: this account's companies, enabled first; limit on request", async () => {
    const r = await call("GET", "/company/agent-config?limit=1", ADMIN);
    assert.equal(r.status, 200);
    assert.deepEqual(r.body.companies.map((c) => [c.company_guid, c.enabled]), [["CO-1", true], ["CO-2", false], ["CO-3", false]]);
    assert.equal(r.body.active_company_guid, "CO-1");
    assert.equal(r.body.company_limit, 2);
    assert.ok(r.body.version.includes("CO-1:1"));
    // The other account sees only its own copy.
    const o = await call("GET", "/company/agent-config", OTHER);
    assert.deepEqual(o.body.companies.map((c) => c.company_guid), ["CO-1"]);
    assert.equal(o.body.companies[0].enabled, false);
  });

  test("selection: enable within the plan limit; off is kept (never deleted)", async () => {
    const on = await call("PUT", "/company/selection", ADMIN, { companies: [{ company_guid: "CO-2", enabled: true, sync_order: 2 }] });
    assert.equal(on.status, 200);
    assert.deepEqual(added, [["ravi@x.in", 1]]); // licence heartbeat for the new one
    // A third would exceed the plan (2).
    const over = await call("PUT", "/company/selection", ADMIN, { companies: [{ company_guid: "CO-3", enabled: true }] });
    assert.equal(over.status, 403);
    assert.equal(over.body.code, "company_limit");
    assert.match(over.body.message, /allows 2 companies/);
    // Off + on in one call stays within the limit.
    const swap = await call("PUT", "/company/selection", ADMIN, {
      companies: [{ company_guid: "CO-1", enabled: false }, { company_guid: "CO-3", enabled: true }],
    });
    assert.equal(swap.status, 200);
    assert.deepEqual(swap.body.companies.filter((c) => c.enabled).map((c) => c.company_guid).sort(), ["CO-2", "CO-3"]);
    // CO-1 is switched off, not removed (its data must stay).
    assert.equal(db.selected.find((x) => x.company_guid === "CO-1").enabled, false);
    assert.ok(!db.sql.some((q) => /DELETE FROM (selected_companies|companies)/.test(q)));
    // The app's company moved to an enabled one.
    assert.notEqual(db.active[7], "CO-1");
    // Turning off never needs room in the plan.
    limit = 0;
    assert.equal((await call("PUT", "/company/selection", ADMIN, { companies: [{ company_guid: "CO-3", enabled: false }] })).status, 200);
  });

  test("selection: admin only; own companies only; values checked", async () => {
    assert.equal((await call("PUT", "/company/selection", USER, { companies: [{ company_guid: "CO-2", enabled: true }] })).status, 403);
    assert.equal((await call("PUT", "/company/selection", OTHER, { companies: [{ company_guid: "CO-2", enabled: true }] })).body.code, "unknown_company");
    assert.equal((await call("PUT", "/company/selection", ADMIN, { companies: [{ company_guid: "CO-2", enabled: "yes" }] })).status, 400);
    assert.equal((await call("PUT", "/company/selection", ADMIN, { companies: [] })).status, 400);
    assert.equal((await call("GET", "/company/agent-config", null)).status, 401);
  });

  test("lock: one Agent per company; renew; release; an expired lock is taken over", async () => {
    const lock = (agent, action, g = "CO-1", user = ADMIN) => call("POST", "/company/sync-lock", user, { company_guid: g, agent_id: agent, action });
    assert.equal((await lock("pc-office-1", "acquire")).body.acquired, true);
    const busy = await lock("pc-home-2", "acquire");
    assert.equal(busy.status, 409);
    assert.equal(busy.body.code, "locked");
    assert.equal(busy.body.held_by, "pc-office-1");
    assert.equal((await lock("pc-office-1", "acquire")).status, 200); // again: still ours
    assert.equal((await lock("pc-office-1", "renew")).status, 200);
    assert.equal((await lock("pc-home-2", "renew")).body.code, "lock_lost");
    // Another company is free at the same time.
    assert.equal((await lock("pc-home-2", "acquire", "CO-2")).status, 200);
    // The other account's lock on ITS copy of the same company is separate.
    assert.equal((await lock("ca-pc-9", "acquire", "CO-1", OTHER)).status, 200);
    // After expiry (3 min default) someone else may take it.
    clock = new Date(clock.getTime() + 4 * 60 * 1000);
    assert.equal((await lock("pc-home-2", "acquire")).status, 200);
    assert.equal((await lock("pc-office-1", "renew")).body.code, "lock_lost");
    await lock("pc-home-2", "release");
    assert.equal((await lock("pc-office-1", "acquire")).status, 200);
    // Not this account's company / bad agent id.
    assert.equal((await lock("pc-office-1", "acquire", "CO-9")).body.code, "no_company");
    assert.equal((await call("POST", "/company/sync-lock", ADMIN, { company_guid: "CO-1", agent_id: "x", action: "acquire" })).status, 400);
  });

  test("progress per company; stalled when silent; isolated per account", async () => {
    const prog = (body, user = ADMIN) => call("POST", "/company/sync-progress", user, body);
    assert.equal((await prog({ company_guid: "CO-1", state: "syncing", step: "syncVouchers", percent: 45.4, agent_id: "pc-office-1" })).status, 200);
    assert.equal((await prog({ company_guid: "CO-2", state: "not_open" })).status, 200);
    assert.equal((await prog({ company_guid: "CO-3", state: "error", error: "Tally is not reachable" })).status, 200);
    let st = (await call("GET", "/company/sync-status", USER)).body.companies; // team users may read
    const by = Object.fromEntries(st.map((c) => [c.company_guid, c]));
    assert.deepEqual([by["CO-1"].state, by["CO-1"].percent, by["CO-1"].step], ["syncing", 45, "syncVouchers"]);
    assert.equal(by["CO-2"].state, "not_open");
    assert.equal(by["CO-3"].last_error, "Tally is not reachable");
    // Nothing heard for > 5 minutes: shown as stalled.
    clock = new Date(clock.getTime() + 6 * 60 * 1000);
    st = (await call("GET", "/company/sync-status", ADMIN)).body.companies;
    assert.equal(st.find((c) => c.company_guid === "CO-1").state, "stalled");
    // The other account: only its own copy, nothing from this account.
    const o = (await call("GET", "/company/sync-status", OTHER)).body.companies;
    assert.deepEqual(o.map((c) => [c.company_guid, c.state]), [["CO-1", "idle"]]);
    assert.equal((await prog({ company_guid: "CO-2", state: "syncing" }, OTHER)).body.code, "no_company");
    assert.equal((await prog({ company_guid: "CO-1", state: "dancing" })).status, 400);
  });
});
