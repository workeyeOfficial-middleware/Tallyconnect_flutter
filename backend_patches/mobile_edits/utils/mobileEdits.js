/* =========================================================
   MOBILE ENTRIES — edit and retry (helpers for the routes)

   Edit (POST /api/mobile-voucher-command/edit) runs the entry type's own
   create handler (same checks, same payload as a new entry) in "edit
   mode"; finishMobileEdit() then decides what happens:
     - the entry is still waiting / failed (never reached Tally): its
       queued payload is replaced and it is sent again (one entry, no
       second voucher);
     - it is in Tally (a mobile entry Tally confirmed — its Tally GUID —
       or a synced voucher): an ALTER command for that Tally voucher is
       queued. The Agent alters the voucher in TallyPrime (never creates a
       new one) and re-reads that day; a waiting ALTER of the same voucher
       is replaced, never doubled.
   Retry (POST /api/mobile-sync-queue/:id/retry): a failed entry (or one
   stuck "sending" for 15 minutes) goes back to waiting, unless it is
   already in Tally (then a retry would make a second voucher).

   Needs sql/2026-10-23_mobile_edits.sql (tally_guid, target_guid,
   edit_of, created_by, retry_count, updated_at on mobile_sync_queue);
   before it runs, edit / retry answer 503 and nothing else changes.
========================================================= */

let cached = null;

export async function hasEditColumns(db) {
  if (cached && Date.now() - cached.at < 10 * 60 * 1000) return cached.on;
  try {
    const r = await db.query(
      `SELECT column_name FROM information_schema.columns
        WHERE table_schema = current_schema() AND table_name = 'mobile_sync_queue'
          AND column_name IN ('tally_guid', 'target_guid', 'edit_of', 'created_by', 'retry_count', 'updated_at')`
    );
    cached = { at: Date.now(), on: (r?.rows || []).length === 6 };
  } catch {
    cached = { at: Date.now(), on: false };
  }
  return cached.on;
}

/** Tests: forget the cached lookup. */
export function resetEditCache() {
  cached = null;
}

export class EditError extends Error {
  constructor(status, message, code) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

/** Entry types the app can edit, with their create route path. */
export const EDIT_TYPES = Object.freeze({
  sales: { path: "/create", voucherType: "Sales" },
  purchase: { path: "/create", voucherType: "Purchase" },
  receipt: { path: "/receipt/create", voucherType: "Receipt" },
  payment: { path: "/payment/create", voucherType: "Payment" },
  journal: { path: "/journal/create", voucherType: "Journal" },
  contra: { path: "/contra/create", voucherType: "Contra" },
});

/** A Tally voucher GUID as the Agent sends it (company GUID + id). */
export const isTallyGuid = (s) => typeof s === "string" && /^[0-9a-f-]{36}-[0-9a-f]{8}$/i.test(s.trim());

/** A stuck "processing" row older than this may be retried. */
export const STUCK_MINUTES = 15;

async function activeCompany(db, adminId) {
  const r = await db.query(`SELECT company_guid FROM active_company WHERE admin_id = $1 LIMIT 1`, [adminId]);
  const g = r.rows[0]?.company_guid;
  if (!g) throw new EditError(409, "No company is selected for this account.", "no_company");
  return g;
}

/** A team login may change only the entries it made itself. */
function mayTouch(user, row) {
  if (user.role === "ADMIN") return true;
  return row.created_by != null && Number(row.created_by) === Number(user.id);
}

/**
 * What an edit request targets (checked: this account, active company,
 * permissions, type). Returns the `req.tcEdit` the create handler gets.
 */
export async function editTarget(db, user, body) {
  if (!(await hasEditColumns(db))) {
    throw new EditError(503, "Editing entries is not available on the server yet.", "not_ready");
  }
  const type = String(body?.type || "").toLowerCase();
  const t = EDIT_TYPES[type];
  if (!t) throw new EditError(400, "This entry type cannot be edited from the app.", "bad_type");
  const adminId = user.adminId;
  const company = await activeCompany(db, adminId);

  if (body.queue_id !== undefined && body.queue_id !== null) {
    const id = Number.parseInt(String(body.queue_id), 10);
    if (!Number.isInteger(id) || id <= 0) throw new EditError(400, "Invalid entry id");
    const r = await db.query(
      `SELECT id, action, status, payload, tally_guid, target_guid, created_by
         FROM mobile_sync_queue
        WHERE id = $1 AND admin_id = $2 AND company_guid = $3 AND entity_type = 'VOUCHER'`,
      [id, adminId, company]
    );
    const row = r.rows[0];
    if (!row) throw new EditError(404, "Entry not found in the selected company.", "not_found");
    if (!mayTouch(user, row)) throw new EditError(403, "You can edit only the entries you made.", "forbidden");
    const p = typeof row.payload === "string" ? JSON.parse(row.payload) : row.payload || {};
    if (String(p.voucher_type || "").toLowerCase() !== t.voucherType.toLowerCase()) {
      throw new EditError(422, "The entry type cannot be changed.", "type_changed");
    }
    return { kind: "queue", type, path: t.path, row, payload: p, company, user };
  }

  const guid = String(body?.voucher_guid || "").trim();
  if (!guid) throw new EditError(400, "Which entry? Send queue_id or voucher_guid.");
  const r = await db.query(
    `SELECT v.voucher_guid, v.voucher_type, v.voucher_date
       FROM vouchers v
      WHERE v.admin_id = $1 AND v.company_guid = $2 AND v.voucher_guid = $3
        AND COALESCE(v.is_active, TRUE) = TRUE
      LIMIT 1`,
    [adminId, company, guid]
  );
  const v = r.rows[0];
  if (!v) throw new EditError(404, "Voucher not found in the selected company.", "not_found");
  // Only the plain Tally types: altering a custom type ("Sales GST", "Tally
  // Service Invoice") through the app's form would change its type.
  if (String(v.voucher_type || "").trim().toLowerCase() !== t.voucherType.toLowerCase()) {
    throw new EditError(
      422,
      `A ${v.voucher_type || "voucher"} can only be changed in TallyPrime.`,
      "type_not_editable"
    );
  }
  if (user.role !== "ADMIN") {
    const p = await db.query(
      `SELECT 1 FROM users u
        WHERE u.id = $1 AND $2 = ANY (SELECT jsonb_array_elements_text(u.voucher_selection_permissions->'allowed_vouchers'))`,
      [user.id, guid]
    );
    if (!p.rowCount) throw new EditError(403, "You do not have access to this voucher.", "forbidden");
  }
  return { kind: "voucher", type, path: t.path, tallyGuid: guid, company, user };
}

/**
 * The create handler's payload, saved as an edit. Returns
 * `{ status, json }` for the route to send.
 */
export async function finishMobileEdit(db, edit, { adminId, company_guid, payload, payload_hash }) {
  if (company_guid !== edit.company) {
    return { status: 409, json: { success: false, message: "The active company changed. Open the entry again." } };
  }
  // A mobile entry that never reached Tally: change it where it waits.
  if (edit.kind === "queue" && edit.row.action === "CREATE" && edit.row.status !== "success") {
    if (edit.row.status === "processing") {
      return {
        status: 409,
        json: { success: false, code: "sending", message: "This entry is being sent to Tally right now. Try again in a minute." },
      };
    }
    // Keep its own id (the payload's voucher_guid) so it stays one entry.
    const kept = { ...payload, voucher_guid: edit.payload.voucher_guid || payload.voucher_guid };
    const u = await db.query(
      `UPDATE mobile_sync_queue
          SET payload = $2, payload_hash = $3, status = 'pending', error = NULL, updated_at = NOW()
        WHERE id = $1 AND status IN ('pending', 'failed')
        RETURNING id`,
      [edit.row.id, kept, payload_hash]
    );
    if (!u.rows[0]) {
      return { status: 409, json: { success: false, code: "changed", message: "The entry changed meanwhile. Open it again." } };
    }
    return { status: 200, json: { success: true, edited: true, command_id: edit.row.id, status: "QUEUED" } };
  }

  // In Tally: alter that voucher.
  const target =
    edit.kind === "voucher"
      ? edit.tallyGuid
      : edit.row.action === "ALTER"
        ? edit.row.target_guid
        : edit.row.tally_guid;
  if (!target) {
    return {
      status: 409,
      json: {
        success: false,
        code: "not_linked",
        message:
          "This entry reached Tally before TallyConnect could link it. Edit it from Vouchers once it has synced, or in TallyPrime.",
      },
    };
  }
  const alter = { ...payload, voucher_guid: target };
  const editOf = edit.kind === "queue" ? edit.row.id : null;
  // One waiting change per Tally voucher: a newer edit replaces it.
  const open = await db.query(
    `SELECT id, status FROM mobile_sync_queue
      WHERE admin_id = $1 AND company_guid = $2 AND action = 'ALTER' AND target_guid = $3
        AND status IN ('pending', 'processing', 'failed')
      ORDER BY id DESC LIMIT 1`,
    [adminId, company_guid, target]
  );
  const o = open.rows[0];
  if (o?.status === "processing") {
    return {
      status: 409,
      json: { success: false, code: "sending", message: "A change to this voucher is being sent to Tally right now. Try again in a minute." },
    };
  }
  if (o) {
    await db.query(
      `UPDATE mobile_sync_queue
          SET payload = $2, payload_hash = $3, status = 'pending', error = NULL, updated_at = NOW()
        WHERE id = $1`,
      [o.id, alter, payload_hash]
    );
    return { status: 200, json: { success: true, edited: true, command_id: o.id, status: "QUEUED", alter: true } };
  }
  const ins = await db.query(
    `INSERT INTO mobile_sync_queue
       (admin_id, company_guid, entity_type, entity_guid, action, payload, payload_hash, source, status,
        target_guid, edit_of, created_by, updated_at)
     VALUES ($1, $2, 'VOUCHER', $3, 'ALTER', $4, $5, 'MOBILE', 'pending', $3, $6, $7, NOW())
     RETURNING id`,
    [adminId, company_guid, target, alter, payload_hash, editOf, edit.user.id]
  );
  return { status: 200, json: { success: true, edited: true, command_id: ins.rows[0].id, status: "QUEUED", alter: true } };
}

/**
 * Retry a failed (or stuck) entry. Returns `{ status, json }`.
 * [findSynced]: a synced voucher with the same type + number (+ date) —
 * then it is already in Tally and is not sent again.
 */
export async function retryEntry(db, user, rawId, now = () => new Date()) {
  if (!(await hasEditColumns(db))) {
    return { status: 503, json: { success: false, code: "not_ready", message: "Retry is not available on the server yet." } };
  }
  const id = Number.parseInt(String(rawId), 10);
  if (!Number.isInteger(id) || id <= 0) return { status: 400, json: { success: false, message: "Invalid entry id" } };
  const company = await activeCompany(db, user.adminId);
  const r = await db.query(
    `SELECT id, action, status, payload, tally_guid, created_by, updated_at, created_at
       FROM mobile_sync_queue
      WHERE id = $1 AND admin_id = $2 AND company_guid = $3 AND entity_type = 'VOUCHER'`,
    [id, user.adminId, company]
  );
  const row = r.rows[0];
  if (!row) return { status: 404, json: { success: false, message: "Entry not found in the selected company." } };
  if (!mayTouch(user, row)) return { status: 403, json: { success: false, message: "You can retry only the entries you made." } };
  if (row.status === "success") {
    return { status: 409, json: { success: false, code: "done", message: "This entry is already in Tally." } };
  }
  if (row.status === "pending") {
    return { status: 200, json: { success: true, status: "QUEUED", already: true, message: "Already waiting to be sent." } };
  }
  if (row.status === "processing") {
    const since = new Date(row.updated_at || row.created_at).getTime();
    if (now().getTime() - since < STUCK_MINUTES * 60000) {
      return { status: 409, json: { success: false, code: "sending", message: "This entry is being sent to Tally right now." } };
    }
  }
  // A CREATE Tally may have taken although the answer was lost: never send
  // it a second time when a synced voucher has its type and number.
  const p = typeof row.payload === "string" ? JSON.parse(row.payload) : row.payload || {};
  if (row.action === "CREATE") {
    if (row.tally_guid) {
      return { status: 409, json: { success: false, code: "done", message: "This entry is already in Tally." } };
    }
    const no = String(p.voucher_no || "").trim();
    if (no) {
      const dup = await db.query(
        `SELECT voucher_guid FROM vouchers
          WHERE admin_id = $1 AND company_guid = $2 AND LOWER(voucher_type) = LOWER($3)
            AND reference_no = $4 AND COALESCE(is_active, TRUE) = TRUE
          LIMIT 1`,
        [user.adminId, company, String(p.voucher_type || ""), no]
      );
      if (dup.rows[0]) {
        return {
          status: 409,
          json: {
            success: false,
            code: "in_tally",
            message: `Tally already has ${p.voucher_type} ${no}. It was not sent again.`,
          },
        };
      }
    }
  }
  const u = await db.query(
    `UPDATE mobile_sync_queue
        SET status = 'pending', error = NULL, retry_count = COALESCE(retry_count, 0) + 1, updated_at = NOW()
      WHERE id = $1 AND status IN ('failed', 'processing')
      RETURNING id, retry_count`,
    [id]
  );
  if (!u.rows[0]) return { status: 409, json: { success: false, code: "changed", message: "The entry changed meanwhile." } };
  return { status: 200, json: { success: true, status: "QUEUED", retry_count: Number(u.rows[0].retry_count) } };
}
