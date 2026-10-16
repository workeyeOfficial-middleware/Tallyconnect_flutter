// Tests for the cash flow forecast (node --test): week maths, payment
// delays (first in, first out), the forecast, and the routes against an
// in-memory fake database. The route tests need `express` (run them from
// the backend folder, where node_modules has it); without it they skip.
import { test, describe } from "node:test";
import assert from "node:assert/strict";

import {
  DOUBTFUL_DAYS,
  addDays,
  advanceKeys,
  allocationPayments,
  buildForecast,
  creditDays,
  delayFor,
  delayStats,
  fifoPayments,
  mondayOf,
  weightedQuantile,
} from "../utils/cashflowCore.js";

describe("dates", () => {
  test("Monday of the week; adding days across months", () => {
    assert.equal(mondayOf("2026-10-14"), "2026-10-12"); // Wednesday
    assert.equal(mondayOf("2026-10-12"), "2026-10-12"); // Monday
    assert.equal(mondayOf("2026-10-18"), "2026-10-12"); // Sunday
    assert.equal(addDays("2026-10-30", 3), "2026-11-02");
    assert.equal(addDays("2027-01-01", -1), "2026-12-31");
  });
});

describe("payment delays", () => {
  test("weighted median / 75th percentile", () => {
    const xs = [
      { v: 0, w: 100 },
      { v: 10, w: 100 },
      { v: 40, w: 800 },
    ];
    assert.equal(weightedQuantile(xs, 0.5), 40); // the big bill dominates
    assert.equal(weightedQuantile([{ v: 5, w: 1 }, { v: 9, w: 1 }], 0.5), 5);
    assert.equal(weightedQuantile([], 0.5), null);
  });

  test("part payments, oldest invoice first", () => {
    const p = fifoPayments([
      { date: "2026-01-01", amount: 1000, side: "charge", due: "2026-01-10" },
      { date: "2026-01-05", amount: 500, side: "charge", due: "2026-01-20" },
      { date: "2026-01-15", amount: 400, side: "settle", cash: true },
      { date: "2026-01-25", amount: 1100, side: "settle", cash: true },
    ]);
    assert.deepEqual(
      p.map((x) => [x.amount, x.delay, x.bill]),
      [
        [400, 5, 0], // 15 Jan vs due 10 Jan
        [600, 15, 0],
        [500, 5, 1], // 25 Jan vs due 20 Jan
      ]
    );
  });

  test("credit notes reduce the bill but are not payments", () => {
    const p = fifoPayments([
      { date: "2026-01-01", amount: 1000, side: "charge", due: "2026-01-01" },
      { date: "2026-01-03", amount: 300, side: "settle", cash: false }, // credit note
      { date: "2026-01-11", amount: 700, side: "settle", cash: true },
    ]);
    assert.deepEqual(p.map((x) => [x.amount, x.delay]), [[700, 10]]);
  });

  test("an opening balance is paid first (no delay counted); advances count as early", () => {
    const p = fifoPayments(
      [
        { date: "2026-02-01", amount: 1000, side: "charge", due: "2026-02-01" },
        { date: "2026-02-05", amount: 1500, side: "settle", cash: true }, // 500 opening + 1000
        { date: "2026-02-10", amount: 200, side: "settle", cash: true }, // advance
        { date: "2026-02-20", amount: 200, side: "charge", due: "2026-02-28" },
      ],
      { opening: 500, openingDate: "2025-12-31" }
    );
    assert.deepEqual(p.map((x) => [x.amount, x.delay]), [
      [1000, 4],
      [200, -18], // paid 10 Feb, due 28 Feb
    ]);
  });

  test("same-day invoice and payment: the payment settles that invoice", () => {
    const p = fifoPayments([
      { date: "2026-03-01", amount: 100, side: "settle", cash: true },
      { date: "2026-03-01", amount: 100, side: "charge", due: "2026-03-01" },
    ]);
    assert.deepEqual(p.map((x) => x.delay), [0]);
  });

  test("statistics: capped, weighted, on-time share, window", () => {
    const pays = [
      { date: "2026-05-01", due: "2026-04-01", amount: 1000, delay: 30, bill: 0 },
      { date: "2026-05-01", due: "2025-01-01", amount: 1000, delay: 485, bill: 1 }, // capped at 180
      { date: "2026-05-01", due: "2026-05-05", amount: 2000, delay: -4, bill: 2 },
      { date: "2024-01-01", due: "2024-01-01", amount: 9999, delay: 90, bill: 3 }, // too old
    ];
    const s = delayStats(pays, { since: "2025-10-14" });
    assert.equal(s.bills, 3);
    assert.equal(s.amount, 4000);
    assert.equal(s.median, -4);
    assert.equal(s.p75, 30);
    assert.equal(s.on_time_pct, 50);
    assert.equal(s.average, Math.round((30 * 1000 + 180 * 1000 - 4 * 2000) / 4000));
    assert.equal(delayStats([], {}), null);
  });

  test("delay used: party, blended, company, none", () => {
    const company = { median: 10 };
    assert.deepEqual(delayFor({ median: 20, bills: 5, amount: 50000, on_time_pct: 10 }, company), {
      days: 20,
      source: "party",
      bills: 5,
      on_time_pct: 10,
    });
    // 1 bill of 3 → a third of its own delay, two thirds the company's.
    assert.equal(delayFor({ median: 40, bills: 1, amount: 50000, on_time_pct: 0 }, company).days, 20);
    assert.equal(delayFor({ median: 40, bills: 1, amount: 50000 }, company).source, "blend");
    assert.deepEqual(delayFor(null, company), { days: 10, source: "company", bills: 0 });
    assert.deepEqual(delayFor(null, null), { days: 0, source: "none", bills: 0 });
  });

  test("usual credit days", () => {
    assert.equal(
      creditDays([
        { date: "2026-01-01", due: "2026-01-31" },
        { date: "2026-01-01", due: "2026-01-16" },
        { date: "2026-01-01", due: "2026-01-01" },
        { date: "2026-01-01", due: "2025-01-01" }, // nonsense, ignored
      ]),
      15
    );
    assert.equal(creditDays([]), null);
  });
});

describe("forecast", () => {
  const today = "2026-10-14"; // Wednesday; first week 12–18 Oct
  const base = {
    today,
    weeks: 13,
    opening: 1000,
    receivables: [
      { party: "Late Co", bill: "S/1", due: "2026-10-20", amount: 5000 }, // +10 → 30 Oct, week 3
      { party: "Late Co", bill: "S/2", due: "2026-10-01", amount: 700 }, // +10 → 11 Oct, overdue → week 1
      { party: "Old Co", bill: "S/3", due: "2026-06-01", amount: 900 }, // > 90 days past due
      { party: "Far Co", bill: "S/4", due: "2027-03-01", amount: 300 }, // after week 13
      { party: "Nodue Co", bill: "S/5", due: null, amount: 50 }, // no due date → today
    ],
    payables: [
      { party: "Supplier", bill: "P/1", due: "2026-10-25", amount: 8000 }, // week 2
      { party: "Supplier", bill: "P/2", due: "2026-09-01", amount: 100 }, // overdue → week 1
    ],
    delayOf: (p) => (p === "Late Co" ? { days: 10, source: "party", bills: 4 } : { days: 0, source: "company", bills: 0 }),
  };

  test("weeks, overdue, doubtful, later, running balance, shortfall", () => {
    const f = buildForecast(base);
    assert.equal(f.first_week, "2026-10-12");
    assert.equal(f.weeks.length, 13);
    assert.deepEqual(
      f.weeks.slice(0, 3).map((w) => [w.start, w.end, w.inflow, w.outflow, w.opening, w.closing, w.shortfall]),
      [
        ["2026-10-12", "2026-10-18", 750, 100, 1000, 1650, false],
        ["2026-10-19", "2026-10-25", 0, 8000, 1650, -6350, true],
        ["2026-10-26", "2026-11-01", 5000, 0, -6350, -1350, true],
      ]
    );
    assert.equal(f.weeks[0].overdue_inflow, 700);
    assert.equal(f.shortfall_week, "2026-10-19");
    assert.deepEqual(f.doubtful, { amount: 900, bills: 1, days: DOUBTFUL_DAYS });
    assert.deepEqual(f.later, { inflow: 300, outflow: 0, inflow_bills: 1, outflow_bills: 0 });
    assert.deepEqual(f.no_due_date, { amount: 50, bills: 1 });
    assert.deepEqual(f.totals, { inflow: 5750, outflow: 8100, net: -2350 });
    // Every open bill is somewhere: weeks + later + doubtful.
    const allIn = base.receivables.reduce((a, b) => a + b.amount, 0);
    assert.equal(f.totals.inflow + f.later.inflow + f.doubtful.amount, allIn);
    const s1 = f.lines.inflows.find((l) => l.bill === "S/1");
    assert.deepEqual([s1.expected, s1.delay_days, s1.delay_source, s1.overdue, s1.week], ["2026-10-30", 10, "party", false, 2]);
  });

  test("due-date mode ignores delays; doubtful can be counted; no opening → no balances", () => {
    const f = buildForecast({ ...base, mode: "due", includeDoubtful: true, opening: null });
    const s1 = f.lines.inflows.find((l) => l.bill === "S/1");
    assert.equal(s1.expected, "2026-10-20");
    assert.equal(s1.delay_days, 0);
    assert.equal(f.doubtful.bills, 0);
    assert.equal(f.weeks[0].inflow, 700 + 900 + 50);
    assert.equal(f.weeks[0].opening, null);
    assert.equal(f.weeks[0].closing, null);
    assert.equal(f.shortfall_week, null);
  });
});

describe("Phase 2: exact payments and advances", () => {
  test("receipts against a bill: delay from that bill's due date", () => {
    const rows = [
      // The invoice (New Ref) — 30 days credit; no due date in the bills table.
      { ledger_name: "Mehta", bill_name: "S/5", ref_type: "New Ref", voucher_type: "Sales", date: "2026-08-01", amount: -5000, credit_days: 30 },
      // Paid in two parts: 5 and 15 days after the due date (31 Aug).
      { ledger_name: "Mehta", bill_name: "S/5", ref_type: "Agst Ref", voucher_type: "Receipt", date: "2026-09-05", amount: 3000 },
      { ledger_name: "Mehta", bill_name: "S/5", ref_type: "Agst Ref", voucher_type: "Receipt", date: "2026-09-15", amount: 2000 },
      // Credit note against the bill: not money.
      { ledger_name: "Mehta", bill_name: "S/6", ref_type: "Agst Ref", voucher_type: "Credit Note", date: "2026-09-01", amount: 100 },
      // A bill the bills table knows: its due date wins.
      { ledger_name: "Mehta", bill_name: "S/7", ref_type: "Agst Ref", voucher_type: "Receipt", date: "2026-09-20", amount: 700 },
      // Unknown bill (no New Ref, no due): skipped.
      { ledger_name: "Mehta", bill_name: "OLD", ref_type: "Agst Ref", voucher_type: "Receipt", date: "2026-09-20", amount: 50 },
      // A supplier paid (Dr) against its bill; party kind from the voucher type.
      { ledger_name: "Polycab", bill_name: "P/1", ref_type: "Agst Ref", voucher_type: "Payment", date: "2026-09-10", amount: -900 },
      { ledger_name: "Polycab", bill_name: "P/1", ref_type: "New Ref", voucher_type: "Purchase", date: "2026-09-01", amount: 900, credit_days: null },
    ];
    const m = allocationPayments(rows, {
      kindOf: (p) => (p === "Mehta" ? "recv" : undefined),
      dueOf: (p, b) => (b === "S/7" ? "2026-09-25" : null),
      creditOf: () => 7,
    });
    assert.deepEqual(
      m.get("Mehta").payments.map((x) => [x.bill, x.due, x.amount, x.delay]),
      [
        ["Mehta@S/5", "2026-08-31", 3000, 5],
        ["Mehta@S/5", "2026-08-31", 2000, 15],
        ["Mehta@S/7", "2026-09-25", 700, -5],
      ]
    );
    const pc = m.get("Polycab");
    assert.equal(pc.kind, "pay");
    assert.deepEqual(pc.payments.map((x) => [x.due, x.delay]), [["2026-09-08", 2]]); // 1 Sep + 7 credit days
  });

  test("advances: the opposite side of most bills; ties follow Tally", () => {
    const keys = advanceKeys([
      { bill_type: "RECEIVABLE", ledger_name: "A", bill_name: "1", raw_amount: -100 },
      { bill_type: "RECEIVABLE", ledger_name: "A", bill_name: "2", raw_amount: -50 },
      { bill_type: "RECEIVABLE", ledger_name: "B", bill_name: "ADV", raw_amount: 30 },
      { bill_type: "PAYABLE", ledger_name: "S", bill_name: "P1", raw_amount: 10 },
      { bill_type: "PAYABLE", ledger_name: "S", bill_name: "ADV", raw_amount: -4 },
      { bill_type: "PAYABLE", ledger_name: "Z", bill_name: "0", raw_amount: 0 },
    ]);
    assert.deepEqual([...keys].sort(), ["pay|S@ADV", "recv|B@ADV"]);
    // One of each on the receivable side: Tally's own Dr (−) is normal.
    const tie = advanceKeys([
      { bill_type: "RECEIVABLE", ledger_name: "A", bill_name: "1", raw_amount: -1 },
      { bill_type: "RECEIVABLE", ledger_name: "B", bill_name: "2", raw_amount: 1 },
    ]);
    assert.deepEqual([...tie], ["recv|B@2"]);
    assert.equal(advanceKeys([]).size, 0);
  });

  test("forecast leaves advances out and counts them", () => {
    const f = buildForecast({
      today: "2026-10-14",
      receivables: [
        { party: "A", bill: "1", due: "2026-10-15", amount: 100 },
        { party: "B", bill: "ADV", due: "2026-10-15", amount: 30 },
      ],
      payables: [{ party: "S", bill: "ADV", due: "2026-10-15", amount: 4 }],
      isAdvance: (kind, p, b) => b === "ADV",
    });
    assert.equal(f.totals.inflow, 100);
    assert.equal(f.totals.outflow, 0);
    assert.deepEqual(f.advances, { received: { amount: 30, bills: 1 }, paid: { amount: 4, bills: 1 } });
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
    this.calls = [];
    this.access = new Set(); // "admin:user"
    this.active = { 7: "CO-1" };
    this.bills = [
      { ledger_name: "Mehta", bill_name: "S/9", due_date: "2026-10-20", pending_amount: 4000, bill_type: "RECEIVABLE" },
      { ledger_name: "Mehta", bill_name: "S/1", due_date: "2026-06-10", pending_amount: 0, bill_type: "RECEIVABLE" },
      { ledger_name: "Polycab", bill_name: "P/3", due_date: "2026-10-22", pending_amount: 2500, bill_type: "PAYABLE" },
    ];
    this.settlements = null; // Phase 2 tables not created
    this.signs = null;
    this.writes = [];
  }
  async query(sql, p = []) {
    const s = sql.replace(/\s+/g, " ").trim();
    this.calls.push(s);
    if (s.startsWith("SELECT 1 FROM financial_report_access")) {
      const ok = this.access.has(`${p[0]}:${p[1]}`);
      return { rows: ok ? [{}] : [], rowCount: ok ? 1 : 0 };
    }
    if (s.startsWith("SELECT ac.company_guid")) {
      return { rows: this.active[p[0]] ? [{ company_guid: this.active[p[0]], company_name: "Rajlaxmi Traders" }] : [] };
    }
    if (s.startsWith("SELECT ledger_name, bill_name, due_date, pending_amount, bill_type FROM bills")) {
      assert.match(s, /pending_amount > 0/);
      return { rows: this.bills.filter((b) => b.pending_amount > 0) };
    }
    if (s.startsWith("SELECT ledger_name, bill_name, due_date, bill_type FROM bills")) {
      return { rows: this.bills };
    }
    if (s.includes("MAX(v.reference_no) AS ref")) {
      // Mehta: invoice S/1 (due 10 Jun) paid 30 Jun → 20 days late.
      return {
        rows: [
          { party: "Mehta", guid: "g1", date: "2026-06-01", type: "Sales", net: -10000, ref: "S/1" },
          { party: "Mehta", guid: "g2", date: "2026-06-30", type: "Receipt", net: 10000, ref: "R/1" },
          { party: "Polycab", guid: "g3", date: "2026-07-01", type: "Purchase", net: 3000, ref: "P/1" },
          { party: "Polycab", guid: "g4", date: "2026-07-05", type: "Payment", net: -3000, ref: "PY/1" },
        ],
      };
    }
    if (s.includes("ve.voucher_date < $4::date")) return { rows: [] };
    if (s.startsWith("SELECT name, opening_balance FROM ledgers")) return { rows: [] };
    if (s.includes("= ANY($5::text[])")) {
      // Matched by name key (capitals / spaces as Tally compares names).
      assert.match(s, /regexp_replace\(ve\.ledger_name/);
      assert.deepEqual(p[4], ["hdfc bank", "cash"].filter((k) => p[4].includes(k)));
      // Cash moved after the financial figures' date: 500 paid out of HDFC.
      return { rows: [{ name: "HDFC Bank", net: 500 }] };
    }
    // Phase 2 tables (null: not created yet → Postgres "undefined table").
    const missing = () => Object.assign(new Error("relation does not exist"), { code: "42P01" });
    if (s.startsWith("SELECT ledger_name, bill_name, ref_type, voucher_type, voucher_date::text AS date")) {
      if (!this.settlements) throw missing();
      return { rows: this.settlements };
    }
    if (s.startsWith("SELECT bill_type, ledger_name, bill_name, raw_amount FROM bill_balance_signs")) {
      if (!this.signs) throw missing();
      return { rows: this.signs };
    }
    if (s.startsWith("SELECT 1 FROM companies")) {
      const ok = p[0] === "CO-1" && p[1] === 7;
      return { rows: ok ? [{}] : [], rowCount: ok ? 1 : 0 };
    }
    if (s.startsWith("DELETE FROM bill_settlements") || s.startsWith("DELETE FROM bill_balance_signs")) {
      if (this.tablesMissing) throw missing();
      this.writes.push({ sql: s.slice(0, 40), params: p });
      return { rows: [], rowCount: 0 };
    }
    if (s.startsWith("INSERT INTO bill_settlements") || s.startsWith("INSERT INTO bill_balance_signs")) {
      this.writes.push({ sql: s.slice(0, 40), params: p, rows: JSON.parse(p[p.length - 1]) });
      return { rows: [], rowCount: 1 };
    }
    throw new Error(`Unexpected SQL: ${s}`);
  }
}

const fakeFinancial = {
  async context() {
    return {
      groups: [
        { name: "Bank Accounts", parent: "Current Assets" },
        { name: "Cash-in-Hand", parent: "Current Assets" },
        { name: "Current Assets", parent: "" },
      ],
      anchors: [{ fy: "2026-04-01" }],
    };
  },
  async offeredDates() {
    return [{ as_on: "2026-10-31" }, { as_on: "2026-09-30" }];
  },
  async snapshotAt(s, ctx, d) {
    assert.equal(d, "2026-09-30"); // newest date not after today
    return {
      ledgers: [
        { name: "HDFC Bank", parent: "Bank Accounts", closing: -20000 }, // Dr 20,000
        { name: "Cash", parent: "Cash-in-Hand", closing: -1500 },
        { name: "Mehta", parent: "Sundry Debtors", closing: -4000 },
      ],
    };
  },
};

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
  return {
    get: async (path) => {
      const r = await fetch(base + path);
      return { status: r.status, body: await r.json() };
    },
    post: async (path, body) => {
      const r = await fetch(base + path, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(body),
      });
      return { status: r.status, body: await r.json() };
    },
    close: () => new Promise((ok) => server.close(ok)),
  };
}

describe("routes", { skip: express ? false : "express not installed here (run from the backend folder)" }, () => {
  const now = () => new Date("2026-10-14T06:00:00Z"); // 14 Oct, India time
  const make = async (db, user = { id: 7, role: "ADMIN", adminId: 7 }, financialData = fakeFinancial) => {
    const { createCashflowRouter } = await import("../utils/cashflowRouter.js");
    const auth = (req, res, next) => next();
    return serve(createCashflowRouter({ db, auth, financialData, now, log: { error: () => {} } }), user);
  };

  test("forecast: opening = cash + bank today, delays from history, weeks", async () => {
    const db = new FakeDb();
    const api = await make(db);
    const r = await api.get("/api/cashflow/forecast");
    await api.close();
    assert.equal(r.status, 200);
    const d = r.body.data;
    assert.equal(d.company, "Rajlaxmi Traders");
    assert.equal(d.as_on, "2026-10-14");
    // 20,000 − 500 paid since 30 Sep + 1,500 cash; debtors not counted.
    assert.equal(d.opening.amount, 21000);
    assert.equal(d.opening.based_on, "2026-09-30");
    assert.deepEqual(d.opening.accounts.map((a) => a.name), ["HDFC Bank", "Cash"]);
    // Mehta pays 20 days late: S/9 due 20 Oct → 9 Nov (week of 9 Nov).
    const top = d.top_receivables[0];
    assert.deepEqual([top.party, top.amount, top.delay_days, top.delay_source], ["Mehta", 4000, 20, "blend"]);
    assert.equal(d.weeks[1].outflow, 2500); // Polycab due 22 Oct
    assert.equal(d.weeks[1].closing, 21000 - 2500);
    assert.equal(d.totals.inflow, 4000);
    assert.equal(d.delays.company_median, 20);
    assert.equal(d.counts.receivable_bills, 1);
  });

  test("due-date mode; one week's bills; bad week", async () => {
    const db = new FakeDb();
    const api = await make(db);
    const due = await api.get("/api/cashflow/forecast?mode=due");
    assert.equal(due.body.data.weeks[1].inflow, 4000); // 20 Oct
    const w = await api.get("/api/cashflow/week?start=2026-10-19&mode=due");
    assert.equal(w.status, 200);
    assert.deepEqual(w.body.data.inflows.map((l) => [l.party, l.bill, l.expected]), [["Mehta", "S/9", "2026-10-20"]]);
    assert.deepEqual(w.body.data.outflows.map((l) => l.bill), ["P/3"]);
    assert.equal((await api.get("/api/cashflow/week?start=2026-10-20")).status, 404); // not a Monday
    assert.equal((await api.get("/api/cashflow/week?start=oops")).status, 400);
    await api.close();
  });

  test("delays are kept 6 hours (history read once)", async () => {
    const db = new FakeDb();
    const api = await make(db);
    await api.get("/api/cashflow/forecast");
    await api.get("/api/cashflow/forecast?mode=due");
    const history = (c) => c.includes("AS party, ve.voucher_guid");
    const reads = db.calls.filter(history).length;
    await api.get("/api/cashflow/forecast?refresh=1");
    const after = db.calls.filter(history).length;
    await api.close();
    assert.equal(reads, 1);
    assert.equal(after, 2);
  });

  test("team member: only with financial-report access; no company → 409", async () => {
    const db = new FakeDb();
    const member = { id: 21, role: "USER", adminId: 7 };
    let api = await make(db, member);
    const no = await api.get("/api/cashflow/forecast");
    assert.equal(no.status, 403);
    assert.equal(no.body.code, "no_access");
    db.access.add("7:21");
    assert.equal((await api.get("/api/cashflow/forecast")).status, 200);
    await api.close();
    db.active = {};
    api = await make(db);
    const nc = await api.get("/api/cashflow/forecast");
    await api.close();
    assert.equal(nc.status, 409);
  });

  test("financial figures not synced: forecast still works, no balances", async () => {
    const db = new FakeDb();
    const api = await make(db, undefined, { ...fakeFinancial, context: async () => ({ groups: [], anchors: [] }) });
    const r = await api.get("/api/cashflow/forecast");
    await api.close();
    assert.equal(r.status, 200);
    assert.equal(r.body.data.opening.amount, null);
    assert.equal(r.body.data.opening.reason, "financial_not_synced");
    assert.equal(r.body.data.weeks[0].closing, null);
    assert.equal(r.body.data.totals.outflow, 2500);
  });

  /* ------------------------------------------------------ Phase 2 */

  test("Phase 2 not set up (no tables): Phase 1 estimate, nothing left out", async () => {
    const db = new FakeDb(); // settlements / signs: relation does not exist
    const api = await make(db);
    const r = await api.get("/api/cashflow/forecast");
    await api.close();
    assert.equal(r.status, 200);
    assert.equal(r.body.data.delays.method, "fifo");
    assert.equal(r.body.data.delays.parties_exact, 0);
    assert.equal(r.body.data.advances_checked, false);
    assert.deepEqual(r.body.data.advances.received, { amount: 0, bills: 0 });
    assert.equal(r.body.data.top_receivables[0].method, "fifo");
  });

  test("exact delays from bill-wise receipts win over the estimate", async () => {
    const db = new FakeDb();
    // S/1 (due 10 Jun) was really paid on 10 Jul: 30 days, not FIFO's 20.
    db.settlements = [
      { ledger_name: "Mehta", bill_name: "S/1", ref_type: "New Ref", voucher_type: "Sales", date: "2026-06-01", amount: -10000, credit_days: 9 },
      { ledger_name: "Mehta", bill_name: "S/1", ref_type: "Agst Ref", voucher_type: "Receipt", date: "2026-07-10", amount: 10000, credit_days: null },
    ];
    db.signs = [];
    const api = await make(db);
    const r = await api.get("/api/cashflow/forecast?refresh=1");
    await api.close();
    const top = r.body.data.top_receivables[0];
    assert.deepEqual([top.party, top.delay_days, top.method], ["Mehta", 30, "alloc"]);
    assert.equal(r.body.data.delays.method, "alloc"); // customers only (Polycab is a supplier)
    assert.equal(r.body.data.delays.parties_exact, 1);
    assert.equal(r.body.data.delays.company_median, 30);
  });

  test("advances (opposite Dr / Cr) are left out of money in / out", async () => {
    const db = new FakeDb();
    db.bills.push(
      { ledger_name: "Mehta", bill_name: "ADV-1", due_date: "2026-10-15", pending_amount: 600, bill_type: "RECEIVABLE" },
      { ledger_name: "Polycab", bill_name: "ADV-P", due_date: "2026-10-16", pending_amount: 300, bill_type: "PAYABLE" }
    );
    db.settlements = [];
    db.signs = [
      { bill_type: "RECEIVABLE", ledger_name: "Mehta", bill_name: "S/9", raw_amount: -4000 }, // Dr: owed to us
      { bill_type: "RECEIVABLE", ledger_name: "Mehta", bill_name: "ADV-1", raw_amount: 600 }, // Cr: advance
      { bill_type: "RECEIVABLE", ledger_name: "Gupta", bill_name: "S/2", raw_amount: -10 },
      { bill_type: "PAYABLE", ledger_name: "Polycab", bill_name: "P/3", raw_amount: 2500 },
      { bill_type: "PAYABLE", ledger_name: "Polycab", bill_name: "ADV-P", raw_amount: -300 },
      { bill_type: "PAYABLE", ledger_name: "Other", bill_name: "P/9", raw_amount: 5 },
    ];
    const api = await make(db);
    const r = await api.get("/api/cashflow/forecast?mode=due");
    await api.close();
    const d = r.body.data;
    assert.equal(d.advances_checked, true);
    assert.deepEqual(d.advances, { received: { amount: 600, bills: 1 }, paid: { amount: 300, bills: 1 } });
    assert.equal(d.totals.inflow, 4000);
    assert.equal(d.totals.outflow, 2500);
  });

  test("Agent upload: allocations replaced per voucher; checks", async () => {
    const db = new FakeDb();
    const api = await make(db);
    const r = await api.post("/api/cashflow/agent/settlements", {
      company_guid: "CO-1",
      voucher_guids: ["G-R1", "G-EMPTY"],
      rows: [
        { voucher_guid: "G-R1", voucher_date: "2026-09-30", voucher_type: "Receipt", ledger_name: "Mehta", bill_name: "S/1", ref_type: "Agst Ref", amount: 10000 },
        { voucher_guid: "G-R1", voucher_date: "2026-09-30", voucher_type: "Receipt", ledger_name: "Mehta", bill_name: "S/1", ref_type: "Agst Ref", amount: 10000 }, // duplicate
        { voucher_guid: "OTHER", voucher_date: "2026-09-30", ledger_name: "X", bill_name: "Y", ref_type: "Agst Ref", amount: 1 }, // not listed
        { voucher_guid: "G-R1", voucher_date: "bad", ledger_name: "X", bill_name: "Y", ref_type: "Agst Ref", amount: 1 },
        { voucher_guid: "G-R1", voucher_date: "2026-09-30", ledger_name: "X", bill_name: "Y", ref_type: "Weird", amount: 1 },
      ],
    });
    assert.deepEqual(r.body, { success: true, vouchers: 2, rows: 1 });
    assert.match(db.writes[0].sql, /^DELETE FROM bill_settlements/);
    assert.deepEqual(db.writes[0].params[2], ["G-R1", "G-EMPTY"]);
    assert.equal(db.writes[1].rows.length, 1);
    assert.equal(db.writes[1].rows[0].bill_name, "S/1");

    const signs = await api.post("/api/cashflow/agent/bill-signs", {
      company_guid: "CO-1",
      bill_type: "RECEIVABLE",
      bills: [
        { ledger_name: "Mehta", bill_name: "S/9", raw_amount: -4000 },
        { ledger_name: "Mehta", bill_name: "S/9", raw_amount: -4000 },
        { ledger_name: "", bill_name: "x", raw_amount: 1 },
      ],
    });
    assert.deepEqual(signs.body, { success: true, bills: 1 });
    assert.equal((await api.post("/api/cashflow/agent/bill-signs", { company_guid: "CO-1", bill_type: "X", bills: [] })).status, 400);
    assert.equal((await api.post("/api/cashflow/agent/settlements", { company_guid: "CO-9", voucher_guids: ["a"] })).status, 403);
    assert.equal((await api.post("/api/cashflow/agent/settlements", { company_guid: "CO-1", voucher_guids: [] })).status, 400);
    await api.close();

    // Phase 2 SQL not run: a clear 503 (the Agent keeps the upload).
    db.tablesMissing = true;
    const again = await make(db);
    const nr = await again.post("/api/cashflow/agent/settlements", { company_guid: "CO-1", voucher_guids: ["a"], rows: [] });
    assert.equal(nr.status, 503);
    assert.equal(nr.body.code, "not_set_up");
    const ns = await again.post("/api/cashflow/agent/bill-signs", { company_guid: "CO-1", bill_type: "PAYABLE", bills: [] });
    assert.equal(ns.status, 503);
    await again.close();
    db.tablesMissing = false;

    // Only the admin's Agent may upload.
    const member = await make(db, { id: 21, role: "USER", adminId: 7 });
    assert.equal((await member.post("/api/cashflow/agent/settlements", { company_guid: "CO-1", voucher_guids: ["a"] })).status, 403);
    await member.close();
  });
});
