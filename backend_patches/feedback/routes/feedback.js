/* =========================================================
   FEEDBACK routes — wires the real database, login check and mailer
   into the router (see utils/feedbackRouter.js).
========================================================= */
import pool from "../db.js";
import requireAuth from "../middleware/requireAuth.js";
import { sendFeedbackEmail } from "../utils/sendFeedbackEmail.js";
import { createFeedbackRouter } from "../utils/feedbackRouter.js";

export default createFeedbackRouter({
  db: pool,
  auth: requireAuth,
  sendEmail: sendFeedbackEmail,
});
