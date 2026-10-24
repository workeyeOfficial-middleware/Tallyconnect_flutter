import express from "express";
import pool from "../db.js";
import requireAuth from "../middleware/requireAuth.js";
import requireAdmin from "../middleware/requireAdmin.js";
import { createMobileNotificationForAdmin } from "../utils/mobileNotification.js";
import { hasLocationColumns, locationOf } from "../utils/ledgerLocation.js";

const router = express.Router();

/* =====================================================
   AGENT → SYNC LEDGER (INSERT / UPDATE)
===================================================== */
router.post("/sync", requireAuth, async (req, res) => {
const {
  ledger_guid,
  company_guid,
  name,
  parent_group,
  opening_balance,
  closing_balance,
  type,
  email,
  phone,
} = req.body;

const adminId = req.user.adminId; // ✅ FROM JWT


  // 🔒 HARD VALIDATION
if (!ledger_guid || !company_guid || !name) {
  return res.status(400).json({
    success: false,
error: "ledger_guid, company_guid and name are required",
  });
}

  

  // 🔒 Validate company exists
// 🔒 Validate company is ACTIVE for this admin
// 🔒 Validate company BELONGS to this admin (NOT active check)
const ownershipCheck = await pool.query(
  `
  SELECT 1
  FROM companies
  WHERE admin_id = $1
    AND company_guid = $2
  `,
  [adminId, company_guid]
);

if (ownershipCheck.rowCount === 0) {
  console.warn(
    "⚠️ Ledger skipped – company ownership missing:",
    company_guid
  );
  return res.json({ success: false, skipped: true });
}



  // State, PIN, country and address from Tally once the columns exist; an
  // Agent that does not send them keeps what is stored.
  const loc = (await hasLocationColumns(pool)) ? locationOf(req.body) : null;

  try {
  const result = await pool.query(
  `
  INSERT INTO ledgers (
    admin_id,
    ledger_guid,
    company_guid,
    name,
    email,
    phone,
    parent_group,
    opening_balance,
    closing_balance,
    type${loc ? ", state, pincode, country, address" : ""}
  )
  VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10${loc ? ",$11,$12,$13,$14" : ""})
  ON CONFLICT (admin_id, company_guid, ledger_guid)
  DO UPDATE SET
    name = EXCLUDED.name,
    email = EXCLUDED.email,
    phone = EXCLUDED.phone,
    parent_group = EXCLUDED.parent_group,
    opening_balance = EXCLUDED.opening_balance,
    closing_balance = EXCLUDED.closing_balance,
    type = EXCLUDED.type${
      loc
        ? `,
    state = COALESCE(EXCLUDED.state, ledgers.state),
    pincode = COALESCE(EXCLUDED.pincode, ledgers.pincode),
    country = COALESCE(EXCLUDED.country, ledgers.country),
    address = COALESCE(EXCLUDED.address, ledgers.address)`
        : ""
    }
  RETURNING *
  `,
  [
    adminId,
    ledger_guid,
    company_guid,
    name,
    email || null,
    phone || null,
    parent_group || null,
    Number(opening_balance) || 0,
    Number(closing_balance) || 0,
    type || "General",
    ...(loc ? [loc.state, loc.pincode, loc.country, loc.address] : []),
  ]
);


    

    const isParty = /party|sundry|creditor|debtor|customer|supplier/i.test(type || "");
    createMobileNotificationForAdmin({
      type: isParty ? "party_sync" : "ledger_sync",
      message: `${isParty ? "New party synced" : "New ledger synced"}: ${name}`,
      adminId,
    }).catch((e) => console.error("mobile ledger sync notify error:", e.message));

    res.json({ success: true, data: result.rows[0] });
  } catch (err) {
    console.error("Ledger sync error:", err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

/* =====================================================
   FETCH LEDGERS (ADMIN / USER)
===================================================== */
router.get("/", requireAuth, async (req, res) => {
  try {
    const userId = req.user.id;
    const adminId = req.user.adminId;
    const role = req.user.role;

    let query;
    let params;
    // Location (state, PIN, country, address) once the columns exist.
    const locCols = (await hasLocationColumns(pool))
      ? ", l.state, l.pincode, l.country, l.address"
      : "";

    // ✅ ADMIN: all ledgers of active company
    if (role === "ADMIN") {
      query = `
        SELECT
          l.ledger_guid,
          l.name,
          l.email,
          l.phone,
          l.parent_group,
          l.type,
          l.opening_balance,
          l.closing_balance${locCols}
        FROM ledgers l
        WHERE l.admin_id = $1
          AND EXISTS (
            SELECT 1 FROM active_company ac
            WHERE ac.admin_id = $1 AND ac.company_guid = l.company_guid
          )
        ORDER BY l.name ASC
      `;
      params = [adminId];
    }

    // ✅ USER: permission-based ledgers
    else {
      query = `
        SELECT
          l.ledger_guid,
          l.name,
          l.parent_group,
          l.type,
          l.opening_balance,
          l.closing_balance${locCols}
        FROM ledgers l
        WHERE l.admin_id = $2
          AND EXISTS (
            SELECT 1 FROM active_company ac
            WHERE ac.admin_id = $2 AND ac.company_guid = l.company_guid
          )
          AND EXISTS (
            SELECT 1 FROM user_ledger_permissions ulp
            WHERE ulp.user_id = $1 AND ulp.ledger_guid = l.ledger_guid
          )
        ORDER BY l.name ASC
      `;
      params = [userId, adminId];
    }

    const ledgersResult = await pool.query(query, params);
    const rows = ledgersResult.rows;

    if (rows.length > 0) {
      const aggResult = await pool.query(
        `
        SELECT
          ve.ledger_name AS name,
          MAX(ve.voucher_date) AS date,
          MAX(ve.voucher_type) AS voucher_type,
          MAX(ve.reference_no) AS reference_no
        FROM voucher_entries ve
        WHERE ve.admin_id = $1
          AND ve.company_guid = (
            SELECT ac.company_guid FROM active_company ac WHERE ac.admin_id = $1
          )
          AND ve.is_active = true
        GROUP BY ve.ledger_name
        `,
        [adminId]
      );
      // Matched by the name as Tally compares it (capitals ignored, line
      // breaks / repeated spaces = one space); several spellings of one
      // ledger on voucher lines → the latest of them.
      const key = (s) => String(s ?? "").replace(/[ \t\r\n\f\v]+/g, " ").trim().toLowerCase();
      const aggMap = new Map();
      for (const r of aggResult.rows) {
        const k = key(r.name);
        const cur = aggMap.get(k);
        if (!cur || (r.date && (!cur.date || new Date(r.date) > new Date(cur.date)))) aggMap.set(k, r);
      }
      for (const row of rows) {
        const a = aggMap.get(key(row.name));
        row.date = a?.date ?? null;
        row.voucher_type = a?.voucher_type ?? null;
        row.reference_no = a?.reference_no ?? null;
      }
    }

    res.json({ success: true, data: rows });
  } catch (err) {
    console.error("Ledger fetch error:", err);
    res.status(500).json({ success: false });
  }
});

/* =====================================================
   ASSIGN LEDGERS TO USER (ADMIN ONLY)
===================================================== */
router.post("/user-ledgers", requireAuth, requireAdmin, async (req, res) => {
  const { userId, ledgers } = req.body;

  if (!userId || !Array.isArray(ledgers)) {
    return res.status(400).json({ error: "Invalid payload" });
  }

  try {
    // 🔴 STEP 1: CLEAR OLD LEDGER ACCESS
    await pool.query(
      `DELETE FROM user_ledger_permissions WHERE user_id = $1`,
      [userId]
    );

    // 🟢 STEP 2: INSERT NEW ACCESS
    for (const ledgerGuid of ledgers) {
      const ledger = await pool.query(
        `SELECT ledger_guid, name
FROM ledgers
WHERE ledger_guid = $1
  AND admin_id = $2
`,
        [ledgerGuid, req.user.adminId]
      );

      if (!ledger.rows.length) continue;

      await pool.query(
        `
        INSERT INTO user_ledger_permissions (user_id, ledger_guid, ledger_name)
        VALUES ($1, $2, $3)
        `,
        [userId, ledgerGuid, ledger.rows[0].name]
      );
    }

    res.json({ success: true });
  } catch (err) {
    console.error("Save user-ledgers failed:", err);
    res.status(500).json({ error: err.message });
  }
});


// ========================================
// FETCH LEDGERS ASSIGNED TO A USER (ADMIN)
// ========================================
router.get("/users/:userId/ledgers", requireAuth, requireAdmin, async (req, res) => {
  const { userId } = req.params;

  try {
    const result = await pool.query(
      `
      SELECT ledger_guid
      FROM user_ledger_permissions
      WHERE user_id = $1
      `,
      [userId]
    );

    res.json(result.rows);
  } catch (err) {
    console.error("Fetch user ledgers failed:", err);
    res.status(500).json({ error: "Failed to fetch user ledgers" });
  }
});

router.post("/ledger/user-ledgers", requireAuth, requireAdmin, async (req, res) => {
  const userId = Number(req.body.userId);
  const ledgers = req.body.ledgers;

  if (!Number.isInteger(userId) || !Array.isArray(ledgers)) {
    return res.status(400).json({ error: "Invalid payload" });
  }

  try {
    await pool.query(
      `DELETE FROM user_ledger_permissions WHERE user_id = $1`,
      [userId]
    );

    for (const ledgerGuid of ledgers) {
      const ledger = await pool.query(
        `SELECT ledger_guid, name
FROM ledgers
WHERE ledger_guid = $1
  AND admin_id = $2
`,
        [ledgerGuid, req.user.adminId]
      );

      if (!ledger.rows.length) continue;

      await pool.query(
        `
        INSERT INTO user_ledger_permissions (user_id, ledger_guid, ledger_name)
        VALUES ($1, $2, $3)
        `,
        [userId, ledgerGuid, ledger.rows[0].name]
      );
    }

    res.json({ success: true });
  } catch (err) {
    console.error("Save user-ledgers failed:", err);
    res.status(500).json({ error: err.message });
  }
});

router.post("/cleanup/ledger", requireAuth, async (req, res) => {
  const { company_guid, existing_ids } = req.body;
  const adminId = req.user.adminId;

  if (!company_guid || !Array.isArray(existing_ids)) {
    return res.status(400).json({ error: "Invalid payload" });
  }

  try {

    // 🔹 Step 1: Find ledgers missing in Tally
    // 🔹 Step 1: Find ledgers missing in Tally
const toDelete = await pool.query(
  `
  SELECT *
  FROM ledgers
  WHERE admin_id = $1
    AND company_guid = $2
    AND ledger_guid <> ALL($3)
  `,
  [adminId, company_guid, existing_ids]
);

    const ledgers = toDelete.rows;

    if (ledgers.length === 0) {
      return res.json({ success: true, deleted: 0 });
    }

    const deleteGuids = ledgers.map(l => l.ledger_guid);

    // 🔹 Step 2: Save history BEFORE delete
    for (const ledger of ledgers) {
      await pool.query(
        `
        INSERT INTO deleted_records
        (admin_id, company_guid, entity_type, entity_guid, entity_data, deleted_from)
        VALUES ($1,$2,$3,$4,$5,$6)
        `,
        [
          adminId,
          company_guid,
          "ledger",
          ledger.ledger_guid,
          ledger,
          "tally_sync"
        ]
      );
    }

    // 🔹 Step 3: Remove user permissions
    await pool.query(
      `
      DELETE FROM user_ledger_permissions
      WHERE ledger_guid = ANY($1)
        AND user_id IN (SELECT id FROM users WHERE admin_id = $2)
      `,
      [deleteGuids, adminId]
    );

    // 🔹 Step 4: Delete ledgers
    const result = await pool.query(
      `
      DELETE FROM ledgers
      WHERE admin_id = $1
        AND company_guid = $2
        AND ledger_guid = ANY($3)
      `,
      [adminId, company_guid, deleteGuids]
    );

    res.json({
      success: true,
      deleted: result.rowCount
    });

  } catch (err) {
    console.error("Ledger cleanup failed:", err);
    res.status(500).json({ error: err.message });
  }
});

router.get("/deleted/history", requireAuth, async (req, res) => {

console.log("REQ USER:", req.user);


  const adminId = req.user.adminId;

  try {

    const result = await pool.query(
      `
      SELECT
        id,
        company_guid,
        entity_type,
        entity_guid,
        entity_data,
        deleted_at
      FROM deleted_records
      WHERE admin_id = $1
        AND entity_type = 'ledger'
      ORDER BY deleted_at DESC
      `,
      [adminId]
    );

    res.json({
      success: true,
      data: result.rows
    });

  } catch (err) {
    console.error("Deleted history fetch failed:", err);
    res.status(500).json({ error: err.message });
  }

});

router.post("/deleted/restore/:id", requireAuth, async (req, res) => {

  console.log("RESTORE LEDGER API HIT");

  const adminId = req.user.adminId;
  const { id } = req.params;

  try {

    const record = await pool.query(
      `
      SELECT *
      FROM deleted_records
      WHERE id = $1
      AND admin_id = $2
      AND entity_type = 'ledger'
      `,
      [id, adminId]
    );

    if (!record.rows.length) {
      return res.status(404).json({ error: "Record not found" });
    }

    const data =
      typeof record.rows[0].entity_data === "string"
        ? JSON.parse(record.rows[0].entity_data)
        : record.rows[0].entity_data;

    const payload = {
      ledger_guid: data.ledger_guid,
      name: data.name,
      parent_group: data.parent_group,
      opening_balance: data.opening_balance,
      email: data.email,
      phone: data.phone
    };

    // ====================================================
    // CHECK IF LEDGER EXISTS
    // ====================================================

    const existing = await pool.query(
      `
      SELECT 1
      FROM ledgers
      WHERE admin_id = $1
      AND company_guid = $2
      AND ledger_guid = $3
      `,
      [adminId, data.company_guid, data.ledger_guid]
    );

    // ====================================================
    // IF LEDGER EXISTS → ONLY QUEUE RESTORE
    // ====================================================

    if (existing.rowCount > 0) {

      console.log("Ledger exists, pushing queue for Tally restore");

      await pool.query(
        `
        INSERT INTO sync_queue
        (admin_id, company_guid, entity_type, entity_guid, action, payload, status)
        VALUES ($1,$2,$3,$4,$5,$6,'pending')
        ON CONFLICT (admin_id, company_guid, entity_type, entity_guid)
        DO UPDATE SET
          action = EXCLUDED.action,
          payload = EXCLUDED.payload,
          status = 'pending',
          created_at = now()
        `,
        [
          adminId,
          data.company_guid,
          "LEDGER",
          data.ledger_guid,
          "CREATE",
          JSON.stringify(payload)
        ]
      );

      await pool.query(
        `DELETE FROM deleted_records WHERE id = $1`,
        [id]
      );

      return res.json({
        success: true,
        message: "Ledger already exists in DB, queued for Tally restore"
      });
    }

    // ====================================================
    // RESTORE LEDGER INTO DATABASE
    // ====================================================

    await pool.query(
      `
      INSERT INTO ledgers
      (
        admin_id,
        ledger_guid,
        company_guid,
        name,
        email,
        phone,
        parent_group,
        opening_balance,
        closing_balance,
        type
      )
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
      ON CONFLICT (admin_id, company_guid, ledger_guid)
      DO NOTHING
      `,
      [
        adminId,
        data.ledger_guid,
        data.company_guid,
        data.name,
        data.email,
        data.phone,
        data.parent_group,
        data.opening_balance,
        data.closing_balance,
        data.type
      ]
    );

    // ====================================================
    // PUSH RESTORE COMMAND TO AGENT
    // ====================================================

    await pool.query(
      `
      INSERT INTO sync_queue
      (admin_id, company_guid, entity_type, entity_guid, action, payload, status)
      VALUES ($1,$2,$3,$4,$5,$6,'pending')
      ON CONFLICT (admin_id, company_guid, entity_type, entity_guid)
      DO UPDATE SET
        action = EXCLUDED.action,
        payload = EXCLUDED.payload,
        status = 'pending',
        created_at = now()
      `,
      [
        adminId,
        data.company_guid,
        "LEDGER",
        data.ledger_guid,
        "CREATE",
        JSON.stringify(payload)
      ]
    );

    // ====================================================
    // REMOVE HISTORY RECORD
    // ====================================================

    await pool.query(
      `DELETE FROM deleted_records WHERE id = $1`,
      [id]
    );

    res.json({
      success: true,
      message: "Ledger restored and queued for Tally"
    });

  } catch (err) {
    console.error("Restore failed:", err);
    res.status(500).json({ error: err.message });
  }

});

// =====================================================
// FETCH LEDGER DETAILS (ADMIN / USER)
// =====================================================
router.get("/:ledgerGuid", requireAuth, async (req, res) => {
  const { ledgerGuid } = req.params;
  const role = req.user.role;

  // ✅ MUST MATCH user_ledger_permissions.user_id (INTEGER)
  const userId = req.user.id; // <-- ensure this is users.id


  try {
    // ✅ ADMIN → FULL ACCESS
    if (role === "ADMIN") {
      const result = await pool.query(
        `SELECT *
FROM ledgers
WHERE ledger_guid = $1
  AND admin_id = $2`,
        [ledgerGuid, req.user.adminId]
      );

      if (!result.rows.length) {
        return res.status(404).json({ message: "Ledger not found" });
      }

      return res.json(result.rows[0]);
    }

    // ✅ USER → PERMISSION CHECK BY ledger_guid
    const check = await pool.query(
  `
  SELECT 1
  FROM user_ledger_permissions ulp
  JOIN ledgers l
    ON l.ledger_guid = ulp.ledger_guid
  WHERE ulp.user_id = $1
    AND ulp.ledger_guid = $2
    AND l.admin_id = $3
  `,
  [userId, ledgerGuid, req.user.adminId]
);


    if (check.rowCount === 0) {
      return res.status(403).json({ message: "Access denied" });
    }

    // ✅ USER HAS ACCESS
    const result = await pool.query(
      `SELECT *
FROM ledgers
WHERE ledger_guid = $1
  AND admin_id = $2
`,
     [ledgerGuid, req.user.adminId]
    );

    if (!result.rows.length) {
      return res.status(404).json({ message: "Ledger not found" });
    }

    res.json(result.rows[0]);
  } catch (err) {
    console.error("Ledger details error:", err);
    res.status(500).json({ message: "Failed to fetch ledger details" });
  }
});

export default router;
