// Tests for the AI assistant API (node --test). No database, no network:
// an in-memory fake pg pool, a scripted fake Gemini and a stub login.
// Needs only `express` installed next to the files.
import { test, describe, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import express from "express";

import { OFF_TOPIC_REPLY, geminiFailure, rankModels, readKey, validateAsk } from "../utils/assistantCore.js";
import { createAssistantRouter } from "../utils/assistantRouter.js";
import { createAdapters } from "../utils/aiProviders.js";
import { GeminiHttpError } from "../utils/geminiClient.js";

const KEY = "AIzaSyTESTKEY_abcdefghijklmnop123456";

/* ------------------------------------------------------------ core */
describe("core", () => {
  test("key: from the header only, format checked, never echoed", () => {
    assert.equal(readKey({ "x-gemini-key": ` ${KEY} ` }), KEY);
    assert.throws(() => readKey({}), (e) => e.code === "no_key" && e.http === 400);
    assert.throws(() => readKey({ "x-gemini-key": "short" }), (e) => e.code === "invalid_key" && !e.message.includes("short"));
    assert.throws(() => readKey({ "x-gemini-key": `${KEY}\nX: y` }), (e) => e.code === "invalid_key");
    // Newer key format with a dot.
    const aq = "AQ.Ab8RTESTKEYabcdefghijklmnopqrstuv_wxyz-12";
    assert.equal(readKey({ "x-gemini-key": aq }), aq);
  });

  test("suspended key / disabled API → clear messages (422, not 401)", () => {
    const sus = geminiFailure(403, {
      error: {
        message: "Permission denied: Consumer 'api_key:AQ.x' has been suspended.",
        details: [{ reason: "CONSUMER_SUSPENDED" }],
      },
    });
    assert.deepEqual([sus.code, sus.http], ["key_suspended", 422]);
    assert.match(sus.message, /suspended/);
    assert.ok(!sus.message.includes("AQ.x"));
    const off = geminiFailure(403, { error: { message: "x", details: [{ reason: "SERVICE_DISABLED" }] } });
    assert.equal(off.code, "api_disabled");
  });

  test("question / history validation", () => {
    assert.equal(validateAsk({ question: "" }).ok, false);
    assert.equal(validateAsk({ question: "x".repeat(1001) }).ok, false);
    assert.equal(validateAsk({ question: "q", history: [{ role: "system", text: "x" }] }).ok, false);
    const v = validateAsk({
      question: " Who owes me most? ",
      history: Array.from({ length: 14 }, (_, i) => ({ role: i % 2 ? "model" : "user", text: `t${i}` })),
    });
    assert.equal(v.value.question, "Who owes me most?");
    assert.equal(v.value.history.length, 10); // only the last 10 turns
  });

  test("model ranking: current text models, latest alias, stable Flash first", () => {
    const m = (name, gen = true) => ({ name: `models/${name}`, supportedGenerationMethods: gen ? ["generateContent"] : ["embedContent"] });
    assert.deepEqual(
      rankModels([
        m("gemini-2.0-flash"),
        m("gemini-2.5-pro"),
        m("gemini-2.5-flash"),
        m("gemini-3.0-flash-preview"),
        m("gemini-2.5-flash-lite"),
        m("gemini-2.5-flash-image"),
        m("gemini-2.5-flash-preview-tts"),
        m("text-embedding-004", false),
        m("gemma-3-27b-it"),
      ]),
      // Flash-Lite before Pro: Pro's free quota is much smaller.
      ["gemini-2.5-flash", "gemini-2.5-flash-lite", "gemini-2.5-pro", "gemini-2.0-flash", "gemini-3.0-flash-preview"]
    );
    assert.equal(rankModels([m("gemini-2.5-flash"), m("gemini-flash-latest")])[0], "gemini-flash-latest");
    assert.deepEqual(rankModels(undefined), []);
  });

  test("Gemini errors → never 401 (that would sign the user out)", () => {
    const bad = geminiFailure(400, { error: { message: "API key not valid. Please pass a valid API key.", details: [{ reason: "API_KEY_INVALID" }] } });
    assert.deepEqual([bad.code, bad.http], ["invalid_key", 422]);
    assert.deepEqual([geminiFailure(403, {}).code, geminiFailure(403, {}).http], ["key_forbidden", 422]);
    assert.deepEqual([geminiFailure(429, {}).code, geminiFailure(429, {}).http], ["quota", 429]);
    assert.equal(geminiFailure(500, {}).http, 502);
    assert.equal(geminiFailure(404, {}).code, "model_unavailable");
  });
});

/* ------------------------------------------------------- fake data */
class FakeDb {
  constructor() {
    this.active = { 7: "CO-1", 8: "CO-9" };
    this.companies = [
      { admin_id: 7, company_guid: "CO-1", name: "Ravi Traders" },
      { admin_id: 8, company_guid: "CO-9", name: "Other Account" },
    ];
    this.ledgers = [
      { admin_id: 7, company_guid: "CO-1", ledger_guid: "L1", name: "Mehta Electricals", parent_group: "Sundry Debtors", opening_balance: "0", closing_balance: "-15000.50" },
      { admin_id: 7, company_guid: "CO-1", ledger_guid: "L2", name: "Gupta Stores", parent_group: "Sundry Debtors", opening_balance: "0", closing_balance: "-4000" },
      { admin_id: 7, company_guid: "CO-1", ledger_guid: "L3", name: "Polycab Wires", parent_group: "Sundry Creditors", opening_balance: "0", closing_balance: "9000" },
      { admin_id: 7, company_guid: "CO-2", ledger_guid: "L5", name: "Mehta Exports", parent_group: "Sundry Debtors", opening_balance: "0", closing_balance: "-77777" },
      { admin_id: 8, company_guid: "CO-9", ledger_guid: "L9", name: "Mehta Secret", parent_group: "Sundry Debtors", opening_balance: "0", closing_balance: "-88888" },
    ];
    this.perms = [{ user_id: 21, ledger_guid: "L2" }];
    this.allowedVouchers = { 21: ["V2"] };
    const b = (admin_id, company_guid, ledger_guid, ledger_name, bill_name, pending_amount, due_date, bill_type = "RECEIVABLE") => ({
      admin_id, company_guid, ledger_guid, ledger_name, bill_name, pending_amount, due_date, bill_date: "2026-09-01", bill_type,
    });
    this.bills = [
      b(7, "CO-1", "L1", "Mehta Electricals", "S/101", "10000.50", "2026-09-20"),
      b(7, "CO-1", "L1", "Mehta Electricals", "S/102", "5000", "2026-10-30"),
      b(7, "CO-1", "L2", "Gupta Stores", "S/201", "4000", "2026-09-01"),
      b(7, "CO-1", "L3", "Polycab Wires", "P/9", "9000", "2026-08-19", "PAYABLE"),
      b(7, "CO-2", "L5", "Mehta Exports", "X/1", "77777", "2026-09-01"),
      b(8, "CO-9", "L9", "Mehta Secret", "Z/1", "88888", "2026-09-01"),
    ];
    const v = (admin_id, company_guid, voucher_guid, voucher_type, voucher_date, party_name, net_amount) => ({
      admin_id, company_guid, voucher_guid, voucher_type, voucher_date, party_name, net_amount, reference_no: voucher_guid,
    });
    this.vouchers = [
      v(7, "CO-1", "V1", "Sales", "2026-09-05", "Mehta Electricals", "12000"),
      v(7, "CO-1", "V2", "Sales", "2026-10-02", "Gupta Stores", "4000"),
      v(7, "CO-1", "V3", "Receipt", "2026-10-03", "Mehta Electricals", "2000"),
      v(7, "CO-2", "V5", "Sales", "2026-10-01", "Mehta Exports", "77777"),
      v(8, "CO-9", "V9", "Sales", "2026-10-01", "Mehta Secret", "88888"),
    ];
  }

  // Index of the parameter compared in a "<expr> $N" fragment.
  static idx(s, re) {
    const m = re.exec(s);
    return m ? Number(m[1]) - 1 : -1;
  }

  permLedgers(s, p) {
    const i = FakeDb.idx(s, /user_ledger_permissions WHERE user_id = \$(\d+)/);
    return i < 0 ? null : this.perms.filter((x) => x.user_id === p[i]).map((x) => x.ledger_guid);
  }

  permVouchers(s, p) {
    const i = FakeDb.idx(s, /FROM users u WHERE u\.id = \$(\d+)/);
    return i < 0 ? null : this.allowedVouchers[p[i]] || [];
  }

  // AI plans and per-user token usage (ai_plans / ai_usage / ai_usage_log).
  aiPlans = { free: { name: "Free", token_limit: "10000", period: "lifetime", is_active: true } };
  aiUsage = new Map();
  aiLog = [];
  // users.email by users.id (what the server trusts, not the request).
  userEmails = { 7: "ravi@x.in", 21: "asha@x.in", 8: "z@x.in", 30: "Workk72002@gmail.com", 31: "workk72002+x@gmail.com" };

  usageQuery(s, p) {
    if (s.startsWith("INSERT INTO ai_usage (")) {
      if (!this.aiUsage.has(p[0])) {
        this.aiUsage.set(p[0], {
          user_id: p[0], admin_id: p[1], plan_code: "free", tokens_used: "0", requests: 0,
          token_limit_override: null, period_start: new Date("2026-10-01T00:00:00Z"),
        });
      }
      return { rows: [] };
    }
    if (s.includes("FROM ai_usage u LEFT JOIN ai_plans p ON p.code = u.plan_code AND p.is_active = TRUE")) {
      const u = this.aiUsage.get(p[0]);
      if (!u) return { rows: [] };
      const pl = this.aiPlans[u.plan_code];
      const on = pl && pl.is_active;
      return {
        rows: [
          {
            ...u,
            plan_name: on ? pl.name : null,
            plan_limit: on ? pl.token_limit : null,
            plan_period: on ? pl.period : null,
            account_email: this.userEmails[p[0]] ?? null,
          },
        ],
      };
    }
    if (s.startsWith("UPDATE ai_usage SET tokens_used = 0")) {
      Object.assign(this.aiUsage.get(p[0]), { tokens_used: "0", requests: 0, period_start: new Date("2026-10-12T06:00:00Z") });
      return { rows: [] };
    }
    if (s.startsWith("UPDATE ai_usage SET tokens_used = tokens_used + $2")) {
      const u = this.aiUsage.get(p[0]);
      u.tokens_used = String(Number(u.tokens_used) + p[1]);
      u.requests++;
      return { rows: [] };
    }
    if (s.startsWith("INSERT INTO ai_usage_log")) {
      const [user_id, admin_id, company_guid, provider, model, input, output, total, estimated] = p;
      this.aiLog.push({ user_id, admin_id, company_guid, provider, model, input, output, total, estimated });
      return { rows: [] };
    }
    return null;
  }

  async query(sql, p = []) {
    const s = sql.replace(/\s+/g, " ").trim();
    const usage = this.usageQuery(s, p);
    if (usage) return usage;
    if (s.includes("FROM active_company ac")) {
      const g = this.active[p[0]];
      const c = this.companies.find((x) => x.admin_id === p[0] && x.company_guid === g);
      return { rows: g ? [{ company_guid: g, company_name: c?.name ?? null }] : [] };
    }
    if (s.includes("FROM bills b") && s.includes("GROUP BY b.ledger_name")) {
      const ok = this.permLedgers(s, p);
      const by = new Map();
      for (const x of this.bills) {
        const kind = x.bill_type === "PAYABLE" ? "payable" : "receivable";
        if (x.admin_id !== p[0] || x.company_guid !== p[1] || kind !== p[2] || Number(x.pending_amount) <= 0) continue;
        if (ok && !ok.includes(x.ledger_guid)) continue;
        const r = by.get(x.ledger_name) || { ledger_name: x.ledger_name, bills: 0, pending: 0, overdue: 0 };
        r.bills++;
        r.pending += Number(x.pending_amount);
        if (x.due_date < "2026-10-12") r.overdue += Number(x.pending_amount);
        by.set(x.ledger_name, r);
      }
      return { rows: [...by.values()].sort((a, b) => b.pending - a.pending) };
    }
    if (s.includes("FROM ledgers WHERE admin_id = $1 AND company_guid = $2 AND name ILIKE")) {
      const ok = this.permLedgers(s, p);
      const rows = this.ledgers.filter(
        (x) => x.admin_id === p[0] && x.company_guid === p[1] && x.name.toLowerCase().includes(p[2].toLowerCase()) && (!ok || ok.includes(x.ledger_guid))
      );
      return { rows };
    }
    if (s.includes("FROM bills WHERE admin_id = $1 AND company_guid = $2 AND (ledger_guid = $3")) {
      return {
        rows: this.bills.filter(
          (x) => x.admin_id === p[0] && x.company_guid === p[1] && (x.ledger_guid === p[2] || (x.ledger_guid === null && x.ledger_name === p[3])) && Number(x.pending_amount) > 0
        ),
      };
    }
    if (s.includes("FROM ledgers WHERE admin_id = $1 AND company_guid = $2 AND ($3 = ''")) {
      const ok = this.permLedgers(s, p);
      const q = p[2].toLowerCase();
      return {
        rows: this.ledgers.filter(
          (x) => x.admin_id === p[0] && x.company_guid === p[1] && (!q || x.name.toLowerCase().includes(q) || x.parent_group.toLowerCase().includes(q)) && (!ok || ok.includes(x.ledger_guid))
        ),
      };
    }
    if (s.includes("FROM vouchers v")) {
      const ok = this.permVouchers(s, p);
      const ti = FakeDb.idx(s, /LOWER\(v\.voucher_type\) = LOWER\(\$(\d+)\)/);
      const pi = FakeDb.idx(s, /v\.party_name ILIKE '%' \|\| \$(\d+)/);
      const summary = s.includes("v.voucher_date >= $4::date");
      const [fromI, toI] = summary ? [3, 4] : [2, 3];
      const rows = this.vouchers.filter(
        (x) =>
          x.admin_id === p[0] && x.company_guid === p[1] &&
          x.voucher_date >= p[fromI] && x.voucher_date <= p[toI] &&
          (ti < 0 || x.voucher_type.toLowerCase() === p[ti].toLowerCase()) &&
          (pi < 0 || (x.party_name || "").toLowerCase().includes(p[pi].toLowerCase())) &&
          (!ok || ok.includes(x.voucher_guid))
      );
      const sum = (l) => l.reduce((a, x) => a + Math.abs(Number(x.net_amount)), 0);
      if (s.includes("COUNT(*)::int AS n, COALESCE(SUM")) return { rows: [{ n: rows.length, total: sum(rows) }] };
      if (s.includes("AS party, COUNT(*)")) {
        const by = new Map();
        for (const x of rows) by.set(x.party_name, [...(by.get(x.party_name) || []), x]);
        return { rows: [...by].map(([party, l]) => ({ party, n: l.length, total: sum(l) })) };
      }
      if (s.includes("AS month")) {
        const by = new Map();
        for (const x of rows) by.set(x.voucher_date.slice(0, 7), [...(by.get(x.voucher_date.slice(0, 7)) || []), x]);
        return { rows: [...by].map(([month, l]) => ({ month, n: l.length, total: sum(l) })) };
      }
      return { rows: rows.slice(0, p[p.length - 1]) };
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

const ADMIN = { id: 7, adminId: 7, role: "ADMIN", email: "ravi@x.in" };
const USER = { id: 21, adminId: 7, role: "USER", email: "asha@x.in" };
const OTHER = { id: 8, adminId: 8, role: "ADMIN", email: "z@x.in" };
// The testing account (users.email = workk72002@gmail.com) and a
// look-alike whose request claims that email but whose saved email differs.
const TESTER = { id: 30, adminId: 7, role: "USER", email: "workk72002@gmail.com" };
const SPOOF = { id: 31, adminId: 7, role: "USER", email: "workk72002@gmail.com" };

/* ---------------------------------------------------------- routes */
// The server's own key (from .env). APP_KEY = a key an older app may still
// send: it must never be used.
const APP_KEY = "AIzaSyAPPUSERKEY_must_never_be_used_0001";
const TOKENS = 120; // what the fake Gemini reports per call

// The real Gemini adapter over a fake HTTP layer that hands each request to
// the scripted fake Gemini (so the adapter's request building is tested too).
function geminiHttp(gem) {
  return async ({ method, url, headers, body }) => {
    const key = headers["x-goog-api-key"];
    if (method === "get" && /\/models\?/.test(url)) return gem.listModels(key);
    const m = /\/models\/([^:]+):generateContent/.exec(url);
    if (!m) throw new Error(`unexpected Gemini URL ${url}`);
    return gem.generate(key, decodeURIComponent(m[1]), body);
  };
}

describe("routes", () => {
  let db, server, base, gem, logs, env;

  // Scripted Gemini: `plan` = function calls to make first, then the
  // answer is built from what the tools returned.
  function fakeGemini() {
    const g = {
      keys: [],
      bodies: [],
      plan: [],
      fail: null,
      noUsage: false,
      delay: 0,
      models: [
        { name: "models/gemini-2.5-flash", supportedGenerationMethods: ["generateContent"] },
        { name: "models/gemini-2.0-flash", supportedGenerationMethods: ["generateContent"] },
        { name: "models/text-embedding-004", supportedGenerationMethods: ["embedContent"] },
      ],
      retired: new Set(),
      used: [],
      lists: 0,
      async listModels(key) {
        g.keys.push(key);
        g.lists++;
        if (g.fail) throw g.fail;
        return { models: g.models };
      },
      async generate(key, model, body) {
        g.keys.push(key);
        g.used.push(model);
        if (g.delay) await new Promise((r) => setTimeout(r, g.delay));
        if (g.fail) throw g.fail;
        if (g.retired.has(model)) {
          throw new GeminiHttpError(404, { error: { message: `models/${model} is no longer available to new users.` } });
        }
        g.bodies.push(JSON.parse(JSON.stringify(body)));
        const usageMetadata = g.noUsage ? undefined : { promptTokenCount: TOKENS - 20, candidatesTokenCount: 20, totalTokenCount: TOKENS };
        const done = body.contents.filter((c) => c.parts.some((p) => p.functionResponse)).length;
        if (done < g.plan.length) {
          return { candidates: [{ content: { role: "model", parts: [{ functionCall: g.plan[done] }] } }], usageMetadata };
        }
        const results = body.contents.flatMap((c) => c.parts.filter((p) => p.functionResponse).map((p) => p.functionResponse.response.result));
        return { candidates: [{ content: { role: "model", parts: [{ text: `ANSWER ${JSON.stringify(results)}` }] } }], usageMetadata };
      },
    };
    return g;
  }

  beforeEach(async () => {
    db = new FakeDb();
    gem = fakeGemini();
    logs = [];
    env = { ASSISTANT_RATE_LIMIT_PER_10_MIN: "50", AI_PROVIDER: "gemini", AI_API_KEY: KEY };
    const log = { error: (...a) => logs.push(a.join(" ")), log: (...a) => logs.push(a.join(" ")) };
    const app = express();
    app.use(express.json());
    app.use(createAssistantRouter({ db, auth: stubAuth, adapters: createAdapters(geminiHttp(gem)), env, log, now: () => new Date("2026-10-12T06:00:00Z") }));
    await new Promise((r) => {
      server = app.listen(0, r);
    });
    base = `http://127.0.0.1:${server.address().port}`;
  });
  afterEach(() => new Promise((r) => server.close(r)));

  const call = async (path, user, body, key = null) => {
    const r = await fetch(base + path, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(key ? { "x-gemini-key": key } : {}),
        ...(user ? { "x-test-user": JSON.stringify(user) } : {}),
      },
      body: JSON.stringify(body ?? {}),
    });
    const text = await r.text();
    return { status: r.status, text, body: JSON.parse(text) };
  };
  const get = async (path, user) => {
    const r = await fetch(base + path, { headers: user ? { "x-test-user": JSON.stringify(user) } : {} });
    const text = await r.text();
    return { status: r.status, text, body: JSON.parse(text) };
  };
  const ask = (user, question, plan = [], extra = {}) => {
    gem.plan = plan;
    return call("/api/assistant/ask", user, { question, ...extra });
  };

  test("no key from the app: the server's key answers; login needed", async () => {
    assert.equal((await call("/api/assistant/ask", null, { question: "q" })).status, 401);
    const r = await ask(ADMIN, "Sales?");
    assert.equal(r.status, 200);
    assert.ok(gem.keys.length > 0 && gem.keys.every((k) => k === KEY));
    for (const t of [r.text, ...logs]) assert.ok(!t.includes(KEY));
  });

  test("not configured (no AI_API_KEY / unknown provider) → 503, nothing called", async () => {
    delete env.AI_API_KEY;
    const r = await ask(ADMIN, "Sales?");
    assert.equal(r.status, 503);
    assert.equal(r.body.code, "ai_not_configured");
    const st = await get("/api/assistant/status", ADMIN);
    assert.equal(st.body.enabled, false);
    env.AI_API_KEY = KEY;
    env.AI_PROVIDER = "nope";
    assert.equal((await ask(ADMIN, "Sales?")).body.code, "ai_not_configured");
    assert.equal(gem.keys.length, 0);
  });

  test("older apps: their key is ignored; verify / models / providers answer from the server", async () => {
    const v = await call("/api/assistant/verify", ADMIN, { provider: "openai", model: "gpt-4o" }, APP_KEY);
    assert.equal(v.status, 200);
    assert.equal(v.body.provider, "gemini");
    assert.equal(gem.keys.length, 0); // no provider call, no tokens used
    const p = await get("/api/assistant/providers", ADMIN);
    assert.deepEqual(p.body.data.map((x) => x.id), ["gemini"]);
    const a = await call("/api/assistant/ask", ADMIN, { question: "Sales?", provider: "openai", model: "gpt-4o" }, APP_KEY);
    assert.equal(a.status, 200);
    assert.ok(gem.keys.every((k) => k === KEY)); // never the app's key
    for (const t of [v.text, a.text, ...logs]) assert.ok(!t.includes(APP_KEY) && !t.includes(KEY));
  });

  test("usage: the provider's tokens are counted per user, across devices", async () => {
    const r = await ask(ADMIN, "Who owes me the most?", [{ name: "outstanding_summary", args: { kind: "receivable" } }]);
    assert.equal(r.status, 200);
    // Two provider calls (tool call + answer).
    assert.equal(r.body.tokens_used, 2 * TOKENS);
    assert.deepEqual(
      { used: r.body.usage.used, limit: r.body.usage.limit, remaining: r.body.usage.remaining, exhausted: r.body.usage.exhausted },
      { used: 240, limit: 10000, remaining: 9760, exhausted: false }
    );
    assert.equal(r.body.usage.plan.code, "free");
    assert.equal(db.aiLog.length, 2);
    assert.deepEqual(
      [db.aiLog[0].user_id, db.aiLog[0].company_guid, db.aiLog[0].provider, db.aiLog[0].model, db.aiLog[0].total, db.aiLog[0].estimated],
      [7, "CO-1", "gemini", "gemini-2.5-flash", TOKENS, false]
    );
    // Another device / session of the same login sees the same total.
    const st = await get("/api/assistant/status", ADMIN);
    assert.equal(st.body.enabled, true);
    assert.equal(st.body.provider.label, "Google Gemini");
    assert.equal(st.body.usage.used, 240);
    // Each login has its own allowance.
    assert.equal((await get("/api/assistant/status", USER)).body.usage.used, 0);
    // A status check costs nothing.
    assert.equal(db.aiLog.length, 2);
  });

  test("allowance used up → 402 with the exact message; the provider is not called", async () => {
    await get("/api/assistant/status", ADMIN);
    db.aiUsage.get(7).tokens_used = "10000";
    const r = await ask(ADMIN, "Sales?");
    assert.equal(r.status, 402);
    assert.equal(r.body.code, "ai_quota_exhausted");
    assert.equal(r.body.message, "Your free AI access has ended. Upgrade your plan to continue.");
    assert.equal(r.body.usage.remaining, 0);
    assert.equal(gem.keys.length, 0);
    assert.equal((await get("/api/assistant/status", ADMIN)).body.usage.exhausted, true);
    // Another user is not affected.
    assert.equal((await ask(USER, "Sales?")).status, 200);
  });

  test("a question started within the allowance is answered; the next is refused", async () => {
    await get("/api/assistant/status", ADMIN);
    db.aiUsage.get(7).tokens_used = "9950";
    const r = await ask(ADMIN, "Who owes me?", [{ name: "outstanding_summary", args: { kind: "receivable" } }]);
    assert.equal(r.status, 200);
    assert.equal(r.body.usage.used, 9950 + 240);
    assert.equal(r.body.usage.exhausted, true);
    assert.equal((await ask(ADMIN, "Again?")).status, 402);
  });

  test("no token count from the provider → estimated, still counted", async () => {
    gem.noUsage = true;
    const r = await ask(ADMIN, "Sales?");
    assert.equal(r.status, 200);
    assert.equal(db.aiLog[0].estimated, true);
    assert.ok(db.aiLog[0].total > 100); // system prompt + tools are counted
    assert.equal(r.body.usage.used, db.aiLog[0].total);
  });

  test("plans: per-user override, monthly plan restarts, AI_FREE_TOKENS", async () => {
    await get("/api/assistant/status", ADMIN);
    const u = db.aiUsage.get(7);
    u.tokens_used = "12000";
    u.token_limit_override = "50000";
    let st = (await get("/api/assistant/status", ADMIN)).body.usage;
    assert.deepEqual([st.limit, st.remaining, st.exhausted], [50000, 38000, false]);
    // A paid monthly plan: its month is over → back to 0.
    db.aiPlans.pro = { name: "Pro", token_limit: "500000", period: "month", is_active: true };
    Object.assign(u, { plan_code: "pro", token_limit_override: null, tokens_used: "500000", period_start: new Date("2026-09-01T00:00:00Z") });
    st = (await get("/api/assistant/status", ADMIN)).body.usage;
    assert.deepEqual([st.plan.name, st.used, st.limit, st.exhausted], ["Pro", 0, 500000, false]);
    assert.ok(st.resets_at.startsWith("2026-11-12"));
    // The free allowance comes from the plan row; AI_FREE_TOKENS only when it is missing.
    env.AI_FREE_TOKENS = "2000";
    delete db.aiPlans.free;
    assert.equal((await get("/api/assistant/status", USER)).body.usage.limit, 2000);
  });

  test("testing account: unlimited tokens, decided from users.email only", async () => {
    await get("/api/assistant/status", TESTER);
    db.aiUsage.get(30).tokens_used = "250000"; // far past the free 10,000
    const st = (await get("/api/assistant/status", TESTER)).body.usage;
    assert.deepEqual(
      [st.unlimited, st.exhausted, st.plan.code, st.used, st.remaining],
      [true, false, "unlimited", 250000, 1000000000]
    );
    assert.ok(st.limit > st.used); // older apps never see it as used up
    const r = await ask(TESTER, "Sales?");
    assert.equal(r.status, 200);
    // Still counted and logged.
    assert.equal(r.body.usage.used, 250000 + TOKENS);
    assert.equal(db.aiLog.at(-1).user_id, 30);
    // A request claiming the email does not make another login unlimited.
    await get("/api/assistant/status", SPOOF);
    db.aiUsage.get(31).tokens_used = "10000";
    const s2 = await ask(SPOOF, "Sales?");
    assert.equal(s2.status, 402);
    assert.equal(s2.body.code, "ai_quota_exhausted");
    // Everyone else: the same allowance as before.
    await get("/api/assistant/status", ADMIN);
    db.aiUsage.get(7).tokens_used = "10000";
    assert.equal((await ask(ADMIN, "Sales?")).status, 402);
    const a = (await get("/api/assistant/status", USER)).body.usage;
    assert.deepEqual([a.limit, a.unlimited, a.plan.code], [10000, undefined, "free"]);
    // Login still needed.
    assert.equal((await get("/api/assistant/status", null)).status, 401);
  });

  test("AI_UNLIMITED_EMAILS: replaces the list; empty turns it off", async () => {
    await get("/api/assistant/status", TESTER);
    db.aiUsage.get(30).tokens_used = "10000";
    env.AI_UNLIMITED_EMAILS = "";
    assert.equal((await ask(TESTER, "Sales?")).status, 402);
    env.AI_UNLIMITED_EMAILS = " ASHA@x.in , not-an-email ";
    assert.equal((await ask(TESTER, "Sales?")).status, 402);
    await get("/api/assistant/status", USER);
    db.aiUsage.get(21).tokens_used = "10000";
    assert.equal((await ask(USER, "Sales?")).status, 200);
  });

  test("one question at a time per user (no double spending from two devices)", async () => {
    gem.delay = 150;
    const [a, b] = await Promise.all([ask(ADMIN, "One?"), new Promise((r) => setTimeout(r, 30)).then(() => ask(ADMIN, "Two?"))]);
    assert.deepEqual([a.status, b.status].sort(), [200, 429]);
    assert.equal([a, b].find((x) => x.status === 429).body.code, "busy");
  });

  test("answers from company-scoped tools only", async () => {
    const r = await ask(ADMIN, "Who owes me the most?", [{ name: "outstanding_summary", args: { kind: "receivable" } }]);
    assert.equal(r.status, 200);
    assert.deepEqual(r.body.tools_used, ["outstanding_summary"]);
    assert.match(r.body.answer, /Mehta Electricals/);
    assert.match(r.body.answer, /"total_pending":19000.5/); // 10000.50 + 5000 + 4000
    // Other company / other account never reach the AI provider.
    const sent = JSON.stringify(gem.bodies);
    for (const secret of ["Mehta Exports", "77777", "Mehta Secret", "88888"]) assert.ok(!sent.includes(secret), secret);
    // System prompt names the active company and forbids guessing.
    const sys = gem.bodies[0].systemInstruction.parts[0].text;
    assert.match(sys, /Ravi Traders/);
    assert.match(sys, /never guess/);
    assert.equal(gem.bodies[0].tools[0].functionDeclarations.length, 5);
  });

  test("USER logins: only permitted ledgers and vouchers", async () => {
    const out = await ask(USER, "Outstanding?", [{ name: "outstanding_summary", args: { kind: "receivable" } }]);
    assert.match(out.body.answer, /Gupta Stores/);
    assert.ok(!out.body.answer.includes("Mehta"));
    const pb = await ask(USER, "Mehta bills?", [{ name: "party_bills", args: { party: "Mehta" } }]);
    assert.match(pb.body.answer, /"found":false/);
    assert.ok(!pb.body.answer.includes("S/101"));
    const sl = await ask(USER, "Ledgers?", [{ name: "search_ledgers", args: { query: "" } }]);
    assert.ok(sl.body.answer.includes("Gupta Stores") && !sl.body.answer.includes("Polycab"));
    const vs = await ask(USER, "Sales?", [{ name: "voucher_summary", args: { voucher_type: "Sales", from: "2026-01-01", to: "2026-12-31" } }]);
    assert.match(vs.body.answer, /"count":1/);
    assert.match(vs.body.answer, /"total":4000/);
    const lt = await ask(USER, "Entries?", [{ name: "list_transactions", args: { from: "2026-01-01", to: "2026-12-31" } }]);
    assert.ok(lt.body.answer.includes("V2") && !lt.body.answer.includes("V1"));
  });

  test("tools: party bills, sales summary, transactions, unknown tool", async () => {
    const pb = await ask(ADMIN, "Mehta?", [{ name: "party_bills", args: { party: "Mehta Electricals" } }]);
    assert.match(pb.body.answer, /"pending_total":15000.5/);
    assert.match(pb.body.answer, /"overdue_days":22/);
    const amb = await ask(ADMIN, "?", [{ name: "party_bills", args: { party: "a" } }]);
    assert.match(amb.body.answer, /did_you_mean/);
    const vs = await ask(ADMIN, "Sales?", [{ name: "voucher_summary", args: { from: "2026-09-01", to: "2026-10-31" } }]);
    assert.match(vs.body.answer, /"count":2,"total":16000/);
    const lt = await ask(ADMIN, "Receipts?", [{ name: "list_transactions", args: { voucher_type: "receipt", from: "2026-10-01", to: "2026-10-31" } }]);
    assert.match(lt.body.answer, /"type":"Receipt"/);
    assert.ok(!lt.body.answer.includes('"type":"Sales"'));
    const un = await ask(ADMIN, "?", [{ name: "drop_tables", args: {} }]);
    assert.match(un.body.answer, /Unknown tool/);
  });

  test("cards and tables come from the lookups' own figures", async () => {
    const r = await ask(ADMIN, "Who owes me the most?", [{ name: "outstanding_summary", args: { kind: "receivable" } }]);
    const [kpis, tbl] = r.body.blocks;
    assert.equal(kpis.type, "kpis");
    assert.deepEqual(
      kpis.items.map((i) => [i.label, i.value]),
      [["Total pending", 19000.5], ["Overdue", 14000.5], ["Bills", 3], ["Parties", 2]]
    );
    assert.equal(kpis.items[0].format, "money");
    assert.equal(tbl.type, "table");
    assert.deepEqual(tbl.rows[0], ["Mehta Electricals", 2, 15000.5, 10000.5]);
    assert.equal(tbl.total_rows, 2);
    const amb = await ask(ADMIN, "?", [{ name: "party_bills", args: { party: "a" } }]);
    assert.equal(amb.body.blocks[0].type, "note");
    const lt = await ask(ADMIN, "Receipts", [{ name: "list_transactions", args: { voucher_type: "Receipt", from: "2026-10-01", to: "2026-10-31" } }]);
    assert.deepEqual(lt.body.blocks[0].rows, [["2026-10-03", "Receipt", "Mehta Electricals", 2000]]);
    const none = await ask(ADMIN, "Today", [{ name: "list_transactions", args: { from: "2020-01-01", to: "2020-01-02" } }]);
    assert.equal(none.body.blocks[0].rows.length, 0);
    assert.equal(none.body.blocks[0].empty, "No entries found for this period.");
    const twice = await ask(ADMIN, "?", [
      { name: "outstanding_summary", args: { kind: "payable" } },
      { name: "outstanding_summary", args: { kind: "payable" } },
    ]);
    assert.equal(twice.body.blocks.length, 2);
    const u = await ask(USER, "Outstanding?", [{ name: "outstanding_summary", args: { kind: "receivable" } }]);
    assert.ok(!JSON.stringify(u.body.blocks).includes("Mehta"));
  });

  test("prompt: TallyConnect-only scope with the exact refusal; summary format", async () => {
    await ask(ADMIN, "Who won the cricket match?");
    const sys = gem.bodies[0].systemInstruction.parts[0].text;
    assert.ok(sys.includes(OFF_TOPIC_REPLY));
    assert.match(sys, /Never write tables/);
    assert.match(sys, /₹1,23,456.78/);
    assert.equal(
      OFF_TOPIC_REPLY,
      "I’m the TallyConnect AI Assistant, designed to help you with TallyConnect and your accounting data. Please ask me something related to TallyConnect."
    );
  });

  test("other account's admin never sees this account's data", async () => {
    const r = await ask(OTHER, "Mehta?", [{ name: "party_bills", args: { party: "Mehta" } }]);
    assert.match(r.body.answer, /Mehta Secret/);
    assert.ok(!r.body.answer.includes("Mehta Electricals"));
  });

  test("no active company → 409, provider not called, nothing counted", async () => {
    delete db.active[7];
    const r = await ask(ADMIN, "Sales?");
    assert.equal(r.status, 409);
    assert.equal(r.body.code, "no_company");
    assert.equal(gem.keys.length, 0);
    assert.equal(db.aiLog.length, 0);
  });

  test("provider errors on the server key: users get service messages, never 401, key never leaked", async () => {
    gem.fail = new GeminiHttpError(400, { error: { message: `API key not valid: ${KEY}`, details: [{ reason: "API_KEY_INVALID" }] } });
    const bad = await ask(ADMIN, "Sales?");
    assert.deepEqual([bad.status, bad.body.code], [503, "ai_unavailable"]);
    assert.ok(!/key/i.test(bad.body.message)); // nothing about "your key"
    gem.fail = new GeminiHttpError(429, { error: { message: `quota for key ${KEY}` } });
    const q = await ask(ADMIN, "Sales?");
    assert.deepEqual([q.status, q.body.code], [503, "ai_busy"]);
    gem.fail = new GeminiHttpError(null, null, true);
    assert.equal((await ask(ADMIN, "Sales?")).status, 504);
    gem.fail = new GeminiHttpError(503, {});
    const d = await ask(ADMIN, "Sales?");
    assert.deepEqual([d.status, d.body.code], [502, "ai_unavailable"]);
    for (const t of [bad.text, q.text, d.text, ...logs]) assert.ok(!t.includes(KEY));
    // Failed calls cost nothing.
    assert.equal(db.aiLog.length, 0);
  });

  test("history is passed; too many tool rounds stop", async () => {
    await ask(ADMIN, "And payables?", [], {
      history: [
        { role: "user", text: "Receivables?" },
        { role: "model", text: "₹19,000.50" },
      ],
    });
    assert.deepEqual(gem.bodies[0].contents.map((c) => c.role), ["user", "model", "user"]);
    const loop = Array.from({ length: 10 }, () => ({ name: "search_ledgers", args: {} }));
    const r = await ask(ADMIN, "?", loop);
    assert.equal(r.status, 502);
    assert.equal(r.body.code, "too_complex");
  });

  test("no AI_MODEL: the key's best model; a retired one (404) → the next", async () => {
    gem.retired.add("gemini-2.5-flash");
    const r = await ask(ADMIN, "Last 5 receipts", [{ name: "list_transactions", args: { voucher_type: "Receipt", limit: 5 } }]);
    assert.equal(r.status, 200);
    assert.match(r.body.answer, /Receipt/);
    assert.equal(gem.used.at(-1), "gemini-2.0-flash");
    assert.ok(logs.some((l) => l.includes("gemini-2.5-flash not available")));
    gem.retired.add("gemini-2.0-flash");
    const none = await ask(ADMIN, "Sales?");
    assert.deepEqual([none.status, none.body.code], [503, "ai_unavailable"]);
  });

  test("AI_MODEL is used as is (no model listing)", async () => {
    env.AI_MODEL = "gemini-2.0-flash";
    await ask(ADMIN, "a");
    await ask(ADMIN, "b");
    assert.deepEqual(gem.used, ["gemini-2.0-flash", "gemini-2.0-flash"]);
    assert.equal(gem.lists, 0);
    assert.equal(db.aiLog[0].model, "gemini-2.0-flash");
  });

  test("rate limit per user", async () => {
    env.ASSISTANT_RATE_LIMIT_PER_10_MIN = "2";
    assert.equal((await ask(ADMIN, "a")).status, 200);
    assert.equal((await ask(ADMIN, "b")).status, 200);
    const r = await ask(ADMIN, "c");
    assert.equal(r.status, 429);
    assert.equal(r.body.code, "rate_limited");
    assert.equal((await ask(USER, "d")).status, 200); // another user
  });
});

/* ------------------------------------------- other AI providers */
const OKEY = "sk-proj-TESTKEY_openai_0123456789abcdef";
const AKEY = "sk-ant-api03-TESTKEY_anthropic_0123456789";

/**
 * Fake OpenAI- and Anthropic-style servers behind one http function. Each
 * checks the request shape its real API expects and records it.
 */
function providerHttp() {
  const seen = [];
  const st = { plan: [], fail: null };
  const http = async ({ method, url, headers, body }) => {
    seen.push({ method, url, headers, body: body && JSON.parse(JSON.stringify(body)) });
    if (st.fail) throw st.fail;
    // ---------------- OpenAI chat API
    if (url.startsWith("https://api.openai.com/v1")) {
      assert.equal(headers.Authorization, `Bearer ${OKEY}`);
      if (method === "get") {
        return {
          data: ["whisper-1", "gpt-4o", "text-embedding-3-small", "gpt-4o-mini", "gpt-4o-realtime-preview"].map((id) => ({ id })),
        };
      }
      const results = body.messages.filter((m) => m.role === "tool");
      for (const t of body.tools || []) {
        assert.equal(t.type, "function");
        assert.equal(t.function.parameters.type, "object"); // JSON Schema, lower case
      }
      const usage = { prompt_tokens: 50, completion_tokens: 10, total_tokens: 60 };
      if (!results.length && st.plan.length) {
        return {
          usage,
          choices: [
            {
              finish_reason: "tool_calls",
              message: {
                role: "assistant",
                content: null,
                tool_calls: st.plan.map((c, i) => ({
                  id: `call_${i}`,
                  type: "function",
                  function: { name: c.name, arguments: JSON.stringify(c.args) },
                })),
              },
            },
          ],
        };
      }
      const asked = body.messages.flatMap((m) => (m.tool_calls || []).map((c) => c.id));
      for (const r of results) assert.ok(asked.includes(r.tool_call_id));
      return {
        usage,
        choices: [
          { finish_reason: "stop", message: { role: "assistant", content: `OPENAI ${results.map((r) => r.content).join(" ")}` } },
        ],
      };
    }
    // ---------------- Anthropic Messages API
    if (url.startsWith("https://api.anthropic.com/v1")) {
      assert.equal(headers["x-api-key"], AKEY);
      assert.equal(headers["anthropic-version"], "2023-06-01");
      assert.equal(headers.Authorization, undefined);
      if (method === "get") {
        return { data: ["claude-haiku-4-5", "claude-sonnet-4-5", "claude-opus-4-1"].map((id) => ({ id })) };
      }
      assert.ok(body.max_tokens > 0);
      assert.ok(!body.messages.some((m) => m.role === "system"));
      for (const t of body.tools || []) assert.equal(t.input_schema.type, "object");
      const results = body.messages.flatMap((m) =>
        (Array.isArray(m.content) ? m.content : []).filter((b) => b.type === "tool_result")
      );
      const usage = { input_tokens: 70, output_tokens: 15 };
      if (!results.length && st.plan.length) {
        return {
          usage,
          stop_reason: "tool_use",
          content: [
            { type: "text", text: "Looking it up." },
            ...st.plan.map((c, i) => ({ type: "tool_use", id: `toolu_${i}`, name: c.name, input: c.args })),
          ],
        };
      }
      return { usage, stop_reason: "end_turn", content: [{ type: "text", text: `CLAUDE ${results.map((r) => r.content).join(" ")}` }] };
    }
    throw new Error(`unexpected URL ${url}`);
  };
  return { http, seen, st };
}

describe("other providers (set on the server)", () => {
  let db, server, base, fake, logs, env;
  beforeEach(async () => {
    db = new FakeDb();
    fake = providerHttp();
    logs = [];
    env = { AI_PROVIDER: "openai", AI_API_KEY: OKEY };
    const log = { error: (...a) => logs.push(a.join(" ")), log: () => {} };
    const app = express();
    app.use(express.json());
    app.use(
      createAssistantRouter({
        db,
        auth: stubAuth,
        adapters: createAdapters(fake.http),
        env,
        log,
        now: () => new Date("2026-10-12T06:00:00Z"),
      })
    );
    await new Promise((r) => {
      server = app.listen(0, r);
    });
    base = `http://127.0.0.1:${server.address().port}`;
  });
  afterEach(() => new Promise((r) => server.close(r)));

  const post = async (path, body, headers = {}, user = ADMIN) => {
    const r = await fetch(base + path, {
      method: "POST",
      headers: { "content-type": "application/json", "x-test-user": JSON.stringify(user), ...headers },
      body: JSON.stringify(body),
    });
    const text = await r.text();
    return { status: r.status, text, body: JSON.parse(text) };
  };

  test("OpenAI: best chat model, scoped tools, its token counts", async () => {
    fake.st.plan = [{ name: "outstanding_summary", args: { kind: "receivable" } }];
    const a = await post("/api/assistant/ask", { question: "Who owes me most?" });
    assert.equal(a.status, 200);
    assert.match(a.body.answer, /^OPENAI .*"total_pending":19000.5/);
    assert.ok(!a.body.answer.includes("Mehta Exports")); // other company never sent
    assert.equal(a.body.blocks[0].type, "kpis");
    assert.equal(fake.seen.at(-1).body.model, "gpt-4o-mini"); // no whisper / embeddings / realtime
    assert.equal(a.body.usage.used, 120); // 2 calls × 60
    assert.deepEqual([db.aiLog[0].input, db.aiLog[0].output, db.aiLog[0].provider], [50, 10, "openai"]);
    env.AI_MODEL = "gpt-4o";
    await post("/api/assistant/ask", { question: "Hi", model: "gpt-9-from-old-app" });
    assert.equal(fake.seen.at(-1).body.model, "gpt-4o"); // the server's model, never the app's
  });

  test("Anthropic: Claude's own format and token counts", async () => {
    Object.assign(env, { AI_PROVIDER: "anthropic", AI_API_KEY: AKEY });
    fake.st.plan = [{ name: "party_bills", args: { party: "Mehta Electricals" } }];
    const a = await post("/api/assistant/ask", { question: "Mehta bills?" });
    assert.equal(a.status, 200);
    assert.match(a.body.answer, /^CLAUDE .*"pending_total":15000.5/);
    assert.equal(fake.seen.at(-1).body.model, "claude-sonnet-4-5"); // Sonnet first
    const last = fake.seen.at(-1).body;
    assert.ok(last.system.includes("Ravi Traders"));
    const toolUse = last.messages.find((m) => m.role === "assistant").content.find((b) => b.type === "tool_use");
    assert.equal(last.messages.at(-1).content[0].tool_use_id, toolUse.id);
    assert.equal(a.body.usage.used, 170); // 2 × (70 + 15)
  });

  test("errors: bad server key / no credit / model gone → service messages, key never leaked", async () => {
    const { ProviderHttpError } = await import("../utils/aiProviders.js");
    fake.st.fail = new ProviderHttpError(401, { error: { message: `Incorrect API key provided: ${OKEY}` } });
    const bad = await post("/api/assistant/ask", { question: "x" });
    assert.deepEqual([bad.status, bad.body.code], [503, "ai_unavailable"]);
    assert.equal(bad.body.message, "The AI Assistant is temporarily unavailable. Please try again later.");
    fake.st.fail = new ProviderHttpError(429, { error: { message: "You exceeded your current quota", type: "insufficient_quota" } });
    assert.equal((await post("/api/assistant/ask", { question: "x" })).body.code, "ai_busy");
    env.AI_MODEL = "gpt-9";
    fake.st.fail = new ProviderHttpError(404, { error: { message: "The model `gpt-9` does not exist" } });
    const gone = await post("/api/assistant/ask", { question: "x" });
    assert.deepEqual([gone.status, gone.body.code], [503, "ai_unavailable"]);
    for (const t of [bad.text, gone.text, ...logs]) assert.ok(!t.includes(OKEY));
    assert.ok(logs.some((l) => l.includes("[key]"))); // the operator sees why, key masked
  });

  test("an old app's X-Gemini-Key never reaches any provider", async () => {
    const r = await post("/api/assistant/ask", { question: "hi" }, { "x-gemini-key": KEY });
    assert.equal(r.status, 200);
    assert.ok(fake.seen.every((x) => !x.headers["x-goog-api-key"] && !JSON.stringify(x.headers).includes(KEY)));
  });
});
