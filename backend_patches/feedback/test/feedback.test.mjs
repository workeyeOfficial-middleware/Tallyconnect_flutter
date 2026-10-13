// Tests for the feedback API (node --test). No database or network: an
// in-memory fake pg pool, a fake mailer and a stub login middleware.
// Needs only `express` installed next to the files.
import { test, describe, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import express from "express";

import {
  buildFeedbackEmail,
  escapeHtml,
  feedbackConfig,
  isFeedbackAdmin,
  validateAdminUpdate,
  validateFeedback,
} from "../utils/feedbackCore.js";
import { createFeedbackRouter } from "../utils/feedbackRouter.js";

/* ------------------------------------------------------------ core */
describe("validateFeedback", () => {
  test("accepts a normal feedback and cleans the text", () => {
    const v = validateFeedback({ type: "feedback", rating: 4, message: "  Great\r\napp\u0007 " });
    assert.equal(v.ok, true);
    assert.deepEqual(v.value, {
      type: "feedback",
      rating: 4,
      message: "Great\napp",
      appVersion: null,
      platform: null,
    });
  });

  test("rejects bad type, empty / long message, bad rating", () => {
    assert.equal(validateFeedback({ type: "spam", message: "x" }).ok, false);
    assert.equal(validateFeedback({ type: "bug", message: "   " }).ok, false);
    assert.equal(validateFeedback({ type: "bug", message: "x".repeat(1001) }).ok, false);
    assert.equal(validateFeedback({ type: "idea", message: "x", rating: 6 }).ok, false);
    assert.equal(validateFeedback({ type: "idea", message: "x", rating: 2.5 }).ok, false);
    assert.equal(validateFeedback({ type: "idea", message: "x", app_version: "<b>" }).ok, false);
    assert.equal(validateFeedback(null).ok, false);
    assert.equal(validateFeedback([]).ok, false);
  });

  test("bug reports never carry a rating; 1000 characters allowed", () => {
    const v = validateFeedback({ type: "bug", message: "x".repeat(1000), rating: 3 });
    assert.equal(v.ok, true);
    assert.equal(v.value.rating, null);
  });
});

describe("config, admin check, admin update", () => {
  test("reads emails and limits from the environment", () => {
    const c = feedbackConfig({
      FEEDBACK_NOTIFICATION_EMAIL: "wokk2720022@gmail.com",
      FEEDBACK_ADMIN_EMAILS: " Team@Tally-Connect.com , bad-email, ops@x.in",
      FEEDBACK_RATE_LIMIT_PER_HOUR: "3",
      FEEDBACK_RATE_LIMIT_PER_DAY: "nope",
    });
    assert.equal(c.notifyEmail, "wokk2720022@gmail.com");
    assert.deepEqual(c.adminEmails, ["team@tally-connect.com", "ops@x.in"]);
    assert.equal(c.perHour, 3);
    assert.equal(c.perDay, 20);
    assert.equal(feedbackConfig({}).notifyEmail, null);
    assert.equal(isFeedbackAdmin({ email: "OPS@x.in" }, c), true);
    assert.equal(isFeedbackAdmin({ email: "customer@x.in" }, c), false);
    assert.equal(isFeedbackAdmin({}, feedbackConfig({})), false); // closed by default
  });

  test("admin update validation", () => {
    assert.equal(validateAdminUpdate({ status: "done" }).ok, false);
    assert.equal(validateAdminUpdate({}).ok, false);
    assert.deepEqual(validateAdminUpdate({ status: "resolved", admin_note: " fixed " }).value, {
      status: "resolved",
      adminNote: "fixed",
    });
  });
});

describe("notification email", () => {
  test("customer text is escaped; subject is one line", () => {
    assert.equal(escapeHtml(`<a href="x">'&`), "&lt;a href=&quot;x&quot;&gt;&#39;&amp;");
    const m = buildFeedbackEmail({
      id: 9,
      user_id: 7,
      user_email: "ravi@x.in\r\nBcc: evil@x.in",
      type: "bug",
      rating: null,
      message: "<script>alert(1)</script>",
      created_at: "2026-10-12T05:00:00Z",
    });
    assert.ok(!m.subject.includes("\n") && !m.subject.includes("\r"));
    assert.ok(m.subject.startsWith("[TallyConnect] Bug report #9"));
    assert.ok(!m.html.includes("<script>"));
    assert.ok(m.html.includes("&lt;script&gt;"));
  });
});

describe("mailer", () => {
  test("missing Microsoft settings → error (never a silent success)", async () => {
    const { sendFeedbackEmail } = await import("../utils/sendFeedbackEmail.js");
    const keys = ["MICROSOFT_TENANT_ID", "MICROSOFT_CLIENT_ID", "MICROSOFT_CLIENT_SECRET", "MICROSOFT_SENDER_EMAIL"];
    const saved = Object.fromEntries(keys.map((k) => [k, process.env[k]]));
    try {
      for (const k of keys) delete process.env[k];
      await assert.rejects(sendFeedbackEmail({ to: "a@x.in", subject: "s", html: "h" }), /MICROSOFT_SENDER_EMAIL/);
      process.env.MICROSOFT_SENDER_EMAIL = "no-reply@x.in";
      await assert.rejects(sendFeedbackEmail({ to: "a@x.in", subject: "s", html: "h" }), /not configured/);
    } finally {
      for (const k of keys) {
        if (saved[k] === undefined) delete process.env[k];
        else process.env[k] = saved[k];
      }
    }
  });
});

/* ---------------------------------------------------------- routes */
class FakeDb {
  constructor() {
    this.rows = [];
    this.nextId = 1;
    this.failInsert = false;
  }
  async query(sql, params = []) {
    const s = sql.replace(/\s+/g, " ");
    if (s.includes("COUNT(*) FILTER")) {
      const now = Date.now();
      const mine = this.rows.filter((r) => r.user_id === params[0]);
      return {
        rows: [
          {
            hour: mine.filter((r) => now - r.created_at.getTime() < 3600e3).length,
            day: mine.filter((r) => now - r.created_at.getTime() < 86400e3).length,
          },
        ],
      };
    }
    if (s.includes("FROM active_company")) return { rows: [{ company_guid: "CO-1" }] };
    if (s.startsWith("INSERT INTO feedback")) {
      if (this.failInsert) throw new Error("db down");
      const [user_id, admin_id, user_email, username, role, company_guid, type, rating, message,
        app_version, platform, user_agent] = params;
      const row = {
        id: this.nextId++, user_id, admin_id, user_email, username, role, company_guid, type,
        rating, message, app_version, platform, user_agent, status: "new", admin_note: null,
        reviewed_by: null, reviewed_at: null, email_status: "pending", email_error: null,
        email_attempts: 0, emailed_at: null, created_at: new Date(), updated_at: new Date(),
      };
      this.rows.push(row);
      return { rows: [{ ...row }] };
    }
    const byId = (id) => this.rows.find((r) => r.id === id);
    if (s.includes("SET email_status = 'sent'")) {
      Object.assign(byId(params[0]), { email_status: "sent", email_error: null, emailed_at: new Date() });
      byId(params[0]).email_attempts++;
      return { rows: [] };
    }
    if (s.includes("SET email_status = 'failed'")) {
      Object.assign(byId(params[0]), { email_status: "failed", email_error: params[1] });
      byId(params[0]).email_attempts++;
      return { rows: [] };
    }
    if (s.includes("SET email_status = 'skipped'")) {
      Object.assign(byId(params[0]), { email_status: "skipped" });
      return { rows: [] };
    }
    if (s.startsWith("UPDATE feedback SET")) {
      const r = byId(params[0]);
      if (!r) return { rows: [] };
      let i = 1;
      if (s.includes("status = $")) r.status = params[i++];
      if (s.includes("admin_note = $")) r.admin_note = params[i++];
      r.reviewed_by = params[i];
      return { rows: [{ ...r }] };
    }
    if (s.includes("FROM feedback WHERE id = $1")) {
      const r = byId(params[0]);
      return { rows: r ? [{ ...r }] : [] };
    }
    const filtered = this.rows.filter((r) => !s.includes("status = $1") || r.status === params[0]);
    if (s.includes("COUNT(*)::int AS n")) return { rows: [{ n: filtered.length }] };
    if (s.includes("ORDER BY created_at DESC")) {
      return { rows: [...filtered].reverse().map((r) => ({ ...r })) };
    }
    throw new Error(`FakeDb: unhandled SQL ${s}`);
  }
}

// Stub login: the test says who is signed in with a header.
const stubAuth = (req, res, next) => {
  const u = req.headers["x-test-user"];
  if (!u) return res.status(401).json({ message: "Unauthorized" });
  req.user = JSON.parse(u);
  next();
};

const CUSTOMER = { id: 7, adminId: 7, role: "ADMIN", username: "ravi", email: "ravi@x.in" };
const TEAM = { id: 1, adminId: 1, role: "ADMIN", username: "ops", email: "ops@tally-connect.com" };

describe("routes", () => {
  let db, sent, server, base, mailFails, env;
  const quiet = { error: () => {} };

  beforeEach(async () => {
    db = new FakeDb();
    sent = [];
    mailFails = false;
    env = {
      FEEDBACK_NOTIFICATION_EMAIL: "wokk2720022@gmail.com",
      FEEDBACK_ADMIN_EMAILS: "ops@tally-connect.com",
      FEEDBACK_RATE_LIMIT_PER_HOUR: "3",
    };
    const app = express();
    app.use(express.json());
    app.use(
      createFeedbackRouter({
        db,
        auth: stubAuth,
        env,
        log: quiet,
        sendEmail: async (m) => {
          if (mailFails) throw new Error("smtp down");
          sent.push(m);
          return { status: 202, requestId: "req-1" };
        },
      })
    );
    await new Promise((resolve) => {
      server = app.listen(0, resolve);
    });
    base = `http://127.0.0.1:${server.address().port}`;
  });
  afterEach(() => new Promise((resolve) => server.close(resolve)));

  const call = (method, path, user, body) =>
    fetch(base + path, {
      method,
      headers: {
        "content-type": "application/json",
        ...(user ? { "x-test-user": JSON.stringify(user) } : {}),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  const settle = () => new Promise((r) => setTimeout(r, 30));

  test("needs a login", async () => {
    const r = await call("POST", "/api/feedback", null, { type: "idea", message: "x" });
    assert.equal(r.status, 401);
  });

  test("stores, then emails the configured address; identity from the login", async () => {
    const r = await call("POST", "/api/feedback", CUSTOMER, {
      type: "feedback",
      rating: 5,
      message: "Love it",
      user_id: 999, // ignored
      user_email: "someone@else.com", // ignored
    });
    assert.equal(r.status, 201);
    const j = await r.json();
    assert.equal(j.success, true);
    assert.equal(j.email_status, "sent"); // answered after the email was accepted
    const row = db.rows[0];
    assert.equal(row.id, j.id);
    assert.equal(row.user_id, 7);
    assert.equal(row.user_email, "ravi@x.in");
    assert.equal(row.company_guid, "CO-1");
    assert.equal(row.email_status, "sent");
    assert.equal(sent.length, 1);
    assert.equal(sent[0].to, "wokk2720022@gmail.com");
    assert.equal(sent[0].replyTo, "ravi@x.in");
  });

  test("email failure: never reported as success; feedback kept and re-sendable", async () => {
    mailFails = true;
    const r = await call("POST", "/api/feedback", CUSTOMER, { type: "bug", message: "Crash" });
    assert.equal(r.status, 502);
    const j = await r.json();
    assert.equal(j.success, false);
    assert.equal(j.stored, true);
    assert.equal(j.email_status, "failed");
    assert.equal(j.code, "email_failed");
    assert.match(j.message, /saved \(#1\)/);
    assert.ok(!j.message.includes("smtp down")); // provider details stay server-side
    assert.equal(db.rows.length, 1);
    assert.equal(db.rows[0].email_status, "failed");
    assert.match(db.rows[0].email_error, /smtp down/);
    mailFails = false;
    const rs = await call("POST", `/api/admin/feedback/${db.rows[0].id}/resend-email`, TEAM);
    assert.equal(rs.status, 200);
    assert.equal((await rs.json()).email_status, "sent");
    assert.equal(db.rows[0].email_status, "sent");
    assert.equal(db.rows[0].email_attempts, 2);
  });

  test("no / invalid notification address → stored, 503, not a success", async () => {
    for (const value of [undefined, "work272002@gmail", "  "]) {
      if (value === undefined) delete env.FEEDBACK_NOTIFICATION_EMAIL;
      else env.FEEDBACK_NOTIFICATION_EMAIL = value;
      const r = await call("POST", "/api/feedback", CUSTOMER, { type: "idea", message: "x" });
      assert.equal(r.status, 503);
      const j = await r.json();
      assert.equal(j.success, false);
      assert.equal(j.code, "email_not_configured");
      assert.equal(db.rows.at(-1).email_status, "skipped");
    }
    assert.equal(sent.length, 0);
  });

  test("team: email settings check shows presence only, never secrets", async () => {
    env.MICROSOFT_TENANT_ID = "tenant-x";
    env.MICROSOFT_CLIENT_SECRET = "super-secret-value";
    assert.equal((await call("GET", "/api/admin/feedback/email-config", CUSTOMER)).status, 403);
    const r = await call("GET", "/api/admin/feedback/email-config", TEAM);
    assert.equal(r.status, 200);
    const text = await r.text();
    assert.ok(!text.includes("super-secret-value") && !text.includes("tenant-x"));
    const j = JSON.parse(text);
    assert.equal(j.notify_email, "wokk2720022@gmail.com");
    assert.deepEqual(j.graph, {
      MICROSOFT_TENANT_ID: true,
      MICROSOFT_CLIENT_ID: false,
      MICROSOFT_CLIENT_SECRET: true,
      MICROSOFT_SENDER_EMAIL: false,
    });
  });

  test("validation errors are 400 and store nothing", async () => {
    const r = await call("POST", "/api/feedback", CUSTOMER, { type: "idea", message: "" });
    assert.equal(r.status, 400);
    assert.equal(db.rows.length, 0);
  });

  test("rate limited per user (429)", async () => {
    for (let i = 0; i < 3; i++) {
      const ok = await call("POST", "/api/feedback", CUSTOMER, { type: "idea", message: `m${i}` });
      assert.equal(ok.status, 201);
    }
    const r = await call("POST", "/api/feedback", CUSTOMER, { type: "idea", message: "m4" });
    assert.equal(r.status, 429);
    assert.equal(r.headers.get("retry-after"), "3600");
    // Another user is not limited by this one.
    const other = await call("POST", "/api/feedback", { ...CUSTOMER, id: 8 }, {
      type: "idea",
      message: "x",
    });
    assert.equal(other.status, 201);
  });

  test("database error → 500, nothing emailed", async () => {
    db.failInsert = true;
    const r = await call("POST", "/api/feedback", CUSTOMER, { type: "idea", message: "x" });
    assert.equal(r.status, 500);
    await settle();
    assert.equal(sent.length, 0);
  });

  test("review is only for allow-listed team emails", async () => {
    await call("POST", "/api/feedback", CUSTOMER, { type: "idea", message: "x" });
    assert.equal((await call("GET", "/api/admin/feedback", CUSTOMER)).status, 403);
    assert.equal((await call("GET", "/api/admin/feedback", null)).status, 401);
    env.FEEDBACK_ADMIN_EMAILS = ""; // closed when not configured
    assert.equal((await call("GET", "/api/admin/feedback", TEAM)).status, 403);
  });

  test("team: list, filter, open, update", async () => {
    await call("POST", "/api/feedback", CUSTOMER, { type: "idea", message: "first" });
    await call("POST", "/api/feedback", CUSTOMER, { type: "bug", message: "second" });
    const list = await (await call("GET", "/api/admin/feedback?limit=10", TEAM)).json();
    assert.equal(list.meta.total, 2);
    assert.equal(list.data[0].message, "second");
    assert.equal((await call("GET", "/api/admin/feedback?status=bogus", TEAM)).status, 400);
    const one = await (await call("GET", "/api/admin/feedback/1", TEAM)).json();
    assert.equal(one.data.message, "first");
    assert.equal((await call("GET", "/api/admin/feedback/999", TEAM)).status, 404);
    const up = await call("PATCH", "/api/admin/feedback/1", TEAM, {
      status: "resolved",
      admin_note: "Shipped in 1.1",
    });
    assert.equal(up.status, 200);
    const d = (await up.json()).data;
    assert.equal(d.status, "resolved");
    assert.equal(d.admin_note, "Shipped in 1.1");
    assert.equal(d.reviewed_by, "ops@tally-connect.com");
    const open = await (await call("GET", "/api/admin/feedback?status=new", TEAM)).json();
    assert.equal(open.meta.total, 1);
    assert.equal(
      (await call("PATCH", "/api/admin/feedback/1", TEAM, { status: "done" })).status,
      400
    );
  });
});
