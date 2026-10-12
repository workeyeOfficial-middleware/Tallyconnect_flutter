/* =========================================================
   FEEDBACK notification email — same Microsoft Graph sender the
   password-reset email uses (MICROSOFT_TENANT_ID, MICROSOFT_CLIENT_ID,
   MICROSOFT_CLIENT_SECRET, MICROSOFT_SENDER_EMAIL). Throws on failure so
   the caller can record it; never logs secrets.
========================================================= */
import axios from "axios";

const TIMEOUT_MS = 15000;

async function getAccessToken() {
  const tenant = process.env.MICROSOFT_TENANT_ID;
  const clientId = process.env.MICROSOFT_CLIENT_ID;
  const secret = process.env.MICROSOFT_CLIENT_SECRET;
  if (!tenant || !clientId || !secret) {
    throw new Error("Microsoft Graph mail is not configured (MICROSOFT_* variables)");
  }
  const body = new URLSearchParams({
    client_id: clientId,
    scope: "https://graph.microsoft.com/.default",
    client_secret: secret,
    grant_type: "client_credentials",
  });
  const res = await axios.post(
    `https://login.microsoftonline.com/${encodeURIComponent(tenant)}/oauth2/v2.0/token`,
    body.toString(),
    { headers: { "Content-Type": "application/x-www-form-urlencoded" }, timeout: TIMEOUT_MS }
  );
  return res.data.access_token;
}

/**
 * @param {{to: string, subject: string, html: string, replyTo?: string|null}} m
 */
export async function sendFeedbackEmail({ to, subject, html, replyTo }) {
  const sender = process.env.MICROSOFT_SENDER_EMAIL;
  if (!sender) throw new Error("MICROSOFT_SENDER_EMAIL is not set");
  try {
    const token = await getAccessToken();
    const message = {
      subject,
      body: { contentType: "HTML", content: html },
      toRecipients: [{ emailAddress: { address: to } }],
    };
    if (replyTo) message.replyTo = [{ emailAddress: { address: replyTo } }];
    await axios.post(
      `https://graph.microsoft.com/v1.0/users/${encodeURIComponent(sender)}/sendMail`,
      { message, saveToSentItems: false },
      {
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        timeout: TIMEOUT_MS,
      }
    );
  } catch (err) {
    const detail = err.response?.data?.error?.message || err.message || "unknown error";
    throw new Error(`Feedback email failed: ${detail}`);
  }
}
