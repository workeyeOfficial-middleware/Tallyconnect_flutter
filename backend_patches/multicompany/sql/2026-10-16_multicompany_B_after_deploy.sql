-- =====================================================================
--  Multi-company sync — PART B: run AFTER the new backend is live
--  (it no longer uses these keys). Removes the company-only unique keys
--  that stop a SECOND account from syncing the same Tally company.
--  Each table keeps its account-scoped unique key (listed beside it).
--  No rows are changed or deleted.
-- =====================================================================
BEGIN;

-- ledgers: keeps unique_ledger_per_admin_company (admin_id, company_guid, ledger_guid)
ALTER TABLE ledgers DROP CONSTRAINT IF EXISTS ledgers_company_ledger_unique;
DROP INDEX IF EXISTS ledgers_company_ledger_unique;

-- invoices: keeps uq_invoices_admin_company_guid (admin_id, company_guid, invoice_guid)
ALTER TABLE invoices DROP CONSTRAINT IF EXISTS invoices_invoice_guid_company_guid_unique;
DROP INDEX IF EXISTS invoices_invoice_guid_company_guid_unique;

-- orders: keeps uq_orders_admin_company_guid (PART A)
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_order_guid_key;
DROP INDEX IF EXISTS orders_order_guid_key;

-- sales_orders: keeps the primary key (admin_id, order_guid)
ALTER TABLE sales_orders DROP CONSTRAINT IF EXISTS uq_sales_orders_guid;
DROP INDEX IF EXISTS uq_sales_orders_guid;

-- voucher_bill_map: keeps uq_vbm_admin_company (PART A)
ALTER TABLE voucher_bill_map DROP CONSTRAINT IF EXISTS voucher_bill_map_company_guid_voucher_guid_bill_ref_key;
DROP INDEX IF EXISTS voucher_bill_map_company_guid_voucher_guid_bill_ref_key;

COMMIT;

-- Check (should return no rows):
-- SELECT indexname FROM pg_indexes WHERE indexname IN (
--   'ledgers_company_ledger_unique','invoices_invoice_guid_company_guid_unique',
--   'orders_order_guid_key','uq_sales_orders_guid',
--   'voucher_bill_map_company_guid_voucher_guid_bill_ref_key');
