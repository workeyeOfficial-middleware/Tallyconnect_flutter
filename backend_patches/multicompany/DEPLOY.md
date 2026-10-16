# Multi-company sync — deployment and test checklist (16 Oct 2026)

What's in this release:
- **Several companies, automatically.** The Agent syncs every *enabled* company,
  one after another.
- **Companies page in the Agent:**
  - companies open in Tally, with a switch for each;
  - the plan limit;
  - per-company progress;
  - **Refresh companies** and **Restart Agent** buttons.
- **The same Tally company in two accounts.** Each account gets its own separate
  copy of the data.
- **App:** each company's sync line shows the new states: "Syncing · 45%", "Not
  open in Tally", "Last sync failed: …".

**Safety switch: off by default.** Off means the Agent syncs only the active
company, exactly as before. Turn it on in **Agent → Companies → "Sync all enabled
companies"**, or with `MULTI_COMPANY=on`.

**Next step, not in this release:** each app user choosing their own company
(about 47 company lookups in 20 backend files).

Nothing has been deployed, built, committed or run against a database.

---

## Order (do not change it)
1. **SQL part A** (adds only).
2. **Backend** (push and redeploy).
3. **SQL part B** (removes the old company-only keys).
4. **Agent** (build and install), then **the tests** (section 5).
5. **App** (next release; optional for this feature).

## 1. SQL part A, before the backend
File: `backend_patches/multicompany/sql/2026-10-16_multicompany_A_before_deploy.sql`
- Run the 2 `CREATE UNIQUE INDEX CONCURRENTLY` lines **one by one**, with
  auto-commit on and no `BEGIN`/`COMMIT` around them.
- Then run the `BEGIN … COMMIT` block. It adds columns to `selected_companies` and
  `agent_status`, and creates `company_sync_locks`.

## 2. Backend (`C:\Users\AVERLON\Downloads\TallyConnect-push`)
```powershell
cd C:\Users\AVERLON\Downloads\TallyConnect-push
git add tally-backend/server.js tally-backend/routes/companies.js tally-backend/routes/agentStatus.js tally-backend/routes/orders.js tally-backend/routes/salesOrder.js tally-backend/routes/invoice.routes.js tally-backend/routes/invoice.bulk.js tally-backend/routes/ledgerItems.js tally-backend/routes/voucherEntry.js tally-backend/routes/ledgers.js tally-backend/routes/companySync.js tally-backend/utils/companySyncRouter.js
git commit -m "Multi-company sync: selection, locks, per-company status; same company in several accounts"
git push origin production_code
```
Then on the server: `git pull`, then `docker compose up -d --build`. The backend
`.env` needs nothing new.

| File | Change |
|---|---|
| `routes/companySync.js`, `utils/companySyncRouter.js` | new: `/company/agent-config`, `/company/selection`, `/company/sync-lock`, `/company/sync-progress`, `/company/sync-status` |
| `server.js` | mounts them before the company routes |
| `routes/companies.js` | `/create`: one row per account (no more "belongs to another account"); `/selected`: joined on account, returns `enabled`; plan limit counts enabled companies |
| `routes/agentStatus.js` | sync status also returns state, step, % and error |
| `orders.js`, `salesOrder.js`, `invoice.routes.js`, `invoice.bulk.js`, `ledgerItems.js` | upserts on the account-scoped keys |
| `voucherEntry.js`, `ledgers.js` | deletes limited to this account |

Every new column is read with a fallback, so the backend works both before and
after part A.

## 3. SQL part B, after the backend is live
File: `backend_patches/multicompany/sql/2026-10-16_multicompany_B_after_deploy.sql`

It drops the 5 company-only unique keys (ledgers, invoices, orders, sales_orders,
voucher_bill_map). Each table keeps its account-scoped key, and no rows are touched.
Until part B runs, a second account still can't sync a company that another account
already has. Everything else works.

## 4. Agent (`C:\Users\AVERLON\Downloads\tally-agent`), built by you
| File | Change |
|---|---|
| `lib/multiCompany.cjs` | new: enabled companies, lock, progress |
| `lib/syncProgress.cjs` | snapshot also gives the current step |
| `agent.cjs` | company loop hooks (only when switched on), local endpoints `/api/companies*` and `/api/agent/restart`, clearer message when the port is taken |
| `web/src/pages/Company.jsx`, `web/src/index.css`, rebuilt `frontend/` and `frontend-assets.js` | new Companies page |
| `desktop/main.js` | tells the Agent the desktop app restarts it (`TC_MANAGED`) |
| `tools/company-probe.cjs` | new: one-time Tally test |

Build as usual (`npm run build`) and rebuild the desktop app.

**How Restart Agent works:**
- **Inside the desktop app or the supervisor:** the Agent ends and they start it
  again.
- **Run on its own:** it starts a fresh copy, which waits 4 s for the port, then
  ends. Sync checkpoints are kept either way.

## 5. Tests on your Tally (before switching on for customers)
1. **Switch off** (default). Install the new Agent and let it sync twice. Check:
   - it syncs the active company exactly as before;
   - the app's figures are unchanged.
2. **Open 2 companies in Tally,** then run `node tools\company-probe.cjs`.
   - **"Each company answered with its own data":** continue.
   - **"the SAME ledgers":** keep multi-company off on that PC.
3. **Agent → Companies:**
   - **Refresh companies:** both companies are listed as *Open in Tally*;
   - **switch both on:** the plan-limit message appears if you are over the limit;
   - **turn on "Sync all enabled companies"**.
4. **Next sync:** the log shows `🏢 Multi-company sync: A, B`. Each company shows a
   progress ring, then *Synced*. In the app, switch between the two companies and
   check their figures against Tally.
5. **Close one company in Tally:**
   - next sync: it shows *Not open in Tally*;
   - the other company still syncs;
   - nothing is synced into the wrong company.
6. **Stop during a sync**, then **Resume:** the company goes back to idle, and the
   next sync continues from its saved position.
7. **Restart Agent:** the page reconnects within a few seconds.
8. **Two accounts** (staging): sign a second account in on another PC with the same
   Tally company. Both sync and each sees only its own data, after part B.
9. **Rollback at any time:** switch "Sync all enabled companies" off. The Agent is
   back to the active company only.

## Tests run (16 Oct)
| Suite | Result |
|---|---|
| Backend multi-company routes | 5/5 |
| Agent multi-company module | 6/6 |
| Agent sync progress | 6/6 |
| Agent financial | 8/8 |
| Backend financial | 22/22 |
| Sales analytics | 6/6 |
| AI assistant | 30/30 |
| Flutter (all, incl. the new company status test) | 251/251 |

All of these use fake data, with no real Tally or database. The Agent was also
started once locally without Tally (smoke test): it loads with no errors and the
new endpoints answer.
