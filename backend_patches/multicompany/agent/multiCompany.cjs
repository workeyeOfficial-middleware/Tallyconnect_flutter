// =====================================================================
//  MULTI-COMPANY SYNC (opt-in; off = exactly the old one-company sync)
//  ---------------------------------------------------------------------
//  On by default (Agent → Companies → "Sync all enabled companies" off,
//  or MULTI_COMPANY=off, gives the old one-company sync). Every sync runs
//  each company ENABLED in the backend
//  (/company/agent-config), one after another, with the usual steps. Per
//  company:
//    - it must be open in Tally (exact GUID) — else "not open", skipped;
//    - a backend lock (/company/sync-lock) makes sure only one Agent of
//      the account syncs it at a time; renewed while the company syncs;
//    - progress goes to the backend (/company/sync-progress) every 15 s
//      and at the end, so the Agent UI and the app show each company.
//  Network problems here never stop a sync: an older backend without
//  these routes simply means "no lock, no progress" (old behaviour).
// =====================================================================
"use strict";

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const TICK_MS = 15000;
const RENEW_EVERY = 4; // ticks (≈ 60 s)
const LOCK_TTL_SEC = 180;

/** A stable id for this Agent install (lock owner), kept in [dir]. */
function agentIdFrom(dir, hostname = "agent") {
  const f = path.join(dir, "agent-id.txt");
  try {
    const v = fs.readFileSync(f, "utf8").trim();
    if (/^[A-Za-z0-9._:-]{4,100}$/.test(v)) return v;
  } catch (e) {
    /* first run */
  }
  const host = String(hostname || "agent").replace(/[^A-Za-z0-9.-]/g, "").slice(0, 40) || "agent";
  const id = `${host}-${crypto.randomBytes(6).toString("hex")}`;
  try {
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(f, id);
  } catch (e) {
    /* read-only: still works for this run */
  }
  return id;
}

/** The on/off switch: MULTI_COMPANY env wins, else the saved setting. */
function createSwitch(dir, env = process.env) {
  const f = path.join(dir, "multi-company.json");
  return {
    isOn() {
      const e = String(env.MULTI_COMPANY || "").toLowerCase();
      if (["on", "1", "true", "yes"].includes(e)) return true;
      if (["off", "0", "false", "no"].includes(e)) return false;
      try {
        return JSON.parse(fs.readFileSync(f, "utf8")).on !== false;
      } catch (err) {
        return true; // nothing saved yet: on by default
      }
    },
    fromEnv() {
      return String(env.MULTI_COMPANY || "").trim() !== "";
    },
    set(on) {
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(f, JSON.stringify({ on: !!on, at: new Date().toISOString() }));
      return !!on;
    },
  };
}

/**
 * @param {object} d
 * @param {(path: string) => Promise<{data: any}>} d.get
 * @param {(path: string, body: object) => Promise<{data: any}>} d.post
 * @param {string} d.agentId
 * @param {() => {percent?: number, step?: string}} [d.snapshot]   current progress
 * @param {(msg: string) => void} [d.log]
 * @param {{setInterval: Function, clearInterval: Function}} [d.timers]
 */
function createMultiCompany({ get, post, put = async () => ({ data: {} }), agentId, snapshot = () => ({}), log = () => {}, timers = { setInterval, clearInterval } }) {
  const status = new Map(); // company_guid → {state, step, percent, error, at}
  let ticker = null;
  let current = null;
  let lockLost = false;

  const statusOf = (e) => e?.response?.status;

  async function report(guid, state, extra = {}) {
    const body = { company_guid: guid, state, agent_id: agentId, ...extra };
    status.set(guid, { state, step: extra.step || null, percent: extra.percent ?? null, error: extra.error || null, at: Date.now() });
    try {
      await post("/company/sync-progress", body);
    } catch (e) {
      if (statusOf(e) !== 404) log(`⚠️ Could not send progress for ${guid}: ${e.message}`);
    }
  }

  /** Enabled companies in sync order, or null (older backend: use the old way). */
  async function enabledCompanies() {
    try {
      const r = await get("/company/agent-config");
      const list = Array.isArray(r.data?.companies) ? r.data.companies : [];
      return list
        .filter((c) => c.enabled)
        .map((c) => ({ company_guid: c.company_guid, name: c.name, startingFrom: c.starting_from || null }));
    } catch (e) {
      if (statusOf(e) === 404) return null;
      throw e;
    }
  }

  function stopTicker() {
    if (ticker) timers.clearInterval(ticker);
    ticker = null;
  }

  /** Lock + start reporting. {ok:false, heldBy} when another Agent has it. */
  async function begin(guid) {
    lockLost = false;
    try {
      await post("/company/sync-lock", { company_guid: guid, agent_id: agentId, action: "acquire", ttl_sec: LOCK_TTL_SEC });
    } catch (e) {
      if (statusOf(e) === 409) {
        const heldBy = e.response?.data?.held_by || null;
        await report(guid, "locked", { step: heldBy ? `Synced by ${heldBy}` : null });
        return { ok: false, heldBy };
      }
      // Older backend (404) or not reachable: sync as before, without a lock.
      if (statusOf(e) !== 404) log(`⚠️ Sync lock not available (${e.message}); syncing without it.`);
    }
    current = guid;
    await report(guid, "syncing", { percent: 0 });
    let n = 0;
    ticker = timers.setInterval(async () => {
      n++;
      const s = snapshot() || {};
      await report(guid, "syncing", { percent: s.percent ?? null, step: s.step || null });
      if (n % RENEW_EVERY === 0) {
        try {
          await post("/company/sync-lock", { company_guid: guid, agent_id: agentId, action: "renew", ttl_sec: LOCK_TTL_SEC });
        } catch (e) {
          if (statusOf(e) === 409 && !lockLost) {
            lockLost = true;
            log(`⚠️ The sync lock for ${guid} was taken over by another Agent.`);
          }
        }
      }
    }, TICK_MS);
    return { ok: true };
  }

  /**
   * Companies open in Tally that were never switched on or off are
   * switched ON (sync is on by default). A company the user switched off
   * stays off. The server applies the plan's company limit.
   * @returns {Promise<{added: string[], limited: boolean}>}
   */
  async function autoEnable(openGuids) {
    const open = new Set(openGuids || []);
    let cfg;
    try {
      cfg = (await get("/company/agent-config")).data;
    } catch (e) {
      return { added: [], limited: false };
    }
    const fresh = (cfg?.companies || []).filter((c) => !c.selected && open.has(c.company_guid));
    if (!fresh.length) return { added: [], limited: false };
    const added = [];
    let limited = false;
    // One at a time, so the plan limit lets in as many as it allows.
    for (const c of fresh) {
      try {
        await put("/company/selection", { companies: [{ company_guid: c.company_guid, enabled: true }] });
        added.push(c.name || c.company_guid);
      } catch (e) {
        if (statusOf(e) === 403) {
          limited = true;
          break;
        }
        if (statusOf(e) !== 404) log(`⚠️ Could not switch on ${c.name}: ${e.message}`);
        break;
      }
    }
    if (added.length) log(`🏢 New companies switched on for sync: ${added.join(", ")}`);
    if (limited) log("ℹ️ Your plan's company limit is reached: other new companies stay off (Agent → Companies).");
    return { added, limited };
  }

  /** Stop reporting, final state, release the lock. */
  async function end(guid, { ok, error } = {}) {
    stopTicker();
    current = null;
    await report(guid, ok ? "synced" : "error", ok ? { percent: 100 } : { error: String(error || "Sync failed").slice(0, 500) });
    try {
      await post("/company/sync-lock", { company_guid: guid, agent_id: agentId, action: "release" });
    } catch (e) {
      /* expires on its own */
    }
  }

  /** Stopped (or left early): back to idle, lock released. */
  async function abort(guid, reason = "Stopped") {
    stopTicker();
    current = null;
    await report(guid, "idle", { step: reason });
    try {
      await post("/company/sync-lock", { company_guid: guid, agent_id: agentId, action: "release" });
    } catch (e) {
      /* expires on its own */
    }
  }

  return {
    enabledCompanies,
    autoEnable,
    begin,
    end,
    abort,
    report,
    current: () => current,
    lockLost: () => lockLost,
    status: () => Object.fromEntries(status),
  };
}

module.exports = { createMultiCompany, createSwitch, agentIdFrom, TICK_MS, LOCK_TTL_SEC };
