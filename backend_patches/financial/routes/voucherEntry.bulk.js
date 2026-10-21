import express from "express";
import pool from "../db.js";
import requireAuth from "../middleware/requireAuth.js";
import { grossAmount, hasCashFlowColumns } from "../utils/cashFlowColumns.js";

const router = express.Router();

/* =====================================================
   BULK VOUCHER LINES
   rows: [{voucher_guid, company_guid, ledger_name, amount, is_debit,
           voucher_date, voucher_type, reference_no, gross_dr?, gross_cr?}]
   Same rules as POST /voucher-entry/sync: the account's own companies
   only, one transaction per voucher, lines upserted on the same key, and
   lines no longer in a voucher made inactive (only when that voucher's
   rows carry real amounts). Earlier this route had no login check, no
   account scope and no database import (every call failed).
===================================================== */
router.post("/bulk-sync", requireAuth, async (req, res) => {
  const adminId = req.user?.adminId;
  const rows = req.body;

  if (!adminId || !Array.isArray(rows)) {
    return res.status(400).json({ success: false });
  }

  // Rows grouped per voucher (company + voucher GUID).
  const byVoucher = new Map();
  for (const r of rows) {
    if (!r || !r.voucher_guid || !r.company_guid || !r.ledger_name) continue;
    if (r.amount === undefined || r.is_debit === undefined) continue;
    const key = `${r.company_guid}\u0000${r.voucher_guid}`;
    if (!byVoucher.has(key)) byVoucher.set(key, []);
    byVoucher.get(key).push(r);
  }

  // A line's gross Dr / Cr (Tally's Cash Flow) once the database has them.
  const cf = await hasCashFlowColumns(pool);
  const owned = new Map(); // company_guid → belongs to this account
  let saved = 0;
  let skipped = 0;
  const client = await pool.connect();
  try {
    for (const lines of byVoucher.values()) {
      const { company_guid, voucher_guid } = lines[0];
      if (!owned.has(company_guid)) {
        const c = await client.query(
          `SELECT 1 FROM companies WHERE company_guid = $1 AND admin_id = $2`,
          [company_guid, adminId]
        );
        owned.set(company_guid, c.rowCount > 0);
      }
      if (!owned.get(company_guid)) {
        skipped += lines.length;
        continue;
      }
      try {
        await client.query("BEGIN");
        for (const r of lines) {
          await client.query(
            `
            INSERT INTO voucher_entries (
              admin_id, voucher_guid, company_guid, ledger_name, amount,
              is_debit, voucher_date, voucher_type, reference_no,${cf ? " gross_dr, gross_cr," : ""} is_active
            )
            VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,${cf ? "$10,$11," : ""}true)
            ON CONFLICT (admin_id, company_guid, voucher_guid, ledger_name)
            DO UPDATE SET
              amount = EXCLUDED.amount,
              is_debit = EXCLUDED.is_debit,
              voucher_date = EXCLUDED.voucher_date,
              voucher_type = EXCLUDED.voucher_type,
              reference_no = EXCLUDED.reference_no,
              ${cf ? "gross_dr = EXCLUDED.gross_dr, gross_cr = EXCLUDED.gross_cr," : ""}
              is_active = true
            `,
            [
              adminId,
              voucher_guid,
              company_guid,
              r.ledger_name,
              Math.abs(Number(r.amount) || 0),
              r.is_debit,
              r.voucher_date,
              r.voucher_type,
              r.reference_no,
              ...(cf ? [grossAmount(r.gross_dr), grossAmount(r.gross_cr)] : []),
            ]
          );
        }
        if (lines.some((r) => Number(r.amount) !== 0)) {
          await client.query(
            `
            UPDATE voucher_entries
            SET is_active = false
            WHERE admin_id = $1
              AND company_guid = $2
              AND voucher_guid = $3
              AND is_active IS DISTINCT FROM false
              AND NOT (ledger_name = ANY($4::text[]))
            `,
            [adminId, company_guid, voucher_guid, lines.map((r) => r.ledger_name)]
          );
        }
        await client.query("COMMIT");
        saved += lines.length;
      } catch (err) {
        await client.query("ROLLBACK").catch(() => {});
        console.error("Bulk voucher lines error:", err.message);
        skipped += lines.length;
      }
    }
  } finally {
    client.release();
  }

  res.json({ success: true, saved, skipped });
});

export default router;
