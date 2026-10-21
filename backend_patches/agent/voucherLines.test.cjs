// Tests for the Agent's voucher lines (node --test), run against
// tally-agent/lib/voucherLines.cjs. An item invoice keeps its Sales /
// Purchase ledger in the stock lines (ACCOUNTINGALLOCATIONS); the stored
// voucher must include it so it balances as in Tally (GI: 4,970 vouchers
// were stored with the party line only).
//   AGENT_DIR=<path to tally-agent> node --test voucherLines.test.cjs
"use strict";
const { test, describe } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const AGENT_DIR = process.env.AGENT_DIR || path.join(__dirname, "..", "..", "..", "tally-agent");
const { mergeLedgerLines, stockLineLedgers, voucherLedgerLines } = require(path.join(AGENT_DIR, "lib", "voucherLines.cjs"));

// Values as the Agent's parsers give them (arrays of strings).
const ev = (v) => (v == null ? null : typeof v === "string" ? v : typeof v === "object" && v._ ? v._ : null);
const line = (name, amount) => ({
  LEDGERNAME: [name],
  AMOUNT: [String(amount)],
  ISDEEMEDPOSITIVE: [amount < 0 ? "Yes" : "No"], // Tally: Dr = negative, deemed positive
});
const stock = (...allocs) => ({ STOCKITEMNAME: ["Item"], "ACCOUNTINGALLOCATIONS.LIST": allocs });
// Stored convention: is_debit TRUE = credit (ISDEEMEDPOSITIVE "No").
const balance = (ls) => Math.round(ls.reduce((a, l) => a + (l.is_debit ? l.amount : -l.amount), 0) * 100) / 100;
const byName = (ls) => Object.fromEntries(ls.map((l) => [l.ledger_name, [l.amount, l.is_debit]]));

describe("item invoices", () => {
  test("sales: the Sales ledger from the stock lines is added; the voucher balances", () => {
    const v = {
      "ALLLEDGERENTRIES.LIST": [line("Kitchen Sales", -6211.01)],
      "ALLINVENTORYENTRIES.LIST": [stock(line("Kitchen", 4352)), stock(line("Kitchen", 145)), stock(line("Kitchen", 1714.01))],
    };
    const items = v["ALLLEDGERENTRIES.LIST"];
    assert.notEqual(balance(mergeLedgerLines(items, ev)), 0); // before: party only
    const got = voucherLedgerLines(items, v, ev);
    assert.equal(balance(got), 0);
    assert.deepEqual(byName(got), {
      "Kitchen Sales": [6211.01, false], // party: debit
      Kitchen: [6211.01, true], // sales: credit, three stock lines added up
    });
  });

  test("purchase: the Purchase ledger is added on the debit side", () => {
    const v = {
      "ALLLEDGERENTRIES.LIST": [line("RAVI STORE KEEPER", 3965)],
      "ALLINVENTORYENTRIES.LIST": [stock(line("Restaurant Pur Non GST", -3965))],
    };
    const got = voucherLedgerLines(v["ALLLEDGERENTRIES.LIST"], v, ev);
    assert.equal(balance(got), 0);
    assert.deepEqual(byName(got), {
      "RAVI STORE KEEPER": [3965, true],
      "Restaurant Pur Non GST": [3965, false],
    });
  });

  test("with tax and round-off in the ledger lines", () => {
    const v = {
      "ALLLEDGERENTRIES.LIST": [line("Mehta", -1180), line("Output GST", 180)],
      "ALLINVENTORYENTRIES.LIST": [stock(line("Sales 18%", 1000))],
    };
    const got = voucherLedgerLines(v["ALLLEDGERENTRIES.LIST"], v, ev);
    assert.equal(balance(got), 0);
    assert.equal(byName(got)["Sales 18%"][0], 1000);
  });

  test("older exports (INVENTORYENTRIES.LIST) are read too", () => {
    const v = {
      "LEDGERENTRIES.LIST": [line("Cash", -500)],
      "INVENTORYENTRIES.LIST": [stock(line("Sales", 500))],
    };
    assert.equal(stockLineLedgers(v).length, 1);
    assert.equal(balance(voucherLedgerLines(v["LEDGERENTRIES.LIST"], v, ev)), 0);
  });
});

describe("never worse than before", () => {
  test("a ledger listed in BOTH places is not counted twice", () => {
    // An export that already puts the Sales ledger in the ledger lines.
    const v = {
      "ALLLEDGERENTRIES.LIST": [line("Party", -1000), line("Sales", 1000)],
      "ALLINVENTORYENTRIES.LIST": [stock(line("Sales", 1000))],
    };
    const got = voucherLedgerLines(v["ALLLEDGERENTRIES.LIST"], v, ev);
    assert.equal(balance(got), 0);
    assert.equal(byName(got).Sales[0], 1000);
  });

  test("vouchers without stock lines are stored exactly as before", () => {
    const v = { "ALLLEDGERENTRIES.LIST": [line("Cash", -250), line("Rent", 250)] };
    const items = v["ALLLEDGERENTRIES.LIST"];
    assert.deepEqual(voucherLedgerLines(items, v, ev), mergeLedgerLines(items, ev));
  });

  test("broken / empty stock lines are ignored", () => {
    const v = {
      "ALLLEDGERENTRIES.LIST": [line("Cash", -10), line("Sales", 10)],
      "ALLINVENTORYENTRIES.LIST": [null, "", { STOCKITEMNAME: ["x"] }, stock(null)],
    };
    const items = v["ALLLEDGERENTRIES.LIST"];
    assert.deepEqual(voucherLedgerLines(items, v, ev), mergeLedgerLines(items, ev));
  });
});

// The AMOUNT's sign is the side Tally posts. A minus discount / freight line
// on an invoice keeps ISDEEMEDPOSITIVE "No" with a negative AMOUNT (GI: Sales
// 171, 19-Apr-2023, "SPL DISCOUNT BY MD SIR" AMOUNT -10000 → Tally Dr 10,000;
// the flag alone stored it as Cr and the voucher was 20,000 off).
describe("side from the amount's sign", () => {
  const raw = (name, amount, deemed) => ({ LEDGERNAME: [name], AMOUNT: [String(amount)], ISDEEMEDPOSITIVE: [deemed] });

  test("a minus discount on a sales invoice is a debit, the voucher balances", () => {
    const items = [
      raw("DEEPAK JI", -170174, "Yes"),
      raw("Revenue From Banquets@18%", 168000, "No"),
      raw("Revenue From Room @12%", 11974, "No"),
      raw("HOTEL EXP", 200, "No"),
      raw("SPL DISCOUNT BY MD SIR", -10000, "No"), // flag says Cr, amount says Dr
    ];
    const got = mergeLedgerLines(items, ev);
    assert.deepEqual(byName(got)["SPL DISCOUNT BY MD SIR"], [10000, false]); // debit
    assert.equal(balance(got), 0);
  });

  test("item invoice with a minus freight line (GI Sales 3837, 2-Jan-2026)", () => {
    const v = {
      "ALLLEDGERENTRIES.LIST": [raw("Kitchen Sales", -2610, "Yes"), raw("FREIGHT GST", -70, "No")],
      "ALLINVENTORYENTRIES.LIST": [stock(raw("Kitchen", 2000, "No")), stock(raw("Kitchen", 680, "No"))],
    };
    const got = voucherLedgerLines(v["ALLLEDGERENTRIES.LIST"], v, ev);
    assert.deepEqual(byName(got), {
      "Kitchen Sales": [2610, false],
      "FREIGHT GST": [70, false], // debit, as in Tally
      Kitchen: [2680, true],
    });
    assert.equal(balance(got), 0);
  });

  test("when flag and sign agree nothing changes", () => {
    const items = [line("Party", -118), line("Sales", 100), line("GST", 18)];
    assert.deepEqual(byName(mergeLedgerLines(items, ev)), { Party: [118, false], Sales: [100, true], GST: [18, true] });
  });

  test("a line of zero keeps its flag's side", () => {
    assert.deepEqual(mergeLedgerLines([raw("R/O", 0, "No")], ev), [
      { ledger_name: "R/O", amount: 0, is_debit: true, gross_dr: 0, gross_cr: 0 },
    ]);
  });
});

// Tally's Cash Flow: its own flag per voucher, and each ledger's Dr and Cr
// lines before netting (GI 4-Jul-2023 Receipt #1176: MSWIPE BILL A/C Dr
// 217.29 + Dr 39.11 + Cr 5.40 → Tally counts Out 256.40 and In 5.40).
describe("cash flow", () => {
  const { cashFlowFlag } = require(path.join(AGENT_DIR, "lib", "voucherLines.cjs"));
  const raw = (name, amount) => ({ LEDGERNAME: [name], AMOUNT: [String(amount)], ISDEEMEDPOSITIVE: [amount < 0 ? "Yes" : "No"] });

  test("gross Dr / Cr per ledger, the stored net unchanged", () => {
    const got = mergeLedgerLines(
      [raw("M-Swipe", 30734), raw("MSWIPE BILL A/C", -217.29), raw("MSWIPE BILL A/C", -39.11), raw("MSWIPE BILL A/C", 5.4)],
      ev
    );
    const bill = got.find((l) => l.ledger_name === "MSWIPE BILL A/C");
    assert.deepEqual(bill, { ledger_name: "MSWIPE BILL A/C", amount: 251, is_debit: false, gross_dr: 256.4, gross_cr: 5.4 });
    assert.deepEqual(got.find((l) => l.ledger_name === "M-Swipe"), {
      ledger_name: "M-Swipe",
      amount: 30734,
      is_debit: true,
      gross_dr: 0,
      gross_cr: 30734,
    });
  });

  test("HASCASHFLOW: Yes / No / not in the export", () => {
    assert.equal(cashFlowFlag({ HASCASHFLOW: ["Yes"] }, ev), true);
    assert.equal(cashFlowFlag({ HASCASHFLOW: ["No"] }, ev), false);
    assert.equal(cashFlowFlag({}, ev), null);
    assert.equal(cashFlowFlag(null, ev), null);
  });
});
