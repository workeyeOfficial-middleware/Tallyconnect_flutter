/* =========================================================
   OUTSTANDING EMAIL REMINDERS — routes (factory; dependencies passed in)

   All routes need a login (requireAuth). Everything is scoped on the
   server to the account (JWT adminId) and its ACTIVE company
   (active_company), and — for USER logins — to the ledgers the user is
   allowed (user_ledger_permissions). Bill amounts, due dates and the
   recipient are always read from the database; the app sends only the
   ledger and the bill references. Nothing is ever written to Tally.

   GET    /api/reminders/templates            list (built-in one when none)
   POST   /api/reminders/templates            ADMIN: create
   PUT    /api/reminders/templates/:id        ADMIN: update
   DELETE /api/reminders/templates/:id        ADMIN: delete
   POST   /api/reminders/preview              {ledger_guid, bill_names[], template_id?}
   POST   /api/reminders/send                 … + expected_total, idempotency_key
   GET    /api/reminders/history?ledger_guid= this company's reminders
   POST   /api/reminders/:id/retry            a failed reminder, again
   GET    /api/reminders/settings             when reminders are due, mode
   PUT    /api/reminders/settings             ADMIN: change them
   GET    /api/reminders/due                  parties due for one today

   Automatic mode: runAutomatic() (hourly cron, cron/reminderCron.js)
   emails each party whose bills are due by the settings, at the set hour,
   once a day per party and bills (idempotency key), within the account's
   daily limit, with the default template.

   Send result = what Microsoft Graph answered: "accepted" means Graph
   accepted the message for delivery (HTTP 202); it is never reported as
   "delivered".
========================================================= */
import express from "express";
import {
  DEFAULT_SETTINGS,
  DEFAULT_TEMPLATE,
  MAX_TEMPLATES,
  PLACEHOLDERS,
  billSetKey,
  buildReminderEmail,
  normaliseBills,
  publicLog,
  recipientsOf,
  reminderConfig,
  totalOf,
  validateSelection,
  validateTemplate,
  autoKey,
  istNow,
  normaliseBills as normalise,
  reminderDue,
  settingsOf,
  validateSettings,
} from "./reminderCore.js";

const TEMPLATE_COLS = "id, name, subject, body, is_default, updated_at";
const LOG_COLS = `id, admin_id, company_guid, ledger_guid, ledger_name, template_id, bill_set,
  bills, total_amount, recipients, subject, status, error, attempts, provider,
  provider_status, provider_request_id, idempotency_key, sent_by_user_id,
  sent_by_email, sent_by_name, created_at, updated_at, sent_at`;

class HttpError extends Error {
  constructor(status, message, code, extra) {
    super(message);
    this.status = status;
    this.code = code;
    this.extra = extra;
  }
}

/**
 * @param {object} deps
 * @param {{query: Function}} deps.db     pg Pool (or compatible)
 * @param {Function} deps.auth            requireAuth middleware
 * @param {Function} deps.sendEmail       async ({to[], subject, html, replyTo}) => {provider, status, requestId}
 * @param {object} [deps.env]             process.env
 * @param {object} [deps.log]             console
 * @param {Function} [deps.now]           () => Date (tests)
 */
export function createReminderRouter({
  db,
  auth,
  sendEmail,
  env = process.env,
  log = console,
  now = () => new Date(),
}) {
  const router = express.Router();
  const cfg = () => reminderConfig(env);

  /* ------------------------------------------------------- scoping */

  /** Who is asking, and the account's active company (from the server). */
  async function scope(req) {
    const u = req.user || {};
    if (!u.id) throw new HttpError(401, "Unauthorized");
    const adminId = u.adminId ?? (u.role === "ADMIN" ? u.id : null);
    if (!adminId) throw new HttpError(403, "Access denied");
    const r = await db.query(
      `SELECT ac.company_guid, c.name AS company_name
         FROM active_company ac
         LEFT JOIN companies c
           ON c.company_guid = ac.company_guid AND c.admin_id = ac.admin_id
        WHERE ac.admin_id = $1
        LIMIT 1`,
      [adminId]
    );
    const company = r.rows[0]?.company_guid || null;
    if (!company) {
      throw new HttpError(409, "No company is selected for this account.", "no_company");
    }
    return {
      user: u,
      adminId,
      isAdmin: u.role === "ADMIN",
      company,
      companyName: r.rows[0]?.company_name || "",
    };
  }

  /** The ledger in the active company, if this login may use it. */
  async function ledgerFor(s, ledgerGuid) {
    const r = await db.query(
      `SELECT ledger_guid, name, email
         FROM ledgers
        WHERE ledger_guid = $1 AND admin_id = $2 AND company_guid = $3
        LIMIT 1`,
      [ledgerGuid, s.adminId, s.company]
    );
    const ledger = r.rows[0];
    if (!ledger) throw new HttpError(404, "Party not found in the selected company.", "no_ledger");
    if (!s.isAdmin) {
      const p = await db.query(
        `SELECT 1 FROM user_ledger_permissions WHERE user_id = $1 AND ledger_guid = $2 LIMIT 1`,
        [s.user.id, ledgerGuid]
      );
      if (!p.rowCount) throw new HttpError(403, "You do not have access to this party.", "no_access");
    }
    return ledger;
  }

  /** Pending receivable bills of the ledger, read from the database. */
  async function billsFor(s, ledger, names) {
    const r = await db.query(
      `SELECT bill_name, bill_date, due_date, pending_amount
         FROM bills
        WHERE admin_id = $1
          AND company_guid = $2
          AND (ledger_guid = $3 OR (ledger_guid IS NULL AND ledger_name = $4))
          AND bill_name = ANY($5::text[])
          AND pending_amount > 0
          AND COALESCE(UPPER(bill_type), 'RECEIVABLE') <> 'PAYABLE'
        ORDER BY due_date ASC NULLS LAST, bill_name ASC`,
      [s.adminId, s.company, ledger.ledger_guid, ledger.name, names]
    );
    const seen = new Set();
    const rows = r.rows.filter((b) => !seen.has(b.bill_name) && seen.add(b.bill_name));
    return normaliseBills(rows, now());
  }

  async function templateFor(s, id) {
    if (id) {
      const r = await db.query(
        `SELECT ${TEMPLATE_COLS} FROM reminder_templates WHERE id = $1 AND admin_id = $2`,
        [id, s.adminId]
      );
      if (!r.rows[0]) throw new HttpError(404, "Template not found.", "no_template");
      return r.rows[0];
    }
    const r = await db.query(
      `SELECT ${TEMPLATE_COLS} FROM reminder_templates
        WHERE admin_id = $1 AND is_default = TRUE ORDER BY id LIMIT 1`,
      [s.adminId]
    );
    return r.rows[0] || DEFAULT_TEMPLATE;
  }

  /** Everything the email will contain, rebuilt from the database. */
  async function compose(s, sel) {
    const ledger = await ledgerFor(s, sel.ledgerGuid);
    const bills = await billsFor(s, ledger, sel.billNames);
    const template = await templateFor(s, sel.templateId);
    const recipients = recipientsOf(ledger.email);
    const sender = s.user.username || s.user.email || "";
    const mail = buildReminderEmail({
      template,
      party: ledger.name,
      company: s.companyName,
      sender,
      bills,
    });
    const found = new Set(bills.map((b) => b.bill_name));
    return {
      ledger,
      bills,
      template,
      recipients,
      mail,
      total: totalOf(bills),
      missing: sel.billNames.filter((n) => !found.has(n)),
    };
  }

  function problemsOf(c) {
    const p = [];
    if (!c.bills.length) p.push("None of the selected bills is pending any more.");
    if (!c.recipients.length) {
      p.push(`No valid email address is saved for ${c.ledger.name} in Tally.`);
    }
    if (!cfg().mailReady) p.push("Email sending is not configured on the server.");
    return p;
  }

  async function rateLimit(s) {
    const c = cfg();
    const r = await db.query(
      `SELECT
         COUNT(*) FILTER (WHERE sent_by_user_id = $2
                            AND created_at > NOW() - INTERVAL '1 hour')::int AS hour,
         COUNT(*)::int AS day
       FROM reminder_log
       WHERE admin_id = $1 AND created_at > NOW() - INTERVAL '1 day'`,
      [s.adminId, s.user.id]
    );
    const { hour = 0, day = 0 } = r.rows[0] || {};
    if (hour >= c.perHour || day >= c.perDay) {
      throw new HttpError(
        429,
        hour >= c.perHour
          ? `You can send at most ${c.perHour} reminders an hour. Try again later.`
          : `This account can send at most ${c.perDay} reminders a day. Try again tomorrow.`,
        "rate_limited",
        { retryAfter: hour >= c.perHour ? 3600 : 86400 }
      );
    }
  }

  /** Sends a stored (pending) row and records exactly what happened. */
  async function deliver(row, c, s) {
    if (!cfg().mailReady) {
      const error = "Email sending is not configured on the server (MICROSOFT_* variables).";
      const u = await db.query(
        `UPDATE reminder_log SET status = 'failed', error = $2, attempts = attempts + 1,
           updated_at = NOW() WHERE id = $1 RETURNING ${LOG_COLS}`,
        [row.id, error]
      );
      return { row: u.rows[0], code: "email_not_configured" };
    }
    try {
      const res = await sendEmail({
        to: c.recipients,
        subject: c.mail.subject,
        html: c.mail.html,
        replyTo: s.user.email || null,
      });
      const u = await db.query(
        `UPDATE reminder_log SET status = 'accepted', error = NULL, attempts = attempts + 1,
           provider = $2, provider_status = $3, provider_request_id = $4,
           sent_at = NOW(), updated_at = NOW()
         WHERE id = $1 RETURNING ${LOG_COLS}`,
        [row.id, res?.provider || null, res?.status ?? null, res?.requestId || null]
      );
      return { row: u.rows[0], code: null };
    } catch (err) {
      log.error(`reminder #${row.id} email failed:`, err?.message || err);
      const u = await db.query(
        `UPDATE reminder_log SET status = 'failed', error = $2, attempts = attempts + 1,
           provider_status = $3, updated_at = NOW()
         WHERE id = $1 RETURNING ${LOG_COLS}`,
        [row.id, String(err?.message || err).slice(0, 500), err?.status ?? null]
      );
      return {
        row: u.rows[0],
        code: err?.code === "not_configured" ? "email_not_configured" : "send_failed",
      };
    }
  }

  function sendResult(res, { row, code }) {
    const data = publicLog(row);
    if (!code) {
      return res.json({
        success: true,
        data,
        message:
          `Accepted by Microsoft 365 for delivery to ${data.recipients.join(", ")}. ` +
          "Delivery to the inbox is not confirmed.",
      });
    }
    const notConfigured = code === "email_not_configured";
    return res.status(notConfigured ? 503 : 502).json({
      success: false,
      code,
      data,
      message: notConfigured
        ? "Email sending is not configured on the server. Nothing was sent."
        : `The email was not sent: ${data.error}`,
    });
  }

  const handle = (fn) => async (req, res) => {
    try {
      await fn(req, res);
    } catch (err) {
      if (err instanceof HttpError) {
        if (err.extra?.retryAfter) res.set("Retry-After", String(err.extra.retryAfter));
        return res.status(err.status).json({
          success: false,
          message: err.message,
          ...(err.code ? { code: err.code } : {}),
          ...(err.extra?.data ? { data: err.extra.data } : {}),
        });
      }
      log.error("reminders error:", err?.message || err);
      if (!res.headersSent) res.status(500).json({ success: false, message: "Server error" });
    }
  };

  const requireAccountAdmin = (req, res, next) => {
    if (req.user?.role !== "ADMIN") {
      return res.status(403).json({ success: false, message: "Only the admin can manage templates." });
    }
    next();
  };

  const idOf = (req) => {
    const id = Number.parseInt(req.params.id, 10);
    if (!Number.isInteger(id) || id <= 0 || String(id) !== req.params.id) {
      throw new HttpError(400, "Invalid id");
    }
    return id;
  };

  /* ----------------------------------------------------- templates */
  router.get(
    "/api/reminders/templates",
    auth,
    handle(async (req, res) => {
      const u = req.user || {};
      const adminId = u.adminId ?? (u.role === "ADMIN" ? u.id : null);
      if (!adminId) throw new HttpError(403, "Access denied");
      const r = await db.query(
        `SELECT ${TEMPLATE_COLS} FROM reminder_templates WHERE admin_id = $1
          ORDER BY is_default DESC, name ASC`,
        [adminId]
      );
      res.json({
        success: true,
        data: r.rows.length ? r.rows : [DEFAULT_TEMPLATE],
        placeholders: PLACEHOLDERS,
        can_edit: u.role === "ADMIN",
        email_configured: cfg().mailReady,
      });
    })
  );

  router.post(
    "/api/reminders/templates",
    auth,
    requireAccountAdmin,
    handle(async (req, res) => {
      const v = validateTemplate(req.body);
      if (!v.ok) throw new HttpError(400, v.message);
      const adminId = req.user.adminId ?? req.user.id;
      const n = await db.query(
        `SELECT COUNT(*)::int AS n FROM reminder_templates WHERE admin_id = $1`,
        [adminId]
      );
      if ((n.rows[0]?.n ?? 0) >= MAX_TEMPLATES) {
        throw new HttpError(409, `At most ${MAX_TEMPLATES} templates.`);
      }
      try {
        const r = await db.query(
          `INSERT INTO reminder_templates (admin_id, name, subject, body, is_default, created_by)
           VALUES ($1, $2, $3, $4, $5, $6) RETURNING ${TEMPLATE_COLS}`,
          [adminId, v.value.name, v.value.subject, v.value.body, v.value.isDefault === true, req.user.id]
        );
        // One default per account (only once the new one is saved).
        if (v.value.isDefault) {
          await db.query(
            `UPDATE reminder_templates SET is_default = FALSE WHERE admin_id = $1 AND id <> $2`,
            [adminId, r.rows[0].id]
          );
        }
        res.status(201).json({ success: true, data: r.rows[0] });
      } catch (err) {
        if (err?.code === "23505") throw new HttpError(409, "A template with this name exists.");
        throw err;
      }
    })
  );

  router.put(
    "/api/reminders/templates/:id",
    auth,
    requireAccountAdmin,
    handle(async (req, res) => {
      const id = idOf(req);
      const v = validateTemplate(req.body, { partial: true });
      if (!v.ok) throw new HttpError(400, v.message);
      const adminId = req.user.adminId ?? req.user.id;
      const sets = [];
      const params = [id, adminId];
      for (const [col, key] of [
        ["name", "name"],
        ["subject", "subject"],
        ["body", "body"],
        ["is_default", "isDefault"],
      ]) {
        if (v.value[key] !== undefined) {
          params.push(v.value[key]);
          sets.push(`${col} = $${params.length}`);
        }
      }
      try {
        const r = await db.query(
          `UPDATE reminder_templates SET ${sets.join(", ")}, updated_at = NOW()
            WHERE id = $1 AND admin_id = $2 RETURNING ${TEMPLATE_COLS}`,
          params
        );
        if (!r.rows[0]) throw new HttpError(404, "Template not found.");
        if (v.value.isDefault) {
          await db.query(
            `UPDATE reminder_templates SET is_default = FALSE WHERE admin_id = $1 AND id <> $2`,
            [adminId, id]
          );
        }
        res.json({ success: true, data: r.rows[0] });
      } catch (err) {
        if (err?.code === "23505") throw new HttpError(409, "A template with this name exists.");
        throw err;
      }
    })
  );

  router.delete(
    "/api/reminders/templates/:id",
    auth,
    requireAccountAdmin,
    handle(async (req, res) => {
      const id = idOf(req);
      const r = await db.query(
        `DELETE FROM reminder_templates WHERE id = $1 AND admin_id = $2 RETURNING id`,
        [id, req.user.adminId ?? req.user.id]
      );
      if (!r.rows[0]) throw new HttpError(404, "Template not found.");
      res.json({ success: true });
    })
  );

  /* ------------------------------------------------------- preview */
  router.post(
    "/api/reminders/preview",
    auth,
    handle(async (req, res) => {
      const v = validateSelection(req.body);
      if (!v.ok) throw new HttpError(400, v.message);
      const s = await scope(req);
      const c = await compose(s, v.value);
      const problems = problemsOf(c);
      res.json({
        success: true,
        data: {
          ledger_guid: c.ledger.ledger_guid,
          party: c.ledger.name,
          company: s.companyName,
          recipients: c.recipients,
          subject: c.mail.subject,
          html: c.mail.html,
          text: c.mail.text,
          bills: c.bills,
          missing_bills: c.missing,
          total: c.total,
          currency: "INR",
          template: { id: c.template.id, name: c.template.name },
          email_configured: cfg().mailReady,
          can_send: problems.length === 0,
          problems,
        },
      });
    })
  );

  /* ---------------------------------------------------------- send */
  router.post(
    "/api/reminders/send",
    auth,
    handle(async (req, res) => {
      const v = validateSelection(req.body);
      if (!v.ok) throw new HttpError(400, v.message);
      const sel = v.value;
      const s = await scope(req);

      // The same confirmation sent twice (double tap / network retry):
      // answer with the first result, never a second email.
      if (sel.key) {
        const prev = await db.query(
          `SELECT ${LOG_COLS} FROM reminder_log WHERE admin_id = $1 AND idempotency_key = $2`,
          [s.adminId, sel.key]
        );
        if (prev.rows[0]) {
          return res.json({ success: prev.rows[0].status === "accepted", replay: true, data: publicLog(prev.rows[0]) });
        }
      }

      const c = await compose(s, sel);
      if (!c.bills.length) {
        throw new HttpError(409, "None of the selected bills is pending any more.", "nothing_pending");
      }
      if (sel.expectedTotal !== null && Math.abs(sel.expectedTotal - c.total) > 0.005) {
        throw new HttpError(
          409,
          "The bills changed in Tally since the preview. Review the reminder again.",
          "changed",
          { data: { total: c.total, bills: c.bills } }
        );
      }
      if (!c.recipients.length) {
        throw new HttpError(
          422,
          `No valid email address is saved for ${c.ledger.name} in Tally.`,
          "no_email"
        );
      }
      await rateLimit(s);

      const set = billSetKey(c.bills.map((b) => b.bill_name));
      const win = cfg().duplicateMinutes;
      if (win > 0) {
        const dup = await db.query(
          `SELECT id, created_at FROM reminder_log
            WHERE admin_id = $1 AND company_guid = $2 AND ledger_guid = $3 AND bill_set = $4
              AND status IN ('pending', 'accepted')
              AND created_at > NOW() - make_interval(mins => $5)
            ORDER BY created_at DESC LIMIT 1`,
          [s.adminId, s.company, c.ledger.ledger_guid, set, win]
        );
        if (dup.rows[0]) {
          throw new HttpError(
            409,
            `A reminder for these bills was already sent to ${c.ledger.name} in the last ${win} minutes.`,
            "duplicate"
          );
        }
      }

      let row;
      try {
        const ins = await db.query(
          `INSERT INTO reminder_log
             (admin_id, company_guid, ledger_guid, ledger_name, template_id, bill_set, bills,
              total_amount, recipients, subject, status, idempotency_key,
              sent_by_user_id, sent_by_email, sent_by_name)
           VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8, $9::jsonb, $10, 'pending', $11, $12, $13, $14)
           RETURNING ${LOG_COLS}`,
          [
            s.adminId,
            s.company,
            c.ledger.ledger_guid,
            c.ledger.name,
            c.template.id,
            set,
            JSON.stringify(c.bills),
            c.total,
            JSON.stringify(c.recipients),
            c.mail.subject,
            sel.key,
            s.user.id,
            s.user.email ? String(s.user.email).slice(0, 320) : null,
            s.user.username ? String(s.user.username).slice(0, 255) : null,
          ]
        );
        row = ins.rows[0];
      } catch (err) {
        if (err?.code === "23505") {
          throw new HttpError(409, "This reminder is already being sent.", "duplicate");
        }
        throw err;
      }
      sendResult(res, await deliver(row, c, s));
    })
  );

  /* ------------------------------------------------------- history */
  router.get(
    "/api/reminders/history",
    auth,
    handle(async (req, res) => {
      const s = await scope(req);
      const limit = Math.min(Math.max(Number.parseInt(req.query.limit, 10) || 30, 1), 100);
      const ledgerGuid = typeof req.query.ledger_guid === "string" ? req.query.ledger_guid.trim() : "";
      let r;
      if (ledgerGuid) {
        await ledgerFor(s, ledgerGuid);
        r = await db.query(
          `SELECT ${LOG_COLS} FROM reminder_log
            WHERE admin_id = $1 AND company_guid = $2 AND ledger_guid = $3
            ORDER BY created_at DESC, id DESC LIMIT $4`,
          [s.adminId, s.company, ledgerGuid, limit]
        );
      } else if (s.isAdmin) {
        r = await db.query(
          `SELECT ${LOG_COLS} FROM reminder_log
            WHERE admin_id = $1 AND company_guid = $2
            ORDER BY created_at DESC, id DESC LIMIT $3`,
          [s.adminId, s.company, limit]
        );
      } else {
        r = await db.query(
          `SELECT ${LOG_COLS} FROM reminder_log
            WHERE admin_id = $1 AND company_guid = $2
              AND ledger_guid IN (SELECT ledger_guid FROM user_ledger_permissions WHERE user_id = $3)
            ORDER BY created_at DESC, id DESC LIMIT $4`,
          [s.adminId, s.company, s.user.id, limit]
        );
      }
      res.json({ success: true, data: r.rows.map(publicLog) });
    })
  );

  /* --------------------------------------------------------- retry */
  router.post(
    "/api/reminders/:id/retry",
    auth,
    handle(async (req, res) => {
      const id = idOf(req);
      const s = await scope(req);
      const r = await db.query(
        `SELECT ${LOG_COLS} FROM reminder_log WHERE id = $1 AND admin_id = $2`,
        [id, s.adminId]
      );
      const old = r.rows[0];
      if (!old || old.company_guid !== s.company) {
        throw new HttpError(404, "Reminder not found in the selected company.");
      }
      // Bills and recipient are read again: a bill paid since is left out,
      // a corrected email address is used.
      const names = (old.bills || []).map((b) => b.bill_name);
      const c = await compose(s, {
        ledgerGuid: old.ledger_guid,
        billNames: names,
        templateId: null,
      });
      if (old.template_id) {
        const t = await db.query(
          `SELECT ${TEMPLATE_COLS} FROM reminder_templates WHERE id = $1 AND admin_id = $2`,
          [old.template_id, s.adminId]
        );
        if (t.rows[0]) {
          c.template = t.rows[0];
          c.mail = buildReminderEmail({
            template: c.template,
            party: c.ledger.name,
            company: s.companyName,
            sender: s.user.username || s.user.email || "",
            bills: c.bills,
          });
        }
      }
      if (!c.bills.length) {
        throw new HttpError(409, "None of these bills is pending any more.", "nothing_pending");
      }
      if (!c.recipients.length) {
        throw new HttpError(422, `No valid email address is saved for ${c.ledger.name} in Tally.`, "no_email");
      }
      await rateLimit(s);
      // Only a failed one (or one stuck while sending) — and only once at a time.
      const claim = await db.query(
        `UPDATE reminder_log
            SET status = 'pending', error = NULL, bills = $2::jsonb, total_amount = $3,
                recipients = $4::jsonb, subject = $5, bill_set = $6, updated_at = NOW()
          WHERE id = $1
            AND (status = 'failed'
                 OR (status = 'pending' AND updated_at < NOW() - INTERVAL '15 minutes'))
          RETURNING ${LOG_COLS}`,
        [
          id,
          JSON.stringify(c.bills),
          c.total,
          JSON.stringify(c.recipients),
          c.mail.subject,
          billSetKey(c.bills.map((b) => b.bill_name)),
        ]
      );
      if (!claim.rows[0]) {
        throw new HttpError(409, "Only a reminder that failed can be retried.", "not_failed");
      }
      sendResult(res, await deliver(claim.rows[0], c, s));
    })
  );

  /* ------------------------------------------------------ settings */
  const noTable = (err) => err?.code === "42P01"; // reminder_settings not created yet

  async function loadSettings(adminId, company) {
    try {
      const r = await db.query(
        `SELECT mode, timing, before_days, after_days, repeat_days, send_hour, updated_at
           FROM reminder_settings WHERE admin_id = $1 AND company_guid = $2`,
        [adminId, company]
      );
      return { settings: settingsOf(r.rows[0]), stored: !!r.rows[0], ready: true };
    } catch (err) {
      if (noTable(err)) return { settings: { ...DEFAULT_SETTINGS }, stored: false, ready: false };
      throw err;
    }
  }

  /**
   * Pending receivable bills due for a reminder on [today] by [settings],
   * one group per party: [{ledger_guid, party, emails, reason, bills, total}].
   * [userId]: only the parties that USER login may see.
   */
  async function dueGroups(adminId, company, settings, today, userId = null) {
    const params = [adminId, company];
    let perm = "";
    if (userId) {
      params.push(userId);
      perm = ` AND l.ledger_guid IN (SELECT ledger_guid FROM user_ledger_permissions WHERE user_id = $3)`;
    }
    const r = await db.query(
      `SELECT b.bill_name, b.bill_date, b.due_date, b.pending_amount,
              l.ledger_guid, COALESCE(l.name, b.ledger_name) AS party, l.email
         FROM bills b
         JOIN ledgers l
           ON l.admin_id = b.admin_id AND l.company_guid = b.company_guid
          AND (l.ledger_guid = b.ledger_guid OR (b.ledger_guid IS NULL AND l.name = b.ledger_name))
        WHERE b.admin_id = $1 AND b.company_guid = $2
          AND b.pending_amount > 0 AND b.due_date IS NOT NULL
          AND COALESCE(UPPER(b.bill_type), 'RECEIVABLE') <> 'PAYABLE'${perm}
        ORDER BY b.due_date ASC, b.bill_name ASC`,
      params
    );
    const groups = new Map();
    for (const row of r.rows) {
      const reason = reminderDue(settings, row.due_date, today);
      if (!reason || !row.ledger_guid) continue;
      let g = groups.get(row.ledger_guid);
      if (!g) {
        g = { ledger_guid: row.ledger_guid, party: row.party, emails: recipientsOf(row.email), reasons: new Set(), rows: [], seen: new Set() };
        groups.set(row.ledger_guid, g);
      }
      if (g.seen.has(row.bill_name)) continue;
      g.seen.add(row.bill_name);
      g.reasons.add(reason);
      g.rows.push(row);
    }
    const todayDate = new Date(`${today}T00:00:00Z`);
    return [...groups.values()].map((g) => {
      const bills = normalise(g.rows, todayDate);
      return {
        ledger_guid: g.ledger_guid,
        party: g.party,
        emails: g.emails,
        reason: g.reasons.size > 1 ? "both" : [...g.reasons][0],
        bills,
        total: totalOf(bills),
      };
    });
  }

  router.get(
    "/api/reminders/settings",
    auth,
    handle(async (req, res) => {
      const s = await scope(req);
      const st = await loadSettings(s.adminId, s.company);
      res.json({
        success: true,
        data: st.settings,
        stored: st.stored,
        ready: st.ready,
        can_edit: s.isAdmin,
        email_configured: cfg().mailReady,
      });
    })
  );

  router.put(
    "/api/reminders/settings",
    auth,
    (req, res, next) =>
      req.user?.role === "ADMIN"
        ? next()
        : res.status(403).json({ success: false, message: "Only the admin can change reminder settings." }),
    handle(async (req, res) => {
      const v = validateSettings(req.body);
      if (!v.ok) throw new HttpError(400, v.message);
      const s = await scope(req);
      const x = v.value;
      try {
        await db.query(
          `INSERT INTO reminder_settings
             (admin_id, company_guid, mode, timing, before_days, after_days, repeat_days, send_hour, updated_by, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW())
           ON CONFLICT (admin_id, company_guid) DO UPDATE SET
             mode = EXCLUDED.mode, timing = EXCLUDED.timing, before_days = EXCLUDED.before_days,
             after_days = EXCLUDED.after_days, repeat_days = EXCLUDED.repeat_days,
             send_hour = EXCLUDED.send_hour, updated_by = EXCLUDED.updated_by, updated_at = NOW()`,
          [s.adminId, s.company, x.mode, x.timing, x.before_days, x.after_days, x.repeat_days, x.send_hour, s.user.id]
        );
      } catch (err) {
        if (noTable(err)) throw new HttpError(503, "Reminder settings are not available on the server yet.", "not_ready");
        throw err;
      }
      res.json({ success: true, data: x, stored: true, ready: true, can_edit: true, email_configured: cfg().mailReady });
    })
  );

  router.get(
    "/api/reminders/due",
    auth,
    handle(async (req, res) => {
      const s = await scope(req);
      const st = await loadSettings(s.adminId, s.company);
      const { today } = istNow(now());
      const groups = await dueGroups(s.adminId, s.company, st.settings, today, s.isAdmin ? null : s.user.id);
      res.json({ success: true, today, settings: st.settings, data: groups });
    })
  );

  /* ------------------------------------------- automatic reminders */
  /**
   * Emails every party due for a reminder now, for each account / company
   * in automatic mode whose hour (IST) is now. Never twice the same day for
   * the same party and bills; stops at the account's daily limit. Returns
   * counts (logged by the cron).
   */
  async function runAutomatic() {
    const out = { companies: 0, sent: 0, failed: 0, skipped_no_email: 0, skipped_done: 0, skipped_limit: 0 };
    const { today, hour } = istNow(now());
    let rows;
    try {
      const r = await db.query(
        `SELECT rs.admin_id, rs.company_guid, rs.mode, rs.timing, rs.before_days, rs.after_days,
                rs.repeat_days, rs.send_hour, c.name AS company_name
           FROM reminder_settings rs
           LEFT JOIN companies c ON c.company_guid = rs.company_guid AND c.admin_id = rs.admin_id
          WHERE rs.mode = 'automatic' AND rs.send_hour = $1`,
        [hour]
      );
      rows = r.rows;
    } catch (err) {
      if (noTable(err)) return out;
      throw err;
    }
    if (!rows.length || !cfg().mailReady) return out;
    for (const row of rows) {
      out.companies++;
      const settings = settingsOf(row);
      const s = {
        adminId: row.admin_id,
        company: row.company_guid,
        companyName: row.company_name || "",
        isAdmin: true,
        user: { id: row.admin_id, email: null, username: row.company_name || "" },
      };
      const groups = await dueGroups(s.adminId, s.company, settings, today);
      if (!groups.length) continue;
      const template = await templateFor(s, null);
      const used = await db.query(
        `SELECT COUNT(*)::int AS day FROM reminder_log WHERE admin_id = $1 AND created_at > NOW() - INTERVAL '1 day'`,
        [s.adminId]
      );
      let left = cfg().perDay - (used.rows[0]?.day ?? 0);
      for (const g of groups) {
        if (!g.emails.length) {
          out.skipped_no_email++;
          continue;
        }
        if (left <= 0) {
          out.skipped_limit++;
          continue;
        }
        const set = billSetKey(g.bills.map((b) => b.bill_name));
        const mail = buildReminderEmail({ template, party: g.party, company: s.companyName, sender: s.companyName, bills: g.bills });
        const ins = await db.query(
          `INSERT INTO reminder_log
             (admin_id, company_guid, ledger_guid, ledger_name, template_id, bill_set, bills,
              total_amount, recipients, subject, status, idempotency_key,
              sent_by_user_id, sent_by_email, sent_by_name)
           VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8, $9::jsonb, $10, 'pending', $11, $12, NULL, 'Automatic reminder')
           ON CONFLICT (admin_id, idempotency_key) DO NOTHING
           RETURNING ${LOG_COLS}`,
          [
            s.adminId,
            s.company,
            g.ledger_guid,
            String(g.party).slice(0, 255),
            template.id,
            set,
            JSON.stringify(g.bills),
            g.total,
            JSON.stringify(g.emails),
            mail.subject,
            autoKey(s.company, g.ledger_guid, set, today),
            s.adminId,
          ]
        );
        if (!ins.rows[0]) {
          out.skipped_done++;
          continue;
        }
        left--;
        const r = await deliver(ins.rows[0], { recipients: g.emails, mail }, s);
        if (r.code) out.failed++;
        else out.sent++;
      }
    }
    return out;
  }
  router.runAutomatic = runAutomatic;

  return router;
}
