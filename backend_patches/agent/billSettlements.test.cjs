// Tests for the Agent's bill-wise allocation reader (node --test), run
// against tally-agent/lib/billSettlements.cjs — no Tally needed.
//   AGENT_DIR=<path to tally-agent> node --test billSettlements.test.cjs
"use strict";
const { test, describe } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const AGENT_DIR = process.env.AGENT_DIR || path.join(__dirname, "..", "..", "..", "tally-agent");
const b = require(path.join(AGENT_DIR, "lib", "billSettlements.cjs"));

// The shape the voucher sync reads (every field an array; text or {_}).
const extract = (val) => (!val ? null : typeof val === "string" ? val : typeof val === "object" && val._ ? val._ : null);
const alloc = (name, type, amount, credit) => ({
  NAME: [name],
  BILLTYPE: [type],
  AMOUNT: [String(amount)],
  ...(credit !== undefined ? { BILLCREDITPERIOD: [credit] } : {}),
});

const receipt = {
  GUID: ["G-R1"],
  DATE: ["20260930"],
  VOUCHERTYPENAME: ["Receipt"],
  VOUCHERNUMBER: ["R/12"],
  "ALLLEDGERENTRIES.LIST": [
    {
      LEDGERNAME: ["Mehta Electricals"],
      AMOUNT: ["15000.00"],
      "BILLALLOCATIONS.LIST": [
        alloc("S/101", "Agst Ref", "10000.00"),
        alloc("\u0004S/102", "Agst Ref", "4000.00"),
        alloc("", "Agst Ref", "1"), // no name: skipped
        alloc("ADV-1", "Advance", "1000.00"),
      ],
    },
    { LEDGERNAME: ["HDFC Bank"], AMOUNT: ["-15000.00"] },
  ],
};

describe("bill allocations (Agent)", () => {
  test("a receipt: each bill settled, Tally's sign kept, control characters removed", () => {
    const rows = b.allocationsOf(receipt, extract);
    assert.deepEqual(
      rows.map((r) => [r.ledger_name, r.bill_name, r.ref_type, r.amount]),
      [
        ["Mehta Electricals", "S/101", "Agst Ref", 10000],
        ["Mehta Electricals", "S/102", "Agst Ref", 4000],
        ["Mehta Electricals", "ADV-1", "Advance", 1000],
      ]
    );
    assert.deepEqual(
      [rows[0].voucher_guid, rows[0].voucher_date, rows[0].voucher_type, rows[0].voucher_no],
      ["G-R1", "2026-09-30", "Receipt", "R/12"]
    );
  });

  test("a sales invoice: New Ref with credit days; meta from the voucher record wins", () => {
    const sale = {
      GUID: ["G-S1"],
      "ALLLEDGERENTRIES.LIST": {
        LEDGERNAME: ["Mehta Electricals"],
        AMOUNT: ["-11800.00"],
        "BILLALLOCATIONS.LIST": alloc("S/101", "New Ref", "-11800.00", { _: "30 Days", $: { JD: "46000" } }),
      },
    };
    const rows = b.allocationsOf(sale, extract, {
      voucher_guid: "G-S1",
      voucher_date: "2026-09-01",
      voucher_type: "Sales",
      voucher_no: "S/101",
    });
    assert.equal(rows.length, 1);
    assert.deepEqual([rows[0].ref_type, rows[0].amount, rows[0].credit_days, rows[0].voucher_date], ["New Ref", -11800, 30, "2026-09-01"]);
  });

  test("repeated lines of one bill are added up; zero totals dropped", () => {
    const v = {
      GUID: ["G-J"],
      DATE: ["20261001"],
      "ALLLEDGERENTRIES.LIST": [
        { LEDGERNAME: ["A"], "BILLALLOCATIONS.LIST": [alloc("B1", "Agst Ref", "100"), alloc("B1", "Agst Ref", "50.5")] },
        { LEDGERNAME: ["A"], "BILLALLOCATIONS.LIST": [alloc("B2", "Agst Ref", "10"), alloc("B2", "Agst Ref", "-10")] },
      ],
    };
    assert.deepEqual(b.allocationsOf(v, extract).map((r) => [r.bill_name, r.amount]), [["B1", 150.5]]);
  });

  test("no GUID / date or no lines: nothing", () => {
    assert.deepEqual(b.allocationsOf({ DATE: ["20261001"] }, extract), []);
    assert.deepEqual(b.allocationsOf({ GUID: ["X"], DATE: ["20261001"] }, extract), []);
    assert.deepEqual(b.allocationsOf(null, extract), []);
  });

  test("helpers: credit days, dates, reference types", () => {
    assert.equal(b.creditDays("45 Days"), 45);
    assert.equal(b.creditDays({ _: "30 Days" }), 30);
    assert.equal(b.creditDays(""), null);
    assert.equal(b.isoDate("20261015"), "2026-10-15");
    assert.equal(b.isoDate("bad"), null);
    assert.equal(b.refType("agst ref"), "Agst Ref");
    assert.equal(b.refType("On Account"), "On Account");
  });

  test("upload: per voucher (also ones without allocations), batched; 404 turns it off", async () => {
    const posts = [];
    const sink = b.createSettlementSink({ post: async (body) => posts.push(body), batchSize: 1, log: {} });
    sink.add(receipt, extract);
    sink.add({ GUID: ["G-EMPTY"], DATE: ["20261001"], "ALLLEDGERENTRIES.LIST": [{ LEDGERNAME: ["Cash"] }] }, extract);
    assert.equal(sink.pending(), 2);
    const r = await sink.flush("CO-1");
    assert.equal(r.sent, 3);
    assert.equal(posts.length, 2);
    assert.deepEqual(posts[0].voucher_guids, ["G-R1"]);
    assert.equal(posts[0].company_guid, "CO-1");
    assert.deepEqual(posts[1], { company_guid: "CO-1", voucher_guids: ["G-EMPTY"], rows: [] });
    assert.equal(sink.pending(), 0);

    const notFound = Object.assign(new Error("404"), { response: { status: 404 } });
    const off = b.createSettlementSink({ post: async () => { throw notFound; }, log: {} });
    off.add(receipt, extract);
    await off.flush("CO-1");
    assert.equal(off.disabled(), true);
    off.add(receipt, extract);
    assert.equal(off.pending(), 0);

    // Other errors: logged, the sink stays on.
    const flaky = b.createSettlementSink({ post: async () => { throw new Error("timeout"); }, log: { warn() {} } });
    flaky.add(receipt, extract);
    await flaky.flush("CO-1");
    assert.equal(flaky.disabled(), false);
  });

  test("a failed upload is kept and sent with the next one (server 500 / 503)", async () => {
    let down = true;
    const posts = [];
    const sink = b.createSettlementSink({
      post: async (body) => {
        if (down) throw Object.assign(new Error("500"), { response: { status: 500 } });
        posts.push(body);
      },
      log: { warn() {} },
    });
    sink.add(receipt, extract);
    const r1 = await sink.flush("CO-1");
    assert.deepEqual(r1, { sent: 0, failed: 1 });
    assert.equal(sink.waiting(), 1);
    // Still down: nothing new, the old batch stays waiting.
    assert.equal((await sink.flush("CO-1")).failed, 1);
    // Server fixed: the kept batch goes first, then the new voucher.
    down = false;
    sink.add({ GUID: ["G-2"], DATE: ["20261002"], "ALLLEDGERENTRIES.LIST": [{ LEDGERNAME: ["Cash"] }] }, extract);
    const r3 = await sink.flush("CO-1");
    assert.deepEqual(r3, { sent: 3, failed: 0 });
    assert.deepEqual(posts.map((p) => p.voucher_guids), [["G-R1"], ["G-2"]]);
    assert.equal(sink.waiting(), 0);
    // Another company's waiting batch is not sent under this company.
    down = true;
    sink.add(receipt, extract);
    await sink.flush("CO-2");
    down = false;
    await sink.flush("CO-1");
    assert.equal(sink.waiting(), 1);
    await sink.flush("CO-2");
    assert.equal(posts.at(-1).company_guid, "CO-2");
  });

  test("waiting uploads are capped (oldest dropped)", async () => {
    const sink = b.createSettlementSink({
      post: async () => {
        throw Object.assign(new Error("500"), { response: { status: 500 } });
      },
      log: { warn() {} },
      batchSize: 1,
      maxWaiting: 2,
    });
    for (const g of ["A", "B", "C"]) sink.add({ GUID: [g], DATE: ["20261001"], "ALLLEDGERENTRIES.LIST": [{ LEDGERNAME: ["X"] }] }, extract);
    await sink.flush("CO-1");
    assert.equal(sink.waiting(), 2);
  });
});
