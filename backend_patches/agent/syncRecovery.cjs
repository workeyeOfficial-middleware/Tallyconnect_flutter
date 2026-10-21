// =====================================================================
//  SYNC RECOVERY — when Tally stops answering during a sync
//  ---------------------------------------------------------------------
//  • Wait, then continue: a step that made Tally stop answering waits for
//    Tally to recover (the guard's checks + rest, within a time budget per
//    run) and runs once more from its own saved position, then the sync
//    goes on with the next steps and companies in the same run.
//  • Remember what freezes Tally: a step that froze Tally again after the
//    wait (or did not let it recover) is postponed for that company, longer
//    each time (30 min, 1 h, 2 h … up to 12 h), instead of being sent again
//    every few minutes. The rest of the sync still runs; the company's
//    position is not advanced while a step is postponed, so nothing it would
//    have read is skipped.
//  • Fair turns: each run starts with the company after the last one that
//    finished, and a company whose sync made Tally stop answering goes last
//    for a while — one heavy company can no longer keep the others from
//    syncing.
//  Pure helpers (no Tally / disk access) so they can be tested alone.
// =====================================================================
"use strict";

const MIN = 60 * 1000;

const DEFAULTS = {
  /** Longest wait for Tally to recover after one freeze. */
  recoverWaitMs: 10 * MIN,
  /** Longest total waiting in one run (all companies). */
  runBudgetMs: 30 * MIN,
  /** First postponement of a step that keeps freezing Tally. */
  backoffFirstMs: 30 * MIN,
  /** Longest postponement. */
  backoffMaxMs: 12 * 60 * MIN,
  /** A company that froze Tally goes last for this long. */
  trippedLastMs: 6 * 60 * MIN,
};

/**
 * The companies in this run's order: starting after [state.lastDone] (the
 * last company that finished), companies that froze Tally recently last.
 * Stable otherwise; the list itself is not changed.
 */
function orderCompanies(companies, state = {}, now = Date.now(), cfg = DEFAULTS) {
  const list = Array.isArray(companies) ? [...companies] : [];
  if (list.length < 2) return list;
  const guidOf = (c) => String((c && c.company_guid) || "");
  const i = list.findIndex((c) => guidOf(c) === String(state.lastDone || ""));
  const rotated = i < 0 ? list : [...list.slice(i + 1), ...list.slice(0, i + 1)];
  const tripped = state.tripped || {};
  const recent = (c) => {
    const at = Number(tripped[guidOf(c)]);
    return Number.isFinite(at) && now - at < cfg.trippedLastMs;
  };
  return [...rotated.filter((c) => !recent(c)), ...rotated.filter(recent)];
}

/** The order state after a company's sync ([cutShort]: Tally stopped answering). */
function afterCompany(state = {}, guid, cutShort, now = Date.now()) {
  const tripped = { ...(state.tripped || {}) };
  if (cutShort) {
    tripped[guid] = now;
    return { ...state, tripped };
  }
  delete tripped[guid];
  return { ...state, lastDone: guid, tripped };
}

/** Whether [step] is postponed now: {blocked, until}. */
function stepBlocked(backoff = {}, step, now = Date.now()) {
  const b = backoff[step];
  const until = b && Number(b.until);
  return { blocked: Number.isFinite(until) && now < until, until: until || 0 };
}

/** [step] froze Tally again: postponed, longer each time. Returns the new map. */
function recordStepFreeze(backoff = {}, step, now = Date.now(), cfg = DEFAULTS) {
  const count = ((backoff[step] && Number(backoff[step].count)) || 0) + 1;
  const ms = Math.min(cfg.backoffMaxMs, cfg.backoffFirstMs * 2 ** (count - 1));
  return { ...backoff, [step]: { count, until: now + ms, at: now } };
}

/** [step] ran fine: forgets its postponements. Returns the new map. */
function clearStep(backoff = {}, step) {
  if (!backoff[step]) return backoff;
  const next = { ...backoff };
  delete next[step];
  return next;
}

/**
 * Runs one sync step with recovery:
 *  - postponed step → not run ({postponed});
 *  - Tally busy before it and does not recover → not run ({skipped});
 *  - the step makes Tally stop answering → wait for it, then the step once
 *    more (it continues from its own saved position); froze again, or Tally
 *    did not recover → postponed for next time ({froze});
 *  - a fine run forgets earlier postponements.
 * `froze` / `skipped` / `postponed` mean the company's position must not be
 * advanced this run.
 *
 * @param {object} o
 * @param {string} o.label
 * @param {() => Promise<void>} o.fn          the step
 * @param {{ready: () => Promise<boolean>, trips: number}} o.guard
 * @param {(why: string) => Promise<boolean>} o.wait   waits for Tally (true: ready)
 * @param {() => object} o.loadBackoff
 * @param {(b: object) => void} o.saveBackoff
 * @param {(msg: string) => void} [o.log]
 * @param {() => number} [o.now]
 */
async function runStepWithRecovery({ label, fn, guard, wait, loadBackoff, saveBackoff, log = () => {}, now = Date.now }) {
  const hold = stepBlocked(loadBackoff(), label, now());
  if (hold.blocked) {
    log(`⏭️ ${label} postponed until ${new Date(hold.until).toLocaleTimeString()} — it made Tally stop answering before. The rest of the sync goes on; this company's position is kept.`);
    return { ok: false, postponed: true };
  }
  if (!(await guard.ready()) && !(await wait(`Tally is busy before ${label}`))) {
    return { ok: false, skipped: true };
  }
  const once = async () => {
    const before = guard.trips;
    let ok = true;
    try {
      await fn();
    } catch (err) {
      ok = false;
      log(`⚠️ ${label} failed (non-blocking, continuing with the next step): ${err && err.message}`);
    }
    return { ok, froze: guard.trips > before };
  };
  let r = await once();
  if (r.froze) {
    if (await wait(`Tally stopped answering during ${label}`)) {
      log(`🔁 ${label}: continuing from where it stopped.`);
      r = await once();
      if (r.froze) {
        const b = recordStepFreeze(loadBackoff(), label, now());
        saveBackoff(b);
        log(`⏸️ ${label} made Tally stop answering again — postponed until ${new Date(b[label].until).toLocaleTimeString()} for this company.`);
      }
    } else {
      const b = recordStepFreeze(loadBackoff(), label, now());
      saveBackoff(b);
      log(`⏸️ ${label} postponed until ${new Date(b[label].until).toLocaleTimeString()} for this company (Tally did not recover after it).`);
    }
  }
  if (!r.froze && r.ok) {
    const cur = loadBackoff();
    if (cur[label]) saveBackoff(clearStep(cur, label));
  }
  return { ok: r.ok && !r.froze, froze: r.froze };
}

module.exports = { DEFAULTS, orderCompanies, afterCompany, stepBlocked, recordStepFreeze, clearStep, runStepWithRecovery };
