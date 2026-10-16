-- =====================================================================
-- TallyConnect financial reports (P&L, Balance Sheet, Trial Balance,
-- Expenses) — schema (PostgreSQL)
-- Review, then run manually (staging first). Safe to re-run: every
-- statement is IF NOT EXISTS. Creates NEW tables only; no existing table is
-- changed. The data comes from the TallyConnect Agent (computed by Tally);
-- nothing here is written back to Tally.
-- =====================================================================

BEGIN;

-- Tally's group tree per company (replaced on every Agent upload).
CREATE TABLE IF NOT EXISTS tally_groups (
  admin_id              BIGINT        NOT NULL,
  company_guid          VARCHAR(100)  NOT NULL,
  name                  VARCHAR(300)  NOT NULL,
  parent                VARCHAR(300),
  is_revenue            BOOLEAN       NOT NULL DEFAULT FALSE,
  is_deemed_positive    BOOLEAN       NOT NULL DEFAULT FALSE,
  affects_gross_profit  BOOLEAN       NOT NULL DEFAULT FALSE,
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  PRIMARY KEY (admin_id, company_guid, name)
);

-- One upload of balances "as on" a date (visible only once committed).
CREATE TABLE IF NOT EXISTS fin_batches (
  id            BIGSERIAL PRIMARY KEY,
  admin_id      BIGINT        NOT NULL,
  company_guid  VARCHAR(100)  NOT NULL,
  as_on         DATE          NOT NULL,
  fy_from       DATE          NOT NULL,
  created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  committed_at  TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS fin_batches_admin_idx ON fin_batches (admin_id, committed_at);

-- Ledger closing balances (Tally sign: debit negative, credit positive).
CREATE TABLE IF NOT EXISTS fin_ledger_balances (
  batch_id     BIGINT        NOT NULL REFERENCES fin_batches (id) ON DELETE CASCADE,
  ledger_guid  VARCHAR(120),
  ledger_name  VARCHAR(300)  NOT NULL,
  parent       VARCHAR(300),
  closing      NUMERIC(20,2) NOT NULL DEFAULT 0,
  opening      NUMERIC(20,2) NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS fin_ledger_balances_batch_idx ON fin_ledger_balances (batch_id);

-- Group closing balances (used for Stock-in-Hand, which has no ledgers).
CREATE TABLE IF NOT EXISTS fin_group_balances (
  batch_id    BIGINT        NOT NULL REFERENCES fin_batches (id) ON DELETE CASCADE,
  group_name  VARCHAR(300)  NOT NULL,
  parent      VARCHAR(300),
  closing     NUMERIC(20,2) NOT NULL DEFAULT 0,
  opening     NUMERIC(20,2) NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS fin_group_balances_batch_idx ON fin_group_balances (batch_id);

-- The committed upload for each date.
CREATE TABLE IF NOT EXISTS fin_snapshots (
  admin_id      BIGINT        NOT NULL,
  company_guid  VARCHAR(100)  NOT NULL,
  as_on         DATE          NOT NULL,
  fy_from       DATE          NOT NULL,
  batch_id      BIGINT        NOT NULL REFERENCES fin_batches (id),
  synced_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  PRIMARY KEY (admin_id, company_guid, as_on)
);

-- Team members the admin allowed to see financial reports.
CREATE TABLE IF NOT EXISTS financial_report_access (
  admin_id    BIGINT       NOT NULL,
  user_id     BIGINT       NOT NULL,
  granted_by  BIGINT,
  granted_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  PRIMARY KEY (admin_id, user_id)
);

COMMIT;

-- ---------------------------------------------------------------------
-- Verification (read-only)
-- ---------------------------------------------------------------------
-- SELECT company_guid, COUNT(*) FROM tally_groups GROUP BY 1;
-- SELECT company_guid, as_on, fy_from, synced_at FROM fin_snapshots ORDER BY as_on DESC LIMIT 20;

-- ---------------------------------------------------------------------
-- Rollback (ONLY if the feature is removed — deletes the synced figures)
-- ---------------------------------------------------------------------
-- DROP TABLE IF EXISTS fin_snapshots, fin_ledger_balances, fin_group_balances,
--   fin_batches, tally_groups, financial_report_access;
