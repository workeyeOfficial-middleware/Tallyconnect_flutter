-- =====================================================================
--  Cash flow forecast — OPTIONAL speed-up indexes (no new tables, no data
--  change). The forecast works without them; they help big companies.
--  CREATE INDEX CONCURRENTLY does not block the Agent's uploads. Run each
--  statement ON ITS OWN (not inside BEGIN/COMMIT), auto-commit on.
--  Skip a statement if an equivalent index already exists.
-- =====================================================================

-- Each party's vouchers (payment delays).
CREATE INDEX CONCURRENTLY IF NOT EXISTS voucher_entries_cashflow_idx
  ON voucher_entries (admin_id, company_guid, ledger_name, voucher_date);

-- Open bills of one company.
CREATE INDEX CONCURRENTLY IF NOT EXISTS bills_cashflow_idx
  ON bills (admin_id, company_guid);

-- Check (read-only):
-- SELECT indexname FROM pg_indexes WHERE indexname LIKE '%cashflow%';

-- Rollback (only if you want them gone):
-- DROP INDEX CONCURRENTLY IF EXISTS voucher_entries_cashflow_idx;
-- DROP INDEX CONCURRENTLY IF EXISTS bills_cashflow_idx;
