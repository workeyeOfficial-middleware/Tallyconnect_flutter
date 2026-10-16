// =====================================================================
//  SYNC PROGRESS — what the Sync Status screen shows (read-only)
//  ---------------------------------------------------------------------
//  Driven only by real events from syncAllData: a run starts with its
//  planned steps, each step reports when it starts and ends, and the
//  voucher step (the long one) reports its real window count. The
//  percentage is (finished steps + the current step's real share) /
//  planned steps; while a sync runs it never shows 100% — that is only
//  reached when the run actually finishes. Nothing here changes what is
//  synced or in which order.
// =====================================================================
"use strict";

function createSyncProgress(now = () => Date.now()) {
  let s = {
    state: "idle", // idle | syncing | completed | failed | paused | waiting
    company: null,
    steps: [],
    done: new Set(),
    failed: new Set(),
    current: null,
    sub: null, // {done, total} of the current step (real counts)
    startedAt: null,
    finishedAt: null,
    error: null,
    nextAt: null,
    lastPercent: 0,
  };

  function raw() {
    if (!s.steps.length) return 0;
    let n = 0;
    for (const x of s.steps) if (s.done.has(x)) n++;
    if (s.current && !s.done.has(s.current) && s.sub && s.sub.total > 0) {
      n += Math.min(1, Math.max(0, s.sub.done / s.sub.total));
    }
    return (n / s.steps.length) * 100;
  }

  function percent() {
    if (s.state === "completed") return 100;
    if (s.state === "syncing") return Math.min(99, Math.floor(raw()));
    return Math.floor(s.lastPercent);
  }

  return {
    /** A company's run begins with these steps (in order). */
    start(company, steps) {
      s = {
        ...s,
        state: "syncing",
        company: company || null,
        steps: [...steps],
        done: new Set(),
        failed: new Set(),
        current: null,
        sub: null,
        startedAt: now(),
        finishedAt: null,
        error: null,
        nextAt: null,
        lastPercent: 0,
      };
    },
    step(label) {
      if (s.state !== "syncing") return;
      s.current = label;
      s.sub = null;
    },
    stepDone(label, ok = true) {
      if (s.state !== "syncing") return;
      s.done.add(label);
      if (!ok) s.failed.add(label);
      if (s.current === label) {
        s.current = null;
        s.sub = null;
      }
      s.lastPercent = raw();
    },
    /** Real sub-progress of the current step (e.g. voucher windows). */
    sub(done, total) {
      if (s.state !== "syncing" || !s.current) return;
      if (!(total > 0)) return;
      s.sub = { done: Math.max(0, Math.min(done, total)), total };
      s.lastPercent = raw();
    },
    finish(ok, error = null) {
      if (s.state !== "syncing" && ok) return;
      s.lastPercent = ok ? 100 : raw();
      s.state = ok ? "completed" : "failed";
      s.error = ok ? null : String(error || "Sync failed");
      s.finishedAt = now();
      s.current = null;
      s.sub = null;
    },
    /** Failure before a run could start (e.g. Tally not reachable). */
    fail(company, error) {
      s.state = "failed";
      if (company) s.company = company;
      s.error = String(error || "Sync failed");
      s.finishedAt = now();
      s.current = null;
      s.sub = null;
    },
    pause() {
      if (s.state !== "syncing") return;
      s.lastPercent = raw();
      s.state = "paused";
      s.current = null;
      s.sub = null;
    },
    /** Nothing to do yet: the plan's sync interval has not passed. */
    waiting(company, nextAt) {
      if (s.state === "syncing") return;
      s.state = "waiting";
      s.company = company || s.company;
      s.nextAt = nextAt || null;
    },
    snapshot() {
      return {
        state: s.state,
        company: s.company,
        percent: percent(),
        step: s.current || null,
        stepIndex: s.steps.length ? s.done.size + (s.current ? 1 : 0) : 0,
        stepCount: s.steps.length,
        failedSteps: s.failed.size,
        startedAt: s.startedAt,
        finishedAt: s.finishedAt,
        nextAt: s.nextAt,
        error: s.error,
      };
    },
  };
}

module.exports = { createSyncProgress };
