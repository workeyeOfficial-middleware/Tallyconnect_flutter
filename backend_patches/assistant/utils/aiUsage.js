/* =========================================================
   AI ASSISTANT — token allowance per user (server-side)

   Every login (users.id) has an AI plan. The free plan gives
   AI_FREE_TOKENS (default 10,000) tokens in total, counted from what the
   AI provider reports for each request, across all devices and sessions.
   When used ≥ limit, questions are refused with 402 `ai_quota_exhausted`.

   Tables (sql/2026-10-14_ai_usage.sql):
     ai_plans        code, name, token_limit, period ('lifetime' | 'month')
     ai_usage        one row per user: plan, tokens used, period start,
                     optional per-user limit override
     ai_usage_log    one row per AI request (provider, model, tokens)

   Paid plans later: add a row to ai_plans and set the user's plan_code;
   a 'month' plan starts a new period (tokens back to 0) each month.
========================================================= */
import { AssistantError } from "./assistantCore.js";

export const DEFAULT_FREE_TOKENS = 10000;

export const QUOTA_MESSAGE = "Your free AI access has ended. Upgrade your plan to continue.";

const int = (v, d) => {
  const x = Number.parseInt(String(v ?? ""), 10);
  return Number.isInteger(x) && x >= 0 ? x : d;
};

/** Rough token count for text (about 4 characters a token). */
export function estimateTokens(text) {
  return Math.ceil(String(text || "").length / 4);
}

/**
 * Tokens of one provider call: the provider's own count, or an estimate
 * from the request and reply when it reports none.
 */
export function tokensOf(out, request) {
  const u = out?.usage || {};
  const input = int(u.input, 0);
  const output = int(u.output, 0);
  const total = int(u.total, input + output);
  if (total > 0) return { input, output, total, estimated: false };
  const inEst = estimateTokens(JSON.stringify(request || {}));
  const outEst = estimateTokens(out?.text) + estimateTokens(JSON.stringify(out?.calls || []));
  return { input: inEst, output: outEst, total: inEst + outEst, estimated: true };
}

const addMonth = (d) => {
  const x = new Date(d);
  x.setUTCMonth(x.getUTCMonth() + 1);
  return x;
};

/**
 * @param {{query: Function}} db
 * @param {object} [env]
 * @param {() => Date} [now]
 */
export function createAiUsage(db, env = process.env, now = () => new Date()) {
  const freeTokens = () => int(env.AI_FREE_TOKENS, DEFAULT_FREE_TOKENS);

  /** The user's row (created on first use) with its plan. */
  async function load(user) {
    await db.query(
      `INSERT INTO ai_usage (user_id, admin_id, plan_code, tokens_used, period_start)
       VALUES ($1, $2, 'free', 0, NOW())
       ON CONFLICT (user_id) DO NOTHING`,
      [user.userId, user.adminId]
    );
    const r = await db.query(
      `SELECT u.plan_code, u.tokens_used, u.requests, u.token_limit_override, u.period_start,
              p.name AS plan_name, p.token_limit AS plan_limit, p.period AS plan_period
         FROM ai_usage u
         LEFT JOIN ai_plans p ON p.code = u.plan_code AND p.is_active = TRUE
        WHERE u.user_id = $1`,
      [user.userId]
    );
    const row = r.rows[0] || {};
    // A monthly plan whose month is over starts again at 0.
    if (row.plan_period === "month" && row.period_start && addMonth(row.period_start) <= now()) {
      await db.query(
        `UPDATE ai_usage SET tokens_used = 0, requests = 0, period_start = NOW(), updated_at = NOW()
          WHERE user_id = $1`,
        [user.userId]
      );
      row.tokens_used = 0;
      row.period_start = now();
    }
    return row;
  }

  function view(row) {
    const planLimit = row.plan_limit != null ? int(row.plan_limit, freeTokens()) : null;
    const limit =
      row.token_limit_override != null
        ? int(row.token_limit_override, freeTokens())
        : planLimit ?? freeTokens();
    const used = int(row.tokens_used, 0);
    const code = row.plan_code || "free";
    return {
      plan: { code, name: row.plan_name || (code === "free" ? "Free" : code), period: row.plan_period || "lifetime" },
      limit,
      used,
      remaining: Math.max(0, limit - used),
      exhausted: used >= limit,
      ...(row.plan_period === "month" && row.period_start
        ? { resets_at: addMonth(row.period_start).toISOString() }
        : {}),
    };
  }

  /** Usage as the app shows it. */
  async function status(user) {
    return view(await load(user));
  }

  /** Throws 402 when the allowance is used up; else the usage. */
  async function assertCanAsk(user) {
    const u = await status(user);
    if (u.exhausted) {
      const e = new AssistantError("ai_quota_exhausted", 402, QUOTA_MESSAGE);
      e.usage = u;
      throw e;
    }
    return u;
  }

  /** Adds one provider call's tokens (atomic) and logs it. */
  async function record(user, { provider, model, input, output, total, estimated }) {
    await db.query(
      `UPDATE ai_usage
          SET tokens_used = tokens_used + $2, requests = requests + 1,
              last_used_at = NOW(), updated_at = NOW()
        WHERE user_id = $1`,
      [user.userId, total]
    );
    await db.query(
      `INSERT INTO ai_usage_log
         (user_id, admin_id, company_guid, provider, model, input_tokens, output_tokens, total_tokens, estimated)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
      [user.userId, user.adminId, user.company || null, provider, model || null, input, output, total, !!estimated]
    );
  }

  return { status, assertCanAsk, record, freeTokens };
}
