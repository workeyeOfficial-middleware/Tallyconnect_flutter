// Tests for voucher status (node --test --experimental-test-module-mocks).
// No database or network: a fake pg pool records every query. Cases are
// Lumilo's (a "Delivery Challan" under the renamed Delivery Note, Purchase
// Orders, an optional challan, cancelled vouchers) and an older Agent /
// a database before sql/2026-10-22_voucher_status.sql, where everything
// must stay exactly as today. Run from the backend folder:
//   node --test --experimental-test-module-mocks test/voucherStatus.test.mjs
import { test, describe, beforeEach, after, mock } from "node:test";
import assert from "node:assert/strict";
import express from "express";

import { IN_BOOKS, resetVoucherStatusCache, voucherStatus } from "../utils/voucherStatus.js";
import { createFinancialData } from "../utils/financialData.js";

/* ------------------------------------------------------ fake pool */
const fake = { statusCols: true, queries: [] };
function answer(sql, params) {
  fake.queries.push({ sql, params });
  if (/information_schema\.columns/.test(sql)) {
    if (/is_accounting/.test(sql)) return { rows: fake.statusCols ? Array(5).fill({}) : [], rowCount: 0 };
    return { rows: Array(3).fill({}), rowCount: 3 }; // Cash Flow columns: there
  }
  if (/FROM companies/.test(sql)) return { rows: [{}], rowCount: 1 };
  if (/COUNT\(\*\)/.test(sql)) return { rows: [{ total: 0, n: 0 }], rowCount: 1 };
  return { rows: [], rowCount: 0 };
}
const pool = {
  query: async (sql, params) => answer(sql, params),
  connect: async () => ({ query: async (sql, params) => answer(sql, params), release() {} }),
};

mock.module(new URL("../db.js", import.meta.url).href, { defaultExport: pool });
mock.module(new URL("../middleware/requireAuth.js", import.meta.url).href, {
  defaultExport: (req, _res, next) => {
    req.user = { id: 7, adminId: 7, role: "ADMIN" };
    next();
  },
});
mock.module(new URL("../utils/mobileNotification.js", import.meta.url).href, {
  namedExports: { createMobileNotificationForAdmin: async () => {} },
});
const { default: voucherRoutes } = await import("../routes/voucherEntry.js");
const { default: dashboardRoutes } = await import("../routes/dashboard.js");

const app = express();
app.use(express.json());
app.use("/voucher-entry", voucherRoutes);
app.use("/dashboard", dashboardRoutes);
const server = app.listen(0);
const base = `http://127.0.0.1:${server.address().port}`;
after(() => {
  server.closeAllConnections();
  server.close();
});

const post = (path, body) =>
  fetch(base + path, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) }).then((r) => r.json());
const get = (path) => fetch(base + path).then((r) => r.json());

const voucher = (extra = {}) => ({
  voucher_guid: "g1",
  company_guid: "df5a67db",
  voucher_date: "2025-04-10",
  voucher_type: "Delivery Challan",
  reference_no: "DC/12",
  net_amount: 50000,
  party_name: "CULTFIT HEALTHCARE PVT LTD",
  has_cash_flow: false,
  entries: [
    { ledger_name: "CULTFIT HEALTHCARE PVT LTD", amount: 50000, is_debit: false },
    { ledger_name: "Sales", amount: 50000, is_debit: true },
  ],
  ...extra,
});
const q = (re) => fake.queries.filter((x) => re.test(x.sql));

beforeEach(() => {
  fake.statusCols = true;
  fake.queries = [];
  resetVoucherStatusCache();
});

/* ------------------------------------------------- classification */
describe("is the voucher in the books", () => {
  test("Tally's built-in type decides; cancelled / optional never", () => {
    const yes = ["Sales", "Purchase", "Receipt", "Payment", "Journal", "Contra", "Credit Note", "Debit Note", "Payroll"];
    for (const b of yes) assert.equal(voucherStatus({ is_cancelled: false, is_optional: false, base_type: b }).accounting, true, b);
    const no = ["Purchase Order", "Sales Order", "Delivery Note", "Receipt Note", "Rejections In", "Stock Journal", "Physical Stock", "Memorandum", "Reversing Journal", "Job Work In Order", "Material Out", "Attendance"];
    for (const b of no) assert.equal(voucherStatus({ base_type: b }).accounting, false, b);
    assert.equal(voucherStatus({ is_cancelled: true, base_type: "Sales" }).accounting, false);
    assert.equal(voucherStatus({ is_optional: true, base_type: "Sales" }).accounting, false);
    assert.equal(voucherStatus({ is_cancelled: true }).accounting, false); // type unknown, still out
  });

  test("nothing sent (older Agent): not known = counted as today", () => {
    assert.deepEqual(voucherStatus({}), { cancelled: null, optional: null, base: null, accounting: null });
    assert.deepEqual(voucherStatus(), { cancelled: null, optional: null, base: null, accounting: null });
    assert.equal(voucherStatus({ is_cancelled: "Yes", base_type: "  " }).accounting, null); // only booleans
    assert.equal(IN_BOOKS("ve"), "COALESCE(ve.is_accounting, TRUE) = TRUE");
  });
});

/* ------------------------------------------------------ the sync */
describe("POST /voucher-entry/sync", () => {
  test("Lumilo's Delivery Challan: saved as not in the books, every line too", async () => {
    const r = await post("/voucher-entry/sync", voucher({ is_cancelled: false, is_optional: false, base_type: "Delivery Note" }));
    assert.equal(r.success, true);
    assert.equal(r.skipped, undefined);
    const ins = q(/INSERT INTO vouchers/)[0];
    assert.match(ins.sql, /is_cancelled, is_optional, base_type, is_accounting/);
    assert.match(ins.sql, /\$10,\$11,\$12,\$13,true\)/);
    assert.deepEqual(ins.params.slice(-4), [false, false, "Delivery Note", false]);
    for (const e of q(/INSERT INTO voucher_entries/)) {
      assert.match(e.sql, /\$12,true\)/);
      assert.equal(e.params.at(-1), false);
    }
    const all = q(/SET is_accounting = \$4::boolean/);
    assert.equal(all.length, 1);
    assert.deepEqual(all[0].params, [7, "df5a67db", "g1", false]);
  });

  test("a cancelled sale (no lines from Tally): its old lines leave the books", async () => {
    await post("/voucher-entry/sync", voucher({ voucher_type: "Sales", entries: [], is_cancelled: true, is_optional: false, base_type: "Sales" }));
    assert.equal(q(/INSERT INTO vouchers/)[0].params.at(-1), false);
    assert.deepEqual(q(/SET is_accounting/)[0].params.at(-1), false);
  });

  test("a sale: in the books", async () => {
    await post("/voucher-entry/sync", voucher({ voucher_type: "Sales", is_cancelled: false, is_optional: false, base_type: "Sales" }));
    assert.equal(q(/INSERT INTO vouchers/)[0].params.at(-1), true);
    assert.equal(q(/SET is_accounting/)[0].params.at(-1), true);
  });

  test("older Agent: nothing sent → stored values kept, no extra update", async () => {
    await post("/voucher-entry/sync", voucher());
    const ins = q(/INSERT INTO vouchers/)[0];
    assert.deepEqual(ins.params.slice(-4), [null, null, null, null]);
    assert.match(ins.sql, /is_accounting = COALESCE\(EXCLUDED\.is_accounting, vouchers\.is_accounting\)/);
    assert.match(q(/INSERT INTO voucher_entries/)[0].sql, /COALESCE\(EXCLUDED\.is_accounting, voucher_entries\.is_accounting\)/);
    assert.equal(q(/SET is_accounting/).length, 0);
  });

  test("database before the SQL: exactly today's statements", async () => {
    fake.statusCols = false;
    await post("/voucher-entry/sync", voucher({ is_cancelled: true, is_optional: false, base_type: "Sales" }));
    for (const x of fake.queries) {
      if (/information_schema/.test(x.sql)) continue;
      assert.doesNotMatch(x.sql, /is_cancelled|is_optional|base_type|is_accounting/);
    }
    assert.equal(q(/INSERT INTO vouchers/)[0].params.length, 9);
    assert.equal(q(/INSERT INTO voucher_entries/)[0].params.length, 11);
  });
});

/* ------------------------------------------------------- the lists */
describe("lists and reports", () => {
  test("voucher list: optional ones left out, cancelled ones marked", async () => {
    const r = await get("/voucher-entry/paged?page=1&limit=50");
    assert.equal(r.success, true);
    for (const x of q(/FROM vouchers v/)) assert.match(x.sql, /COALESCE\(v\.is_optional, FALSE\) = FALSE/);
    assert.match(q(/LIMIT \$/)[0].sql, /v\.is_cancelled, v\.is_accounting,/);
  });

  test("voucher list before the SQL: as today", async () => {
    fake.statusCols = false;
    await get("/voucher-entry/paged?page=1&limit=50");
    for (const x of q(/FROM vouchers v/)) assert.doesNotMatch(x.sql, /is_optional|is_cancelled/);
  });

  test("dashboard income / expense: orders and notes left out once known", async () => {
    await get("/dashboard/income-expense?company_guid=df5a67db");
    assert.match(q(/DATE_TRUNC/)[0].sql, /COALESCE\(vouchers\.is_accounting, TRUE\) = TRUE/);
    fake.queries = [];
    fake.statusCols = false;
    resetVoucherStatusCache();
    await get("/dashboard/income-expense?company_guid=df5a67db");
    assert.doesNotMatch(q(/DATE_TRUNC/)[0].sql, /is_accounting/);
  });

  test("financial figures: not-in-books lines left out; before the SQL as today", async () => {
    const s = { adminId: 7, company: "df5a67db" };
    let fd = createFinancialData(pool);
    await fd.monthlyMovements(s, "2025-03-31", "2025-04-30");
    await fd.unbalanced(s, "2025-03-31", "2025-04-30");
    for (const x of q(/FROM voucher_entries ve/)) assert.match(x.sql, /COALESCE\(ve\.is_accounting, TRUE\) = TRUE/);
    fake.queries = [];
    fake.statusCols = false;
    fd = createFinancialData(pool); // its own 10-minute lookup
    await fd.monthlyMovements(s, "2025-03-31", "2025-04-30");
    for (const x of q(/FROM voucher_entries ve/)) assert.doesNotMatch(x.sql, /is_accounting/);
  });
});
