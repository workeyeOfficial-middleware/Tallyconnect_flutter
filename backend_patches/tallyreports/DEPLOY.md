# Official Tally figures (Trial Balance, P&L, Balance Sheet, Cash Flow) in small pieces, so Tally never hangs

## Why the first version hung Tally
It asked for the Trial Balance of every ledger (1,157 on GI) in **one** request, and it would then have asked for Tally's Balance Sheet, P&L and Cash Flow screens, which make Tally value all the stock at once. Tally handles one request at a time and freezes while it works. Stopping our wait does not stop Tally.

## What it does now
**Tally's report screens are never requested.** The Agent asks for small pieces of Tally's own figures:

| Piece | Size | Request |
|---|---|---|
| Ledger balances (from year start to today) | about **40 ledgers** | Ledger collection, filtered to those names, `OPENINGBALANCE, CLOSINGBALANCE` |
| Stock value at the period end | about **15 items** | StockItem collection, filtered, `CLOSINGVALUE` |
| Stock value at the year start | about **15 items** | same, at the day before the year starts (only once; then reused) |
| Cash / bank balances | **one month** | the cash/bank ledgers only, one month's opening and closing |

The server builds the four reports from these pieces with the same rules as the app's financial statements and Tally's group tree:
- Trial Balance = ledger balances plus opening stock;
- P&L and Balance Sheet = ledger balances plus Tally's stock values;
- Cash Flow = cash/bank opening, net change and closing per month.

## Pacing (all settings are Agent environment variables)
| Rule | Default | Setting |
|---|---|---|
| Pieces per sync run | **6** | `TALLY_REPORT_PIECES_PER_RUN` |
| Rest before the first piece | 10 s | `TALLY_REPORT_PAUSE_MS` |
| Gap between pieces | **8 s** | `TALLY_REPORT_GAP_MS` |
| Time limit per piece | 30 s | `TALLY_REPORT_PIECE_TIMEOUT_MS` |
| A piece slower than | 5 s → the next pieces are **half the size**, and the Agent stops for this sync | `TALLY_REPORT_SLOW_MS` |
| A piece times out | No piece for **30 min**; next pieces a quarter of the size | `TALLY_REPORT_COOL_MS` |
| Fast pieces (under 1 s) | Grow by a quarter (at most 120 ledgers / 50 items) | — |
| Starting sizes | 40 ledgers / 15 items | `TALLY_REPORT_LEDGERS_PER_PIECE`, `TALLY_REPORT_ITEMS_PER_PIECE` |
| "Is Tally answering?" first | 15 s, else nothing this sync | — |
| Today's figures again | Next day, or after 6 h if something changed in Tally | `TALLY_REPORT_REFRESH_MS` |
| Switch off | — | `TALLY_REPORTS=off` |

**Progress:** saved after every piece, so a stopped or interrupted sync carries on next time. The step runs at the end of the sync, after the ledger and stock-item name lists are read (they are reused, so Tally isn't asked twice).

**Example, GI** (1,157 ledgers, 509 items, 7 months so far this year): about 30 ledger pieces, 34 stock pieces for the period end, 34 for the year start and 7 cash pieces, so about 105 small pieces. At 6 per sync (every 5 minutes) that's about 18 syncs, roughly 1½ hours, for the first full set. Last year's closing figures come after that. Each piece keeps Tally busy for about a second.

## Release
1. **SQL:** `sql/2026-10-18_tally_reports.sql` (4 new tables), if not run yet.
2. **Backend:** `utils/tallyReportsCore.js` and `utils/tallyReportsRouter.js` (updated), `routes/tallyReports.js`, and the 2 `server.js` lines. It uses the already-deployed `utils/financialCore.js`.
3. **Agent:** `lib/tallyReports.cjs` (rewritten) and `agent.cjs` (the step now runs after the name lists). Rebuild and install.
4. **App:** no change needed.

## What the Agent log shows
- `📑 Tally figures 2026-04-01–2026-10-18: 105 small pieces to fetch (a few per sync).`
- `📑 Tally figures: 6 small piece(s) fetched this sync — more next sync.`
- `🐢 Tally figures: a piece took 6.2 s — smaller pieces next time; stopping for this sync.`
- `⏳ … a piece took over 30 s — resting Tally 30 min; next pieces smaller.`
- `📑 Tally figures 2026-04-01–2026-10-18: complete (105 pieces, 48 s of Tally time) — uploaded.`
- `⏭️ Tally figures: Tally is busy …` / `… resting …` / `📑 Tally figures: up to date.`

**Please note:** while you're working in Tally you shouldn't notice anything. If you ever see `🐢` repeatedly, raise `TALLY_REPORT_GAP_MS` (for example to 20000) or lower `TALLY_REPORT_PIECES_PER_RUN` (for example to 3).

## Check against TallyPrime (same company, same date)
- **Trial Balance:** each ledger's closing and the "Debit = Credit" line match Tally's Trial Balance, including the Opening Stock line.
- **Balance Sheet:** Capital Account, Current Liabilities, Profit & Loss A/c and Current Assets (with stock) match Tally.
- **Profit & Loss:** Opening Stock, Purchase, Sales, Closing Stock, the indirect groups and Net Profit match Tally for 1 April → today.
- **Cash Flow:** each month's cash and bank opening and closing match Tally (Display → Account Books → Cash/Bank).

**SQL to see what is in:**
```sql
SELECT 'trial_balance' r, company_guid, period_from, period_to, jsonb_array_length(rows) n, fetch_seconds, report_name, fetched_at FROM tally_trial_balance
UNION ALL SELECT 'balance_sheet', company_guid, period_from, period_to, jsonb_array_length(rows), fetch_seconds, report_name, fetched_at FROM tally_balance_sheet
UNION ALL SELECT 'profit_loss', company_guid, period_from, period_to, jsonb_array_length(rows), fetch_seconds, report_name, fetched_at FROM tally_profit_loss
UNION ALL SELECT 'cash_flow', company_guid, period_from, period_to, jsonb_array_length(rows), fetch_seconds, report_name, fetched_at FROM tally_cash_flow
ORDER BY fetched_at DESC;
```
