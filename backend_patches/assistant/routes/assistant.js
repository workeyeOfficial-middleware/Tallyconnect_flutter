/* =========================================================
   AI FINANCIAL ASSISTANT routes — wires the real database, login check
   and Gemini client into the router (see utils/assistantRouter.js).
========================================================= */
import pool from "../db.js";
import requireAuth from "../middleware/requireAuth.js";
import { gemini } from "../utils/geminiClient.js";
import { createAssistantRouter } from "../utils/assistantRouter.js";

export default createAssistantRouter({ db: pool, auth: requireAuth, gemini });
