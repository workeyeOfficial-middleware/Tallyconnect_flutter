// Tests for the Agent's mobile entry rules (node --test), run against
// tally-agent/lib/mobileVouchers.cjs — no Tally needed.
//   AGENT_DIR=<path to tally-agent> node --test mobileVouchers.test.cjs
"use strict";
const { test, describe } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const AGENT_DIR = process.env.AGENT_DIR || path.join(__dirname, "..", "..", "..", "tally-agent");
const m = require(path.join(AGENT_DIR, "lib", "mobileVouchers.cjs"));

const LEDGERS = [
  { name: "Cash", parent: "Cash-in-Hand" },
  { name: "HDFC Bank – Current", parent: "Bank Accounts" },
  { name: "ICICI OD", parent: "Bank OD A/c" },
  { name: "SBI Branch 2", parent: "Branch Banks" }, // sub-group of Bank Accounts
  { name: "Rent A/c", parent: "Indirect Expenses" },
  { name: "Gupta Traders", parent: "Sundry Debtors" },
];
const GROUPS = [
  { name: "Cash-in-Hand", parent: "Current Assets" },
  { name: "Bank Accounts", parent: "Current Assets" },
  { name: "Bank OD A/c", parent: "Loans (Liability)" },
  { name: "Branch Banks", parent: "Bank Accounts" },
  { name: "Indirect Expenses", parent: "" },
  { name: "Sundry Debtors", parent: "Current Assets" },
  { name: "Current Assets", parent: "" },
];

const contra = (from, to, amount = 5000) => ({
  voucher_type: "Contra",
  voucher_guid: "G-1",
  voucher_date: "2026-10-15",
  voucher_no: "C-7",
  reference_no: "UTR123",
  narration: "Cash deposited",
  ledger_entries: [
    { ledger_name: to, amount, is_debit: true },
    { ledger_name: from, amount, is_debit: false },
  ],
});

const rejects = (fn, re) =>
  assert.throws(fn, (e) => e.isValidationError === true && re.test(e.message));

describe("mobile entries (Agent)", () => {
  test("party: only Sales / Purchase / Receipt / Payment need one", () => {
    for (const t of ["Sales", "Purchase", "Receipt", "Payment"]) assert.equal(m.needsParty(t), true, t);
    for (const t of ["Journal", "Contra", "", undefined]) assert.equal(m.needsParty(t), false, String(t));
  });

  test("Journal / Contra: existing ledgers only (exact Tally name back)", () => {
    assert.equal(m.needsExistingLedgers("Journal"), true);
    assert.equal(m.needsExistingLedgers("Contra"), true);
    for (const t of ["Sales", "Purchase", "Receipt", "Payment"]) assert.equal(m.needsExistingLedgers(t), false);
    const out = m.resolveExistingLedgers(
      [
        { ledger_name: "  rent a/c ", amount: 10, is_debit: true },
        { ledger_name: "CASH", amount: 10, is_debit: false },
      ],
      LEDGERS
    );
    assert.deepEqual(out.map((e) => e.ledger_name), ["Rent A/c", "Cash"]);
    rejects(
      () => m.resolveExistingLedgers([{ ledger_name: "Rnet A/c" }, { ledger_name: "Cash" }], LEDGERS),
      /Ledger not found in Tally: Rnet A\/c/
    );
  });

  test("cash / bank groups, also through sub-groups", () => {
    assert.equal(m.isCashOrBankGroup("Cash-in-Hand", GROUPS), true);
    assert.equal(m.isCashOrBankGroup("bank od a/c", GROUPS), true);
    assert.equal(m.isCashOrBankGroup("Branch Banks", GROUPS), true);
    assert.equal(m.isCashOrBankGroup("Indirect Expenses", GROUPS), false);
    assert.equal(m.isCashOrBankGroup("Sundry Debtors", GROUPS), false);
    // A loop in the group list never hangs.
    assert.equal(m.isCashOrBankGroup("A", [{ name: "A", parent: "B" }, { name: "B", parent: "A" }]), false);
  });

  test("Contra: valid cash → bank, OD and sub-group banks", () => {
    const out = m.checkContra(contra("cash", "hdfc bank – current"), LEDGERS, GROUPS);
    assert.deepEqual(
      out.map((e) => [e.ledger_name, e.is_debit]),
      [
        ["HDFC Bank – Current", true],
        ["Cash", false],
      ]
    );
    m.checkContra(contra("ICICI OD", "SBI Branch 2"), LEDGERS, GROUPS);
  });

  test("Contra: refused entries", () => {
    rejects(() => m.checkContra(contra("Cash", "Rent A/c"), LEDGERS, GROUPS), /only for cash and bank.*Rent A\/c/);
    rejects(() => m.checkContra(contra("Cash", "Gupta Traders"), LEDGERS, GROUPS), /Gupta Traders/);
    rejects(() => m.checkContra(contra("Cash", "cash"), LEDGERS, GROUPS), /different accounts/);
    rejects(() => m.checkContra(contra("Cash", "Nowhere Bank"), LEDGERS, GROUPS), /not found in Tally: Nowhere Bank/);
    rejects(() => m.checkContra(contra("Cash", "HDFC Bank – Current", 0), LEDGERS, GROUPS), /Invalid Contra amount/);
    const unbalanced = contra("Cash", "HDFC Bank – Current");
    unbalanced.ledger_entries[0].amount = 5001;
    rejects(() => m.checkContra(unbalanced, LEDGERS, GROUPS), /not balanced/);
    rejects(() => m.checkContra({ ledger_entries: [] }, LEDGERS, GROUPS), /'from' and a 'to'/);
  });

  test("Contra XML: Dr negative + deemed positive, Cr positive; escaped", () => {
    const p = contra("Cash", "HDFC Bank – Current", 5000);
    p.narration = "Deposit <cash> & coins";
    const xml = m.buildContraXml({ action: "CREATE", payload: p, companyName: "A & B Traders", date: "20261015" });
    assert.match(xml, /<VOUCHER ACTION="Create" VCHTYPE="Contra">/);
    assert.match(xml, /<VOUCHERTYPENAME>Contra<\/VOUCHERTYPENAME>/);
    assert.match(xml, /<SVCOMPANY>A &amp; B Traders<\/SVCOMPANY>/);
    assert.match(xml, /<DATE>20261015<\/DATE>/);
    assert.match(xml, /<VOUCHERNUMBER>C-7<\/VOUCHERNUMBER>/);
    assert.match(xml, /<REFERENCE>UTR123<\/REFERENCE>/);
    assert.match(xml, /<GUID>G-1<\/GUID>/);
    assert.match(xml, /<NARRATION>Deposit &lt;cash&gt; &amp; coins<\/NARRATION>/);
    const lines = [...xml.matchAll(/<ALLLEDGERENTRIES\.LIST>([\s\S]*?)<\/ALLLEDGERENTRIES\.LIST>/g)].map((x) => x[1]);
    assert.equal(lines.length, 2);
    assert.match(lines[0], /<LEDGERNAME>HDFC Bank – Current<\/LEDGERNAME>/);
    assert.match(lines[0], /<ISDEEMEDPOSITIVE>Yes<\/ISDEEMEDPOSITIVE>/);
    assert.match(lines[0], /<AMOUNT>-5000\.00<\/AMOUNT>/);
    assert.match(lines[1], /<LEDGERNAME>Cash<\/LEDGERNAME>/);
    assert.match(lines[1], /<ISDEEMEDPOSITIVE>No<\/ISDEEMEDPOSITIVE>/);
    assert.match(lines[1], /<AMOUNT>5000\.00<\/AMOUNT>/);
    // Optional fields left out when empty.
    const bare = m.buildContraXml({
      action: "CREATE",
      payload: { ...p, voucher_no: null, reference_no: "", narration: "" },
      companyName: "X",
      date: "20261015",
    });
    assert.doesNotMatch(bare, /VOUCHERNUMBER|REFERENCE|NARRATION/);
    assert.throws(() => m.buildContraXml({ action: "CREATE", payload: p, companyName: "X", date: "" }), /date missing/);
  });
});
