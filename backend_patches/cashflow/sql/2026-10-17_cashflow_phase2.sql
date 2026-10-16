-- =====================================================================
--  Cash flow forecast — Phase 2 schema (PostgreSQL)
--  Run BEFORE deploying the Phase 2 backend (the backend works without
--  these tables too — it then keeps using the Phase 1 estimate).
--  Creates NEW tables only. No existing table is changed, no data is
--  updated or deleted. Safe to re-run (IF NOT EXISTS).
-- =====================================================================

BEGIN;

-- Tally's bill-wise allocations of each voucher (sent by the Agent):
-- which receipt / payment settled which bill, and when.
-- amount keeps Tally's sign: debit negative, credit positive.
CREATE TABLE IF NOT EXISTS bill_settlements (
  admin_id      BIGINT         NOT NULL,
  company_guid  VARCHAR(100)   NOT NULL,
  voucher_guid  VARCHAR(120)   NOT NULL,
  voucher_date  DATE           NOT NULL,
  voucher_type  VARCHAR(100),
  voucher_no    VARCHAR(200),
  ledger_name   VARCHAR(300)   NOT NULL,
  bill_name     VARCHAR(300)   NOT NULL,
  ref_type      VARCHAR(30)    NOT NULL,   -- Agst Ref / New Ref / Advance / On Account
  amount        NUMERIC(20,2)  NOT NULL,
  credit_days   INTEGER,
  synced_at     TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  PRIMARY KEY (admin_id, company_guid, voucher_guid, ledger_name, bill_name, ref_type)
);
CREATE INDEX IF NOT EXISTS bill_settlements_date_idx
  ON bill_settlements (admin_id, company_guid, voucher_date);

-- Tally's signed amount of every CURRENT bill (Dr / Cr), replaced on each
-- bills sync, so advances are not counted as money to come in / go out.
CREATE TABLE IF NOT EXISTS bill_balance_signs (
  admin_id      BIGINT         NOT NULL,
  company_guid  VARCHAR(100)   NOT NULL,
  bill_type     VARCHAR(20)    NOT NULL,   -- RECEIVABLE / PAYABLE
  ledger_name   VARCHAR(300)   NOT NULL,
  bill_name     VARCHAR(300)   NOT NULL,
  raw_amount    NUMERIC(20,2)  NOT NULL,
  synced_at     TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  PRIMARY KEY (admin_id, company_guid, bill_type, ledger_name, bill_name)
);

COMMIT;

-- ---------------------------------------------------------------------
-- Check (read-only)
-- ---------------------------------------------------------------------
-- SELECT company_guid, ref_type, COUNT(*), MIN(voucher_date), MAX(voucher_date)
--   FROM bill_settlements GROUP BY 1, 2 ORDER BY 1, 2;
-- SELECT company_guid, bill_type, COUNT(*),
--        SUM(CASE WHEN raw_amount < 0 THEN 1 ELSE 0 END) AS negative,
--        SUM(CASE WHEN raw_amount > 0 THEN 1 ELSE 0 END) AS positive
--   FROM bill_balance_signs GROUP BY 1, 2;

-- ---------------------------------------------------------------------
-- Rollback (ONLY if the feature is removed — deletes the synced rows)
-- ---------------------------------------------------------------------
-- DROP TABLE IF EXISTS bill_settlements, bill_balance_signs;
