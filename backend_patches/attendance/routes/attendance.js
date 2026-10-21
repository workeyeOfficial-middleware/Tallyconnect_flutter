/* =========================================================
   SALES TEAM ATTENDANCE routes — wires the real database and login check
   into the router (see utils/attendanceRouter.js).
========================================================= */
import pool from "../db.js";
import requireAuth from "../middleware/requireAuth.js";
import { createAttendanceRouter } from "../utils/attendanceRouter.js";

export default createAttendanceRouter({ db: pool, auth: requireAuth });
