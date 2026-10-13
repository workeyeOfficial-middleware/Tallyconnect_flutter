# Outstanding email reminders — manual deployment

Everything here is applied **by hand**. Nothing has been run against any
database or server, and nothing has been deployed.

## 1. Files (already copied into `TallyConnect-push/tally-backend`, uncommitted)

| From this folder | In the backend | Status |
|---|---|---|
| `routes/reminders.js` | `routes/reminders.js` | new |
| `utils/reminderRouter.js` | `utils/reminderRouter.js` | new |
| `utils/reminderCore.js` | `utils/reminderCore.js` | new |
| `utils/sendReminderEmail.js` | `utils/sendReminderEmail.js` | new |
| `sql/2026-10-12_reminders.sql` | run in the database (step 3) | new |

`server.js` — two lines (already added):

```js
import reminderRoutes from "./routes/reminders.js";
// … right after app.use(feedbackRoutes); — before app.use("/", requireAuth, userRequestsRouter)
app.use(reminderRoutes); // /api/reminders/* (own login check; before the "/" catch-all)
```

No other backend file changes: `GET /bill`, `/bill/ledger/:guid`, the sync
routes and the Tally Agent are untouched. No new npm packages (`express`,
`axios` are already dependencies).

## 2. Security model

* Every route needs a login (`requireAuth`).
* Account = JWT `adminId`; company = the account's row in `active_company`
  (read on the server, never from the request). Ledgers, bills, templates
  and history are filtered by both.
* USER logins: only ledgers in `user_ledger_permissions`. Template
  create / edit / delete: `role = ADMIN` only.
* The app sends only `ledger_guid` + bill numbers. Pending amounts, due
  dates and the recipient (`ledgers.email`) are read from the database
  (`bills.pending_amount > 0`, not PAYABLE, active company). The unfiltered
  `GET /bill` is **not** used.
* All Tally / template text is HTML-escaped; subject is one line.
* Limits: per user per hour (`REMINDER_RATE_LIMIT_PER_HOUR`, default 20),
  per account per day (`REMINDER_RATE_LIMIT_PER_DAY`, default 200); the
  same party + same bills within `REMINDER_DUPLICATE_WINDOW_MINUTES`
  (default 60) is refused; `idempotency_key` (unique per account) makes a
  repeated confirmation return the first result instead of a second email.
* Nothing is written to Tally or to `sync_queue`.

## 3. Database

Run `sql/2026-10-12_reminders.sql` on **staging** first, then production.
It only creates `reminder_templates` and `reminder_log` (+ indexes),
`IF NOT EXISTS`, in one transaction. Check first that `users.id` is
`integer`/`bigint` (the tables store ids as `BIGINT`).

## 4. Environment

Uses the **existing** Microsoft Graph settings (same as password-reset and
feedback emails) — no new secrets:
`MICROSOFT_TENANT_ID`, `MICROSOFT_CLIENT_ID`, `MICROSOFT_CLIENT_SECRET`,
`MICROSOFT_SENDER_EMAIL`. The app registration needs the `Mail.Send`
application permission for the sender mailbox. If any is missing, preview
says so and send answers **503 `email_not_configured`** (recorded as a
failed attempt) — never a fake success.

Optional:
```env
REMINDER_RATE_LIMIT_PER_HOUR=20
REMINDER_RATE_LIMIT_PER_DAY=200
REMINDER_DUPLICATE_WINDOW_MINUTES=60
```

## 5. API

| Route | Who | Notes |
|---|---|---|
| `GET /api/reminders/templates` | signed in | built-in template when none; `can_edit`, `email_configured` |
| `POST /api/reminders/templates` | ADMIN | `{name, subject, body, is_default}`; placeholders `{{party}} {{company}} {{bills}} {{total}} {{count}} {{sender}}` |
| `PUT /api/reminders/templates/:id` | ADMIN | partial update |
| `DELETE /api/reminders/templates/:id` | ADMIN | |
| `POST /api/reminders/preview` | signed in + ledger access | `{ledger_guid, bill_names[], template_id?}` → recipients, bills, total, subject, text, html, `can_send`, `problems` |
| `POST /api/reminders/send` | signed in + ledger access | + `expected_total` (409 `changed` if Tally data moved), `idempotency_key` |
| `GET /api/reminders/history?ledger_guid=` | signed in + ledger access | this company only |
| `POST /api/reminders/:id/retry` | signed in + ledger access | failed ones only; bills / recipient read again |

Send results: **200 `accepted`** = Microsoft Graph accepted the message
(HTTP 202). It is **not** a delivery confirmation and is never shown as
"delivered". **502 `send_failed`** carries Graph's error; **503
`email_not_configured`**; **409** `duplicate` / `changed` /
`nothing_pending` / `no_company`; **422** `no_email`; **429**
`rate_limited` (+ `Retry-After`); **403** no ledger access / not admin;
**404** party not in the active company.

## 6. Tests

`test/reminders.test.mjs` (node:test, 19 tests, fake database and mailer):

```bash
# in a scratch copy of this folder
echo {"type":"module"} > package.json
npm install express@5 axios
node --test test/reminders.test.mjs
```

## 7. Deploy and check

1. Run the SQL (step 3), deploy the backend with the new files and the
   `server.js` change, **rebuild the container** (`docker compose up -d --build`).
2. Smoke test with a real login token:
   ```bash
   curl https://<backend>/api/reminders/templates -H "Authorization: Bearer <token>"
   # → 200 {"success":true,"data":[{"name":"Standard reminder",…}],"email_configured":true}
   ```
3. In the app: Outstanding → Receivable → Email reminder → a customer with
   an email in Tally → Preview → Send email → Yes, send. Then check
   `SELECT id, status, error, provider_status FROM reminder_log ORDER BY id DESC LIMIT 5;`
