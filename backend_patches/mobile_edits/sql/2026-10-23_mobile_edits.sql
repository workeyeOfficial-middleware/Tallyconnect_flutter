-- Edit and retry mobile entries. Only adds empty columns and one index to
-- mobile_sync_queue; no existing row is changed. Safe to run again.
-- Before it runs: the app's Edit / Retry answer "not available yet" and
-- entries are created exactly as today.

ALTER TABLE mobile_sync_queue ADD COLUMN IF NOT EXISTS tally_guid  VARCHAR(100); -- the voucher Tally created
ALTER TABLE mobile_sync_queue ADD COLUMN IF NOT EXISTS target_guid VARCHAR(100); -- ALTER: the Tally voucher changed
ALTER TABLE mobile_sync_queue ADD COLUMN IF NOT EXISTS edit_of     BIGINT;       -- ALTER: the entry it edits
ALTER TABLE mobile_sync_queue ADD COLUMN IF NOT EXISTS created_by  BIGINT;       -- the login that made it
ALTER TABLE mobile_sync_queue ADD COLUMN IF NOT EXISTS retry_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE mobile_sync_queue ADD COLUMN IF NOT EXISTS updated_at  TIMESTAMPTZ;

-- One waiting change per Tally voucher is looked up by its GUID.
CREATE INDEX IF NOT EXISTS mobile_sync_queue_target_idx
  ON mobile_sync_queue (admin_id, company_guid, target_guid)
  WHERE action = 'ALTER';
