# TallyConnect Backend — API Reference (for Flutter integration)

> **Single source of truth** for the future Flutter ↔ backend integration.
> Audited source: `C:\Users\AVERLON\Downloads\Tallyconnect__Backend\tally-backend` (read-only audit, nothing modified).
> Audit date: 3 Oct 2026.
> Every endpoint below exists in the source code. Nothing was inferred or invented.
> Anything the code does not show is marked **NOT FOUND / NOT DETERMINED**.

---

## 0. How to read this document

### 0.1 Status labels (per endpoint, relative to the current Flutter app)

| Label | Meaning |
|---|---|
| **IMPLEMENTED** | Endpoint exists and is usable for the Flutter feature as-is. |
| **NEEDS ADAPTER / BACKEND CHANGE** | Endpoint exists, but its shape, scope or behaviour doesn't match what the Flutter screen needs. The gap needs a client-side adapter or a backend change. |
| **MISSING ENDPOINT** | Flutter needs it, and no suitable endpoint exists (listed per module and in §25). |
| **AGENT / WEB ONLY** | Exists, but it serves the Tally desktop agent or the web admin panel. The Flutter app should not call it. |
| **BROKEN** | Exists, but fails at runtime as written (details given). |

### 0.2 Stack facts

| Item | Value (from source) |
|---|---|
| Runtime | Node.js, ES modules (`"type": "module"`) |
| Framework | Express **5.2.1** (`express.json({limit:"50mb"})`, `express.urlencoded`) |
| Database | PostgreSQL via `pg` Pool (`db.js`); `DATABASE_URL` or fallback `postgresql://postgres:crm%40123@localhost:5433/Tally12` |
| Auth | JWT (`jsonwebtoken`), `Authorization: Bearer <token>`, expiry **1 day** |
| CORS | `cors()`: all origins allowed |
| Port | `process.env.PORT \|\| 4000` |
| Base URL | NOT DETERMINED (no deployment config in repo; `queueWorker.js` mentions `process.env.API_BASE_URL`) |
| DB schema / migrations | **NOT FOUND** (no SQL schema in repo). Column types are therefore NOT DETERMINED unless the code creates the table (`mobile_notifications`, `mobile_notification_preferences`, `voucher_bill_map`, `selected_companies.starting_from`). |
| External services | Licentic license server (`dashboard.licentic.org`), Microsoft Graph (emails), Brevo (emails), Cloudinary (avatars) |
| Background jobs | `cron/monthlyReportCron.js` runs every minute and writes Excel reports and notifications. `routes/queueWorker.js` is **never imported (dead code)**. |

### 0.3 Global response conventions (inconsistent — see §28)

- There is no single envelope. Endpoints return one of:
  - `{ success: true, data: … }`
  - a raw array or object
  - `{ success: true }`
  - errors as `{ message }`, `{ error }`, `{ success:false, message }` or `{ success:false, error }`
- **PostgreSQL `NUMERIC` / `BIGINT` / `COUNT(*)` come back as JSON strings** (node-pg default), e.g. `"receivables": "348690.00"`, `"pending_bills": "3"`.
  - Flutter must parse with `num.tryParse` for every money or count field unless the route explicitly calls `Number(...)` (noted per endpoint).
- `DATE` / `TIMESTAMP` columns serialise as ISO-8601 strings (`"2026-09-26T00:00:00.000Z"`). A `DATE` column becomes midnight UTC, so convert carefully to IST for display.
- **Common unhandled behaviour:**
  - Many handlers have no `try/catch`. On a DB error Express 5 returns its default **500 HTML/text** error, not JSON (noted per endpoint as *"unhandled → default 500"*).
  - Several routes read `req.user` with no `requireAuth` on the route itself. They depend on the mount-level middleware (§1.3).

---

## 1. Authentication model

### 1.1 Token

| Item | Value |
|---|---|
| Header | `Authorization: Bearer <JWT>` (checked by `middleware/requireAuth.js`) |
| Secret | ⚠️ `routes/auth.js` line 5 **overwrites** `process.env.JWT_SECRET = "tallyconnect-local-test-secret-2026"` at import time. The `.env` value is ignored. |
| Algorithm | jsonwebtoken default (HS256) |
| Expiry | `1d` |
| Claims (`req.user`) | `{ id, role ("ADMIN"\|"USER"), adminId, username, email, iat, exp }` |
| Missing / bad header | `401 { "message": "Unauthorized" }` |
| Invalid / expired token | `401 { "message": "Invalid token" }` |
| Refresh token endpoint | **NOT FOUND** |
| Logout endpoint | **NOT FOUND** (stateless JWT; the client discards the token) |

### 1.2 Roles

| Role | Created by | Data scope |
|---|---|---|
| `ADMIN` | Licentic login (auto-provisioned) or `POST /auth/register` with `isAdmin:true` | `admin_id = id`. Owns companies, ledgers, vouchers, … |
| `USER` | Admin via `POST /users` (or `POST /auth/register`) | `admin_id` = owning admin. Sees only the ledgers, vouchers, orders and inventory items the admin assigned. |

Most business queries filter by `admin_id = req.user.adminId` **and** `company_guid = (SELECT company_guid FROM active_company WHERE admin_id = …)`. The **active company is per admin, not per user**, and only an ADMIN can change it (`POST /company/set-active`).

### 1.3 Mount-level middleware (server.js) — important

| Mount | Effect |
|---|---|
| `/ledger` | Wrapper skips auth for `/sync`, but `/ledger/sync` itself has `requireAuth`, so a **token is still required**. |
| `/voucher-entry` | Wrapper skips auth for `/sync`, `/mark-inactive`, `/bulk-sync`. `/sync` has its own `requireAuth`; **`/mark-inactive` route does not exist**; `/bulk-sync` is unauthenticated and **broken** (§13). |
| `/invoice`, `/invoice-item` | Wrapper skips auth for `/sync` and `/bulk-sync`. Per-route `requireAuth` applies where present. |
| `/orders`, `/admin/notifications`, `/api/mobile/notifications`, `/entry-field-settings` | `requireAuth` on the whole mount. |
| **`app.use("/", requireAuth, userRequestsRouter)`** (line 137) | ⚠️ Runs `requireAuth` for **every request that reaches it**. As a result:<br>• every router mounted **after** it requires a Bearer token: `/api/mobile-voucher-command`, `/api/mobile-sync-queue`, `/api/mobile/notifications`, `/ledger-items`, `/entry-field-settings`, **`GET /`** and **`GET /check-db`**;<br>• any **unknown path** returns `401 Unauthorized` (instead of 404) when no token is sent. |
| `/users` **and** `/api/users` | The same router is mounted twice (every `/users/*` path also exists under `/api/users/*`). |
| `/inventory`, `/stock-summary` | Mounted twice (harmless duplicate). |
| `/uploads` | `express.static("uploads")`: public static files (no auth). |

### 1.4 Authentication flow (as implemented)

```
1. POST /auth/login  { username: <email>, password, loginType: "ADMIN" | "USER" }
   ADMIN → backend checks Licentic license → Licentic customer-login → finds/creates local ADMIN → JWT
   USER  → local users table, plain-text password compare, must have admin_id → JWT
2. Store token (1 day). Send Authorization: Bearer <token> on every call.
3. GET /users/me                   → profile + permission objects
4. GET /company/active             → { company_guid } (active company of the admin)
   GET /company/selected           → companies the admin selected (name + guid)
   (ADMIN only) POST /company/set-active { company_guid } to switch
5. All data endpoints use the server-side active company implicitly.
6. On 401 → token expired/invalid → re-login (no refresh endpoint).
Forgot password: POST /api/auth/send-otp {email} → email OTP (10 min) → POST /api/auth/verify-otp {email, otp, newPassword}
```

---

## 2. Authentication (module 1)

**Module status:**
- IMPLEMENTED: login, OTP password reset, `/auth/me`.
- NEEDS ADAPTER: login (`loginType` is required but the Flutter login has no role selector); forgot password (Flutter shows "send link", the backend uses an OTP and new-password flow).
- MISSING: refresh token, logout, change password for a logged-in user (the menu's "Change password" can only reuse the OTP flow).

### POST `/auth/login`
| Field | Detail |
|---|---|
| Status | **NEEDS ADAPTER**: `loginType` is mandatory; the Flutter login screen has no ADMIN/USER switch. |
| Auth | None |
| Headers | `Content-Type: application/json` |
| Body | `username` *string, required* (treated as **email**: trimmed + lower-cased), `password` *string, required*, `loginType` *"USER" \| "ADMIN", required* |
| 200 (USER) | `{ token: string, user: { id: int, username: string, email: string, role: "USER", adminId: int } }` |
| 200 (ADMIN) | `{ token, user: { id, username, email, role: "ADMIN", adminId, plan: string\|null } }`. `plan` = Licentic `licenseTypeId.name`. |
| Errors | `400 {message:"Username and password required"}`; `400 {message:"loginType is required (USER or ADMIN)"}`<br>USER: `401 "No account found with this email"`, `403 "Invalid user login type"`, `401 "Invalid credentials"`, `403 "User is not linked to any admin"`<br>ADMIN: `403 "No active license found"`, `401 "Invalid credentials"`, `403 "Not an admin account"`<br>`500 {message:"Login failed"}` |
| ⚠️ Unclear | If `loginType` is any other non-empty value (e.g. `"user"` lowercase), **no response is ever sent** (request hangs until timeout). |
| Tables | `users` (read; insert on first ADMIN login, `setval` on `users_id_seq`) |
| Side effects | ADMIN: two outbound calls to `dashboard.licentic.org` (`/api/external/actve-license/{email}?productId=695902cfc240b17f16c3d716` and `/api/external/customer-login`). The local admin is auto-created with `username = email` prefix and the **plain-text password stored**. |
| Rules | Passwords are stored and compared **in plain text** (bcrypt commented out). |

### POST `/auth/register`
| Field | Detail |
|---|---|
| Status | **AGENT / WEB ONLY** (⚠️ security risk: unauthenticated, can create an ADMIN) |
| Auth | None |
| Body | `username` string, `email` string, `password` string, `isAdmin` boolean (optional) |
| 200 | `{ success: true, user: { id, username, role } }` |
| Errors | `400 {message:"User already exists"}`; `500 {message: err.message}` |
| Tables | `users` insert; ADMIN → `admin_id = id`. USER created this way has `admin_id = NULL`, so it **cannot log in** ("User is not linked to any admin"). |

### GET `/auth/me`
| Field | Detail |
|---|---|
| Status | IMPLEMENTED (prefer `GET /users/me`, which returns more fields) |
| Auth | Bearer |
| 200 | `{ id, username, role, adminId, ledgerPermissions: object\|null, vouchersPermissions: object\|null, ordersPermissions: object\|null, inventoryPermissions: object\|null, dashboardPermissions: object (default {widgets:{}}) }` |
| Errors | 401. If the user row was deleted → crash (`user` undefined) → default 500. No try/catch. |
| Tables | `users` |

### POST `/api/auth/send-otp`
| Field | Detail |
|---|---|
| Status | **NEEDS ADAPTER**: the Flutter "Forgot password" screen says "we will send you a link", but the backend sends a 6-digit **OTP**. Flutter needs OTP + new-password steps. |
| Auth | None |
| Body | `email` string, required (case-insensitive match) |
| 200 | `{ message: "OTP sent successfully" }` |
| Errors | `400 "Email required"`; `404 "User not found"` (⚠️ reveals whether an account exists); `500 "Server error"` (also when the email send fails) |
| Tables | `users.reset_otp`, `users.otp_expiry` (now + 10 min) |
| Side effects | Email via Microsoft Graph (`utils/sendResetEmail.js`, env `MICROSOFT_*`). |

### POST `/api/auth/verify-otp`
| Field | Detail |
|---|---|
| Status | IMPLEMENTED (needs a new Flutter step) |
| Auth | None |
| Body | `email` string, `otp` string (6 digits; compared as string), `newPassword` string (all required) |
| 200 | `{ message: "Password updated successfully" }` |
| Errors | `400 "All fields required"`, `404 "User not found"`, `400 "Invalid OTP"`, `400 "OTP expired"`, `500 "Server error"` |
| Rules | Password saved in **plain text**; OTP cleared. No attempt limit or rate limit. |

---

## 3. User / Profile (module 2)

**Module status:**
- IMPLEMENTED: read profile.
- NEEDS ADAPTER: the profile shows *Mobile*, *Plan* and *Renews on*. The backend has no user mobile/phone field; the plan comes only from the ADMIN login response; no renewal date exists.
- MISSING: user mobile number, plan renewal date.

### GET `/users/me`  (alias `/api/users/me`)
| Field | Detail |
|---|---|
| Status | IMPLEMENTED |
| Auth | Bearer |
| 200 | `{ id:int, username, email, company:string\|null, role, avatar_url:string\|null, admin_email:string, ledger_permissions, vouchers_permissions, orders_permissions, inventory_permissions, dashboard_permissions, ledgerPermissions, vouchersPermissions, ordersPermissions, inventoryPermissions, dashboardPermissions }`. Each permission object is returned **twice** (snake_case and camelCase, same object). Defaults are `{columns:{}}` and `{widgets:{}}` for dashboard. |
| Errors | `500 {message:"Failed to load profile"}` |
| Tables | `users` (self join for `admin_email`) |

### PUT `/users/me`
| Field | Detail |
|---|---|
| Status | IMPLEMENTED with a ⚠️ **critical security bug**: the body field `role` is written directly, so any USER can set `"role":"ADMIN"`. Flutter must always send the current role unchanged. |
| Auth | Bearer |
| Body | `username`, `email`, `company`, `role`. **All four are written**; omitted ones become `NULL`. |
| 200 | `{ success: true }` |
| Errors | `500 "Profile update failed"` |

### POST `/users/me/avatar`
| Field | Detail |
|---|---|
| Status | NEEDS ADAPTER (Flutter has no avatar upload; the returned URL is likely wrong) |
| Auth | Bearer |
| Headers | `Content-Type: multipart/form-data` |
| Body | file field **`avatar`** (jpg/png/jpeg/webp, max 2 MB) |
| 200 | `{ avatar_url: "/uploads/avatars/<filename>" }` |
| ⚠️ Unclear | The file goes to **Cloudinary** (`multer-storage-cloudinary`, folder `avatars`, public_id `user-<id>`), but the saved URL is a local `/uploads/avatars/...` path built from `req.file.filename`. That path will probably not resolve. The Cloudinary URL (`req.file.path`) is discarded. |
| Errors | `500 "Avatar upload failed"`; multer errors (size/format) → default error handler |

### GET / PUT `/users/me/notifications`
| Field | Detail |
|---|---|
| Status | WEB ONLY (web notification preferences). For mobile use `/api/mobile/notifications/config` (§19). |
| Auth | Bearer |
| GET 200 | `notification_preferences` jsonb object or `{}`. Known keys: `user_created, user_deleted, new_voucher, payment_due, low_stock, monthly_reports, bill_created` (booleans) |
| PUT body | Any JSON object (stored as-is, **no validation**) |
| PUT 200 | `{ success: true }` |
| Errors | 500 `{message}` |

### GET / PUT `/users/me/monthly-report-schedule`
| Field | Detail |
|---|---|
| Status | IMPLEMENTED (no Flutter UI yet) |
| Auth | Bearer |
| PUT body | `report_day` int (day of month, required), `report_time` string `"HH:mm"` **in UTC** (required; the cron compares against the UTC clock), `enabled` boolean |
| PUT 200 | `{ success: true }`. `400 {message:"Missing fields"}` |
| GET 200 | `{ day_of_month, report_time, enabled }` or `null` |
| Side effects | Cron (every minute) generates `uploads/reports/monthly_report_<userId>_<ts>.xlsx` from DB function `monthly_report_data(adminId)` and inserts a **web** notification `MONTHLY_REPORT`. |
| Errors | No try/catch → default 500 |

---

## 4. Company (module 3)

**Module status:**
- IMPLEMENTED: list companies, get/set the active company.
- NEEDS ADAPTER: the Flutter company sheet lets **any** user switch company, but the backend allows only an ADMIN (`403` for USER). The active company is shared by the admin and all their users. Per-company "synced 10:32 AM" needs `GET /agent-status/sync-status` per company.
- MISSING: "Refresh company list from Tally" (an agent concern; no endpoint triggers it).

### GET `/company`
| Field | Detail |
|---|---|
| Status | IMPLEMENTED (⚠️ side effect) |
| Auth | Bearer (router-level) |
| 200 | `{ success: true, data: [ companies.* ] }`. Columns include `company_guid`, `name`, `admin_id`, `created_at` (other columns NOT DETERMINED). Sorted `created_at DESC`. |
| ⚠️ Side effect | First runs `UPDATE companies SET admin_id = <caller adminId> WHERE admin_id IS NULL`. **Any caller claims all unowned companies** (cross-tenant risk). |
| Errors | No try/catch → default 500 |

### GET `/company/selected`
| Field | Detail |
|---|---|
| Status | IMPLEMENTED (best source for the Flutter "Choose company" list) |
| Auth | Bearer |
| 200 | `{ success: true, data: [ { company_guid, name, starting_from: "YYYY-MM-01" or null } ] }`, sorted by `selected_at ASC` |
| Tables | `selected_companies` joined with `companies` |

### GET `/company/active`
| Field | Detail |
|---|---|
| Status | IMPLEMENTED |
| Auth | Bearer |
| 200 | `{ success: true, company_guid: string or null }` (per **admin**) |

### POST `/company/set-active`
| Field | Detail |
|---|---|
| Status | NEEDS ADAPTER (ADMIN only; Flutter must hide or disable switching for USER) |
| Auth | Bearer, role ADMIN |
| Body | `company_guid` string, required |
| 200 | `{ success: true, company_guid }` |
| Errors | `403 {message:"Admin only"}`, `400 {message:"company_guid required"}`, `500 {message:"Server error"}` |
| Rules | Does **not** verify that the company belongs to the admin. Changes the active company for the admin **and all their users**. |
| Tables | `active_company` upsert (`admin_id` unique) |

### POST `/company/select`
| Field | Detail |
|---|---|
| Status | WEB ONLY (company onboarding with license limit) |
| Auth | Bearer, ADMIN |
| Body | `company_guid` string, required |
| 200 | `{ success: true }` |
| Errors | `403 "Admin only"`, `400 "company_guid required"`, `403 {success:false, message:"Company selection limit exceeded. ..."}`, `500 "Server error"` |
| Side effects | Licentic license lookup; on a new selection → heartbeat `company-limit +1`. |

### GET `/company/by-guid/:guid`
| Field | Detail |
|---|---|
| Status | IMPLEMENTED |
| Auth | Bearer |
| Path | `guid`: company_guid |
| 200 | `{ success: true, data: { company_guid, name } }` |
| Errors | `404 { error: "Company not found" }` (note: `error`, not `message`) |

### GET `/company/sync-start/:guid`
| Field | Detail |
|---|---|
| Status | WEB ONLY |
| Auth | Bearer |
| 200 | `{ success: true, company_guid, starting_from: "YYYY-MM-01" or null }` |
| Errors | `500 {success:false, message:"Server error"}` |

### PUT `/company/sync-start/:guid`
| Field | Detail |
|---|---|
| Status | WEB ONLY |
| Auth | Bearer, ADMIN |
| Body | `starting_from` string `YYYY-MM-01`, required |
| 200 | `{ success: true, company_guid, starting_from }` |
| Errors | `403 "Admin only"`, `400 "starting_from is required (YYYY-MM-01)"`, `400 "Invalid date format. Use YYYY-MM-01"`, `500` |
| ⚠️ Rule | Inserts into `selected_companies` if missing, **bypassing the license company limit** checked in `/company/select`. |

### POST `/company/create`
| Field | Detail |
|---|---|
| Status | AGENT ONLY |
| Auth | Bearer (comment says "NO AUTH" but `requireAuth` is applied) |
| Body | `company_guid` string, `name` string (both required) |
| 200 | `{ success: true, data: company }` or `{ success: true, skipped: true, message: "Company belongs to another account" }` |
| Errors | `400 {success:false, message:"company_guid and name are required"}`, `500` |

---

## 5. Dashboard (module 4)

**Module status:**
- IMPLEMENTED: To get / To give totals, the Tally sync status line.
- NEEDS ADAPTER: Money in / out this month, Total sales / purchase this month (derive from `/voucher-entry/paged` meta or `/dashboard/income-expense`); Cash in hand / Bank balance (derive from `GET /ledger` closing balances by group).
- MISSING: a single dashboard endpoint returning the 8 Flutter money cards.

### GET `/dashboard/summary`
| Field | Detail |
|---|---|
| Status | IMPLEMENTED (Home "To get" / "To give", Dues hub totals) |
| Auth | Bearer |
| Query | `company_guid` string, **required** |
| 200 | `{ receivables: "numeric-string", payables: "numeric-string", pending_bills: "count-string", cleared_bills: "count-string" }` |
| Errors | `400 {message:"company_guid required"}`, `500 {message:"Summary failed"}` |
| Rules | Sums `bills.pending_amount > 0` split by `bill_type` RECEIVABLE / PAYABLE, for `admin_id` and `company_guid`. Not filtered per USER permissions. |

### GET `/dashboard/income-expense`
| Field | Detail |
|---|---|
| Status | NEEDS ADAPTER (monthly sales/purchase totals; Flutter needs "this month") |
| Auth | Bearer |
| Query | `company_guid` (not validated; missing → empty result) |
| 200 | `[ { month: ISO timestamp (month start), income: "numeric-string", expense: "numeric-string" } ]`, ascending |
| Rules | `income` = vouchers with `voucher_type ILIKE 'sales%'`; `expense` = `ILIKE 'purchase%'`; active vouchers only. Date range: all months (no filter). |
| Errors | `500 {message:"Failed to load income/expense"}` |

### GET `/dashboard/bills`
| Field | Detail |
|---|---|
| Status | NEEDS ADAPTER (no `bill_type`, `bill_name` or party info; prefer `GET /bill`) |
| Auth | Bearer |
| Query | `company_guid` |
| 200 | `[ { ledger_name, pending_amount: "numeric-string", due_date } ]`, pending > 0, `due_date ASC NULLS LAST` |
| Errors | `500 {message:"Failed to load bills"}` |

### GET `/bill/dashboard-summary`
| Field | Detail |
|---|---|
| Status | Overlaps `/dashboard/summary` (no receivable/payable split) |
| Auth | Bearer |
| Query | `company_guid`, required |
| 200 | `{ total_outstanding: "numeric-string", pending_bills: "count-string", settled_bills: "count-string" }` |
| Errors | `400`, `500 {message:"Failed to load dashboard summary"}` |

### GET `/agent-status/sync-status`
| Field | Detail |
|---|---|
| Status | IMPLEMENTED (Home "Tally Connected · Synced N min ago", Activity header) |
| Auth | Bearer |
| Query | `company_guid` (optional; if missing → `{success:true, last_sync_at:null, sync_in_progress:false}`) |
| 200 | `{ success: true, last_sync_at: ISO or null, sync_in_progress: boolean }` |
| Errors | `500 {success:false}` |
| Note | There is no "Tally connected / computer name" field. The prototype's "RAJESH-PC" is **NOT FOUND** in the API (`/agent/agent-info` stores Tally details but has no GET). |

---

## 6. Parties / Ledgers (module 5)

**Module status:**
- IMPLEMENTED: party list (via ledgers), party detail, party entries, items per party, bills per party.
- NEEDS ADAPTER:
  - customer/supplier type must be derived from `parent_group` / `type` (e.g. "Sundry Debtors" / "Sundry Creditors");
  - balance sign / "They owe you" must be derived from `closing_balance`;
  - the USER list omits `email` / `phone`.
- MISSING:
  - **create party from the app** (Flutter "Add new party"). Only Sales/Purchase can carry an unvalidated `new_party` object inside the voucher payload; there is no ledger create endpoint;
  - party city / address / GSTIN / contact person (not stored in `ledgers`);
  - "Quiet customers" (no sale in 60 days); derivable from the `date` field of `GET /ledger`.

### GET `/ledger`
| Field | Detail |
|---|---|
| Status | IMPLEMENTED (+ adapter for type / city) |
| Auth | Bearer |
| 200 | `{ success: true, data: [ Ledger ] }`, sorted by name ASC, **active company only** |
| Ledger (ADMIN) | `{ ledger_guid, name, email, phone, parent_group, type, opening_balance: "numeric-string", closing_balance: "numeric-string", date: last voucher date or null, voucher_type, reference_no }` |
| Ledger (USER) | same **without `email` and `phone`**; only ledgers in `user_ledger_permissions` |
| ⚠️ Note | `date` / `voucher_type` / `reference_no` are `MAX()` per ledger name taken **independently**, so they may come from different vouchers. |
| Pagination / filter / sort | None (full list) |
| Errors | `500 {success:false}` |
| Tables | `ledgers`, `active_company`, `user_ledger_permissions`, `voucher_entries` |

### GET `/ledger/:ledgerGuid`
| Field | Detail |
|---|---|
| Status | IMPLEMENTED (party detail header) |
| Auth | Bearer; USER must have a ledger permission |
| 200 | Full `ledgers.*` row (columns include `admin_id, ledger_guid, company_guid, name, email, phone, parent_group, opening_balance, closing_balance, type`; others NOT DETERMINED) |
| Errors | `404 {message:"Ledger not found"}`, `403 {message:"Access denied"}`, `500 {message:"Failed to fetch ledger details"}` |
| ⚠️ Note | Not filtered by active company (any company of the admin). |

### GET `/voucher-entry/ledger/:ledgerGuid`
| Field | Detail |
|---|---|
| Status | IMPLEMENTED (party detail → Entries tab) |
| Auth | Bearer; USER permission check |
| 200 | `[ { id: voucher_guid, voucher_date, voucher_type, reference_no, debit: "numeric-string", credit: "numeric-string", items: [ { voucher_guid, item_name, total_qty, total_amount } ] } ]`, `voucher_date ASC` |
| Errors | `403`, `500 {message:"Failed to fetch ledger vouchers"}` |
| Rules | Active company; joins `voucher_entries.ledger_name = ledgers.name`. |

### GET `/ledger-items/ledger/:ledgerGuid`
| Field | Detail |
|---|---|
| Status | IMPLEMENTED (party detail → Items tab) |
| Auth | Bearer; USER permission check |
| 200 | `[ { item_name, total_qty, total_amount, first_date, last_date } ]`, sorted `total_amount DESC` |
| Errors | `403`, `500 {message:"Failed to fetch ledger items"}` |

### GET `/bill/ledger/:ledgerGuid`
| Field | Detail |
|---|---|
| Status | IMPLEMENTED (party pending bills) |
| Auth | Bearer; USER permission check |
| 200 | `[ { bill_name, ledger_name, bill_date, due_date, pending_amount: "numeric-string", bill_type: "RECEIVABLE" or "PAYABLE", items: [ { voucher_guid, voucher_no, item_name, total_qty, total_amount } ] } ]`. Only `pending_amount > 0`, active company, `due_date ASC`. |
| ⚠️ Note | `bill_date` is selected, but `/bill/sync` never writes it, so it is likely always null. |
| Errors | `403`, `404 {message:"Ledger not found"}`, `500 {message, error}` |

### GET `/invoice/ledger/:ledgerGuid`
| Field | Detail |
|---|---|
| Status | IMPLEMENTED (alternative party invoice list) |
| Auth | Bearer; USER check **without** admin scoping (`user_ledger_permissions` only) |
| 200 | `[ { id: invoice_guid, invoice_no, invoice_date, invoice_type, party_name, total_amount } ]` |
| Errors | `403`, `500 {message:"Failed to fetch invoices"}` |

### GET `/ageing/ledger/:ledgerGuid`
| Field | Detail |
|---|---|
| Status | NEEDS ADAPTER (⚠️ unauthenticated and not tenant-scoped) |
| Auth | **None** |
| 200 | `[ {period:"0-30",amount:number}, {period:"31-60",...}, {period:"61-90",...}, {period:"90+",...} ]` |
| ⚠️ Bugs | Joins `bills.ledger_name = ledgers.name` with **no admin or company filter** (mixes tenants with the same party name). Reads `bill.amount` while every other bills query uses `pending_amount` (whether column `amount` exists is NOT DETERMINED). Buckets are by days since due date, so not-yet-due bills fall into "0-30". |
| Errors | `500 {error}` |

### GET `/ledger-items/item/:itemName/parties`
| Field | Detail |
|---|---|
| Status | IMPLEMENTED (no Flutter screen yet; useful for item detail) |
| Auth | Bearer |
| Path | `itemName` (URL-encoded, case-insensitive) |
| Query | `type` = `Sales` or `Purchase` (optional) |
| 200 | `[ { party_name, total_qty, total_amount, invoices: "count-string", last_date } ]` (empty if no active company) |
| Errors | `500 {message:"Failed to fetch item parties"}` |

### GET `/ledger/deleted/history`
| Field | Detail |
|---|---|
| Status | WEB ONLY |
| Auth | Bearer |
| 200 | `{ success: true, data: [ { id, company_guid, entity_type:"ledger", entity_guid, entity_data: object, deleted_at } ] }` |

### POST `/ledger/deleted/restore/:id`
| Field | Detail |
|---|---|
| Status | WEB ONLY |
| Auth | Bearer |
| 200 | `{ success: true, message: "Ledger already exists in DB, queued for Tally restore" or "Ledger restored and queued for Tally" }` |
| Errors | `404 {error:"Record not found"}`, `500 {error}` |
| Side effects | `sync_queue` upsert `LEDGER/CREATE`; deletes the `deleted_records` row. |

### POST `/ledger/sync` and POST `/ledger/cleanup/ledger`
| Endpoint | Detail |
|---|---|
| `/ledger/sync` | **AGENT ONLY**. Bearer. Body: `ledger_guid`, `company_guid`, `name` (required), `parent_group`, `opening_balance`, `closing_balance`, `type`, `email`, `phone`. 200 `{success:true, data}` or `{success:false, skipped:true}`. Side effect: mobile notification `party_sync` / `ledger_sync`. |
| `/ledger/cleanup/ledger` | **AGENT ONLY** (⚠️ any authenticated USER can call it; no admin check). Body `{ company_guid, existing_ids: string[] }`. Deletes ledgers not in the list and archives them to `deleted_records`. 200 `{success:true, deleted:int}`. |

Ledger permission assignment (Team admin) is covered in §17.

---

## 7. Items / Inventory (module 6)

**Module status:**
- IMPLEMENTED: item list with stock, rate, value and GST (`GET /inventory/mobile`); stock summary (`GET /inventory`).
- NEEDS ADAPTER:
  - "Running low / Finished" status: the backend returns `minStock: 0` always, so Flutter must derive it (closing 0 = finished; the low threshold is NOT DETERMINED);
  - `/inventory/mobile` does **not** apply USER item permissions (see the bug below).
- MISSING: **create item** (Flutter "Add new item"; items only travel inside a voucher payload), barcode lookup, item categories list (Flutter uses static categories).

### GET `/inventory/mobile`
| Field | Detail |
|---|---|
| Status | IMPLEMENTED (Items screen, item picker in Sales/Purchase) |
| Auth | Bearer + `requireInventoryPermission` (USER with `inventory_permissions.can_view === false` → 403) |
| 200 | `{ success: true, items: [ Item ] }`, sorted by name ASC, active company |
| Item | `{ item_guid, name, group, unit, opening_qty: number, opening_value: number, closing_qty: number, closing_value: number, rate: number (closing_value / closing_qty), hsn_code: string or null, gst_rate, cgst_rate, sgst_rate, igst_rate: number or null, gst_applicable: string or null }` (all numbers converted with `Number()`) |
| ⚠️ Bug | Unlike `GET /inventory`, it does **not** restrict a USER to `user_inventory_permissions`: every item is visible. |
| Errors | `403 {message:"Inventory access denied"}`, `403 {message:"Invalid user"}`, `500 {success:false, message:"Failed to fetch mobile inventory"}` |
| Tables | `stock_items` left-joined with `stock_summary`, `active_company`, `users.inventory_permissions` |

### GET `/inventory`
| Field | Detail |
|---|---|
| Status | IMPLEMENTED (stock summary report; "Items not moving" can be derived from inward/outward) |
| Auth | Bearer + `requireInventoryPermission` |
| 200 | `{ success: true, data: [ { id: item_guid, name, opening, inward, outward, closing, rate, minStock: 0, value } ] }`. Numbers are numeric strings (no `Number()`). |
| Rules | USER: only items in `user_inventory_permissions`, and column hiding via `inventory_permissions.columns` (`itemCode → id`, `itemName → name`, `closingStock → closing`, `rate`, `value` deleted when `false`). |
| Errors | `403 {success:false, message:"You do not have permission to view inventory"}`, `500 {success:false}` |

### Inventory permission and agent endpoints
| Endpoint | Status | Auth | Body / response |
|---|---|---|---|
| GET `/inventory/user-inventory/:userId` | WEB ONLY (Team permissions) | Bearer + ADMIN | 200 `[ { item_name } ]` |
| POST `/inventory/user-inventory` | WEB ONLY | Bearer + ADMIN | Body `{ userId, items: string[] }` → `{ success: true }`; `400 {error:"Invalid payload"}` |
| POST `/inventory/bulk-user-inventory` | WEB ONLY | Bearer + ADMIN | Body `{ userIds: int[], items: string[] }` → `{ success: true }` (no validation; no try/catch) |
| POST `/inventory/full-sync` | AGENT ONLY | Bearer + ADMIN | Body `{ company_guid, item_guid, name (required), group, unit, opening_qty, opening_value, closing_qty, closing_value, hsn_code, gst_rate, cgst_rate, sgst_rate, igst_rate, gst_applicable }`. Errors are swallowed → `{ success: true, skipped: true }`. |
| POST `/inventory/inventory-movement/sync` | AGENT ONLY | Bearer + ADMIN | Body `{ company_guid, item_name, qty, movement_type "IN" or "OUT", voucher_type, voucher_date "YYYYMMDD" }` |
| POST `/inventory/cleanup` | AGENT ONLY | Bearer + ADMIN | Body `{ company_guid, existing_ids: string[] }`. Deletes summary, items and movements not in the list. |
| POST `/stock-item/sync` | AGENT ONLY | Bearer | Body `{ item_guid, company_guid, name, unit, opening_qty, opening_value }`. `ON CONFLICT (admin_id, item_guid)` differs from `full-sync`'s `(admin_id, company_guid, item_guid)`; one of them may not match a real unique index (NOT DETERMINED). No try/catch. Side effect: mobile notification `item_sync`. |
| POST `/stock-summary/sync` | AGENT ONLY | Bearer | Body `{ company_guid, item_name (required), closing_qty, closing_value }` |

---

## 8. Sales (module 7)

**Module status:**
- IMPLEMENTED: create Sales (queued to the Tally agent).
- NEEDS ADAPTER: the Flutter flow computes lines, GST and totals, but the backend expects `items[]`, `summary{subtotal,…,total_amount}` and `payment{…}`. Item and payment field names inside these objects are **not validated or defined** by the backend (passed through to the agent). Ledger entries are generated server-side (party Dr total, "Sales" Cr subtotal) with **no balance check**, and **GST ledgers are not generated**.
- MISSING:
  - next bill-number suggestion;
  - draft save (Flutter keeps drafts locally);
  - edit or cancel a queued mobile voucher.

### POST `/api/mobile-voucher-command/create`
| Field | Detail |
|---|---|
| Status | **NEEDS ADAPTER** (Sales and Purchase) |
| Auth | Bearer (route) + mount-level auth |
| Headers | `Content-Type: application/json` |
| Body | `voucher_type` **"Sales" or "Purchase"** (also accepts "Journal", "Payment", "Receipt", but then ledger entries are still generated as Sales; use the dedicated endpoints instead), **required**<br>`voucher_date` string, **required** (format NOT DETERMINED; passed to the agent as-is)<br>`voucher_no` string (optional)<br>`party_name` string (optional; used as the Dr ledger)<br>`new_party` object (optional; passed through, structure NOT DETERMINED)<br>`due_date` string (optional)<br>`narration` string (optional)<br>`items` **array, required for Sales/Purchase** (element structure NOT DETERMINED; passed through)<br>`summary` object `{ subtotal, discount, cgst, sgst, total_amount }` (defaults to zeros)<br>`payment` object `{ payment_mode, amount_received, balance_due }` (defaults to nulls/zeros)<br>`ledger_entries`: **ignored** (overwritten by generated entries) |
| Server-generated | `voucher_guid` (UUID), `reference_no = "MOBILE-<epoch ms>"`, `ledger_entries = [ {party_name, total_amount, is_debit:true}, {"Purchase" or "Sales", subtotal, is_debit:false} ]` |
| 200 | `{ success: true, command_id: int, voucher_guid: string, status: "QUEUED" }` or `{ success: true, duplicate: true, command_id: int }` |
| Errors | `400 {success:false, message:"voucher_type and voucher_date are required"}`, `400 "Unsupported voucher type: X"`, `400 "items must be an array for Sales/Purchase"`, `400 "No active company"`, `400 {success:false, message: err.message}` (any exception) |
| ⚠️ Bugs | (1) For **Purchase** the party is still put on the **debit** side and "Purchase" on credit, the reverse of Tally's purchase accounting (the web `/voucher-command` requires party Cr for Purchase). (2) Dr total ≠ Cr subtotal whenever tax exists; no tax ledgers. (3) The duplicate check hashes a payload that contains a random `voucher_guid` and a time-based `reference_no`, so it **never detects duplicates**; Flutter must prevent double-submit itself. |
| Tables | `active_company`, `mobile_sync_queue` (insert: `entity_type='VOUCHER'`, `action='CREATE'`, `source='MOBILE'`, `status='pending'`) |
| Side effects | Web notification `VOUCHER_CREATED` (to admin); mobile notification `create_entry` to the admin and all their users (respecting prefs). The Tally agent later polls `GET /api/mobile-sync-queue/pending`. |

**Example request (Sales)**
```json
{
  "voucher_type": "Sales",
  "voucher_date": "2026-09-26",
  "voucher_no": "11",
  "party_name": "Om Sai Electricals",
  "due_date": "2026-10-11",
  "narration": "Order by phone – deliver today",
  "items": [ { "name": "Havells FR Wire 1.5 sq mm (90 m)", "qty": 2, "unit": "coil", "rate": 1850, "gst": 18 } ],
  "summary": { "subtotal": 12300, "discount": 0, "cgst": 1107, "sgst": 1107, "total_amount": 14514 },
  "payment": { "payment_mode": "cash", "amount_received": 5000, "balance_due": 9514 }
}
```
> The `items[]` element keys above are the **Flutter proposal**; the backend does not define them (passed through to the agent). Confirm with the agent implementation (**NOT FOUND** in this repo).

### Other sales-related endpoints (not for the Flutter entry flow)
| Endpoint | Status | Auth | Notes |
|---|---|---|---|
| POST `/voucher-command/create` | WEB ONLY | Bearer | Web voucher builder (see §13). |
| GET `/invoice` | IMPLEMENTED (read-only invoice list) | Bearer | 200 `{ success:true, data:[ { invoice_guid, invoice_no, invoice_date, invoice_type, party_name, total_amount } ] }`, active company, `invoice_date DESC` |
| GET `/invoice-item/:invoice_guid` | IMPLEMENTED | Bearer | 200 `{ success:true, data:[ invoice_items.* ] }` (columns NOT DETERMINED beyond `admin_id, invoice_guid, item_name, quantity, rate, amount, company_guid`). ⚠️ Not admin-scoped (active company of the caller only). |
| POST `/invoice/sync`, POST `/invoice/bulk-sync` | AGENT ONLY | Bearer | invoice upsert (single / array) |
| POST `/invoice-item/sync` | **BROKEN** / AGENT | none | References undefined `admin_id` → always 500 `{error}` (also 6 columns vs 5 placeholders). |
| POST `/invoice-item/bulk-sync` | **BROKEN** / AGENT | none | 7 columns vs 6 placeholders → SQL error → `500 {success:false}`. |
| POST `/sales-order/sync` | AGENT ONLY | Bearer | Body `{ order_guid, company_guid, order_no, order_date, party_name, voucher_type, total_amount }`; no try/catch |
| POST `/sales-order-item/sync` | AGENT ONLY | Bearer | Body `{ order_guid, item_name, quantity, rate, amount }`; plain insert (duplicates on resync) |
| GET `/orders` | IMPLEMENTED (order book; no Flutter screen) | Bearer | 200 `{ success:true, data:[ { id, type, date, customer, amount, due_date, status, items:[{item_name,quantity,rate,amount}] } ] }`. USER: only `order_selection_permissions.allowed_orders`. ⚠️ ADMIN query filters by active company only (not `admin_id`). |
| POST `/orders/sync` | AGENT ONLY | Bearer | Body `{ order_guid, company_guid (required), order_no, order_date, party_name, total_amount, type }` |
| POST `/orders/cleanup/order` | AGENT ONLY | Bearer | Body `{ company_guid, existing_ids[] }` → sets `is_active=false` for missing orders |

---

## 9. Purchase (module 8)

Same endpoint as Sales: **POST `/api/mobile-voucher-command/create`** with `voucher_type: "Purchase"`.

**Module status:** NEEDS ADAPTER, with the same gaps as Sales, plus:
- the **inverted Dr/Cr bug** described in §8;
- Flutter's "Seller's bill no." (`pSupInv`) has no dedicated field (only `voucher_no`, `narration`, or pass-through inside `items` / `summary`).

MISSING: supplier invoice number field, next purchase number.

---

## 10. Money In / Receipt (module 9)

### POST `/api/mobile-voucher-command/receipt/create`
| Field | Detail |
|---|---|
| Status | **IMPLEMENTED** (Flutter Money In flow) + small adapter (field names below) |
| Auth | Bearer |
| Body | `voucher_date` string **required**<br>`voucher_no` string<br>`party_name` string **required**<br>`amount_received` number **> 0, required**<br>`reference_no` string (optional; default `"MOBILE-RECEIPT-<epoch>"`)<br>`narration` string<br>`payment` object: `payment_mode` **required** (values not enumerated by the backend), `bank_name`, `account_number`, `cheque_number`, `cheque_date`, `upi_ref`, `other_ref`, `deposit_account` (all optional strings) |
| Flutter mapping | `rParty → party_name`, `rAmt → amount_received`, `rRef ("Against Sales 9") → reference_no`, `rNote → narration`, `rBank → payment.bank_name`, `rUtr → payment.upi_ref` / `cheque_number` / `other_ref` depending on mode, `rAcc → payment.deposit_account`, mode `cash/bank/upi/cheque/other → payment.payment_mode` |
| 200 | `{ success: true, command_id, voucher_guid, status: "QUEUED" }` or `{ success:true, duplicate:true, command_id }` |
| Errors | `400 {success:false, message}`: `"voucher_date is required"`, `"party_name is required"`, `"amount_received must be greater than 0"`, `"payment_mode is required"`, `"No active company"`, or the exception message |
| Notes | The payload carries **no `ledger_entries`**; the agent must build them (agent NOT FOUND in repo). Duplicate protection only works when the client sends the same `reference_no` and identical data (the GUID is still random, so it effectively never matches). |
| Tables / side effects | `mobile_sync_queue` insert; notifications `VOUCHER_CREATED` (web) and `create_entry` (mobile) |

---

## 11. Money Out / Payment (module 10)

### POST `/api/mobile-voucher-command/payment/create`
| Field | Detail |
|---|---|
| Status | **IMPLEMENTED** + adapter (field names differ from Receipt) |
| Auth | Bearer |
| Body | `voucher_date` **required**, `voucher_no`, `party_name` **required**, `amount_paid` number **> 0 required**, `reference_no` (default `"MOBILE-PAYMENT-<epoch>"`), `narration`, `payment`: `{ payment_mode` **required**, `bank_account`, `transaction_instrument_no`, `transaction_date`, `remarks }` |
| Flutter mapping | `yParty → party_name`, `yAmt → amount_paid`, `yRef → reference_no`, `yNote → narration`, `yAcc → payment.bank_account`, `yUtr → payment.transaction_instrument_no`, `yBank → payment.remarks` (no bank-name field) |
| 200 / errors | Same shapes as Receipt (`"amount_paid must be greater than 0"`, …) |
| ⚠️ Inconsistency | Receipt uses `bank_name / account_number / cheque_number / upi_ref / deposit_account`; Payment uses `bank_account / transaction_instrument_no / transaction_date / remarks` for the same concepts. |

---

## 12. Adjustment / Journal (module 11)

### POST `/api/mobile-voucher-command/journal/create`
| Field | Detail |
|---|---|
| Status | **IMPLEMENTED** (Flutter Adjustment flow) |
| Auth | Bearer |
| Body | `voucher_date` **required**, `voucher_no`, `reference_no` (default `"MOBILE-JOURNAL-<epoch>"`), `narration`, `ledger_entries` **array, ≥ 2 required**: `[ { ledger_name: string (required), amount: number > 0, is_debit: boolean } ]` |
| Validation | Each entry is checked. Total Dr must equal total Cr within **0.01**. |
| Flutter mapping | `jl[] → ledger_entries` (`side "Dr" → is_debit:true`, `"Cr" → false`, `amt → amount`), `jNo → voucher_no`, `jNote → narration`. **"Main account" (`jParty`) has no backend field** (the server uses `ledger_entries[0].ledger_name` only for the notification text). |
| 200 | `{ success: true, command_id, voucher_guid, status: "QUEUED" }` / duplicate shape |
| Errors | `400 {success:false, message}`: `"voucher_date is required"`, `"ledger_entries must be an array"`, `"At least 2 ledger entries are required"`, `"ledger_name is required for every entry"`, `"Invalid amount for ledger: X"`, `"is_debit must be true or false for ledger: X"`, `{ success:false, message:"Journal is not balanced", total_debit, total_credit, difference }`, `"No active company"` |

---

## 13. Vouchers (module 12)

**Module status:**
- IMPLEMENTED: paged list with type, search, year and month filters plus sorting; voucher detail (ledger lines).
- NEEDS ADAPTER:
  - the Flutter period filter "Last 7 days" / "Today" has **no date-range query param** (only `year` and `month`); filter client-side or add `from` / `to`;
  - voucher type names are Tally names ("Sales", "Receipt", …) and must be mapped to the Flutter kinds;
  - "Synced" badge: every voucher in `vouchers` is already synced (it came from Tally), and `is_active` is returned;
  - per-type counts for the hub need one call per type (`meta.total`).
- MISSING: voucher detail with **items + party + amount** in one call (detail returns only ledger lines; items come from the list row), and a per-type count summary.

### GET `/voucher-entry/paged`
| Field | Detail |
|---|---|
| Status | **IMPLEMENTED** (preferred list endpoint) |
| Auth | Bearer |
| Query | `page` int ≥ 1 (default 1)<br>`limit` int 1–200 (default 50)<br>`type` string (`voucher_type ILIKE %type%`)<br>`search` string (matches party_name, reference_no, voucher_type, voucher_date text)<br>`year` int<br>`month` int 1–12<br>`sort_by` = `date_desc` (default) \| `date_asc` \| `amount_desc` \| `amount_asc` |
| 200 | `{ success: true, data: [ Voucher ], meta: { total: int, page, limit, hasMore: boolean, totalAmount: number, types: string[], years: int[] } }` |
| Voucher | `{ voucher_guid, company_guid, voucher_date, voucher_type, reference_no, amount: "numeric-string", is_active: boolean, party_name: string or null (falls back to the first credit-side ledger), items: [ { item_name, quantity, rate, amount } ] }` |
| Rules | Active company. USER: only `users.voucher_selection_permissions.allowed_vouchers`. ⚠️ Includes **inactive** (soft-deleted) vouchers, since there is no `is_active` filter. |
| Errors | `500 {success:false}` |

**Example**: `GET /voucher-entry/paged?page=1&limit=50&type=Receipt&year=2026&month=9&sort_by=date_desc`

### GET `/voucher-entry`
| Field | Detail |
|---|---|
| Status | IMPLEMENTED (unpaged; same row shape as `/paged`) |
| Auth | Bearer |
| Query | `ledgerGuid` (optional) switches to "ledger detail mode" |
| 200 (list) | `{ success:true, data:[ Voucher ] }` |
| 200 (ledgerGuid) | `[ { id, voucher_date, voucher_type, reference_no, debit, credit } ]` |
| ⚠️ Bug | Ledger mode joins `ledgers` on guid/company only, **without `ledger_name = l.name`**, so it returns **every entry of the company**. Use `GET /voucher-entry/ledger/:ledgerGuid` instead. |
| Errors | `403`, `500 {success:false}` |

### GET `/voucher-entry/:voucherGuid`
| Field | Detail |
|---|---|
| Status | IMPLEMENTED (entry detail) + adapter |
| Auth | Bearer |
| 200 | `{ voucher_guid, voucher_date, voucher_type, reference_no, ledger_entries: [ { ledger_name, amount: number, is_debit: boolean } ] }` |
| Errors | `404 {message:"Voucher not found"}`; no try/catch → default 500 |
| ⚠️ Note | No USER permission check (any voucher of the admin's active company). No items, party or net amount fields. |

### DELETE `/voucher-entry/:voucherGuid`
| Field | Detail |
|---|---|
| Status | WEB ONLY (soft delete in the cloud DB only; **not** propagated to Tally, and the next agent sync re-activates it) |
| Auth | Bearer (no role check) |
| 200 | `{ success: true }`; `500 {success:false}` |

### POST `/voucher-command/create` and `/voucher-command/alter`
| Field | Detail |
|---|---|
| Status | WEB ONLY (desktop web voucher builder). Flutter should use `/api/mobile-voucher-command/*`. |
| Auth | Bearer |
| Body | `voucher_type` ∈ Journal / Payment / Receipt / Sales / Purchase, `voucher_date`, `narration`, `reference_no`, `invoice_number`, `due_date`, `party`, `items[]`, `subtotal`, `discount_amount`, `taxable_amount`, `cgst_amount`, `sgst_amount`, `igst_amount`, `total_tax`, `invoice_total`, `payment`, `custom_fields`, **`ledger_entries[]` (required)**, plus `voucher_guid` (required for alter) |
| Validation | Every entry needs `ledger_name`, a truthy `amount` and a boolean `is_debit`. Dr must equal Cr exactly (float `!==`). Sales: exactly 1 Dr. Purchase: exactly 1 Cr. |
| 200 | create: `{ success:true, command_id, voucher_guid, status:"QUEUED" }` or `{ success:true, duplicate:true }`; alter: `{ success:true, command_id }` |
| Errors | `400 {message}` |
| ⚠️ Notes | The create duplicate check never matches (random guid in the hash). `/alter` inserts a second `sync_queue` row for the same `entity_guid`; `ledgers.js` uses `ON CONFLICT (admin_id, company_guid, entity_type, entity_guid)`, so a unique index probably exists and **alter of a previously created voucher would fail with 400**. |
| Tables | `sync_queue` (web queue, separate from `mobile_sync_queue`) |

### Voucher permission and agent endpoints
| Endpoint | Status | Auth | Detail |
|---|---|---|---|
| GET `/voucher-entry/user-vouchers/:userId` | WEB ONLY | Bearer (⚠️ no admin check, not tenant-scoped) | `{ vouchers: string[] }` |
| POST `/voucher-entry/user-vouchers` | WEB ONLY | Bearer (⚠️ any user can rewrite **any** user's permissions) | Body `{ userId, vouchers: string[] }` → `{ success:true }` |
| POST `/voucher-entry/bulk-user-vouchers` | WEB ONLY | Bearer (⚠️ same issue) | Body `{ userIds: int[], vouchers: string[] }` |
| POST `/voucher-entry/sync` | AGENT ONLY | Bearer | Body `{ voucher_guid, company_guid, voucher_date, voucher_type, reference_no, net_amount, party_name, entries:[{ledger_name, amount, is_debit}] }`. Errors are swallowed → `{success:true, skipped:true}`. Side effect: mobile notification `voucher_sync`. |
| POST `/voucher-entry/reset-active` | AGENT ONLY | Bearer | Body `{ company_guid }` → marks all vouchers inactive |
| POST `/voucher-entry/cleanup/voucher` | AGENT ONLY | Bearer | Body `{ company_guid, existing_ids[] }` → hard-deletes missing vouchers and archives them |
| POST `/voucher-entry/deleted/restore-voucher/:id` | WEB ONLY | Bearer | → `{ success:true, message:"Voucher restored" }`; `404 {error}`; no try/catch |
| POST `/voucher-entry/bulk-sync` | **BROKEN** | none | `voucherEntry.bulk.js` never imports `pool` → ReferenceError → default 500 |
| POST `/voucher-entry/mark-inactive` | **NOT FOUND** | — | Listed in the auth bypass in server.js, but no route exists |

---

## 14. Outstanding / Dues (module 13)

**Module status:**
- IMPLEMENTED: bill list with `bill_type`, pending amount and due date; totals (`/dashboard/summary`).
- NEEDS ADAPTER:
  - `GET /bill` returns **all companies** of the admin (filter `company_guid` client-side);
  - "late / due soon / later" status, "N days late" text and ageing buckets must be computed client-side from `due_date`;
  - party city comes from no source;
  - `bill_date` is never written by `/bill/sync`.
- MISSING:
  - WhatsApp reminder (single / bulk) and the auto-reminder toggle (Flutter shows toasts only);
  - payment-alert settings;
  - "As on" date from the server.

### GET `/bill`
| Field | Detail |
|---|---|
| Status | **IMPLEMENTED** + adapter (company filter, status computation) |
| Auth | Bearer |
| Query | none (⚠️ no company, pagination or status filter) |
| 200 | `{ success: true, data: [ bills.* ] }`, sorted `due_date ASC`. Known columns: `admin_id, company_guid, bill_guid, ledger_guid, ledger_name, bill_name, bill_amount, pending_amount, due_date, bill_type ("RECEIVABLE" or "PAYABLE"), status ("Pending" or "Settled"), sync_status, synced_at, sync_error, bill_date`. Exact set NOT DETERMINED (`SELECT *`). |
| Rules | Admin scope only; **not** limited to the active company; **not** limited for USER role (a USER sees all bills of the admin). |
| Errors | `500 {success:false}` |

### POST `/bill/push-to-tally`
| Field | Detail |
|---|---|
| Status | WEB ONLY (create a bill-wise entry and queue it to Tally). Not used by Flutter (Flutter creates vouchers instead). |
| Auth | Bearer |
| Body | `company_guid`, `ledger_guid`, `bill_name`, `bill_date`, `amount` (number) — all required; `bill_guid`, `due_date`, `voucher_type` ("Purchase" → PAYABLE, otherwise RECEIVABLE) |
| 200 | `{ success: true, message: "Bill queued for sync" }` |
| Errors | `400 "Missing fields"`, `403 "Access denied"`, `404 "Ledger not found"`, `500 "Failed to queue bill"` |
| Side effects | `bills` upsert, web notification `BILL`, `sync_queue` insert `BILL/CREATE` |

### Bill agent / maintenance endpoints
| Endpoint | Status | Auth | Detail |
|---|---|---|---|
| POST `/bill/sync` | AGENT ONLY | Bearer | Body `{ company_guid, ledger_name, bill_name (required), bill_guid, bill_amount: number, pending_amount: number, due_date, bill_type "PAYABLE" or other → RECEIVABLE }` |
| POST `/bill/mark-processing` / `mark-success` / `mark-failed` | AGENT ONLY | Bearer | Body `{ bill_name, company_guid, error? }` → `{success:true}`; no try/catch |
| POST `/bill/mark-all-cleared` | AGENT / WEB | Bearer | Body `{ company_guid }`; sets **every** bill of the company to pending 0 / Settled |
| POST `/bill/reconcile` | AGENT ONLY | Bearer | Body `{ company_guid, existing_bill_names: string[] }`; settles bills not in the list |
| POST `/bill/ensure-voucher-bill-map` | ⚠️ maintenance | Bearer | Runs `CREATE TABLE IF NOT EXISTS voucher_bill_map …` from an HTTP call; returns `{ success, found_in_schemas }` |

### Ageing endpoints (⚠️ unauthenticated, not tenant-scoped)
| Endpoint | Status | Detail |
|---|---|---|
| GET `/ageing` | **NEEDS BACKEND CHANGE** (do not use) | No auth. Returns the **whole `ageing` table of all tenants**: `{ success:true, data:[…] }`. Errors are returned as `200 {success:false, error}`. |
| POST `/ageing/sync` | AGENT ONLY | No auth. Body `{ ledger_guid, company_guid, period, amount }`; plain insert. |
| GET `/ageing/ledger/:ledgerGuid` | See §6 | |

---

## 15. Reports (module 14)

**Module status:**
- IMPLEMENTED: monthly turnover / expense / profit (`/api/reports/monthly-summary`); Day Book, Sales list and Purchase list (via `/voucher-entry/paged`); Stock summary (`/inventory`).
- NEEDS ADAPTER:
  - Top customers (aggregate `GET /bill` RECEIVABLE by `ledger_name`);
  - Quiet customers (from `GET /ledger` `date`);
  - Items not moving (from `GET /inventory` inward/outward);
  - monthly-summary amounts are likely **inflated** (see the bug below).
- MISSING:
  - Expenses report (direct / indirect expense ledgers);
  - report export (Flutter builds PDFs locally);
  - Profit & Loss read endpoint (`profit_loss` table is written by the agent but **never read**).

### GET `/api/reports/monthly-summary`
| Field | Detail |
|---|---|
| Status | IMPLEMENTED + ⚠️ data caveat |
| Auth | Bearer |
| Query | `company_guid` **required**, `year` int **required** |
| 200 | `[ { month: "Jan 2026", turnover: number, expense: number, profit: number } ]` (12 rows, Jan–Dec) |
| Rules | Turnover = voucher types sales / sales invoice / receipt / receipt voucher; expense = purchase / payment (case-insensitive, trimmed). USER: only allowed vouchers. |
| ⚠️ Bug | Sums **`voucher_entries.amount` (every Dr and Cr line)**, not voucher totals, so each voucher is counted on both sides (roughly 2× the real value). Receipts are also counted as turnover alongside sales. |
| Errors | `400 "company_guid is required"`, `400 "Year query param missing"`, `400 "Year must be a valid number"`, `500 "Internal server error"` |

### POST `/api/reports/profit-loss/sync`
| Field | Detail |
|---|---|
| Status | AGENT ONLY (⚠️ unauthenticated, no admin scope) |
| Body | `company_guid`, `month` (required), `from_date`, `to_date`, `net_amount`, `type` |
| 200 | `{ success: true }`; `400 {message:"company_guid and month required"}`, `500` |

---

## 16. Activity / History (module 15)

**Module status:**
- IMPLEMENTED: list of mobile-created entries with status (`pending`, `processing`, `success`, `failed`) and error message.
- NEEDS ADAPTER:
  - status values must be mapped (`success → Sent`, `pending`/`processing` → Waiting, `failed → Not sent`);
  - the display title, amount and party must be read from `payload` (different keys per voucher type: `summary.total_amount`, `amount_received`, `amount_paid`, `total_debit`);
  - not tenant-scoped (see below).
- MISSING:
  - **retry / re-queue a failed entry** (Flutter "Try again");
  - trigger a sync from the app ("Sync now"): `POST /sync/trigger` only sets an in-process global flag that nothing in this repo reads;
  - activity filtered by `admin_id` / user;
  - pagination (fixed `LIMIT 100`).

### GET `/api/mobile-sync-queue/activity`
| Field | Detail |
|---|---|
| Status | **IMPLEMENTED** + adapter |
| Auth | Bearer |
| Query | `company_guid` **required** |
| 200 | `[ { id: int, entity_type: "VOUCHER", action: "CREATE", status: "pending" or "processing" or "success" or "failed", payload: object (the queued voucher payload, see §8–§12), error: string or null, created_at: ISO, processed_at: ISO or null } ]`, newest first, max 100 |
| ⚠️ Security | Filtered **only by `company_guid`**: any authenticated user who knows a company guid can read its queue. |
| Errors | `400 {message:"company_guid required"}`, `500 {message:"Failed to fetch queue activity"}` |

### Agent queue endpoints (not for Flutter)
| Endpoint | Status | Auth | Detail |
|---|---|---|---|
| GET `/api/mobile-sync-queue/pending` | AGENT ONLY | Bearer | `?company_guid` → `[ {id, action, payload} ]` (10 oldest pending) |
| POST `/api/mobile-sync-queue/:id/processing` \| `/success` \| `/failed` | AGENT ONLY | Bearer (⚠️ any user, any id) | `/failed` body `{ error }`; side effect: mobile notification `entry_failed` |
| GET `/sync-queue/pending` \| `/pending-bills` \| `/pending-ledgers` | AGENT ONLY | Bearer | `?company_guid` → `[ {id, action, payload} ]` (web queue, VOUCHER / BILL / LEDGER) |
| POST `/sync-queue/:id/processing` \| `/success` \| `/failed` | AGENT ONLY | Bearer (⚠️ any id) | `/failed` side effect: mobile notification `sync_failed` |
| POST `/agent-status/sync-status` | AGENT ONLY | Bearer | Body `{ company_guid }`; records last sync; mobile notification `sync_completed` |
| POST `/agent-status/sync-started` | AGENT ONLY | Bearer | Body `{ company_guid }` |
| POST `/sync/event` | AGENT ONLY (⚠️ no auth) | none | Body `{ entity_type, entity_guid, company_guid, operation, source, payload }` → `{ success, queue_id, status: "INSERTED"/"UPDATED"/"NO_CHANGE", diff }`. ⚠️ Inserts into `sync_queue` with columns `operation`, `source`, `payload_hash` and no `admin_id`/`action`; whether this matches the real `sync_queue` schema is NOT DETERMINED. |
| POST `/sync/trigger` | ⚠️ no auth, no effect | none | Sets `global.FORCE_SYNC = true` (never read in this repo) → `{success:true, message:"Sync triggered"}` |
| GET `/sync/active-admin` | AGENT ONLY (⚠️ no auth, leaks `admin_id`) | none | `{ active:false }` or `{ active:true, admin_id, company_guid }` |

---

## 17. Team / Members (module 16)

**Module status:**
- IMPLEMENTED (ADMIN only): list users, create a user (email + password), delete a user, send an invite email.
- NEEDS ADAPTER:
  - Flutter "Add person" collects **name + mobile**, but the backend `POST /users` requires **email + password** (username = email prefix);
  - Flutter "Invite by email" creates a *pending* member, but the backend has no invitation state: `POST /send-invite` only emails credentials of an **existing** user, including the plain-text password;
  - member status `active` / `pending` / `off` and role text ("Sales Rep · Mumbai") do not exist;
  - a USER cannot access Team endpoints at all (403).
- MISSING:
  - **disable / enable access** (Flutter "Turn off access"); only DELETE exists;
  - resend / cancel invitation;
  - pending invites list;
  - member mobile number, role title and city.

### GET `/users`  (alias `/api/users`)
| Field | Detail |
|---|---|
| Status | IMPLEMENTED (ADMIN) |
| Auth | Bearer + ADMIN (`403 {message:"Admin access required"}`) |
| 200 | `[ { id, username, email, role, avatar_url, ledger_permissions, vouchers_permissions, orders_permissions, inventory_permissions, dashboard_permissions, ledgerPermissions, …(camelCase duplicates) } ]`, `id DESC`, `WHERE admin_id = adminId` (**includes the admin itself**) |
| Errors | No try/catch → default 500 |

### POST `/users`
| Field | Detail |
|---|---|
| Status | NEEDS ADAPTER (field mismatch) |
| Auth | Bearer + ADMIN |
| Body | `email` string **required**, `password` string **required** |
| 200 | `{ user: { id, username, email } }` (username = part before `@`) |
| Errors | `400 "Email and password required"`, `403 "Upgrade your plan to create more users"` (license `user-limit`), `400 "User already exists"`, `500 "Server error"` |
| Side effects | Licentic license lookup + heartbeat `user-limit +1`; password stored in plain text. |

### DELETE `/users/:id`
| Field | Detail |
|---|---|
| Status | IMPLEMENTED (maps to "Cancel invite" / remove member) |
| Auth | Bearer + ADMIN |
| 200 | `{ success: true }`; `404 {message:"User not found"}`, `500` |
| ⚠️ Security | Does **not** check that the user belongs to this admin (an admin can delete users of other tenants by id). |
| Side effects | Licentic heartbeat `user-limit −1`; web notification `USER_DELETED`. |

### POST `/send-invite`
| Field | Detail |
|---|---|
| Status | NEEDS ADAPTER (credentials email, not an invitation) |
| Auth | Bearer (⚠️ no ADMIN check, no tenant check) |
| Body | Single: `{ email, username }` (both required). Bulk: `{ users: [ { email } ] }` |
| 200 | `{ success: true }` or `{ success: true, bulk: true }` |
| Errors | `400 "Admin ID missing in token"`, `400 "Email and username are required"`, `404 "User not found"`, `500 {success:false, message}` |
| ⚠️ Security | Emails the user's **plain-text password** (Microsoft Graph). Works for any email in the database, including other tenants' users. |

### GET `/users/:id/invite-info`
| Field | Detail |
|---|---|
| Status | WEB ONLY (⚠️ returns the **plain-text password**) |
| Auth | Bearer + ADMIN; scoped to `admin_id` |
| 200 | `{ id, username, email, password }`; `404`, `500` |

### Permission management (ADMIN web panel; Flutter has no screen)
| Endpoint | Body | Notes |
|---|---|---|
| PUT `/users/:id/voucher-permissions` | any JSON → `vouchers_permissions` | ⚠️ no tenant check, no try/catch |
| PUT `/users/:id/ledger-permissions` | any JSON → `ledger_permissions` | same |
| PUT `/users/:id/orders-permissions` | any JSON → `orders_permissions` | same |
| PUT `/users/:id/inventory-permissions` | any JSON → `inventory_permissions` (`{ can_view: bool, columns:{…} }`) | same |
| PUT `/users/:id/dashboard-permissions` | any JSON → `dashboard_permissions` (`{ widgets:{…} }`) | same |
| PUT `/users/bulk-voucher-permissions` \| `bulk-orders-permissions` \| `bulk-ledger-permissions` \| `bulk-inventory-permissions` \| `bulk-dashboard-permissions` | `{ userIds: int[], permissions: object }` | `400 {message:"Invalid payload"}` |
| GET `/users/:id/ledgers` | — | `[ { ledger_guid } ]` (errors → `[]`) |
| POST `/users/bulk-ledger-assign` | `{ userIds: int[], ledgerIds: string[] }` | replaces `user_ledger_permissions` |
| POST `/ledger/user-ledgers` | `{ userId, ledgers: string[] }` | replaces ledger access (admin-scoped ledgers) |
| POST `/ledger/ledger/user-ledgers` | `{ userId: int, ledgers: string[] }` | **duplicate** of the above (stricter int check) |
| GET `/ledger/users/:userId/ledgers` | — | `[ { ledger_guid } ]` (duplicate of `GET /users/:id/ledgers`) |
| GET `/orders/user-orders/:userId`, POST `/orders/user-orders`, POST `/orders/bulk-user-orders` | `{ userId, orders[] }` / `{ userIds[], orders[] }` | tenant-checked |
| GET/POST `/voucher-entry/user-vouchers…`, POST `/voucher-entry/bulk-user-vouchers` | see §13 | ⚠️ not tenant-checked |
| GET `/inventory/user-inventory/:userId`, POST `/inventory/user-inventory`, POST `/inventory/bulk-user-inventory` | see §7 | ADMIN |
| POST `/notify-permission-update` | `{ userIds: int[], modules: string[] }` | Emails "access updated" via Brevo (`BREVO_API_KEY` required, else `500 "Brevo API key not configured"`). ⚠️ No ADMIN or tenant check. |

### User ↔ Admin requests
| Endpoint | Status | Auth | Detail |
|---|---|---|---|
| POST `/request-to-admin` | IMPLEMENTED (no Flutter screen) | Bearer | Body `{ message }` (≥ 10 chars) → `{ success:true, message:"Request sent successfully" }`; inserts `user_requests` + web notification `request` for the admin. Errors `400 "Message too short (min 10 chars)"`, `400 "No admin assigned to this user"`, `500`. |
| GET `/admin/requests` | IMPLEMENTED (ADMIN) | Bearer | `[ { id, message, created_at, is_read, user_name, user_email } ]`; `403 "Access denied"` |

---

## 18. Settings (module 17)

**Module status:**
- IMPLEMENTED: profile read/update (§3); mobile notification preferences (§19).
- NEEDS ADAPTER: the Flutter Alerts tab toggles `pay, sync, due, team, wa`, but the backend mobile keys are `create_entry, entry_failed, sync_failed, sync_completed, voucher_sync, party_sync, item_sync, ledger_sync, tally_connection, system_alerts`. A mapping is needed, and `due`, `team`, `wa` have no backend equivalent.
- MISSING:
  - plan details / renewal date (only `plan` name from the ADMIN login);
  - plans & billing / switch plan (license lives in the external Licentic system);
  - refer-a-friend code and referrals.
  - **Look / theme / wallpaper / glass level are local-only** (no backend needed).

### Entry field settings (per user, per active company, per voucher type)
`voucherType` path param, case-insensitive: `SALES | PURCHASE | RECEIPT | PAYMENT | JOURNAL`.

| Endpoint | Status | Body / response |
|---|---|---|
| GET `/entry-field-settings/:voucherType` | IMPLEMENTED (no Flutter UI yet) | 200 `{ success:true, voucherType, fields: { <standard_key>: boolean }, customFields: [ { id, field_key, field_name, field_type, options (jsonb), enabled, created_at, updated_at } ] }`. Standard keys:<br>SALES: due_date, hsn_sac, discount, gst, reference_no, sales_person, bank_payment_details<br>PURCHASE: due_date, hsn_sac, discount, gst, reference_no, bank_payment_details, bill_allocation<br>RECEIPT: reference_no, instrument_cheque_no, deposit_to_account, bill_allocation, narration<br>PAYMENT: reference_no, transaction_utr_cheque_no, bank_account_details, bill_allocation, narration<br>JOURNAL: reference_no, bill_allocation, narration |
| PUT `/entry-field-settings/:voucherType` | IMPLEMENTED | Body `{ fields: { <standard_key>: boolean } }` → `{ success:true, message, voucherType, fields }`. 400 on an unknown key or a non-boolean value. |
| POST `/entry-field-settings/:voucherType/custom` | IMPLEMENTED | Body `{ fieldName (required), fieldType (required), fieldKey?, options?: [] }` → **201** `{ success:true, message, customField }` |
| PATCH `/entry-field-settings/:voucherType/custom/:fieldKey` | IMPLEMENTED | Body `{ enabled: boolean }` → `{ success:true, customField }`; `404 "Custom field not found"` |
| DELETE `/entry-field-settings/:voucherType/custom/:fieldKey` | IMPLEMENTED | → `{ success:true, customField }`; `404` |
| Common errors | | `400 "Invalid voucher type"`, `400 "No active company selected"`, `404 "User not found"`, `500 {success:false, message, error}` |
| Note | Custom-field PATCH/DELETE are not company-scoped (they affect the same `field_key` in every company of that user). |

---

## 19. Notifications (module 18)

**Module status:**
- IMPLEMENTED: mobile notification list, mark one read, clear all, preferences, report file download.
- NEEDS ADAPTER:
  - Flutter "Mark all read" needs one call per id;
  - unread count must be computed client-side;
  - deep link format is `activity?voucher_guid=…&company_guid=…`;
  - title and message are server text, while Flutter's alerts navigate by type.
- MISSING: bulk mark-all-read, unread count, push notifications (FCM/APNs), pagination (fixed 100).

### GET `/api/mobile/notifications`
| Field | Detail |
|---|---|
| Status | **IMPLEMENTED** |
| Auth | Bearer |
| 200 | `{ success: true, notifications: [ { id: int, title: string, message: string, is_read: boolean, created_at: ISO, type: string, file: string or null, meta: object or null, deep_link: string or null } ] }`, newest first, max 100, **filtered to types enabled in the user's config** |
| `type` values | `create_entry, entry_failed, sync_failed, sync_completed, voucher_sync, party_sync, item_sync, ledger_sync, tally_connection, system_alerts` |
| `meta` (entry types) | `{ voucher_guid, company_guid, voucher_type, reference_no, voucher_date, party_name, amount }` |
| Errors | `500 {success:false, message:"Failed to fetch notifications"}` |
| Tables | `mobile_notifications` (created at boot by `ensureMobileSchema`), `mobile_notification_preferences` |

### Other mobile notification endpoints
| Endpoint | Status | Detail |
|---|---|---|
| GET `/api/mobile/notifications/config` | IMPLEMENTED | `{ success:true, config: { create_entry:true, entry_failed:true, sync_failed:true, sync_completed:false, voucher_sync:false, party_sync:true, item_sync:false, ledger_sync:false, tally_connection:true, system_alerts:true } }` (defaults merged with saved values) |
| PUT `/api/mobile/notifications/config` | IMPLEMENTED | Body: any subset of the keys above with boolean values (unknown keys ignored, values coerced with `Boolean`) → `{ success:true, config }` |
| POST `/api/mobile/notifications/:id/read` | IMPLEMENTED | → `{ success:true }` (scoped to the user; unknown id still returns success) |
| DELETE `/api/mobile/notifications/clear-all` | IMPLEMENTED (no Flutter UI) | → `{ success:true }` |
| GET `/api/mobile/notifications/download/:file` | IMPLEMENTED | Downloads `uploads/reports/<file>` (path-traversal safe); `400 {success:false, message:"Invalid file"}`. Note: the monthly-report cron writes **web** notifications, not mobile ones, so mobile `file` values are NOT DETERMINED. |

### Web notifications (`/admin/notifications`; not for Flutter)
| Endpoint | Detail |
|---|---|
| GET `/admin/notifications` | Raw `notifications.*` rows (max 50) filtered by `users.notification_preferences` |
| POST `/admin/notifications/:id/read` | ⚠️ not user-scoped (marks any id) |
| GET `/admin/notifications/download/:file` | ⚠️ **path traversal**: `res.download("uploads/reports/" + file)` with no sanitising |
| DELETE `/admin/notifications/clear-all` | Deletes the user's web notifications |

---

## 20. Other discovered modules (module 19)

| Endpoint | Status | Auth | Detail |
|---|---|---|---|
| GET `/` | Health | **Bearer** (due to the `/` mount, §1.3) | `"Backend working!"` (text) |
| GET `/check-db` | Health | **Bearer** | `{ success:true, time:{ now } }` or `{ success:false, error }` |
| GET `/uploads/*` | Static files | none | `express.static("uploads")`. ⚠️ Monthly report Excel files are publicly downloadable if the file name is known. |
| POST `/agent/handshake` | AGENT ONLY | none | Body `{ license_key, device_fingerprint }` → `{ admin_id, company_guid }` or `{ admin_id, company_guid:null, message }`. Errors `400 "Missing data"`, `401 "Invalid license"`, `403 "Admin not found or invalid"` / `"License disabled"` / `"Device limit exceeded"`. Side effect: **forces `active_company`**. Tables `licenses`, `license_devices`. Note: it returns **no JWT**, but every other agent route needs a Bearer token; how the agent obtains one is NOT DETERMINED (agent not in repo; `queueWorker.js` mentions `SERVICE_TOKEN`). |
| POST `/agent/agent-info` | AGENT ONLY | none | Body `{ tally_serial_no (required), person_name, mobile_number, company_name, description, facing_errors, support_type, tally_ticket_no, tally_company, tally_version, license_edition, tss_valid_till, account_id, site_id, license_admin, tally_gateway }` → `{ message, action:"created" or "updated" }` |

---

## 21. Total endpoint count

| Measure | Count |
|---|---|
| **Distinct route handlers (method + path) in source** | **152** |
| Extra reachable paths from the duplicate mount `/api/users/*` (same 23 handlers as `/users/*`) | +23 → **175 reachable method+path combinations** |
| Static mount | 1 (`GET /uploads/*`) |
| **BROKEN** handlers (fail at runtime as written) | 3: `POST /voucher-entry/bulk-sync`, `POST /invoice-item/sync`, `POST /invoice-item/bulk-sync` |
| Referenced but **NOT FOUND** | `POST /voucher-entry/mark-inactive` (auth-bypass entry only) |
| Dead code (not mounted / never imported) | `routes/queueWorker.js`, `index.js`, `utils/jwt.js` (empty) |
| Handlers without authentication | 13: `POST /auth/register`, `POST /auth/login`, `POST /api/auth/send-otp`, `POST /api/auth/verify-otp`, `GET /ageing`, `POST /ageing/sync`, `GET /ageing/ledger/:ledgerGuid`, `POST /api/reports/profit-loss/sync`, `POST /sync/event`, `POST /sync/trigger`, `GET /sync/active-admin`, `POST /agent/handshake`, `POST /agent/agent-info` (plus the two broken `/invoice-item/*` sync routes, `POST /voucher-entry/bulk-sync`, and the static `/uploads`) |

## 22. Endpoint count by module

| # | Module | Handlers | Flutter-relevant (non-agent/web) |
|---|---|---|---|
| 1 | Authentication | 5 | 4 (login, send-otp, verify-otp, me) |
| 2 | User / Profile | 7 | 2 (GET/PUT `/users/me`) |
| 3 | Company | 9 | 4 (`/company`, `/selected`, `/active`, `/set-active`) |
| 4 | Dashboard | 5 | 3 |
| 5 | Parties / Ledgers | 13 | 6 |
| 6 | Items / Inventory | 10 | 2 |
| 7 | Sales (+ invoices / orders) | 12 | 1 (+ read-only invoices / orders) |
| 8 | Purchase | 0 distinct (shares the Sales create endpoint) | — |
| 9 | Money In | 1 | 1 |
| 10 | Money Out | 1 | 1 |
| 11 | Adjustment / Journal | 1 | 1 |
| 12 | Vouchers | 14 | 2 (`/paged`, `/:voucherGuid`) |
| 13 | Outstanding / Dues | 11 | 1 (`GET /bill`) |
| 14 | Reports | 2 | 1 |
| 15 | Activity / History / Sync | 16 | 2 (`/api/mobile-sync-queue/activity`, `/agent-status/sync-status` counted in Dashboard) |
| 16 | Team / Members / Permissions | 26 | 4 (`GET/POST /users`, `DELETE /users/:id`, `POST /send-invite`) |
| 17 | Settings (entry field settings) | 5 | 0 used today (5 available) |
| 18 | Notifications | 10 | 4 |
| 19 | Other (health, agent) | 4 | 0 |
| | **Total** | **152** | |

## 23. Authentication flow (summary)

```
Flutter Login screen
 ├─ POST /auth/login {username:<email>, password, loginType:"ADMIN"|"USER"}
 │     ← { token, user:{id, username, email, role, adminId, plan?} }
 ├─ save token (secure storage), expiry 24 h (no refresh endpoint)
 ├─ GET /users/me                      ← profile + permissions
 ├─ GET /company/active                ← { company_guid }
 ├─ GET /company/selected              ← [ {company_guid, name} ]
 └─ every request: Authorization: Bearer <token>
       401 {message:"Unauthorized"|"Invalid token"} → clear session → Login
Forgot password: POST /api/auth/send-otp {email} → POST /api/auth/verify-otp {email, otp, newPassword}
Company switch (ADMIN only): POST /company/set-active {company_guid}
Logout: client-side only
```

## 24. Complete endpoint index

Legend: **A** = auth required · **Ad** = ADMIN only · **—** = no auth · Flutter column: ✅ IMPLEMENTED · 🔧 NEEDS ADAPTER / BACKEND CHANGE · 🤖 AGENT ONLY · 🌐 WEB ONLY · ❌ BROKEN

| # | Method | Path | Auth | Module | Flutter |
|---|---|---|---|---|---|
| 1 | POST | /auth/register | — | Auth | 🌐 (⚠️) |
| 2 | POST | /auth/login | — | Auth | 🔧 |
| 3 | GET | /auth/me | A | Auth | ✅ |
| 4 | POST | /api/auth/send-otp | — | Auth | 🔧 |
| 5 | POST | /api/auth/verify-otp | — | Auth | ✅ |
| 6 | GET | /users/me | A | Profile | ✅ |
| 7 | PUT | /users/me | A | Profile | 🔧 (⚠️ role) |
| 8 | GET | /users/me/notifications | A | Profile/Settings | 🌐 |
| 9 | PUT | /users/me/notifications | A | Profile/Settings | 🌐 |
| 10 | POST | /users/me/avatar | A | Profile | 🔧 |
| 11 | PUT | /users/me/monthly-report-schedule | A | Profile/Settings | ✅ (no UI) |
| 12 | GET | /users/me/monthly-report-schedule | A | Profile/Settings | ✅ (no UI) |
| 13 | GET | /users | Ad | Team | ✅ |
| 14 | POST | /users | Ad | Team | 🔧 |
| 15 | PUT | /users/:id/voucher-permissions | Ad | Team | 🌐 |
| 16 | PUT | /users/:id/ledger-permissions | Ad | Team | 🌐 |
| 17 | PUT | /users/:id/orders-permissions | Ad | Team | 🌐 |
| 18 | PUT | /users/:id/inventory-permissions | Ad | Team | 🌐 |
| 19 | PUT | /users/:id/dashboard-permissions | Ad | Team | 🌐 |
| 20 | DELETE | /users/:id | Ad | Team | ✅ (⚠️ tenant) |
| 21 | GET | /users/:id/ledgers | Ad | Team | 🌐 |
| 22 | POST | /users/bulk-ledger-assign | Ad | Team | 🌐 |
| 23 | PUT | /users/bulk-voucher-permissions | Ad | Team | 🌐 |
| 24 | PUT | /users/bulk-orders-permissions | Ad | Team | 🌐 |
| 25 | PUT | /users/bulk-ledger-permissions | Ad | Team | 🌐 |
| 26 | GET | /users/:id/invite-info | Ad | Team | 🌐 (⚠️ password) |
| 27 | PUT | /users/bulk-inventory-permissions | Ad | Team | 🌐 |
| 28 | PUT | /users/bulk-dashboard-permissions | Ad | Team | 🌐 |
| — | * | /api/users/* | same as #6–#28 | duplicate mount | — |
| 29 | POST | /company/create | A | Company | 🤖 |
| 30 | POST | /company/select | Ad | Company | 🌐 |
| 31 | GET | /company/selected | A | Company | ✅ |
| 32 | GET | /company | A | Company | ✅ (⚠️ side effect) |
| 33 | GET | /company/active | A | Company | ✅ |
| 34 | POST | /company/set-active | Ad | Company | 🔧 |
| 35 | GET | /company/by-guid/:guid | A | Company | ✅ |
| 36 | GET | /company/sync-start/:guid | A | Company | 🌐 |
| 37 | PUT | /company/sync-start/:guid | Ad | Company | 🌐 |
| 38 | POST | /ledger/sync | A | Parties | 🤖 |
| 39 | GET | /ledger | A | Parties | 🔧 |
| 40 | POST | /ledger/user-ledgers | Ad | Team | 🌐 |
| 41 | GET | /ledger/users/:userId/ledgers | Ad | Team | 🌐 |
| 42 | POST | /ledger/ledger/user-ledgers | Ad | Team | 🌐 (duplicate) |
| 43 | POST | /ledger/cleanup/ledger | A | Parties | 🤖 (⚠️) |
| 44 | GET | /ledger/deleted/history | A | Parties | 🌐 |
| 45 | POST | /ledger/deleted/restore/:id | A | Parties | 🌐 |
| 46 | GET | /ledger/:ledgerGuid | A | Parties | ✅ |
| 47 | POST | /voucher-entry/reset-active | A | Vouchers | 🤖 |
| 48 | POST | /voucher-entry/sync | A | Vouchers | 🤖 |
| 49 | GET | /voucher-entry | A | Vouchers | 🔧 (ledger-mode bug) |
| 50 | GET | /voucher-entry/paged | A | Vouchers | ✅ / 🔧 date range |
| 51 | DELETE | /voucher-entry/:voucherGuid | A | Vouchers | 🌐 |
| 52 | GET | /voucher-entry/:voucherGuid | A | Vouchers | 🔧 |
| 53 | GET | /voucher-entry/user-vouchers/:userId | A | Team | 🌐 (⚠️) |
| 54 | POST | /voucher-entry/user-vouchers | A | Team | 🌐 (⚠️) |
| 55 | GET | /voucher-entry/ledger/:ledgerGuid | A | Parties | ✅ |
| 56 | POST | /voucher-entry/bulk-user-vouchers | A | Team | 🌐 (⚠️) |
| 57 | POST | /voucher-entry/cleanup/voucher | A | Vouchers | 🤖 |
| 58 | POST | /voucher-entry/deleted/restore-voucher/:id | A | Vouchers | 🌐 |
| 59 | POST | /voucher-entry/bulk-sync | — | Vouchers | ❌ |
| 60 | GET | /orders | A | Sales | ✅ (no screen) |
| 61 | GET | /orders/user-orders/:userId | A | Team | 🌐 |
| 62 | POST | /orders/user-orders | A | Team | 🌐 |
| 63 | POST | /orders/bulk-user-orders | A | Team | 🌐 |
| 64 | POST | /orders/sync | A | Sales | 🤖 |
| 65 | POST | /orders/cleanup/order | A | Sales | 🤖 |
| 66 | POST | /bill/sync | A | Dues | 🤖 |
| 67 | POST | /bill/push-to-tally | A | Dues | 🌐 |
| 68 | GET | /bill | A | Dues | 🔧 |
| 69 | GET | /bill/ledger/:ledgerGuid | A | Parties/Dues | ✅ |
| 70 | POST | /bill/ensure-voucher-bill-map | A | Dues | 🌐 (maintenance) |
| 71 | POST | /bill/mark-processing | A | Dues | 🤖 |
| 72 | POST | /bill/mark-success | A | Dues | 🤖 |
| 73 | POST | /bill/mark-failed | A | Dues | 🤖 |
| 74 | GET | /bill/dashboard-summary | A | Dashboard | ✅ (overlap) |
| 75 | POST | /bill/mark-all-cleared | A | Dues | 🤖 |
| 76 | POST | /bill/reconcile | A | Dues | 🤖 |
| 77 | POST | /ageing/sync | — | Dues | 🤖 (⚠️) |
| 78 | GET | /ageing | — | Dues | 🔧 (⚠️ all tenants) |
| 79 | GET | /ageing/ledger/:ledgerGuid | — | Parties/Dues | 🔧 (⚠️) |
| 80 | POST | /sales-order/sync | A | Sales | 🤖 |
| 81 | POST | /sales-order-item/sync | A | Sales | 🤖 |
| 82 | POST | /stock-item/sync | A | Items | 🤖 |
| 83 | POST | /stock-summary/sync | A | Items | 🤖 |
| 84 | POST | /invoice/sync | A | Sales | 🤖 |
| 85 | GET | /invoice | A | Sales | ✅ (no screen) |
| 86 | GET | /invoice/ledger/:ledgerGuid | A | Parties | ✅ |
| 87 | POST | /invoice/bulk-sync | A | Sales | 🤖 |
| 88 | POST | /invoice-item/sync | — | Sales | ❌ |
| 89 | GET | /invoice-item/:invoice_guid | A | Sales | ✅ |
| 90 | POST | /invoice-item/bulk-sync | — | Sales | ❌ |
| 91 | POST | /sync/event | — | Activity/Sync | 🤖 (⚠️) |
| 92 | POST | /sync/trigger | — | Activity/Sync | 🔧 (no effect) |
| 93 | GET | /sync/active-admin | — | Activity/Sync | 🤖 (⚠️) |
| 94 | GET | /inventory | A + inv-perm | Items | ✅ |
| 95 | GET | /inventory/user-inventory/:userId | Ad | Team | 🌐 |
| 96 | POST | /inventory/user-inventory | Ad | Team | 🌐 |
| 97 | POST | /inventory/bulk-user-inventory | Ad | Team | 🌐 |
| 98 | POST | /inventory/full-sync | Ad | Items | 🤖 |
| 99 | POST | /inventory/inventory-movement/sync | Ad | Items | 🤖 |
| 100 | POST | /inventory/cleanup | Ad | Items | 🤖 |
| 101 | GET | /inventory/mobile | A + inv-perm | Items | ✅ (⚠️ USER filter) |
| 102 | GET | /dashboard/summary | A | Dashboard | ✅ |
| 103 | GET | /dashboard/income-expense | A | Dashboard/Reports | 🔧 |
| 104 | GET | /dashboard/bills | A | Dashboard/Dues | 🔧 |
| 105 | GET | /api/reports/monthly-summary | A | Reports | ✅ (⚠️ inflated) |
| 106 | POST | /api/reports/profit-loss/sync | — | Reports | 🤖 (⚠️) |
| 107 | POST | /send-invite | A | Team | 🔧 (⚠️) |
| 108 | POST | /agent/handshake | — | Other | 🤖 |
| 109 | POST | /agent/agent-info | — | Other | 🤖 |
| 110 | POST | /agent-status/sync-status | A | Activity/Sync | 🤖 |
| 111 | GET | /agent-status/sync-status | A | Dashboard | ✅ |
| 112 | POST | /agent-status/sync-started | A | Activity/Sync | 🤖 |
| 113 | POST | /voucher-command/create | A | Vouchers | 🌐 |
| 114 | POST | /voucher-command/alter | A | Vouchers | 🌐 |
| 115 | GET | /sync-queue/pending | A | Activity/Sync | 🤖 |
| 116 | POST | /sync-queue/:id/processing | A | Activity/Sync | 🤖 |
| 117 | POST | /sync-queue/:id/success | A | Activity/Sync | 🤖 |
| 118 | POST | /sync-queue/:id/failed | A | Activity/Sync | 🤖 |
| 119 | GET | /sync-queue/pending-bills | A | Activity/Sync | 🤖 |
| 120 | GET | /sync-queue/pending-ledgers | A | Activity/Sync | 🤖 |
| 121 | GET | /admin/notifications | A | Notifications | 🌐 |
| 122 | POST | /admin/notifications/:id/read | A | Notifications | 🌐 |
| 123 | GET | /admin/notifications/download/:file | A | Notifications | 🌐 (⚠️ traversal) |
| 124 | DELETE | /admin/notifications/clear-all | A | Notifications | 🌐 |
| 125 | POST | /notify-permission-update | A | Team | 🌐 (⚠️) |
| 126 | POST | /request-to-admin | A | Team | ✅ (no screen) |
| 127 | GET | /admin/requests | A (ADMIN check) | Team | ✅ (no screen) |
| 128 | POST | /api/mobile-voucher-command/create | A | Sales / Purchase | 🔧 |
| 129 | POST | /api/mobile-voucher-command/receipt/create | A | Money In | ✅ |
| 130 | POST | /api/mobile-voucher-command/payment/create | A | Money Out | ✅ |
| 131 | POST | /api/mobile-voucher-command/journal/create | A | Journal | ✅ |
| 132 | GET | /api/mobile-sync-queue/pending | A | Activity/Sync | 🤖 |
| 133 | GET | /api/mobile-sync-queue/activity | A | Activity | 🔧 |
| 134 | POST | /api/mobile-sync-queue/:id/processing | A | Activity/Sync | 🤖 |
| 135 | POST | /api/mobile-sync-queue/:id/success | A | Activity/Sync | 🤖 |
| 136 | POST | /api/mobile-sync-queue/:id/failed | A | Activity/Sync | 🤖 |
| 137 | GET | /api/mobile/notifications | A | Notifications | ✅ |
| 138 | GET | /api/mobile/notifications/config | A | Notifications/Settings | 🔧 (key mapping) |
| 139 | PUT | /api/mobile/notifications/config | A | Notifications/Settings | 🔧 |
| 140 | POST | /api/mobile/notifications/:id/read | A | Notifications | ✅ |
| 141 | DELETE | /api/mobile/notifications/clear-all | A | Notifications | ✅ |
| 142 | GET | /api/mobile/notifications/download/:file | A | Notifications | ✅ |
| 143 | POST | /ledger-items/sync | A | Parties | 🤖 |
| 144 | GET | /ledger-items/ledger/:ledgerGuid | A | Parties | ✅ |
| 145 | GET | /ledger-items/item/:itemName/parties | A | Items/Parties | ✅ |
| 146 | GET | /entry-field-settings/:voucherType | A | Settings | ✅ (no UI) |
| 147 | PUT | /entry-field-settings/:voucherType | A | Settings | ✅ (no UI) |
| 148 | POST | /entry-field-settings/:voucherType/custom | A | Settings | ✅ (no UI) |
| 149 | PATCH | /entry-field-settings/:voucherType/custom/:fieldKey | A | Settings | ✅ (no UI) |
| 150 | DELETE | /entry-field-settings/:voucherType/custom/:fieldKey | A | Settings | ✅ (no UI) |
| 151 | GET | / | A (via `/` mount) | Other | health |
| 152 | GET | /check-db | A (via `/` mount) | Other | health |
| — | GET | /uploads/* | — | Other | static |

---

## 25. Missing endpoints required by the current Flutter app

| # | Flutter feature (screen) | What is missing |
|---|---|---|
| 1 | Session (all) | Token refresh / renew (JWT expires after 24 h; no refresh) |
| 2 | Menu → Change password | Change password while logged in (only the OTP reset flow exists) |
| 3 | Entry flow → "+ Add new party"; Party → "Add party" | Create party / ledger (and return its guid) |
| 4 | Item picker → "Add new item" | Create stock item (name, unit, rate, HSN, GST, category) |
| 5 | Entry flow → bill / receipt / payment / journal number | Next voucher number per type |
| 6 | Activity → "Try again"; Activity detail → "Try sending again" | Retry / re-queue a failed `mobile_sync_queue` row |
| 7 | Activity → Sync now; Companies → Refresh; pull-to-refresh | Trigger agent sync (`/sync/trigger` has no effect and no auth) |
| 8 | Alerts → "Mark all read", unread badge | Bulk mark-all-read + unread count |
| 9 | Team → member → "Turn off / on access" | Disable / enable user (only DELETE exists) |
| 10 | Team → Invite by email (pending), Send invite again, Cancel invite | Invitation lifecycle (pending state, resend, cancel, accept) |
| 11 | Dues / Bill / Party → "Remind", "Send reminders", Auto reminders toggle, Payment alerts | WhatsApp / SMS reminder sending + reminder settings |
| 12 | Reports → Expenses | Expense ledgers report (direct / indirect) |
| 13 | Reports → Top customers / Quiet customers / Items not moving | Server-side reports (currently client-derivable only, see §29) |
| 14 | Settings → Plan, Plans & billing, "Switch to …" | Plan details, renewal date, plan change request |
| 15 | Refer a friend | Referral code + referrals list |
| 16 | Home → 8 money cards | One dashboard endpoint (money in/out, sales/purchase this month, cash in hand, bank balance) |
| 17 | Vouchers → "Last 7 days" / "Today" | Date-range filter (`from` / `to`) on `/voucher-entry/paged` |
| 18 | Entry detail | Voucher detail with party, amount and items in one response |
| 19 | Vouchers hub → "N this month" per type | Count per voucher type (one request per type today) |
| 20 | Party detail → GSTIN, address, contact, phone, credit days, city | Extended party fields (not stored in `ledgers`) |
| 21 | Profile → Mobile; Team → member role / city / mobile | User phone, role title, location |
| 22 | Activity | Pagination + per-user / admin scoping of the activity feed |
| 23 | Push alerts | Device token registration (FCM / APNs). Notifications are pull-only. |

---

## 26. Endpoints requiring adapters / backend changes

| Endpoint | Gap for Flutter | Suggested handling |
|---|---|---|
| POST /auth/login | `loginType` required | Add an ADMIN/USER toggle, or try `USER` then `ADMIN` on 401/403 (backend change preferred: auto-detect role) |
| POST /api/auth/send-otp + verify-otp | OTP flow vs "link" UI | Add OTP + new password steps to the Forgot screen |
| PUT /users/me | Writes `role` from body | Always send the current role; **backend must stop accepting `role`** |
| POST /company/set-active | ADMIN only, shared per admin | Hide or disable the company switch for USER |
| GET /ledger | No customer/supplier flag, city, or signed balance | Map `parent_group` / `type` to customer/supplier; compute Dr/Cr from `closing_balance`; parse numeric strings |
| GET /inventory/mobile | No stock status; ignores USER item permissions | Derive ok/low/finished; backend should filter by `user_inventory_permissions` |
| POST /api/mobile-voucher-command/create | Item/summary/payment schema undefined; Purchase Dr/Cr inverted; no tax ledgers; dedupe ineffective | Agree a payload contract with the agent; fix Purchase sides; client-side double-submit guard |
| POST …/receipt/create, …/payment/create | Different `payment` field names | Two mappers |
| POST …/journal/create | No "main account" field | Put it in `narration`, or drop it |
| GET /voucher-entry/paged | No date range; includes inactive vouchers; Tally type names | Client filter for week/today; map types; filter `is_active` |
| GET /voucher-entry/:voucherGuid | Only ledger lines | Merge with the list row (party, amount, items) |
| GET /voucher-entry?ledgerGuid= | Returns all company entries (bug) | Use `/voucher-entry/ledger/:ledgerGuid` |
| GET /bill | All companies; no status text | Filter `company_guid == active`; compute late / soon / later from `due_date`; ageing client-side |
| GET /dashboard/income-expense | Monthly, sales/purchase only | Pick the current month; receipts/payments via `/paged` meta `totalAmount` |
| GET /dashboard/bills | No `bill_type` / `bill_name` | Use `GET /bill` |
| GET /ageing, GET /ageing/ledger/:guid | No auth / tenant scope | Do not use; compute from `GET /bill` (backend must secure it) |
| GET /api/reports/monthly-summary | Double-counted amounts | Backend should sum `vouchers.net_amount`; until then treat as indicative only |
| GET /api/mobile-sync-queue/activity | Not tenant-scoped; payload keys vary by type; no pagination | Map status; extract amount/party per type; backend should scope by `admin_id` |
| GET/PUT /api/mobile/notifications/config | Keys differ from the Flutter Alerts toggles | Map: pay → `create_entry`?, sync → `sync_completed` / `voucher_sync`, due / team / wa → no equivalent (NOT DETERMINED) |
| POST /api/mobile/notifications/:id/read | No bulk | Loop for "Mark all read" |
| POST /users | Needs email + password; Flutter collects name + mobile | Change the Add person form, or backend change |
| POST /send-invite | Emails a plain-text password for an existing user | Create the user first (`POST /users`), then call; backend should send a set-password link instead |
| DELETE /users/:id | No tenant check | Only call with ids from `GET /users`; backend must scope |
| POST /users/me/avatar | Stores the wrong URL | Backend should save the Cloudinary URL |
| GET /agent-status/sync-status | No computer name | Show the time only |

---

## 27. Duplicate / overlapping endpoints

| Overlap | Endpoints |
|---|---|
| Entire router mounted twice | `/users/*` and `/api/users/*` |
| Router mounted twice (harmless) | `/inventory` (×2), `/stock-summary` (×2) |
| Profile | `GET /auth/me` vs `GET /users/me` (different fields and casing) |
| Dashboard totals | `GET /dashboard/summary` vs `GET /bill/dashboard-summary` |
| Outstanding lists | `GET /bill` vs `GET /dashboard/bills` vs `GET /bill/ledger/:ledgerGuid` |
| Voucher lists | `GET /voucher-entry` vs `GET /voucher-entry/paged` |
| Ledger vouchers | `GET /voucher-entry?ledgerGuid=` (buggy) vs `GET /voucher-entry/ledger/:ledgerGuid` |
| Ledger permission assignment | `POST /ledger/user-ledgers` vs `POST /ledger/ledger/user-ledgers` vs `POST /users/bulk-ledger-assign` |
| Ledger permission read | `GET /users/:id/ledgers` vs `GET /ledger/users/:userId/ledgers` |
| Per-user vs bulk permission writes | `PUT /users/:id/*-permissions` vs `PUT /users/bulk-*-permissions` |
| Notification systems | Web `/admin/notifications` (`notifications` table) vs mobile `/api/mobile/notifications` (`mobile_notifications` table); prefs `/users/me/notifications` vs `/api/mobile/notifications/config` |
| Voucher command queues | Web `/voucher-command/*` → `sync_queue` vs mobile `/api/mobile-voucher-command/*` → `mobile_sync_queue` |
| Agent queue polling | `/sync-queue/*` vs `/api/mobile-sync-queue/*` |
| Item sync | `/stock-item/sync` vs `/inventory/full-sync` vs `/stock-summary/sync` (different conflict keys) |
| Orders | `/sales-order/sync` (`sales_orders`) vs `/orders/sync` (`orders`) |
| Invoice sync | `/invoice/sync` vs `/invoice/bulk-sync`; `/invoice-item/sync` vs `/invoice-item/bulk-sync` (both broken) |
| Bill settlement | `/bill/mark-all-cleared` vs `/bill/reconcile` |
| Company lists | `GET /company` vs `GET /company/selected` |
| Emails to users | `/send-invite` vs `/notify-permission-update` |

---

## 28. Important backend integration issues

### 28.1 Critical security issues (fix before production / mobile release)
1. **Hard-coded JWT secret.** `routes/auth.js` sets `process.env.JWT_SECRET = "tallyconnect-local-test-secret-2026"`, overriding `.env`. Anyone who reads the source can forge tokens.
2. **Plain-text passwords** stored and compared (bcrypt commented out). They are also emailed (`/send-invite`) and returned by `GET /users/:id/invite-info`.
3. **Privilege escalation.** `PUT /users/me` writes `role` from the request body.
4. **Unauthenticated ADMIN creation.** `POST /auth/register` with `isAdmin:true`.
5. **Cross-tenant access.**
   - Data reads / writes: `GET /company` claims unowned companies; `GET /ageing` and `GET /ageing/ledger/:guid` (no auth); `GET /api/mobile-sync-queue/activity` (company-guid only); `GET /voucher-entry/:voucherGuid` (no USER check).
   - Admin user management: `DELETE /users/:id`; `PUT /users/:id/*-permissions`; `/voucher-entry/user-vouchers*`; `/send-invite`; `/notify-permission-update`.
   - Queue status: `/sync-queue/:id/*` and `/api/mobile-sync-queue/:id/*` accept any id.
6. **Path traversal** in `GET /admin/notifications/download/:file`.
7. **Unauthenticated writes.** `/sync/event`, `/sync/trigger`, `/ageing/sync`, `/api/reports/profit-loss/sync`; `/sync/active-admin` leaks `admin_id`.
8. **Default DB credentials** in `db.js` (`postgres:crm@123@localhost:5433/Tally12`).
9. `POST /api/auth/send-otp` reveals whether an email is registered (404) and has no rate limit. OTP verification has no attempt limit.

### 28.2 Correctness bugs affecting Flutter data
1. **Purchase Dr/Cr inverted** in `/api/mobile-voucher-command/create`; no tax ledgers; no balance check.
2. **Duplicate detection never works** in all mobile and web create commands (the hash includes a random GUID and a time-based reference).
3. **`/api/reports/monthly-summary` double counts** (sums every voucher line).
4. **`GET /voucher-entry?ledgerGuid=`** returns every entry of the company.
5. **`GET /inventory/mobile`** ignores USER item permissions.
6. **`bills.bill_date`** is never written by `/bill/sync`, so it is null in `/bill/ledger/:guid`.
7. **Soft-deleted vouchers** are still returned by `/voucher-entry/paged`.
8. Broken handlers: `/voucher-entry/bulk-sync`, `/invoice-item/sync`, `/invoice-item/bulk-sync`.
9. `POST /auth/login` with an unexpected `loginType` never responds (the request hangs).
10. `POST /users/me/avatar` saves a local path for a Cloudinary upload.
11. `/voucher-command/alter` likely conflicts with the `sync_queue` unique key.
12. `/ledger` `date` / `voucher_type` / `reference_no` columns are independent `MAX()` values.

### 28.3 Inconsistent request / response formats
- **Envelopes:** `{success, data}` (ledger, company, vouchers, bills, invoices, orders); `{success, items}` (`/inventory/mobile`); `{success, notifications}`; `{success, config}`; raw arrays (dashboard, ledger sub-resources, reports, activity, sync-queue); raw objects (`/users/me`, `/dashboard/summary`).
- **Error keys:** `message` vs `error` vs `{success:false}` with no message; some handlers return **200 with `success:false`** (`/ageing`, `/check-db`, `/agent-status/sync-status` POST) or `success:true, skipped:true` on failure (agent sync routes).
- **Casing:** snake_case DB fields plus camelCase duplicates (`/users/me`, `GET /users`); `adminId` (JWT, login) vs `admin_id` (agent handshake).
- **Numbers:** most money and count fields are **strings** (pg NUMERIC / COUNT). Only `/inventory/mobile`, `/api/reports/monthly-summary`, `/ageing/ledger`, voucher detail `ledger_entries.amount` and `meta.totalAmount` are real numbers.
- **IDs:** user ids are integers; company, ledger, voucher and item ids are GUID strings; queue `command_id` is an integer.
- **Dates:** `voucher_date` and others serialise as ISO timestamps; the inventory movement agent sends `YYYYMMDD`; sync-start uses `YYYY-MM-01`; the monthly report time is `HH:mm` UTC; the input format for mobile `voucher_date` is NOT DETERMINED (passed to the agent).
- **Voucher type casing:** `"Sales"` (commands), `"SALES"` (entry-field-settings), `ILIKE` matching (dashboard / reports).
- **Receipt vs Payment** payment-object field names differ (§10, §11).

### 28.4 Authentication inconsistencies
- The `/` mount makes `GET /`, `/check-db` and every later router require auth, and turns unknown paths into 401 instead of 404.
- The server.js bypass lists (`/sync`, `/mark-inactive`, `/bulk-sync`) disagree with the per-route `requireAuth`. `/mark-inactive` doesn't exist. `/bulk-sync` routes are open.
- Agent routes require a Bearer JWT, but `/agent/handshake` (license based) issues none. How the agent authenticates is **NOT DETERMINED**.
- The ADMIN role is enforced inconsistently: some routes use `requireAdmin`, some check `role` inline, and many admin-style routes (`/voucher-entry/user-vouchers`, `/send-invite`, `/notify-permission-update`, `/ledger/cleanup/ledger`, `/voucher-entry/reset-active`, `/bill/mark-all-cleared`) check nothing.
- The active company is per admin, so a USER cannot choose their own company and an admin's switch changes it for everyone.

### 28.5 Missing fields required by existing Flutter functionality
- **Party:** city, address, GSTIN, contact person, phone (USER role), credit days, customer/supplier flag.
- **Item:** stock status (low / finished), minimum stock, category.
- **Voucher (list):** "synced" status, kind mapping.
- **Voucher (detail):** party, net amount, items, due date, payment mode / amount received.
- **Bill:** bill date, party city, days late / status text.
- **Activity:** amount and party as top-level fields (inside `payload` only).
- **User / member:** mobile number, role title, city, status (active / pending / off).
- **Plan:** renewal date, price, features.
- **Dashboard:** money-in / money-out this month, cash in hand, bank balance (as direct values).
- **Company:** "synced at" per company (needs one agent-status call per company).

### 28.6 Behaviour that is unclear from the source
- Agent payload contract for mobile vouchers (`items[]`, `summary`, `payment`, `new_party`); the agent is not in this repo.
- Real DB schema (types, unique indexes, nullable columns), e.g. `bills.amount` vs `pending_amount`, the `sync_queue` columns used by `/sync/event`.
- What consumes `global.FORCE_SYNC` (`/sync/trigger`).
- Which file names appear in mobile notification `file` (`/download/:file`).
- How the agent obtains its JWT (`SERVICE_TOKEN`?).
- The `monthly_report_data(adminId)` DB function definition.

---

## 29. Recommended Flutter repository mapping

Proposed async methods for the future `TallyRepository` (the current interface in `lib/data/repositories/tally_repository.dart` is synchronous and mock-based). Request and response models are named for the Dart classes to create.

| Flutter feature | Repository method | Backend endpoint | HTTP | Request model | Response model |
|---|---|---|---|---|---|
| Login | `login(email, password, loginType)` | /auth/login | POST | `LoginRequest{username,password,loginType}` | `LoginResponse{token, AuthUser{id,username,email,role,adminId,plan?}}` |
| Forgot password (send) | `sendResetOtp(email)` | /api/auth/send-otp | POST | `{email}` | `MessageResponse` |
| Forgot password (verify) | `resetPassword(email, otp, newPassword)` | /api/auth/verify-otp | POST | `{email,otp,newPassword}` | `MessageResponse` |
| Profile | `getProfile()` | /users/me | GET | — | `UserProfile` (+ `Permissions`) |
| Edit profile | `updateProfile(p)` | /users/me | PUT | `{username,email,company,role(current)}` | `SuccessResponse` |
| Company list | `companies()` | /company/selected | GET | — | `List<Company{companyGuid,name,startingFrom}>` |
| Active company | `activeCompany()` | /company/active | GET | — | `String? companyGuid` |
| Switch company (ADMIN) | `setActiveCompany(guid)` | /company/set-active | POST | `{company_guid}` | `SuccessResponse` |
| Tally status line | `syncStatus(companyGuid)` | /agent-status/sync-status | GET | `?company_guid` | `SyncStatus{lastSyncAt,syncInProgress}` |
| Home To get / To give | `outstandingTotals(companyGuid)` | /dashboard/summary | GET | `?company_guid` | `OutstandingTotals{receivables,payables,pendingBills,clearedBills}` (parse strings) |
| Home money in/out/sales/purchase this month | `monthTotal(type, year, month)` | /voucher-entry/paged | GET | `?type&year&month&limit=1` | `VoucherPage.meta.totalAmount` (adapter) |
| Home cash / bank balance | `cashAndBank()` | /ledger | GET | — | adapter: sum `closing_balance` by `parent_group` (Cash-in-Hand / Bank Accounts) |
| Party list | `parties()` | /ledger | GET | — | `List<Ledger>` → `Party` adapter |
| Party detail | `party(guid)` | /ledger/:ledgerGuid | GET | — | `Ledger` |
| Party entries | `partyVouchers(guid)` | /voucher-entry/ledger/:ledgerGuid | GET | — | `List<LedgerVoucher{id,date,type,ref,debit,credit,items}>` |
| Party items | `partyItems(guid)` | /ledger-items/ledger/:ledgerGuid | GET | — | `List<PartyItem{itemName,totalQty,totalAmount,firstDate,lastDate}>` |
| Party bills | `partyBills(guid)` | /bill/ledger/:ledgerGuid | GET | — | `List<Bill>` |
| Items / item picker | `items()` | /inventory/mobile | GET | — | `List<StockItem{itemGuid,name,group,unit,closingQty,closingValue,rate,hsnCode,gstRate…}>` |
| Stock summary report | `stockSummary()` | /inventory | GET | — | `List<StockRow{id,name,opening,inward,outward,closing,rate,value}>` |
| Item buyers / sellers | `itemParties(name, type)` | /ledger-items/item/:itemName/parties | GET | `?type` | `List<ItemParty>` |
| New Sale / Purchase | `createSaleOrPurchase(entry)` | /api/mobile-voucher-command/create | POST | `MobileVoucherRequest{voucher_type,voucher_date,voucher_no,party_name,new_party?,due_date,narration,items[],summary{},payment{}}` | `QueueResult{commandId,voucherGuid,status,duplicate?}` |
| New Money In | `createReceipt(entry)` | /api/mobile-voucher-command/receipt/create | POST | `ReceiptRequest{voucher_date,voucher_no,party_name,amount_received,reference_no,narration,payment{payment_mode,bank_name,account_number,cheque_number,cheque_date,upi_ref,other_ref,deposit_account}}` | `QueueResult` |
| New Money Out | `createPayment(entry)` | /api/mobile-voucher-command/payment/create | POST | `PaymentRequest{voucher_date,voucher_no,party_name,amount_paid,reference_no,narration,payment{payment_mode,bank_account,transaction_instrument_no,transaction_date,remarks}}` | `QueueResult` |
| New Adjustment | `createJournal(entry)` | /api/mobile-voucher-command/journal/create | POST | `JournalRequest{voucher_date,voucher_no,reference_no,narration,ledger_entries[{ledger_name,amount,is_debit}]}` | `QueueResult` / `JournalImbalance{totalDebit,totalCredit,difference}` on 400 |
| Ledger / account pickers | `ledgers()` | /ledger | GET | — | `List<Ledger>` (filter by group client-side) |
| Vouchers list | `vouchers(page, filters)` | /voucher-entry/paged | GET | `?page&limit&type&search&year&month&sort_by` | `VoucherPage{data:List<VoucherRow>, meta{total,page,limit,hasMore,totalAmount,types,years}}` |
| Entry detail | `voucher(guid)` | /voucher-entry/:voucherGuid | GET | — | `VoucherDetail{guid,date,type,ref,ledgerEntries[]}` (+ merge with list row) |
| Dues list | `bills()` | /bill | GET | — | `List<Bill{billName,ledgerName,ledgerGuid,billAmount,pendingAmount,dueDate,billType,status}>` (filter by active company) |
| Reports: monthly | `monthlySummary(companyGuid, year)` | /api/reports/monthly-summary | GET | `?company_guid&year` | `List<MonthSummary{month,turnover,expense,profit}>` |
| Reports: sales/purchase list, day book | `vouchers(...)` | /voucher-entry/paged | GET | type filter | `VoucherPage` |
| Reports: top customers | `topCustomers()` | /bill | GET | — | adapter (group RECEIVABLE by party) |
| Activity | `activity(companyGuid)` | /api/mobile-sync-queue/activity | GET | `?company_guid` | `List<QueueItem{id,entityType,action,status,payload,error,createdAt,processedAt}>` |
| Alerts list | `notifications()` | /api/mobile/notifications | GET | — | `List<MobileNotification{id,title,message,isRead,createdAt,type,file,meta,deepLink}>` |
| Mark alert read | `markRead(id)` | /api/mobile/notifications/:id/read | POST | — | `SuccessResponse` |
| Clear alerts | `clearAlerts()` | /api/mobile/notifications/clear-all | DELETE | — | `SuccessResponse` |
| Alert settings | `alertConfig()` / `saveAlertConfig(c)` | /api/mobile/notifications/config | GET / PUT | `Map<String,bool>` | `NotificationConfig` |
| Report file | `downloadReport(file)` | /api/mobile/notifications/download/:file | GET | — | bytes |
| Team list (ADMIN) | `team()` | /users | GET | — | `List<TeamUser>` |
| Add person (ADMIN) | `createUser(email, password)` | /users | POST | `{email,password}` | `{user:{id,username,email}}` |
| Remove member | `deleteUser(id)` | /users/:id | DELETE | — | `SuccessResponse` |
| Invite by email | `sendInvite(email, username)` | /send-invite | POST | `{email,username}` | `SuccessResponse` |
| Entry field settings (future) | `entryFields(type)` / `saveEntryFields(type, f)` | /entry-field-settings/:voucherType | GET / PUT | `{fields:{}}` | `EntryFieldSettings{fields,customFields}` |
| Request to admin (future) | `requestToAdmin(msg)` | /request-to-admin | POST | `{message}` | `SuccessResponse` |
| Logout | `logout()` | — (client only) | — | — | — |
| Workspaces, Home layout, Look/themes, pins, hidden cards, drafts, search | local only | — | — | — | (no backend; keep SharedPreferences) |
| Plans / billing, Refer, WhatsApp reminders, create party, create item, retry entry, mark-all-read, disable member, next number | **MISSING** (§25) | — | — | — | — |

*End of reference.*
