# Cash Flow Forecast — Phase 1

Reports → **Cash flow forecast**: 13 weeks of opening balance, money in, money out and closing balance.

- **Money in:** open customer bills, each placed on its due date plus how late that customer usually pays. A switch shows plain due dates instead.
- **Money out:** open supplier bills on their due dates.
- **Opening balance:** today's cash and bank balance.

It is **read-only**:
- **Agent:** no change.
- **Database:** no new tables, no data written; one optional index file.
- **Existing routes:** nothing changed.

## Who sees it

The account admin, and team members the admin allowed to see Financial Reports (Team → member → Financial reports). This is the same rule as `/api/financial/*`.

Demo Company and sample data don't show it.

## Backend

New files, copied in with their paths:

```
utils/cashflowCore.js        calculations (no database)
utils/cashflowRouter.js      GET /api/cashflow/forecast, GET /api/cashflow/week
routes/cashflow.js           wires the database, login and financial figures
```

`server.js`: two lines, next to the existing `financialRoutes` / `salesAnalyticsRoutes` lines and **before** the `"/"` catch-all:

```js
import cashflowRoutes from "./routes/cashflow.js";
app.use(cashflowRoutes); // /api/cashflow/* (own login check; before the "/" catch-all)
```

The new files need the Financial Reports files that are already deployed (`utils/financialData.js`, `utils/financialCore.js`). They don't change them.

## SQL

None is required. `sql/2026-10-16_cashflow_indexes.sql` holds two optional indexes for large companies. Run each statement on its own.

## Release order

Backend first, then the app.

On an older server the app shows "The cash flow forecast is not available on the server yet."

## How the figures are worked out

| Figure | Source |
|---|---|
| Open bills | The `bills` table where pending amount > 0, active company only |
| Cash + bank today | The Financial Reports figures on their newest date, plus cash and bank vouchers after that date. All ledgers under Cash-in-Hand, Bank Accounts and Bank OD count, sub-groups included. If Financial Reports aren't synced, the screen shows "Not available" and still shows money in and out. |
| Customer's usual delay | Each customer's receipts in `voucher_entries` are matched to their oldest unpaid invoices first. Delay = receipt date − due date, in days. The figure is the **amount-weighted median** over the last 12 months, with each delay capped between −30 and 180 days. With fewer than 3 bills or less than ₹10,000 of history, it is blended with the all-customers figure; with no history, the all-customers figure is used. Credit notes and journals reduce a bill but don't count as payments. |
| Invoice due date | The bill with the same number (`vouchers.reference_no` = `bills.bill_name`). Otherwise the invoice date + the customer's usual credit days. |
| Week | Monday to Sunday, India time. Late bills count in the current week. Bills more than 90 days past due are shown separately and not counted, unless "Count them" is tapped. |

Payment delays are kept for 6 hours per company. The refresh button on the screen recalculates them.

## Known limits (Phase 1)

- **Delays are an estimate:** matching receipts to the oldest invoices first goes wrong when customers pay chosen bills. Phase 2 reads Tally's bill-wise receipts for exact delays.
- **Advances may look like money to come in:** the Agent sends bill amounts without the Dr/Cr sign. This is a Phase 2 fix.
- **Bills only:** salaries, rent, taxes and loan payments are not included (Phase 3). The screen says so.
- **Only bill-wise parties:** a party whose bills Tally doesn't keep bill by bill has no bills, so it isn't forecast.

## Tests

```
# From the backend folder (it has express):
node --test <path>/backend_patches/cashflow/test/cashflow.test.mjs
flutter test test/cashflow_test.dart
```

## Check with real data

1. Reports shows **Cash flow forecast** for an admin. It doesn't show for a team member without financial-report access.
2. "Cash + bank today" matches the Balance Sheet's cash and bank total for today.
3. Switch to **Due dates**. Week totals then match Tally's Cash Flow Projection, weekly, for receivables and payables.
4. Tap a week. Its bills add up to that week's money in and money out.

---

# Phase 2: exact payment delays and advances

Two fixes to the Phase 1 limits:

- **Exact delays:** delays now come from the receipts in Tally that name the bill they pay ("Agst Ref" bill-wise allocations), instead of matching receipts to the oldest bills first.
- **Advances left out:** advances (bills on the opposite Dr/Cr side) are no longer counted as money to come in or go out.

Phase 1 is kept as the fallback: for customers without bill-wise receipts, and on a server where the Phase 2 SQL hasn't been run yet.

## What changes

| Part | Change |
|---|---|
| **Agent** | <ul><li>**New file:** `lib/billSettlements.cjs`.</li><li>**`agent.cjs`, additive only:**<ul><li>While vouchers are read as usual, each voucher's bill allocations are collected and sent to `POST /api/cashflow/agent/settlements`. No extra Tally request.</li><li>New sync step **"Payment history"** (`billSettlements`, after Financial statements): reads the **last ~13 months** of the Voucher Register once, **3 months per sync run**, and remembers how far it got for each company. When it has caught up, it does nothing.</li><li>After each bills sync, Tally's signed amount of every current bill goes to `POST /api/cashflow/agent/bill-signs`.</li></ul></li><li>**Existing uploads** (`/voucher-entry/sync`, `/bill/sync`, reconcile) are unchanged. On a server without these routes (404), the Agent stops trying for that run and carries on.</li><li>**Agent screen:** the new step shows as "Payment history"; `web/src/lib/format.js` is changed and the UI is rebuilt into `frontend/` and `frontend-assets.js`.</li></ul> |
| **Backend** | `utils/cashflowCore.js` and `utils/cashflowRouter.js` (same files as Phase 1, updated). No change to `server.js` or any other file. |
| **SQL** | `sql/2026-10-17_cashflow_phase2.sql`: two **new** tables, `bill_settlements` and `bill_balance_signs`. No existing table is changed. |
| **App** | Customers show "(exact)" or "(estimated)". The notes say which delays are exact, and how much in advances was left out. |

## Order

1. **Run the SQL** (`2026-10-17_cashflow_phase2.sql`, all of it, once).
2. **Deploy the backend** (the 2 files).
3. **Build and install the Agent.** History fills in over the next few syncs, 3 months per run.
4. **App.**

If the backend goes out before the SQL, the forecast still works with the Phase 1 estimate. The Agent's uploads fail until the tables exist, and the Agent tries again on the next sync.

## How an exact delay is found

- A **receipt** (customer) or **payment** (supplier) line "Agst Ref S/101 ₹10,000" means bill S/101 was paid that day.
- **The bill's due date comes from:**
  1. the bills table;
  2. otherwise, its "New Ref" (the invoice) date plus its credit period from Tally;
  3. otherwise, the invoice date plus the customer's usual credit days.
- **Part payments** each count with their own amount.
- **Credit notes and journals** against a bill are not money, so they aren't counted.
- **When a customer uses the exact figure:** it has at least one such payment in the last 12 months. Otherwise the Phase 1 estimate is used.

## How an advance is found

Tally gives each current bill a Dr or Cr amount. Within receivables, and separately within payables, most bills are on one side. A bill on the **other** side is an advance. If the two sides are tied, Tally's own convention decides (a receivable is Dr). Advances are listed in the notes, not counted.

## Tests

```
# Agent (no Tally needed):
AGENT_DIR=C:/Users/AVERLON/Downloads/tally-agent node --test backend_patches/agent/billSettlements.test.cjs
# Backend (from a folder that has express):
node --test backend_patches/cashflow/test/cashflow.test.mjs
flutter test test/cashflow_test.dart
```

## Check with real data

1. After the first sync with the new Agent, its log shows "💸 Bill settlements history … voucher(s) read" for the months it read.
2. `SELECT ref_type, COUNT(*) FROM bill_settlements GROUP BY 1;` shows Agst Ref and New Ref rows.
3. The forecast's customer list shows "(exact)" for customers who pay against bills in Tally.
4. A customer advance in Tally shows in the notes ("Advances received …") and not in money in.
