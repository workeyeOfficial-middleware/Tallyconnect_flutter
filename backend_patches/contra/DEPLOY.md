# Create Entry — Phase 1: Contra + Journal fix

No SQL. No new `.env` values. The 5 existing entry types keep their routes and payloads.

## What changes

| Part | Change |
|---|---|
| Agent | Journal and Contra no longer need a party (this fixes Journal entries that failed with "Party name is missing"). Their ledgers must already exist in Tally; a missing ledger is no longer auto-created under *Indirect Incomes*. New Contra voucher, posted only between Cash-in-Hand / Bank Accounts / Bank OD ledgers (sub-groups included). |
| Backend | New route `POST /api/mobile-voucher-command/contra/create` in a **new file**. `mobileVoucherCommand.js` is not changed. |
| App | The Contra card on New Entry opens a 3-step flow: Details → To account → Check. |

## Release order

1. **Agent first**, so it can post Contra entries before any are queued.
2. **Backend.**
3. **App.**

An app on an older server shows "Contra entries are not available on the server yet."

## 1. Agent (`tally-agent`)

The files are already edited in `C:\Users\AVERLON\Downloads\tally-agent`:

- `lib/mobileVouchers.cjs` (new; a copy is in `agent/` here)
- `agent.cjs`:
  - requires the new module;
  - party check only for Sales, Purchase, Receipt and Payment;
  - Journal and Contra use existing ledgers only;
  - Contra cash / bank check;
  - `fetchTallyGroupParents()`;
  - `buildVoucherXML` accepts Contra.

Rebuild the Agent and the desktop app as usual.

## 2. Backend

Copy these two files into the backend, keeping the paths:

```
utils/contraCore.js
routes/UniversalUpdate/mobileContraCommand.js
```

In `server.js`, add these two lines next to the existing `mobileVoucherCommand` lines:

```js
import mobileContraCommand from "./routes/UniversalUpdate/mobileContraCommand.js";
app.use("/api/mobile-voucher-command", mobileContraCommand);
```

Contra rows go into the same `mobile_sync_queue` table, in the same shape as Journal rows (`entity_type` VOUCHER, `action` CREATE). The Agent's pending list and the app's Activity pick them up without changes.

## Tests

```
node --test backend_patches/contra/test/
AGENT_DIR=C:/Users/AVERLON/Downloads/tally-agent node --test backend_patches/agent/mobileVouchers.test.cjs
flutter test test/contra_entry_test.dart
```

## Check in Tally (use a test company first)

1. Contra, Cash → Bank, ₹100. Tally Day Book shows a Contra entry: Bank Dr 100, Cash Cr 100.
2. Contra, Bank → Bank, with a cheque / UTR number. The number appears as the voucher's Reference.
3. Contra using a non-cash/bank ledger, for example a party sent through the API. The queue row fails with "Contra is only for cash and bank accounts …".
4. **Journal:** a Journal between non-cash ledgers (for example Rent Dr / Salary Payable Cr) now reaches Tally instead of failing with "Party name is missing". Also try one Journal that uses a cash or bank ledger, and note whether your Tally accepts it. Tally normally expects Contra, Payment or Receipt for cash and bank.
5. **Journal with a ledger name not in Tally:** fails with "Ledger not found in Tally: …". Nothing is created.
6. **Existing types:** one Sale, Purchase, Receipt and Payment. They behave exactly as before.
