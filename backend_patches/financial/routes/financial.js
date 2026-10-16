/* =========================================================
   FINANCIAL REPORTS routes — wires the real database and login check into
   the router (see utils/financialRouter.js).
========================================================= */
import pool from "../db.js";
import requireAuth from "../middleware/requireAuth.js";
import { createFinancialRouter } from "../utils/financialRouter.js";

export default createFinancialRouter({ db: pool, auth: requireAuth });
