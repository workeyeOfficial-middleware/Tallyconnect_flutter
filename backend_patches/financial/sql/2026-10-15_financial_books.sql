-- =====================================================================
--  Financial reports — books-beginning data (run AFTER 2026-10-14_financial_anchor.sql)
--  Additive only: one new table. No UPDATE / DELETE of existing data.
-- =====================================================================

-- Sent by the Agent once a day (light Tally masters): where the books
-- begin, where the synced vouchers begin and the items' opening values.
CREATE TABLE IF NOT EXISTS fin_books (
  admin_id       BIGINT        NOT NULL,
  company_guid   VARCHAR(100)  NOT NULL,
  books_from     DATE          NOT NULL,
  vouchers_from  DATE,
  fy_from        DATE,
  opening_stock  NUMERIC(20,2) NOT NULL DEFAULT 0,
  synced_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  PRIMARY KEY (admin_id, company_guid)
);

-- Check:
-- SELECT company_guid, books_from, vouchers_from, fy_from, opening_stock, synced_at FROM fin_books;
