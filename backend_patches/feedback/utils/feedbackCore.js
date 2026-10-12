/* =========================================================
   FEEDBACK — pure helpers (no database, no network)
   Validation, configuration, admin check and the notification email.
   Kept free of dependencies so it can be unit-tested on its own.
========================================================= */

export const FEEDBACK_TYPES = ["feedback", "bug", "idea"];
export const FEEDBACK_STATUSES = ["new", "seen", "resolved"];
export const MAX_MESSAGE = 1000;
export const MAX_NOTE = 2000;

const TYPE_LABEL = { feedback: "Feedback", bug: "Bug report", idea: "Suggestion" };
const EMAIL_RE = /^[^\s@<>()",;]+@[^\s@<>()",;]+\.[^\s@<>()",;]+$/;

/** Control characters except tab / newline removed; CRLF → LF. */
function cleanText(s) {
  return String(s)
    .replace(/\r\n?/g, "\n")
    // eslint-disable-next-line no-control-regex
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, "")
    .trim();
}

/**
 * Validates POST /api/feedback. Unknown fields are ignored; the user,
 * account and company never come from the body.
 * @returns {{ok: true, value: object} | {ok: false, message: string}}
 */
export function validateFeedback(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return { ok: false, message: "Invalid request body" };
  }
  const type = typeof body.type === "string" ? body.type.trim().toLowerCase() : "";
  if (!FEEDBACK_TYPES.includes(type)) {
    return { ok: false, message: "type must be one of: feedback, bug, idea" };
  }
  if (typeof body.message !== "string") {
    return { ok: false, message: "message is required" };
  }
  const message = cleanText(body.message);
  if (message.length === 0) return { ok: false, message: "message is required" };
  if (message.length > MAX_MESSAGE) {
    return { ok: false, message: `message must be at most ${MAX_MESSAGE} characters` };
  }

  let rating = null;
  if (body.rating !== undefined && body.rating !== null && body.rating !== "") {
    const r = Number(body.rating);
    if (!Number.isInteger(r) || r < 1 || r > 5) {
      return { ok: false, message: "rating must be a whole number from 1 to 5" };
    }
    rating = r;
  }
  if (type === "bug") rating = null; // bug reports are not rated

  let appVersion = null;
  if (body.app_version !== undefined && body.app_version !== null && body.app_version !== "") {
    const v = String(body.app_version).trim();
    if (v.length > 40 || !/^[0-9A-Za-z.+\-_ ]+$/.test(v)) {
      return { ok: false, message: "app_version is not valid" };
    }
    appVersion = v;
  }

  let platform = null;
  if (body.platform !== undefined && body.platform !== null && body.platform !== "") {
    const p = cleanText(body.platform).replace(/\n/g, " ");
    if (p.length > 120) return { ok: false, message: "platform is too long" };
    platform = p || null;
  }

  return { ok: true, value: { type, rating, message, appVersion, platform } };
}

/** Validates PATCH /api/admin/feedback/:id. */
export function validateAdminUpdate(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return { ok: false, message: "Invalid request body" };
  }
  const out = {};
  if (body.status !== undefined) {
    if (!FEEDBACK_STATUSES.includes(body.status)) {
      return { ok: false, message: "status must be one of: new, seen, resolved" };
    }
    out.status = body.status;
  }
  if (body.admin_note !== undefined) {
    if (body.admin_note !== null && typeof body.admin_note !== "string") {
      return { ok: false, message: "admin_note must be text" };
    }
    const n = body.admin_note === null ? null : cleanText(body.admin_note);
    if (n && n.length > MAX_NOTE) {
      return { ok: false, message: `admin_note must be at most ${MAX_NOTE} characters` };
    }
    out.adminNote = n || null;
  }
  if (out.status === undefined && out.adminNote === undefined) {
    return { ok: false, message: "Nothing to update (status or admin_note)" };
  }
  return { ok: true, value: out };
}

function intEnv(v, def, min, max) {
  const n = Number.parseInt(String(v ?? ""), 10);
  return Number.isInteger(n) && n >= min && n <= max ? n : def;
}

/** Settings from the environment (read on every request: no restart cache). */
export function feedbackConfig(env = process.env) {
  const notify = String(env.FEEDBACK_NOTIFICATION_EMAIL || "").trim();
  const admins = String(env.FEEDBACK_ADMIN_EMAILS || "")
    .split(",")
    .map((s) => s.trim().toLowerCase())
    .filter((s) => EMAIL_RE.test(s));
  return {
    notifyEmail: EMAIL_RE.test(notify) ? notify : null,
    adminEmails: admins,
    perHour: intEnv(env.FEEDBACK_RATE_LIMIT_PER_HOUR, 5, 1, 1000),
    perDay: intEnv(env.FEEDBACK_RATE_LIMIT_PER_DAY, 20, 1, 10000),
  };
}

/** Feedback review is only for the TallyConnect team (allow-listed emails). */
export function isFeedbackAdmin(user, cfg) {
  const email = String(user?.email || "").trim().toLowerCase();
  return email.length > 0 && cfg.adminEmails.includes(email);
}

export function escapeHtml(s) {
  return String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/** One line, no header injection, at most [max] characters. */
function oneLine(s, max = 200) {
  return String(s ?? "").replace(/[\r\n]+/g, " ").trim().slice(0, max);
}

/** Notification email for one stored feedback row. */
export function buildFeedbackEmail(row) {
  const label = TYPE_LABEL[row.type] || "Feedback";
  const who = row.user_email || row.username || `user ${row.user_id}`;
  const stars = row.rating ? `${"★".repeat(row.rating)}${"☆".repeat(5 - row.rating)} (${row.rating}/5)` : "—";
  const subject = oneLine(
    `[TallyConnect] ${label} #${row.id} from ${who}${row.rating ? ` · ${row.rating}/5` : ""}`
  );
  const when = row.created_at ? new Date(row.created_at).toISOString() : "";
  const facts = [
    ["Type", label],
    ["Rating", stars],
    ["From", who],
    ["Username", row.username || "—"],
    ["Role", row.role || "—"],
    ["User ID", row.user_id ?? "—"],
    ["Account (admin) ID", row.admin_id ?? "—"],
    ["Active company", row.company_guid || "—"],
    ["App version", row.app_version || "—"],
    ["Platform", row.platform || "—"],
    ["Received", when || "—"],
    ["Feedback ID", row.id],
  ];
  const rows = facts
    .map(
      ([k, v]) =>
        `<tr><td style="padding:4px 12px 4px 0;color:#667;white-space:nowrap">${escapeHtml(k)}</td>` +
        `<td style="padding:4px 0;color:#111">${escapeHtml(v)}</td></tr>`
    )
    .join("");
  const html = `
<div style="font-family:Arial,sans-serif;background:#f4f6f8;padding:24px">
  <div style="max-width:620px;margin:0 auto;background:#fff;border-radius:12px;overflow:hidden;border:1px solid #e5e7eb">
    <div style="background:#8C1D3F;color:#fff;padding:16px 20px;font-size:18px;font-weight:bold">
      TallyConnect · ${escapeHtml(label)}
    </div>
    <div style="padding:20px">
      <div style="white-space:pre-wrap;font-size:15px;line-height:1.5;color:#111;background:#f8fafc;border:1px solid #e5e7eb;border-radius:8px;padding:12px 14px">${escapeHtml(row.message)}</div>
      <table style="margin-top:16px;font-size:13px;border-collapse:collapse">${rows}</table>
      <p style="margin-top:16px;font-size:12px;color:#889">Reply to this email to answer the customer.</p>
    </div>
  </div>
</div>`;
  return { subject, html };
}

/** Paging for the admin list. */
export function parsePaging(query) {
  const page = intEnv(query?.page, 1, 1, 100000);
  const limit = intEnv(query?.limit, 25, 1, 100);
  return { page, limit, offset: (page - 1) * limit };
}
