// Tests for the outstanding email reminder API (node --test). No database
// or network: an in-memory fake pg pool, a fake mailer and a stub login.
// Needs only `express` installed next to the files.
import { test, describe, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import express from "express";

import {
  buildReminderEmail,
  DEFAULT_TEMPLATE,
  inr,
  recipientsOf,
  reminderConfig,
  validateSelection,
  validateTemplate,
} from "../utils/reminderCore.js";
import { createReminderRouter } from "../utils/reminderRouter.js";
import { sendReminderEmail } from "../utils/sendReminderEmail.js";

/* ------------------------------------------------------------ core */
describe("core", () => {
  test("recipients: valid, distinct, at most 5", () => {
    assert.deepEqual(recipientsOf("a@x.in; A@X.in, bad, mailto:b@y.com"), ["a@x.in", "b@y.com"]);
    assert.deepEqual(recipientsOf(null), []);
    assert.deepEqual(recipientsOf("not an email"), []);
    assert.equal(recipientsOf("1@x.in 2@x.in 3@x.in 4@x.in 5@x.in 6@x.in").length, 5);
  });

  test("selection: only ledger + bill references; amounts never read", () => {
    const v = validateSelection({
      ledger_guid: " L1 ",
      bill_names: ["B1", "B1", " B2 "],
      pending_amount: 1, // ignored
    });
    assert.equal(v.ok, true);
    assert.deepEqual(v.value, {
      ledgerGuid: "L1",
      billNames: ["B1", "B2"],
      templateId: null,
      expectedTotal: null,
      key: null,
    });
    assert.equal(validateSelection({ ledger_guid: "L1", bill_names: [] }).ok, false);
    assert.equal(validateSelection({ bill_names: ["B1"] }).ok, false);
    assert.equal(validateSelection({ ledger_guid: "L1", bill_names: [5] }).ok, false);
    assert.equal(
      validateSelection({ ledger_guid: "L1", bill_names: Array.from({ length: 51 }, (_, i) => `B${i}`) }).ok,
      false
    );
    assert.equal(validateSelection({ ledger_guid: "L1", bill_names: ["B"], idempotency_key: "x" }).ok, false);
  });

  test("template validation: placeholders checked, subject one line", () => {
    assert.equal(validateTemplate({ name: "A", subject: "Hi {{party}}", body: "{{bills}}" }).ok, true);
    const bad = validateTemplate({ name: "A", subject: "Hi {{amount}}", body: "x" });
    assert.equal(bad.ok, false);
    assert.match(bad.message, /Unknown placeholder \{\{amount\}\}/);
    assert.equal(validateTemplate({ name: "", subject: "s", body: "b" }).ok, false);
    assert.equal(
      validateTemplate({ name: "A", subject: "s\r\nBcc: x@y.z", body: "b" }).value.subject,
      "s Bcc: x@y.z"
    );
    assert.equal(validateTemplate({}, { partial: true }).ok, false);
  });

  test("email: Tally / template text escaped; Indian rupees; one-line subject", () => {
    assert.equal(inr(123456.5), "₹1,23,456.50");
    const m = buildReminderEmail({
      template: { subject: "Due {{total}} from {{company}}\n", body: "<b>Hi</b> {{party}}\n{{bills}}" },
      party: `<script>alert(1)</script>`,
      company: "Shree & Co\r\nBcc: x@y.z",
      sender: "Ravi",
      bills: [
        { bill_name: "INV<1>", bill_date: "2026-09-01", due_date: "2026-09-30", pending_amount: 1000, overdue_days: 12 },
        { bill_name: "INV2", bill_date: null, due_date: null, pending_amount: 234.5, overdue_days: 0 },
      ],
    });
    assert.ok(!m.subject.includes("\n") && !m.subject.includes("\r"));
    assert.equal(m.subject, "Due ₹1,234.50 from Shree & Co Bcc: x@y.z");
    assert.ok(!m.html.includes("<script>"));
    assert.ok(!m.html.includes("<b>Hi</b>"));
    assert.ok(m.html.includes("&lt;script&gt;"));
    assert.ok(m.html.includes("INV&lt;1&gt;"));
    assert.ok(m.html.includes("30-09-2026"));
    assert.ok(m.html.includes("12 days overdue"));
    assert.ok(m.text.includes("INV2 · due — · ₹234.50"));
  });

  test("config: mail ready only with every Microsoft variable", () => {
    assert.equal(reminderConfig({}).mailReady, false);
    assert.equal(
      reminderConfig({
        MICROSOFT_TENANT_ID: "t",
        MICROSOFT_CLIENT_ID: "c",
        MICROSOFT_CLIENT_SECRET: "s",
        MICROSOFT_SENDER_EMAIL: "no-reply@x.in",
      }).mailReady,
      true
    );
  });

  test("mailer: missing configuration is an error, never a success", async () => {
    await assert.rejects(
      sendReminderEmail({ to: ["a@x.in"], subject: "s", html: "h" }, {}),
      (e) => e.code === "not_configured"
    );
  });
});

/* ---------------------------------------------------------- routes */
const MAIL_ENV = {
  MICROSOFT_TENANT_ID: "t",
  MICROSOFT_CLIENT_ID: "c",
  MICROSOFT_CLIENT_SECRET: "s",
  MICROSOFT_SENDER_EMAIL: "no-reply@tally-connect.com",
};

class FakeDb {
  constructor() {
    this.active = { 7: "CO-1", 8: "CO-9" };
    this.companies = [
      { admin_id: 7, company_guid: "CO-1", name: "Ravi Traders" },
      { admin_id: 7, company_guid: "CO-2", name: "Ravi Exports" },
      { admin_id: 8, company_guid: "CO-9", name: "Other Account" },
    ];
    this.ledgers = [
      { admin_id: 7, company_guid: "CO-1", ledger_guid: "L1", name: "Mehta Electricals", email: "accounts@mehta.in" },
      { admin_id: 7, company_guid: "CO-1", ledger_guid: "L2", name: "No Mail Ltd", email: "" },
      { admin_id: 7, company_guid: "CO-2", ledger_guid: "L5", name: "Exports Party", email: "e@x.in" },
      { admin_id: 8, company_guid: "CO-9", ledger_guid: "L9", name: "Someone Else", email: "s@x.in" },
    ];
    this.perms = [{ user_id: 21, ledger_guid: "L1" }];
    const b = (company_guid, ledger_guid, ledger_name, bill_name, pending_amount, due_date, extra = {}) => ({
      admin_id: 7, company_guid, ledger_guid, ledger_name, bill_name, pending_amount,
      due_date, bill_date: "2026-09-01", bill_type: "RECEIVABLE", ...extra,
    });
    this.bills = [
      b("CO-1", "L1", "Mehta Electricals", "INV-1", "10000.00", "2026-09-30"),
      b("CO-1", "L1", "Mehta Electricals", "INV-2", "5000.50", "2026-10-20"),
      b("CO-1", "L1", "Mehta Electricals", "INV-3", "0", "2026-09-10"), // settled
      b("CO-1", "L1", "Mehta Electricals", "PUR-1", "700", "2026-09-10", { bill_type: "PAYABLE" }),
      b("CO-1", null, "Mehta Electricals", "INV-4", "250", null), // synced before the ledger
      b("CO-2", "L1", "Mehta Electricals", "INV-1", "99999", "2026-09-30"), // other company
      b("CO-1", "L2", "No Mail Ltd", "INV-7", "100", "2026-10-01"),
    ];
    this.templates = [];
    this.logs = [];
    this.nextId = 1;
  }

  async query(sql, params = []) {
    const s = sql.replace(/\s+/g, " ").trim();
    const p = params;
    if (s.includes("FROM active_company ac")) {
      const g = this.active[p[0]];
      const c = this.companies.find((x) => x.admin_id === p[0] && x.company_guid === g);
      return { rows: g ? [{ company_guid: g, company_name: c?.name ?? null }] : [] };
    }
    if (s.includes("FROM ledgers WHERE ledger_guid = $1")) {
      return {
        rows: this.ledgers.filter((l) => l.ledger_guid === p[0] && l.admin_id === p[1] && l.company_guid === p[2]),
      };
    }
    if (s.includes("FROM user_ledger_permissions WHERE user_id = $1 AND ledger_guid = $2")) {
      const r = this.perms.filter((x) => x.user_id === p[0] && x.ledger_guid === p[1]);
      return { rows: r, rowCount: r.length };
    }
    if (s.includes("FROM bills")) {
      const rows = this.bills
        .filter(
          (x) =>
            x.admin_id === p[0] &&
            x.company_guid === p[1] &&
            (x.ledger_guid === p[2] || (x.ledger_guid === null && x.ledger_name === p[3])) &&
            p[4].includes(x.bill_name) &&
            Number(x.pending_amount) > 0 &&
            (x.bill_type || "RECEIVABLE").toUpperCase() !== "PAYABLE"
        )
        .sort((a, b) => String(a.due_date ?? "9999").localeCompare(String(b.due_date ?? "9999")));
      return { rows };
    }

    /* templates */
    if (s.startsWith("SELECT COUNT(*)::int AS n FROM reminder_templates")) {
      return { rows: [{ n: this.templates.filter((t) => t.admin_id === p[0]).length }] };
    }
    if (s.startsWith("UPDATE reminder_templates SET is_default = FALSE")) {
      for (const t of this.templates) if (t.admin_id === p[0] && t.id !== p[1]) t.is_default = false;
      return { rows: [] };
    }
    if (s.startsWith("INSERT INTO reminder_templates")) {
      if (this.templates.some((t) => t.admin_id === p[0] && t.name === p[1])) {
        throw Object.assign(new Error("dup"), { code: "23505" });
      }
      const t = { id: this.nextId++, admin_id: p[0], name: p[1], subject: p[2], body: p[3], is_default: p[4] };
      this.templates.push(t);
      return { rows: [{ ...t }] };
    }
    if (s.startsWith("UPDATE reminder_templates SET")) {
      const t = this.templates.find((x) => x.id === p[0] && x.admin_id === p[1]);
      if (!t) return { rows: [] };
      for (const m of s.matchAll(/(name|subject|body|is_default) = \$(\d+)/g)) t[m[1]] = p[Number(m[2]) - 1];
      return { rows: [{ ...t }] };
    }
    if (s.startsWith("DELETE FROM reminder_templates")) {
      const i = this.templates.findIndex((x) => x.id === p[0] && x.admin_id === p[1]);
      if (i < 0) return { rows: [] };
      this.templates.splice(i, 1);
      return { rows: [{ id: p[0] }] };
    }
    if (s.includes("FROM reminder_templates WHERE id = $1 AND admin_id = $2")) {
      return { rows: this.templates.filter((t) => t.id === p[0] && t.admin_id === p[1]) };
    }
    if (s.includes("FROM reminder_templates WHERE admin_id = $1 AND is_default = TRUE")) {
      return { rows: this.templates.filter((t) => t.admin_id === p[0] && t.is_default) };
    }
    if (s.includes("FROM reminder_templates WHERE admin_id = $1")) {
      return { rows: this.templates.filter((t) => t.admin_id === p[0]) };
    }

    /* log */
    const byId = (id) => this.logs.find((r) => r.id === id);
    if (s.startsWith("INSERT INTO reminder_log")) {
      if (p[10] && this.logs.some((r) => r.admin_id === p[0] && r.idempotency_key === p[10])) {
        throw Object.assign(new Error("dup"), { code: "23505" });
      }
      const row = {
        id: this.nextId++, admin_id: p[0], company_guid: p[1], ledger_guid: p[2], ledger_name: p[3],
        template_id: p[4], bill_set: p[5], bills: JSON.parse(p[6]), total_amount: String(p[7]),
        recipients: JSON.parse(p[8]), subject: p[9], status: "pending", error: null, attempts: 0,
        idempotency_key: p[10], sent_by_user_id: p[11], sent_by_email: p[12], sent_by_name: p[13],
        created_at: new Date(), updated_at: new Date(), sent_at: null,
      };
      this.logs.push(row);
      return { rows: [{ ...row }] };
    }
    if (s.startsWith("UPDATE reminder_log SET status = 'accepted'")) {
      const r = byId(p[0]);
      Object.assign(r, { status: "accepted", error: null, provider: p[1], provider_status: p[2], provider_request_id: p[3], sent_at: new Date() });
      r.attempts++;
      return { rows: [{ ...r }] };
    }
    if (s.startsWith("UPDATE reminder_log SET status = 'failed'")) {
      const r = byId(p[0]);
      Object.assign(r, { status: "failed", error: p[1], provider_status: p[2] ?? null });
      r.attempts++;
      return { rows: [{ ...r }] };
    }
    if (s.startsWith("UPDATE reminder_log SET status = 'pending'")) {
      const r = byId(p[0]);
      if (!r || r.status !== "failed") return { rows: [] };
      Object.assign(r, {
        status: "pending", error: null, bills: JSON.parse(p[1]), total_amount: String(p[2]),
        recipients: JSON.parse(p[3]), subject: p[4], bill_set: p[5],
      });
      return { rows: [{ ...r }] };
    }
    if (s.includes("FROM reminder_log WHERE admin_id = $1 AND idempotency_key = $2")) {
      return { rows: this.logs.filter((r) => r.admin_id === p[0] && r.idempotency_key === p[1]) };
    }
    if (s.includes("COUNT(*) FILTER")) {
      const mine = this.logs.filter((r) => r.admin_id === p[0]);
      return { rows: [{ hour: mine.filter((r) => r.sent_by_user_id === p[1]).length, day: mine.length }] };
    }
    if (s.includes("AND bill_set = $4")) {
      return {
        rows: this.logs.filter(
          (r) =>
            r.admin_id === p[0] && r.company_guid === p[1] && r.ledger_guid === p[2] &&
            r.bill_set === p[3] && ["pending", "accepted"].includes(r.status)
        ),
      };
    }
    if (s.includes("FROM reminder_log WHERE id = $1 AND admin_id = $2")) {
      return { rows: this.logs.filter((r) => r.id === p[0] && r.admin_id === p[1]).map((r) => ({ ...r })) };
    }
    if (s.includes("FROM reminder_log WHERE admin_id = $1 AND company_guid = $2")) {
      let rows = this.logs.filter((r) => r.admin_id === p[0] && r.company_guid === p[1]);
      if (s.includes("AND ledger_guid = $3")) rows = rows.filter((r) => r.ledger_guid === p[2]);
      if (s.includes("ledger_guid IN (SELECT")) {
        const ok = this.perms.filter((x) => x.user_id === p[2]).map((x) => x.ledger_guid);
        rows = rows.filter((r) => ok.includes(r.ledger_guid));
      }
      return { rows: [...rows].reverse() };
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

const ADMIN = { id: 7, adminId: 7, role: "ADMIN", username: "Ravi", email: "ravi@x.in" };
const USER_OK = { id: 21, adminId: 7, role: "USER", username: "Asha", email: "asha@x.in" };
const USER_NONE = { id: 22, adminId: 7, role: "USER", username: "Vik", email: "vik@x.in" };
const OTHER_ADMIN = { id: 8, adminId: 8, role: "ADMIN", username: "Zed", email: "z@x.in" };

describe("routes", () => {
  let db, sent, server, base, mailFails, env;
  const quiet = { error: () => {} };

  beforeEach(async () => {
    db = new FakeDb();
    sent = [];
    mailFails = null;
    env = { ...MAIL_ENV, REMINDER_RATE_LIMIT_PER_HOUR: "5" };
    const app = express();
    app.use(express.json());
    app.use(
      createReminderRouter({
        db,
        auth: stubAuth,
        env,
        log: quiet,
        now: () => new Date(2026, 9, 12),
        sendEmail: async (m) => {
          if (mailFails) throw mailFails;
          sent.push(m);
          return { provider: "microsoft-graph", status: 202, requestId: "req-1" };
        },
      })
    );
    await new Promise((resolve) => {
      server = app.listen(0, resolve);
    });
    base = `http://127.0.0.1:${server.address().port}`;
  });
  afterEach(() => new Promise((resolve) => server.close(resolve)));

  const call = async (method, path, user, body) => {
    const r = await fetch(base + path, {
      method,
      headers: {
        "content-type": "application/json",
        ...(user ? { "x-test-user": JSON.stringify(user) } : {}),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    return { status: r.status, headers: r.headers, body: await r.json() };
  };
  const SEL = { ledger_guid: "L1", bill_names: ["INV-1", "INV-2", "INV-3", "PUR-1", "INV-4", "NOPE"] };

  test("every route needs a login", async () => {
    for (const [m, path] of [
      ["GET", "/api/reminders/templates"],
      ["POST", "/api/reminders/preview"],
      ["POST", "/api/reminders/send"],
      ["GET", "/api/reminders/history"],
      ["POST", "/api/reminders/1/retry"],
    ]) {
      assert.equal((await call(m, path, null, m === "POST" ? SEL : undefined)).status, 401, path);
    }
  });

  test("preview: bills rebuilt on the server (active company, pending receivables)", async () => {
    const r = await call("POST", "/api/reminders/preview", ADMIN, {
      ...SEL,
      bills: [{ bill_name: "INV-1", pending_amount: 1 }], // ignored
      total: 1, // ignored
    });
    assert.equal(r.status, 200);
    const d = r.body.data;
    assert.deepEqual(d.bills.map((b) => b.bill_name), ["INV-1", "INV-2", "INV-4"]);
    assert.equal(d.total, 15250.5); // never the other company's 99999
    assert.deepEqual(d.missing_bills, ["INV-3", "PUR-1", "NOPE"]);
    assert.deepEqual(d.recipients, ["accounts@mehta.in"]);
    assert.equal(d.company, "Ravi Traders");
    assert.equal(d.bills[0].overdue_days, 12);
    assert.equal(d.template.name, DEFAULT_TEMPLATE.name);
    assert.equal(d.can_send, true);
    assert.match(d.subject, /₹15,250\.50/);
  });

  test("company isolation: other company's / other account's ledgers are not found", async () => {
    // L5 is in the same account but not the active company.
    assert.equal((await call("POST", "/api/reminders/preview", ADMIN, { ledger_guid: "L5", bill_names: ["X"] })).status, 404);
    // L9 belongs to another account.
    assert.equal((await call("POST", "/api/reminders/preview", ADMIN, { ledger_guid: "L9", bill_names: ["X"] })).status, 404);
    assert.equal((await call("POST", "/api/reminders/send", ADMIN, { ledger_guid: "L9", bill_names: ["X"] })).status, 404);
    // The other account cannot see this account's ledger either.
    assert.equal((await call("POST", "/api/reminders/preview", OTHER_ADMIN, SEL)).status, 404);
    assert.equal(sent.length, 0);
  });

  test("no active company (e.g. nothing selected) → 409, nothing sent", async () => {
    delete db.active[7];
    const r = await call("POST", "/api/reminders/send", ADMIN, SEL);
    assert.equal(r.status, 409);
    assert.equal(r.body.code, "no_company");
    assert.equal(sent.length, 0);
  });

  test("ledger permissions for USER logins", async () => {
    assert.equal((await call("POST", "/api/reminders/preview", USER_NONE, SEL)).status, 403);
    assert.equal((await call("POST", "/api/reminders/send", USER_NONE, SEL)).status, 403);
    assert.equal((await call("GET", "/api/reminders/history?ledger_guid=L1", USER_NONE)).status, 403);
    assert.equal(sent.length, 0);
    const ok = await call("POST", "/api/reminders/send", USER_OK, SEL);
    assert.equal(ok.status, 200);
    assert.equal(sent[0].replyTo, "asha@x.in");
    // Admin's reminder for L2: a user with access to L1 only does not see it.
    db.ledgers[1].email = "nm@x.in";
    assert.equal((await call("POST", "/api/reminders/send", ADMIN, { ledger_guid: "L2", bill_names: ["INV-7"] })).status, 200);
    const mine = await call("GET", "/api/reminders/history", USER_OK);
    assert.deepEqual(mine.body.data.map((x) => x.ledger_guid), ["L1"]);
    const all = await call("GET", "/api/reminders/history", ADMIN);
    assert.equal(all.body.data.length, 2);
    assert.equal((await call("GET", "/api/reminders/history", USER_NONE)).body.data.length, 0);
  });

  test("send: provider result recorded; 'accepted' is not reported as delivered", async () => {
    const r = await call("POST", "/api/reminders/send", ADMIN, { ...SEL, expected_total: 15250.5 });
    assert.equal(r.status, 200);
    assert.equal(r.body.success, true);
    assert.equal(r.body.data.status, "accepted");
    assert.match(r.body.message, /Accepted by Microsoft 365/);
    assert.match(r.body.message, /not confirmed/);
    assert.equal(sent.length, 1);
    assert.deepEqual(sent[0].to, ["accounts@mehta.in"]);
    assert.equal(sent[0].replyTo, "ravi@x.in");
    assert.ok(sent[0].html.includes("INV-2"));
    const row = db.logs[0];
    assert.equal(row.status, "accepted");
    assert.equal(row.provider_status, 202);
    assert.equal(row.provider_request_id, "req-1");
    assert.equal(row.total_amount, "15250.5");
    assert.equal(row.attempts, 1);
    const h = await call("GET", "/api/reminders/history?ledger_guid=L1", ADMIN);
    assert.equal(h.body.data[0].status, "accepted");
    assert.equal(h.body.data[0].sent_by, "ravi@x.in");
  });

  test("provider failure → 502 with the provider's error, then retry", async () => {
    mailFails = Object.assign(new Error("Microsoft Graph refused the email (HTTP 403): Access denied"), {
      code: "provider_error",
      status: 403,
    });
    const r = await call("POST", "/api/reminders/send", ADMIN, SEL);
    assert.equal(r.status, 502);
    assert.equal(r.body.success, false);
    assert.equal(r.body.code, "send_failed");
    assert.match(r.body.message, /HTTP 403/);
    assert.equal(db.logs[0].status, "failed");
    assert.equal(db.logs[0].provider_status, 403);
    // A paid bill is left out on retry; amounts are read again.
    db.bills.find((b) => b.bill_name === "INV-4").pending_amount = "0";
    mailFails = null;
    const again = await call("POST", `/api/reminders/${db.logs[0].id}/retry`, ADMIN);
    assert.equal(again.status, 200);
    assert.equal(again.body.data.status, "accepted");
    assert.equal(again.body.data.total, 15000.5);
    assert.equal(db.logs[0].attempts, 2);
    assert.equal(db.logs.length, 1);
    // An accepted one cannot be retried.
    assert.equal((await call("POST", `/api/reminders/${db.logs[0].id}/retry`, ADMIN)).status, 409);
  });

  test("mail not configured → 503, attempt recorded as failed, never a success", async () => {
    delete env.MICROSOFT_CLIENT_SECRET;
    const p = await call("POST", "/api/reminders/preview", ADMIN, SEL);
    assert.equal(p.body.data.can_send, false);
    assert.equal(p.body.data.email_configured, false);
    const r = await call("POST", "/api/reminders/send", ADMIN, SEL);
    assert.equal(r.status, 503);
    assert.equal(r.body.success, false);
    assert.equal(r.body.code, "email_not_configured");
    assert.equal(sent.length, 0);
    assert.equal(db.logs[0].status, "failed");
  });

  test("duplicates: same bills again refused; same confirmation replayed, one email", async () => {
    const key = "confirm-abc12345";
    const a = await call("POST", "/api/reminders/send", ADMIN, { ...SEL, idempotency_key: key });
    assert.equal(a.status, 200);
    const b = await call("POST", "/api/reminders/send", ADMIN, { ...SEL, idempotency_key: key });
    assert.equal(b.status, 200);
    assert.equal(b.body.replay, true);
    assert.equal(sent.length, 1);
    const c = await call("POST", "/api/reminders/send", ADMIN, { ...SEL, bill_names: ["INV-4", "INV-2", "INV-1"] });
    assert.equal(c.status, 409);
    assert.equal(c.body.code, "duplicate");
    assert.equal(sent.length, 1);
    // A different set of bills is a different reminder.
    assert.equal((await call("POST", "/api/reminders/send", ADMIN, { ledger_guid: "L1", bill_names: ["INV-1"] })).status, 200);
    // No duplicate window when set to 0.
    env.REMINDER_DUPLICATE_WINDOW_MINUTES = "0";
    assert.equal((await call("POST", "/api/reminders/send", ADMIN, { ledger_guid: "L1", bill_names: ["INV-1"] })).status, 200);
  });

  test("changed since preview / nothing pending / no email address", async () => {
    const ch = await call("POST", "/api/reminders/send", ADMIN, { ...SEL, expected_total: 15000 });
    assert.equal(ch.status, 409);
    assert.equal(ch.body.code, "changed");
    assert.equal(ch.body.data.total, 15250.5);
    const none = await call("POST", "/api/reminders/send", ADMIN, { ledger_guid: "L1", bill_names: ["INV-3"] });
    assert.equal(none.status, 409);
    assert.equal(none.body.code, "nothing_pending");
    const nm = await call("POST", "/api/reminders/send", ADMIN, { ledger_guid: "L2", bill_names: ["INV-7"] });
    assert.equal(nm.status, 422);
    assert.equal(nm.body.code, "no_email");
    assert.equal(sent.length, 0);
    assert.equal(db.logs.length, 0);
  });

  test("rate limit per user per hour", async () => {
    for (let i = 1; i <= 5; i++) {
      env.REMINDER_DUPLICATE_WINDOW_MINUTES = "0";
      assert.equal((await call("POST", "/api/reminders/send", ADMIN, { ledger_guid: "L1", bill_names: ["INV-1"] })).status, 200);
    }
    const r = await call("POST", "/api/reminders/send", ADMIN, { ledger_guid: "L1", bill_names: ["INV-1"] });
    assert.equal(r.status, 429);
    assert.equal(r.headers.get("retry-after"), "3600");
    assert.equal(sent.length, 5);
  });

  test("templates: built-in by default; only the admin manages them", async () => {
    const list = await call("GET", "/api/reminders/templates", USER_OK);
    assert.equal(list.body.data[0].name, DEFAULT_TEMPLATE.name);
    assert.equal(list.body.can_edit, false);
    assert.equal(list.body.email_configured, true);
    const t = { name: "Firm", subject: "{{party}}: {{total}} due", body: "Pay now.\n{{bills}}", is_default: true };
    assert.equal((await call("POST", "/api/reminders/templates", USER_OK, t)).status, 403);
    const made = await call("POST", "/api/reminders/templates", ADMIN, t);
    assert.equal(made.status, 201);
    const id = made.body.data.id;
    assert.equal((await call("POST", "/api/reminders/templates", ADMIN, t)).status, 409); // same name
    assert.equal(
      (await call("POST", "/api/reminders/templates", ADMIN, { ...t, name: "X", body: "{{amount}}" })).status,
      400
    );
    // The default template is used for the preview.
    const p = await call("POST", "/api/reminders/preview", ADMIN, SEL);
    assert.equal(p.body.data.subject, "Mehta Electricals: ₹15,250.50 due");
    assert.equal((await call("PUT", `/api/reminders/templates/${id}`, USER_OK, { name: "Y" })).status, 403);
    const up = await call("PUT", `/api/reminders/templates/${id}`, ADMIN, { subject: "Reminder · {{company}}" });
    assert.equal(up.status, 200);
    assert.equal(up.body.data.subject, "Reminder · {{company}}");
    // Another account cannot use or change this template.
    assert.equal((await call("PUT", `/api/reminders/templates/${id}`, OTHER_ADMIN, { name: "Z" })).status, 404);
    assert.equal((await call("POST", "/api/reminders/preview", ADMIN, { ...SEL, template_id: 999 })).status, 404);
    assert.equal((await call("DELETE", `/api/reminders/templates/${id}`, USER_OK)).status, 403);
    assert.equal((await call("DELETE", `/api/reminders/templates/${id}`, ADMIN)).status, 200);
    assert.equal((await call("DELETE", `/api/reminders/templates/${id}`, ADMIN)).status, 404);
  });

  test("retry: only this company's reminders", async () => {
    mailFails = new Error("boom");
    await call("POST", "/api/reminders/send", ADMIN, SEL);
    mailFails = null;
    db.active[7] = "CO-2";
    assert.equal((await call("POST", `/api/reminders/${db.logs[0].id}/retry`, ADMIN)).status, 404);
    assert.equal((await call("POST", `/api/reminders/${db.logs[0].id}/retry`, OTHER_ADMIN)).status, 404);
    assert.equal((await call("POST", "/api/reminders/abc/retry", ADMIN)).status, 400);
    assert.equal(sent.length, 0);
  });
});
