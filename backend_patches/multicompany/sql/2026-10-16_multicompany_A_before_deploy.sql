-- =====================================================================
--  Multi-company sync — PART A: run BEFORE deploying the new backend.
--  Additive only: new indexes, new columns (with defaults), new table.
--  No UPDATE / DELETE of data. Safe to run again.
-- =====================================================================

-- 1. Account-scoped keys the new code uses for its upserts. They cannot
--    meet duplicates: the stricter old keys (dropped in PART B) already
--    keep these rows unique.
--    CONCURRENTLY: does not block the Agent. Run each of these two lines
--    ON ITS OWN (not inside BEGIN/COMMIT), auto-commit on.
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS uq_orders_admin_company_guid
  ON orders (admin_id, company_guid, order_guid);
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS uq_vbm_admin_company
  ON voucher_bill_map (admin_id, company_guid, voucher_guid, bill_ref);

-- 2. The rest can run together.
BEGIN;

-- Which companies the Agent syncs (switched off = kept, never deleted:
-- deleting a company would cascade to all of its data).
ALTER TABLE selected_companies ADD COLUMN IF NOT EXISTS enabled    BOOLEAN     NOT NULL DEFAULT TRUE;
ALTER TABLE selected_companies ADD COLUMN IF NOT EXISTS sync_order INT;
ALTER TABLE selected_companies ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- One Agent at a time per account + company.
CREATE TABLE IF NOT EXISTS company_sync_locks (
  admin_id      BIGINT        NOT NULL,
  company_guid  VARCHAR(100)  NOT NULL,
  agent_id      VARCHAR(100)  NOT NULL,
  acquired_at   TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  expires_at    TIMESTAMPTZ   NOT NULL,
  PRIMARY KEY (admin_id, company_guid)
);

-- Per-company progress (agent_status is already one row per account + company).
ALTER TABLE agent_status ADD COLUMN IF NOT EXISTS state       VARCHAR(20);
ALTER TABLE agent_status ADD COLUMN IF NOT EXISTS step        VARCHAR(60);
ALTER TABLE agent_status ADD COLUMN IF NOT EXISTS percent     INT;
ALTER TABLE agent_status ADD COLUMN IF NOT EXISTS last_error  TEXT;
ALTER TABLE agent_status ADD COLUMN IF NOT EXISTS agent_id    VARCHAR(100);
ALTER TABLE agent_status ADD COLUMN IF NOT EXISTS progress_at TIMESTAMPTZ;

COMMIT;

-- Check:
-- SELECT to_regclass('uq_orders_admin_company_guid'), to_regclass('uq_vbm_admin_company'), to_regclass('company_sync_locks');
-- SELECT column_name FROM information_schema.columns WHERE table_name = 'selected_companies' AND column_name IN ('enabled','sync_order','updated_at');
