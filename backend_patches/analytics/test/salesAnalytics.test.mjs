// Tests for GET /api/analytics/sales (node --test). No database: an
// in-memory fake that answers the endpoint's queries; a stub login.
import { test, describe, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import express from "express";

import { createSalesAnalyticsRouter, growth, previousPeriod, trendKeys } from "../utils/salesAnalytics.js";

describe("helpers", () => {
  test("previous period of the same length; growth; chart keys", () => {
    assert.deepEqual(previousPeriod("2026-09-01", "2026-09-30"), { from: "2026-08-02", to: "2026-08-31" });
    assert.deepEqual(previousPeriod("2026-04-01", "2027-03-31"), { from: "2025-04-01", to: "2026-03-31" });
    assert.equal(growth(120, 100), 20);
    assert.equal(growth(80, 100), -20);
    assert.equal(growth(50, 0), null);
    assert.deepEqual(trendKeys("2026-01-30", "2026-02-02", "day"), ["2026-01-30", "2026-01-31", "2026-02-01", "2026-02-02"]);
    assert.deepEqual(trendKeys("2025-11-15", "2026-02-10", "month"), ["2025-11", "2025-12", "2026-01", "2026-02"]);
  });
});

// Sales types as the SQL classifies them (same regexes).
const isSale = (t) => /sale/i.test(t) && !/(order|quotation|note|return|memo|rejection|reversing)/i.test(t);
const isReturn = (t) => /(credit note|sales return)/i.test(t);

class FakeDb {
  constructor() {
    this.active = { 7: "CO-1" };
    this.allowed = { 21: ["V2", "V3"] };
    const v = (guid, type, date, party, amt, extra = {}) => ({
      admin_id: 7, company_guid: "CO-1", voucher_guid: guid, voucher_type: type, voucher_date: date, party_name: party, net_amount: String(amt), is_active: true, ...extra,
    });
    this.vouchers = [
      v("V1", "Sales", "2026-09-05", "Mehta Electricals", 11800),
      v("V2", "Sales GST", "2026-09-20", "Gupta Stores", 5900),
      v("V3", "Sales", "2026-09-25", "Mehta Electricals", -2360), // sign as synced: amounts are taken as positive
      v("V4", "Sales Order", "2026-09-26", "Gupta Stores", 99999), // an order is not a sale
      v("V5", "Credit Note", "2026-09-28", "Mehta Electricals", 1180), // a return
      v("V6", "Sales", "2026-09-29", "Deleted Co", 50000, { is_active: false }),
      v("V7", "Purchase", "2026-09-10", "Polycab", 30000),
      v("V8", "Sales", "2026-08-15", "Mehta Electricals", 10000), // previous period
      v("V9", "Sales", "2026-01-10", "Gupta Stores", 4000), // Gupta: repeat customer
      v("VX", "Sales", "2026-09-05", "Other Co", 77777, { company_guid: "CO-2" }),
    ];
    const li = (guid, item, qty, amount) => ({ admin_id: 7, company_guid: "CO-1", voucher_guid: guid, item_name: item, quantity: String(qty), amount: String(amount) });
    this.lines = [
      li("V1", "Copper Wire 1.5mm", 10, 8000),
      li("V1", "Switch 6A", 20, 2000),
      li("V2", "Switch 6A", 50, 5000),
      li("V3", "MCB 32A", 4, 2000),
      li("V4", "Copper Wire 1.5mm", 999, 99999),
      li("V7", "Copper Wire 1.5mm", 100, 30000),
      li("V6", "MCB 32A", 100, 50000),
    ];
    this.items = [
      { admin_id: 7, company_guid: "CO-1", name: "Copper Wire 1.5mm", parent_group: "Wires" },
      { admin_id: 7, company_guid: "CO-1", name: "Switch 6A", parent_group: "Switchgear" },
      { admin_id: 7, company_guid: "CO-1", name: "MCB 32A", parent_group: "Switchgear" },
    ];
    this.sql = [];
  }

  matching(s, p) {
    const perm = s.includes("voucher_selection_permissions");
    const userId = perm ? p[4] : null;
    const type = s.includes("~* '(credit note|sales return)'") ? isReturn : isSale;
    return this.vouchers.filter(
      (x) =>
        x.admin_id === p[0] && x.company_guid === p[1] && x.voucher_date >= p[2] && x.voucher_date <= p[3] &&
        x.is_active !== false && type(x.voucher_type) && (!perm || (this.allowed[userId] || []).includes(x.voucher_guid))
    );
  }

  async query(sql, p = []) {
    const s = sql.replace(/\s+/g, " ").trim();
    this.sql.push(s);
    const amt = (x) => Math.abs(Number(x.net_amount));
    if (s.includes("FROM active_company ac")) {
      const g = this.active[p[0]];
      return { rows: g ? [{ company_guid: g, company_name: "Ravi Traders" }] : [] };
    }
    if (s.includes("FROM stock_items")) {
      return { rows: this.items.filter((x) => x.admin_id === p[0] && x.company_guid === p[1] && p[2].includes(x.name)) };
    }
    if (s.includes("first_sale")) {
      const from = p[p.length - 1];
      const rows = this.matching(s, p);
      const by = new Map();
      for (const x of rows) {
        if (!x.party_name) continue;
        const c = by.get(x.party_name) || { first: x.voucher_date, last: x.voucher_date };
        if (x.voucher_date < c.first) c.first = x.voucher_date;
        if (x.voucher_date > c.last) c.last = x.voucher_date;
        by.set(x.party_name, c);
      }
      const inP = [...by.values()].filter((c) => c.last >= from);
      return { rows: [{ new_customers: inP.filter((c) => c.first >= from).length, repeat_customers: inP.filter((c) => c.first < from).length }] };
    }
    if (s.includes("FROM ledger_items li")) {
      const ok = new Set(this.matching(s, p).map((x) => x.voucher_guid));
      const by = new Map();
      for (const l of this.lines) {
        if (l.admin_id !== p[0] || l.company_guid !== p[1] || !ok.has(l.voucher_guid)) continue;
        const c = by.get(l.item_name) || { item: l.item_name, amount: 0, qty: 0, vs: new Set() };
        c.amount += Math.abs(Number(l.amount));
        c.qty += Math.abs(Number(l.quantity));
        c.vs.add(l.voucher_guid);
        by.set(l.item_name, c);
      }
      return { rows: [...by.values()].map((c) => ({ item: c.item, amount: c.amount, qty: c.qty, n: c.vs.size })).sort((a, b) => b.amount - a.amount) };
    }
    const rows = this.matching(s, p);
    if (s.includes(" AS k,")) {
      const day = s.includes("'YYYY-MM-DD'");
      const by = new Map();
      for (const x of rows) {
        const k = day ? x.voucher_date : x.voucher_date.slice(0, 7);
        const c = by.get(k) || { k, total: 0, n: 0 };
        c.total += amt(x);
        c.n++;
        by.set(k, c);
      }
      return { rows: [...by.values()] };
    }
    if (s.includes("AS party")) {
      const by = new Map();
      for (const x of rows) {
        const c = by.get(x.party_name) || { party: x.party_name, n: 0, total: 0 };
        c.n++;
        c.total += amt(x);
        by.set(x.party_name, c);
      }
      return { rows: [...by.values()].sort((a, b) => b.total - a.total) };
    }
    if (s.includes("COUNT(DISTINCT v.party_name)")) {
      return { rows: [{ n: rows.length, total: rows.reduce((a, x) => a + amt(x), 0), customers: new Set(rows.map((x) => x.party_name)).size }] };
    }
    if (s.startsWith("SELECT COUNT(*)::int AS n, COALESCE(SUM")) {
      return { rows: [{ n: rows.length, total: rows.reduce((a, x) => a + amt(x), 0) }] };
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

describe("GET /api/analytics/sales", () => {
  let db, server, base;
  beforeEach(async () => {
    db = new FakeDb();
    const app = express();
    app.use(createSalesAnalyticsRouter({ db, auth: stubAuth, log: { error: () => {} } }));
    await new Promise((r) => {
      server = app.listen(0, r);
    });
    base = `http://127.0.0.1:${server.address().port}`;
  });
  afterEach(() => new Promise((r) => server.close(r)));

  const get = async (q, user = ADMIN) => {
    const r = await fetch(`${base}/api/analytics/sales${q}`, { headers: user ? { "x-test-user": JSON.stringify(user) } : {} });
    return { status: r.status, body: await r.json() };
  };

  test("September: headline numbers vs August, returns, new vs repeat", async () => {
    const r = await get("?from=2026-09-01&to=2026-09-30");
    assert.equal(r.status, 200);
    const k = r.body.data.kpis;
    // V1 11800 + V2 5900 + V3 2360 (order, purchase, deleted, other company left out).
    assert.equal(k.sales, 20060);
    assert.equal(k.invoices, 3);
    assert.equal(k.customers, 2);
    assert.equal(k.avg_invoice, 6686.67);
    assert.equal(k.returns, 1180);
    assert.equal(k.net_sales, 18880);
    assert.equal(k.prev_sales, 10000); // 2026-08-02 … 2026-08-31
    assert.equal(k.growth_pct, 100.6);
    // Mehta sold to before (Aug), Gupta before (Jan): both repeat.
    assert.deepEqual(r.body.data.customers, { new: 0, repeat: 2 });
    assert.deepEqual(r.body.data.previous, { from: "2026-08-02", to: "2026-08-31" });
  });

  test("trend by day for a month (no holes), by month for a year", async () => {
    const m = (await get("?from=2026-09-01&to=2026-09-30")).body.data.trend;
    assert.equal(m.unit, "day");
    assert.equal(m.points.length, 30);
    assert.deepEqual(m.points.find((x) => x.key === "2026-09-05"), { key: "2026-09-05", sales: 11800, invoices: 1 });
    assert.equal(m.points.find((x) => x.key === "2026-09-06").sales, 0);
    const y = (await get("?from=2026-04-01&to=2027-03-31")).body.data.trend;
    assert.equal(y.unit, "month");
    assert.equal(y.points.length, 12);
    assert.equal(y.points.find((x) => x.key === "2026-08").sales, 10000);
  });

  test("top customers with share; top items by amount and quantity; item groups", async () => {
    const d = (await get("?from=2026-09-01&to=2026-09-30")).body.data;
    assert.deepEqual(d.top_customers, [
      { party: "Mehta Electricals", sales: 14160, invoices: 2, share: 70.6 },
      { party: "Gupta Stores", sales: 5900, invoices: 1, share: 29.4 },
    ]);
    assert.deepEqual(d.top_items.map((x) => [x.item, x.amount, x.qty]), [
      ["Copper Wire 1.5mm", 8000, 10],
      ["Switch 6A", 7000, 70],
      ["MCB 32A", 2000, 4],
    ]);
    assert.equal(d.top_items_qty[0].item, "Switch 6A");
    assert.deepEqual(d.item_groups, [
      { group: "Switchgear", amount: 9000 },
      { group: "Wires", amount: 8000 },
    ]);
    assert.equal(d.items_total, 17000);
  });

  test("team users: only the vouchers they may see", async () => {
    const d = (await get("?from=2026-09-01&to=2026-09-30", USER)).body.data;
    assert.equal(d.kpis.sales, 5900 + 2360);
    assert.ok(!JSON.stringify(d).includes("11800"));
    assert.ok(db.sql.some((q) => q.includes("voucher_selection_permissions")));
  });

  test("checks: login, dates, company", async () => {
    assert.equal((await get("?from=2026-09-01&to=2026-09-30", null)).status, 401);
    assert.equal((await get("?from=2026-09-30&to=2026-09-01")).status, 400);
    assert.equal((await get("?from=x&to=2026-09-01")).status, 400);
    assert.equal((await get("?from=2015-01-01&to=2026-09-01")).status, 400);
    delete db.active[7];
    assert.equal((await get("?from=2026-09-01&to=2026-09-30")).body.code, "no_company");
  });
});
