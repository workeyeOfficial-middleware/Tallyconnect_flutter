-- =====================================================================
--  Financial reports — anchor model (run AFTER 2026-10-13_financial_reports.sql)
--  Additive only: new table, new columns with defaults, one index.
--  No UPDATE / DELETE of existing data.
-- =====================================================================

-- Closing stock (Stock-in-Hand) at month ends, sent by the Agent once per month.
CREATE TABLE IF NOT EXISTS fin_stock_values (
  admin_id      BIGINT        NOT NULL,
  company_guid  VARCHAR(100)  NOT NULL,
  as_on         DATE          NOT NULL,
  value         NUMERIC(20,2) NOT NULL DEFAULT 0,
  synced_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  PRIMARY KEY (admin_id, company_guid, as_on)
);

-- 'anchor' = the year's opening balances (kept), 'snapshot' = older agents.
ALTER TABLE fin_batches   ADD COLUMN IF NOT EXISTS kind VARCHAR(10) NOT NULL DEFAULT 'snapshot';
ALTER TABLE fin_snapshots ADD COLUMN IF NOT EXISTS kind VARCHAR(10) NOT NULL DEFAULT 'snapshot';

-- Reports add up voucher lines by company and date. CONCURRENTLY does not
-- block the Agent's uploads; run this statement on its own (not inside a
-- transaction). Skip it if an equivalent index already exists.
CREATE INDEX CONCURRENTLY IF NOT EXISTS voucher_entries_fin_idx
  ON voucher_entries (admin_id, company_guid, voucher_date);

-- Check:
-- SELECT company_guid, as_on, fy_from, kind FROM fin_snapshots ORDER BY as_on DESC LIMIT 10;
-- SELECT company_guid, as_on, value FROM fin_stock_values ORDER BY as_on DESC LIMIT 12;
