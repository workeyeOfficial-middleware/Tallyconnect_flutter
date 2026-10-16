// Tests for the Agent's Tally guard (node --test), run against
// tally-agent/lib/tallyGuard.cjs with a local fake Tally — no real Tally.
//   AGENT_DIR=<path to tally-agent> node --test tallyGuard.test.cjs
"use strict";
const { test, describe } = require("node:test");
const assert = require("node:assert/strict");
const http = require("node:http");
const path = require("node:path");

const AGENT_DIR = process.env.AGENT_DIR || path.join(__dirname, "..", "..", "..", "tally-agent");
const { createTallyGuard, isTripError } = require(path.join(AGENT_DIR, "lib", "tallyGuard.cjs"));
const axios = require(path.join(AGENT_DIR, "node_modules", "axios"));

/** A fake Tally: `hang` = never answers (except the ping while `pingOk`). */
function fakeTally() {
  const t = { hits: [], hang: false, pingOk: true, server: null, url: "" };
  t.server = http.createServer((req, res) => {
    let b = "";
    req.on("data", (c) => (b += c));
    req.on("end", () => {
      const ping = b.includes("TCGuardPing");
      t.hits.push(ping ? "ping" : b.slice(0, 20));
      if (ping ? !t.pingOk : t.hang) return; // no answer
      res.end("<ENVELOPE><OK/></ENVELOPE>");
    });
  });
  return new Promise((resolve) =>
    t.server.listen(0, "127.0.0.1", () => {
      t.url = `http://127.0.0.1:${t.server.address().port}`;
      resolve(t);
    })
  );
}

function guardedClient(t, config) {
  const client = axios.create({ httpAgent: new http.Agent({ keepAlive: true, maxSockets: 1 }), timeout: 300 });
  const logs = [];
  const guard = createTallyGuard({
    ping: async () => {
      try {
        await client.post(t.url, "<TCGuardPing/>", { timeout: 200, tcGuardBypass: true });
        return true;
      } catch (e) {
        return false;
      }
    },
    log: (m) => logs.push(m),
    config: { pingEveryMs: 50, restMs: 100, gapMinMs: 0, gapFactor: 0, gapMaxMs: 0, ...config },
  });
  guard.attach(client);
  return { client, guard, logs };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

describe("Tally guard", () => {
  test("a timeout trips it: later requests are refused without reaching Tally", async () => {
    const t = await fakeTally();
    const { client, guard, logs } = guardedClient(t, { pingEveryMs: 10000 });
    try {
      await client.post(t.url, "<FIRST/>");
      t.hang = true;
      await assert.rejects(client.post(t.url, "<STUCK/>"), (e) => e.code === "ECONNABORTED");
      assert.equal(guard.state, "open");
      assert.equal(guard.trips, 1);
      const before = t.hits.length;
      for (let i = 0; i < 5; i++) {
        await assert.rejects(client.post(t.url, `<MORE${i}/>`), (e) => e.code === "TALLY_BUSY");
      }
      assert.equal(t.hits.length, before, "nothing more was sent to the stuck Tally");
      assert.match(logs.join("\n"), /did not answer/);
    } finally {
      t.server.close();
    }
  });

  test("recovers only after Tally answers the check AND has rested", async () => {
    const t = await fakeTally();
    const { client, guard } = guardedClient(t);
    try {
      t.hang = true;
      t.pingOk = false;
      await assert.rejects(client.post(t.url, "<STUCK/>"));
      await sleep(70);
      assert.equal(await guard.ready(), false, "check not answered: still closed off");
      assert.equal(guard.state, "open");
      t.pingOk = true;
      await sleep(70);
      assert.equal(await guard.ready(), false, "answered, but resting first");
      assert.equal(guard.state, "resting");
      await assert.rejects(client.post(t.url, "<WHILE-RESTING/>"), (e) => e.code === "TALLY_BUSY");
      await sleep(120);
      t.hang = false;
      const r = await client.post(t.url, "<AFTER/>");
      assert.match(String(r.data), /ENVELOPE/);
      assert.equal(guard.state, "closed");
    } finally {
      t.server.close();
    }
  });

  test("checks Tally at most every pingEveryMs, never in a burst", async () => {
    const t = await fakeTally();
    const { client, guard } = guardedClient(t, { pingEveryMs: 1000 });
    try {
      t.hang = true;
      t.pingOk = false;
      await assert.rejects(client.post(t.url, "<STUCK/>"));
      for (let i = 0; i < 10; i++) await assert.rejects(client.post(t.url, `<X${i}/>`));
      assert.equal(t.hits.filter((h) => h === "ping").length, 0, "no check before pingEveryMs");
      assert.equal(guard.state, "open");
    } finally {
      t.server.close();
    }
  });

  test("Tally not running (ECONNREFUSED) trips it too", async () => {
    const t = await fakeTally();
    const url = t.url;
    await new Promise((r) => t.server.close(r));
    const { client, guard } = guardedClient({ url }, { pingEveryMs: 10000 });
    await assert.rejects(client.post(url, "<X/>"), (e) => e.code === "ECONNREFUSED");
    assert.equal(guard.state, "open");
    await assert.rejects(client.post(url, "<Y/>"), (e) => e.code === "TALLY_BUSY");
  });

  test("bypass requests (UI test connection) are never held back", async () => {
    const t = await fakeTally();
    const { client, guard } = guardedClient(t, { pingEveryMs: 10000 });
    try {
      t.hang = true;
      await assert.rejects(client.post(t.url, "<STUCK/>"));
      assert.equal(guard.state, "open");
      t.hang = false;
      const r = await client.post(t.url, "<UI-TEST/>", { tcGuardBypass: true });
      assert.match(String(r.data), /ENVELOPE/);
      assert.equal(guard.state, "open", "a bypass request does not reopen the gate either");
    } finally {
      t.server.close();
    }
  });

  test("other errors (e.g. a 500 answer) do not trip it", async () => {
    const server = http.createServer((req, res) => {
      res.statusCode = 500;
      res.end("x");
    });
    await new Promise((r) => server.listen(0, "127.0.0.1", r));
    const url = `http://127.0.0.1:${server.address().port}`;
    const { client, guard } = guardedClient({ url });
    try {
      await assert.rejects(client.post(url, "<X/>"));
      assert.equal(guard.state, "closed");
    } finally {
      server.close();
    }
  });

  test("gap: the next request waits after the previous one, longer after a slow one", async () => {
    let now = 0;
    const waits = [];
    const guard = createTallyGuard({
      ping: async () => true,
      clock: () => now,
      sleep: async (ms) => {
        waits.push(ms);
        now += ms;
      },
      config: { gapMinMs: 300, gapFactor: 0.5, gapMaxMs: 10000 },
    });
    let s = await guard.beforeRequest(); // first request: no wait
    now += 100; // took 0.1 s
    guard.afterRequest(s);
    assert.equal(guard.gapMs, 300, "fast request → the minimum gap");
    s = await guard.beforeRequest();
    now += 8000; // took 8 s
    guard.afterRequest(s);
    assert.equal(guard.gapMs, 4000, "slow request → half its time");
    s = await guard.beforeRequest();
    now += 60000;
    guard.afterRequest(s);
    assert.equal(guard.gapMs, 10000, "capped");
    assert.deepEqual(waits, [300, 4000]);
  });

  test("isTripError", () => {
    assert.equal(isTripError({ code: "ECONNABORTED", message: "timeout of 600000ms exceeded" }), true);
    assert.equal(isTripError({ message: "timeout of 300000ms exceeded" }), true);
    assert.equal(isTripError({ code: "ECONNRESET" }), true);
    assert.equal(isTripError({ code: "TALLY_BUSY", message: "timeout" }), false);
    assert.equal(isTripError({ message: "Request failed with status code 500" }), false);
  });
});
