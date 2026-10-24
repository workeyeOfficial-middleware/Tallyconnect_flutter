/* =========================================================
   AUTOMATIC PAYMENT REMINDERS — every hour at :05 (server time; the
   settings' hour is India time). Emails the parties whose bills are due
   for a reminder, for companies whose admin chose Automatic (see
   utils/reminderRouter.js runAutomatic). Nothing happens for Manual, or
   before sql/2026-10-22_reminder_settings.sql has run.
========================================================= */
import cron from "node-cron";
import reminderRoutes from "../routes/reminders.js";

let running = false;

cron.schedule("5 * * * *", async () => {
  if (running) return;
  running = true;
  try {
    const r = await reminderRoutes.runAutomatic();
    if (r.companies) console.log("[REMINDER CRON]", r);
  } catch (err) {
    console.error("[REMINDER CRON] error:", err?.message || err);
  } finally {
    running = false;
  }
});
