/* =========================================================
   OUTSTANDING EMAIL REMINDERS — pure helpers (no database, no network)
   Validation, configuration, template rendering and the reminder email.
   Kept free of dependencies so it can be unit-tested on its own.
========================================================= */
import { createHash } from "node:crypto";

export const MAX_BILLS = 50;
export const MAX_TEMPLATES = 20;
export const MAX_SUBJECT = 200;
export const MAX_BODY = 5000;
export const MAX_NAME = 80;
export const MAX_RECIPIENTS = 5;

/** Placeholders a template may use (shown in the template editor). */
export const PLACEHOLDERS = ["party", "company", "bills", "total", "count", "sender"];

/** Built-in template, used when the account has none of its own. */
export const DEFAULT_TEMPLATE = Object.freeze({
  id: null,
  name: "Standard reminder",
  subject: "Payment reminder from {{company}} · {{total}} outstanding",
  body:
    "Dear {{party}},\n\n" +
    "This is a friendly reminder that the following {{count}} bill(s) are pending " +
    "in our books:\n\n{{bills}}\n\nTotal outstanding: {{total}}\n\n" +
    "Please arrange the payment at the earliest. If you have already paid, " +
    "kindly ignore this email or reply with the payment details.\n\n" +
    "Regards,\n{{sender}}\n{{company}}",
  is_default: true,
});

const EMAIL_RE = /^[^\s@<>()",;:]+@[^\s@<>()",;:]+\.[^\s@<>()",;:]+$/;

/** Control characters except tab / newline removed; CRLF → LF. */
export function cleanText(s) {
  return String(s ?? "")
    .replace(/\r\n?/g, "\n")
    // eslint-disable-next-line no-control-regex
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, "")
    .trim();
}

/** One line, no header injection, at most [max] characters. */
export function oneLine(s, max = MAX_SUBJECT) {
  return String(s ?? "").replace(/[\r\n\t]+/g, " ").replace(/\s{2,}/g, " ").trim().slice(0, max);
}

export function escapeHtml(s) {
  return String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function intEnv(v, def, min, max) {
  const n = Number.parseInt(String(v ?? ""), 10);
  return Number.isInteger(n) && n >= min && n <= max ? n : def;
}

/** Settings from the environment (read on every request: no restart cache). */
export function reminderConfig(env = process.env) {
  const mailReady = Boolean(
    env.MICROSOFT_TENANT_ID &&
      env.MICROSOFT_CLIENT_ID &&
      env.MICROSOFT_CLIENT_SECRET &&
      env.MICROSOFT_SENDER_EMAIL
  );
  return {
    mailReady,
    // Per signed-in user.
    perHour: intEnv(env.REMINDER_RATE_LIMIT_PER_HOUR, 20, 1, 1000),
    // Per account (admin and all its users together).
    perDay: intEnv(env.REMINDER_RATE_LIMIT_PER_DAY, 200, 1, 100000),
    // Same party + same bills again within this many minutes → refused.
    duplicateMinutes: intEnv(env.REMINDER_DUPLICATE_WINDOW_MINUTES, 60, 0, 10080),
  };
}

/** Valid, distinct email addresses in a ledger's (free text) email field. */
export function recipientsOf(raw) {
  const out = [];
  for (const part of String(raw ?? "").split(/[,;\s]+/)) {
    const e = part.trim().replace(/^mailto:/i, "");
    if (!EMAIL_RE.test(e) || e.length > 320) continue;
    if (!out.some((x) => x.toLowerCase() === e.toLowerCase())) out.push(e);
    if (out.length >= MAX_RECIPIENTS) break;
  }
  return out;
}

export function isEmail(s) {
  return EMAIL_RE.test(String(s ?? "").trim());
}

/**
 * Validates the bill selection of preview / send. Only the ledger and the
 * bill references come from the app; amounts and dates are read on the
 * server. `expected_total` (optional) is what the user confirmed on the
 * preview — used only to notice that Tally data changed in between.
 */
export function validateSelection(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return { ok: false, message: "Invalid request body" };
  }
  const ledgerGuid = typeof body.ledger_guid === "string" ? body.ledger_guid.trim() : "";
  if (!ledgerGuid || ledgerGuid.length > 100) {
    return { ok: false, message: "ledger_guid is required" };
  }
  if (!Array.isArray(body.bill_names) || body.bill_names.length === 0) {
    return { ok: false, message: "Select at least one bill" };
  }
  const names = [];
  for (const n of body.bill_names) {
    if (typeof n !== "string") return { ok: false, message: "bill_names must be text" };
    const t = n.trim();
    if (!t || t.length > 200) return { ok: false, message: "A bill reference is not valid" };
    if (!names.includes(t)) names.push(t);
  }
  if (names.length > MAX_BILLS) {
    return { ok: false, message: `At most ${MAX_BILLS} bills in one reminder` };
  }
  let templateId = null;
  if (body.template_id !== undefined && body.template_id !== null && body.template_id !== "") {
    const id = Number(body.template_id);
    if (!Number.isInteger(id) || id <= 0) return { ok: false, message: "template_id is not valid" };
    templateId = id;
  }
  let expectedTotal = null;
  if (body.expected_total !== undefined && body.expected_total !== null) {
    const t = Number(body.expected_total);
    if (!Number.isFinite(t)) return { ok: false, message: "expected_total is not valid" };
    expectedTotal = t;
  }
  let key = null;
  if (body.idempotency_key !== undefined && body.idempotency_key !== null) {
    const k = String(body.idempotency_key).trim();
    if (!/^[A-Za-z0-9_-]{8,80}$/.test(k)) {
      return { ok: false, message: "idempotency_key is not valid" };
    }
    key = k;
  }
  return { ok: true, value: { ledgerGuid, billNames: names, templateId, expectedTotal, key } };
}

/** Validates a template create / update. */
export function validateTemplate(body, { partial = false } = {}) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return { ok: false, message: "Invalid request body" };
  }
  const out = {};
  if (body.name !== undefined || !partial) {
    const name = oneLine(body.name, 1000);
    if (!name) return { ok: false, message: "Template name is required" };
    if (name.length > MAX_NAME) {
      return { ok: false, message: `Template name must be at most ${MAX_NAME} characters` };
    }
    out.name = name;
  }
  if (body.subject !== undefined || !partial) {
    const subject = oneLine(body.subject, 1000);
    if (!subject) return { ok: false, message: "Subject is required" };
    if (subject.length > MAX_SUBJECT) {
      return { ok: false, message: `Subject must be at most ${MAX_SUBJECT} characters` };
    }
    out.subject = subject;
  }
  if (body.body !== undefined || !partial) {
    const text = cleanText(body.body);
    if (!text) return { ok: false, message: "Message is required" };
    if (text.length > MAX_BODY) {
      return { ok: false, message: `Message must be at most ${MAX_BODY} characters` };
    }
    out.body = text;
  }
  if (body.is_default !== undefined) out.isDefault = body.is_default === true;
  const unknown = [...`${out.subject ?? ""} ${out.body ?? ""}`.matchAll(/\{\{\s*([^}]*?)\s*\}\}/g)]
    .map((m) => m[1])
    .filter((p) => !PLACEHOLDERS.includes(p));
  if (unknown.length) {
    return {
      ok: false,
      message: `Unknown placeholder {{${unknown[0]}}}. Use: ${PLACEHOLDERS.map((p) => `{{${p}}}`).join(", ")}`,
    };
  }
  if (partial && Object.keys(out).length === 0) {
    return { ok: false, message: "Nothing to update" };
  }
  return { ok: true, value: out };
}

/** Rupees with Indian grouping: ₹1,23,456.78. */
export function inr(n) {
  const v = Math.round(Number(n || 0) * 100) / 100;
  return `₹${v.toLocaleString("en-IN", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

/** A pg DATE / timestamp / ISO text → "YYYY-MM-DD" (calendar date only). */
export function isoDate(d) {
  if (d === null || d === undefined || d === "") return null;
  if (d instanceof Date) {
    if (Number.isNaN(d.getTime())) return null;
    const p = (x) => String(x).padStart(2, "0");
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
  }
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(d));
  return m ? `${m[1]}-${m[2]}-${m[3]}` : null;
}

/** "YYYY-MM-DD" → "DD-MM-YYYY"; nothing → "—". */
export function dmy(iso) {
  if (!iso) return "—";
  const [y, m, d] = iso.split("-");
  return `${d}-${m}-${y}`;
}

/** Bill rows from the database → the reminder's bills (amounts in paise-safe numbers). */
export function normaliseBills(rows, today = new Date()) {
  const todayIso = isoDate(today);
  return rows.map((r) => {
    const due = isoDate(r.due_date);
    const overdue =
      due && todayIso && due < todayIso
        ? Math.round((Date.parse(todayIso) - Date.parse(due)) / 86400000)
        : 0;
    return {
      bill_name: String(r.bill_name),
      bill_date: isoDate(r.bill_date),
      due_date: due,
      pending_amount: Math.round(Number(r.pending_amount) * 100) / 100,
      overdue_days: overdue,
    };
  });
}

export function totalOf(bills) {
  return Math.round(bills.reduce((s, b) => s + b.pending_amount * 100, 0)) / 100;
}

/** Same bills (in any order) → same key; used to refuse duplicates. */
export function billSetKey(names) {
  return createHash("sha256")
    .update(JSON.stringify([...names].sort()))
    .digest("hex")
    .slice(0, 32);
}

function fill(text, values) {
  return text.replace(/\{\{\s*([a-z]+)\s*\}\}/g, (m, k) =>
    Object.prototype.hasOwnProperty.call(values, k) ? values[k] : m
  );
}

/**
 * The reminder email. Every value from Tally or the template is escaped;
 * the subject is one line (no header injection).
 * @returns {{subject: string, html: string, text: string}}
 */
export function buildReminderEmail({ template, party, company, sender, bills }) {
  const total = inr(totalOf(bills));
  const plainValues = {
    party: oneLine(party, 200),
    company: oneLine(company || "", 200),
    sender: oneLine(sender || "", 200),
    total,
    count: String(bills.length),
  };
  const subject = oneLine(fill(template.subject, { ...plainValues, bills: "" }));

  const textBills = bills
    .map(
      (b) =>
        `• ${b.bill_name} · due ${dmy(b.due_date)} · ${inr(b.pending_amount)}` +
        (b.overdue_days > 0 ? ` (${b.overdue_days} days overdue)` : "")
    )
    .join("\n");
  const text = fill(template.body, { ...plainValues, bills: textBills });

  const th = (s, right) =>
    `<th style="text-align:${right ? "right" : "left"};padding:8px 10px;border-bottom:1px solid #e5e7eb;color:#556;font-weight:600">${s}</th>`;
  const td = (s, right) =>
    `<td style="text-align:${right ? "right" : "left"};padding:8px 10px;border-bottom:1px solid #f0f1f3;color:#111">${s}</td>`;
  const tableRows = bills
    .map(
      (b) =>
        `<tr>${td(escapeHtml(b.bill_name))}${td(escapeHtml(dmy(b.bill_date)))}` +
        `${td(escapeHtml(dmy(b.due_date)) + (b.overdue_days > 0 ? `<br><span style="color:#b42318;font-size:12px">${b.overdue_days} days overdue</span>` : ""))}` +
        `${td(escapeHtml(inr(b.pending_amount)), true)}</tr>`
    )
    .join("");
  const htmlTable =
    `<table style="width:100%;border-collapse:collapse;font-size:14px;margin:8px 0">` +
    `<tr>${th("Bill")}${th("Bill date")}${th("Due date")}${th("Pending", true)}</tr>${tableRows}` +
    `<tr><td colspan="3" style="padding:10px;font-weight:700;color:#111">Total</td>` +
    `<td style="padding:10px;text-align:right;font-weight:700;color:#111">${escapeHtml(total)}</td></tr></table>`;

  const htmlValues = Object.fromEntries(
    Object.entries(plainValues).map(([k, v]) => [k, escapeHtml(v)])
  );
  // Escape the template text first, then put the values in: a template or
  // a ledger name can never inject markup.
  const bodyHtml = fill(escapeHtml(template.body), { ...htmlValues, bills: "\u0000BILLS\u0000" })
    .split("\u0000BILLS\u0000")
    .map((chunk) => `<div style="white-space:pre-wrap">${chunk}</div>`)
    .join(htmlTable);

  const html = `
<div style="font-family:Arial,sans-serif;background:#f4f6f8;padding:24px">
  <div style="max-width:640px;margin:0 auto;background:#fff;border-radius:12px;overflow:hidden;border:1px solid #e5e7eb">
    <div style="background:#8C1D3F;color:#fff;padding:16px 20px;font-size:18px;font-weight:bold">${escapeHtml(plainValues.company || "Payment reminder")}</div>
    <div style="padding:20px;font-size:15px;line-height:1.5;color:#111">${bodyHtml}</div>
  </div>
</div>`;
  return { subject, html, text };
}

/** A reminder_log row → API shape (no internal columns). */
export function publicLog(r) {
  return {
    id: Number(r.id),
    ledger_guid: r.ledger_guid,
    party: r.ledger_name,
    recipients: r.recipients || [],
    subject: r.subject,
    bills: r.bills || [],
    total: Number(r.total_amount),
    status: r.status,
    error: r.error || null,
    attempts: Number(r.attempts || 0),
    sent_by: r.sent_by_email || r.sent_by_name || null,
    created_at: r.created_at,
    sent_at: r.sent_at || null,
  };
}

/* ---------------------------------------------- reminder settings
   Per account and company (set by the admin): when outstanding reminders
   are due — before the due date, after it, or both — and whether the
   server emails them by itself (automatic) or the team sends them
   (manual). Hours are India time (IST). */

export const REMINDER_MODES = ["manual", "automatic"];
export const REMINDER_TIMINGS = ["before", "after", "both"];

export const DEFAULT_SETTINGS = Object.freeze({
  mode: "manual",
  timing: "before",
  before_days: 3,
  after_days: 1,
  repeat_days: 0, // 0 = once after the due date; else again every N days
  send_hour: 10,
});

const intIn = (v, min, max) => {
  const n = typeof v === "number" ? v : Number.parseInt(String(v ?? ""), 10);
  return Number.isInteger(n) && n >= min && n <= max ? n : null;
};

/** Checks a settings body; every field is required. */
export function validateSettings(body) {
  const b = body && typeof body === "object" ? body : {};
  if (!REMINDER_MODES.includes(b.mode)) return { ok: false, message: "Mode must be automatic or manual." };
  if (!REMINDER_TIMINGS.includes(b.timing)) return { ok: false, message: "Choose before, after or both." };
  const before = intIn(b.before_days, 1, 60);
  const after = intIn(b.after_days, 1, 90);
  const repeat = intIn(b.repeat_days ?? 0, 0, 30);
  const hour = intIn(b.send_hour, 0, 23);
  if (before === null) return { ok: false, message: "Days before the due date: 1 to 60." };
  if (after === null) return { ok: false, message: "Days after the due date: 1 to 90." };
  if (repeat === null) return { ok: false, message: "Repeat every: 0 (once) to 30 days." };
  if (hour === null) return { ok: false, message: "Time: an hour from 0 to 23." };
  return {
    ok: true,
    value: { mode: b.mode, timing: b.timing, before_days: before, after_days: after, repeat_days: repeat, send_hour: hour },
  };
}

/** A stored row (or nothing) → the settings in use. */
export function settingsOf(row) {
  if (!row) return { ...DEFAULT_SETTINGS };
  const v = validateSettings(row);
  return v.ok ? v.value : { ...DEFAULT_SETTINGS };
}

/** Today's date and hour in India time: { today: "YYYY-MM-DD", hour }. */
export function istNow(now = new Date()) {
  const t = new Date(now.getTime() + 330 * 60000);
  return { today: t.toISOString().slice(0, 10), hour: t.getUTCHours() };
}

/**
 * Is a bill due for a reminder on [todayIso] by [s]? "before" (N days before
 * its due date), "after" (N days after it, then every repeat_days), or null.
 */
export function reminderDue(s, dueIso, todayIso) {
  const due = isoDate(dueIso);
  if (!due || !todayIso) return null;
  const days = Math.round((Date.parse(due) - Date.parse(todayIso)) / 86400000);
  if ((s.timing === "before" || s.timing === "both") && days === s.before_days) return "before";
  if (s.timing === "after" || s.timing === "both") {
    const over = -days;
    if (over === s.after_days) return "after";
    if (s.repeat_days > 0 && over > s.after_days && (over - s.after_days) % s.repeat_days === 0) return "after";
  }
  return null;
}

/** Idempotency key of the automatic reminder of one party's bills on a day. */
export function autoKey(company, ledgerGuid, set, todayIso) {
  const h = createHash("sha256").update(`${company}|${ledgerGuid}|${set}`).digest("hex").slice(0, 32);
  return `auto:${todayIso}:${h}`;
}
