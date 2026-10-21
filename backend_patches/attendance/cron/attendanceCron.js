// Closes check-ins left open past their India day at 23:59 IST (marked
// closed_by 'auto'). Runs every 10 minutes, so a server restart around
// midnight still closes them; every attendance request also does this for
// its own account first.
import cron from "node-cron";
import pool from "../db.js";
import { closeForgotten } from "../utils/attendanceRouter.js";

let running = false;

cron.schedule("*/10 * * * *", async () => {
  if (running) return;
  running = true;
  try {
    const n = await closeForgotten(pool, new Date());
    if (n) console.log("[ATTENDANCE CRON] auto check-out", { sessions: n });
  } catch (err) {
    console.error("[ATTENDANCE CRON] error:", err.message);
  } finally {
    running = false;
  }
});
