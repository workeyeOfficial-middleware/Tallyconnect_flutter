// Tests for the financial reports (node --test). No database or network:
// a worked, balanced sample company (figures checked by hand), an
// in-memory fake pg pool and a stub login. Needs only `express`.
import { test, describe, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import express from "express";

import {
  balanceSheet,
  expenseReport,
  groupIndex,
  ledgerRowsAt,
  nameKey,
  profitLoss,
  trialBalance,
} from "../utils/financialCore.js";
import { createFinancialRouter } from "../utils/financialRouter.js";

/* ------------------------------------------------- sample company */
// Tally's predefined primary groups (flags as Tally reports them).
const G = (name, parent, rev, dp, gp = false) => ({
  name, parent, is_revenue: rev, is_deemed_positive: dp, affects_gross_profit: gp,
});
const GROUPS = [
  G("Capital Account", "Primary", false, false),
  G("Loans (Liability)", "Primary", false, false),
  G("Current Liabilities", "Primary", false, false),
  G("Sundry Creditors", "Current Liabilities", false, false),
  G("Duties & Taxes", "Current Liabilities", false, false),
  G("Fixed Assets", "Primary", false, true),
  G("Current Assets", "Primary", false, true),
  G("Sundry Debtors", "Current Assets", false, true),
  G("Bank Accounts", "Current Assets", false, true),
  G("Cash-in-Hand", "Current Assets", false, true),
  G("Stock-in-Hand", "Current Assets", false, true),
  G("Sales Accounts", "Primary", true, false, true),
  G("Purchase Accounts", "Primary", true, true, true),
  G("Direct Expenses", "Primary", true, true, true),
  G("Direct Incomes", "Primary", true, false, true),
  G("Indirect Expenses", "Primary", true, true, false),
  G("Office Expenses", "Indirect Expenses", true, true, false), // user sub-group
  G("Indirect Incomes", "Primary", true, false, false),
];
const L = (name, parent, closing) => ({ name, guid: `g-${name}`, parent, closing, opening: 0 });

// As on 30-09-2026 (FY from 01-04-2026). Tally sign: Dr negative.
const SEP = {
  as_on: "2026-09-30",
  fy_from: "2026-04-01",
  ledgers: [
    L("Capital A/c", "Capital Account", 115000),
    L("HDFC Bank", "Bank Accounts", -60000),
    L("Cash", "Cash-in-Hand", -5000),
    L("Mehta Electricals", "Sundry Debtors", -77000),
    L("Polycab Wires", "Sundry Creditors", 30000),
    L("GST Payable", "Duties & Taxes", 5000),
    L("Furniture", "Fixed Assets", -50000),
    L("Sales", "Sales Accounts", 200000),
    L("Purchase", "Purchase Accounts", -120000),
    L("Freight Inward", "Direct Expenses", -5000),
    L("Office Rent", "Office Expenses", -12000),
    L("Salary", "Indirect Expenses", -18000),
    L("Interest Received", "Indirect Incomes", 2000),
    L("Profit & Loss A/c", "Primary", 10000), // earlier years' profit
  ],
  groups: [{ name: "Stock-in-Hand", parent: "Current Assets", closing: -25000, opening: -15000 }],
};
// As on 31-08-2026 (for a September-only period).
const AUG = {
  as_on: "2026-08-31",
  fy_from: "2026-04-01",
  ledgers: [
    L("Capital A/c", "Capital Account", 115000),
    L("HDFC Bank", "Bank Accounts", -40000),
    L("Cash", "Cash-in-Hand", -5000),
    L("Mehta Electricals", "Sundry Debtors", -60000),
    L("Polycab Wires", "Sundry Creditors", 20000),
    L("GST Payable", "Duties & Taxes", 4000),
    L("Furniture", "Fixed Assets", -50000),
    L("Sales", "Sales Accounts", 150000),
    L("Purchase", "Purchase Accounts", -90000),
    L("Freight Inward", "Direct Expenses", -4000),
    L("Office Rent", "Office Expenses", -10000),
    L("Salary", "Indirect Expenses", -15000),
    L("Interest Received", "Indirect Incomes", 1000),
    L("Profit & Loss A/c", "Primary", 10000),
  ],
  groups: [{ name: "Stock-in-Hand", parent: "Current Assets", closing: -20000, opening: -15000 }],
};

describe("core: worked example", () => {
  test("group tree: primary group and nature of a user sub-group", () => {
    const idx = groupIndex(GROUPS);
    assert.deepEqual(idx.info("Office Expenses"), { primary: "Indirect Expenses", nature: "expense", direct: false });
    assert.equal(idx.info("Sundry Debtors").nature, "asset");
    assert.equal(idx.info("Duties & Taxes").nature, "liability");
    assert.equal(idx.info("Sales Accounts").direct, true);
    // A loop in bad data never hangs.
    const loop = groupIndex([G("A", "B", false, true), G("B", "A", false, true)]);
    assert.ok(loop.info("A") !== undefined);
  });

  test("Trial Balance: Dr = Cr (opening stock as in Tally's TB)", () => {
    const tb = trialBalance(GROUPS, SEP);
    assert.equal(tb.opening_stock, 15000);
    assert.equal(tb.total_debit, 362000);
    assert.equal(tb.total_credit, 362000);
    assert.equal(tb.difference, 0);
    const ca = tb.sections.find((s) => s.name === "Current Assets");
    assert.equal(ca.amount, 157000); // 60000 + 5000 + 77000 + opening stock 15000
    const ie = tb.sections.find((s) => s.name === "Indirect Expenses");
    assert.equal(ie.amount, 30000);
    assert.deepEqual(ie.children.map((c) => [c.name, c.amount]), [["Office Expenses", 12000], ["Salary", 18000]].sort((a, b) => b[1] - a[1]));
    assert.ok(tb.sections.some((s) => s.name === "Other ledgers")); // P&L A/c under Primary
    assert.deepEqual(tb.ungrouped, []);
  });

  test("P&L for the year so far: gross and net profit", () => {
    const pl = profitLoss(GROUPS, SEP, null);
    assert.equal(pl.trading.opening_stock, 15000);
    assert.equal(pl.trading.closing_stock, 25000);
    assert.equal(pl.trading.total_income, 225000); // 200000 + closing stock 25000
    assert.equal(pl.trading.total_expense, 140000); // 120000 + 5000 + opening stock 15000
    assert.equal(pl.gross_profit, 85000);
    assert.equal(pl.indirect.total_income, 2000);
    assert.equal(pl.indirect.total_expense, 30000);
    assert.equal(pl.net_profit, 57000);
  });

  test("P&L for one month (September): movements and stock change", () => {
    const pl = profitLoss(GROUPS, SEP, AUG);
    // Sales 50000; purchases 30000; freight 1000; stock 20000 → 25000.
    assert.equal(pl.trading.opening_stock, 20000);
    assert.equal(pl.trading.closing_stock, 25000);
    assert.equal(pl.gross_profit, 50000 + 25000 - (30000 + 1000 + 20000)); // 24000
    // Rent 2000 + salary 3000; interest 1000.
    assert.equal(pl.net_profit, 24000 + 1000 - 5000);
  });

  test("Balance Sheet balances, with P&L A/c = earlier years + this year", () => {
    const bs = balanceSheet(GROUPS, SEP);
    assert.deepEqual(bs.profit_loss, { opening: 10000, current_period: 57000, total: 67000 });
    assert.equal(bs.total_liabilities, 217000); // 115000 + 35000 + 67000
    assert.equal(bs.total_assets, 217000); // 50000 + 60000 + 5000 + 77000 + stock 25000
    assert.equal(bs.difference, 0);
    const ca = bs.assets.find((s) => s.name === "Current Assets");
    assert.ok(ca.children.some((c) => c.name === "Stock-in-Hand" && c.amount === 25000));
  });

  test("Expense report: purchases optional, top ledgers, month-wise", () => {
    const ex = expenseReport(GROUPS, SEP, null, { months: [AUG, SEP] });
    assert.equal(ex.total, 35000); // freight 5000 + rent 12000 + salary 18000
    assert.equal(ex.top_ledgers[0].name, "Salary");
    assert.deepEqual(ex.by_month.map((m) => m.amount), [29000, 6000]); // Apr–Aug, Sep
    const withP = expenseReport(GROUPS, SEP, null, { includePurchases: true });
    assert.equal(withP.total, 155000);
  });
});

/* ---------------------------------------------------------- routes */
// Anchor model: one anchor per year (Tally's balances on 31-03-2026) +
// the synced voucher entries + stock values. Worked figures below.
const ANCHOR_LEDGERS = [
  L("Capital A/c", "Capital Account", 115000),
  L("HDFC Bank", "Bank Accounts", -40000),
  L("Cash", "Cash-in-Hand", -5000),
  L("Mehta Electricals", "Sundry Debtors", -30000),
  L("Polycab Wires", "Sundry Creditors", 20000),
  L("GST Payable", "Duties & Taxes", 0),
  L("Furniture", "Fixed Assets", -50000),
  L("Sales", "Sales Accounts", 500000), // last year's: must not carry over
  L("Purchase", "Purchase Accounts", -300000), // last year's
  L("Profit & Loss A/c", "Primary", 10000),
];
const MASTERS = [
  ...ANCHOR_LEDGERS.map((l) => ({ name: l.name, ledger_guid: l.guid, parent_group: l.parent, opening_balance: "0" })),
  { name: "Office Rent", ledger_guid: "g-rent", parent_group: "Office Expenses", opening_balance: "0" },
  { name: "Salary", ledger_guid: "g-sal", parent_group: "Indirect Expenses", opening_balance: "0" },
  { name: "Interest Received", ledger_guid: "g-int", parent_group: "Indirect Incomes", opening_balance: "0" },
  // Created after the anchor was taken: its books opening counts.
  { name: "Late Debtor", ledger_guid: "g-late", parent_group: "Sundry Debtors", opening_balance: "-1000" },
];
// Balanced vouchers (each Dr = Cr) plus ones that must be left out.
const E = (date, type, lines, extra = {}) =>
  // Stored as the Agent stores it: is_debit = ISDEEMEDPOSITIVE "No" = a CREDIT line.
  lines.map(([name, dr, amt], i) => ({ voucher_guid: `${date}-${type}-${extra.tag || ""}`, voucher_date: date, voucher_type: type, ledger_name: name, is_debit: !dr, amount: amt, is_active: true, ...extra }));
const ENTRIES = [
  ...E("2026-05-10", "Sales", [["Mehta Electricals", true, 100000], ["Sales", false, 100000]]),
  ...E("2026-06-15", "Purchase", [["Purchase", true, 60000], ["Polycab Wires", false, 60000]]),
  ...E("2026-07-01", "Receipt", [["HDFC Bank", true, 50000], ["Mehta Electricals", false, 50000]]),
  ...E("2026-08-20", "Sales", [["Mehta Electricals", true, 100000], ["Sales", false, 100000]]),
  ...E("2026-09-05", "Payment", [["Office Rent", true, 12000], ["HDFC Bank", false, 12000]]),
  ...E("2026-09-25", "Payment", [["Salary", true, 18000], ["HDFC Bank", false, 18000]]),
  ...E("2026-09-30", "Receipt", [["HDFC Bank", true, 2000], ["Interest Received", false, 2000]]),
  // Left out: memorandum, deleted (inactive), before the anchor.
  ...E("2026-08-02", "Memorandum", [["Salary", true, 99999], ["HDFC Bank", false, 99999]]),
  ...E("2026-08-03", "Sales", [["Mehta Electricals", true, 777], ["Sales", false, 777]], { is_active: false }),
  ...E("2026-03-20", "Sales", [["Mehta Electricals", true, 5555], ["Sales", false, 5555]]),
];

class FakeDb {
  constructor() {
    this.active = { 7: "CO-1", 8: "CO-9" };
    this.companies = [
      { admin_id: 7, company_guid: "CO-1", name: "Ravi Traders" },
      { admin_id: 7, company_guid: "CO-2", name: "Ravi Exports" },
      { admin_id: 8, company_guid: "CO-9", name: "Other" },
    ];
    this.users = [
      { id: 21, admin_id: 7, role: "USER" },
      { id: 22, admin_id: 7, role: "USER" },
      { id: 31, admin_id: 8, role: "USER" },
    ];
    this.access = [];
    this.groups = [];
    this.batches = [];
    this.ledgerRows = [];
    this.groupRows = [];
    this.snapshots = [];
    this.stockValues = [];
    this.books = [];
    this.nextId = 1;
    // Synced data of CO-1 (account 7).
    this.ledgers = MASTERS.map((m) => ({ admin_id: 7, company_guid: "CO-1", ...m }));
    this.entries = ENTRIES.map((e) => ({ admin_id: 7, company_guid: "CO-1", ...e }));
    this.stockSummary = [
      { admin_id: 7, company_guid: "CO-1", closing_value: "20000" },
      { admin_id: 7, company_guid: "CO-1", closing_value: "6000" },
    ];
  }
  connect() {
    return { query: (s, p) => this.query(s, p), release() {} };
  }
  async query(sql, p = []) {
    const s = sql.replace(/\s+/g, " ").trim();
    const mine = (x) => x.admin_id === p[0] && x.company_guid === p[1];
    if (s === "BEGIN" || s === "COMMIT" || s === "ROLLBACK") return { rows: [] };
    if (s.startsWith("SELECT 1 FROM companies")) {
      const r = this.companies.filter((c) => c.company_guid === p[0] && c.admin_id === p[1]);
      return { rows: r, rowCount: r.length };
    }
    if (s.includes("FROM active_company ac")) {
      const g = this.active[p[0]];
      const c = this.companies.find((x) => x.admin_id === p[0] && x.company_guid === g);
      return { rows: g ? [{ company_guid: g, company_name: c?.name }] : [] };
    }
    if (s.startsWith("DELETE FROM tally_groups")) {
      this.groups = this.groups.filter((g) => !mine(g));
      return { rows: [] };
    }
    if (s.startsWith("INSERT INTO tally_groups")) {
      for (const x of JSON.parse(p[2])) this.groups.push({ admin_id: p[0], company_guid: p[1], ...x });
      return { rows: [] };
    }
    if (s.startsWith("SELECT name, parent, is_revenue")) return { rows: this.groups.filter(mine) };
    if (s.startsWith("DELETE FROM fin_batches WHERE admin_id")) return { rows: [] };
    if (s.startsWith("INSERT INTO fin_batches")) {
      const b = { id: this.nextId++, admin_id: p[0], company_guid: p[1], as_on: p[2], fy_from: p[3], kind: p[4], committed_at: null };
      this.batches.push(b);
      return { rows: [{ id: b.id }] };
    }
    if (s.startsWith("SELECT id, admin_id, company_guid, as_on, fy_from, kind, committed_at FROM fin_batches")) {
      return { rows: this.batches.filter((b) => b.id === p[0] && b.admin_id === p[1]) };
    }
    if (s.startsWith("INSERT INTO fin_ledger_balances")) {
      for (const x of JSON.parse(p[1])) this.ledgerRows.push({ batch_id: p[0], ...x });
      return { rows: [] };
    }
    if (s.startsWith("INSERT INTO fin_group_balances")) {
      for (const x of JSON.parse(p[1])) this.groupRows.push({ batch_id: p[0], ...x });
      return { rows: [] };
    }
    if (s.includes("FROM fin_ledger_balances WHERE batch_id = $1) AS ledgers")) {
      return {
        rows: [{
          ledgers: this.ledgerRows.filter((r) => r.batch_id === p[0]).length,
          groups: this.groupRows.filter((r) => r.batch_id === p[0]).length,
        }],
      };
    }
    if (s.startsWith("SELECT batch_id FROM fin_snapshots")) {
      return { rows: this.snapshots.filter((x) => mine(x) && x.as_on === p[2]) };
    }
    if (s.startsWith("INSERT INTO fin_snapshots")) {
      const i = this.snapshots.findIndex((x) => mine(x) && x.as_on === p[2]);
      const row = { admin_id: p[0], company_guid: p[1], as_on: p[2], fy_from: p[3], batch_id: p[4], kind: p[5], synced_at: new Date() };
      if (i >= 0) this.snapshots[i] = row;
      else this.snapshots.push(row);
      return { rows: [] };
    }
    if (s.startsWith("UPDATE fin_batches SET committed_at")) {
      this.batches.find((b) => b.id === p[0]).committed_at = new Date();
      return { rows: [] };
    }
    if (s.startsWith("DELETE FROM fin_ledger_balances")) {
      this.ledgerRows = this.ledgerRows.filter((r) => r.batch_id !== p[0]);
      return { rows: [] };
    }
    if (s.startsWith("DELETE FROM fin_group_balances")) {
      this.groupRows = this.groupRows.filter((r) => r.batch_id !== p[0]);
      return { rows: [] };
    }
    if (s.startsWith("DELETE FROM fin_batches WHERE id")) {
      this.batches = this.batches.filter((b) => b.id !== p[0]);
      return { rows: [] };
    }
    if (s.startsWith("SELECT as_on, batch_id, kind FROM fin_snapshots")) {
      return { rows: this.snapshots.filter((x) => mine(x) && x.as_on < p[2]) };
    }
    if (s.startsWith("DELETE FROM fin_snapshots")) {
      this.snapshots = this.snapshots.filter((x) => !(mine(x) && x.as_on === p[2]));
      return { rows: [] };
    }
    if (s.includes("FROM fin_snapshots WHERE admin_id = $1 AND company_guid = $2 AND kind = 'anchor'")) {
      return { rows: this.snapshots.filter((x) => mine(x) && x.kind === "anchor").sort((a, b) => a.as_on.localeCompare(b.as_on)) };
    }
    if (s.startsWith("INSERT INTO fin_stock_values")) {
      for (const x of JSON.parse(p[2])) {
        this.stockValues = this.stockValues.filter((v) => !(mine(v) && v.as_on === x.as_on));
        this.stockValues.push({ admin_id: p[0], company_guid: p[1], ...x });
      }
      return { rows: [] };
    }
    if (s.startsWith("SELECT as_on, value FROM fin_stock_values")) return { rows: this.stockValues.filter(mine) };
    if (s.startsWith("INSERT INTO fin_books")) {
      this.books = this.books.filter((x) => !mine(x));
      this.books.push({ admin_id: p[0], company_guid: p[1], books_from: p[2], vouchers_from: p[3], fy_from: p[4], opening_stock: String(p[5]) });
      return { rows: [] };
    }
    if (s.startsWith("SELECT books_from, vouchers_from, fy_from, opening_stock FROM fin_books")) return { rows: this.books.filter(mine) };
    if (s.includes("FROM stock_summary")) {
      const r = this.stockSummary.filter(mine);
      return { rows: [{ n: r.length, value: r.reduce((a, x) => a + Number(x.closing_value), 0) }] };
    }
    if (s.startsWith("SELECT name, ledger_guid AS guid, parent_group AS parent")) {
      return { rows: this.ledgers.filter(mine).map((x) => ({ name: x.name, guid: x.ledger_guid, parent: x.parent_group, opening: x.opening_balance })) };
    }
    if (s.startsWith("SELECT ledger_name AS name, ledger_guid AS guid, parent, closing FROM fin_ledger_balances")) {
      return { rows: this.ledgerRows.filter((r) => r.batch_id === p[0]).map((r) => ({ name: r.name, guid: r.guid, parent: r.parent, closing: String(r.closing) })) };
    }
    if (s.startsWith("SELECT group_name AS name, closing FROM fin_group_balances")) {
      return { rows: this.groupRows.filter((r) => r.batch_id === p[0]).map((r) => ({ name: r.name, closing: String(r.closing) })) };
    }
    if (s.includes("FROM voucher_entries ve")) {
      assert.ok(s.includes("COALESCE(ve.is_active, TRUE) = TRUE"));
      assert.ok(s.includes("CASE WHEN ve.is_debit THEN ve.amount ELSE -ve.amount END"));
      const re = /!~\* '([^']+)'/.exec(s);
      const skip = new RegExp(re[1], "i");
      const rows = this.entries.filter(
        (e) => mine(e) && e.voucher_date > p[2] && e.voucher_date <= p[3] && e.is_active !== false && !skip.test(e.voucher_type || "")
      );
      if (s.includes("GROUP BY ve.voucher_guid")) {
        const by = new Map();
        for (const e of rows) by.set(e.voucher_guid, (by.get(e.voucher_guid) || 0) + (e.is_debit ? e.amount : -e.amount));
        const bad = [...by.values()].filter((v) => Math.abs(v) >= 0.01);
        return { rows: [{ n: bad.length, gap: String(bad.reduce((a, v) => a + Math.abs(v), 0)) }] };
      }
      const monthly = s.includes("TO_CHAR");
      const by = new Map();
      for (const e of rows) {
        const k = monthly ? `${e.ledger_name}|${e.voucher_date.slice(0, 7)}` : e.ledger_name;
        by.set(k, (by.get(k) || 0) + (e.is_debit ? e.amount : -e.amount));
      }
      return {
        rows: [...by].map(([k, net]) =>
          monthly ? { name: k.split("|")[0], month: k.split("|")[1], net: String(net) } : { name: k, net: String(net) }
        ),
      };
    }
    if (s.startsWith("SELECT 1 FROM financial_report_access")) {
      const r = this.access.filter((a) => a.admin_id === p[0] && a.user_id === p[1]);
      return { rows: r, rowCount: r.length };
    }
    if (s.startsWith("SELECT user_id FROM financial_report_access")) return { rows: this.access.filter((a) => a.admin_id === p[0]) };
    if (s.startsWith("SELECT id FROM users")) {
      const r = this.users.filter((u) => u.id === p[0] && u.admin_id === p[1] && u.role !== "ADMIN");
      return { rows: r, rowCount: r.length };
    }
    if (s.startsWith("INSERT INTO financial_report_access")) {
      if (!this.access.some((a) => a.admin_id === p[0] && a.user_id === p[1])) this.access.push({ admin_id: p[0], user_id: p[1] });
      return { rows: [] };
    }
    if (s.startsWith("DELETE FROM financial_report_access")) {
      this.access = this.access.filter((a) => !(a.admin_id === p[0] && a.user_id === p[1]));
      return { rows: [] };
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
const USER = { id: 21, adminId: 7, role: "USER" };
const OTHER_ADMIN = { id: 8, adminId: 8, role: "ADMIN" };

/* --------------------------- names as Tally compares them (nameKey) */
// Live data: masters keep Tally's exact name ("DAIKIN  AIR…", a trailing
// line break, other capitals) while voucher lines were stored collapsed
// ("DAIKIN AIR…"). They are ONE ledger and must not drop out of a report.
describe("ledger names: spaces, line breaks and capitals", () => {
  test("nameKey", () => {
    assert.equal(nameKey("DAIKIN  AIR CONDITIONING"), "daikin air conditioning");
    assert.equal(nameKey("DIVISIONAL RAILWAY MANAGER,\nEAST CENTRAL"), "divisional railway manager, east central");
    assert.equal(nameKey("Alumayer India Pvt. Ltd.\n"), "alumayer india pvt. ltd.");
    assert.equal(nameKey("TDS RECEIVABLE"), nameKey("TDS Receivable"));
    assert.equal(nameKey(null), "");
  });

  test("a voucher line in another spelling counts on the master's ledger and group", () => {
    const rows = ledgerRowsAt({
      groups: GROUPS,
      anchorRows: [],
      carryRevenue: false,
      masters: [
        { name: "DAIKIN  AIR CONDITIONING", guid: "g-daikin", parent: "Sundry Creditors", opening: 1000 },
        { name: "North Bihar Power\n", guid: "g-nbp", parent: "Office Expenses", opening: 0 },
      ],
      movements: new Map([
        ["DAIKIN AIR CONDITIONING", 500],
        ["daikin  air conditioning", 250], // a second spelling of the same ledger
        ["North Bihar Power", -199582],
      ]),
    });
    assert.equal(rows.length, 2, "one row per ledger, not one per spelling");
    const daikin = rows.find((r) => r.guid === "g-daikin");
    assert.equal(daikin.name, "DAIKIN  AIR CONDITIONING");
    assert.equal(daikin.parent, "Sundry Creditors");
    assert.equal(daikin.closing, 1750);
    const nbp = rows.find((r) => r.guid === "g-nbp");
    assert.equal(nbp.parent, "Office Expenses");
    assert.equal(nbp.closing, -199582);
    // …and it reaches the P&L instead of "Primary".
    const pl = profitLoss(GROUPS, { as_on: "2026-09-30", fy_from: "2026-04-01", ledgers: rows, groups: [] }, null);
    assert.equal(pl.indirect.total_expense, 199582);
  });

  test("group names that differ only in spacing / capitals still form the tree", () => {
    const groups = [...GROUPS, G("Staff  Advances", "current assets", false, true)];
    const idx = groupIndex(groups);
    assert.equal(idx.info("staff advances").nature, "asset");
    const tb = trialBalance(groups, {
      as_on: "2026-09-30",
      fy_from: "2026-04-01",
      ledgers: [L("Raj Kumar", "Staff Advances", -500), L("Capital A/c", "Capital Account", 500)],
      groups: [],
    });
    assert.deepEqual(tb.ungrouped, []);
    assert.equal(tb.total_debit, 500);
    assert.equal(tb.total_credit, 500);
  });
});

describe("routes (anchor + vouchers)", () => {
  let db, server, base;
  beforeEach(async () => {
    db = new FakeDb();
    const app = express();
    app.use(express.json({ limit: "20mb" }));
    app.use(createFinancialRouter({ db, auth: stubAuth, log: { error: () => {} }, now: () => new Date("2026-10-12T06:00:00Z") }));
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

  /** What the Agent uploads: groups, the anchor, month-end stock values. */
  async function upload({ user = ADMIN, company = "CO-1", anchor = { as_on: "2026-03-31", fy_from: "2025-04-01", ledgers: ANCHOR_LEDGERS, stock: -15000 }, stock = [["2026-08-31", 20000], ["2026-09-30", 25000]] } = {}) {
    const g = await call("POST", "/api/financial/agent/groups", user, { company_guid: company, groups: GROUPS });
    if (g.status !== 200) return g;
    const b = await call("POST", "/api/financial/agent/snapshot/begin", user, { company_guid: company, as_on: anchor.as_on, fy_from: anchor.fy_from, kind: "anchor" });
    if (b.status !== 200) return b;
    const groups = [{ name: "Stock-in-Hand", parent: "Current Assets", closing: anchor.stock, opening: 0 }];
    await call("POST", "/api/financial/agent/snapshot/rows", user, { batch_id: b.body.batch_id, ledgers: anchor.ledgers, groups });
    const c = await call("POST", "/api/financial/agent/snapshot/commit", user, { batch_id: b.body.batch_id, ledger_count: anchor.ledgers.length, group_count: 1 });
    if (c.status !== 200) return c;
    const v = await call("POST", "/api/financial/agent/stock-values", user, { company_guid: company, values: stock.map(([as_on, value]) => ({ as_on, value })) });
    return v;
  }

  test("dates offered: month ends with stock, and today", async () => {
    assert.equal((await upload()).status, 200);
    const per = await call("GET", "/api/financial/periods", ADMIN);
    assert.equal(per.body.groups_synced, true);
    assert.deepEqual(per.body.snapshots.map((x) => [x.as_on, x.fy_from]), [
      ["2026-10-12", "2026-04-01"],
      ["2026-09-30", "2026-04-01"],
      ["2026-08-31", "2026-04-01"],
    ]);
  });

  test("P&L for the year: from the vouchers, last year's revenue not carried", async () => {
    await upload();
    const pl = (await call("GET", "/api/financial/profit-loss?from=2026-04-01&to=2026-09-30", ADMIN)).body.data;
    assert.equal(pl.trading.opening_stock, 15000); // anchor day
    assert.equal(pl.trading.closing_stock, 25000); // month-end value
    assert.equal(pl.trading.total_income, 225000); // sales 200000 (memo / deleted / before-anchor left out)
    assert.equal(pl.trading.total_expense, 75000); // purchase 60000 + opening stock
    assert.equal(pl.gross_profit, 150000);
    assert.equal(pl.indirect.total_expense, 30000);
    assert.equal(pl.net_profit, 122000);
    // One month: September.
    const sep = (await call("GET", "/api/financial/profit-loss?from=2026-09-01&to=2026-09-30", ADMIN)).body.data;
    assert.equal(sep.gross_profit, 5000); // stock 20000 → 25000
    assert.equal(sep.net_profit, 5000 + 2000 - 30000);
    // Today: closing stock from the stock summary.
    const today = (await call("GET", "/api/financial/profit-loss?from=2026-04-01&to=2026-10-12", ADMIN)).body.data;
    assert.equal(today.trading.closing_stock, 26000);
  });

  test("Balance Sheet balances exactly (balanced vouchers), P&L A/c brought forward", async () => {
    await upload();
    const bs = (await call("GET", "/api/financial/balance-sheet?as_on=2026-09-30", ADMIN)).body.data;
    // Assets: furniture 50000 + bank 62000 + cash 5000 + debtors 180000 + 1000 (new ledger) + stock 25000.
    assert.equal(bs.total_assets, 323000);
    assert.equal(bs.profit_loss.opening, 6000);
    assert.equal(bs.profit_loss.current_period, 122000);
    assert.equal(bs.total_liabilities, 323000);
    assert.equal(bs.difference, 0);
    assert.deepEqual(bs.data_check, { unbalanced_vouchers: 0, unbalanced_amount: 0 });
    // Also at another date and today.
    for (const d of ["2026-08-31", "2026-10-12"]) {
      assert.equal((await call("GET", `/api/financial/balance-sheet?as_on=${d}`, ADMIN)).body.data.difference, 0, d);
    }
  });

  test("Trial Balance and Expenses from the same figures", async () => {
    await upload();
    const tb = (await call("GET", "/api/financial/trial-balance?as_on=2026-09-30", ADMIN)).body.data;
    assert.equal(tb.opening_stock, 15000);
    assert.equal(tb.total_debit, 62000 + 5000 + 180000 + 50000 + 1000 + 60000 + 12000 + 18000 + 15000);
    assert.equal(tb.total_credit, 115000 + 80000 + 200000 + 2000 + 10000);
    const ex = (await call("GET", "/api/financial/expenses?from=2026-04-01&to=2026-09-30", ADMIN)).body.data;
    assert.equal(ex.total, 30000);
    assert.equal(ex.by_month.at(-1).amount, 30000);
    assert.equal(ex.by_month.reduce((a, m) => a + m.amount, 0), 30000);
    const withP = (await call("GET", "/api/financial/expenses?from=2026-04-01&to=2026-09-30&purchases=1", ADMIN)).body.data;
    assert.equal(withP.total, 90000);
  });

  test("an anchor inside the year (vouchers synced from July): still balances", async () => {
    // Tally's balances on 30-06-2026 (this year's revenue to date carried).
    const mid = [
      L("Capital A/c", "Capital Account", 115000),
      L("HDFC Bank", "Bank Accounts", -40000),
      L("Cash", "Cash-in-Hand", -5000),
      L("Mehta Electricals", "Sundry Debtors", -130000),
      L("Polycab Wires", "Sundry Creditors", 80000),
      L("Furniture", "Fixed Assets", -50000),
      L("Sales", "Sales Accounts", 100000),
      L("Purchase", "Purchase Accounts", -60000),
      L("Profit & Loss A/c", "Primary", 10000),
    ];
    db.entries = db.entries.filter((e) => e.voucher_date > "2026-06-30" || e.voucher_date < "2026-04-01");
    await upload({ anchor: { as_on: "2026-06-30", fy_from: "2026-04-01", ledgers: mid, stock: -18000 }, stock: [["2026-03-31", 15000], ["2026-08-31", 20000], ["2026-09-30", 25000]] });
    const pl = (await call("GET", "/api/financial/profit-loss?from=2026-04-01&to=2026-09-30", ADMIN)).body.data;
    assert.equal(pl.trading.total_income, 200000 + 25000); // 100000 to June + 100000 after
    const bs = (await call("GET", "/api/financial/balance-sheet?as_on=2026-09-30", ADMIN)).body.data;
    assert.equal(bs.difference, 0);
    // The anchor day itself is a reportable date.
    const per = (await call("GET", "/api/financial/periods", ADMIN)).body.snapshots.map((x) => x.as_on);
    assert.ok(per.includes("2026-06-30"));
  });

  test("a voucher whose lines do not add up is reported, with its gap", async () => {
    // A sale stored with a line missing (the tax line never arrived).
    db.entries.push(...E("2026-09-10", "Sales", [["Mehta Electricals", true, 1180], ["Sales", false, 1000]], { tag: "bad", admin_id: 7, company_guid: "CO-1" }));
    await upload();
    const bs = (await call("GET", "/api/financial/balance-sheet?as_on=2026-09-30", ADMIN)).body.data;
    assert.deepEqual(bs.data_check, { unbalanced_vouchers: 1, unbalanced_amount: 180 });
    assert.equal(Math.abs(bs.difference), 180);
  });

  test("dates without stock figures are refused; across years refused", async () => {
    await upload();
    assert.equal((await call("GET", "/api/financial/balance-sheet?as_on=2026-07-15", ADMIN)).body.code, "no_snapshot");
    assert.equal((await call("GET", "/api/financial/profit-loss?from=2026-07-16&to=2026-09-30", ADMIN)).body.code, "no_snapshot");
    assert.equal((await call("GET", "/api/financial/profit-loss?from=2025-04-01&to=2026-09-30", ADMIN)).body.code, "cross_year");
    assert.equal((await call("GET", "/api/financial/profit-loss?from=x&to=y", ADMIN)).status, 400);
  });

  test("older agents' per-date snapshots are ignored; anchors never pruned", async () => {
    await upload();
    // An older agent's daily snapshot.
    const b = await call("POST", "/api/financial/agent/snapshot/begin", ADMIN, { company_guid: "CO-1", as_on: "2026-10-01", fy_from: "2026-04-01" });
    await call("POST", "/api/financial/agent/snapshot/rows", ADMIN, { batch_id: b.body.batch_id, ledgers: [L("Sales", "Sales Accounts", 1)], groups: [] });
    await call("POST", "/api/financial/agent/snapshot/commit", ADMIN, { batch_id: b.body.batch_id, ledger_count: 1, group_count: 0 });
    const b2 = await call("POST", "/api/financial/agent/snapshot/begin", ADMIN, { company_guid: "CO-1", as_on: "2026-10-02", fy_from: "2026-04-01" });
    await call("POST", "/api/financial/agent/snapshot/commit", ADMIN, { batch_id: b2.body.batch_id, ledger_count: 0, group_count: 0 });
    assert.ok(db.snapshots.some((x) => x.kind === "anchor" && x.as_on === "2026-03-31"));
    const pl = (await call("GET", "/api/financial/profit-loss?from=2026-04-01&to=2026-09-30", ADMIN)).body.data;
    assert.equal(pl.net_profit, 122000);
  });

  test("a half-finished anchor upload is never used", async () => {
    await call("POST", "/api/financial/agent/groups", ADMIN, { company_guid: "CO-1", groups: GROUPS });
    const b = await call("POST", "/api/financial/agent/snapshot/begin", ADMIN, { company_guid: "CO-1", as_on: "2026-03-31", fy_from: "2025-04-01", kind: "anchor" });
    await call("POST", "/api/financial/agent/snapshot/rows", ADMIN, { batch_id: b.body.batch_id, ledgers: ANCHOR_LEDGERS.slice(0, 3), groups: [] });
    const bad = await call("POST", "/api/financial/agent/snapshot/commit", ADMIN, { batch_id: b.body.batch_id, ledger_count: ANCHOR_LEDGERS.length, group_count: 1 });
    assert.equal(bad.body.code, "incomplete");
    assert.equal((await call("GET", "/api/financial/trial-balance?as_on=2026-09-30", ADMIN)).body.code, "not_synced");
  });

  test("uploads: admin agent only, own companies only; stock values validated", async () => {
    assert.equal((await upload({ user: USER })).status, 403);
    assert.equal((await upload({ company: "CO-9" })).status, 403);
    assert.equal((await call("POST", "/api/financial/agent/stock-values", ADMIN, { company_guid: "CO-1", values: [{ as_on: "bad", value: 1 }] })).status, 400);
    assert.equal((await call("POST", "/api/financial/agent/groups", null, {})).status, 401);
  });

  test("team users: none by default; admin grants and revokes", async () => {
    await upload();
    assert.equal((await call("GET", "/api/financial/me", USER)).body.can_view, false);
    assert.equal((await call("GET", "/api/financial/trial-balance?as_on=2026-09-30", USER)).body.code, "no_access");
    assert.equal((await call("PUT", "/api/financial/access/21", USER, { enabled: true })).status, 403);
    assert.equal((await call("PUT", "/api/financial/access/31", ADMIN, { enabled: true })).status, 404);
    assert.equal((await call("PUT", "/api/financial/access/21", ADMIN, { enabled: true })).status, 200);
    assert.equal((await call("GET", "/api/financial/balance-sheet?as_on=2026-09-30", USER)).status, 200);
    assert.equal((await call("GET", "/api/financial/periods", { id: 22, adminId: 7, role: "USER" })).status, 403);
    assert.equal((await call("PUT", "/api/financial/access/21", ADMIN, { enabled: false })).status, 200);
    assert.equal((await call("GET", "/api/financial/periods", USER)).status, 403);
  });

  test("company isolation", async () => {
    await upload();
    assert.equal((await call("GET", "/api/financial/trial-balance?as_on=2026-09-30", OTHER_ADMIN)).body.code, "not_synced");
    db.active[7] = "CO-2";
    assert.equal((await call("GET", "/api/financial/periods", ADMIN)).body.snapshots.length, 0);
    delete db.active[7];
    assert.equal((await call("GET", "/api/financial/periods", ADMIN)).body.code, "no_company");
  });
});

describe("routes (no balances from Tally: books opening + vouchers)", () => {
  let db, server, base;
  beforeEach(async () => {
    db = new FakeDb();
    // The ledger masters' opening balances (Dr −) at the books' start: the
    // same figures as the Tally anchor of the other tests.
    const open = { "Capital A/c": 115000, "HDFC Bank": -40000, Cash: -5000, "Mehta Electricals": -30000, "Polycab Wires": 20000, Furniture: -50000, "Profit & Loss A/c": 10000 };
    for (const l of db.ledgers) if (open[l.name] !== undefined) l.opening_balance = String(open[l.name]);
    const app = express();
    app.use(express.json({ limit: "20mb" }));
    app.use(createFinancialRouter({ db, auth: stubAuth, log: { error: () => {} }, now: () => new Date("2026-10-12T06:00:00Z") }));
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
  const books = (b) => call("POST", "/api/financial/agent/books", ADMIN, { company_guid: "CO-1", ...b });
  const stock = (vals) =>
    call("POST", "/api/financial/agent/stock-values", ADMIN, { company_guid: "CO-1", values: vals.map(([as_on, value]) => ({ as_on, value })) });
  const groups = () => call("POST", "/api/financial/agent/groups", ADMIN, { company_guid: "CO-1", groups: GROUPS });

  test("books start = year start: same figures as Tally's balances, no Tally balance request", async () => {
    await groups();
    assert.equal((await books({ books_from: "2026-04-01", vouchers_from: "2026-04-01", fy_from: "2026-04-01", opening_stock: 15000 })).status, 200);
    await stock([["2026-08-31", 20000], ["2026-09-30", 25000]]);
    const per = (await call("GET", "/api/financial/periods", ADMIN)).body;
    assert.deepEqual(per.snapshots.map((x) => x.as_on), ["2026-10-12", "2026-09-30", "2026-08-31"]);
    assert.equal(per.reason, undefined);
    const pl = (await call("GET", "/api/financial/profit-loss?from=2026-04-01&to=2026-09-30", ADMIN)).body.data;
    assert.equal(pl.trading.opening_stock, 15000);
    assert.equal(pl.gross_profit, 150000);
    assert.equal(pl.net_profit, 122000);
    const bs = (await call("GET", "/api/financial/balance-sheet?as_on=2026-09-30", ADMIN)).body.data;
    assert.equal(bs.total_assets, 323000);
    assert.equal(bs.difference, 0);
  });

  test("next year is carried forward (revenue restarts, profit into P&L A/c); needs the year-end stock", async () => {
    // Books from 2025-04-01: the worked vouchers move one year back.
    for (const e of db.entries) e.voucher_date = e.voucher_date.replace(/^2026-/, "2025-").replace(/^2025-03-/, "2024-03-");
    db.entries.push(
      ...E("2026-05-05", "Sales", [["Mehta Electricals", true, 50000], ["Sales", false, 50000]], { tag: "ny", admin_id: 7, company_guid: "CO-1" })
    );
    await groups();
    await books({ books_from: "2025-04-01", vouchers_from: "2025-04-01", fy_from: "2025-04-01", opening_stock: 15000 });
    // No closing stock at 2026-03-31 yet: nothing for this year, and a reason.
    let per = (await call("GET", "/api/financial/periods", ADMIN)).body;
    assert.equal(per.reason, "stock_values");
    assert.match(per.message, /closing stock/i);
    await stock([["2025-09-30", 25000], ["2026-03-31", 25000], ["2026-09-30", 30000]]);
    per = (await call("GET", "/api/financial/periods", ADMIN)).body;
    assert.ok(per.snapshots.some((x) => x.as_on === "2026-09-30" && x.fy_from === "2026-04-01"));
    assert.ok(per.snapshots.some((x) => x.as_on === "2026-03-31" && x.fy_from === "2025-04-01"));
    // Last year: the worked figures (closing stock 25000 at the year end).
    const ly = (await call("GET", "/api/financial/profit-loss?from=2025-04-01&to=2026-03-31", ADMIN)).body.data;
    assert.equal(ly.net_profit, 122000);
    // This year: only this year's sale; stock 25000 → 30000.
    const pl = (await call("GET", "/api/financial/profit-loss?from=2026-04-01&to=2026-09-30", ADMIN)).body.data;
    assert.equal(pl.trading.total_income, 50000 + 30000);
    assert.equal(pl.trading.opening_stock, 25000);
    assert.equal(pl.net_profit, 55000);
    const bs = (await call("GET", "/api/financial/balance-sheet?as_on=2026-09-30", ADMIN)).body.data;
    assert.equal(bs.difference, 0);
    assert.equal(bs.profit_loss.opening, 6000 + 122000); // earlier years + last year
    assert.equal(bs.profit_loss.current_period, 55000);
  });

  test("vouchers synced from later than the books: a clear reason", async () => {
    await groups();
    await books({ books_from: "2024-04-01", vouchers_from: "2026-04-01", fy_from: "2024-04-01", opening_stock: 1 });
    const per = (await call("GET", "/api/financial/periods", ADMIN)).body;
    assert.equal(per.reason, "vouchers_after_books");
    assert.equal(per.snapshots.length, 0);
    assert.equal((await call("GET", "/api/financial/trial-balance?as_on=2026-09-30", ADMIN)).body.code, "not_synced");
  });

  test("books upload: admin agent only, values checked", async () => {
    assert.equal((await call("POST", "/api/financial/agent/books", USER, { company_guid: "CO-1", books_from: "2026-04-01" })).status, 403);
    assert.equal((await books({ books_from: "1 April" })).status, 400);
    assert.equal((await books({ books_from: "2026-04-01", opening_stock: "x" })).status, 400);
    assert.equal((await call("POST", "/api/financial/agent/books", ADMIN, { company_guid: "CO-9", books_from: "2026-04-01" })).status, 403);
    assert.equal((await books({ books_from: "2026-04-01", opening_stock: -500 })).status, 200);
    assert.equal(db.books[0].opening_stock, "500");
  });
});
