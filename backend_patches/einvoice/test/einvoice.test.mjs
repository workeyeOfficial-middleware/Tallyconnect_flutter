// Tests for e-invoice tracking (node --test). No database or network: an
// in-memory fake pg pool, a stub login and a settable clock. The cases are
// Rajlaxmi's real invoices of 15 Sep 2025 (values shortened).
import { test, describe, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import express from "express";

import { alertsOf, cleanRow, isRegisteredParty, listRange, statusOf, summarize } from "../utils/einvoiceCore.js";
import { createEinvoiceRouter } from "../utils/einvoiceRouter.js";

const QR = "eyJhbGciOiJSUzI1NiIs" + "x".repeat(926); // 946 characters, like Tally's
const inv = (over = {}) => ({
  voucher_guid: "g-srv-125",
  voucher_date: "2025-09-15",
  voucher_type: "Tally Service Invoice",
  voucher_no: "SRV/0125/25-26",
  party_name: "Manisha Steel Centre",
  party_gstin: "27AAIFM2182K1Z0",
  registration_type: "Regular",
  company_gstin: "27AAFCR3058P1ZT",
  place_of_supply: "Maharashtra",
  amount: 11800,
  is_sale: true,
  is_optional: false,
  is_cancelled: false,
  gst_applicable: true,
  irn: "01352aca6a5d5f12468b" + "0".repeat(44),
  ack_no: "122528944683651",
  ack_date: "2025-10-04",
  signed_qr: QR,
  irn_cancelled: false,
  eway_applicable: false,
  eway: null,
  ...over,
});

/* ------------------------------------------------------------ core */
describe("core", () => {
  test("status: done / cancelled / pending / not needed", () => {
    assert.equal(statusOf(inv()), "done");
    assert.equal(statusOf(inv({ irn_cancelled: true })), "cancelled");
    // A sale to a GST-registered customer without an IRN.
    assert.equal(statusOf(inv({ irn: null })), "pending");
    // Rajlaxmi TSS/1000: customer without GST → not needed.
    assert.equal(statusOf(inv({ irn: null, party_gstin: null, registration_type: "Unregistered/Consumer" })), "not_needed");
    // Rajlaxmi proforma: Tally marks it optional and GST not applicable.
    assert.equal(statusOf(inv({ irn: null, is_optional: true, gst_applicable: false })), "not_needed");
    assert.equal(statusOf(inv({ irn: null, is_sale: false })), "not_needed"); // purchase
    assert.equal(statusOf(inv({ irn: null, is_cancelled: true })), "not_needed");
    assert.equal(statusOf(inv({ irn: null, party_gstin: "BAD" })), "not_needed");
    assert.equal(isRegisteredParty({ party_gstin: "27aaifm2182k1z0", registration_type: "Composition" }), true);
  });

  test("alerts: due soon, overdue, late report, ack before the invoice", () => {
    const pending = inv({ irn: null, voucher_date: "2025-09-15" });
    assert.deepEqual(alertsOf(pending, "2025-09-20"), []); // 25 days left
    assert.deepEqual(alertsOf(pending, "2025-10-10"), ["due_soon"]); // 5 left
    assert.deepEqual(alertsOf(pending, "2025-10-16"), ["overdue"]); // 31 days
    // Rajlaxmi: 15 Sep → acknowledged 4 Oct (19 days): fine.
    assert.deepEqual(alertsOf(inv(), "2025-10-21"), []);
    assert.deepEqual(alertsOf(inv({ ack_date: "2025-10-20" }), "2025-10-21"), ["late_report"]);
    // Rajlaxmi CLD/0189: acknowledged 28 May 2024, invoice dated 15 Sep 2025.
    assert.deepEqual(alertsOf(inv({ ack_date: "2024-05-28" }), "2025-10-21"), ["ack_before_invoice"]);
    assert.deepEqual(alertsOf(inv({ irn: null, party_gstin: null }), "2025-12-31"), []); // not needed: no alert
  });

  test("summary counts", () => {
    const rows = [inv(), inv({ irn: null }), inv({ irn: null, party_gstin: null }), inv({ irn_cancelled: true }), inv({ ack_date: "2024-05-28" })];
    assert.deepEqual(summarize(rows, "2025-10-21"), {
      total: 5, done: 2, pending: 1, cancelled: 1, not_needed: 1, overdue: 1, due_soon: 0, late_report: 0, ack_before_invoice: 1,
    });
  });

  test("cleaning what the Agent sends", () => {
    const r = cleanRow({ ...inv(), party_gstin: " 27aaifm2182k1z0 ", amount: -11800, is_sale: "Yes", gst_applicable: "", eway: { BILLNO: "123", EMPTY: "", "": "x" } });
    assert.equal(r.party_gstin, "27AAIFM2182K1Z0");
    assert.equal(r.amount, 11800);
    assert.equal(r.is_sale, true);
    assert.equal(r.gst_applicable, null);
    assert.deepEqual(r.eway, { BILLNO: "123" });
    assert.equal(r.signed_qr.length, 946);
    assert.equal(cleanRow({ voucher_guid: "x", voucher_date: "2025-02-30" }), null);
    assert.equal(cleanRow({ voucher_date: "2025-09-15" }), null);
    assert.equal(cleanRow({ ...inv(), ack_date: "nope" }).ack_date, null);
  });

  test("list range: this financial year by default", () => {
    assert.deepEqual(listRange({}, "2025-10-21"), { ok: true, from: "2025-04-01", to: "2025-10-21" });
    assert.deepEqual(listRange({}, "2026-02-01"), { ok: true, from: "2025-04-01", to: "2026-02-01" });
    assert.equal(listRange({ from: "2025-10-22", to: "2025-10-21" }, "2025-10-21").ok, false);
  });
});

/* ------------------------------------------------------- fake db */
class FakeDb {
  constructor() {
    this.companies = [
      { admin_id: 7, company_guid: "CO-1", name: "Rajlaxmi Solutions" },
      { admin_id: 8, company_guid: "CO-9", name: "Other" },
    ];
    this.active = { 7: "CO-1", 8: "CO-9" };
    this.access = [{ admin_id: 7, user_id: 21 }];
    this.rows = [];
    this.vouchers = []; // {admin_id, company_guid, voucher_guid, is_active}
    this.missing = false;
  }
  async query(sql, p = []) {
    const s = sql.replace(/\s+/g, " ").trim();
    if (s.includes("FROM financial_report_access")) {
      const r = this.access.filter((a) => a.admin_id === p[0] && a.user_id === p[1]);
      return { rows: r, rowCount: r.length };
    }
    if (s.includes("FROM active_company ac")) {
      const g = this.active[p[0]];
      const c = this.companies.find((x) => x.admin_id === p[0] && x.company_guid === g);
      return { rows: g ? [{ company_guid: g, company_name: c?.name }] : [] };
    }
    if (s.startsWith("SELECT 1 FROM companies")) {
      const r = this.companies.filter((c) => c.company_guid === p[0] && c.admin_id === p[1]);
      return { rows: r, rowCount: r.length };
    }
    if (this.missing && s.includes("einvoices")) throw Object.assign(new Error('relation "einvoices" does not exist'), { code: "42P01" });
    if (s.startsWith("INSERT INTO einvoices")) {
      for (const x of JSON.parse(p[2])) {
        const i = this.rows.findIndex((r) => r.admin_id === p[0] && r.company_guid === p[1] && r.voucher_guid === x.voucher_guid);
        const row = { admin_id: p[0], company_guid: p[1], ...x, ack_date: x.ack_date || null };
        if (i >= 0) this.rows[i] = row;
        else this.rows.push(row);
      }
      return { rows: [], rowCount: 0 };
    }
    const live = (r) =>
      this.vouchers.find((v) => v.admin_id === r.admin_id && v.company_guid === r.company_guid && v.voucher_guid === r.voucher_guid)?.is_active !== false;
    const out = (r, qr) => {
      const { signed_qr, admin_id, company_guid, ...rest } = r;
      return qr ? { ...rest, signed_qr } : rest;
    };
    if (s.includes("e.voucher_guid = $3")) {
      const r = this.rows.filter((r) => r.admin_id === p[0] && r.company_guid === p[1] && r.voucher_guid === p[2] && live(r));
      return { rows: r.map((x) => out(x, true)) };
    }
    if (s.includes("e.voucher_date BETWEEN $3::date AND $4::date")) {
      const r = this.rows
        .filter((r) => r.admin_id === p[0] && r.company_guid === p[1] && r.voucher_date >= p[2] && r.voucher_date <= p[3] && live(r))
        .sort((a, b) => b.voucher_date.localeCompare(a.voucher_date) || String(b.voucher_no).localeCompare(String(a.voucher_no)));
      assert.ok(!s.includes("signed_qr"), "the list never sends the QR data");
      return { rows: r.map((x) => out(x, false)) };
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
const ASHA = { id: 21, adminId: 7, role: "USER" }; // allowed financial reports
const VIK = { id: 22, adminId: 7, role: "USER" }; // not allowed
const OTHER = { id: 8, adminId: 8, role: "ADMIN" };

/* ---------------------------------------------------------- routes */
describe("routes", () => {
  let db, server, base;
  beforeEach(async () => {
    db = new FakeDb();
    const app = express();
    app.use(express.json({ limit: "5mb" }));
    app.use(createEinvoiceRouter({ db, auth: stubAuth, log: { error: () => {} }, now: () => new Date("2025-10-21T06:00:00Z") }));
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
  const upload = (rows, user = ADMIN, company = "CO-1") => call("POST", "/api/einvoice/agent/sync", user, { company_guid: company, rows });

  test("every route needs a login", async () => {
    assert.equal((await call("POST", "/api/einvoice/agent/sync", null, {})).status, 401);
    assert.equal((await call("GET", "/api/einvoice/list", null)).status, 401);
    assert.equal((await call("GET", "/api/einvoice/voucher/x", null)).status, 401);
  });

  test("the Agent uploads; again = updated, not doubled; only its own companies", async () => {
    const u = await upload([inv(), inv({ voucher_guid: "g-tss-1000", voucher_no: "TSS/1000/25-26", irn: null, party_gstin: null, registration_type: "Unregistered/Consumer" }), { bad: 1 }]);
    assert.equal(u.status, 200);
    assert.deepEqual([u.body.saved, u.body.skipped], [2, 1]);
    // The IRN arrives later (Tally adds it after the invoice): the same row.
    await upload([inv({ irn: null, ack_no: null, ack_date: null, signed_qr: null }), inv()]);
    assert.equal(db.rows.length, 2);
    assert.ok(db.rows.find((r) => r.voucher_guid === "g-srv-125").irn);
    assert.equal((await upload([inv()], ASHA)).status, 403); // a team member's login
    assert.equal((await upload([inv()], ADMIN, "CO-9")).status, 403); // another account's company
    assert.equal((await upload([], ADMIN, "")).status, 400);
    assert.equal((await upload(Array.from({ length: 1001 }, () => inv()))).status, 413);
  });

  test("list: counts, filters, deleted vouchers left out, no QR data in the list", async () => {
    await upload([
      inv(),
      inv({ voucher_guid: "g-pend", voucher_no: "SRV/0130/25-26", voucher_date: "2025-09-15", irn: null, signed_qr: null, ack_date: null }),
      inv({ voucher_guid: "g-b2c", voucher_no: "TSS/1000/25-26", irn: null, party_gstin: null, registration_type: "Unregistered/Consumer" }),
      inv({ voucher_guid: "g-pro", voucher_no: "Proforma/0138", irn: null, is_optional: true, gst_applicable: false }),
      inv({ voucher_guid: "g-cld", voucher_no: "CLD/0189/25-26", ack_date: "2024-05-28" }),
      inv({ voucher_guid: "g-del", voucher_no: "SRV/0999/25-26", irn: null }),
      inv({ voucher_guid: "g-old", voucher_date: "2024-12-01" }), // last financial year
    ]);
    db.vouchers.push({ admin_id: 7, company_guid: "CO-1", voucher_guid: "g-del", is_active: false });

    const all = await call("GET", "/api/einvoice/list", ADMIN);
    assert.equal(all.status, 200);
    assert.deepEqual([all.body.from, all.body.to], ["2025-04-01", "2025-10-21"]);
    assert.deepEqual(
      { done: all.body.summary.done, pending: all.body.summary.pending, not_needed: all.body.summary.not_needed, overdue: all.body.summary.overdue },
      { done: 2, pending: 1, not_needed: 2, overdue: 1 }
    );
    assert.equal(all.body.rows.length, 5);
    assert.ok(all.body.rows.every((r) => !("signed_qr" in r)));
    const pend = (await call("GET", "/api/einvoice/list?status=pending", ADMIN)).body.rows;
    assert.deepEqual(pend.map((r) => [r.voucher_no, r.days_since, r.days_left, r.alerts]), [["SRV/0130/25-26", 36, 0, ["overdue"]]]);
    const alerts = (await call("GET", "/api/einvoice/list?status=alerts", ADMIN)).body.rows;
    assert.deepEqual(alerts.map((r) => r.voucher_no).sort(), ["CLD/0189/25-26", "SRV/0130/25-26"]);
    assert.equal((await call("GET", "/api/einvoice/list?from=2024-04-01&to=2025-03-31", ADMIN)).body.rows.length, 1);
    assert.equal((await call("GET", "/api/einvoice/list?status=maybe", ADMIN)).status, 400);
    // Team members: only with financial report access.
    assert.equal((await call("GET", "/api/einvoice/list", ASHA)).status, 200);
    assert.equal((await call("GET", "/api/einvoice/list", VIK)).body.code, "no_access");
    // Another account sees its own (none).
    assert.equal((await call("GET", "/api/einvoice/list", OTHER)).body.rows.length, 0);
  });

  test("one invoice with its signed QR; deleted / unknown: 404", async () => {
    await upload([inv(), inv({ voucher_guid: "g-del" })]);
    db.vouchers.push({ admin_id: 7, company_guid: "CO-1", voucher_guid: "g-del", is_active: false });
    const r = await call("GET", "/api/einvoice/voucher/g-srv-125", ADMIN);
    assert.equal(r.status, 200);
    assert.equal(r.body.invoice.signed_qr.length, 946);
    assert.equal(r.body.invoice.ack_no, "122528944683651");
    assert.equal(r.body.invoice.status, "done");
    assert.equal((await call("GET", "/api/einvoice/voucher/g-del", ADMIN)).status, 404);
    assert.equal((await call("GET", "/api/einvoice/voucher/nope", OTHER)).status, 404);
  });

  test("before the SQL is run: a clear 503, never a crash", async () => {
    db.missing = true;
    const r = await call("GET", "/api/einvoice/list", ADMIN);
    assert.equal(r.status, 503);
    assert.equal(r.body.code, "not_set_up");
    assert.equal((await upload([inv()])).status, 503);
  });
});
