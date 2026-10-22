/* =========================================================
   E-INVOICE (Basic) — pure helpers (no database): which sales invoices need
   an e-invoice, each invoice's status, the alerts, and cleaning what the
   Agent sends. The e-invoice itself is created in TallyPrime (Tally is a
   GSP); TallyConnect only shows and tracks what Tally saved.
========================================================= */

/** Days a business with turnover ₹10 crore+ has to report an invoice. */
export const REPORT_DAYS = 30;
/** Largest upload from the Agent. */
export const MAX_ROWS = 1000;

const DAY_MS = 24 * 60 * 60 * 1000;

export const isIsoDate = (s) =>
  typeof s === "string" && /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(Date.parse(`${s}T00:00:00Z`)) &&
  new Date(`${s}T00:00:00Z`).toISOString().slice(0, 10) === s;

/** Whole days from [a] to [b] (YYYY-MM-DD). */
export const daysFrom = (a, b) => Math.round((Date.parse(`${b}T00:00:00Z`) - Date.parse(`${a}T00:00:00Z`)) / DAY_MS);

/** A GSTIN: 15 characters, state code first. */
export const isGstin = (s) => typeof s === "string" && /^[0-9]{2}[A-Z0-9]{13}$/.test(s.trim().toUpperCase());

/** The customer is GST-registered (B2B): a GSTIN and not "Unregistered/Consumer". */
export function isRegisteredParty(r) {
  if (!isGstin(r.party_gstin || "")) return false;
  return !/unregistered|consumer/i.test(String(r.registration_type || ""));
}

/**
 * One invoice's e-invoice status:
 *   done        Tally saved an IRN
 *   cancelled   the IRN was cancelled
 *   pending     needs an e-invoice, none yet (a sale to a GST-registered
 *               customer, not optional / cancelled, GST applicable)
 *   not_needed  everything else (customer without GST, proforma / optional,
 *               purchases, cancelled vouchers, GST not applicable)
 */
export function statusOf(r) {
  if (r.irn) return r.irn_cancelled ? "cancelled" : "done";
  if (!r.is_sale || r.is_optional || r.is_cancelled || r.gst_applicable === false) return "not_needed";
  return isRegisteredParty(r) ? "pending" : "not_needed";
}

/**
 * Alerts on one invoice ([today] YYYY-MM-DD):
 *   overdue       pending for more than 30 days (businesses with turnover
 *                 ₹10 crore+ can no longer report it)
 *   due_soon      pending, 7 days or fewer left of the 30
 *   late_report   e-invoiced more than 30 days after the invoice date
 *   ack_before_invoice  acknowledged before the invoice date (the invoice
 *                 was probably changed or re-dated after e-invoicing)
 */
export function alertsOf(r, today) {
  const st = statusOf(r);
  const d = String(r.voucher_date).slice(0, 10);
  const out = [];
  if (st === "pending") {
    const age = daysFrom(d, today);
    if (age > REPORT_DAYS) out.push("overdue");
    else if (REPORT_DAYS - age <= 7) out.push("due_soon");
  }
  if (r.irn && r.ack_date) {
    const ack = String(r.ack_date).slice(0, 10);
    if (ack < d) out.push("ack_before_invoice");
    else if (daysFrom(d, ack) > REPORT_DAYS) out.push("late_report");
  }
  return out;
}

/** A row as the app gets it (the signed QR only when [withQr]). */
export function rowOut(r, today, withQr = false) {
  const d = String(r.voucher_date).slice(0, 10);
  const st = statusOf(r);
  return {
    voucher_guid: r.voucher_guid,
    date: d,
    voucher_type: r.voucher_type ?? null,
    voucher_no: r.voucher_no ?? null,
    party_name: r.party_name ?? null,
    party_gstin: r.party_gstin ?? null,
    registration_type: r.registration_type ?? null,
    company_gstin: r.company_gstin ?? null,
    place_of_supply: r.place_of_supply ?? null,
    amount: r.amount == null ? null : Number(r.amount),
    status: st,
    irn: r.irn ?? null,
    ack_no: r.ack_no ?? null,
    ack_date: r.ack_date ? String(r.ack_date).slice(0, 10) : null,
    eway_applicable: r.eway_applicable ?? null,
    eway: r.eway ?? null,
    days_since: daysFrom(d, today),
    days_left: st === "pending" ? Math.max(0, REPORT_DAYS - daysFrom(d, today)) : null,
    alerts: alertsOf(r, today),
    ...(withQr ? { signed_qr: r.signed_qr ?? null } : {}),
  };
}

/** Counts per status and per alert. */
export function summarize(rows, today) {
  const c = { total: rows.length, done: 0, pending: 0, cancelled: 0, not_needed: 0, overdue: 0, due_soon: 0, late_report: 0, ack_before_invoice: 0 };
  for (const r of rows) {
    c[statusOf(r)] += 1;
    for (const a of alertsOf(r, today)) c[a] += 1;
  }
  return c;
}

const str = (v, max) => {
  if (v === undefined || v === null) return null;
  const s = String(v).replace(/[\u0000-\u001f]+/g, " ").trim();
  return s ? s.slice(0, max) : null;
};
const bool = (v) => v === true || v === "Yes" || v === "yes" || v === "true";
const optBool = (v) => (v === undefined || v === null || v === "" ? null : bool(v));

/** One row from the Agent, cleaned (null when it cannot be stored). */
export function cleanRow(x) {
  if (!x || typeof x !== "object") return null;
  const guid = str(x.voucher_guid, 120);
  const date = str(x.voucher_date, 10);
  if (!guid || !isIsoDate(date)) return null;
  const amount = Number(x.amount);
  const ack = str(x.ack_date, 10);
  const gstin = str(x.party_gstin, 20);
  let eway = null;
  if (x.eway && typeof x.eway === "object" && !Array.isArray(x.eway)) {
    eway = {};
    for (const [k, v] of Object.entries(x.eway).slice(0, 40)) {
      const kk = str(k, 60);
      const vv = str(v, 200);
      if (kk && vv) eway[kk] = vv;
    }
    if (!Object.keys(eway).length) eway = null;
  }
  return {
    voucher_guid: guid,
    voucher_date: date,
    voucher_type: str(x.voucher_type, 120),
    voucher_no: str(x.voucher_no, 120),
    party_name: str(x.party_name, 255),
    party_gstin: gstin ? gstin.toUpperCase() : null,
    registration_type: str(x.registration_type, 60),
    company_gstin: (str(x.company_gstin, 20) || "").toUpperCase() || null,
    place_of_supply: str(x.place_of_supply, 80),
    amount: Number.isFinite(amount) ? Math.round(Math.abs(amount) * 100) / 100 : null,
    is_sale: bool(x.is_sale),
    is_optional: bool(x.is_optional),
    is_cancelled: bool(x.is_cancelled),
    gst_applicable: optBool(x.gst_applicable),
    irn: str(x.irn, 64),
    ack_no: str(x.ack_no, 30),
    ack_date: isIsoDate(ack) ? ack : null,
    signed_qr: str(x.signed_qr, 4000),
    irn_cancelled: bool(x.irn_cancelled),
    eway_applicable: optBool(x.eway_applicable),
    eway,
  };
}

/** From / To of a list (defaults: this financial year to today). */
export function listRange(q, today) {
  const fyStart = `${Number(today.slice(5, 7)) >= 4 ? today.slice(0, 4) : Number(today.slice(0, 4)) - 1}-04-01`;
  const from = q?.from ? String(q.from) : fyStart;
  const to = q?.to ? String(q.to) : today;
  if (!isIsoDate(from) || !isIsoDate(to)) return { ok: false, message: "Dates must be YYYY-MM-DD" };
  if (from > to) return { ok: false, message: "From must be on or before To" };
  return { ok: true, from, to };
}

export const STATUSES = ["all", "pending", "done", "cancelled", "not_needed", "alerts"];
