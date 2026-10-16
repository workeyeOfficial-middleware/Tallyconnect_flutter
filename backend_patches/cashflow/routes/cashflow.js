/* =========================================================
   CASH FLOW FORECAST routes — wires the real database, login check and the
   financial reports' figures (opening cash / bank balance) into the router
   (see utils/cashflowRouter.js). Read-only.
========================================================= */
import pool from "../db.js";
import requireAuth from "../middleware/requireAuth.js";
import { createFinancialData } from "../utils/financialData.js";
import { createCashflowRouter } from "../utils/cashflowRouter.js";

export default createCashflowRouter({
  db: pool,
  auth: requireAuth,
  financialData: createFinancialData(pool),
});
