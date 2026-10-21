-- Cash Flow as TallyPrime counts it. Run once, BEFORE the backend and the
-- Agent that send these. Only adds three empty columns; nothing existing
-- changes (until the Agent's next full sync fills them, Cash Flow counts as
-- before).

-- Tally's own "this voucher is in the Cash Flow" flag (HASCASHFLOW), saved
-- with each voucher. NULL = not synced yet.
ALTER TABLE vouchers ADD COLUMN IF NOT EXISTS has_cash_flow BOOLEAN;

-- A ledger's Dr and Cr lines in one voucher before netting (Tally's Cash
-- Flow counts each line on its own side). NULL = not synced yet.
ALTER TABLE voucher_entries ADD COLUMN IF NOT EXISTS gross_dr NUMERIC(18,2);
ALTER TABLE voucher_entries ADD COLUMN IF NOT EXISTS gross_cr NUMERIC(18,2);
