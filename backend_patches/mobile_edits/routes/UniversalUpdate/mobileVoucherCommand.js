import express from "express";
import pool from "../../db.js";
import requireAuth from "../../middleware/requireAuth.js";
import { createNotification } from "../../utils/notification.js";
import { createMobileNotificationForAdmin } from "../../utils/mobileNotification.js";
import crypto from "crypto";
import { queueContra } from "../../utils/contraCore.js";
import { EditError, editTarget, finishMobileEdit, hasEditColumns } from "../../utils/mobileEdits.js";

const router = express.Router();

const ALLOWED_VOUCHER_TYPES = [
  "Journal",
  "Payment",
  "Receipt",
  "Sales",
  "Purchase"
];

function hashPayload(payload) {
  return crypto
    .createHash("sha256")
    .update(JSON.stringify(payload))
    .digest("hex");
}

/** The login that made a new entry (team members edit / retry only theirs). */
async function noteCreator(id, user) {
  try {
    if (id && user?.id && (await hasEditColumns(pool))) {
      await pool.query(`UPDATE mobile_sync_queue SET created_by = $2 WHERE id = $1`, [id, user.id]);
    }
  } catch (e) {
    console.error("mobile entry created_by:", e.message);
  }
}

// =========================================
// EDIT AN ENTRY (mobile entry or synced voucher)
// POST /edit  { type, queue_id | voucher_guid, ...the same fields as create }
// The entry type's own create handler runs (same checks and payload) and
// saves it as an edit: over the waiting entry, or as an ALTER of the Tally
// voucher (utils/mobileEdits.js).
// =========================================
router.post("/edit", requireAuth, async (req, res, next) => {
  try {
    const edit = await editTarget(pool, req.user, req.body || {});
    if (edit.type === "contra") {
      const r = await queueContra({
        db: pool,
        adminId: req.user.adminId,
        body: req.body,
        edit: (payload, payload_hash, company_guid) =>
          finishMobileEdit(pool, edit, { adminId: req.user.adminId, company_guid, payload, payload_hash }),
      });
      return res.status(r.status).json(r.json);
    }
    // Sales / Purchase: the type comes from the body as on create.
    if (edit.type === "sales" || edit.type === "purchase") {
      req.body.voucher_type = edit.type === "sales" ? "Sales" : "Purchase";
    }
    req.tcEdit = edit;
    req.url = edit.path;
    return router.handle(req, res, next);
  } catch (err) {
    if (err instanceof EditError) {
      return res.status(err.status).json({ success: false, code: err.code, message: err.message });
    }
    console.error("Mobile entry edit error:", err);
    return res.status(500).json({ success: false, message: "Could not save the change." });
  }
});

router.post("/create", requireAuth, async (req, res) => {
  try {
    const adminId = req.user.adminId;

const {
  voucher_type,
  voucher_date,
  voucher_no,
  party_name,
  new_party,
  due_date,
      narration,
      ledger_entries,
      items,
      summary,
      payment
    } = req.body;

// -----------------------------------------
// BASIC VALIDATION
// -----------------------------------------
if (!voucher_type || !voucher_date) {
  return res.status(400).json({
    success: false,
    message: "voucher_type and voucher_date are required"
  });
}

if (!ALLOWED_VOUCHER_TYPES.includes(voucher_type)) {
  return res.status(400).json({
    success: false,
    message: `Unsupported voucher type: ${voucher_type}`
  });
}

if (voucher_type === "Sales" || voucher_type === "Purchase") {
  if (!Array.isArray(items)) {
    return res.status(400).json({
      success: false,
      message: "items must be an array for Sales/Purchase"
    });
  }
}

// -----------------------------------------
// ACTIVE COMPANY
// -----------------------------------------
const companyRes = await pool.query(
  `
  SELECT company_guid
  FROM active_company
  WHERE admin_id = $1
  `,
  [adminId]
);

if (!companyRes.rows.length) {
  return res.status(400).json({
    success: false,
    message: "No active company"
  });
}

const company_guid = companyRes.rows[0].company_guid;

// -----------------------------------------
// GENERATE IDENTIFIERS ON BACKEND
// -----------------------------------------
const voucher_guid = crypto.randomUUID();
const reference_no = `MOBILE-${Date.now()}`;

// -----------------------------------------
// GENERATE LEDGER ENTRIES
// -----------------------------------------
const subtotal = Number(summary?.subtotal || 0);
const totalAmount = Number(summary?.total_amount || 0);

const generatedLedgerEntries = [
  {
    ledger_name: party_name || "",
    amount: totalAmount,
    is_debit: true
  },
  {
    ledger_name: voucher_type === "Purchase"
      ? "Purchase"
      : "Sales",
    amount: subtotal,
    is_debit: false
  }
];

// -----------------------------------------
// COMPLETE MOBILE PAYLOAD
// -----------------------------------------
const payload = {
  voucher_guid,
  voucher_type,
  voucher_date,
  voucher_no: voucher_no || null,
party_name: party_name || null,
new_party: new_party || null,
due_date: due_date || null,
  narration: narration || "",
  reference_no,

  ledger_entries: generatedLedgerEntries,

  items: items || [],

  summary: summary || {
    subtotal: 0,
    discount: 0,
    cgst: 0,
    sgst: 0,
    total_amount: 0
  },

  payment: payment || {
    payment_mode: null,
    amount_received: 0,
    balance_due: 0
  }
};

    const payload_hash = hashPayload(payload);

    // Edit (POST /edit): saved over the queued entry, or sent to Tally as
    // an alteration of its voucher (utils/mobileEdits.js).
    if (req.tcEdit) {
      const edited = await finishMobileEdit(pool, req.tcEdit, { adminId, company_guid, payload, payload_hash });
      return res.status(edited.status).json(edited.json);
    }

    // -----------------------------------------
    // DUPLICATE PROTECTION
    // -----------------------------------------
    const duplicate = await pool.query(
      `
      SELECT id
      FROM mobile_sync_queue
      WHERE admin_id = $1
        AND company_guid = $2
        AND entity_type = 'VOUCHER'
        AND action = 'CREATE'
        AND payload_hash = $3
        AND status IN ('pending', 'processing', 'success')
      LIMIT 1
      `,
      [
        adminId,
        company_guid,
        payload_hash
      ]
    );

    if (duplicate.rowCount > 0) {
      return res.json({
        success: true,
        duplicate: true,
        command_id: duplicate.rows[0].id
      });
    }

    // -----------------------------------------
    // INSERT MOBILE QUEUE
    // -----------------------------------------
    const result = await pool.query(
      `
      INSERT INTO mobile_sync_queue
      (
        admin_id,
        company_guid,
        entity_type,
        entity_guid,
        action,
        payload,
        payload_hash,
        source,
        status
      )
      VALUES
      (
        $1,
        $2,
        'VOUCHER',
        $3,
        'CREATE',
        $4,
        $5,
        'MOBILE',
        'pending'
      )
      RETURNING id
      `,
      [
        adminId,
        company_guid,
        voucher_guid,
        payload,
        payload_hash
      ]
    );

    await noteCreator(result.rows[0]?.id, req.user);

    await createNotification({
      type: "VOUCHER_CREATED",
      message: `Mobile ${voucher_type} voucher queued successfully`,
      user_id: adminId
    });

    createMobileNotificationForAdmin({
      type: "create_entry",
      message: `${voucher_type} | ₹${totalAmount} | ${party_name || "-"} | queued for Tally sync`,
      adminId,
      meta: {
        voucher_guid,
        company_guid,
        voucher_type,
        reference_no,
        voucher_date,
        party_name: party_name || null,
        amount: totalAmount
      }
    }).catch((e) => console.error("mobile create_entry notify error:", e.message));

    return res.json({
      success: true,
      command_id: result.rows[0].id,
      voucher_guid,
      status: "QUEUED"
    });

  } catch (err) {
    console.error("Mobile voucher create error:", err);

    return res.status(400).json({
      success: false,
      message: err.message
    });
  }
});

// =========================================
// MOBILE RECEIPT CREATE
// =========================================
// =========================================
// MOBILE RECEIPT CREATE
// =========================================
router.post("/receipt/create", requireAuth, async (req, res) => {
  try {
    const adminId = req.user.adminId;

const {
  voucher_date,
  voucher_no,
  party_name,
  amount_received,
  reference_no,
  narration,
  payment
} = req.body;

const payment_mode =
  payment?.payment_mode || null;

const bank_name =
  payment?.bank_name || null;

const account_number =
  payment?.account_number || null;

const cheque_number =
  payment?.cheque_number || null;

const cheque_date =
  payment?.cheque_date || null;

const upi_ref =
  payment?.upi_ref || null;

const other_ref =
  payment?.other_ref || null;

const deposit_account =
  payment?.deposit_account || null;

    // -----------------------------------------
    // BASIC VALIDATION
    // -----------------------------------------

    if (!voucher_date) {
      return res.status(400).json({
        success: false,
        message: "voucher_date is required"
      });
    }

    if (!party_name) {
      return res.status(400).json({
        success: false,
        message: "party_name is required"
      });
    }

    const amountReceived = Number(amount_received || 0);

    if (amountReceived <= 0) {
      return res.status(400).json({
        success: false,
        message: "amount_received must be greater than 0"
      });
    }

    if (!payment_mode) {
      return res.status(400).json({
        success: false,
        message: "payment_mode is required"
      });
    }

    // -----------------------------------------
    // ACTIVE COMPANY
    // -----------------------------------------

    const companyRes = await pool.query(
      `
      SELECT company_guid
      FROM active_company
      WHERE admin_id = $1
      `,
      [adminId]
    );

    if (!companyRes.rows.length) {
      return res.status(400).json({
        success: false,
        message: "No active company"
      });
    }

    const company_guid =
      companyRes.rows[0].company_guid;

    // -----------------------------------------
    // GENERATE IDENTIFIERS
    // -----------------------------------------

    const voucher_guid =
      crypto.randomUUID();

    const generatedReferenceNo =
      reference_no ||
      `MOBILE-RECEIPT-${Date.now()}`;

    // -----------------------------------------
    // COMPLETE RECEIPT PAYLOAD
    // -----------------------------------------

    const payload = {
      voucher_guid,

      voucher_type: "Receipt",

      voucher_date,

      voucher_no:
        voucher_no || null,

      party_name,

      amount_received:
        amountReceived,

      reference_no:
        generatedReferenceNo,

      narration:
        narration || "",

      payment: {
        payment_mode:
          payment_mode || null,

        bank_name:
          bank_name || null,

        account_number:
          account_number || null,

        cheque_number:
          cheque_number || null,

        cheque_date:
          cheque_date || null,

        upi_ref:
          upi_ref || null,

        other_ref:
          other_ref || null,

        deposit_account:
          deposit_account || null
      }
    };

    // -----------------------------------------
    // HASH PAYLOAD
    // -----------------------------------------

    const payload_hash =
      hashPayload(payload);

    // Edit (POST /edit): saved over the queued entry, or sent to Tally as
    // an alteration of its voucher (utils/mobileEdits.js).
    if (req.tcEdit) {
      const edited = await finishMobileEdit(pool, req.tcEdit, { adminId, company_guid, payload, payload_hash });
      return res.status(edited.status).json(edited.json);
    }

    // -----------------------------------------
    // DUPLICATE PROTECTION
    // -----------------------------------------

    const duplicate = await pool.query(
      `
      SELECT id
      FROM mobile_sync_queue
      WHERE admin_id = $1
        AND company_guid = $2
        AND entity_type = 'VOUCHER'
        AND action = 'CREATE'
        AND payload_hash = $3
        AND status IN (
          'pending',
          'processing',
          'success'
        )
      LIMIT 1
      `,
      [
        adminId,
        company_guid,
        payload_hash
      ]
    );

    if (duplicate.rowCount > 0) {
      return res.json({
        success: true,
        duplicate: true,
        command_id:
          duplicate.rows[0].id
      });
    }

    // -----------------------------------------
    // INSERT INTO MOBILE QUEUE
    // -----------------------------------------

    const result = await pool.query(
      `
      INSERT INTO mobile_sync_queue
      (
        admin_id,
        company_guid,
        entity_type,
        entity_guid,
        action,
        payload,
        payload_hash,
        source,
        status
      )
      VALUES
      (
        $1,
        $2,
        'VOUCHER',
        $3,
        'CREATE',
        $4,
        $5,
        'MOBILE',
        'pending'
      )
      RETURNING id
      `,
      [
        adminId,
        company_guid,
        voucher_guid,
        payload,
        payload_hash
      ]
    );

    await noteCreator(result.rows[0]?.id, req.user);

    // -----------------------------------------
    // NOTIFICATION
    // -----------------------------------------

    await createNotification({
      type: "VOUCHER_CREATED",
      message:
        "Mobile Receipt voucher queued successfully",
      user_id: adminId
    });

    createMobileNotificationForAdmin({
      type: "create_entry",
      message: `Receipt | ₹${amountReceived} | ${party_name || "-"} | queued for Tally sync`,
      adminId,
      meta: {
        voucher_guid,
        company_guid,
        voucher_type: "Receipt",
        reference_no: generatedReferenceNo,
        voucher_date,
        party_name: party_name || null,
        amount: amountReceived
      }
    }).catch((e) => console.error("mobile create_entry notify error:", e.message));

    // -----------------------------------------
    // RESPONSE
    // -----------------------------------------

    return res.json({
      success: true,
      command_id:
        result.rows[0].id,
      voucher_guid,
      status: "QUEUED"
    });

  } catch (err) {

    console.error(
      "Mobile Receipt create error:",
      err
    );

    return res.status(400).json({
      success: false,
      message: err.message
    });
  }
});


// =========================================
// MOBILE PAYMENT CREATE
// =========================================
router.post("/payment/create", requireAuth, async (req, res) => {
  try {
    const adminId = req.user.adminId;

    const {
      voucher_date,
      voucher_no,
      party_name,
      amount_paid,
      reference_no,
      narration,
      payment
    } = req.body;

    const payment_mode =
      payment?.payment_mode || null;

    const bank_account =
      payment?.bank_account || null;

    const transaction_instrument_no =
      payment?.transaction_instrument_no || null;

    const transaction_date =
      payment?.transaction_date || null;

    const remarks =
      payment?.remarks || null;

    // -----------------------------------------
    // BASIC VALIDATION
    // -----------------------------------------

    if (!voucher_date) {
      return res.status(400).json({
        success: false,
        message: "voucher_date is required"
      });
    }

    if (!party_name) {
      return res.status(400).json({
        success: false,
        message: "party_name is required"
      });
    }

    const amountPaid = Number(amount_paid || 0);

    if (amountPaid <= 0) {
      return res.status(400).json({
        success: false,
        message: "amount_paid must be greater than 0"
      });
    }

    if (!payment_mode) {
      return res.status(400).json({
        success: false,
        message: "payment_mode is required"
      });
    }

    // -----------------------------------------
    // ACTIVE COMPANY
    // -----------------------------------------

    const companyRes = await pool.query(
      `
      SELECT company_guid
      FROM active_company
      WHERE admin_id = $1
      `,
      [adminId]
    );

    if (!companyRes.rows.length) {
      return res.status(400).json({
        success: false,
        message: "No active company"
      });
    }

    const company_guid =
      companyRes.rows[0].company_guid;

    // -----------------------------------------
    // GENERATE IDENTIFIERS
    // -----------------------------------------

    const voucher_guid =
      crypto.randomUUID();

    const generatedReferenceNo =
      reference_no ||
      `MOBILE-PAYMENT-${Date.now()}`;

    // -----------------------------------------
    // COMPLETE PAYMENT PAYLOAD
    // -----------------------------------------

    const payload = {
      voucher_guid,

      voucher_type: "Payment",

      voucher_date,

      voucher_no:
        voucher_no || null,

      party_name,

      amount_paid:
        amountPaid,

      reference_no:
        generatedReferenceNo,

      narration:
        narration || "",

      payment: {
        payment_mode,

        bank_account:
          bank_account || null,

        transaction_instrument_no:
          transaction_instrument_no || null,

        transaction_date:
          transaction_date || null,

        remarks:
          remarks || null
      }
    };

    // -----------------------------------------
    // HASH PAYLOAD
    // -----------------------------------------

    const payload_hash =
      hashPayload(payload);

    // Edit (POST /edit): saved over the queued entry, or sent to Tally as
    // an alteration of its voucher (utils/mobileEdits.js).
    if (req.tcEdit) {
      const edited = await finishMobileEdit(pool, req.tcEdit, { adminId, company_guid, payload, payload_hash });
      return res.status(edited.status).json(edited.json);
    }

    // -----------------------------------------
    // DUPLICATE PROTECTION
    // -----------------------------------------

    const duplicate = await pool.query(
      `
      SELECT id
      FROM mobile_sync_queue
      WHERE admin_id = $1
        AND company_guid = $2
        AND entity_type = 'VOUCHER'
        AND action = 'CREATE'
        AND payload_hash = $3
        AND status IN (
          'pending',
          'processing',
          'success'
        )
      LIMIT 1
      `,
      [
        adminId,
        company_guid,
        payload_hash
      ]
    );

    if (duplicate.rowCount > 0) {
      return res.json({
        success: true,
        duplicate: true,
        command_id:
          duplicate.rows[0].id
      });
    }

    // -----------------------------------------
    // INSERT INTO MOBILE QUEUE
    // -----------------------------------------

    const result = await pool.query(
      `
      INSERT INTO mobile_sync_queue
      (
        admin_id,
        company_guid,
        entity_type,
        entity_guid,
        action,
        payload,
        payload_hash,
        source,
        status
      )
      VALUES
      (
        $1,
        $2,
        'VOUCHER',
        $3,
        'CREATE',
        $4,
        $5,
        'MOBILE',
        'pending'
      )
      RETURNING id
      `,
      [
        adminId,
        company_guid,
        voucher_guid,
        payload,
        payload_hash
      ]
    );

    await noteCreator(result.rows[0]?.id, req.user);

    // -----------------------------------------
    // NOTIFICATION
    // -----------------------------------------

    await createNotification({
      type: "VOUCHER_CREATED",
      message:
        "Mobile Payment voucher queued successfully",
      user_id: adminId
    });

    createMobileNotificationForAdmin({
      type: "create_entry",
      message: `Payment | ₹${amountPaid} | ${party_name || "-"} | queued for Tally sync`,
      adminId,
      meta: {
        voucher_guid,
        company_guid,
        voucher_type: "Payment",
        reference_no: generatedReferenceNo,
        voucher_date,
        party_name: party_name || null,
        amount: amountPaid
      }
    }).catch((e) => console.error("mobile create_entry notify error:", e.message));

    // -----------------------------------------
    // RESPONSE
    // -----------------------------------------

    return res.json({
      success: true,
      command_id:
        result.rows[0].id,
      voucher_guid,
      status: "QUEUED"
    });

  } catch (err) {

    console.error(
      "Mobile Payment create error:",
      err
    );

    return res.status(400).json({
      success: false,
      message: err.message
    });
  }
});

// =========================================
// MOBILE JOURNAL CREATE
// =========================================
router.post("/journal/create", requireAuth, async (req, res) => {
  try {
    const adminId = req.user.adminId;

    const {
      voucher_date,
      voucher_no,
      reference_no,
      narration,
      ledger_entries
    } = req.body;

    // -----------------------------------------
    // BASIC VALIDATION
    // -----------------------------------------

    if (!voucher_date) {
      return res.status(400).json({
        success: false,
        message: "voucher_date is required"
      });
    }

    if (!Array.isArray(ledger_entries)) {
      return res.status(400).json({
        success: false,
        message: "ledger_entries must be an array"
      });
    }

    if (ledger_entries.length < 2) {
      return res.status(400).json({
        success: false,
        message: "At least 2 ledger entries are required"
      });
    }

    // -----------------------------------------
    // VALIDATE LEDGER ENTRIES
    // -----------------------------------------

    for (const entry of ledger_entries) {

      if (!entry.ledger_name) {
        return res.status(400).json({
          success: false,
          message: "ledger_name is required for every entry"
        });
      }

      if (
        entry.amount === undefined ||
        entry.amount === null ||
        Number(entry.amount) <= 0
      ) {
        return res.status(400).json({
          success: false,
          message:
            `Invalid amount for ledger: ${entry.ledger_name}`
        });
      }

      if (typeof entry.is_debit !== "boolean") {
        return res.status(400).json({
          success: false,
          message:
            `is_debit must be true or false for ledger: ${entry.ledger_name}`
        });
      }
    }

    // -----------------------------------------
    // CALCULATE DEBIT / CREDIT TOTALS
    // -----------------------------------------

    let totalDebit = 0;
    let totalCredit = 0;

    for (const entry of ledger_entries) {

      const amount = Number(entry.amount);

      if (entry.is_debit) {
        totalDebit += amount;
      } else {
        totalCredit += amount;
      }
    }

    // -----------------------------------------
    // JOURNAL MUST BALANCE
    // -----------------------------------------

    const difference =
      Math.abs(totalDebit - totalCredit);

    if (difference > 0.01) {
      return res.status(400).json({
        success: false,
        message:
          "Journal is not balanced",
        total_debit:
          Number(totalDebit.toFixed(2)),
        total_credit:
          Number(totalCredit.toFixed(2)),
        difference:
          Number(difference.toFixed(2))
      });
    }

    // -----------------------------------------
    // ACTIVE COMPANY
    // -----------------------------------------

    const companyRes = await pool.query(
      `
      SELECT company_guid
      FROM active_company
      WHERE admin_id = $1
      `,
      [adminId]
    );

    if (!companyRes.rows.length) {
      return res.status(400).json({
        success: false,
        message: "No active company"
      });
    }

    const company_guid =
      companyRes.rows[0].company_guid;

    // -----------------------------------------
    // GENERATE IDENTIFIERS
    // -----------------------------------------

    const voucher_guid =
      crypto.randomUUID();

    const generatedReferenceNo =
      reference_no ||
      `MOBILE-JOURNAL-${Date.now()}`;

    // -----------------------------------------
    // COMPLETE JOURNAL PAYLOAD
    // -----------------------------------------

    const payload = {

      voucher_guid,

      voucher_type: "Journal",

      voucher_date,

      voucher_no:
        voucher_no || null,

      reference_no:
        generatedReferenceNo,

      narration:
        narration || "",

      ledger_entries:
        ledger_entries.map(entry => ({
          ledger_name:
            entry.ledger_name,

          amount:
            Number(entry.amount),

          is_debit:
            entry.is_debit
        })),

      total_debit:
        Number(totalDebit.toFixed(2)),

      total_credit:
        Number(totalCredit.toFixed(2))
    };

    // -----------------------------------------
    // HASH PAYLOAD
    // -----------------------------------------

    const payload_hash =
      hashPayload(payload);

    // Edit (POST /edit): saved over the queued entry, or sent to Tally as
    // an alteration of its voucher (utils/mobileEdits.js).
    if (req.tcEdit) {
      const edited = await finishMobileEdit(pool, req.tcEdit, { adminId, company_guid, payload, payload_hash });
      return res.status(edited.status).json(edited.json);
    }

    // -----------------------------------------
    // DUPLICATE PROTECTION
    // -----------------------------------------

    const duplicate = await pool.query(
      `
      SELECT id
      FROM mobile_sync_queue
      WHERE admin_id = $1
        AND company_guid = $2
        AND entity_type = 'VOUCHER'
        AND action = 'CREATE'
        AND payload_hash = $3
        AND status IN (
          'pending',
          'processing',
          'success'
        )
      LIMIT 1
      `,
      [
        adminId,
        company_guid,
        payload_hash
      ]
    );

    if (duplicate.rowCount > 0) {
      return res.json({
        success: true,
        duplicate: true,
        command_id:
          duplicate.rows[0].id
      });
    }

    // -----------------------------------------
    // INSERT INTO MOBILE QUEUE
    // -----------------------------------------

    const result = await pool.query(
      `
      INSERT INTO mobile_sync_queue
      (
        admin_id,
        company_guid,
        entity_type,
        entity_guid,
        action,
        payload,
        payload_hash,
        source,
        status
      )
      VALUES
      (
        $1,
        $2,
        'VOUCHER',
        $3,
        'CREATE',
        $4,
        $5,
        'MOBILE',
        'pending'
      )
      RETURNING id
      `,
      [
        adminId,
        company_guid,
        voucher_guid,
        payload,
        payload_hash
      ]
    );

    await noteCreator(result.rows[0]?.id, req.user);

    // -----------------------------------------
    // NOTIFICATION
    // -----------------------------------------

    await createNotification({
      type: "VOUCHER_CREATED",
      message:
        "Mobile Journal voucher queued successfully",
      user_id: adminId
    });

    const journalParty = ledger_entries[0]?.ledger_name || null;

    createMobileNotificationForAdmin({
      type: "create_entry",
      message: `Journal | ₹${totalDebit} | ${journalParty || "-"} | queued for Tally sync`,
      adminId,
      meta: {
        voucher_guid,
        company_guid,
        voucher_type: "Journal",
        reference_no: generatedReferenceNo,
        voucher_date,
        party_name: journalParty,
        amount: totalDebit
      }
    }).catch((e) => console.error("mobile create_entry notify error:", e.message));

    // -----------------------------------------
    // RESPONSE
    // -----------------------------------------

    return res.json({
      success: true,
      command_id:
        result.rows[0].id,
      voucher_guid,
      status: "QUEUED"
    });

  } catch (err) {

    console.error(
      "Mobile Journal create error:",
      err
    );

    return res.status(400).json({
      success: false,
      message: err.message
    });
  }
});


export default router;
