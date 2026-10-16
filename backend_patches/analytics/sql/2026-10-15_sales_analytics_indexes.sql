-- =====================================================================
--  Sales analytics — OPTIONAL speed-up indexes (no new tables, no data change)
--  The dashboard works without them; they help big companies.
--  CREATE INDEX CONCURRENTLY does not block the Agent's uploads. Run each
--  statement ON ITS OWN (not inside BEGIN/COMMIT), auto-commit on.
--  Skip a statement if an equivalent index already exists.
-- =====================================================================

CREATE INDEX CONCURRENTLY IF NOT EXISTS vouchers_analytics_idx
  ON vouchers (admin_id, company_guid, voucher_date);

CREATE INDEX CONCURRENTLY IF NOT EXISTS ledger_items_voucher_idx
  ON ledger_items (admin_id, company_guid, voucher_guid);
