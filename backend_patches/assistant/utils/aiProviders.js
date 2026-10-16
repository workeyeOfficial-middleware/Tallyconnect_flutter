/* =========================================================
   AI PROVIDERS — one adapter per API style, provider list on top.

   Every adapter speaks the same neutral conversation:
     {role: "user", text}
     {role: "assistant", text, calls: [{id, name, args}], raw?}
     {role: "tool", results: [{id, name, result}]}
   and offers:
     listModels(key)                     → ["model-id", …] best first
     chat({key, model, system, messages, tools})
                                         → {text, calls, raw}
   chat also returns usage {input, output, total}: the tokens the provider
   counted for that call (0 when it reports none).
   Tools are given once in a neutral JSON-Schema form and converted per
   provider. The user's key goes only in the provider's auth header (never
   a URL), and HTTP errors carry the status and the provider's own message
   with the key removed. Adding a provider that speaks the OpenAI chat API
   is one entry in PROVIDERS.
========================================================= */
import axios from "axios";

const TIMEOUT_MS = 45000;

export class ProviderHttpError extends Error {
  constructor(status, body, timeout = false) {
    super(timeout ? "AI provider timed out" : `AI provider HTTP ${status ?? "network error"}`);
    this.status = status;
    this.body = body;
    this.timeout = timeout;
  }
}

/** Real HTTP (tests pass their own). Never logs anything. */
export async function httpJson({ method, url, headers, body }) {
  try {
    const res = await axios({
      method,
      url,
      data: body,
      headers: { "Content-Type": "application/json", ...headers },
      timeout: TIMEOUT_MS,
      validateStatus: () => true,
    });
    if (res.status >= 200 && res.status < 300) return res.data;
    throw new ProviderHttpError(res.status, res.data);
  } catch (err) {
    if (err instanceof ProviderHttpError) throw err;
    throw new ProviderHttpError(null, null, err?.code === "ECONNABORTED");
  }
}

/** Gemini-style schema (OBJECT/STRING…) → JSON Schema (object/string…). */
export function toJsonSchema(s) {
  if (!s || typeof s !== "object") return s;
  const out = {};
  for (const [k, v] of Object.entries(s)) {
    if (k === "type" && typeof v === "string") out.type = v.toLowerCase();
    else if (k === "properties" && v && typeof v === "object") {
      out.properties = Object.fromEntries(Object.entries(v).map(([pk, pv]) => [pk, toJsonSchema(pv)]));
    } else if (k === "items") out.items = toJsonSchema(v);
    else out[k] = v;
  }
  if (out.type === "object" && !out.properties) out.properties = {};
  return out;
}

const parseArgs = (s) => {
  if (s && typeof s === "object") return s;
  try {
    return JSON.parse(s || "{}");
  } catch {
    return {};
  }
};

/* ------------------------------------------------------------ Gemini */
function geminiAdapter(p, http) {
  const headers = (key) => ({ "x-goog-api-key": key });
  return {
    async listModels(key) {
      const r = await http({ method: "get", url: `${p.base}/models?pageSize=1000`, headers: headers(key) });
      return rankGemini(r?.models);
    },
    async chat({ key, model, system, messages, tools }) {
      const contents = [];
      for (const m of messages) {
        if (m.role === "user") contents.push({ role: "user", parts: [{ text: m.text }] });
        else if (m.role === "assistant") {
          // The model's own parts (incl. thought signatures) when we have them.
          const parts = m.raw?.gemini || [
            ...(m.text ? [{ text: m.text }] : []),
            ...(m.calls || []).map((c) => ({ functionCall: { name: c.name, args: c.args } })),
          ];
          contents.push({ role: "model", parts });
        } else if (m.role === "tool") {
          contents.push({
            role: "user",
            parts: m.results.map((x) => ({ functionResponse: { name: x.name, response: { result: x.result } } })),
          });
        }
      }
      const body = {
        ...(system ? { systemInstruction: { parts: [{ text: system }] } } : {}),
        contents,
        ...(tools?.length
          ? { tools: [{ functionDeclarations: tools.map((t) => ({ name: t.name, description: t.description, parameters: t.geminiParameters })) }] }
          : {}),
        generationConfig: { temperature: 0.2 },
      };
      const out = await http({
        method: "post",
        url: `${p.base}/models/${encodeURIComponent(model)}:generateContent`,
        headers: headers(key),
        body,
      });
      const cand = out?.candidates?.[0];
      const parts = cand?.content?.parts || [];
      const calls = parts
        .filter((x) => x.functionCall)
        .map((x, i) => ({ id: `g${i}`, name: String(x.functionCall.name || ""), args: x.functionCall.args || {} }));
      const text = parts
        .filter((x) => typeof x.text === "string" && !x.thought)
        .map((x) => x.text)
        .join("")
        .trim();
      const blocked = cand?.finishReason === "SAFETY" || !!out?.promptFeedback?.blockReason;
      const um = out?.usageMetadata || {};
      const usage = {
        input: um.promptTokenCount || 0,
        output: (um.candidatesTokenCount || 0) + (um.thoughtsTokenCount || 0),
        total: um.totalTokenCount || 0,
      };
      return { text, calls, raw: { gemini: parts }, blocked, usage };
    },
  };
}

/** Gemini text models the key can call, best first. */
export function rankGemini(models) {
  const ids = [];
  for (const m of models || []) {
    const id = String(m?.name || "").replace(/^models\//, "");
    if (!/^gemini-/.test(id)) continue;
    if (!(m.supportedGenerationMethods || []).includes("generateContent")) continue;
    if (/(embed|image|tts|audio|live|vision|robotics|computer-use|aqa|learnlm|gemma)/i.test(id)) continue;
    if (!ids.includes(id)) ids.push(id);
  }
  const score = (id) => {
    const v = Number((/^gemini-(\d+(?:\.\d+)?)/.exec(id) || [])[1] || 0);
    let s = v * 100;
    if (/-latest$/.test(id)) s += 10000;
    if (/flash/.test(id)) s += 50;
    if (/lite/.test(id)) s -= 30;
    if (/pro/.test(id)) s += 10;
    if (/(preview|exp|experimental)/.test(id)) s -= 1000;
    if (/-\d{3,}$|-\d{2}-\d{2,4}$/.test(id)) s -= 5;
    return s;
  };
  return ids.sort((a, b) => score(b) - score(a) || a.localeCompare(b));
}

/* --------------------------------------------- OpenAI chat API style */
function openaiAdapter(p, http) {
  const headers = (key) => ({ Authorization: `Bearer ${key}`, ...(p.extraHeaders || {}) });
  return {
    async listModels(key) {
      const r = await http({ method: "get", url: `${p.base}/models`, headers: headers(key) });
      const ids = (r?.data || [])
        .filter((m) => !p.toolsOnly || (m.supported_parameters || []).includes("tools"))
        .map((m) => String(m?.id || ""))
        .filter((id) => id && (!p.include || p.include.test(id)) && !(p.exclude && p.exclude.test(id)));
      const pref = p.preferred || [];
      const rank = (id) => {
        const i = pref.findIndex((re) => re.test(id));
        return i < 0 ? pref.length : i;
      };
      return [...new Set(ids)].sort((a, b) => rank(a) - rank(b) || a.localeCompare(b));
    },
    async chat({ key, model, system, messages, tools }) {
      const msgs = system ? [{ role: "system", content: system }] : [];
      for (const m of messages) {
        if (m.role === "user") msgs.push({ role: "user", content: m.text });
        else if (m.role === "assistant") {
          msgs.push({
            role: "assistant",
            content: m.text || null,
            ...(m.calls?.length
              ? {
                  tool_calls: m.calls.map((c) => ({
                    id: c.id,
                    type: "function",
                    function: { name: c.name, arguments: JSON.stringify(c.args || {}) },
                  })),
                }
              : {}),
          });
        } else if (m.role === "tool") {
          for (const x of m.results) {
            msgs.push({ role: "tool", tool_call_id: x.id, content: JSON.stringify(x.result) });
          }
        }
      }
      const body = {
        model,
        messages: msgs,
        ...(tools?.length
          ? {
              tools: tools.map((t) => ({
                type: "function",
                function: { name: t.name, description: t.description, parameters: t.parameters },
              })),
            }
          : {}),
        ...(p.noTemperature?.test(model) ? {} : { temperature: 0.2 }),
      };
      const out = await http({ method: "post", url: `${p.base}/chat/completions`, headers: headers(key), body });
      const choice = out?.choices?.[0];
      const msg = choice?.message || {};
      const calls = (msg.tool_calls || [])
        .filter((c) => c?.function?.name)
        .map((c, i) => ({ id: String(c.id || `c${i}`), name: String(c.function.name), args: parseArgs(c.function.arguments) }));
      const text = typeof msg.content === "string" ? msg.content.trim() : "";
      const u = out?.usage || {};
      const usage = { input: u.prompt_tokens || 0, output: u.completion_tokens || 0, total: u.total_tokens || 0 };
      return { text, calls, blocked: choice?.finish_reason === "content_filter", usage };
    },
  };
}

/* ------------------------------------------------- Anthropic Messages */
function anthropicAdapter(p, http) {
  const headers = (key) => ({ "x-api-key": key, "anthropic-version": "2023-06-01" });
  return {
    async listModels(key) {
      const r = await http({ method: "get", url: `${p.base}/models?limit=100`, headers: headers(key) });
      const ids = (r?.data || []).map((m) => String(m?.id || "")).filter((id) => /^claude-/.test(id));
      // Newest first as returned; Sonnet before Opus (cost), Haiku last.
      const tier = (id) => (/sonnet/.test(id) ? 0 : /opus/.test(id) ? 1 : /haiku/.test(id) ? 2 : 3);
      return [...new Set(ids)].map((id, i) => ({ id, i })).sort((a, b) => tier(a.id) - tier(b.id) || a.i - b.i).map((x) => x.id);
    },
    async chat({ key, model, system, messages, tools }) {
      const msgs = [];
      for (const m of messages) {
        if (m.role === "user") msgs.push({ role: "user", content: m.text });
        else if (m.role === "assistant") {
          const content = [
            ...(m.text ? [{ type: "text", text: m.text }] : []),
            ...(m.calls || []).map((c) => ({ type: "tool_use", id: c.id, name: c.name, input: c.args || {} })),
          ];
          msgs.push({ role: "assistant", content: content.length ? content : [{ type: "text", text: "" }] });
        } else if (m.role === "tool") {
          msgs.push({
            role: "user",
            content: m.results.map((x) => ({ type: "tool_result", tool_use_id: x.id, content: JSON.stringify(x.result) })),
          });
        }
      }
      const body = {
        model,
        max_tokens: 2048,
        ...(system ? { system } : {}),
        messages: msgs,
        ...(tools?.length
          ? { tools: tools.map((t) => ({ name: t.name, description: t.description, input_schema: t.parameters })) }
          : {}),
        temperature: 0.2,
      };
      const out = await http({ method: "post", url: `${p.base}/messages`, headers: headers(key), body });
      const blocks = out?.content || [];
      const calls = blocks
        .filter((b) => b.type === "tool_use")
        .map((b) => ({ id: String(b.id), name: String(b.name), args: b.input || {} }));
      const text = blocks
        .filter((b) => b.type === "text")
        .map((b) => b.text)
        .join("")
        .trim();
      const u = out?.usage || {};
      const input = (u.input_tokens || 0) + (u.cache_creation_input_tokens || 0) + (u.cache_read_input_tokens || 0);
      const usage = { input, output: u.output_tokens || 0, total: input + (u.output_tokens || 0) };
      return { text, calls, blocked: out?.stop_reason === "refusal", usage };
    },
  };
}

/* --------------------------------------------------- provider list */
/**
 * Providers the app offers. `api` picks the adapter; OpenAI-compatible
 * providers only need a base URL and a model filter.
 */
export const PROVIDERS = {
  gemini: {
    label: "Google Gemini",
    api: "gemini",
    base: "https://generativelanguage.googleapis.com/v1beta",
    keyUrl: "https://aistudio.google.com/apikey",
    keyHint: "AIza… or AQ.…",
  },
  openai: {
    label: "OpenAI (ChatGPT)",
    api: "openai",
    base: "https://api.openai.com/v1",
    keyUrl: "https://platform.openai.com/api-keys",
    keyHint: "sk-…",
    include: /^(gpt-|o\d|chatgpt-)/,
    exclude: /(audio|realtime|transcribe|tts|image|search|embedding|instruct|moderation|dall-e|whisper|codex|computer-use)/,
    preferred: [/^gpt-4\.1-mini$/, /^gpt-4o-mini$/, /^gpt-4\.1$/, /^gpt-4o$/, /^gpt-5-mini$/, /^gpt-5$/, /^o4-mini$/],
    noTemperature: /^(o\d|gpt-5)/,
  },
  anthropic: {
    label: "Anthropic Claude",
    api: "anthropic",
    base: "https://api.anthropic.com/v1",
    keyUrl: "https://console.anthropic.com/settings/keys",
    keyHint: "sk-ant-…",
  },
  groq: {
    label: "Groq",
    api: "openai",
    base: "https://api.groq.com/openai/v1",
    keyUrl: "https://console.groq.com/keys",
    keyHint: "gsk_…",
    exclude: /(whisper|guard|tts|distil|playai|prompt-guard|compound)/,
    preferred: [/llama-3\.3-70b/, /llama-3\.1-8b/, /qwen/, /gpt-oss/],
  },
  openrouter: {
    label: "OpenRouter",
    api: "openai",
    base: "https://openrouter.ai/api/v1",
    keyUrl: "https://openrouter.ai/keys",
    keyHint: "sk-or-…",
    toolsOnly: true,
    preferred: [/^openai\/gpt-4o-mini$/, /^google\/gemini-.*flash/, /^anthropic\/claude-.*sonnet/],
  },
  mistral: {
    label: "Mistral AI",
    api: "openai",
    base: "https://api.mistral.ai/v1",
    keyUrl: "https://console.mistral.ai/api-keys",
    keyHint: "",
    exclude: /(embed|moderation|ocr|pixtral|codestral|voxtral)/,
    preferred: [/^mistral-small-latest$/, /^mistral-medium-latest$/, /^mistral-large-latest$/],
  },
  deepseek: {
    label: "DeepSeek",
    api: "openai",
    base: "https://api.deepseek.com/v1",
    keyUrl: "https://platform.deepseek.com/api_keys",
    keyHint: "sk-…",
    exclude: /reasoner/,
    preferred: [/^deepseek-chat$/],
  },
};

const FACTORIES = { gemini: geminiAdapter, openai: openaiAdapter, anthropic: anthropicAdapter };

/** Adapters for every provider over [http] (tests pass a fake). */
export function createAdapters(http = httpJson, providers = PROVIDERS) {
  const out = {};
  for (const [id, p] of Object.entries(providers)) {
    const f = FACTORIES[p.api];
    if (f) out[id] = { id, ...p, ...f(p, http) };
  }
  return out;
}

/** Public provider list for the app (no internal fields). */
export function providerList(providers = PROVIDERS) {
  return Object.entries(providers).map(([id, p]) => ({
    id,
    label: p.label,
    key_url: p.keyUrl,
    key_hint: p.keyHint,
  }));
}
