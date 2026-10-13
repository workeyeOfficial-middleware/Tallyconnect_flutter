/* =========================================================
   OUTSTANDING EMAIL REMINDER routes — wires the real database, login
   check and mailer into the router (see utils/reminderRouter.js).
========================================================= */
import pool from "../db.js";
import requireAuth from "../middleware/requireAuth.js";
import { sendReminderEmail } from "../utils/sendReminderEmail.js";
import { createReminderRouter } from "../utils/reminderRouter.js";

export default createReminderRouter({
  db: pool,
  auth: requireAuth,
  sendEmail: (m) => sendReminderEmail(m),
});
