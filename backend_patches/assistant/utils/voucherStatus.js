/* =========================================================
   VOUCHER STATUS — is a voucher in the books?
   Tally's books (P&L, Balance Sheet, Trial Balance, Cash Flow, ledgers)
   leave out:
     - cancelled vouchers (ISCANCELLED) and optional ones (ISOPTIONAL);
     - vouchers whose built-in type does not post to the accounts: orders,
       delivery / receipt notes, rejections, stock journals, physical stock,
       memorandum, … — whatever the company renamed them to ("Replacement"
       is Tally's Delivery Note) or made under them ("Delivery Challan").
   The Agent sends is_cancelled, is_optional and base_type (the built-in
   type); vouchers.is_accounting / voucher_entries.is_accounting keep the
   answer. NULL = not known (an older Agent, or a database before
   sql/2026-10-22_voucher_status.sql): reports count it as they always did.
   Columns looked up again every 10 minutes.
========================================================= */
let cached = null;

/** Whether the database has the five columns (not cached; false on error). */
export async function checkVoucherStatusColumns(db) {
  try {
    const r = await db.query(
      `SELECT table_name, column_name FROM information_schema.columns
        WHERE table_schema = current_schema()
          AND ((table_name = 'vouchers'
                AND column_name IN ('is_cancelled', 'is_optional', 'base_type', 'is_accounting'))
            OR (table_name = 'voucher_entries' AND column_name = 'is_accounting'))`
    );
    return (r?.rows || []).length === 5;
  } catch {
    return false;
  }
}

export async function hasVoucherStatusColumns(db) {
  if (cached && Date.now() - cached.at < 10 * 60 * 1000) return cached.on;
  cached = { at: Date.now(), on: await checkVoucherStatusColumns(db) };
  return cached.on;
}

/** Tests: forget the cached lookup. */
export function resetVoucherStatusCache() {
  cached = null;
}

/** Tally's built-in voucher types that post to the books of accounts. */
export const ACCOUNTING_TYPES = new Set([
  "sales",
  "purchase",
  "receipt",
  "payment",
  "journal",
  "contra",
  "credit note",
  "debit note",
  "payroll",
]);

const flag = (v) => (typeof v === "boolean" ? v : null);

/**
 * The status the Agent sent → what is stored. is_accounting: false when
 * cancelled / optional / a non-accounting built-in type, true for an
 * accounting type, null when the built-in type was not sent.
 */
export function voucherStatus({ is_cancelled, is_optional, base_type } = {}) {
  const cancelled = flag(is_cancelled);
  const optional = flag(is_optional);
  const base = typeof base_type === "string" && base_type.trim() ? base_type.trim().slice(0, 100) : null;
  let accounting = null;
  if (cancelled === true || optional === true) accounting = false;
  else if (base) accounting = ACCOUNTING_TYPES.has(base.toLowerCase());
  return { cancelled, optional, base, accounting };
}

/**
 * SQL condition: the line / voucher with alias [alias] is in the books
 * (NULL = not known = counted, as before). Use only when
 * hasVoucherStatusColumns() is true.
 */
export const IN_BOOKS = (alias) => `COALESCE(${alias}.is_accounting, TRUE) = TRUE`;
