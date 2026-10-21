// Tests for the Agent's sync recovery (node --test), run against
// tally-agent/lib/syncRecovery.cjs + lib/tallyGuard.cjs with a local fake
// Tally that stops answering and recovers — no real Tally, no network.
//   AGENT_DIR=<path to tally-agent> node --test syncRecovery.test.cjs
"use strict";
const { test, describe } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");

const AGENT_DIR = process.env.AGENT_DIR || path.join(__dirname, "..", "..", "..", "tally-agent");
const rec = require(path.join(AGENT_DIR, "lib", "syncRecovery.cjs"));
const { createTallyGuard } = require(path.join(AGENT_DIR, "lib", "tallyGuard.cjs"));
const axios = require(path.join(AGENT_DIR, "node_modules", "axios"));

const MIN = 60 * 1000;
const co = (g) => ({ company_guid: g, name: g });

/** A fake Tally: requests whose body contains a word in `hangOn` get no answer. */
function fakeTally() {
  const t = { hits: [], hangOn: new Set(), pingOk: true, server: null, url: "" };
  t.server = http.createServer((req, res) => {
    let b = "";
    req.on("data", (c) => (b += c));
    req.on("end", () => {
      const ping = b.includes("TCGuardPing");
      t.hits.push(ping ? "ping" : b);
      if (ping ? !t.pingOk : [...t.hangOn].some((w) => b.includes(w))) return; // no answer
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

function guarded(t) {
  const client = axios.create({ httpAgent: new http.Agent({ keepAlive: false }), timeout: 300 });
  const guard = createTallyGuard({
    ping: async () => {
      try {
        await client.post(t.url, "<TCGuardPing/>", { timeout: 200, tcGuardBypass: true });
        return true;
      } catch (e) {
        return false;
      }
    },
    config: { pingEveryMs: 40, restMs: 60, gapMinMs: 0, gapFactor: 0, gapMaxMs: 0 },
  });
  guard.attach(client);
  return { client, guard };
}

describe("company order", () => {
  test("starts after the company that finished last", () => {
    const cs = [co("A"), co("B"), co("C")];
    assert.deepEqual(rec.orderCompanies(cs, {}).map((c) => c.company_guid), ["A", "B", "C"]);
    assert.deepEqual(rec.orderCompanies(cs, { lastDone: "A" }).map((c) => c.company_guid), ["B", "C", "A"]);
    assert.deepEqual(rec.orderCompanies(cs, { lastDone: "C" }).map((c) => c.company_guid), ["A", "B", "C"]);
    assert.deepEqual(rec.orderCompanies(cs, { lastDone: "gone" }).map((c) => c.company_guid), ["A", "B", "C"]);
  });

  test("a company that froze Tally goes last (for a while), so the others sync", () => {
    const cs = [co("RAJ"), co("GI"), co("TEST")];
    const now = Date.now();
    // Rajlaxmi froze Tally: GI and TEST first.
    let st = rec.afterCompany({}, "RAJ", true, now);
    assert.deepEqual(rec.orderCompanies(cs, st, now).map((c) => c.company_guid), ["GI", "TEST", "RAJ"]);
    // GI finished: next run starts after GI, Rajlaxmi still last.
    st = rec.afterCompany(st, "GI", false, now);
    assert.deepEqual(rec.orderCompanies(cs, st, now).map((c) => c.company_guid), ["TEST", "GI", "RAJ"]);
    // After the hold time Rajlaxmi gets its normal turn again.
    assert.deepEqual(
      rec.orderCompanies(cs, st, now + 7 * 60 * MIN).map((c) => c.company_guid),
      ["TEST", "RAJ", "GI"]
    );
    // Rajlaxmi finishing clears its mark.
    st = rec.afterCompany(st, "RAJ", false, now);
    assert.equal(st.tripped.RAJ, undefined);
    assert.equal(st.lastDone, "RAJ");
  });
});

describe("postponing a step that freezes Tally", () => {
  test("longer each time (30 min, 1 h, 2 h …) up to 12 h; a fine run forgets it", () => {
    const now = 1_000_000;
    let b = {};
    const waits = [];
    for (let i = 0; i < 7; i++) {
      b = rec.recordStepFreeze(b, "syncVouchers", now);
      waits.push((b.syncVouchers.until - now) / MIN);
    }
    assert.deepEqual(waits, [30, 60, 120, 240, 480, 720, 720]);
    assert.equal(rec.stepBlocked(b, "syncVouchers", now).blocked, true);
    assert.equal(rec.stepBlocked(b, "syncVouchers", now + 721 * MIN).blocked, false);
    assert.equal(rec.stepBlocked(b, "syncLedgers", now).blocked, false);
    b = rec.clearStep(b, "syncVouchers");
    assert.deepEqual(b, {});
  });
});

describe("waiting for Tally (guard)", () => {
  test("waitUntilReady: true once Tally answers again (after its rest); false when it never does", async () => {
    const t = await fakeTally();
    const { client, guard } = guarded(t);
    try {
      t.hangOn.add("heavy");
      await assert.rejects(client.post(t.url, "<heavy/>"));
      assert.equal(guard.state, "open");
      // Tally still stuck (the tiny check gets no answer): gives up in time.
      t.pingOk = false;
      const t0 = Date.now();
      assert.equal(await guard.waitUntilReady(250, { tickMs: 20 }), false);
      assert.ok(Date.now() - t0 < 1500);
      // Tally recovers: ready after the checks + rest.
      t.pingOk = true;
      assert.equal(await guard.waitUntilReady(2000, { tickMs: 20 }), true);
      assert.equal(guard.state, "closed");
    } finally {
      t.server.close();
    }
  });
});

describe("a step that makes Tally stop answering", () => {
  /** A step reading pages 1..3, saving its position after each page. */
  function pagedStep(client, t, store, pos) {
    return async () => {
      for (let p = pos.next; p <= 3; p++) {
        await client.post(t.url, `<page${p}/>`);
        store.set(`page${p}`, (store.get(`page${p}`) || 0) + 1); // server upsert by key
        pos.next = p + 1; // position saved only after the page is stored
      }
    };
  }

  test("waits, then continues from the same page: every page once, no duplicate, position not held back", async () => {
    const t = await fakeTally();
    const { client, guard } = guarded(t);
    const store = new Map();
    const pos = { next: 1 };
    let backoff = {};
    const logs = [];
    try {
      t.hangOn.add("page2"); // Tally stops answering on page 2 …
      const wait = async () => {
        t.hangOn.clear(); // … and recovers.
        return guard.waitUntilReady(3000, { tickMs: 20 });
      };
      const r = await rec.runStepWithRecovery({
        label: "syncVouchers",
        fn: pagedStep(client, t, store, pos),
        guard,
        wait,
        loadBackoff: () => backoff,
        saveBackoff: (b) => (backoff = b),
        log: (m) => logs.push(m),
      });
      assert.equal(r.ok, true);
      assert.equal(r.froze, false); // recovered: the company's position may advance
      assert.deepEqual([...store.keys()].sort(), ["page1", "page2", "page3"]);
      assert.equal(store.get("page1"), 1); // page 1 was not read again
      assert.equal(store.get("page2"), 1);
      const pages = t.hits.filter((h) => h !== "ping");
      assert.deepEqual(pages, ["<page1/>", "<page2/>", "<page2/>", "<page3/>"]);
      assert.ok(logs.some((m) => m.includes("continuing from where it stopped")));
      assert.deepEqual(backoff, {});
    } finally {
      t.server.close();
    }
  });

  test("freezes Tally again: postponed (not sent next time), the company's position is held", async () => {
    const t = await fakeTally();
    const { client, guard } = guarded(t);
    let backoff = {};
    try {
      t.hangOn.add("page2"); // stays heavy
      const run = () =>
        rec.runStepWithRecovery({
          label: "syncVouchers",
          fn: pagedStep(client, t, new Map(), { next: 1 }),
          guard,
          wait: () => guard.waitUntilReady(3000, { tickMs: 20 }),
          loadBackoff: () => backoff,
          saveBackoff: (b) => (backoff = b),
        });
      const r = await run();
      assert.equal(r.froze, true);
      assert.equal(r.ok, false);
      assert.equal(backoff.syncVouchers.count, 1);
      // Next sync: not sent at all while postponed.
      await guard.waitUntilReady(3000, { tickMs: 20 });
      const before = t.hits.length;
      const again = await run();
      assert.equal(again.postponed, true);
      assert.equal(t.hits.length, before);
    } finally {
      t.server.close();
    }
  });

  test("Tally does not recover: postponed, step not retried", async () => {
    const t = await fakeTally();
    const { client, guard } = guarded(t);
    let backoff = {};
    let calls = 0;
    try {
      t.hangOn.add("x");
      const r = await rec.runStepWithRecovery({
        label: "fetchFullStockData",
        fn: async () => {
          calls++;
          await client.post(t.url, "<x/>");
        },
        guard,
        wait: async () => false,
        loadBackoff: () => backoff,
        saveBackoff: (b) => (backoff = b),
      });
      assert.equal(r.froze, true);
      assert.equal(calls, 1);
      assert.ok(backoff.fetchFullStockData.until > Date.now());
    } finally {
      t.server.close();
    }
  });

  test("Tally busy before the step and does not recover: skipped, nothing sent", async () => {
    let calls = 0;
    const r = await rec.runStepWithRecovery({
      label: "syncLedgers",
      fn: async () => calls++,
      guard: { ready: async () => false, trips: 1 },
      wait: async () => false,
      loadBackoff: () => ({}),
      saveBackoff: () => {},
    });
    assert.equal(r.skipped, true);
    assert.equal(calls, 0);
  });
});

describe("agent.cjs: no request that sorts every voucher", () => {
  const src = fs.readFileSync(path.join(AGENT_DIR, "agent.cjs"), "utf8");
  test("the earliest-voucher sort is gone", () => {
    assert.ok(!src.includes("fetchTallyVoucherDateRange"));
    assert.ok(!/<COLLECTION NAME="VoucherDates">/.test(src));
  });
  test("a period Tally did not give is saved (not asked again every sync)", () => {
    assert.match(src, /rememberTallyPeriod\(companyGuid, found, \{ allowDefault: true \}\)/);
  });
  test("the step runner waits and resumes through lib/syncRecovery", () => {
    assert.match(src, /syncRecovery\.runStepWithRecovery\(/);
    assert.match(src, /syncRecovery\.orderCompanies\(/);
    assert.match(src, /const cutShort = runIncomplete;/);
  });
});
