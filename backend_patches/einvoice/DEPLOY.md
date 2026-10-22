# E-invoice tracking (Basic) — deploy

E-invoices are created in TallyPrime (Tally is a GSP). TallyConnect shows and tracks what Tally saved on each invoice: IRN, acknowledgement, signed QR, e-way bill.

1. Run once on the database: `sql/2026-10-21_einvoice.sql`. It only creates one new table (`einvoices`); nothing existing changes.
2. Backend files (already copied into `tally-backend/`):
   - `utils/einvoiceCore.js`, `utils/einvoiceRouter.js`
   - `routes/einvoice.js`
   - `server.js`: `import einvoiceRoutes from "./routes/einvoice.js";` and `app.use(einvoiceRoutes);` next to `leaveRoutes`.
3. Deploy the backend.
4. Agent: build the new exe (`lib/einvoiceSink.cjs` + the calls in `agent.cjs`). The voucher sync is unchanged; e-invoice details go in a separate upload after each voucher batch. Before the server has the route, the Agent turns this off by itself (404).
5. App: build as usual. Reports → E-invoices (admin, and team members allowed to see financial reports).

Data arrives as the Agent reads vouchers: invoices in the recent sync window at once; an IRN added in Tally to an older invoice appears with the Agent's weekly full read.

Tests: `node --test test/einvoice.test.mjs` (fake database; no network).
