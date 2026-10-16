// Tests for the official Tally reports (node --test): upload checks, the
// plain checks (sides equal), group drill-down, and the routes against an
// in-memory fake database. Route tests need `express` (run from a folder
// that has it); without it they skip.
import { test, describe } from "node:test";
import assert from "node:assert/strict";

import {
  buildFromPieces,
  checksFor,
  mainAmount,
  primaryGroup,
  validateSnapshot,
  validateUpload,
  withLedgers,
} from "../utils/tallyReportsCore.js";
// The statements' own builders (deployed with the financial reports).
import * as financialCore from "../../financial/utils/financialCore.js";

// A small company as Tally keeps it (Tally sign: Dr −, Cr +).
const FULL_GROUPS = [
  { name: "Capital Account", parent: "Primary", is_revenue: false, is_deemed_positive: false, affects_gross_profit: false },
  { name: "Current Liabilities", parent: "Primary", is_revenue: false, is_deemed_positive: false, affects_gross_profit: false },
  { name: "Sundry Creditors", parent: "Current Liabilities", is_revenue: false, is_deemed_positive: false, affects_gross_profit: false },
  { name: "Current Assets", parent: "Primary", is_revenue: false, is_deemed_positive: true, affects_gross_profit: false },
  { name: "Bank Accounts", parent: "Current Assets", is_revenue: false, is_deemed_positive: true, affects_gross_profit: false },
  { name: "Sundry Debtors", parent: "Current Assets", is_revenue: false, is_deemed_positive: true, affects_gross_profit: false },
  { name: "Stock-in-Hand", parent: "Current Assets", is_revenue: false, is_deemed_positive: true, affects_gross_profit: false },
  { name: "Sales Accounts", parent: "Primary", is_revenue: true, is_deemed_positive: false, affects_gross_profit: true },
  { name: "Purchase Accounts", parent: "Primary", is_revenue: true, is_deemed_positive: true, affects_gross_profit: true },
  { name: "Indirect Expenses", parent: "Primary", is_revenue: true, is_deemed_positive: true, affects_gross_profit: false },
];
const PIECES = {
  period_from: "2026-04-01",
  period_to: "2026-10-15",
  ledgers: [
    { name: "Capital", parent: "Capital Account", opening: 10000, closing: 10000 },
    { name: "Polycab", parent: "Sundry Creditors", closing: 2000 },
    { name: "HDFC Bank", parent: "Bank Accounts", opening: -6000, closing: -9000 },
    { name: "Mehta", parent: "Sundry Debtors", closing: -3000 },
    { name: "Sales", parent: "Sales Accounts", closing: 8000 },
    { name: "Purchase", parent: "Purchase Accounts", closing: -5000 },
    { name: "Rent", parent: "Indirect Expenses", closing: -1000 },
  ],
  stock: { opening: 2000, closing: 4000 },
  cash_months: [{ from: "2026-04-01", to: "2026-04-30", opening: -6000, closing: -7500 }],
  pieces: 9,
  fetch_seconds: 4.2,
};

describe("reports built from Tally's figures (pieces)", () => {
  test("Trial Balance, Balance Sheet and P&L all balance; Cash Flow by month", () => {
    const v = validateSnapshot(PIECES).value;
    const b = buildFromPieces(v, FULL_GROUPS, financialCore);
    // Trial Balance: ledgers + opening stock → Dr 20,000 = Cr 20,000.
    assert.equal(b.trial_balance.at(-1).name, "Opening Stock");
    assert.deepEqual(checksFor("trial_balance", b.trial_balance), { debit: 20000, credit: 20000, difference: 0, balanced: true });
    // P&L: gross 5,000 (8,000 + 4,000 − 5,000 − 2,000), net 4,000.
    const pl = Object.fromEntries(b.profit_loss.map((x) => [x.name, mainAmount(x)]));
    assert.deepEqual(pl, {
      "Opening Stock": -2000,
      "Purchase Accounts": -5000,
      "Sales Accounts": 8000,
      "Closing Stock": 4000,
      "Indirect Expenses": -1000,
      "Net Profit": -4000,
    });
    assert.equal(checksFor("profit_loss", b.profit_loss).balanced, true);
    assert.deepEqual(b.profit_loss.find((x) => x.name === "Sales Accounts").ledgers, [{ name: "Sales", group: "Sales Accounts", amount: 8000 }]);
    // Balance Sheet: 10,000 + 2,000 + profit 4,000 = 9,000 + 3,000 + stock 4,000.
    const bs = Object.fromEntries(b.balance_sheet.map((x) => [x.name, mainAmount(x)]));
    assert.deepEqual(bs, { "Capital Account": 10000, "Current Liabilities": 2000, "Profit & Loss A/c": 4000, "Current Assets": -16000 });
    assert.equal(checksFor("balance_sheet", b.balance_sheet).balanced, true);
    assert.deepEqual(
      b.balance_sheet.find((x) => x.name === "Current Assets").ledgers.map((l) => [l.name, l.amount]),
      [
        ["HDFC Bank", -9000],
        ["Mehta", -3000],
      ]
    );
    // Cash Flow: money held shown positive.
    assert.deepEqual(b.cash_flow, [{ name: "Apr 2026", tag: "CF", amounts: { CFOPENING: 6000, CFNET: 1500, CFCLOSING: 7500 } }]);
  });

  test("no group tree yet: Trial Balance and Cash Flow only; checks on the upload", () => {
    const v = validateSnapshot(PIECES).value;
    const b = buildFromPieces(v, [], financialCore);
    assert.equal(b.balance_sheet, null);
    assert.equal(b.profit_loss, null);
    assert.equal(b.trial_balance.length, 8);
    assert.match(validateSnapshot({ ...PIECES, ledgers: [] }).error, /ledgers/);
    assert.match(validateSnapshot({ ...PIECES, period_to: "2026-02-30" }).error, /dates/);
    // Duplicate ledger names (two pieces overlapping) kept once.
    assert.equal(validateSnapshot({ ...PIECES, ledgers: [...PIECES.ledgers, PIECES.ledgers[0]] }).value.ledgers.length, 7);
  });
});

const BS_ROWS = [
  { name: "Capital Account", tag: "DSPDISPNAME", amounts: { BSMAINAMT: 150000 } },
  { name: "Current Liabilities", tag: "DSPDISPNAME", amounts: { BSMAINAMT: 25000.5 } },
  { name: "Current Assets", tag: "DSPDISPNAME", amounts: { BSSUBAMT: -1, BSMAINAMT: -175000.5 } },
];
const TB_ROWS = [
  { name: "Cash", parent: "Cash-in-Hand", opening: 0, closing: -2500 },
  { name: "HDFC", parent: "Bank Accounts", opening: 0, closing: -172500.5 },
  { name: "Capital", parent: "Capital Account", opening: 0, closing: 150000 },
  { name: "Polycab", parent: "Sundry Creditors", opening: 0, closing: 25000.5 },
  { name: "Zero", parent: "Sundry Creditors", opening: 0, closing: 0 },
];
const GROUPS = [
  { name: "Current Assets", parent: "Primary" },
  { name: "Cash-in-Hand", parent: "Current Assets" },
  { name: "Bank Accounts", parent: "Current Assets" },
  { name: "Current Liabilities", parent: "" },
  { name: "Sundry Creditors", parent: "Current Liabilities" },
  { name: "Capital Account", parent: "Primary" },
];

describe("checks and drill-down", () => {
  test("upload checks: dates, rows, amounts", () => {
    assert.match(validateUpload("nope", {}).error, /Unknown/);
    assert.match(validateUpload("trial_balance", { period_from: "2026-04-01", period_to: "2026-02-30", rows: [{}] }).error, /dates/);
    assert.match(validateUpload("trial_balance", { period_from: "2026-05-01", period_to: "2026-04-01", rows: [{}] }).error, /dates/);
    assert.match(validateUpload("trial_balance", { period_from: "2026-04-01", period_to: "2026-10-15", rows: [] }).error, /rows/);
    const tb = validateUpload("trial_balance", { period_from: "2026-04-01", period_to: "2026-10-15", rows: [{ name: " Cash ", closing: "-2500.004" }, { name: "" }] });
    assert.deepEqual(tb.value.rows, [{ name: "Cash", parent: "Primary", opening: 0, closing: -2500 }]);
    const bs = validateUpload("balance_sheet", {
      period_from: "2026-04-01",
      period_to: "2026-10-15",
      rows: [{ name: "Capital", tag: "DSPDISPNAME", amounts: { BSMAINAMT: 5, bad_key: 1, BSSUBAMT: "x" } }],
    });
    assert.deepEqual(bs.value.rows[0].amounts, { BSMAINAMT: 5 });
  });

  test("main amount: Tally's main column, else the sub-column", () => {
    assert.equal(mainAmount(BS_ROWS[2]), -175000.5);
    assert.equal(mainAmount({ amounts: { PLSUBAMT: 7 } }), 7);
    assert.equal(mainAmount({ amounts: {} }), null);
  });

  test("sides equal: Trial Balance Dr = Cr; Balance Sheet both sides", () => {
    assert.deepEqual(checksFor("trial_balance", TB_ROWS), { debit: 175000.5, credit: 175000.5, difference: 0, balanced: true });
    assert.deepEqual(checksFor("balance_sheet", BS_ROWS), { credit_side: 175000.5, debit_side: 175000.5, difference: 0, balanced: true });
    const off = checksFor("balance_sheet", BS_ROWS.slice(1));
    assert.equal(off.balanced, false);
    assert.equal(off.difference, 150000);
    assert.deepEqual(checksFor("cash_flow", BS_ROWS), {});
  });

  test("each group row lists its ledgers (from the same period's Trial Balance)", () => {
    assert.equal(primaryGroup("Cash-in-Hand", GROUPS), "current assets");
    assert.equal(primaryGroup("Capital Account", GROUPS), "capital account");
    const rows = withLedgers(BS_ROWS, TB_ROWS, GROUPS);
    assert.deepEqual(rows[2].ledgers.map((l) => [l.name, l.amount]), [
      ["HDFC", -172500.5],
      ["Cash", -2500],
    ]);
    assert.deepEqual(rows[1].ledgers.map((l) => l.name), ["Polycab"]); // zero balances left out
    assert.deepEqual(withLedgers(BS_ROWS, [], GROUPS), BS_ROWS);
  });
});

/* ------------------------------------------------------------ routes */
let express = null;
try {
  express = (await import("express")).default;
} catch {
  express = null;
}

class FakeDb {
  constructor() {
    this.tables = { tally_trial_balance: [], tally_profit_loss: [], tally_balance_sheet: [], tally_cash_flow: [] };
    this.access = new Set();
    this.active = { 7: "CO-1" };
    this.missing = false;
  }
  async query(sql, p = []) {
    const s = sql.replace(/\s+/g, " ").trim();
    const miss = () => Object.assign(new Error("relation does not exist"), { code: "42P01" });
    if (s.startsWith("SELECT 1 FROM companies")) {
      const ok = p[0] === "CO-1" && p[1] === 7;
      return { rows: ok ? [{}] : [], rowCount: ok ? 1 : 0 };
    }
    if (s.startsWith("SELECT 1 FROM financial_report_access")) {
      const ok = this.access.has(`${p[0]}:${p[1]}`);
      return { rows: ok ? [{}] : [], rowCount: ok ? 1 : 0 };
    }
    if (s.startsWith("SELECT ac.company_guid")) {
      return { rows: this.active[p[0]] ? [{ company_guid: this.active[p[0]], company_name: "GI Apr 25-26" }] : [] };
    }
    if (s.startsWith("SELECT name, parent FROM tally_groups")) return { rows: GROUPS };
    if (s.startsWith("SELECT name, parent, is_revenue")) return { rows: this.fullGroups || [] };
    const t = /(?:INTO|FROM) (tally_[a-z_]+)/.exec(s)?.[1];
    if (t && this.tables[t]) {
      if (this.missing) throw miss();
      const list = this.tables[t];
      if (s.startsWith("INSERT INTO")) {
        const [admin, company, from, to, rows, name, secs, hash] = p;
        const i = list.findIndex((x) => x.admin === admin && x.company === company && x.period_from === from && x.period_to === to);
        const rec = { admin, company, period_from: from, period_to: to, rows: JSON.parse(rows), report_name: name, fetch_seconds: secs, content_hash: hash, fetched_at: new Date().toISOString() };
        if (i >= 0) list[i] = rec;
        else list.push(rec);
        return { rows: [], rowCount: 1 };
      }
      const mine = list
        .filter((x) => x.admin === p[0] && x.company === p[1])
        .sort((a, b) => (a.period_to < b.period_to ? 1 : a.period_to > b.period_to ? -1 : a.period_from < b.period_from ? -1 : 1));
      if (s.includes("period_from = $3::date AND period_to = $4::date")) {
        return { rows: mine.filter((x) => x.period_from === p[2] && x.period_to === p[3]) };
      }
      if (s.includes("LIMIT 1")) return { rows: mine.slice(0, 1) };
      return { rows: mine };
    }
    throw new Error(`Unexpected SQL: ${s}`);
  }
}

async function serve(router, user) {
  const app = express();
  app.use(express.json());
  app.use((req, res, next) => {
    req.user = user;
    next();
  });
  app.use(router);
  const server = await new Promise((ok) => {
    const sv = app.listen(0, () => ok(sv));
  });
  const base = `http://127.0.0.1:${server.address().port}`;
  const call = async (method, path, body) => {
    const r = await fetch(base + path, {
      method,
      headers: { "content-type": "application/json" },
      body: body ? JSON.stringify(body) : undefined,
    });
    return { status: r.status, body: await r.json() };
  };
  return { get: (p) => call("GET", p), post: (p, b) => call("POST", p, b), close: () => new Promise((ok) => server.close(ok)) };
}

describe("routes", { skip: express ? false : "express not installed here (run from the backend folder)" }, () => {
  const admin = { id: 7, role: "ADMIN", adminId: 7 };
  const make = async (db, user = admin) => {
    const { createTallyReportsRouter } = await import("../utils/tallyReportsRouter.js");
    return serve(createTallyReportsRouter({ db, auth: (req, res, next) => next(), log: { error: () => {} } }), user);
  };
  const up = (report, to, rows, from = "2026-04-01") => ({ company_guid: "CO-1", period_from: from, period_to: to, rows, report_name: "Balance Sheet", fetch_seconds: 12.4 });

  test("upload → periods → report (newest, or a chosen period); a new fetch replaces", async () => {
    const db = new FakeDb();
    const api = await make(db);
    assert.deepEqual((await api.post("/api/tally-reports/agent/trial_balance", up("trial_balance", "2026-10-15", TB_ROWS))).body, { success: true, rows: 5 });
    await api.post("/api/tally-reports/agent/balance_sheet", up("balance_sheet", "2026-09-30", BS_ROWS));
    await api.post("/api/tally-reports/agent/balance_sheet", up("balance_sheet", "2026-10-15", BS_ROWS));
    await api.post("/api/tally-reports/agent/balance_sheet", up("balance_sheet", "2026-10-15", BS_ROWS.slice(0, 2))); // replaces
    assert.equal(db.tables.tally_balance_sheet.length, 2);

    const p = await api.get("/api/tally-reports/periods");
    assert.deepEqual(p.body.reports.balance_sheet.map((x) => x.to), ["2026-10-15", "2026-09-30"]);
    assert.deepEqual(p.body.reports.cash_flow, []);

    const newest = await api.get("/api/tally-reports/balance_sheet");
    assert.equal(newest.body.data.period_to, "2026-10-15");
    assert.equal(newest.body.data.rows.length, 2);
    assert.equal(newest.body.data.source, "tally");
    assert.equal(newest.body.data.checks.balanced, false);

    const sept = await api.get("/api/tally-reports/balance_sheet?from=2026-04-01&to=2026-09-30");
    assert.equal(sept.body.data.checks.balanced, true);
    assert.equal(sept.body.data.rows[2].ledgers, undefined); // no TB for 30 Sep

    // Same period as the Trial Balance: groups list their ledgers.
    await api.post("/api/tally-reports/agent/balance_sheet", up("balance_sheet", "2026-10-15", BS_ROWS));
    const withTb = await api.get("/api/tally-reports/balance_sheet?from=2026-04-01&to=2026-10-15");
    assert.deepEqual(withTb.body.data.rows[2].ledgers.map((l) => l.name), ["HDFC", "Cash"]);

    const tb = await api.get("/api/tally-reports/trial_balance");
    assert.deepEqual(tb.body.data.checks, { debit: 175000.5, credit: 175000.5, difference: 0, balanced: true });
    assert.equal((await api.get("/api/tally-reports/cash_flow")).status, 404);
    assert.equal((await api.get("/api/tally-reports/nope")).status, 404);
    await api.close();
  });

  test("snapshot upload: all four reports stored and served", async () => {
    const db = new FakeDb();
    db.fullGroups = FULL_GROUPS;
    const { createTallyReportsRouter } = await import("../utils/tallyReportsRouter.js");
    const api = await serve(
      createTallyReportsRouter({ db, auth: (req, res, next) => next(), log: { error: () => {} }, builders: financialCore }),
      admin
    );
    const up = await api.post("/api/tally-reports/agent/snapshot", { company_guid: "CO-1", ...PIECES });
    assert.deepEqual(up.body, { success: true, saved: ["trial_balance", "balance_sheet", "profit_loss", "cash_flow"], groups: FULL_GROUPS.length });
    const bs = await api.get("/api/tally-reports/balance_sheet");
    assert.equal(bs.body.data.checks.balanced, true);
    assert.equal(bs.body.data.period_to, "2026-10-15");
    const pl = await api.get("/api/tally-reports/profit_loss");
    assert.equal(pl.body.data.checks.balanced, true);
    const tb = await api.get("/api/tally-reports/trial_balance");
    assert.equal(tb.body.data.checks.balanced, true);
    assert.equal((await api.get("/api/tally-reports/cash_flow")).body.data.rows[0].name, "Apr 2026");
    assert.equal((await api.post("/api/tally-reports/agent/snapshot", { company_guid: "CO-1", ...PIECES, ledgers: [] })).status, 400);
    await api.close();
  });

  test("only the admin's Agent uploads; bad uploads refused", async () => {
    const db = new FakeDb();
    const member = await make(db, { id: 21, role: "USER", adminId: 7 });
    assert.equal((await member.post("/api/tally-reports/agent/trial_balance", up("x", "2026-10-15", TB_ROWS))).status, 403);
    await member.close();
    const api = await make(db);
    assert.equal((await api.post("/api/tally-reports/agent/trial_balance", { ...up("x", "2026-10-15", TB_ROWS), company_guid: "CO-9" })).status, 403);
    assert.equal((await api.post("/api/tally-reports/agent/trial_balance", up("x", "bad", TB_ROWS))).status, 400);
    assert.equal((await api.post("/api/tally-reports/agent/nope", up("x", "2026-10-15", TB_ROWS))).status, 404);
    await api.close();
  });

  test("team member: only with financial-report access; tables missing → 503", async () => {
    const db = new FakeDb();
    const member = await make(db, { id: 21, role: "USER", adminId: 7 });
    assert.equal((await member.get("/api/tally-reports/periods")).status, 403);
    db.access.add("7:21");
    assert.equal((await member.get("/api/tally-reports/periods")).status, 200);
    await member.close();
    db.missing = true;
    const api = await make(db);
    const p = await api.get("/api/tally-reports/periods");
    assert.equal(p.status, 200); // nothing fetched yet
    assert.deepEqual(p.body.reports.trial_balance, []);
    const u = await api.post("/api/tally-reports/agent/trial_balance", up("x", "2026-10-15", TB_ROWS));
    assert.equal(u.status, 503);
    assert.equal(u.body.code, "not_set_up");
    await api.close();
  });
});
