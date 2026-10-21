-- Leave management (with check-in / check-out). Run once, before deploying
-- the backend that has /api/leave/*. Only creates new tables; nothing
-- existing is changed. Everything is set by the account admin in the app
-- (Leave settings): on/off, leave year, weekly off, half days, leave types
-- and quotas, holidays.

-- One row per account; no row = the defaults (leave management off).
CREATE TABLE IF NOT EXISTS leave_settings (
  admin_id          BIGINT       PRIMARY KEY,
  enabled           BOOLEAN      NOT NULL DEFAULT FALSE,
  year_start_month  SMALLINT     NOT NULL DEFAULT 4 CHECK (year_start_month BETWEEN 1 AND 12),
  weekly_off        SMALLINT[]   NOT NULL DEFAULT '{0}',   -- 0 = Sunday … 6 = Saturday
  half_day          BOOLEAN      NOT NULL DEFAULT TRUE,
  backdate_days     SMALLINT     NOT NULL DEFAULT 7 CHECK (backdate_days BETWEEN 0 AND 365),
  max_request_days  SMALLINT     NOT NULL DEFAULT 30 CHECK (max_request_days BETWEEN 1 AND 366),
  updated_by        BIGINT,
  updated_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Leave types of an account (Casual, Sick, …). yearly_quota NULL = no limit.
CREATE TABLE IF NOT EXISTS leave_types (
  id             BIGSERIAL     PRIMARY KEY,
  admin_id       BIGINT        NOT NULL,
  name           VARCHAR(40)   NOT NULL,
  yearly_quota   NUMERIC(5,1)  CHECK (yearly_quota IS NULL OR yearly_quota >= 0),
  paid           BOOLEAN       NOT NULL DEFAULT TRUE,
  carry_forward  BOOLEAN       NOT NULL DEFAULT FALSE,
  max_carry      NUMERIC(5,1)  CHECK (max_carry IS NULL OR max_carry >= 0),
  active         BOOLEAN       NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS leave_types_name_idx ON leave_types (admin_id, lower(name));

-- Holidays of an account (not counted as leave days).
CREATE TABLE IF NOT EXISTS leave_holidays (
  admin_id    BIGINT       NOT NULL,
  date        DATE         NOT NULL,
  name        VARCHAR(60)  NOT NULL,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  PRIMARY KEY (admin_id, date)
);

-- Leave requests. days = working days (weekly off and holidays left out;
-- a half day is 0.5). A request stays inside one leave year.
CREATE TABLE IF NOT EXISTS leave_requests (
  id               BIGSERIAL     PRIMARY KEY,
  admin_id         BIGINT        NOT NULL,
  user_id          BIGINT        NOT NULL,
  leave_type_id    BIGINT        NOT NULL REFERENCES leave_types(id),
  from_date        DATE          NOT NULL,
  to_date          DATE          NOT NULL,
  half_day         VARCHAR(6)    CHECK (half_day IS NULL OR half_day IN ('first', 'second')),
  days             NUMERIC(5,1)  NOT NULL CHECK (days > 0),
  reason           VARCHAR(300),
  status           VARCHAR(10)   NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  decided_by       BIGINT,
  decided_at       TIMESTAMPTZ,
  decision_note    VARCHAR(300),
  idempotency_key  VARCHAR(80),
  created_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CHECK (to_date >= from_date),
  CHECK (half_day IS NULL OR to_date = from_date)
);
-- A retried request (same key) never makes a second row.
CREATE UNIQUE INDEX IF NOT EXISTS leave_requests_idem_idx
  ON leave_requests (user_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS leave_requests_user_idx ON leave_requests (admin_id, user_id, from_date);
CREATE INDEX IF NOT EXISTS leave_requests_status_idx ON leave_requests (admin_id, status, from_date);
