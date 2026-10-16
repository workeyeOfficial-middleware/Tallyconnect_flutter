/* =========================================================
   MOBILE CONTRA ENTRY route (see utils/contraCore.js).
   Mounted at /api/mobile-voucher-command next to mobileVoucherCommand.js,
   which is not changed:
     POST /api/mobile-voucher-command/contra/create
========================================================= */
import express from "express";
import pool from "../../db.js";
import requireAuth from "../../middleware/requireAuth.js";
import { createNotification } from "../../utils/notification.js";
import { createMobileNotificationForAdmin } from "../../utils/mobileNotification.js";
import { queueContra } from "../../utils/contraCore.js";

const router = express.Router();

router.post("/contra/create", requireAuth, async (req, res) => {
  try {
    const r = await queueContra({
      db: pool,
      adminId: req.user.adminId,
      body: req.body,
      notify: createNotification,
      notifyMobile: createMobileNotificationForAdmin,
    });
    return res.status(r.status).json(r.json);
  } catch (err) {
    console.error("Mobile Contra create error:", err);
    return res.status(400).json({ success: false, message: err.message });
  }
});

export default router;
