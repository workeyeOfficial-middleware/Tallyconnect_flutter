-- =====================================================================
--  Official Tally reports (Trial Balance, P&L, Balance Sheet, Cash Flow)
--  Run BEFORE deploying the backend. NEW tables only: no existing table is
--  changed, no data is updated or deleted. Safe to re-run.
--  One row per company + period; a new fetch from Tally replaces it.
-- =====================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS tally_trial_balance (
  admin_id       BIGINT        NOT NULL,
  company_guid   VARCHAR(100)  NOT NULL,
  period_from    DATE          NOT NULL,
  period_to      DATE          NOT NULL,
  rows           JSONB         NOT NULL,   -- [{name, parent, opening, closing}] Dr negative
  report_name    VARCHAR(100),
  fetch_seconds  NUMERIC(10,1),
  content_hash   VARCHAR(64),
  fetched_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  PRIMARY KEY (admin_id, company_guid, period_from, period_to)
);

CREATE TABLE IF NOT EXISTS tally_profit_loss (
  admin_id       BIGINT        NOT NULL,
  company_guid   VARCHAR(100)  NOT NULL,
  period_from    DATE          NOT NULL,
  period_to      DATE          NOT NULL,
  rows           JSONB         NOT NULL,   -- [{name, tag, amounts}] in Tally's order
  report_name    VARCHAR(100),
  fetch_seconds  NUMERIC(10,1),
  content_hash   VARCHAR(64),
  fetched_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  PRIMARY KEY (admin_id, company_guid, period_from, period_to)
);

CREATE TABLE IF NOT EXISTS tally_balance_sheet (
  admin_id       BIGINT        NOT NULL,
  company_guid   VARCHAR(100)  NOT NULL,
  period_from    DATE          NOT NULL,
  period_to      DATE          NOT NULL,
  rows           JSONB         NOT NULL,
  report_name    VARCHAR(100),
  fetch_seconds  NUMERIC(10,1),
  content_hash   VARCHAR(64),
  fetched_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  PRIMARY KEY (admin_id, company_guid, period_from, period_to)
);

CREATE TABLE IF NOT EXISTS tally_cash_flow (
  admin_id       BIGINT        NOT NULL,
  company_guid   VARCHAR(100)  NOT NULL,
  period_from    DATE          NOT NULL,
  period_to      DATE          NOT NULL,
  rows           JSONB         NOT NULL,
  report_name    VARCHAR(100),
  fetch_seconds  NUMERIC(10,1),
  content_hash   VARCHAR(64),
  fetched_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  PRIMARY KEY (admin_id, company_guid, period_from, period_to)
);

COMMIT;

-- ---------------------------------------------------------------------
-- Check (read-only): what the Agent has fetched so far
-- ---------------------------------------------------------------------
-- SELECT 'trial_balance' AS report, company_guid, period_from, period_to, jsonb_array_length(rows) AS rows, fetch_seconds, fetched_at FROM tally_trial_balance
-- UNION ALL SELECT 'profit_loss', company_guid, period_from, period_to, jsonb_array_length(rows), fetch_seconds, fetched_at FROM tally_profit_loss
-- UNION ALL SELECT 'balance_sheet', company_guid, period_from, period_to, jsonb_array_length(rows), fetch_seconds, fetched_at FROM tally_balance_sheet
-- UNION ALL SELECT 'cash_flow', company_guid, period_from, period_to, jsonb_array_length(rows), fetch_seconds, fetched_at FROM tally_cash_flow
-- ORDER BY fetched_at DESC;

-- ---------------------------------------------------------------------
-- Rollback (ONLY if the feature is removed — deletes the fetched figures)
-- ---------------------------------------------------------------------
-- DROP TABLE IF EXISTS tally_trial_balance, tally_profit_loss, tally_balance_sheet, tally_cash_flow;
