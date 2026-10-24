// Tests for payment reminder settings (node --test): before / after / both
// the due date, days, hour (India time), Automatic vs Manual, the "due
// today" list and the hourly automatic run. No database or network: a
// small in-memory fake pg pool, a fake mailer and a stub login.
import { test, describe, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import express from "express";

import { DEFAULT_SETTINGS, autoKey, istNow, reminderDue, settingsOf, validateSettings } from "../utils/reminderCore.js";
import { createReminderRouter } from "../utils/reminderRouter.js";

const S = (x = {}) => ({ ...DEFAULT_SETTINGS, ...x });

/* ------------------------------------------------------------ rules */
describe("rules", () => {
  test("before: exactly N days before the due date", () => {
    const s = S({ timing: "before", before_days: 3 });
    assert.equal(reminderDue(s, "2026-10-15", "2026-10-12"), "before");
    assert.equal(reminderDue(s, "2026-10-14", "2026-10-12"), null);
    assert.equal(reminderDue(s, "2026-10-11", "2026-10-12"), null); // after: not chosen
  });

  test("after: N days after, then every repeat_days; both = either", () => {
    const once = S({ timing: "after", after_days: 2 });
    assert.equal(reminderDue(once, "2026-10-10", "2026-10-12"), "after");
    assert.equal(reminderDue(once, "2026-10-03", "2026-10-12"), null);
    const rep = S({ timing: "after", after_days: 2, repeat_days: 7 });
    assert.equal(reminderDue(rep, "2026-10-01", "2026-10-12"), null); // 11 days
    assert.equal(reminderDue(rep, "2026-10-03", "2026-10-12"), "after"); // 9 = 2 + 7
    assert.equal(reminderDue(rep, "2026-09-26", "2026-10-12"), "after"); // 16 = 2 + 14
    const both = S({ timing: "both", before_days: 3, after_days: 1 });
    assert.equal(reminderDue(both, "2026-10-15", "2026-10-12"), "before");
    assert.equal(reminderDue(both, "2026-10-11", "2026-10-12"), "after");
    assert.equal(reminderDue(both, null, "2026-10-12"), null);
  });

  test("validation and stored rows", () => {
    assert.deepEqual(validateSettings({ mode: "automatic", timing: "both", before_days: 5, after_days: 2, repeat_days: 7, send_hour: 9 }).value, {
      mode: "automatic", timing: "both", before_days: 5, after_days: 2, repeat_days: 7, send_hour: 9,
    });
    assert.equal(validateSettings({ ...DEFAULT_SETTINGS, mode: "sometimes" }).ok, false);
    assert.equal(validateSettings({ ...DEFAULT_SETTINGS, timing: "never" }).ok, false);
    assert.equal(validateSettings({ ...DEFAULT_SETTINGS, before_days: 0 }).ok, false);
    assert.equal(validateSettings({ ...DEFAULT_SETTINGS, after_days: 91 }).ok, false);
    assert.equal(validateSettings({ ...DEFAULT_SETTINGS, send_hour: 24 }).ok, false);
    assert.equal(validateSettings({ ...DEFAULT_SETTINGS, repeat_days: 31 }).ok, false);
    assert.deepEqual(settingsOf(null), DEFAULT_SETTINGS);
    assert.equal(DEFAULT_SETTINGS.mode, "manual"); // nothing automatic until the admin says so
  });

  test("India time and the once-a-day key", () => {
    assert.deepEqual(istNow(new Date("2026-10-12T04:40:00Z")), { today: "2026-10-12", hour: 10 });
    assert.deepEqual(istNow(new Date("2026-10-11T19:00:00Z")), { today: "2026-10-12", hour: 0 });
    const k = autoKey("CO-1", "L1", "x".repeat(32), "2026-10-12");
    assert.match(k, /^auto:2026-10-12:[0-9a-f]{32}$/);
    assert.ok(k.length <= 80);
    assert.notEqual(k, autoKey("CO-1", "L2", "x".repeat(32), "2026-10-12"));
  });
});

/* ---------------------------------------------------------- fake db */
class FakeDb {
  constructor({ table = true } = {}) {
    this.table = table;
    this.settings = [];
    this.ledgers = [
      { admin_id: 7, company_guid: "CO-1", ledger_guid: "L1", name: "Mehta Electricals", email: "accounts@mehta.in" },
      { admin_id: 7, company_guid: "CO-1", ledger_guid: "L2", name: "No Mail Ltd", email: "" },
      { admin_id: 7, company_guid: "CO-1", ledger_guid: "L3", name: "Patel Stores", email: "p@patel.in" },
    ];
    const b = (ledger_guid, ledger_name, bill_name, pending_amount, due_date, extra = {}) => ({
      admin_id: 7, company_guid: "CO-1", ledger_guid, ledger_name, bill_name, pending_amount,
      due_date, bill_date: "2026-09-01", bill_type: "RECEIVABLE", ...extra,
    });
    // Today (India time) is 2026-10-12.
    this.bills = [
      b("L1", "Mehta Electricals", "INV-1", "1000", "2026-10-15"), // due in 3 days
      b("L1", "Mehta Electricals", "INV-2", "500", "2026-10-11"), // 1 day overdue
      b("L1", "Mehta Electricals", "INV-3", "0", "2026-10-15"), // settled
      b("L1", "Mehta Electricals", "PUR-1", "700", "2026-10-15", { bill_type: "PAYABLE" }),
      b("L2", "No Mail Ltd", "INV-7", "100", "2026-10-15"), // no email
      b(null, "Patel Stores", "INV-9", "300", "2026-10-15"), // synced before its ledger guid
      b("L3", "Patel Stores", "INV-10", "50", "2026-11-30"), // not due for one
    ];
    this.perms = [{ user_id: 21, ledger_guid: "L1" }];
    this.logs = [];
    this.nextId = 1;
  }

  async query(sql, params = []) {
    const s = sql.replace(/\s+/g, " ").trim();
    const p = params;
    const missing = () => {
      throw Object.assign(new Error('relation "reminder_settings" does not exist'), { code: "42P01" });
    };
    if (s.includes("FROM active_company ac")) return { rows: [{ company_guid: "CO-1", company_name: "Ravi Traders" }] };
    if (s.includes("FROM reminder_settings rs")) {
      if (!this.table) missing();
      return {
        rows: this.settings
          .filter((x) => x.mode === "automatic" && x.send_hour === p[0])
          .map((x) => ({ ...x, company_name: "Ravi Traders" })),
      };
    }
    if (s.includes("FROM reminder_settings WHERE admin_id = $1 AND company_guid = $2")) {
      if (!this.table) missing();
      return { rows: this.settings.filter((x) => x.admin_id === p[0] && x.company_guid === p[1]) };
    }
    if (s.startsWith("INSERT INTO reminder_settings")) {
      if (!this.table) missing();
      const row = {
        admin_id: p[0], company_guid: p[1], mode: p[2], timing: p[3], before_days: p[4],
        after_days: p[5], repeat_days: p[6], send_hour: p[7], updated_by: p[8],
      };
      this.settings = this.settings.filter((x) => !(x.admin_id === p[0] && x.company_guid === p[1]));
      this.settings.push(row);
      return { rows: [] };
    }
    if (s.includes("FROM bills b JOIN ledgers l")) {
      const rows = [];
      for (const b of this.bills) {
        if (b.admin_id !== p[0] || b.company_guid !== p[1]) continue;
        if (!(Number(b.pending_amount) > 0) || !b.due_date || b.bill_type === "PAYABLE") continue;
        const l = this.ledgers.find(
          (x) => x.admin_id === b.admin_id && x.company_guid === b.company_guid &&
            (x.ledger_guid === b.ledger_guid || (b.ledger_guid === null && x.name === b.ledger_name))
        );
        if (!l) continue;
        if (s.includes("user_ledger_permissions") && !this.perms.some((x) => x.user_id === p[2] && x.ledger_guid === l.ledger_guid)) continue;
        rows.push({ ...b, ledger_guid: l.ledger_guid, party: l.name, email: l.email });
      }
      return { rows };
    }
    if (s.includes("FROM reminder_templates")) return { rows: [] };
    if (s.startsWith("SELECT COUNT(*)::int AS day FROM reminder_log")) {
      return { rows: [{ day: this.logs.filter((r) => r.admin_id === p[0]).length }] };
    }
    if (s.startsWith("INSERT INTO reminder_log")) {
      assert.match(s, /ON CONFLICT \(admin_id, idempotency_key\) DO NOTHING/);
      if (this.logs.some((r) => r.admin_id === p[0] && r.idempotency_key === p[10])) return { rows: [] };
      const row = {
        id: this.nextId++, admin_id: p[0], company_guid: p[1], ledger_guid: p[2], ledger_name: p[3],
        template_id: p[4], bill_set: p[5], bills: JSON.parse(p[6]), total_amount: String(p[7]),
        recipients: JSON.parse(p[8]), subject: p[9], status: "pending", idempotency_key: p[10],
        sent_by_user_id: p[11], sent_by_name: "Automatic reminder", attempts: 0,
      };
      this.logs.push(row);
      return { rows: [{ ...row }] };
    }
    if (s.startsWith("UPDATE reminder_log SET status = 'accepted'")) {
      const r = this.logs.find((x) => x.id === p[0]);
      r.status = "accepted";
      return { rows: [{ ...r }] };
    }
    if (s.startsWith("UPDATE reminder_log SET status = 'failed'")) {
      const r = this.logs.find((x) => x.id === p[0]);
      Object.assign(r, { status: "failed", error: p[1] });
      return { rows: [{ ...r }] };
    }
    throw new Error(`FakeDb: unhandled SQL ${s}`);
  }
}

const MAIL_ENV = {
  MICROSOFT_TENANT_ID: "t",
  MICROSOFT_CLIENT_ID: "c",
  MICROSOFT_CLIENT_SECRET: "s",
  MICROSOFT_SENDER_EMAIL: "no-reply@tally-connect.com",
};
const ADMIN = { id: 7, adminId: 7, role: "ADMIN", username: "Ravi", email: "ravi@x.in" };
const USER = { id: 21, adminId: 7, role: "USER", username: "Asha", email: "asha@x.in" };
const stubAuth = (req, res, next) => {
  const u = req.headers["x-test-user"];
  if (!u) return res.status(401).json({ message: "Unauthorized" });
  req.user = JSON.parse(u);
  next();
};

describe("routes and the automatic run", () => {
  let db, sent, server, base, router, clock;
  const quiet = { error: () => {} };

  async function start(opts, env = MAIL_ENV) {
    db = new FakeDb(opts);
    sent = [];
    // 2026-10-12 10:05 India time.
    clock = new Date("2026-10-12T04:35:00Z");
    router = createReminderRouter({
      db,
      auth: stubAuth,
      env,
      log: quiet,
      now: () => clock,
      sendEmail: async (m) => {
        sent.push(m);
        return { provider: "microsoft-graph", status: 202, requestId: "r" };
      },
    });
    const app = express();
    app.use(express.json());
    app.use(router);
    await new Promise((resolve) => {
      server = app.listen(0, resolve);
    });
    base = `http://127.0.0.1:${server.address().port}`;
  }
  afterEach(() => new Promise((resolve) => server.close(resolve)));

  const call = async (method, path, user, body) => {
    const r = await fetch(base + path, {
      method,
      headers: { "content-type": "application/json", ...(user ? { "x-test-user": JSON.stringify(user) } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    return { status: r.status, body: await r.json() };
  };

  describe("with the table", () => {
    beforeEach(() => start());

    test("settings: defaults, only the admin changes them, everyone reads them", async () => {
      let r = await call("GET", "/api/reminders/settings", USER);
      assert.equal(r.status, 200);
      assert.deepEqual(r.body.data, DEFAULT_SETTINGS);
      assert.equal(r.body.stored, false);
      assert.equal(r.body.can_edit, false);
      const want = { mode: "automatic", timing: "both", before_days: 3, after_days: 1, repeat_days: 0, send_hour: 10 };
      assert.equal((await call("PUT", "/api/reminders/settings", USER, want)).status, 403);
      assert.equal((await call("PUT", "/api/reminders/settings", ADMIN, { ...want, send_hour: 30 })).status, 400);
      r = await call("PUT", "/api/reminders/settings", ADMIN, want);
      assert.equal(r.status, 200);
      r = await call("GET", "/api/reminders/settings", USER);
      assert.deepEqual(r.body.data, want);
      assert.equal(r.body.stored, true);
      assert.equal((await call("GET", "/api/reminders/settings", null)).status, 401);
    });

    test("due today: by the settings, one line per party, USER sees only allowed parties", async () => {
      await call("PUT", "/api/reminders/settings", ADMIN, { mode: "manual", timing: "both", before_days: 3, after_days: 1, repeat_days: 0, send_hour: 10 });
      let r = await call("GET", "/api/reminders/due", ADMIN);
      assert.equal(r.body.today, "2026-10-12");
      const by = Object.fromEntries(r.body.data.map((g) => [g.party, g]));
      assert.deepEqual(Object.keys(by).sort(), ["Mehta Electricals", "No Mail Ltd", "Patel Stores"]);
      assert.deepEqual(by["Mehta Electricals"].bills.map((b) => b.bill_name), ["INV-1", "INV-2"]);
      assert.equal(by["Mehta Electricals"].reason, "both");
      assert.equal(by["Mehta Electricals"].total, 1500);
      assert.deepEqual(by["No Mail Ltd"].emails, []);
      assert.equal(by["Patel Stores"].ledger_guid, "L3"); // bill without guid, matched by name
      r = await call("GET", "/api/reminders/due", USER);
      assert.deepEqual(r.body.data.map((g) => g.party), ["Mehta Electricals"]);
    });

    test("automatic: emails each due party with an email, once a day, at the set hour only", async () => {
      await call("PUT", "/api/reminders/settings", ADMIN, { mode: "automatic", timing: "before", before_days: 3, after_days: 1, repeat_days: 0, send_hour: 10 });
      let out = await router.runAutomatic();
      assert.deepEqual(out, { companies: 1, sent: 2, failed: 0, skipped_no_email: 1, skipped_done: 0, skipped_limit: 0 });
      assert.deepEqual(sent.map((m) => m.to[0]).sort(), ["accounts@mehta.in", "p@patel.in"]);
      assert.equal(db.logs.every((l) => l.sent_by_name === "Automatic reminder" && l.status === "accepted"), true);
      assert.deepEqual(db.logs.find((l) => l.ledger_guid === "L1").bills.map((b) => b.bill_name), ["INV-1"]);
      // Again the same hour (the cron runs hourly; a restart): nothing new.
      out = await router.runAutomatic();
      assert.equal(out.sent, 0);
      assert.equal(out.skipped_done, 2);
      assert.equal(sent.length, 2);
      // Another hour: not this company's time.
      clock = new Date("2026-10-12T06:35:00Z");
      out = await router.runAutomatic();
      assert.equal(out.companies, 0);
    });

    test("manual: the run sends nothing", async () => {
      await call("PUT", "/api/reminders/settings", ADMIN, { mode: "manual", timing: "before", before_days: 3, after_days: 1, repeat_days: 0, send_hour: 10 });
      const out = await router.runAutomatic();
      assert.equal(out.companies, 0);
      assert.equal(sent.length, 0);
    });
  });

  test("before the SQL: defaults shown, saving explains, the run does nothing", async () => {
    await start({ table: false });
    let r = await call("GET", "/api/reminders/settings", ADMIN);
    assert.equal(r.status, 200);
    assert.equal(r.body.ready, false);
    assert.deepEqual(r.body.data, DEFAULT_SETTINGS);
    r = await call("PUT", "/api/reminders/settings", ADMIN, DEFAULT_SETTINGS);
    assert.equal(r.status, 503);
    assert.equal(r.body.code, "not_ready");
    assert.deepEqual(await router.runAutomatic(), { companies: 0, sent: 0, failed: 0, skipped_no_email: 0, skipped_done: 0, skipped_limit: 0 });
  });

  test("email not configured: automatic run sends nothing", async () => {
    await start({}, {});
    db.settings.push({ admin_id: 7, company_guid: "CO-1", mode: "automatic", timing: "before", before_days: 3, after_days: 1, repeat_days: 0, send_hour: 10 });
    const out = await router.runAutomatic();
    assert.equal(out.sent, 0);
    assert.equal(sent.length, 0);
  });
});
