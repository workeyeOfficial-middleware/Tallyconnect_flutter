-- =====================================================================
--  AI Assistant — plans and token usage per user
--  Additive only: three new tables + the Free plan row.
--  No UPDATE / DELETE of existing data. Safe to run again.
-- =====================================================================
BEGIN;

-- Plans. 'lifetime' = one allowance in total; 'month' = resets each month.
CREATE TABLE IF NOT EXISTS ai_plans (
  code         VARCHAR(30)   PRIMARY KEY,
  name         VARCHAR(100)  NOT NULL,
  token_limit  BIGINT        NOT NULL CHECK (token_limit >= 0),
  period       VARCHAR(10)   NOT NULL DEFAULT 'lifetime' CHECK (period IN ('lifetime', 'month')),
  is_active    BOOLEAN       NOT NULL DEFAULT TRUE,
  created_at   TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

INSERT INTO ai_plans (code, name, token_limit, period)
VALUES ('free', 'Free', 10000, 'lifetime')
ON CONFLICT (code) DO NOTHING;

-- One row per login (users.id), created on first use of the assistant.
CREATE TABLE IF NOT EXISTS ai_usage (
  user_id               BIGINT       PRIMARY KEY,
  admin_id              BIGINT,
  plan_code             VARCHAR(30)  NOT NULL DEFAULT 'free' REFERENCES ai_plans (code),
  tokens_used           BIGINT       NOT NULL DEFAULT 0,
  requests              INTEGER      NOT NULL DEFAULT 0,   -- AI provider calls
  token_limit_override  BIGINT,                             -- per-user limit (NULL = the plan's)
  period_start          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  last_used_at          TIMESTAMPTZ,
  updated_at            TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ai_usage_admin_idx ON ai_usage (admin_id);

-- Every AI provider call (for audits and future billing).
CREATE TABLE IF NOT EXISTS ai_usage_log (
  id             BIGSERIAL    PRIMARY KEY,
  user_id        BIGINT       NOT NULL,
  admin_id       BIGINT,
  company_guid   VARCHAR(100),
  provider       VARCHAR(30)  NOT NULL,
  model          VARCHAR(120),
  input_tokens   INTEGER      NOT NULL DEFAULT 0,
  output_tokens  INTEGER      NOT NULL DEFAULT 0,
  total_tokens   INTEGER      NOT NULL DEFAULT 0,
  estimated      BOOLEAN      NOT NULL DEFAULT FALSE,     -- provider reported no count
  created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ai_usage_log_user_idx ON ai_usage_log (user_id, created_at);

COMMIT;

-- Check:
-- SELECT * FROM ai_plans;
-- SELECT user_id, plan_code, tokens_used, requests, last_used_at FROM ai_usage ORDER BY last_used_at DESC NULLS LAST LIMIT 20;
--
-- Later (examples, run only when you decide to):
--   give one user more tokens:   UPDATE ai_usage SET token_limit_override = 50000 WHERE user_id = <id>;
--   add a paid monthly plan:     INSERT INTO ai_plans (code, name, token_limit, period) VALUES ('pro', 'Pro', 500000, 'month');
--   move a user to it:           UPDATE ai_usage SET plan_code = 'pro', tokens_used = 0, period_start = NOW() WHERE user_id = <id>;
