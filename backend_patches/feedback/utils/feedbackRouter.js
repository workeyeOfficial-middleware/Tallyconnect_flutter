/* =========================================================
   FEEDBACK — routes (factory; dependencies are passed in)

   Customer:  POST  /api/feedback                       (any signed-in user)
   Team:      GET   /api/admin/feedback                 (allow-listed emails)
              GET   /api/admin/feedback/:id
              PATCH /api/admin/feedback/:id             {status, admin_note}
              POST  /api/admin/feedback/:id/resend-email

   Every submission is stored FIRST, then the notification email is sent
   and only then does the request answer — with the real email result:
     201 {success:true,  email_status:'sent'}    Microsoft Graph accepted it
     502 {success:false, email_status:'failed'}  Graph refused / unreachable
     503 {success:false, email_status:'skipped'} no recipient configured
   The feedback is kept in every case (`stored:true`, email_status recorded)
   and a failed email can be re-sent from the admin route.
========================================================= */
import express from "express";
import {
  buildFeedbackEmail,
  feedbackConfig,
  isFeedbackAdmin,
  parsePaging,
  validateAdminUpdate,
  validateFeedback,
  FEEDBACK_STATUSES,
  FEEDBACK_TYPES,
} from "./feedbackCore.js";

const SELECT_COLS = `id, user_id, admin_id, user_email, username, role, company_guid,
  type, rating, message, app_version, platform, status, admin_note,
  reviewed_by, reviewed_at, email_status, email_error, email_attempts,
  emailed_at, created_at, updated_at`;

/**
 * @param {object} deps
 * @param {{query: Function}} deps.db         pg Pool (or compatible)
 * @param {Function} deps.auth                requireAuth middleware
 * @param {Function} deps.sendEmail           async ({to, subject, html, replyTo}) => void
 * @param {object} [deps.env]                 process.env
 * @param {object} [deps.log]                 console
 */
export function createFeedbackRouter({ db, auth, sendEmail, env = process.env, log = console }) {
  const router = express.Router();
  const cfg = () => feedbackConfig(env);

  /**
   * Sends the notification for a stored row and records the outcome.
   * @returns {Promise<{status: "sent"|"failed"|"skipped", error?: string}>}
   */
  async function notify(row) {
    const to = cfg().notifyEmail;
    if (!to) {
      const error = "FEEDBACK_NOTIFICATION_EMAIL is not set (or not a valid email)";
      log.error(`feedback #${row.id} email skipped: ${error}`);
      await db
        .query(
          `UPDATE feedback SET email_status = 'skipped',
             email_error = $2, updated_at = NOW()
           WHERE id = $1`,
          [row.id, error]
        )
        .catch((e) => log.error("feedback email status update failed:", e.message));
      return { status: "skipped", error };
    }
    try {
      const { subject, html } = buildFeedbackEmail(row);
      const res = await sendEmail({ to, subject, html, replyTo: row.user_email || null });
      (log.info || log.log || (() => {})).call(
        log,
        `feedback #${row.id} email accepted by Microsoft Graph` +
          ` (HTTP ${res?.status ?? "?"}, request-id ${res?.requestId ?? "-"})`
      );
      await db.query(
        `UPDATE feedback SET email_status = 'sent', email_error = NULL,
           email_attempts = email_attempts + 1, emailed_at = NOW(), updated_at = NOW()
         WHERE id = $1`,
        [row.id]
      );
      return { status: "sent" };
    } catch (err) {
      const error = String(err?.message || err).slice(0, 500);
      log.error(`feedback #${row.id} email failed:`, error);
      await db
        .query(
          `UPDATE feedback SET email_status = 'failed', email_error = $2,
             email_attempts = email_attempts + 1, updated_at = NOW()
           WHERE id = $1`,
          [row.id, error]
        )
        .catch((e) => log.error("feedback email status update failed:", e.message));
      return { status: "failed", error };
    }
  }

  /* ------------------------------------------------ customer: submit */
  router.post("/api/feedback", auth, async (req, res) => {
    const user = req.user || {};
    if (!user.id) return res.status(401).json({ success: false, message: "Unauthorized" });

    const v = validateFeedback(req.body);
    if (!v.ok) return res.status(400).json({ success: false, message: v.message });
    const f = v.value;
    const c = cfg();

    try {
      // Rate limit per user (stored submissions; works across instances).
      const rl = await db.query(
        `SELECT
           COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '1 hour')::int AS hour,
           COUNT(*)::int AS day
         FROM feedback
         WHERE user_id = $1 AND created_at > NOW() - INTERVAL '1 day'`,
        [user.id]
      );
      const { hour = 0, day = 0 } = rl.rows[0] || {};
      if (hour >= c.perHour || day >= c.perDay) {
        res.set("Retry-After", hour >= c.perHour ? "3600" : "86400");
        return res.status(429).json({
          success: false,
          message: "You have sent a lot of feedback recently. Please try again later.",
        });
      }

      // The account's active company, from the server (never the body).
      let companyGuid = null;
      if (user.adminId) {
        try {
          const a = await db.query(
            `SELECT company_guid FROM active_company WHERE admin_id = $1`,
            [user.adminId]
          );
          companyGuid = a.rows[0]?.company_guid || null;
        } catch {
          companyGuid = null;
        }
      }

      const ins = await db.query(
        `INSERT INTO feedback
           (user_id, admin_id, user_email, username, role, company_guid,
            type, rating, message, app_version, platform, user_agent)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
         RETURNING ${SELECT_COLS}`,
        [
          user.id,
          user.adminId ?? null,
          user.email ? String(user.email).slice(0, 320) : null,
          user.username ? String(user.username).slice(0, 255) : null,
          user.role ? String(user.role).slice(0, 20) : null,
          companyGuid,
          f.type,
          f.rating,
          f.message,
          f.appVersion,
          f.platform,
          String(req.headers["user-agent"] || "").slice(0, 300) || null,
        ]
      );
      const row = ins.rows[0];

      // Answer only once the email result is known (the row is stored
      // whatever happens). Provider details stay in the log / database.
      const email = await notify(row);
      if (email.status === "sent") {
        return res.status(201).json({ success: true, id: row.id, email_status: "sent" });
      }
      const skipped = email.status === "skipped";
      return res.status(skipped ? 503 : 502).json({
        success: false,
        stored: true,
        id: row.id,
        email_status: email.status,
        code: skipped ? "email_not_configured" : "email_failed",
        message: skipped
          ? `Your feedback was saved (#${row.id}), but feedback email is not set up on the server, so the TallyConnect team was not emailed.`
          : `Your feedback was saved (#${row.id}), but the email to the TallyConnect team could not be sent. Please try again later.`,
      });
    } catch (err) {
      log.error("feedback submit error:", err.message);
      if (!res.headersSent) {
        res.status(500).json({ success: false, message: "Could not save feedback. Try again." });
      }
    }
  });

  /* --------------------------------------------- TallyConnect team */
  const requireFeedbackAdmin = (req, res, next) => {
    if (!isFeedbackAdmin(req.user, cfg())) {
      return res.status(403).json({ success: false, message: "Forbidden" });
    }
    next();
  };
  const idOf = (req) => {
    const id = Number.parseInt(req.params.id, 10);
    return Number.isInteger(id) && id > 0 ? id : null;
  };

  router.get("/api/admin/feedback", auth, requireFeedbackAdmin, async (req, res) => {
    const { page, limit, offset } = parsePaging(req.query);
    const where = [];
    const params = [];
    if (req.query.status) {
      if (!FEEDBACK_STATUSES.includes(req.query.status)) {
        return res.status(400).json({ success: false, message: "Unknown status" });
      }
      params.push(req.query.status);
      where.push(`status = $${params.length}`);
    }
    if (req.query.type) {
      if (!FEEDBACK_TYPES.includes(req.query.type)) {
        return res.status(400).json({ success: false, message: "Unknown type" });
      }
      params.push(req.query.type);
      where.push(`type = $${params.length}`);
    }
    if (req.query.q) {
      params.push(String(req.query.q).slice(0, 100));
      const i = params.length;
      where.push(`(message ILIKE '%' || $${i} || '%' OR user_email ILIKE '%' || $${i} || '%')`);
    }
    const whereSql = where.length ? `WHERE ${where.join(" AND ")}` : "";
    try {
      const total = await db.query(`SELECT COUNT(*)::int AS n FROM feedback ${whereSql}`, params);
      const rows = await db.query(
        `SELECT ${SELECT_COLS} FROM feedback ${whereSql}
         ORDER BY created_at DESC, id DESC
         LIMIT $${params.length + 1} OFFSET $${params.length + 2}`,
        [...params, limit, offset]
      );
      res.json({
        success: true,
        data: rows.rows,
        meta: { total: total.rows[0]?.n ?? 0, page, limit },
      });
    } catch (err) {
      log.error("feedback list error:", err.message);
      res.status(500).json({ success: false, message: "Server error" });
    }
  });

  /** Which email settings the running server has (never their values,
   *  except the recipient address the team chose). */
  router.get("/api/admin/feedback/email-config", auth, requireFeedbackAdmin, (req, res) => {
    const has = (k) => Boolean(String(env[k] || "").trim());
    res.json({
      success: true,
      notify_email: cfg().notifyEmail,
      graph: {
        MICROSOFT_TENANT_ID: has("MICROSOFT_TENANT_ID"),
        MICROSOFT_CLIENT_ID: has("MICROSOFT_CLIENT_ID"),
        MICROSOFT_CLIENT_SECRET: has("MICROSOFT_CLIENT_SECRET"),
        MICROSOFT_SENDER_EMAIL: has("MICROSOFT_SENDER_EMAIL"),
      },
    });
  });

  router.get("/api/admin/feedback/:id", auth, requireFeedbackAdmin, async (req, res) => {
    const id = idOf(req);
    if (!id) return res.status(400).json({ success: false, message: "Invalid id" });
    try {
      const r = await db.query(`SELECT ${SELECT_COLS} FROM feedback WHERE id = $1`, [id]);
      if (!r.rows[0]) return res.status(404).json({ success: false, message: "Not found" });
      res.json({ success: true, data: r.rows[0] });
    } catch (err) {
      log.error("feedback get error:", err.message);
      res.status(500).json({ success: false, message: "Server error" });
    }
  });

  router.patch("/api/admin/feedback/:id", auth, requireFeedbackAdmin, async (req, res) => {
    const id = idOf(req);
    if (!id) return res.status(400).json({ success: false, message: "Invalid id" });
    const v = validateAdminUpdate(req.body);
    if (!v.ok) return res.status(400).json({ success: false, message: v.message });
    const sets = [];
    const params = [id];
    if (v.value.status !== undefined) {
      params.push(v.value.status);
      sets.push(`status = $${params.length}`);
    }
    if (v.value.adminNote !== undefined) {
      params.push(v.value.adminNote);
      sets.push(`admin_note = $${params.length}`);
    }
    params.push(String(req.user.email || "").slice(0, 320));
    sets.push(`reviewed_by = $${params.length}`, "reviewed_at = NOW()", "updated_at = NOW()");
    try {
      const r = await db.query(
        `UPDATE feedback SET ${sets.join(", ")} WHERE id = $1 RETURNING ${SELECT_COLS}`,
        params
      );
      if (!r.rows[0]) return res.status(404).json({ success: false, message: "Not found" });
      res.json({ success: true, data: r.rows[0] });
    } catch (err) {
      log.error("feedback update error:", err.message);
      res.status(500).json({ success: false, message: "Server error" });
    }
  });

  router.post("/api/admin/feedback/:id/resend-email", auth, requireFeedbackAdmin, async (req, res) => {
    const id = idOf(req);
    if (!id) return res.status(400).json({ success: false, message: "Invalid id" });
    try {
      const r = await db.query(`SELECT ${SELECT_COLS} FROM feedback WHERE id = $1`, [id]);
      if (!r.rows[0]) return res.status(404).json({ success: false, message: "Not found" });
      const email = await notify(r.rows[0]);
      res.json({
        success: email.status === "sent",
        email_status: email.status,
        email_error: email.error || null,
      });
    } catch (err) {
      log.error("feedback resend error:", err.message);
      res.status(500).json({ success: false, message: "Server error" });
    }
  });

  return router;
}
