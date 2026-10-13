-- =====================================================================
-- TallyConnect outstanding email reminders — schema (PostgreSQL)
-- Review, then run manually (staging first). Safe to re-run: every
-- statement is IF NOT EXISTS. Creates two NEW tables only; does not touch
-- bills, ledgers or any other existing table. Nothing here is synced to
-- Tally.
-- =====================================================================

BEGIN;

-- Email templates, per account (admin). Managed by the admin only.
CREATE TABLE IF NOT EXISTS reminder_templates (
  id          BIGSERIAL PRIMARY KEY,
  admin_id    BIGINT        NOT NULL,
  name        VARCHAR(80)   NOT NULL CHECK (char_length(name) BETWEEN 1 AND 80),
  subject     VARCHAR(200)  NOT NULL CHECK (char_length(subject) BETWEEN 1 AND 200),
  body        TEXT          NOT NULL CHECK (char_length(body) BETWEEN 1 AND 5000),
  is_default  BOOLEAN       NOT NULL DEFAULT FALSE,
  created_by  BIGINT,
  created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT reminder_templates_name_uq UNIQUE (admin_id, name)
);

-- Every reminder attempt and its real result.
CREATE TABLE IF NOT EXISTS reminder_log (
  id                  BIGSERIAL PRIMARY KEY,

  -- Scope (from the login and active_company on the server).
  admin_id            BIGINT        NOT NULL,
  company_guid        VARCHAR(100)  NOT NULL,
  ledger_guid         VARCHAR(100)  NOT NULL,
  ledger_name         VARCHAR(255)  NOT NULL,

  -- What was sent (bills as read from the bills table at send time).
  template_id         BIGINT REFERENCES reminder_templates (id) ON DELETE SET NULL,
  bill_set            CHAR(32)      NOT NULL,   -- hash of the bill names (duplicate check)
  bills               JSONB         NOT NULL,   -- [{bill_name, bill_date, due_date, pending_amount, overdue_days}]
  total_amount        NUMERIC(18,2) NOT NULL,
  recipients          JSONB         NOT NULL,   -- ["a@b.in", …]
  subject             VARCHAR(255)  NOT NULL,

  -- Result. 'accepted' = Microsoft Graph accepted it for delivery (HTTP
  -- 202); delivery to the inbox is not confirmed by the provider.
  status              VARCHAR(16)   NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'accepted', 'failed')),
  error               VARCHAR(500),
  attempts            INTEGER       NOT NULL DEFAULT 0,
  provider            VARCHAR(40),
  provider_status     INTEGER,
  provider_request_id VARCHAR(100),
  idempotency_key     VARCHAR(80),

  -- Who sent it (from the login token).
  sent_by_user_id     BIGINT        NOT NULL,
  sent_by_email       VARCHAR(320),
  sent_by_name        VARCHAR(255),

  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  sent_at             TIMESTAMPTZ,

  CONSTRAINT reminder_log_idem_uq UNIQUE (admin_id, idempotency_key)
);

-- Party history (newest first) and the duplicate check.
CREATE INDEX IF NOT EXISTS reminder_log_ledger_idx
  ON reminder_log (admin_id, company_guid, ledger_guid, created_at DESC);

-- Rate limits (per account per day, per user per hour).
CREATE INDEX IF NOT EXISTS reminder_log_admin_created_idx
  ON reminder_log (admin_id, created_at DESC);

-- Failed ones (to retry).
CREATE INDEX IF NOT EXISTS reminder_log_failed_idx
  ON reminder_log (status)
  WHERE status IN ('pending', 'failed');

COMMIT;

-- ---------------------------------------------------------------------
-- Verification (read-only)
-- ---------------------------------------------------------------------
-- SELECT table_name FROM information_schema.tables
--  WHERE table_name IN ('reminder_templates', 'reminder_log');
--
-- Latest reminders:
-- SELECT id, created_at, ledger_name, total_amount, status, error, attempts
--   FROM reminder_log ORDER BY created_at DESC LIMIT 20;

-- ---------------------------------------------------------------------
-- Rollback (ONLY if the feature is removed — deletes reminder history)
-- ---------------------------------------------------------------------
-- DROP TABLE IF EXISTS reminder_log;
-- DROP TABLE IF EXISTS reminder_templates;
