/* =========================================================
   LEAVE MANAGEMENT routes — wires the real database and login check
   into the router (see utils/leaveRouter.js).
========================================================= */
import pool from "../db.js";
import requireAuth from "../middleware/requireAuth.js";
import { createLeaveRouter } from "../utils/leaveRouter.js";

export default createLeaveRouter({ db: pool, auth: requireAuth });
