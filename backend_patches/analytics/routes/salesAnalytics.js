/* =========================================================
   SALES ANALYTICS routes — wires the real database and login check into
   the router (see utils/salesAnalytics.js).
========================================================= */
import pool from "../db.js";
import requireAuth from "../middleware/requireAuth.js";
import { createSalesAnalyticsRouter } from "../utils/salesAnalytics.js";

export default createSalesAnalyticsRouter({ db: pool, auth: requireAuth });
