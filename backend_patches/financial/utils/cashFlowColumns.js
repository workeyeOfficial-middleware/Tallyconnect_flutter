/* =========================================================
   CASH FLOW COLUMNS — vouchers.has_cash_flow (Tally's HASCASHFLOW flag)
   and voucher_entries.gross_dr / gross_cr (a line's Dr and Cr before
   netting). Added by sql/2026-10-21_cashflow_flag.sql; until that has run
   the voucher sync stores what it stored before (never fails on them).
   Looked up again every 10 minutes.
========================================================= */
let cached = null;

export async function hasCashFlowColumns(db) {
  if (cached && Date.now() - cached.at < 10 * 60 * 1000) return cached.on;
  try {
    const r = await db.query(
      `SELECT table_name, column_name FROM information_schema.columns
        WHERE table_schema = current_schema()
          AND ((table_name = 'vouchers' AND column_name = 'has_cash_flow')
            OR (table_name = 'voucher_entries' AND column_name IN ('gross_dr', 'gross_cr')))`
    );
    cached = { at: Date.now(), on: r.rows.length === 3 };
  } catch {
    cached = { at: Date.now(), on: false };
  }
  return cached.on;
}

/** A line's gross Dr / Cr from the Agent (null when not sent). */
export const grossAmount = (v) =>
  v === undefined || v === null || v === "" || !Number.isFinite(Number(v)) ? null : Math.abs(Number(v));
