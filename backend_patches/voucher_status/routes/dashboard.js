import express from "express";
import pool from "../db.js";
import requireAuth from "../middleware/requireAuth.js";
import { hasVoucherStatusColumns, IN_BOOKS } from "../utils/voucherStatus.js";

const router = express.Router();

/* =====================================================
   SUMMARY
===================================================== */
router.get("/summary", requireAuth, async (req, res) => {
  const { company_guid } = req.query;
  const adminId = req.user.adminId;

  if (!company_guid) {
    return res.status(400).json({ message: "company_guid required" });
  }

  try {
    const { rows } = await pool.query(`
      SELECT
        /* RECEIVABLE ONLY */
COALESCE(SUM(
  CASE 
    WHEN pending_amount > 0 
         AND bill_type = 'RECEIVABLE'
    THEN pending_amount
  END
),0)::numeric AS receivables,


          /* PAYABLE (Purchase Bills) */
COALESCE(SUM(
  CASE 
    WHEN pending_amount > 0 
         AND bill_type = 'PAYABLE'
    THEN pending_amount
  END
),0)::numeric AS payables,






        COUNT(*) FILTER (
          WHERE pending_amount != 0
        ) AS pending_bills,

        COUNT(*) FILTER (
          WHERE pending_amount = 0
        ) AS cleared_bills

      FROM bills
      WHERE company_guid = $1
        AND admin_id = $2
    `, [company_guid, adminId]);

    res.json(rows[0] || {
      receivables: 0,
      payables: 0,
      pending_bills: 0,
      cleared_bills: 0
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: "Summary failed" });
  }
});




/* =====================================================
   MONTHLY INCOME / EXPENSE
===================================================== */
router.get("/income-expense", requireAuth, async (req, res) => {
  const { company_guid } = req.query;
  const adminId = req.user.adminId;

  try {
    // Once known (voucherStatus.js): not cancelled / optional, and not an
    // order or note ("Purchase Order" matched 'purchase%').
    const books = (await hasVoucherStatusColumns(pool)) ? `AND ${IN_BOOKS("vouchers")}` : "";
    const { rows } = await pool.query(
      `
      SELECT
        DATE_TRUNC('month', voucher_date) AS month,

        /* ✅ SALES ONLY */
        COALESCE(SUM(
          CASE 
            WHEN voucher_type ILIKE 'sales%'

            THEN net_amount
          END
        ),0)::numeric AS income,

        /* ✅ PURCHASE ONLY */
        COALESCE(SUM(
          CASE 
            WHEN voucher_type ILIKE 'purchase%'
            THEN net_amount
          END
        ),0)::numeric AS expense

      FROM vouchers
      WHERE company_guid = $1
        AND admin_id = $2
        AND is_active = true
        ${books}

      GROUP BY month
      ORDER BY month ASC
      `,
      [company_guid, adminId]
    );

    res.json(rows);
  } catch (err) {
    console.error("Income/Expense error:", err);
    res.status(500).json({ message: "Failed to load income/expense" });
  }
});

/* =====================================================
   OUTSTANDING BILLS (FOR LIST + DASHBOARD USE)
===================================================== */
router.get("/bills", requireAuth, async (req, res) => {
  const { company_guid } = req.query;
  const adminId = req.user.adminId;

  try {
    const { rows } = await pool.query(
      `
      SELECT
        ledger_name,
        pending_amount::numeric,
        due_date
      FROM bills
      WHERE company_guid = $1
        AND admin_id = $2
        AND pending_amount > 0
      ORDER BY due_date ASC NULLS LAST
      `,
      [company_guid, adminId]
    );

    res.json(rows);
  } catch (err) {
    console.error("Bills fetch error:", err);
    res.status(500).json({ message: "Failed to load bills" });
  }
});

export default router;
