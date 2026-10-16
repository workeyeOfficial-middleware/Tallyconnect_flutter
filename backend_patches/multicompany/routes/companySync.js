/* =========================================================
   MULTI-COMPANY SYNC routes — wires the database, login check and the
   licence (company limit + heartbeat, same as /company/select) into the
   router (see utils/companySyncRouter.js). Mounted at /company.
========================================================= */
import pool from "../db.js";
import requireAuth from "../middleware/requireAuth.js";
import { sendHeartbeat } from "../utils/licenseheartbeat.js";
import { createCompanySyncRouter } from "../utils/companySyncRouter.js";

const PRODUCT_ID = "695902cfc240b17f16c3d716";
const lmsUrl = () => (process.env.LMS_URL || "http://lms-backend:4000").replace(/\/$/, "");

async function activeLicense(email) {
  const r = await fetch(`${lmsUrl()}/api/external/actve-license/${encodeURIComponent(email)}?productId=${PRODUCT_ID}`, {
    headers: { "Content-Type": "application/json", "x-api-key": process.env.LICENSE_INTERNAL_KEY },
  });
  return (await r.json())?.activeLicense || null;
}

/** The plan's company limit (null: no limit / licence not reachable). */
async function getCompanyLimit(email) {
  try {
    const lic = await activeLicense(email);
    const f = lic?.licenseType?.features || lic?.licenseTypeId?.features;
    const v = f && typeof f === "object" ? f["company-limit"] : null;
    return v === undefined || v === null ? null : Number(v);
  } catch (e) {
    console.error("License fetch failed:", e.message);
    return null;
  }
}

/** Same heartbeat as /company/select: +1 per newly selected company. */
async function onCompaniesAdded(user, added) {
  const lic = await activeLicense(user.email);
  if (lic?._id && lic?.ownerUserId) {
    await sendHeartbeat({ licenseId: lic._id, adminId: lic.ownerUserId, features: [{ slug: "company-limit", value: added }] });
  }
}

export default createCompanySyncRouter({ db: pool, auth: requireAuth, getCompanyLimit, onCompaniesAdded });
