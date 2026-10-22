/* =========================================================
   E-INVOICE (Basic) routes — wires the real database and login check into
   the router (see utils/einvoiceRouter.js).
========================================================= */
import pool from "../db.js";
import requireAuth from "../middleware/requireAuth.js";
import { createEinvoiceRouter } from "../utils/einvoiceRouter.js";

export default createEinvoiceRouter({ db: pool, auth: requireAuth });
