-- Voucher status: cancelled / optional / built-in type, and whether the
-- voucher is in the books (Tally's P&L, Balance Sheet, Trial Balance and
-- Cash Flow leave out cancelled, optional and order / note / stock vouchers).
--
-- Only adds empty (NULL) columns: no row is changed, nothing is rewritten.
-- NULL = not known yet = every report counts the voucher exactly as today.
-- The values arrive as the new Agent re-reads the vouchers (one full pass).
-- Safe to run more than once.

ALTER TABLE vouchers ADD COLUMN IF NOT EXISTS is_cancelled BOOLEAN;
ALTER TABLE vouchers ADD COLUMN IF NOT EXISTS is_optional BOOLEAN;
ALTER TABLE vouchers ADD COLUMN IF NOT EXISTS base_type VARCHAR(100);
ALTER TABLE vouchers ADD COLUMN IF NOT EXISTS is_accounting BOOLEAN;
ALTER TABLE voucher_entries ADD COLUMN IF NOT EXISTS is_accounting BOOLEAN;

-- Check (read only): the five columns are there.
SELECT table_name, column_name, data_type
  FROM information_schema.columns
 WHERE table_schema = current_schema()
   AND ((table_name = 'vouchers' AND column_name IN ('is_cancelled', 'is_optional', 'base_type', 'is_accounting'))
     OR (table_name = 'voucher_entries' AND column_name = 'is_accounting'))
 ORDER BY table_name, column_name;
