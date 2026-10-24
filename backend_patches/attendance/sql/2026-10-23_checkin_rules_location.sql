-- Who checks in (positions and exempt list) and ledger location.
-- Only adds a table / empty columns; nothing existing changes. Safe to run
-- again. Until it has run: every team member checks in (as today) and
-- ledgers have no location (the location filter shows none).

-- The positions that do not check in (e.g. Manager, Director), per account.
CREATE TABLE IF NOT EXISTS attendance_settings (
  admin_id          BIGINT       PRIMARY KEY,
  exempt_positions  TEXT[]       NOT NULL DEFAULT '{}',
  updated_by        BIGINT,
  updated_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Each team member's position and rule: auto (by position), required or
-- exempt (the admin's choice for that person).
CREATE TABLE IF NOT EXISTS attendance_members (
  admin_id    BIGINT       NOT NULL,
  user_id     BIGINT       NOT NULL,
  position    VARCHAR(40),
  rule        VARCHAR(8)   NOT NULL DEFAULT 'auto'
              CHECK (rule IN ('auto', 'required', 'exempt')),
  updated_by  BIGINT,
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  PRIMARY KEY (admin_id, user_id)
);

-- Ledger location as saved in Tally (filled by the Agent's next ledger pass).
ALTER TABLE ledgers ADD COLUMN IF NOT EXISTS state   VARCHAR(80);
ALTER TABLE ledgers ADD COLUMN IF NOT EXISTS pincode VARCHAR(12);
ALTER TABLE ledgers ADD COLUMN IF NOT EXISTS country VARCHAR(60);
ALTER TABLE ledgers ADD COLUMN IF NOT EXISTS address VARCHAR(500);
