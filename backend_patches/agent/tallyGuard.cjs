// =====================================================================
//  TALLY GUARD — keeps the Agent from piling requests onto a stuck Tally
//  ---------------------------------------------------------------------
//  Tally answers one request at a time and keeps working on a request even
//  after the Agent stopped waiting for it. Sending more requests then only
//  queues more work behind it (seen live: ~40 requests sent to a stuck
//  Tally over an hour until it stopped listening). So:
//
//   • Circuit breaker: the first request that times out (or finds Tally
//     unreachable) "trips" the guard. From then on NO request is sent —
//     each is refused at once with code TALLY_BUSY — except a tiny check
//     (`ping`) at most every `pingEveryMs`. Once Tally answers the check
//     quickly, it is left to rest `restMs` more, then requests resume.
//   • Gap: after every request the next one waits a little, longer after a
//     slow request (gap = duration × gapFactor, between gapMinMs and
//     gapMaxMs), so Tally's own screen stays usable during a sync.
//
//  attach(axiosInstance) installs both on every request of that instance
//  (normal, streamed, health checks). A request with `tcGuardBypass: true`
//  in its config is never held or refused (the guard's own check, the
//  Agent UI's "test connection").
// =====================================================================
"use strict";

const DEFAULTS = {
  pingEveryMs: 15000,
  restMs: 120000,
  gapMinMs: 300,
  gapFactor: 0.5,
  gapMaxMs: 10000,
};

/** A timeout, or Tally not reachable / connection dropped. */
function isTripError(err) {
  if (!err || err.code === "TALLY_BUSY") return false;
  const code = String(err.code || "");
  if (["ECONNABORTED", "ETIMEDOUT", "ECONNREFUSED", "ECONNRESET", "EPIPE"].includes(code)) return true;
  return /timeout|socket hang up/i.test(String(err.message || ""));
}

function busyError(since) {
  const e = new Error(
    `Tally is busy or not running — request not sent (Tally stopped answering at ${new Date(since).toLocaleTimeString()}; waiting for it to answer again)`
  );
  e.code = "TALLY_BUSY";
  return e;
}

/**
 * @param {object} deps
 * @param {() => Promise<boolean>} deps.ping  true: Tally answered a tiny request quickly
 * @param {() => number} [deps.clock]
 * @param {(ms: number) => Promise<void>} [deps.sleep]
 * @param {(msg: string) => void} [deps.log]
 * @param {object} [deps.config]  see DEFAULTS
 */
function createTallyGuard({ ping, clock = () => Date.now(), sleep = (ms) => new Promise((r) => setTimeout(r, ms)), log = () => {}, config = {} }) {
  const cfg = { ...DEFAULTS, ...config };
  let state = "closed"; // closed | open | resting
  let since = 0; // when it tripped
  let nextPingAt = 0;
  let restUntil = 0;
  let pinging = null;
  let trips = 0;
  let lastEndAt = 0;
  let gapMs = 0;

  function trip(reason) {
    if (state !== "closed") return;
    state = "open";
    trips += 1;
    since = clock();
    nextPingAt = since + cfg.pingEveryMs;
    log(
      `⛔ Tally did not answer (${reason}). The Agent sends nothing more to Tally until it answers again ` +
        `(a tiny check every ${Math.round(cfg.pingEveryMs / 1000)} s, then ${Math.round(cfg.restMs / 1000)} s of rest).`
    );
  }

  /**
   * True when requests may be sent. While tripped: runs the tiny check when
   * it is due (never two at once), never waits.
   */
  async function ready() {
    if (state === "closed") return true;
    if (state === "resting") {
      if (clock() < restUntil) return false;
      state = "closed";
      log(`✅ Tally rested — requests resume (it had stopped answering for ${Math.round((clock() - since) / 1000)} s).`);
      return true;
    }
    if (pinging) {
      await pinging;
      return state === "closed";
    }
    if (clock() < nextPingAt) return false;
    pinging = (async () => {
      let ok = false;
      try {
        ok = await ping();
      } catch (e) {
        ok = false;
      }
      if (state !== "open") return;
      if (ok) {
        if (cfg.restMs > 0) {
          state = "resting";
          restUntil = clock() + cfg.restMs;
          log(`🟡 Tally answers again — resting it ${Math.round(cfg.restMs / 1000)} s before the next request.`);
        } else {
          state = "closed";
          log("✅ Tally answers again — requests resume.");
        }
      } else {
        nextPingAt = clock() + cfg.pingEveryMs;
      }
    })();
    try {
      await pinging;
    } finally {
      pinging = null;
    }
    return state === "closed";
  }

  /**
   * Waits (at most [maxMs]) until requests may be sent again: the tiny
   * checks run as usual, then Tally's rest. True when Tally is ready; false
   * when it did not recover in time (the caller then leaves it for later).
   */
  async function waitUntilReady(maxMs, { tickMs = 5000 } = {}) {
    const end = clock() + Math.max(0, maxMs || 0);
    for (;;) {
      if (await ready()) return true;
      const left = end - clock();
      if (left <= 0) return false;
      await sleep(Math.min(tickMs, left));
    }
  }

  /** Waits out the gap after the previous request. */
  async function beforeRequest() {
    const wait = lastEndAt + gapMs - clock();
    if (wait > 0) await sleep(wait);
    return clock();
  }

  function afterRequest(startedAt) {
    lastEndAt = clock();
    const took = typeof startedAt === "number" ? Math.max(0, lastEndAt - startedAt) : 0;
    gapMs = Math.min(cfg.gapMaxMs, Math.max(cfg.gapMinMs, took * cfg.gapFactor));
  }

  /** Installs the guard on an axios instance. */
  function attach(instance) {
    instance.interceptors.request.use(async (config) => {
      if (config.tcGuardBypass) return config;
      if (!(await ready())) {
        const e = busyError(since);
        e.config = config;
        throw e;
      }
      config.tcStartedAt = await beforeRequest();
      return config;
    });
    instance.interceptors.response.use(
      (res) => {
        if (res && res.config && !res.config.tcGuardBypass) afterRequest(res.config.tcStartedAt);
        return res;
      },
      (err) => {
        const c = (err && err.config) || {};
        if (!c.tcGuardBypass && err && err.code !== "TALLY_BUSY") {
          afterRequest(c.tcStartedAt);
          if (isTripError(err)) trip(err.code === "ECONNREFUSED" ? "Tally is not reachable" : String(err.message || err.code));
        }
        return Promise.reject(err);
      }
    );
    return instance;
  }

  return {
    attach,
    ready,
    waitUntilReady,
    trip,
    beforeRequest,
    afterRequest,
    isClosed: () => state === "closed",
    get state() {
      return state;
    },
    get trips() {
      return trips;
    },
    get since() {
      return since;
    },
    get gapMs() {
      return gapMs;
    },
  };
}

module.exports = { createTallyGuard, isTripError, busyError, DEFAULTS };
