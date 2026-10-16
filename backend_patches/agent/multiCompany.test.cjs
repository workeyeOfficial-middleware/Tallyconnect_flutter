// Tests for the Agent's multi-company module (node --test), run against
// tally-agent/lib/multiCompany.cjs with a fake backend and fake timers.
//   AGENT_DIR=<path to tally-agent> node --test multiCompany.test.cjs
"use strict";
const { test, describe } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const AGENT_DIR = process.env.AGENT_DIR || path.join(__dirname, "..", "..", "..", "tally-agent");
const { createMultiCompany, createSwitch, agentIdFrom, TICK_MS } = require(path.join(AGENT_DIR, "lib", "multiCompany.cjs"));

const httpErr = (status, data = {}) => Object.assign(new Error(`HTTP ${status}`), { response: { status, data } });

function fakeBackend({ config = null, lockHeldBy = null, missing = false } = {}) {
  const posts = [];
  const lock = { holder: lockHeldBy };
  return {
    posts,
    lock,
    async get(p) {
      if (missing) throw httpErr(404);
      assert.equal(p, "/company/agent-config");
      return { data: config };
    },
    async post(p, body) {
      posts.push({ p, body: JSON.parse(JSON.stringify(body)) });
      if (missing) throw httpErr(404);
      if (p === "/company/sync-lock") {
        if (body.action === "acquire") {
          if (lock.holder && lock.holder !== body.agent_id) throw httpErr(409, { code: "locked", held_by: lock.holder });
          lock.holder = body.agent_id;
        } else if (body.action === "renew") {
          if (lock.holder !== body.agent_id) throw httpErr(409, { code: "lock_lost" });
        } else if (body.action === "release" && lock.holder === body.agent_id) lock.holder = null;
      }
      return { data: { success: true } };
    },
  };
}

/** Manual timers: tick() runs the interval callback once. */
function fakeTimers() {
  let fn = null;
  return {
    setInterval: (f, ms) => {
      assert.equal(ms, TICK_MS);
      fn = f;
      return 1;
    },
    clearInterval: () => {
      fn = null;
    },
    tick: async () => fn && fn(),
    running: () => !!fn,
  };
}

describe("multi-company (Agent)", () => {
  test("enabled companies in the server's order; older server → null (old way)", async () => {
    const be = fakeBackend({
      config: {
        companies: [
          { company_guid: "CO-1", name: "GI Apr 25-26", enabled: true, starting_from: "2025-04-01" },
          { company_guid: "CO-2", name: "Old Co", enabled: false },
          { company_guid: "CO-3", name: "Ravi Traders", enabled: true },
        ],
      },
    });
    const mc = createMultiCompany({ get: be.get, post: be.post, agentId: "pc-1" });
    assert.deepEqual(await mc.enabledCompanies(), [
      { company_guid: "CO-1", name: "GI Apr 25-26", startingFrom: "2025-04-01" },
      { company_guid: "CO-3", name: "Ravi Traders", startingFrom: null },
    ]);
    const old = createMultiCompany({ ...fakeBackend({ missing: true }), agentId: "pc-1" });
    assert.equal(await old.enabledCompanies(), null);
  });

  test("a company: lock, progress every tick, renew, synced, released", async () => {
    const be = fakeBackend();
    const t = fakeTimers();
    let snap = { percent: 10, step: "syncLedgers" };
    const mc = createMultiCompany({ get: be.get, post: be.post, agentId: "pc-1", snapshot: () => snap, timers: t });
    assert.deepEqual(await mc.begin("CO-1"), { ok: true });
    assert.equal(be.lock.holder, "pc-1");
    assert.equal(mc.current(), "CO-1");
    snap = { percent: 45, step: "syncVouchers" };
    for (let i = 0; i < 4; i++) await t.tick();
    const prog = be.posts.filter((x) => x.p === "/company/sync-progress");
    assert.deepEqual(prog.at(-1).body, { company_guid: "CO-1", state: "syncing", agent_id: "pc-1", percent: 45, step: "syncVouchers" });
    assert.equal(be.posts.filter((x) => x.body.action === "renew").length, 1); // every 4th tick
    await mc.end("CO-1", { ok: true });
    assert.equal(t.running(), false);
    assert.equal(be.lock.holder, null);
    assert.deepEqual(mc.status()["CO-1"].state, "synced");
    assert.equal(be.posts.filter((x) => x.p === "/company/sync-progress").at(-1).body.percent, 100);
  });

  test("another PC has the company: skipped, reported, no progress ticker", async () => {
    const be = fakeBackend({ lockHeldBy: "pc-office" });
    const t = fakeTimers();
    const mc = createMultiCompany({ get: be.get, post: be.post, agentId: "pc-home", timers: t });
    assert.deepEqual(await mc.begin("CO-1"), { ok: false, heldBy: "pc-office" });
    assert.equal(t.running(), false);
    assert.equal(mc.status()["CO-1"].state, "locked");
    assert.equal(mc.current(), null);
  });

  test("lock taken over while syncing: noticed; failure and stop release it", async () => {
    const be = fakeBackend();
    const t = fakeTimers();
    const logs = [];
    const mc = createMultiCompany({ get: be.get, post: be.post, agentId: "pc-1", timers: t, log: (m) => logs.push(m) });
    await mc.begin("CO-1");
    be.lock.holder = "pc-2"; // expired and taken by another PC
    for (let i = 0; i < 4; i++) await t.tick();
    assert.equal(mc.lockLost(), true);
    assert.ok(logs.some((l) => /taken over/.test(l)));
    // Failure: error reported (a release of someone else's lock does nothing).
    await mc.end("CO-1", { ok: false, error: "Tally is not reachable" });
    assert.equal(mc.status()["CO-1"].state, "error");
    assert.equal(be.lock.holder, "pc-2");
    // Stop: back to idle, lock released.
    be.lock.holder = null;
    await mc.begin("CO-2");
    await mc.abort("CO-2");
    assert.equal(mc.status()["CO-2"].state, "idle");
    assert.equal(be.lock.holder, null);
    assert.equal(t.running(), false);
  });

  test("older server (no lock / progress routes): the sync still runs", async () => {
    const be = fakeBackend({ missing: true });
    const mc = createMultiCompany({ get: be.get, post: be.post, agentId: "pc-1", timers: fakeTimers() });
    assert.deepEqual(await mc.begin("CO-1"), { ok: true });
    await mc.end("CO-1", { ok: true });
  });

  test("new companies open in Tally are switched on, up to the plan limit", async () => {
    const be = fakeBackend({
      config: {
        companies: [
          { company_guid: "CO-1", name: "Averlon3", selected: true, enabled: true },
          { company_guid: "CO-2", name: "GI Apr 25-26", selected: false },
          { company_guid: "CO-3", name: "Ravi Traders", selected: false },
          { company_guid: "CO-4", name: "Closed Co", selected: false },
        ],
      },
    });
    const puts = [];
    const put = async (p, body) => {
      puts.push(body.companies[0].company_guid);
      if (puts.length > 1) throw httpErr(403, { code: "company_limit" });
      return { data: { success: true } };
    };
    const logs = [];
    const mc = createMultiCompany({ get: be.get, post: be.post, put, agentId: "pc-1", log: (m) => logs.push(m) });
    assert.deepEqual(await mc.autoEnable(["CO-1", "CO-2", "CO-3"]), { added: ["GI Apr 25-26"], limited: true });
    assert.deepEqual(puts, ["CO-2", "CO-3"]); // CO-1 already chosen; CO-4 not open in Tally
    assert.ok(logs.some((l) => /limit/.test(l)));
    // Older server: nothing happens.
    const old = createMultiCompany({ ...fakeBackend({ missing: true }), put, agentId: "pc-1" });
    assert.deepEqual(await old.autoEnable(["CO-2"]), { added: [], limited: false });
  });

  test("Agent id: created once, kept; the on/off switch (env wins)", () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "tc-mc-"));
    const a = agentIdFrom(dir, "OFFICE-PC 01");
    assert.match(a, /^OFFICE-PC01-[0-9a-f]{12}$/);
    assert.equal(agentIdFrom(dir, "other"), a);
    const sw = createSwitch(dir, {});
    assert.equal(sw.isOn(), true); // default: on (every company syncs)
    sw.set(false);
    assert.equal(sw.isOn(), false);
    sw.set(true);
    assert.equal(sw.isOn(), true);
    assert.equal(createSwitch(dir, { MULTI_COMPANY: "off" }).isOn(), false);
    assert.equal(createSwitch(dir, { MULTI_COMPANY: "off" }).fromEnv(), true);
    sw.set(false);
    assert.equal(createSwitch(dir, { MULTI_COMPANY: "on" }).isOn(), true);
    fs.rmSync(dir, { recursive: true, force: true });
  });
});
