import express from "express";
import pool from "../db.js";
import requireAuth from "../middleware/requireAuth.js";
import { createMobileNotificationForAdmin } from "../utils/mobileNotification.js";
import { hasEditColumns, isTallyGuid, retryEntry } from "../utils/mobileEdits.js";

const router = express.Router();

/* =========================================
   AGENT: FETCH PENDING MOBILE VOUCHERS
========================================= */
router.get("/pending", requireAuth, async (req, res) => {
  const { company_guid } = req.query;

  if (!company_guid) {
    return res.status(400).json({
      message: "company_guid required"
    });
  }

  const result = await pool.query(
    `
    SELECT
      id,
      action,
      payload
    FROM mobile_sync_queue
    WHERE status = 'pending'
      AND entity_type = 'VOUCHER'
      AND company_guid = $1
    ORDER BY created_at ASC
    LIMIT 10
    `,
    [company_guid]
  );

  res.json(result.rows);
});


/* =========================================
   MOBILE APP: FETCH QUEUE ACTIVITY / HISTORY
========================================= */
router.get("/activity", requireAuth, async (req, res) => {
  try {
    const { company_guid } = req.query;

    if (!company_guid) {
      return res.status(400).json({
        message: "company_guid required"
      });
    }

    const result = await pool.query(
      `
      SELECT
        id,
        entity_type,
        action,
        status,
        payload,
        error,
        created_at,
        processed_at${
          (await hasEditColumns(pool))
            ? ",\n        tally_guid, target_guid, edit_of, created_by, retry_count, updated_at"
            : ""
        }
      FROM mobile_sync_queue
      WHERE entity_type = 'VOUCHER'
        AND company_guid = $1
      ORDER BY created_at DESC
      LIMIT 100
      `,
      [company_guid]
    );

    res.json(result.rows);
  } catch (error) {
    console.error("Failed to fetch mobile queue activity:", error);

    res.status(500).json({
      message: "Failed to fetch queue activity"
    });
  }
});

/* =========================================
   AGENT: MARK PROCESSING
========================================= */
router.post("/:id/processing", requireAuth, async (req, res) => {
  await pool.query(
    `
    UPDATE mobile_sync_queue
    SET status = 'processing'${(await hasEditColumns(pool)) ? ", updated_at = NOW()" : ""}
    WHERE id = $1
    `,
    [req.params.id]
  );

  res.json({ success: true });
});

/* =========================================
   AGENT: MARK SUCCESS
========================================= */
router.post("/:id/success", requireAuth, async (req, res) => {
  // The Agent sends Tally's GUID of a voucher it created (needed to alter
  // it later); an older Agent sends nothing.
  const tallyGuid = isTallyGuid(req.body?.tally_guid) ? String(req.body.tally_guid).trim() : null;
  const cols = await hasEditColumns(pool);
  await pool.query(
    `
    UPDATE mobile_sync_queue
    SET
      status = 'success',
      processed_at = now()${cols ? ", error = NULL, updated_at = NOW(), tally_guid = COALESCE($2, tally_guid, target_guid)" : ""}
    WHERE id = $1
    `,
    cols ? [req.params.id, tallyGuid] : [req.params.id]
  );

  res.json({ success: true });
});

/* =========================================
   AGENT: MARK FAILED
========================================= */
router.post("/:id/failed", requireAuth, async (req, res) => {
  const { error } = req.body;

  const result = await pool.query(
    `
    UPDATE mobile_sync_queue
    SET
      status = 'failed',
      error = $2${(await hasEditColumns(pool)) ? ", updated_at = NOW()" : ""}
    WHERE id = $1
    RETURNING admin_id, entity_type, error
    `,
    [
      req.params.id,
      error || "Unknown error"
    ]
  );

  const failed = result.rows[0];
  if (failed) {
    createMobileNotificationForAdmin({
      type: "entry_failed",
      message: `Mobile ${failed.entity_type || "entry"} sync failed: ${failed.error || "Unknown error"}`,
      adminId: failed.admin_id,
    }).catch((e) => console.error("mobile entry_failed notify error:", e.message));
  }

  res.json({ success: true });
});

/* =========================================
   MOBILE APP: RETRY A FAILED (OR STUCK) ENTRY
   Only this account's entries in the active company; a team login only
   its own; never one that is already in Tally (utils/mobileEdits.js).
========================================= */
router.post("/:id/retry", requireAuth, async (req, res) => {
  try {
    const r = await retryEntry(pool, req.user, req.params.id);
    res.status(r.status).json(r.json);
  } catch (err) {
    if (err?.status && err?.message) {
      return res.status(err.status).json({ success: false, code: err.code, message: err.message });
    }
    console.error("mobile entry retry error:", err);
    res.status(500).json({ success: false, message: "Could not retry the entry." });
  }
});

export default router;