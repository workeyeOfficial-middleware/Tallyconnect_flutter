import express from "express";
import pool from "../db.js";
import requireAuth from "../middleware/requireAuth.js";
import { createNotification } from "../utils/notification.js";
import { randomUUID } from "crypto";
const router = express.Router();

const MONTHS = { jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12 };

/**
 * A date as Tally's bill reports send it ("4-Apr-24", "4-Apr-2024",
 * "20240404" or "2024-04-04") → "YYYY-MM-DD"; null when it is not a date.
 */
export function tallyDate(v) {
  const t = String(v ?? "").trim();
  let y, m, d;
  let x;
  if ((x = /^(\d{1,2})-([A-Za-z]{3})-(\d{2}|\d{4})$/.exec(t))) {
    d = Number(x[1]);
    m = MONTHS[x[2].toLowerCase()];
    y = x[3].length === 2 ? 2000 + Number(x[3]) : Number(x[3]);
  } else if ((x = /^(\d{4})-?(\d{2})-?(\d{2})$/.exec(t))) {
    [y, m, d] = [Number(x[1]), Number(x[2]), Number(x[3])];
  } else {
    return null;
  }
  const dt = new Date(Date.UTC(y, (m || 0) - 1, d));
  if (!m || dt.getUTCFullYear() !== y || dt.getUTCMonth() !== m - 1 || dt.getUTCDate() !== d) return null;
  return dt.toISOString().slice(0, 10);
}

/**
 * POST /bill/sync
 * Used by Tally Agent
 */
router.post("/sync", requireAuth, async (req, res) => {
  try {
    const {
      company_guid,
      ledger_name,
      bill_guid,
      bill_name,
      bill_amount,
      pending_amount,
      due_date,
      bill_date,
      bill_type
    } = req.body;

    if (
      !company_guid ||
      !ledger_name ||
      !bill_name ||
      !ledger_name.trim() ||
      !bill_name.trim()
    ) {
      return res.status(400).json({
        success: false,
        message: "company_guid, ledger_name, bill_name required"
      });
    }

    const safeBillAmount =
      typeof bill_amount === "number" ? bill_amount : 0;

    const safePendingAmount =
      typeof pending_amount === "number" ? pending_amount : 0;

    const billStatus =
      safePendingAmount === 0 ? "Settled" : "Pending";

    const safeDueDate =
      due_date && !isNaN(Date.parse(due_date)) ? due_date : null;

    // The bill's date from Tally (the Agent always sent it; it was not
    // saved, so Bill date and Credit period were blank in the app).
    const safeBillDate = tallyDate(bill_date);

    const finalBillGuid = bill_guid || randomUUID();

    // ✅ FIXED: use bill_type from body
    const finalBillType =
      bill_type === "PAYABLE" ? "PAYABLE" : "RECEIVABLE";

    const ledgerRes = await pool.query(
      `
      SELECT ledger_guid
      FROM ledgers
      WHERE company_guid = $1
        AND name = $2
        AND admin_id = $3
      LIMIT 1
      `,
      [company_guid, ledger_name.trim(), req.user.adminId]
    );

    const ledger_guid = ledgerRes.rows[0]?.ledger_guid || null;

    await pool.query(
      `
      INSERT INTO bills (
        admin_id,
        company_guid,
        bill_guid,
        ledger_guid,
        ledger_name,
        bill_name,
        bill_amount,
        pending_amount,
        due_date,
        bill_type,
        status,
        bill_date
      )
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
      ON CONFLICT (admin_id, company_guid, ledger_name, bill_name)
      DO UPDATE SET
        bill_amount = EXCLUDED.bill_amount,
        pending_amount = EXCLUDED.pending_amount,
        due_date = EXCLUDED.due_date,
        bill_type = EXCLUDED.bill_type,
        bill_date = COALESCE(EXCLUDED.bill_date, bills.bill_date),
        status = CASE
          WHEN EXCLUDED.pending_amount = 0 THEN 'Settled'
          ELSE 'Pending'
        END
      `,
      [
        req.user.adminId,
        company_guid,
        finalBillGuid,
        ledger_guid,
        ledger_name.trim(),
        bill_name.trim(),
        safeBillAmount,
        safePendingAmount,
        safeDueDate,
        finalBillType,  // ✅ ADDED
        billStatus,
        safeBillDate
      ]
    );

    res.json({ success: true });
  } catch (err) {
    console.error("❌ bill/sync error:", err);
    res.status(500).json({ success: false, error: err.message });
  }
});




/**
 * POST /bill/push-to-tally
 * Used by UI → Push bill into Tally Prime
 */
router.post("/push-to-tally", requireAuth, async (req, res) => {


  try {
    const {
      company_guid,
      bill_guid, 
      ledger_guid,
      bill_name,
      bill_date,
      due_date,
      amount,
      voucher_type
    } = req.body;

    const adminId = req.user.adminId;

    if (!company_guid || !ledger_guid || !bill_name || !bill_date || !amount) {
      return res.status(400).json({ message: "Missing fields" });
    }

    const check = await pool.query(
      `SELECT 1 FROM companies WHERE company_guid=$1 AND admin_id=$2`,
      [company_guid, adminId]
    );
    if (!check.rowCount) {
      return res.status(403).json({ message: "Access denied" });
    }

    const ledgerRes = await pool.query(
      `SELECT name
       FROM ledgers
       WHERE ledger_guid = $1
         AND company_guid = $2
         AND admin_id = $3`,
      [ledger_guid, company_guid, adminId]
    );
    if (!ledgerRes.rowCount) {
      return res.status(404).json({ message: "Ledger not found" });
    }

    const ledger_name = ledgerRes.rows[0].name;

    const safeBillAmount =
  typeof amount === "number" ? amount : 0;

const safePendingAmount = safeBillAmount; // full amount pending initially

const billStatus =
  safePendingAmount === 0 ? "Settled" : "Pending";

const safeDueDate =
  due_date && !isNaN(Date.parse(due_date)) ? due_date : null;

const finalBillGuid = bill_guid || randomUUID();

const finalBillType =
  voucher_type === "Purchase" ? "PAYABLE" : "RECEIVABLE";

  
await pool.query(
  `
  INSERT INTO bills (
  admin_id,
  company_guid,
  bill_guid,
  ledger_guid,
  ledger_name,
  bill_name,
  bill_amount,
  pending_amount,
  due_date,
  bill_type,
  status
)
VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)

  ON CONFLICT (admin_id, company_guid, bill_guid, bill_name)
  DO UPDATE SET
    bill_amount = EXCLUDED.bill_amount,
    pending_amount = EXCLUDED.pending_amount,
    due_date = EXCLUDED.due_date,
    status = CASE
      WHEN EXCLUDED.pending_amount = 0 THEN 'Settled'
      ELSE 'Pending'
    END
  `,
  [
  req.user.adminId,
  company_guid,
  finalBillGuid,
  ledger_guid,
  ledger_name.trim(),
  bill_name.trim(),
  safeBillAmount,
  safePendingAmount,
  safeDueDate,
  finalBillType,   // ✅ ADD THIS
  billStatus
]

);




    // Notification code...
    try {
      await createNotification({
        type: "BILL",
        user_id: adminId,
        message: `🧾 Bill ${bill_name} created for ${ledger_name} (₹${amount})`
      });
    } catch (err) {
      console.error("Notification failed:", err.message);
    }

    await pool.query(
  `
  INSERT INTO sync_queue
  (admin_id, company_guid, entity_type, entity_guid, action, payload)
  VALUES ($1, $2, 'BILL', $3, 'CREATE', $4)
  `,
  [
    req.user.adminId,
    company_guid,
    finalBillGuid,   // ✅ REQUIRED FIX
    {
      ledger_name,
      bill_name,
      bill_date,
      due_date,
      amount,
      voucher_type: voucher_type === "Purchase" ? "Purchase" : "Sales"
    }
  ]
);

    res.json({ success: true, message: "Bill queued for sync" });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: "Failed to queue bill" });
  }
});


/**
 * GET /bill
 */
router.get("/", requireAuth, async (req, res) => {
  try {
    const result = await pool.query(
  `
  SELECT *
  FROM bills
  WHERE admin_id = $1
  ORDER BY due_date ASC
  `,
  [req.user.adminId]
);

    res.json({ success: true, data: result.rows });
  } catch (err) {
    console.error("❌ bill fetch error:", err);
    res.status(500).json({ success: false });
  }
});

// =====================================================
// 🆕 GET BILLS BY LEDGER (READ-ONLY, SAFE)
// =====================================================
// router.get("/ledger/:ledgerGuid", requireAuth, async (req, res) => {
//   try {
//     const { ledgerGuid } = req.params;
//     const { role, id: userId, adminId } = req.user;

//     // 🔒 USER permission check (same pattern everywhere)
//     if (role !== "ADMIN") {
//       const check = await pool.query(
//         `
//        SELECT 1
// FROM user_ledger_permissions ulp
// JOIN ledgers l ON l.ledger_guid = ulp.ledger_guid
// WHERE ulp.user_id = $1
//   AND ulp.ledger_guid = $2
//   AND l.admin_id = $3

//         `,
// [userId, ledgerGuid, adminId]
//       );

//       if (check.rowCount === 0) {
//         return res.status(403).json({ message: "Access denied" });
//       }
//     }

//    const { rows } = await pool.query(
//   `
//   SELECT
//     bill_name,
//     ledger_name,
//     due_date,
//     pending_amount
//  FROM bills
// WHERE ledger_guid = $1
//   AND admin_id = $2
//   AND company_guid = (
//     SELECT company_guid
//     FROM active_company
//     WHERE admin_id = $2
//   )

//   ORDER BY due_date ASC
//   `,
//   [ledgerGuid, adminId]
// );


//     res.json(rows);
//   } catch (err) {
//     console.error("Ledger bills fetch error:", err);
//     res.status(500).json({ message: "Failed to fetch bills" });
//   }
// });


// New
router.get("/ledger/:ledgerGuid", requireAuth, async (req, res) => {
  try {
    const { ledgerGuid } = req.params;
    const { role, id: userId, adminId } = req.user;

    if (role !== "ADMIN") {
      const check = await pool.query(
        `
        SELECT 1
        FROM user_ledger_permissions ulp
        JOIN ledgers l ON l.ledger_guid = ulp.ledger_guid
        WHERE ulp.user_id = $1
          AND ulp.ledger_guid = $2
          AND l.admin_id = $3
        `,
        [userId, ledgerGuid, adminId]
      );

      if (check.rowCount === 0) {
        return res.status(403).json({ message: "Access denied" });
      }
    }

    const ledgerRes = await pool.query(
      `SELECT name FROM ledgers WHERE ledger_guid = $1 AND admin_id = $2 LIMIT 1`,
      [ledgerGuid, adminId]
    );
    if (!ledgerRes.rowCount) {
      return res.status(404).json({ message: "Ledger not found" });
    }
    const ledgerName = ledgerRes.rows[0].name;

    const companyRes = await pool.query(
      `SELECT company_guid FROM active_company WHERE admin_id = $1 LIMIT 1`,
      [adminId]
    );
    const companyGuid = companyRes.rows[0]?.company_guid || null;

const { rows } = await pool.query(
      `
      SELECT bill_name, ledger_name, bill_date, due_date, pending_amount, bill_type
      FROM bills
      WHERE ledger_guid = $1
        AND admin_id = $2
        AND company_guid = $3
        AND pending_amount > 0
      ORDER BY due_date ASC
      `,
      [ledgerGuid, adminId, companyGuid]
    );

    let itemRows = [];
    let mapRows = [];
    if (companyGuid) {
      const itemRes = await pool.query(
        `
        SELECT voucher_guid, voucher_no, item_name,
               SUM(quantity) AS total_qty,
               SUM(amount)   AS total_amount
        FROM ledger_items
        WHERE admin_id = $1 AND company_guid = $2
          AND lower(btrim(regexp_replace(ledger_name, '[[:space:]]+', ' ', 'g')))
            = lower(btrim(regexp_replace($3::text, '[[:space:]]+', ' ', 'g')))
        GROUP BY voucher_guid, voucher_no, item_name
        `,
        [adminId, companyGuid, ledgerName]
      );
      itemRows = itemRes.rows;

      const mapRes = await pool.query(
        `
        SELECT voucher_guid, bill_ref
        FROM voucher_bill_map
        WHERE company_guid = $1
        `,
        [companyGuid]
      );
      mapRows = mapRes.rows;
    }

    const data = rows.map((b) => {
      const guids = new Set(
        mapRows
          .filter((m) => m.bill_ref === b.bill_name)
          .map((m) => m.voucher_guid)
      );
      const matched = itemRows.filter(
        (i) =>
          (i.voucher_guid && guids.has(i.voucher_guid)) ||
          (!guids.size && i.voucher_no && i.voucher_no === b.bill_name)
      );
      return { ...b, items: matched };
    });

    res.json(data);
  } catch (err) {
    console.error("Ledger bills fetch error:", err);
    res.status(500).json({ message: "Failed to fetch bills", error: err.message });
  }
});

// error is coming that's why added this route
router.post("/ensure-voucher-bill-map", requireAuth, async (req, res) => {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS voucher_bill_map (
        id SERIAL PRIMARY KEY,
        admin_id INT NOT NULL,
        company_guid UUID NOT NULL,
        voucher_guid UUID NOT NULL,
        bill_ref TEXT NOT NULL,
        bill_type TEXT,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        UNIQUE (company_guid, voucher_guid, bill_ref)
      )
    `);
    const { rows } = await pool.query(
      `SELECT table_schema FROM information_schema.tables WHERE table_name = 'voucher_bill_map'`
    );
    res.json({ success: true, found_in_schemas: rows.map(r => r.table_schema) });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});



router.post("/mark-processing", requireAuth, async (req, res) => {
  const { bill_name, company_guid } = req.body;

  await pool.query(
  `
  UPDATE bills
  SET sync_status='PROCESSING'
  WHERE bill_name = $1
    AND company_guid = $2
    AND admin_id = $3
  `,
  [bill_name, company_guid, req.user.adminId]
);


  res.json({ success: true });
});

router.post("/mark-success", requireAuth, async (req, res) => {
  const { bill_name, company_guid } = req.body;

  await pool.query(
  `
  UPDATE bills
  SET sync_status='SYNCED',
      synced_at=now(),
      sync_error=NULL
  WHERE bill_name = $1
    AND company_guid = $2
    AND admin_id = $3
  `,
  [bill_name, company_guid, req.user.adminId]
);



  res.json({ success: true });
});

router.post("/mark-failed", requireAuth, async (req, res) => {
  const { bill_name, company_guid, error } = req.body;

  await pool.query(
  `
  UPDATE bills
  SET sync_status='FAILED',
      sync_error=$4
  WHERE bill_name = $1
    AND company_guid = $2
    AND admin_id = $3
  `,
  [bill_name, company_guid, req.user.adminId, error]
);


  res.json({ success: true });
});

// =====================================================
// 🆕 DASHBOARD BILL SUMMARY (THIS FIXES EVERYTHING)
// =====================================================
router.get("/dashboard-summary", requireAuth, async (req, res) => {
  try {
    const { company_guid } = req.query;

    if (!company_guid) {
      return res.status(400).json({ message: "company_guid required" });
    }

    const { rows } = await pool.query(
      `
      SELECT
  COALESCE(SUM(pending_amount), 0) AS total_outstanding,
  COUNT(*) FILTER (WHERE pending_amount > 0) AS pending_bills,
  COUNT(*) FILTER (WHERE pending_amount = 0) AS settled_bills
FROM bills
WHERE company_guid = $1
  AND admin_id = $2


      `,
      [company_guid, req.user.adminId]

    );

    res.json(rows[0]);
  } catch (err) {
    console.error("Dashboard bill summary error:", err);
    res.status(500).json({ message: "Failed to load dashboard summary" });
  }
});

router.post("/mark-all-cleared", requireAuth, async (req, res) => {
  const { company_guid } = req.body;
  const adminId = req.user.adminId;

  await pool.query(
    `
    UPDATE bills
    SET pending_amount = 0,
        status = 'Settled'
    WHERE company_guid = $1
      AND admin_id = $2
    `,
    [company_guid, adminId]
  );

  res.json({ success: true });
});

router.post("/reconcile", requireAuth, async (req, res) => {
  const { company_guid, existing_bill_names } = req.body;

  await pool.query(
    `
    UPDATE bills
    SET pending_amount = 0,
        status = 'Settled'
    WHERE company_guid = $1
      AND admin_id = $2
      AND bill_name NOT IN (
        SELECT unnest($3::text[])
      )
    `,
    [company_guid, req.user.adminId, existing_bill_names]
  );

  res.json({ success: true });
});

export default router;
