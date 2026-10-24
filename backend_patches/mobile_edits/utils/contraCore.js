/* =========================================================
   MOBILE CONTRA ENTRY — money moved between cash and bank accounts
   (cash deposit, cash withdrawal, bank → bank transfer).

   POST /api/mobile-voucher-command/contra/create
   {
     voucher_date: "YYYY-MM-DD",          required
     from_account: "Cash",                 required — money goes out of it
     to_account:   "HDFC Bank",            required — money comes into it
     amount:       5000,                   required, > 0
     voucher_no?, narration?, instrument_no? (cheque / UTR no.)
   }

   Queued in mobile_sync_queue exactly like the Journal entry (entity_type
   VOUCHER, action CREATE, payload JSON); the Agent posts it to Tally as a
   Contra voucher: to_account Dr, from_account Cr. The Agent checks that both
   accounts exist in Tally and are cash / bank accounts.

   No dependencies here (database and notifications are passed in), so it
   is testable with plain `node --test`.
========================================================= */
import crypto from "crypto";

const DATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/;
const MAX_AMOUNT = 1e12;

const text = (v) => (typeof v === "string" ? v.trim() : v == null ? "" : String(v).trim());

/** Rupees rounded to paise. */
const paise = (n) => Math.round(n * 100) / 100;

function validDate(s) {
  const m = DATE_RE.exec(s);
  if (!m) return false;
  const d = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3]));
  return d.getUTCFullYear() === +m[1] && d.getUTCMonth() === +m[2] - 1 && d.getUTCDate() === +m[3];
}

/**
 * Checks the request body.
 * @returns {{ error: string } | { value: object }}
 */
export function validateContra(body) {
  const b = body && typeof body === "object" ? body : {};
  const voucher_date = text(b.voucher_date).split("T")[0];
  const from_account = text(b.from_account);
  const to_account = text(b.to_account);
  const voucher_no = text(b.voucher_no);
  const narration = text(b.narration);
  const instrument_no = text(b.instrument_no);
  const amount = typeof b.amount === "number" ? b.amount : Number(text(b.amount));

  if (!voucher_date) return { error: "voucher_date is required" };
  if (!validDate(voucher_date)) return { error: "voucher_date must be a date (YYYY-MM-DD)" };
  if (!from_account) return { error: "from_account is required (the cash / bank account money goes out of)" };
  if (!to_account) return { error: "to_account is required (the cash / bank account money comes into)" };
  if (from_account.toLowerCase() === to_account.toLowerCase()) {
    return { error: "from_account and to_account must be different accounts" };
  }
  if (from_account.length > 200 || to_account.length > 200) return { error: "Account name is too long" };
  if (!Number.isFinite(amount) || amount <= 0) return { error: "amount must be greater than 0" };
  if (amount > MAX_AMOUNT) return { error: "amount is too large" };
  if (paise(amount) <= 0) return { error: "amount must be at least ₹0.01" };
  if (voucher_no.length > 50) return { error: "voucher_no is too long" };
  if (instrument_no.length > 60) return { error: "instrument_no is too long" };
  if (narration.length > 1000) return { error: "narration is too long" };

  return {
    value: {
      voucher_date,
      from_account,
      to_account,
      amount: paise(amount),
      voucher_no: voucher_no || null,
      narration,
      instrument_no: instrument_no || null,
    },
  };
}

/** The queue payload (the Agent's contract, same shape as Journal). */
export function buildContraPayload(v, { guid, now }) {
  return {
    voucher_guid: guid,
    voucher_type: "Contra",
    voucher_date: v.voucher_date,
    voucher_no: v.voucher_no,
    reference_no: v.instrument_no || `MOBILE-CONTRA-${now.getTime()}`,
    narration: v.narration,
    transfer: {
      from_account: v.from_account,
      to_account: v.to_account,
      amount: v.amount,
      instrument_no: v.instrument_no,
    },
    ledger_entries: [
      { ledger_name: v.to_account, amount: v.amount, is_debit: true },
      { ledger_name: v.from_account, amount: v.amount, is_debit: false },
    ],
    total_debit: v.amount,
    total_credit: v.amount,
  };
}

export function hashPayload(payload) {
  return crypto.createHash("sha256").update(JSON.stringify(payload)).digest("hex");
}

/**
 * Validates, then queues one Contra entry for the login's active company.
 * @param {object} deps
 * @param {{query: Function}} deps.db
 * @param {number} deps.adminId
 * @param {object} deps.body
 * @param {(n: object) => Promise<void>} [deps.notify]        createNotification
 * @param {(n: object) => Promise<void>} [deps.notifyMobile]  createMobileNotificationForAdmin
 * @param {() => string} [deps.newGuid]
 * @param {() => Date} [deps.now]
 * @param {(payload: object, hash: string, company: string) => Promise<{status: number, json: object}>} [deps.edit]
 *   an edit (POST /api/mobile-voucher-command/edit): the payload is saved by
 *   it (over the waiting entry, or as an ALTER) instead of a new entry.
 * @returns {Promise<{ status: number, json: object }>}
 */
export async function queueContra({
  db,
  adminId,
  body,
  notify = async () => {},
  notifyMobile = async () => {},
  newGuid = () => crypto.randomUUID(),
  now = () => new Date(),
  log = console,
  edit = null,
}) {
  const checked = validateContra(body);
  if (checked.error) return { status: 400, json: { success: false, message: checked.error } };
  const v = checked.value;

  const companyRes = await db.query(`SELECT company_guid FROM active_company WHERE admin_id = $1`, [adminId]);
  if (!companyRes.rows.length) return { status: 400, json: { success: false, message: "No active company" } };
  const company_guid = companyRes.rows[0].company_guid;

  const payload = buildContraPayload(v, { guid: newGuid(), now: now() });
  const payload_hash = hashPayload(payload);

  // An edit: saved over the waiting entry or as an ALTER (mobileEdits.js).
  if (edit) return edit(payload, payload_hash, company_guid);

  // Same duplicate protection as the other mobile entries.
  const duplicate = await db.query(
    `SELECT id FROM mobile_sync_queue
     WHERE admin_id = $1 AND company_guid = $2 AND entity_type = 'VOUCHER' AND action = 'CREATE'
       AND payload_hash = $3 AND status IN ('pending', 'processing', 'success')
     LIMIT 1`,
    [adminId, company_guid, payload_hash]
  );
  if (duplicate.rowCount > 0) {
    return { status: 200, json: { success: true, duplicate: true, command_id: duplicate.rows[0].id } };
  }

  const result = await db.query(
    `INSERT INTO mobile_sync_queue
       (admin_id, company_guid, entity_type, entity_guid, action, payload, payload_hash, source, status)
     VALUES ($1, $2, 'VOUCHER', $3, 'CREATE', $4, $5, 'MOBILE', 'pending')
     RETURNING id`,
    [adminId, company_guid, payload.voucher_guid, payload, payload_hash]
  );

  const route = `${v.from_account} → ${v.to_account}`;
  try {
    await notify({ type: "VOUCHER_CREATED", message: "Mobile Contra voucher queued successfully", user_id: adminId });
  } catch (e) {
    log.error("Contra notification error:", e.message);
  }
  Promise.resolve()
    .then(() =>
      notifyMobile({
        type: "create_entry",
        message: `Contra | ₹${v.amount} | ${route} | queued for Tally sync`,
        adminId,
        meta: {
          voucher_guid: payload.voucher_guid,
          company_guid,
          voucher_type: "Contra",
          reference_no: payload.reference_no,
          voucher_date: v.voucher_date,
          party_name: route,
          amount: v.amount,
        },
      })
    )
    .catch((e) => log.error("mobile create_entry notify error:", e.message));

  return {
    status: 200,
    json: { success: true, command_id: result.rows[0].id, voucher_guid: payload.voucher_guid, status: "QUEUED" },
  };
}
