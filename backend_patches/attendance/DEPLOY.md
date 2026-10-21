# Sales team check-in / check-out — deploy

1. Run once on the database: `sql/2026-10-19_attendance.sql`. It only creates two new tables (`attendance_access`, `attendance_sessions`) and their indexes; nothing existing changes.
2. Backend files (already copied into `tally-backend/`):
   - `utils/attendanceCore.js`, `utils/attendanceRouter.js`
   - `routes/attendance.js`
   - `cron/attendanceCron.js` (closes forgotten check-outs at 23:59 IST; runs every 10 minutes)
   - `server.js`: `import attendanceRoutes from "./routes/attendance.js";`, `import "./cron/attendanceCron.js";` and `app.use(attendanceRoutes);` next to the other `/api/*` routers.
3. Deploy the backend. No Agent change.
4. In the app (admin): Sales Team → a person → Configure User → turn on **Sales team check-in**.

Tests: `node --test test/attendance.test.mjs` (fake database; no network).

## Leave management

1. Run once on the database: `sql/2026-10-21_leave.sql`. It only creates four new tables (`leave_settings`, `leave_types`, `leave_holidays`, `leave_requests`) and their indexes; nothing existing changes.
2. Backend files (copy into `tally-backend/`):
   - `utils/leaveCore.js`, `utils/leaveRouter.js` (they use `utils/attendanceCore.js`)
   - `routes/leave.js`
   - `server.js`: `import leaveRoutes from "./routes/leave.js";` and `app.use(leaveRoutes);` next to `attendanceRoutes`.
3. Deploy the backend. No Agent change.
4. In the app (admin): Leave settings → turn leave on, add leave types (or "Add default types"), holidays, weekly off, leave year.

Tests: `node --test test/leave.test.mjs` (fake database; no network).
