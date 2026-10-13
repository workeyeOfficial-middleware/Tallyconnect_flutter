/* =========================================================
   OUTSTANDING REMINDER email — same Microsoft Graph sender the
   password-reset and feedback emails use (MICROSOFT_TENANT_ID,
   MICROSOFT_CLIENT_ID, MICROSOFT_CLIENT_SECRET, MICROSOFT_SENDER_EMAIL).

   Returns what Microsoft Graph answered. Graph's sendMail answers
   202 Accepted: the message was accepted for delivery — it does NOT
   confirm that it reached the inbox. Throws on any failure (err.code =
   "not_configured" when the variables are missing); never logs secrets.
========================================================= */
import axios from "axios";

const TIMEOUT_MS = 15000;

export class MailError extends Error {
  constructor(message, code, status) {
    super(message);
    this.code = code;
    this.status = status ?? null;
  }
}

async function getAccessToken(env) {
  const body = new URLSearchParams({
    client_id: env.MICROSOFT_CLIENT_ID,
    scope: "https://graph.microsoft.com/.default",
    client_secret: env.MICROSOFT_CLIENT_SECRET,
    grant_type: "client_credentials",
  });
  const res = await axios.post(
    `https://login.microsoftonline.com/${encodeURIComponent(env.MICROSOFT_TENANT_ID)}/oauth2/v2.0/token`,
    body.toString(),
    { headers: { "Content-Type": "application/x-www-form-urlencoded" }, timeout: TIMEOUT_MS }
  );
  return res.data.access_token;
}

/**
 * @param {{to: string[], subject: string, html: string, replyTo?: string|null}} m
 * @returns {Promise<{provider: string, status: number, requestId: string|null}>}
 */
export async function sendReminderEmail({ to, subject, html, replyTo }, env = process.env) {
  if (
    !env.MICROSOFT_TENANT_ID ||
    !env.MICROSOFT_CLIENT_ID ||
    !env.MICROSOFT_CLIENT_SECRET ||
    !env.MICROSOFT_SENDER_EMAIL
  ) {
    throw new MailError(
      "Email sending is not configured on the server (MICROSOFT_* variables)",
      "not_configured"
    );
  }
  try {
    const token = await getAccessToken(env);
    const message = {
      subject,
      body: { contentType: "HTML", content: html },
      toRecipients: to.map((address) => ({ emailAddress: { address } })),
    };
    if (replyTo) message.replyTo = [{ emailAddress: { address: replyTo } }];
    const res = await axios.post(
      `https://graph.microsoft.com/v1.0/users/${encodeURIComponent(env.MICROSOFT_SENDER_EMAIL)}/sendMail`,
      { message, saveToSentItems: true },
      {
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        timeout: TIMEOUT_MS,
      }
    );
    return {
      provider: "microsoft-graph",
      status: res.status,
      requestId: res.headers?.["request-id"] || null,
    };
  } catch (err) {
    const status = err.response?.status ?? null;
    const detail = err.response?.data?.error?.message || err.message || "unknown error";
    throw new MailError(
      `Microsoft Graph refused the email${status ? ` (HTTP ${status})` : ""}: ${detail}`,
      "provider_error",
      status
    );
  }
}
