/* =========================================================
   AI FINANCIAL ASSISTANT — routes (factory; dependencies passed in)

   GET  /api/assistant/status   is the assistant on; this user's AI plan
                                 and token usage {limit, used, remaining}
   POST /api/assistant/ask      {question, history[]} → answer, cards,
                                 usage after this question

   One AI provider, model and API key for everyone, set on the server
   (.env: AI_PROVIDER, AI_MODEL, AI_API_KEY). Users enter no key. The key
   is never sent to the app, logged or returned.

   Each user has a token allowance (free plan: AI_FREE_TOKENS, default
   10,000), counted from the provider's own token figures for every call,
   across devices (see aiUsage.js). Used up → 402 `ai_quota_exhausted`
   and the AI provider is not called.

   The provider gets only what the read-only tools return, all limited to
   the login's account, its active company and (USER logins) its
   permissions. Provider errors never answer 401 (that would sign the user
   out of TallyConnect).

   Older apps still call /providers, /verify and /models with their own
   key: those answer from the server's configuration (the key they send is
   ignored, never used), so they keep working.
========================================================= */
import { createHash } from "node:crypto";
import express from "express";
import {
  AssistantError,
  MAX_TOOL_ROUNDS,
  assistantConfig,
  blocksFor,
  neutralTools,
  providerFailure,
  serviceFailure,
  systemPrompt,
  todayIso,
  validateAsk,
} from "./assistantCore.js";
import { createAdapters } from "./aiProviders.js";
import { createTools } from "./assistantTools.js";
import { createAiUsage, tokensOf } from "./aiUsage.js";

const MODEL_TTL_MS = 6 * 3600 * 1000;

/**
 * @param {object} deps
 * @param {{query: Function}} deps.db
 * @param {Function} deps.auth
 * @param {object} [deps.adapters]   provider id → adapter (tests pass fakes)
 * @param {object} [deps.env]
 * @param {object} [deps.log]
 * @param {() => Date} [deps.now]
 */
export function createAssistantRouter({
  db,
  auth,
  adapters = createAdapters(),
  env = process.env,
  log = console,
  now = () => new Date(),
}) {
  const router = express.Router();
  const cfg = () => assistantConfig(env);
  const usage = createAiUsage(db, env, now);
  const hits = new Map(); // userId → request times (last 10 minutes)
  const inFlight = new Set(); // userIds with a question being answered

  function limit(userId) {
    const t = Date.now();
    const recent = (hits.get(userId) || []).filter((x) => t - x < 600000);
    if (recent.length >= cfg().perTenMinutes) {
      throw new AssistantError("rate_limited", 429, "Too many questions in a short time. Wait a few minutes.");
    }
    recent.push(t);
    hits.set(userId, recent);
  }

  /** The configured provider and key, or null when not set up. */
  function service() {
    const c = cfg();
    const ad = adapters[c.provider];
    if (!ad || !c.apiKey) return null;
    return { ad, key: c.apiKey, model: c.model };
  }

  function requireService() {
    const s = service();
    if (!s) {
      log.error("assistant: AI_PROVIDER / AI_API_KEY not set (or unknown provider) — the assistant is off");
      throw new AssistantError("ai_not_configured", 503, "The AI Assistant is not available right now.");
    }
    return s;
  }

  async function scope(req) {
    const u = req.user || {};
    if (!u.id) throw new AssistantError("unauthorized", 401, "Unauthorized");
    const adminId = u.adminId ?? (u.role === "ADMIN" ? u.id : null);
    if (!adminId) throw new AssistantError("forbidden", 403, "Access denied");
    const r = await db.query(
      `SELECT ac.company_guid, c.name AS company_name
         FROM active_company ac
         LEFT JOIN companies c ON c.company_guid = ac.company_guid AND c.admin_id = ac.admin_id
        WHERE ac.admin_id = $1 LIMIT 1`,
      [adminId]
    );
    const company = r.rows[0]?.company_guid || null;
    if (!company) throw new AssistantError("no_company", 409, "No company is selected for this account.");
    return {
      adminId,
      company,
      companyName: r.rows[0]?.company_name || "",
      isAdmin: u.role === "ADMIN",
      userId: u.id,
      role: u.role,
    };
  }

  /** The login only (usage needs no company). */
  function who(req) {
    const u = req.user || {};
    if (!u.id) throw new AssistantError("unauthorized", 401, "Unauthorized");
    return { userId: u.id, adminId: u.adminId ?? (u.role === "ADMIN" ? u.id : null) };
  }

  /** A provider call; failures become user-safe errors (key never logged). */
  async function call(ad, key, what, fn) {
    try {
      return await fn();
    } catch (err) {
      if (err instanceof AssistantError) throw err;
      const raw = err?.body?.error?.message || err?.body?.message || "";
      const why = String(typeof raw === "string" ? raw : "")
        .split(key || "\u0000")
        .join("[key]")
        .slice(0, 300);
      log.error(
        `assistant: ${ad.label} ${what} failed (${err?.status ?? (err?.timeout ? "timeout" : "network")})` +
          (why ? `: ${why}` : "")
      );
      if (err?.timeout) throw serviceFailure({ code: "timeout" });
      if (!err?.status) throw serviceFailure({ code: "unavailable" });
      throw serviceFailure(providerFailure(ad.id, ad.label, err.status, err.body));
    }
  }

  // ------------------------------------------ models of the key (cached)
  const models = new Map(); // provider|keyHash → {list, at}
  const cacheKey = (ad, key) => `${ad.id}|${createHash("sha256").update(key).digest("hex")}`;

  async function modelsFor(ad, key) {
    const ck = cacheKey(ad, key);
    const c = models.get(ck);
    if (c && Date.now() - c.at < MODEL_TTL_MS && c.list.length) return c.list;
    const list = await call(ad, key, "model list", () => ad.listModels(key));
    if (!list.length) {
      log.error(`assistant: the ${ad.label} key has no model that can answer (set AI_MODEL or check the key)`);
      throw serviceFailure({ code: "model_unavailable" });
    }
    models.set(ck, { list, at: Date.now() });
    return list;
  }

  /**
   * One chat turn. With AI_MODEL set, only that model; without, the key's
   * best model, moving to the next when the provider says it is gone (404).
   */
  async function chat(ad, key, chosen, req) {
    if (chosen) {
      return { out: await call(ad, key, `chat (${chosen})`, () => ad.chat({ key, model: chosen, ...req })), model: chosen };
    }
    let list = await modelsFor(ad, key);
    for (let i = 0; i < 4 && list.length; i++) {
      const model = list[0];
      try {
        return { out: await ad.chat({ key, model, ...req }), model };
      } catch (err) {
        if (err?.status !== 404) return call(ad, key, `chat (${model})`, () => Promise.reject(err));
        log.error(`assistant: ${ad.label} model ${model} not available for this key (404); trying the next`);
        list = list.slice(1);
        models.set(cacheKey(ad, key), { list, at: Date.now() });
      }
    }
    models.delete(cacheKey(ad, key));
    log.error(`assistant: none of the ${ad.label} models could answer (set AI_MODEL or check the key)`);
    throw serviceFailure({ code: "model_unavailable" });
  }

  const handle = (fn) => async (req, res) => {
    try {
      await fn(req, res);
    } catch (err) {
      if (err instanceof AssistantError) {
        if (err.code === "rate_limited" || err.code === "ai_busy") res.set("Retry-After", "60");
        return res.status(err.http).json({
          success: false,
          code: err.code,
          message: err.message,
          ...(err.usage ? { usage: err.usage } : {}),
        });
      }
      log.error("assistant error:", err?.message || err);
      if (!res.headersSent) res.status(500).json({ success: false, message: "Server error" });
    }
  };

  router.get(
    "/api/assistant/status",
    auth,
    handle(async (req, res) => {
      const s = service();
      res.json({
        success: true,
        enabled: !!s,
        provider: s ? { id: s.ad.id, label: s.ad.label } : null,
        usage: await usage.status(who(req)),
      });
    })
  );

  router.post(
    "/api/assistant/ask",
    auth,
    handle(async (req, res) => {
      const v = validateAsk(req.body);
      if (!v.ok) throw new AssistantError("bad_input", 400, v.message);
      const s = await scope(req);
      const { ad, key, model: configured } = requireService();
      await usage.assertCanAsk(s);
      if (inFlight.has(s.userId)) {
        throw new AssistantError("busy", 429, "Wait for the current answer before asking again.");
      }
      limit(req.user.id);
      inFlight.add(s.userId);
      try {
        const run = createTools(db, s, now);
        const tools = neutralTools();
        const system = systemPrompt({ company: s.companyName, today: todayIso(now()), role: s.role });
        const messages = [
          ...v.value.history.map((h) => ({ role: h.role === "model" ? "assistant" : "user", text: h.text })),
          { role: "user", text: v.value.question },
        ];
        const used = [];
        // Cards / tables for the app, from the lookups' own results (one
        // set per distinct lookup; the model's text never supplies figures).
        const blocks = [];
        const seen = new Set();
        let model = configured;
        let tokens = 0;
        for (let round = 0; round <= MAX_TOOL_ROUNDS; round++) {
          const g = await chat(ad, key, model, { system, messages, tools });
          model = g.model;
          const out = g.out;
          // Every provider call counts, whatever happens next. A question
          // that started within the allowance is answered in full.
          const t = tokensOf(out, { system, messages, tools });
          tokens += t.total;
          await usage.record(s, { provider: ad.id, model, ...t });
          if (!out.calls?.length) {
            if (!out.text) {
              throw new AssistantError(
                out.blocked ? "blocked" : "empty",
                502,
                out.blocked ? "The AI Assistant declined to answer this question." : "The AI Assistant returned no answer. Try again."
              );
            }
            return res.json({
              success: true,
              answer: out.text,
              blocks: blocks.slice(0, 8),
              tools_used: used,
              tokens_used: tokens,
              usage: await usage.status(s),
            });
          }
          if (round === MAX_TOOL_ROUNDS) break;
          messages.push({ role: "assistant", text: out.text, calls: out.calls, raw: out.raw });
          const results = [];
          for (const c of out.calls) {
            used.push(c.name);
            const result = await run(c.name, c.args);
            const sig = `${c.name}|${JSON.stringify(c.args || {})}`;
            if (!seen.has(sig)) {
              seen.add(sig);
              blocks.push(...blocksFor(c.name, result));
            }
            results.push({ id: c.id, name: c.name, result });
          }
          messages.push({ role: "tool", results });
        }
        throw new AssistantError("too_complex", 502, "The question needed too many steps. Try asking it more simply.");
      } finally {
        inFlight.delete(s.userId);
      }
    })
  );

  // ------------------------------------------------- older app versions
  // They ask for a provider list, check "their" key and list models before
  // asking. Answered from the server's configuration; any key they send is
  // ignored (never used, logged or stored).
  router.get(
    "/api/assistant/providers",
    auth,
    handle(async (req, res) => {
      const s = service();
      res.json({ success: true, data: s ? [{ id: s.ad.id, label: s.ad.label, key_url: "", key_hint: "" }] : [] });
    })
  );

  const legacyVerify = handle(async (req, res) => {
    const { ad, model } = requireService();
    res.json({ success: true, provider: ad.id, model: model || "auto", models: model ? [model] : [] });
  });
  router.post("/api/assistant/verify", auth, legacyVerify);
  router.post("/api/assistant/models", auth, legacyVerify);

  return router;
}
