# Voucher status (cancelled / optional / non-accounting) — deploy

Reports now leave out what Tally's books leave out: cancelled and optional vouchers, and vouchers whose built-in Tally type doesn't post to the accounts. That covers orders, delivery and receipt notes, rejections, stock journals and similar types, whatever the company has renamed them to (for example Lumilo's "Replacement" = Delivery Note, and "Delivery Challan" made under it).

Nothing changes until the data is known. Every new column starts as NULL, and NULL means "counted exactly as today". The apps keep showing what they show now while the Agent's re-read fills the values in.

## Order

1. **SQL** (once): `sql/2026-10-22_voucher_status.sql`. It adds 5 empty columns (`vouchers.is_cancelled`, `vouchers.is_optional`, `vouchers.base_type`, `vouchers.is_accounting` and `voucher_entries.is_accounting`). It doesn't update or rewrite any rows.
2. **Backend** (`tally-backend/`):
   - `utils/voucherStatus.js` (new)
   - `routes/voucherEntry.js`:
     - `/sync` stores the status;
     - a cancelled voucher's old lines are marked;
     - `/paged` leaves out optional vouchers and returns `is_cancelled`.
   - `utils/financialData.js` (P&L / BS / TB / Cash Flow / ledger vouchers), `utils/cashflowRouter.js` (forecast)
   - `utils/salesAnalytics.js`, `routes/dashboard.js` (monthly income / expense: "Purchase Order" matched `purchase%`), `utils/assistantTools.js`
   - Each file checks whether the columns exist (re-checked every 10 minutes). Before the SQL has run, they send exactly the same queries as today.
3. **Agent**: build the new exe (`lib/voucherTypes.cjs` plus the changes in `agent.cjs`).
   - Each voucher now carries `is_cancelled`, `is_optional` and `base_type`.
   - The voucher types come from one small masters read (NAME and PARENT), at most every 10 minutes.
   - It runs one full voucher pass after the update (`voucher_status_v5`). That pass also runs the end-of-pass cleanup, which removes vouchers deleted in Tally.
   - If the Agent goes out before the backend, the extra fields are ignored. The weekly full pass then fills them in once the backend is live.
4. **App**: build as usual. Cancelled vouchers show "Cancelled" in the list and on the voucher screen.

## What changes for Lumilo once the pass is done

- Purchase Orders, Delivery Challans, Replacements, Receipt Notes, Rejections and Stock Journals no longer move P&L, BS, TB, Cash Flow or the ledger balances.
- Optional vouchers (for example the optional Delivery Challan in April 2025) are no longer listed. The count then matches Tally's Statistics: 440 in April 2025.
- Cancelled vouchers stay listed (Tally counts them too), marked "Cancelled", and are never in the figures.

## Tests

- Backend: `node --test --experimental-test-module-mocks test/voucherStatus.test.mjs`, run from the backend folder. It uses a fake database and no network.
- Agent: `AGENT_DIR=<tally-agent> node --test agent/voucherTypes.test.cjs`.
