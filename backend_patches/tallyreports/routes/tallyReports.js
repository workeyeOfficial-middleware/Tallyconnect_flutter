/* =========================================================
   OFFICIAL TALLY REPORTS routes — wires the database and login check into
   the router (see utils/tallyReportsRouter.js). Mounted before the "/"
   catch-all in server.js.
========================================================= */
import pool from "../db.js";
import requireAuth from "../middleware/requireAuth.js";
import { createTallyReportsRouter } from "../utils/tallyReportsRouter.js";

export default createTallyReportsRouter({ db: pool, auth: requireAuth });
