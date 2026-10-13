# Feedback API — manual deployment

> **2026-10-12 fix — email result.** `POST /api/feedback` now answers only
> after the email was tried: `201 {email_status:"sent"}` (Microsoft Graph
> accepted it, HTTP 202), `502 {email_status:"failed"}`, or
> `503 {email_status:"skipped"}` when `FEEDBACK_NOTIFICATION_EMAIL` is
> missing / invalid. The feedback is stored in every case (`stored:true`).
> The app shows "Thank you — your feedback was sent" only for `sent`.
> Updated files: `utils/feedbackRouter.js`, `utils/sendFeedbackEmail.js`.
> New team check: `GET /api/admin/feedback/email-config` (needs
> `FEEDBACK_ADMIN_EMAILS`) shows the recipient and which `MICROSOFT_*`
> variables are present (never their values).
>
> **Check the recipient spelling** in `tally-backend/.env` on the server:
> it must be exactly the inbox that should receive feedback (e.g.
> `work272002@gmail.com` — the example below used `wokk2720022@gmail.com`).

Everything here is applied **by hand**. Nothing has been run against any
database or server.

## 1. Files

Copy these into the backend (`tally-backend/`), keeping the same paths:

| From this folder | To the backend | Status |
|---|---|---|
| `routes/feedback.js` | `routes/feedback.js` | new |
| `utils/feedbackRouter.js` | `utils/feedbackRouter.js` | new |
| `utils/feedbackCore.js` | `utils/feedbackCore.js` | new |
| `utils/sendFeedbackEmail.js` | `utils/sendFeedbackEmail.js` | new |
| `sql/2026-10-12_feedback.sql` | run in the database (step 3) | new |

No existing file changes except the two lines in `server.js` (step 2). No new
npm packages: the code uses `express` and `axios`, which are already
dependencies.

## 2. `server.js` — two lines

Add the import with the other route imports (for example after
`import ledgerItemRoutes from "./routes/ledgerItems.js";`):

```js
import feedbackRoutes from "./routes/feedback.js";
```

Mount it **right after** `app.use("/company", companiesRoute);` (line ~59) —
it must be **before** `app.use("/", requireAuth, userRequestsRouter);`, which
catches everything after it:

```js
app.use(feedbackRoutes); // POST /api/feedback, /api/admin/feedback…
```

The router sets its own full paths (`/api/feedback`, `/api/admin/feedback`)
and its own login check (`requireAuth`), so it is mounted without a prefix.

## 3. Database

1. Check the users id type (the table stores it as `BIGINT`):
   ```sql
   SELECT data_type FROM information_schema.columns
    WHERE table_name = 'users' AND column_name = 'id';
   ```
   `integer` or `bigint` → fine. If it is `uuid`, change `user_id` and
   `admin_id` in the SQL file to `UUID` before running it.
2. Run `sql/2026-10-12_feedback.sql` on **staging** first, then production
   (psql: `\i 2026-10-12_feedback.sql`). It only creates the new `feedback`
   table and its indexes (`IF NOT EXISTS`, in one transaction).
3. Verify with the read-only queries at the end of the file.

## 4. Environment variables

Add to the backend environment (and to `.env.example` without values):

```env
# Where every feedback is emailed (change to info@averlonworld.com later —
# no code change needed, only this value and a restart).
FEEDBACK_NOTIFICATION_EMAIL=wokk2720022@gmail.com

# TallyConnect team logins (comma-separated emails) allowed to review
# feedback through /api/admin/feedback. Empty = nobody (closed by default).
FEEDBACK_ADMIN_EMAILS=

# Optional rate limits per user (defaults 5 per hour, 20 per day).
FEEDBACK_RATE_LIMIT_PER_HOUR=5
FEEDBACK_RATE_LIMIT_PER_DAY=20
```

The email is sent with the **existing** Microsoft Graph settings already used
for password-reset emails — they must be present:
`MICROSOFT_TENANT_ID`, `MICROSOFT_CLIENT_ID`, `MICROSOFT_CLIENT_SECRET`,
`MICROSOFT_SENDER_EMAIL`.

## 5. Deploy and check

1. Deploy the backend with the new files, `server.js` change and variables;
   restart it.
2. Smoke test with a real login token:
   ```bash
   curl -X POST https://<backend>/api/feedback \
     -H "Authorization: Bearer <token>" -H "Content-Type: application/json" \
     -d '{"type":"feedback","rating":5,"message":"Test from deployment"}'
   # → 201 {"success":true,"id":1}
   ```
3. Check the email arrived at `FEEDBACK_NOTIFICATION_EMAIL`, and in the
   database: `SELECT id, email_status, email_error FROM feedback ORDER BY id DESC LIMIT 5;`
4. Send from the app: Home → feedback button → Send.

## API

### `POST /api/feedback` — any signed-in user
Body: `{ "type": "feedback"|"bug"|"idea", "message": "1–1000 chars",
"rating": 1–5 (optional; ignored for bug), "app_version": "…",
"platform": "…" }`. The user, account (admin) and active company are taken
from the login on the server, never from the body.

| Status | Meaning |
|---|---|
| 201 `{success, id}` | Stored (the email follows in the background) |
| 400 `{message}` | Invalid input |
| 401 | Not signed in |
| 429 `{message}` + `Retry-After` | Too many in the last hour / day |
| 500 | Could not store — nothing was saved or emailed |

### Team review — signed in **and** email in `FEEDBACK_ADMIN_EMAILS`
* `GET /api/admin/feedback?status=new|seen|resolved&type=…&q=…&page=1&limit=25`
* `GET /api/admin/feedback/:id`
* `PATCH /api/admin/feedback/:id` `{ "status": "seen|resolved|new", "admin_note": "…" }`
* `POST /api/admin/feedback/:id/resend-email` — re-sends a failed email

Customer ADMIN accounts cannot read other customers' feedback; only the
allow-listed team emails can.

## Behaviour notes

* **Email never loses feedback**: the row is saved first; the email is sent
  after the response and its result recorded in `email_status`
  (`sent` / `failed` + `email_error` / `skipped` when no address is set).
  Failed ones: list with the query in the SQL file, re-send with
  `POST /api/admin/feedback/:id/resend-email`.
* **Email content** is HTML-escaped; the subject is one line (no header
  injection); Reply-To is the customer's login email.
* **Rate limit** counts stored rows per user, so it works with several
  server instances; two requests at the very same moment can each pass the
  check (at most one extra row).

## Tests

`test/feedback.test.mjs` (Node's built-in runner, 15 tests, no database):

```bash
# in a scratch copy of this folder
echo {"type":"module"} > package.json
npm install express@5
node --test test/feedback.test.mjs
```
