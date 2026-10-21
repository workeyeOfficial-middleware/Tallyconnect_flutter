-- Sales team check-in / check-out (attendance). Run once, before deploying
-- the backend that has /api/attendance/*. Only creates new tables; nothing
-- existing is changed.

-- Team members the account admin put on the sales team (may check in).
CREATE TABLE IF NOT EXISTS attendance_access (
  admin_id    BIGINT       NOT NULL,
  user_id     BIGINT       NOT NULL,
  enabled_by  BIGINT,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  PRIMARY KEY (admin_id, user_id)
);

-- One row per check-in; check_out_at is NULL while checked in. Times are
-- the server's clock; work_date is the India (IST) date of the check-in.
CREATE TABLE IF NOT EXISTS attendance_sessions (
  id               BIGSERIAL     PRIMARY KEY,
  admin_id         BIGINT        NOT NULL,
  company_guid     VARCHAR(100)  NOT NULL,
  user_id          BIGINT        NOT NULL,
  work_date        DATE          NOT NULL,
  check_in_at      TIMESTAMPTZ   NOT NULL,
  check_out_at     TIMESTAMPTZ,
  last_seen_at     TIMESTAMPTZ   NOT NULL,
  in_note          VARCHAR(300),
  out_note         VARCHAR(300),
  closed_by        VARCHAR(10),            -- 'user' | 'auto' | 'admin'
  idempotency_key  VARCHAR(80),
  created_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CHECK (check_out_at IS NULL OR check_out_at >= check_in_at)
);

-- At most one open session per person (a double tap cannot check in twice).
CREATE UNIQUE INDEX IF NOT EXISTS attendance_one_open_idx
  ON attendance_sessions (user_id) WHERE check_out_at IS NULL;
-- A retried check-in (same key) never makes a second row.
CREATE UNIQUE INDEX IF NOT EXISTS attendance_idem_idx
  ON attendance_sessions (user_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS attendance_company_day_idx
  ON attendance_sessions (admin_id, company_guid, work_date);
CREATE INDEX IF NOT EXISTS attendance_user_day_idx
  ON attendance_sessions (user_id, work_date);
