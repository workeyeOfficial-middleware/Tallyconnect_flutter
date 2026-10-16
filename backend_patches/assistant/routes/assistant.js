/* =========================================================
   AI FINANCIAL ASSISTANT routes — wires the real database, login check
   and AI provider adapters into the router (see utils/assistantRouter.js).
========================================================= */
import pool from "../db.js";
import requireAuth from "../middleware/requireAuth.js";
import { createAdapters } from "../utils/aiProviders.js";
import { createAssistantRouter } from "../utils/assistantRouter.js";

export default createAssistantRouter({ db: pool, auth: requireAuth, adapters: createAdapters() });
