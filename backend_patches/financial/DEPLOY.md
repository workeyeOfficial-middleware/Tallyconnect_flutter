# Financial statements (P&L, Balance Sheet, Trial Balance, Expenses) — deployment

Nothing has been deployed, run against a database, built or committed.

## How it works (light on Tally)
1. **Agent** (`tally-agent/lib/financialSync.cjs`, step 5b in `agent.cjs`) asks Tally for only:
   - the group tree (masters, no balances), once a day;
   - ONE **anchor** per financial year: every ledger's closing balance on the day
     before the synced vouchers begin (normally 31-03), plus Stock-in-Hand that day.
     It is fetched once and re-checked weekly;
   - **Stock-in-Hand at each month end**, fetched once after the month closes. The
     last two month ends are re-checked weekly.

   The Agent makes at most 4 heavy Tally requests per sync, with a 3-second pause
   between them. The first sync's history fills in over a few syncs. Nothing is
   ever recalculated in Tally per date (that was what froze Tally).
2. **Backend** computes every figure as the anchor balance plus the movements of
   the synced voucher lines (`voucher_entries`). Income and expense ledgers restart
   at 0 each year. It leaves out memorandum, optional, reversing-journal and deleted
   vouchers. Closing stock comes from the month-end values, and today's from
   `stock_summary`. The Balance Sheet carries
   `data_check {unbalanced_vouchers, unbalanced_amount}`, which explains any
   difference.
3. **App**: unchanged. Reports → *Financial statements*. The admin sees the
   reports by default. A team member sees them only after the admin turns on
   *Configure User → Reports → Financial statements*.

### Voucher lines fix (Agent, affects all voucher syncs)
A ledger appearing more than once in a voucher (an item invoice lists the sales
ledger once per item) used to keep only the FIRST line. The other lines were
dropped, which understated those ledgers and unbalanced the voucher. Now
`lib/voucherLines.cjs` adds them up.
- A ledger that appears once is stored exactly as before.
- The stored flag keeps its convention: `is_debit = ISDEEMEDPOSITIVE "No"`. Despite
  the name, that marks a credit line, and the backend reads it that way.
- Vouchers already in the database are corrected on the next **full** voucher sync.

## 1. Database (staging first; additive only)
1. `sql/2026-10-13_financial_reports.sql`, if not run yet.
2. `sql/2026-10-14_financial_anchor.sql`:
   - creates `fin_stock_values`;
   - adds a `kind` column (default `'snapshot'`) to `fin_batches` and `fin_snapshots`;
   - creates the index `voucher_entries (admin_id, company_guid, voucher_date)`.

   Run the `CREATE INDEX CONCURRENTLY` statement on its own, outside a transaction.

## 2. Backend (files in `TallyConnect-push/tally-backend`, uncommitted)
- Changed: `utils/financialCore.js`, `utils/financialRouter.js`.
- New: `utils/financialData.js`.
- `routes/financial.js` and `server.js` are as before.

```powershell
git add tally-backend/utils/financialCore.js tally-backend/utils/financialRouter.js tally-backend/utils/financialData.js
git commit -m "Financial reports: compute from anchor + vouchers"
git push origin production_code
```
Server: `git pull`, then `docker compose up -d --build`. No new environment
variables or npm packages.

## 3. Agent (files in `Downloads/tally-agent`, uncommitted)
- New: `lib/financialSync.cjs`, `lib/voucherLines.cjs`.
- `agent.cjs` changes:
  - requires for both;
  - the three entry builders call `mergeLedgerLines`;
  - step 5b passes `syncStart`.
- Build as usual. `pkg` bundles `lib/*.cjs` through the static `require`.
- After installing: force one **full** voucher sync per company, so stored lines are
  re-saved merged. Then let it sync 3–5 times, so the month-end stock values fill in.

## 4. Verify against Tally BEFORE releasing to customers
For 2–3 real companies (at least one using item invoices), compare with Tally on the
same dates:
- Trial Balance totals (Dr = Cr) and a few ledgers;
- P&L: gross profit, net profit, opening and closing stock, for this year and for
  one month;
- Balance Sheet totals and the Profit & Loss A/c line. Check that `difference` is 0
  and `data_check.unbalanced_vouchers` is 0;
- Expenses total equals the P&L expense groups.

Points only real Tally can confirm:
- Ledger `CLOSINGBALANCE` for the `SVFROMDATE`/`SVTODATE` period in a Collection
  export (debit negative).
- The `$$GroupStock` / "Stock-in-Hand" filter returns that group's value.
- For item invoices, `ALLLEDGERENTRIES.LIST` carries the sales and purchase ledger
  lines. If it does not, `data_check` will show those invoices as unbalanced.
- Renamed ledgers: voucher lines are keyed by ledger name, so a rename needs a full
  voucher sync.
- During a full voucher sync, all lines are reset and then re-saved, so reports read
  in the middle of that sync are temporarily incomplete. The same is true of the
  existing reports.

## API
Agent (admin login):
- `POST /api/financial/agent/groups`;
- `/agent/snapshot/begin {kind:"anchor"}` → `/rows` (chunks) → `/commit` (counts
  checked);
- `POST /api/financial/agent/stock-values {company_guid, values:[{as_on, value}]}`.

App (response shapes unchanged; the Balance Sheet adds `data_check`):
- `GET /api/financial/me`;
- `GET /api/financial/periods`;
- `GET /api/financial/trial-balance?as_on=`;
- `GET /api/financial/profit-loss?from=&to=`;
- `GET /api/financial/balance-sheet?as_on=`;
- `GET /api/financial/expenses?from=&to=&purchases=1`.

Admin: `GET /api/financial/access`, `PUT /api/financial/access/:userId {enabled}`.

Everything is scoped to the login's account and active company.

## Tests
- Backend `test/financial.test.mjs`: 18 tests.
  - Core worked example.
  - Anchor model:
    - P&L for the year and for a month;
    - Balance Sheet balances, with P&L A/c brought forward;
    - Trial Balance and expenses;
    - mid-year anchor;
    - unbalanced-voucher check;
    - memo, deleted and before-anchor vouchers left out;
    - half-uploaded anchor ignored;
    - access and isolation.
- Agent `agent/financialSync.test.cjs`: 12 tests.
  - Plan, budget and pauses, failure, Stop.
  - Voucher-line merge.
  - Run with `AGENT_DIR=<tally-agent> node --test`.
