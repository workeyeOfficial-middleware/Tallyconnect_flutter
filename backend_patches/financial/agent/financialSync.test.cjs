// Tests for the Agent's financial statements sync (node --test), run
// against tally-agent/lib/financialSync.cjs with a fake Tally and a fake
// backend, plus the voucher line merge. No Tally, no network.
//   AGENT_DIR=<path to tally-agent> node --test financialSync.test.cjs
"use strict";
const { test, describe } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const AGENT_DIR = process.env.AGENT_DIR || path.join(__dirname, "..", "..", "..", "..", "tally-agent");
const {
  createFinancialSync,
  planHeavy,
  inHeavyHours,
  monthEnds,
  fyStartOf,
  isoFromTally,
  MAX_HEAVY,
  HEAVY_TIMEOUT_MS,
  HEAVY_EVERY_MS,
  HEAVY_SLOW_EVERY_MS,
  MAX_HEAVY_TIMEOUTS,
} = require(
  path.join(AGENT_DIR, "lib", "financialSync.cjs")
);
const { mergeLedgerLines } = require(path.join(AGENT_DIR, "lib", "voucherLines.cjs"));
const xml2js = require(path.join(AGENT_DIR, "node_modules", "xml2js"));

// Same parsing as the Agent's parseTallyNumber.
function parseNumber(val = "0") {
  if (val === null || val === undefined) return 0;
  if (typeof val === "object") val = val._ !== undefined ? val._ : "0";
  return Number(String(val).replace(/\(/g, "-").replace(/\)/g, "").replace(/,/g, "").replace(/[^0-9.-]/g, ""));
}

const tag = (xml, t) => (new RegExp(`<${t}>([^<]*)</${t}>`).exec(xml) || [])[1] || null;

/** A fake Tally: masters, books date, item openings, stock by date. */
function fakeTally({ slowStock = false } = {}) {
  const calls = [];
  async function tallyPost(xml, timeoutMs) {
    calls.push({ xml, timeoutMs });
    const type = (/<COLLECTION NAME="[^"]*">\s*<TYPE>(\w+)<\/TYPE>/.exec(xml) || [])[1];
    const fetch = tag(xml, "FETCH");
    let body = "";
    if (type === "Group" && /ISREVENUE/.test(fetch)) {
      body =
        `<GROUP NAME="Capital Account"><PARENT>&#4; Primary</PARENT><ISREVENUE>No</ISREVENUE><ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE><AFFECTSGROSSPROFIT>No</AFFECTSGROSSPROFIT></GROUP>` +
        `<GROUP NAME="Sales Accounts"><PARENT>&#4; Primary</PARENT><ISREVENUE>Yes</ISREVENUE><ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE><AFFECTSGROSSPROFIT>Yes</AFFECTSGROSSPROFIT></GROUP>`;
    } else if (type === "Company") {
      body = `<COMPANY NAME="Other Co"><STARTINGFROM>20200401</STARTINGFROM></COMPANY><COMPANY NAME="Ravi Traders"><STARTINGFROM>20250401</STARTINGFROM></COMPANY>`;
    } else if (type === "StockItem") {
      body = `<STOCKITEM NAME="Wire"><OPENINGVALUE>-10000.00</OPENINGVALUE></STOCKITEM><STOCKITEM NAME="Switch"><OPENINGVALUE>(5,000.00)</OPENINGVALUE></STOCKITEM>`;
    } else if (type === "Group") {
      if (slowStock) {
        const e = new Error(`timeout of ${timeoutMs}ms exceeded`);
        e.code = "ECONNABORTED";
        throw e;
      }
      const m = Number(tag(xml, "SVTODATE").slice(4, 6));
      body = `<GROUP NAME="Stock-in-Hand"><PARENT>Current Assets</PARENT><CLOSINGBALANCE TYPE="Amount">-${m * 1000}.00</CLOSINGBALANCE></GROUP>`;
    } else if (type === "Ledger") {
      body = `<LEDGER NAME="Sales"><GUID>g-s</GUID><PARENT>Sales Accounts</PARENT><CLOSINGBALANCE TYPE="Amount">40000.00</CLOSINGBALANCE></LEDGER>`;
    }
    return { data: `<ENVELOPE><BODY><DATA><COLLECTION>${body}</COLLECTION></DATA></BODY></ENVELOPE>` };
  }
  return { tallyPost, calls };
}

function fakeBackend() {
  const posts = [];
  let batch = 0;
  async function post(p, body) {
    posts.push({ path: p, body });
    if (p.endsWith("/begin")) return { data: { batch_id: ++batch } };
    return { data: { success: true } };
  }
  return { post, posts };
}

const parseXml = (x) =>
  new xml2js.Parser({ explicitArray: false }).parseStringPromise(
    x.replace(/&#(?:x0*[0-8bcef]|x0*1[0-9a-f]|0*[0-8]|0*1[1-2]|0*1[4-9]|0*2[0-9]|0*3[01]);/gi, "")
  );

const T = new Date("2026-10-14T10:00:00");
const base = { companyGuid: "CO-1", companyName: "Ravi Traders", fyFrom: "2025-04-01", syncStart: "2025-04-01" };

describe("plan", () => {
  test("dates", () => {
    assert.deepEqual(monthEnds("2026-04-01", "2026-06-30"), ["2026-04-30", "2026-05-31", "2026-06-30"]);
    assert.equal(fyStartOf("2026-10-14", "2025-04-01"), "2026-04-01");
    assert.equal(fyStartOf("2026-02-01", "2025-04-01"), "2025-04-01");
    assert.equal(isoFromTally("20250401"), "2025-04-01");
  });

  test("heavy work is off by default; never before the books begin", () => {
    const p = { fyFrom: "2025-04-01", booksFrom: "2025-04-01", syncStart: "2025-04-01", today: "2026-10-14", state: {}, nowMs: 0 };
    assert.deepEqual(planHeavy(p), []);
    const on = planHeavy({ ...p, stockFromTally: true });
    // The year end first (next year's opening stock), then yesterday (one
    // value per day from now on), then month ends, newest first.
    assert.deepEqual(on.slice(0, 4).map((x) => x.asOn), ["2026-03-31", "2026-10-13", "2026-09-30", "2026-08-31"]);
    assert.equal(on.find((x) => x.asOn === "2026-10-13").daily, true);
    // Without the daily value: as before.
    assert.deepEqual(planHeavy({ ...p, stockFromTally: true, daily: false }).slice(0, 2).map((x) => x.asOn), ["2026-03-31", "2026-09-30"]);
    assert.ok(on.every((x) => x.asOn >= "2025-04-01"));
    assert.equal(on.find((x) => x.asOn === "2026-03-31").fyFrom, "2025-04-01");
    // No ledger balances from Tally while the vouchers start with the books.
    assert.ok(!planHeavy({ ...p, tallyAnchor: true }).length);
    // Vouchers from later than the books + switched on: one anchor.
    assert.deepEqual(planHeavy({ ...p, syncStart: "2026-04-01", tallyAnchor: true }), [{ kind: "anchor", asOn: "2026-03-31", fyFrom: "2025-04-01" }]);
    // Paused after a slow answer.
    assert.deepEqual(planHeavy({ ...p, stockFromTally: true, state: { fin_paused_until: 10 }, nowMs: 5 }), []);
  });
});

describe("run", () => {
  test("default: only light requests (groups, books date, item openings)", async () => {
    const tally = fakeTally();
    const be = fakeBackend();
    let saved = null;
    const sync = createFinancialSync({ tallyPost: tally.tallyPost, parseXml, parseNumber, post: be.post });
    const out = await sync.run({ ...base, state: {}, saveState: (s) => (saved = JSON.parse(JSON.stringify(s))), now: T });
    assert.deepEqual(out.done, ["groups", "books"]);
    assert.equal(out.left, 0);
    // No balances, no period: masters only.
    for (const c of tally.calls) {
      assert.ok(!/CLOSINGBALANCE/.test(c.xml), "no balance asked");
      assert.ok(!/SVFROMDATE/.test(c.xml), "no period asked");
    }
    const books = be.posts.find((x) => x.path === "/api/financial/agent/books").body;
    assert.deepEqual(books, { company_guid: "CO-1", books_from: "2025-04-01", vouchers_from: "2025-04-01", opening_stock: 15000, fy_from: "2025-04-01" });
    assert.ok(saved.fin_groups_at && saved.fin_books_at && saved.fin_books_from === "2025-04-01");
    // Same day again: nothing.
    const again = await sync.run({ ...base, state: saved, saveState: () => {}, now: new Date("2026-10-14T12:00:00") });
    assert.deepEqual(again.done, []);
  });

  test("switched on: one closing-stock request per sync, with the short time limit", async () => {
    const tally = fakeTally();
    const be = fakeBackend();
    const state = {};
    const sync = createFinancialSync({ tallyPost: tally.tallyPost, parseXml, parseNumber, post: be.post });
    const out = await sync.run({ ...base, state, saveState: () => {}, now: T, stockFromTally: true });
    assert.equal(MAX_HEAVY, 1);
    assert.deepEqual(out.done, ["groups", "books", "stock 2026-03-31"]);
    const heavy = tally.calls.filter((c) => /CLOSINGBALANCE/.test(c.xml));
    assert.equal(heavy.length, 1);
    assert.equal(heavy[0].timeoutMs, HEAVY_TIMEOUT_MS);
    assert.ok(heavy[0].xml.includes("<SVFROMDATE>20250401</SVFROMDATE>") && heavy[0].xml.includes("<SVTODATE>20260331</SVTODATE>"));
    assert.deepEqual(be.posts.at(-1).body, { company_guid: "CO-1", values: [{ as_on: "2026-03-31", value: 3000 }] });
    const next = await sync.run({ ...base, state, saveState: () => {}, now: new Date("2026-10-14T11:00:00"), stockFromTally: true });
    assert.deepEqual(next.done, ["stock 2026-10-13"]);
    const third = await sync.run({ ...base, state, saveState: () => {}, now: new Date("2026-10-14T12:00:00"), stockFromTally: true });
    assert.deepEqual(third.done, ["stock 2026-09-30"]);
  });

  test("a day's value is read once; the two newest month ends are re-read weekly", () => {
    const p = { fyFrom: "2025-04-01", booksFrom: "2025-04-01", syncStart: "2025-04-01", today: "2026-10-14", stockFromTally: true };
    const day = 86400000;
    const allDone = {};
    for (const x of planHeavy({ ...p, state: {}, nowMs: 0 })) allDone[x.asOn] = 1;
    const later = planHeavy({ ...p, state: { fin_stock: allDone }, nowMs: 1 + 8 * day }).map((x) => x.asOn);
    assert.deepEqual(later, ["2026-09-30", "2026-08-31"], "only the two newest month ends again");
  });

  test("allowed hours: nothing heavy outside them (light requests still run)", async () => {
    const tally = fakeTally();
    const be = fakeBackend();
    const sync = createFinancialSync({ tallyPost: tally.tallyPost, parseXml, parseNumber, post: be.post });
    const out = await sync.run({ ...base, state: {}, saveState: () => {}, now: T, stockFromTally: true, heavyHours: "20-8" });
    assert.deepEqual(out.done, ["groups", "books"]);
    assert.ok(out.left > 0);
    assert.match(out.waiting, /20-8/);
    assert.ok(!tally.calls.some((c) => /CLOSINGBALANCE/.test(c.xml)), "no stock value asked at 10:00");
    const night = await sync.run({ ...base, state: {}, saveState: () => {}, now: new Date("2026-10-14T22:30:00"), stockFromTally: true, heavyHours: "20-8" });
    assert.ok(night.done.includes("stock 2026-03-31"));
  });

  test("Tally busy (tiny request not answered at once): nothing heavy this sync", async () => {
    const tally = fakeTally();
    const be = fakeBackend();
    const sync = createFinancialSync({ tallyPost: tally.tallyPost, parseXml, parseNumber, post: be.post });
    let asked = 0;
    const out = await sync.run({ ...base, state: {}, saveState: () => {}, now: T, stockFromTally: true, isIdle: async () => (asked++, false) });
    assert.equal(asked, 1);
    assert.match(out.waiting, /busy/);
    assert.ok(!tally.calls.some((c) => /CLOSINGBALANCE/.test(c.xml)));
    const idle = await sync.run({ ...base, state: {}, saveState: () => {}, now: T, stockFromTally: true, isIdle: async () => true });
    assert.ok(idle.done.includes("stock 2026-03-31"));
  });

  test("paced: one stock value per 30 minutes, not one per sync", async () => {
    assert.equal(HEAVY_EVERY_MS, 30 * 60000);
    const tally = fakeTally();
    const be = fakeBackend();
    const state = {};
    const sync = createFinancialSync({ tallyPost: tally.tallyPost, parseXml, parseNumber, post: be.post });
    const at = (hhmm) => new Date(`2026-10-14T${hhmm}:00`);
    const a = await sync.run({ ...base, state, saveState: () => {}, now: at("10:00"), stockFromTally: true });
    assert.ok(a.done.includes("stock 2026-03-31"));
    const b = await sync.run({ ...base, state, saveState: () => {}, now: at("10:05"), stockFromTally: true });
    assert.ok(!b.done.some((d) => d.startsWith("stock")), "the next sync 5 minutes later sends nothing heavy");
    assert.match(b.waiting, /after 10:30/);
    const c = await sync.run({ ...base, state, saveState: () => {}, now: at("10:31"), stockFromTally: true });
    assert.deepEqual(c.done, ["stock 2026-10-13"]);
    assert.equal(tally.calls.filter((x) => /CLOSINGBALANCE/.test(x.xml)).length, 2);
  });

  test("a slow stock value (over 15 s): the next one waits 4 hours", async () => {
    const tally = fakeTally();
    const be = fakeBackend();
    const state = {};
    const logs = [];
    let t = 0;
    const clock = () => (t += 10000); // each reading 10 s later → the request "took" 10–20 s
    const sync = createFinancialSync({ tallyPost: tally.tallyPost, parseXml, parseNumber, post: be.post, log: (m) => logs.push(m), clock });
    const out = await sync.run({ ...base, state, saveState: () => {}, now: T, stockFromTally: true, heavySlowMs: 5000 });
    assert.ok(out.done.includes("stock 2026-03-31"));
    assert.equal(state.fin_heavy_next_at - T.getTime(), HEAVY_SLOW_EVERY_MS);
    assert.ok(logs.some((l) => /next one waits 4 h/.test(l)));
    const later = await sync.run({ ...base, state, saveState: () => {}, now: new Date("2026-10-14T11:00:00"), stockFromTally: true });
    assert.ok(!later.done.some((d) => d.startsWith("stock")));
    assert.match(later.waiting, /after 14:00/);
  });

  test("the Agent switches stock values off for a company after Tally failed twice", async () => {
    assert.equal(MAX_HEAVY_TIMEOUTS, 2);
    const tally = fakeTally({ slowStock: true });
    const be = fakeBackend();
    const state = {};
    const logs = [];
    const sync = createFinancialSync({ tallyPost: tally.tallyPost, parseXml, parseNumber, post: be.post, log: (m) => logs.push(m) });
    const stockCalls = () => tally.calls.filter((c) => /CLOSINGBALANCE/.test(c.xml)).length;
    const first = await sync.run({ ...base, state, saveState: () => {}, now: T, stockFromTally: true });
    assert.match(first.skipped, /paused for 7 days/);
    assert.equal(state.fin_heavy_timeouts, 1);
    assert.ok(!state.fin_heavy_off_at);
    // 8 days later (pause over): fails again → off for this company.
    const second = await sync.run({ ...base, state, saveState: () => {}, now: new Date("2026-10-22T10:00:00"), stockFromTally: true });
    assert.match(second.skipped, /switched off/);
    assert.ok(state.fin_heavy_off_at);
    assert.ok(logs.some((l) => /switched OFF for this company/.test(l)));
    // From then on: no stock request at all.
    const n = stockCalls();
    const third = await sync.run({ ...base, state, saveState: () => {}, now: new Date("2026-11-30T10:00:00"), stockFromTally: true });
    assert.equal(third.off, true);
    assert.equal(stockCalls(), n);
    // Developer override (always on) still tries.
    await sync.run({ ...base, state, saveState: () => {}, now: new Date("2026-12-30T10:00:00"), stockFromTally: true, forceHeavy: true });
    assert.equal(stockCalls(), n + 1);
  });

  test("an answer in time forgives an earlier miss", async () => {
    const tally = fakeTally();
    const be = fakeBackend();
    const state = { fin_heavy_timeouts: 1 };
    const sync = createFinancialSync({ tallyPost: tally.tallyPost, parseXml, parseNumber, post: be.post });
    const out = await sync.run({ ...base, state, saveState: () => {}, now: T, stockFromTally: true });
    assert.ok(out.done.includes("stock 2026-03-31"));
    assert.equal(state.fin_heavy_timeouts, 0);
  });

  test("hours", () => {
    const at = (h) => new Date(2026, 9, 14, h, 30);
    assert.equal(inHeavyHours(at(22), "20-8"), true);
    assert.equal(inHeavyHours(at(3), "20-8"), true);
    assert.equal(inHeavyHours(at(8), "20-8"), false);
    assert.equal(inHeavyHours(at(14), "20-8"), false);
    assert.equal(inHeavyHours(at(14), "9-18"), true);
    assert.equal(inHeavyHours(at(18), "9-18"), false);
    assert.equal(inHeavyHours(at(14), "all"), true);
    assert.equal(inHeavyHours(at(14), ""), true);
  });

  test("Tally too slow: stops, pauses heavy requests 7 days, the sync goes on", async () => {
    const tally = fakeTally({ slowStock: true });
    const be = fakeBackend();
    const state = {};
    const logs = [];
    const sync = createFinancialSync({ tallyPost: tally.tallyPost, parseXml, parseNumber, post: be.post, log: (m) => logs.push(m) });
    const out = await sync.run({ ...base, state, saveState: () => {}, now: T, stockFromTally: true });
    assert.match(out.skipped, /paused/);
    assert.ok(state.fin_paused_until - T.getTime() === 7 * 86400000);
    assert.ok(logs.some((l) => /paused for 7 days/.test(l)));
    const later = await sync.run({ ...base, state, saveState: () => {}, now: new Date("2026-10-16T10:00:00"), stockFromTally: true });
    assert.ok(!later.done.some((d) => d.startsWith("stock")));
  });

  test("Stop is honoured", async () => {
    const tally = fakeTally();
    const be = fakeBackend();
    const sync = createFinancialSync({ tallyPost: tally.tallyPost, parseXml, parseNumber, post: be.post });
    let n = 0;
    const out = await sync.run({ ...base, state: {}, saveState: () => {}, now: T, stopRequested: () => ++n > 0 });
    assert.deepEqual(out.done, ["groups"]);
  });
});

describe("voucher lines", () => {
  const ev = (rows) => rows.map(([n, dp, a]) => ({ LEDGERNAME: [n], ISDEEMEDPOSITIVE: [dp], AMOUNT: [String(a)] }));
  const x = (v) => (typeof v === "string" ? v : v && v._ ? v._ : null);

  test("a ledger that appears once is stored exactly as before", () => {
    assert.deepEqual(mergeLedgerLines(ev([["Mehta", "Yes", -1180], ["Sales", "No", 1000], ["GST", "No", 180]]), x), [
      { ledger_name: "Mehta", amount: 1180, is_debit: false },
      { ledger_name: "Sales", amount: 1000, is_debit: true },
      { ledger_name: "GST", amount: 180, is_debit: true },
    ]);
  });

  test("repeated lines of a ledger are added up (not dropped), so the voucher balances", () => {
    const out = mergeLedgerLines(ev([["Mehta", "Yes", -2360], ["Sales", "No", 1000], ["Sales", "No", 1000], ["GST", "No", 360]]), x);
    assert.deepEqual(out.find((e) => e.ledger_name === "Sales"), { ledger_name: "Sales", amount: 2000, is_debit: true });
    assert.equal(out.reduce((a, e) => a + (e.is_debit ? e.amount : -e.amount), 0), 0);
    assert.deepEqual(mergeLedgerLines(ev([["Cash", "Yes", -500], ["Cash", "No", 200], ["Bank", "No", 300]]), x)[0], {
      ledger_name: "Cash",
      amount: 300,
      is_debit: false,
    });
  });
});
