-- =====================================================================
-- TallyConnect feedback — schema (PostgreSQL)
-- Review, then run manually (staging first). Safe to re-run: every
-- statement is IF NOT EXISTS. Does not touch any existing table.
-- =====================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS feedback (
  id              BIGSERIAL PRIMARY KEY,

  -- Who sent it: always taken from the login token, never from the body.
  user_id         BIGINT        NOT NULL,
  admin_id        BIGINT,
  user_email      VARCHAR(320),
  username        VARCHAR(255),
  role            VARCHAR(20),
  company_guid    VARCHAR(100),

  -- What was sent.
  type            VARCHAR(16)   NOT NULL
                  CHECK (type IN ('feedback', 'bug', 'idea')),
  rating          SMALLINT      CHECK (rating BETWEEN 1 AND 5),
  message         TEXT          NOT NULL
                  CHECK (char_length(message) BETWEEN 1 AND 1000),
  app_version     VARCHAR(40),
  platform        VARCHAR(120),
  user_agent      VARCHAR(300),

  -- Review by the TallyConnect team.
  status          VARCHAR(16)   NOT NULL DEFAULT 'new'
                  CHECK (status IN ('new', 'seen', 'resolved')),
  admin_note      TEXT          CHECK (admin_note IS NULL OR char_length(admin_note) <= 2000),
  reviewed_by     VARCHAR(320),
  reviewed_at     TIMESTAMPTZ,

  -- Notification email (the row is kept whatever happens to the email).
  email_status    VARCHAR(16)   NOT NULL DEFAULT 'pending'
                  CHECK (email_status IN ('pending', 'sent', 'failed', 'skipped')),
  email_error     VARCHAR(500),
  email_attempts  INTEGER       NOT NULL DEFAULT 0,
  emailed_at      TIMESTAMPTZ,

  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT feedback_bug_has_no_rating CHECK (type <> 'bug' OR rating IS NULL)
);

-- Rate limit lookups (per user, recent first).
CREATE INDEX IF NOT EXISTS feedback_user_created_idx
  ON feedback (user_id, created_at DESC);

-- Team review list (by status, newest first).
CREATE INDEX IF NOT EXISTS feedback_status_created_idx
  ON feedback (status, created_at DESC);

-- Per-account lookups.
CREATE INDEX IF NOT EXISTS feedback_admin_created_idx
  ON feedback (admin_id, created_at DESC);

-- Emails still to send / to retry.
CREATE INDEX IF NOT EXISTS feedback_email_pending_idx
  ON feedback (email_status)
  WHERE email_status IN ('pending', 'failed');

COMMIT;

-- ---------------------------------------------------------------------
-- Verification (read-only)
-- ---------------------------------------------------------------------
-- SELECT column_name, data_type, is_nullable
--   FROM information_schema.columns
--  WHERE table_name = 'feedback'
--  ORDER BY ordinal_position;
--
-- SELECT indexname FROM pg_indexes WHERE tablename = 'feedback';
--
-- Latest feedback:
-- SELECT id, created_at, user_email, type, rating, status, email_status
--   FROM feedback ORDER BY created_at DESC LIMIT 20;
--
-- Emails that failed (re-send from POST /api/admin/feedback/:id/resend-email):
-- SELECT id, created_at, email_error, email_attempts
--   FROM feedback WHERE email_status IN ('pending', 'failed')
--  ORDER BY created_at;

-- ---------------------------------------------------------------------
-- Rollback (ONLY if the feature is removed — deletes all feedback)
-- ---------------------------------------------------------------------
-- DROP TABLE IF EXISTS feedback;
