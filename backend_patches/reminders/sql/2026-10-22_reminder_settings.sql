-- Payment reminder settings, per account and company (set by the admin):
-- before / after / both the due date, how many days, the hour (India time),
-- and Automatic (the server emails parties) or Manual (the team sends them).
-- Creates one NEW table; nothing existing changes. Safe to run again.
-- Until this has run, the app shows the defaults (Manual, 3 days before,
-- 10 AM) and nothing is sent automatically.

CREATE TABLE IF NOT EXISTS reminder_settings (
  admin_id      BIGINT       NOT NULL,
  company_guid  VARCHAR(100) NOT NULL,
  mode          VARCHAR(10)  NOT NULL DEFAULT 'manual'
                CHECK (mode IN ('manual', 'automatic')),
  timing        VARCHAR(6)   NOT NULL DEFAULT 'before'
                CHECK (timing IN ('before', 'after', 'both')),
  before_days   SMALLINT     NOT NULL DEFAULT 3  CHECK (before_days BETWEEN 1 AND 60),
  after_days    SMALLINT     NOT NULL DEFAULT 1  CHECK (after_days BETWEEN 1 AND 90),
  repeat_days   SMALLINT     NOT NULL DEFAULT 0  CHECK (repeat_days BETWEEN 0 AND 30),
  send_hour     SMALLINT     NOT NULL DEFAULT 10 CHECK (send_hour BETWEEN 0 AND 23),
  updated_by    BIGINT,
  updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  PRIMARY KEY (admin_id, company_guid)
);

-- The hourly job looks up the companies set to Automatic at this hour.
CREATE INDEX IF NOT EXISTS reminder_settings_auto_idx
  ON reminder_settings (send_hour) WHERE mode = 'automatic';

-- Bill date (Bill details: Bill date, Credit period). The column is already
-- read by the server; this only makes sure it exists.
ALTER TABLE bills ADD COLUMN IF NOT EXISTS bill_date DATE;
