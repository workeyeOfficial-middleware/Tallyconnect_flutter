/* =========================================================
   AI FINANCIAL ASSISTANT — routes (factory; dependencies passed in)

   POST /api/assistant/verify   header X-Gemini-Key → is the key usable?
   POST /api/assistant/ask      header X-Gemini-Key, {question, history[]}

   The key is the user's own, sent with each request over HTTPS and used
   only for that request: never stored, logged or returned. Gemini gets
   only the data the read-only tools return, all limited to the login's
   account, its active company and (USER logins) its permissions.
   Gemini errors never answer 401 (that would sign the user out of
   TallyConnect): bad key → 422, quota → 429, Gemini down → 502 / 504.
========================================================= */
import { createHash } from "node:crypto";
import express from "express";
import {
  AssistantError,
  MAX_TOOL_ROUNDS,
  TOOL_DECLARATIONS,
  assistantConfig,
  geminiFailure,
  rankModels,
  readKey,
  systemPrompt,
  todayIso,
  validateAsk,
} from "./assistantCore.js";

const MODEL_TTL_MS = 6 * 3600 * 1000;
import { createTools } from "./assistantTools.js";

/**
 * @param {object} deps
 * @param {{query: Function}} deps.db
 * @param {Function} deps.auth
 * @param {{listModels: Function, generate: Function}} deps.gemini
 * @param {object} [deps.env]
 * @param {object} [deps.log]
 * @param {() => Date} [deps.now]
 */
export function createAssistantRouter({ db, auth, gemini, env = process.env, log = console, now = () => new Date() }) {
  const router = express.Router();
  const cfg = () => assistantConfig(env);
  const hits = new Map(); // userId → request times (last 10 minutes)

  function limit(userId) {
    const t = Date.now();
    const recent = (hits.get(userId) || []).filter((x) => t - x < 600000);
    if (recent.length >= cfg().perTenMinutes) {
      throw new AssistantError("rate_limited", 429, "Too many questions in a short time. Wait a few minutes.");
    }
    recent.push(t);
    hits.set(userId, recent);
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

  async function geminiCall(fn, key, what = "call") {
    try {
      return await fn();
    } catch (err) {
      if (err instanceof AssistantError) throw err;
      // Status + Google's own message (the key removed) — never the key.
      const why = String(err?.body?.error?.message || "")
        .split(key || "\u0000")
        .join("[key]")
        .slice(0, 300);
      log.error(
        `assistant: Gemini ${what} failed (${err?.status ?? (err?.timeout ? "timeout" : "network")})` +
          (why ? `: ${why}` : "")
      );
      if (err?.timeout) throw new AssistantError("timeout", 504, "Gemini took too long to answer. Try again.");
      if (!err?.status) throw new AssistantError("unavailable", 502, "Could not reach Gemini. Try again.");
      throw geminiFailure(err.status, err.body);
    }
  }

  // ------------------------------------------------- model per key
  // Google retires models and offers different ones per key / project, so
  // the model is taken from what the key can use (cached per key hash —
  // the key itself is never kept) and replaced when Google answers 404.
  const models = new Map(); // keyHash → {list, at}
  const keyHash = (key) => createHash("sha256").update(key).digest("hex");

  async function modelsFor(key, fresh = false) {
    const h = keyHash(key);
    const c = models.get(h);
    if (!fresh && c && Date.now() - c.at < MODEL_TTL_MS && c.list.length) return c.list;
    const r = await geminiCall(() => gemini.listModels(key), key, "model list");
    let list = rankModels(r?.models);
    const want = cfg().model;
    if (want && list.includes(want)) list = [want, ...list.filter((m) => m !== want)];
    if (!list.length) {
      throw new AssistantError(
        "model_unavailable",
        502,
        "This Gemini key has no model that can answer questions. Check the key's project in Google AI Studio."
      );
    }
    models.set(h, { list, at: Date.now() });
    return list;
  }

  /** generateContent with the key's best model; a 404 moves to the next. */
  async function generate(key, body) {
    let list = await modelsFor(key);
    for (let i = 0; i < 4 && list.length; i++) {
      const model = list[0];
      try {
        return { out: await gemini.generate(key, model, body), model };
      } catch (err) {
        if (err?.status !== 404) return geminiCall(() => Promise.reject(err), key, `generate (${model})`);
        log.error(`assistant: Gemini model ${model} not available for this key (404); trying the next`);
        list = list.slice(1);
        models.set(keyHash(key), { list, at: Date.now() });
      }
    }
    models.delete(keyHash(key));
    throw new AssistantError(
      "model_unavailable",
      502,
      "None of the Gemini models available to this key could answer. Check the key's project in Google AI Studio."
    );
  }

  const handle = (fn) => async (req, res) => {
    try {
      await fn(req, res);
    } catch (err) {
      if (err instanceof AssistantError) {
        if (err.code === "quota" || err.code === "rate_limited") res.set("Retry-After", "60");
        return res.status(err.http).json({ success: false, code: err.code, message: err.message });
      }
      log.error("assistant error:", err?.message || err);
      if (!res.headersSent) res.status(500).json({ success: false, message: "Server error" });
    }
  };

  router.post(
    "/api/assistant/verify",
    auth,
    handle(async (req, res) => {
      const key = readKey(req.headers);
      await scope(req);
      limit(req.user.id);
      // A real (tiny) generation, so a key that cannot answer fails here and
      // not on the first question.
      await modelsFor(key, true);
      const { model } = await generate(key, {
        contents: [{ role: "user", parts: [{ text: "Reply with OK." }] }],
      });
      res.json({ success: true, model });
    })
  );

  router.post(
    "/api/assistant/ask",
    auth,
    handle(async (req, res) => {
      const key = readKey(req.headers);
      const v = validateAsk(req.body);
      if (!v.ok) throw new AssistantError("bad_input", 400, v.message);
      const s = await scope(req);
      limit(req.user.id);
      const run = createTools(db, s, now);
      let model = null;

      const contents = [
        ...v.value.history.map((h) => ({ role: h.role, parts: [{ text: h.text }] })),
        { role: "user", parts: [{ text: v.value.question }] },
      ];
      const used = [];
      for (let round = 0; round <= MAX_TOOL_ROUNDS; round++) {
        // No output-token cap: newer "thinking" models spend tokens before
        // answering, and a small cap leaves an empty answer.
        const g = await generate(key, {
          systemInstruction: {
            parts: [{ text: systemPrompt({ company: s.companyName, today: todayIso(now()), role: s.role }) }],
          },
          contents,
          tools: [{ functionDeclarations: TOOL_DECLARATIONS }],
          generationConfig: { temperature: 0.2 },
        });
        const out = g.out;
        model = g.model;
        const cand = out?.candidates?.[0];
        const parts = cand?.content?.parts || [];
        const calls = parts.filter((p) => p.functionCall);
        if (!calls.length) {
          const text = parts
            .filter((p) => typeof p.text === "string" && !p.thought)
            .map((p) => p.text)
            .join("")
            .trim();
          if (!text) {
            const blocked = cand?.finishReason === "SAFETY" || out?.promptFeedback?.blockReason;
            throw new AssistantError(
              blocked ? "blocked" : "empty",
              502,
              blocked ? "Gemini declined to answer this question." : "Gemini returned no answer. Try again."
            );
          }
          return res.json({ success: true, answer: text, tools_used: used, model });
        }
        if (round === MAX_TOOL_ROUNDS) break;
        // Keep the model's turn as returned (incl. thought signatures), then
        // answer every function call with the scoped data.
        contents.push({ role: "model", parts });
        const responses = [];
        for (const p of calls) {
          const name = String(p.functionCall.name || "");
          used.push(name);
          const result = await run(name, p.functionCall.args);
          responses.push({ functionResponse: { name, response: { result } } });
        }
        contents.push({ role: "user", parts: responses });
      }
      throw new AssistantError("too_complex", 502, "The question needed too many steps. Try asking it more simply.");
    })
  );

  return router;
}
