// Tests for the Agent's daily stock value (node --test), run against
// tally-agent/lib/stockCapture.cjs with a fake Tally and backend.
//   AGENT_DIR=<path to tally-agent> node --test stockCapture.test.cjs
"use strict";
const { test, describe } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const AGENT_DIR = process.env.AGENT_DIR || path.join(__dirname, "..", "..", "..", "tally-agent");
const { createStockCapture, readStockTotal, stockValuesXml, amountOf, isoDay, DEFAULTS } = require(
  path.join(AGENT_DIR, "lib", "stockCapture.cjs")
);

const ITEMS = `<ENVELOPE><BODY><DATA><COLLECTION>
  <STOCKITEM NAME="Pen"><CLOSINGVALUE>-1,200.50</CLOSINGVALUE></STOCKITEM>
  <STOCKITEM NAME="tv"><CLOSINGVALUE>-48000.00</CLOSINGVALUE></STOCKITEM>
  <STOCKITEM NAME="Negative Item"><CLOSINGVALUE>500.00</CLOSINGVALUE></STOCKITEM>
  <STOCKITEM NAME="No value"></STOCKITEM>
</COLLECTION></DATA></BODY></ENVELOPE>`;

function fakes({ answer = ITEMS, fail = null } = {}) {
  const calls = [];
  const posts = [];
  return {
    calls,
    posts,
    tallyPost: async (xml, timeoutMs) => {
      calls.push({ xml, timeoutMs });
      if (fail) throw fail;
      return { data: answer };
    },
    post: async (p, body) => {
      posts.push({ path: p, body });
      return { data: { success: true } };
    },
  };
}
const timeout = () => Object.assign(new Error("timeout of 120000ms exceeded"), { code: "ECONNABORTED" });
const at = (s) => new Date(s);

describe("daily stock value", () => {
  test("the request has NO date range (the date-range kind froze Tally)", () => {
    const x = stockValuesXml("GI Apr 25-26");
    assert.ok(!/SVFROMDATE|SVTODATE/.test(x));
    assert.match(x, /<TYPE>StockItem<\/TYPE>/);
    assert.match(x, /<FETCH>NAME, CLOSINGVALUE<\/FETCH>/);
    assert.match(stockValuesXml("A & B"), /A &amp; B/);
  });

  test("total: Tally's signs added up (negative stock reduces it), shown positive", () => {
    assert.deepEqual(readStockTotal(ITEMS), { items: 4, value: 48700.5 });
    assert.equal(amountOf("(1,000.00)"), -1000);
    assert.equal(amountOf("250.00 Dr"), -250);
    assert.deepEqual(readStockTotal("<ENVELOPE></ENVELOPE>"), { items: 0, value: 0 });
  });

  test("saved as today's value; again only after 3 hours; the later value replaces it", async () => {
    const f = fakes();
    const cap = createStockCapture({ tallyPost: f.tallyPost, post: f.post });
    const state = {};
    const a = await cap.run({ companyGuid: "CO-1", companyName: "GI", state, saveState: () => {}, now: at("2026-10-16T10:00:00") });
    assert.equal(a.done, true);
    assert.deepEqual(f.posts[0], { path: "/api/financial/agent/stock-values", body: { company_guid: "CO-1", values: [{ as_on: "2026-10-16", value: 48700.5 }] } });
    assert.equal(f.calls[0].timeoutMs, DEFAULTS.timeoutMs);
    const b = await cap.run({ companyGuid: "CO-1", companyName: "GI", state, saveState: () => {}, now: at("2026-10-16T11:00:00") });
    assert.equal(b.done, false);
    assert.equal(f.calls.length, 1, "nothing sent before 3 hours");
    const c = await cap.run({ companyGuid: "CO-1", companyName: "GI", state, saveState: () => {}, now: at("2026-10-16T13:01:00") });
    assert.equal(c.done, true);
    assert.equal(f.posts[1].body.values[0].as_on, "2026-10-16", "same day: the value is replaced");
  });

  test("a company with no stock items: value 0 (reports work for every day)", async () => {
    const f = fakes({ answer: "<ENVELOPE><BODY><DATA><COLLECTION></COLLECTION></DATA></BODY></ENVELOPE>" });
    const cap = createStockCapture({ tallyPost: f.tallyPost, post: f.post });
    const out = await cap.run({ companyGuid: "CO-1", companyName: "X", state: {}, saveState: () => {}, now: at("2026-10-16T10:00:00") });
    assert.equal(out.value, 0);
    assert.equal(f.posts[0].body.values[0].value, 0);
  });

  test("Tally busy: nothing sent", async () => {
    const f = fakes();
    const cap = createStockCapture({ tallyPost: f.tallyPost, post: f.post });
    const out = await cap.run({ companyGuid: "CO-1", companyName: "GI", state: {}, saveState: () => {}, now: at("2026-10-16T10:00:00"), isIdle: async () => false });
    assert.equal(out.waiting, "Tally is busy");
    assert.equal(f.calls.length, 0);
  });

  test("slow (over 15 s): once a day from then on", async () => {
    const f = fakes();
    let t = 0;
    const state = {};
    const logs = [];
    // Each clock reading 20 s later → the request "took" 20 s.
    const cap = createStockCapture({ tallyPost: f.tallyPost, post: f.post, clock: () => (t += 20000), log: (m) => logs.push(m) });
    await cap.run({ companyGuid: "CO-1", companyName: "GI", state, saveState: () => {}, now: at("2026-10-16T10:00:00") });
    assert.equal(state.stock_capture.next_at - at("2026-10-16T10:00:00").getTime(), DEFAULTS.slowEveryMs);
    assert.ok(logs.some((l) => /once a day/.test(l)));
  });

  test("no answer in time twice: switched off for that company, nothing more sent", async () => {
    const f = fakes({ fail: timeout() });
    const logs = [];
    const cap = createStockCapture({ tallyPost: f.tallyPost, post: f.post, log: (m) => logs.push(m) });
    const state = {};
    const a = await cap.run({ companyGuid: "CO-1", companyName: "GI", state, saveState: () => {}, now: at("2026-10-16T10:00:00") });
    assert.equal(a.waiting, "Tally too slow");
    assert.equal(state.stock_capture.timeouts, 1);
    const b = await cap.run({ companyGuid: "CO-1", companyName: "GI", state, saveState: () => {}, now: at("2026-10-17T11:00:00") });
    assert.equal(b.done, false);
    assert.ok(state.stock_capture.off_at);
    assert.ok(logs.some((l) => /switched OFF/.test(l)));
    const n = f.calls.length;
    const c = await cap.run({ companyGuid: "CO-1", companyName: "GI", state, saveState: () => {}, now: at("2026-10-20T11:00:00") });
    assert.equal(c.off, true);
    assert.equal(f.calls.length, n);
    assert.equal(f.posts.length, 0);
  });

  test("Tally refuses (LINEERROR): nothing saved, tried again later", async () => {
    const f = fakes({ answer: "<ENVELOPE><LINEERROR>Unknown</LINEERROR></ENVELOPE>" });
    const cap = createStockCapture({ tallyPost: f.tallyPost, post: f.post });
    const out = await cap.run({ companyGuid: "CO-1", companyName: "GI", state: {}, saveState: () => {}, now: at("2026-10-16T10:00:00") });
    assert.equal(out.waiting, "Tally refused");
    assert.equal(f.posts.length, 0);
  });

  test("isoDay is the local calendar date", () => {
    assert.equal(isoDay(new Date(2026, 9, 16, 23, 59)), "2026-10-16");
  });
});
