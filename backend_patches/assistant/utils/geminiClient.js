/* =========================================================
   Gemini REST client (generativelanguage.googleapis.com).
   The key travels only in the `x-goog-api-key` header — never in a URL,
   so it cannot end up in proxy / access logs — and errors are reduced to
   a status + Google's error body (the request config, which holds the key,
   is dropped).
========================================================= */
import axios from "axios";

const BASE = "https://generativelanguage.googleapis.com/v1beta";
const TIMEOUT_MS = 45000;

export class GeminiHttpError extends Error {
  constructor(status, body, timeout = false) {
    super(timeout ? "Gemini timed out" : `Gemini HTTP ${status ?? "network error"}`);
    this.status = status;
    this.body = body;
    this.timeout = timeout;
  }
}

async function call(method, path, key, data) {
  try {
    const res = await axios({
      method,
      url: `${BASE}${path}`,
      data,
      headers: { "x-goog-api-key": key, "Content-Type": "application/json" },
      timeout: TIMEOUT_MS,
      validateStatus: () => true,
    });
    if (res.status >= 200 && res.status < 300) return res.data;
    throw new GeminiHttpError(res.status, res.data);
  } catch (err) {
    if (err instanceof GeminiHttpError) throw err;
    throw new GeminiHttpError(null, null, err?.code === "ECONNABORTED");
  }
}

/** Real Gemini calls (the router takes any object with these two methods). */
export const gemini = {
  /** Models this key can use (`models[].name`, `supportedGenerationMethods`). */
  listModels: (key) => call("get", "/models?pageSize=1000", key),
  generate: (key, model, body) =>
    call("post", `/models/${encodeURIComponent(model)}:generateContent`, key, body),
};
