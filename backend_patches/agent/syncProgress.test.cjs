// Tests for the Agent's sync progress tracker (node --test), run against
// tally-agent/lib/syncProgress.cjs. The percentage must only move on real
// events and never reach 100% before the run really finishes.
//   AGENT_DIR=<path to tally-agent> node --test syncProgress.test.cjs
"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const AGENT_DIR = process.env.AGENT_DIR || path.join(__dirname, "..", "..", "..", "tally-agent");
const { createSyncProgress } = require(path.join(AGENT_DIR, "lib", "syncProgress.cjs"));

const STEPS = ["a", "b", "vouchers", "d"];

test("idle before any run: 0%, nothing invented", () => {
  const p = createSyncProgress(() => 1000);
  assert.deepEqual(
    { state: p.snapshot().state, percent: p.snapshot().percent, stepCount: p.snapshot().stepCount },
    { state: "idle", percent: 0, stepCount: 0 }
  );
});

test("steps and real sub-progress drive the %; never 100 while syncing", () => {
  const p = createSyncProgress(() => 1000);
  p.start("Ravi Traders", STEPS);
  assert.equal(p.snapshot().percent, 0);
  p.step("a");
  assert.equal(p.snapshot().percent, 0); // started, not finished
  p.stepDone("a");
  assert.equal(p.snapshot().percent, 25);
  p.step("b");
  p.stepDone("b");
  p.step("vouchers");
  p.sub(30, 120); // 30 of 120 windows done
  assert.equal(p.snapshot().percent, Math.floor(((2 + 0.25) / 4) * 100)); // 56
  p.sub(120, 120);
  p.stepDone("vouchers");
  p.step("d");
  p.stepDone("d");
  // Every step done, but the run has not finished yet: 99, not 100.
  assert.equal(p.snapshot().percent, 99);
  assert.equal(p.snapshot().state, "syncing");
  p.finish(true);
  assert.deepEqual(
    [p.snapshot().state, p.snapshot().percent, p.snapshot().company],
    ["completed", 100, "Ravi Traders"]
  );
});

test("sub-progress outside a step, or bad totals, are ignored", () => {
  const p = createSyncProgress();
  p.start("X", STEPS);
  p.sub(5, 10); // no current step
  assert.equal(p.snapshot().percent, 0);
  p.step("a");
  p.sub(5, 0);
  assert.equal(p.snapshot().percent, 0);
  p.sub(50, 10); // clamped
  assert.equal(p.snapshot().percent, 25); // 10 of 10 = this step's full share
});

test("a failed step still completes the run, counted as an issue", () => {
  const p = createSyncProgress();
  p.start("X", ["a", "b"]);
  p.step("a");
  p.stepDone("a", false);
  p.step("b");
  p.stepDone("b");
  p.finish(true);
  assert.equal(p.snapshot().state, "completed");
  assert.equal(p.snapshot().failedSteps, 1);
});

test("failure keeps the % reached and the reason; pause keeps the %", () => {
  const p = createSyncProgress(() => 2000);
  p.start("X", STEPS);
  p.step("a");
  p.stepDone("a");
  p.finish(false, "Network error");
  assert.deepEqual(
    [p.snapshot().state, p.snapshot().percent, p.snapshot().error, p.snapshot().finishedAt],
    ["failed", 25, "Network error", 2000]
  );
  const q = createSyncProgress();
  q.start("X", STEPS);
  q.step("a");
  q.stepDone("a");
  q.step("b");
  q.pause();
  assert.deepEqual([q.snapshot().state, q.snapshot().percent], ["paused", 25]);
  // A late success report after a pause does not fake completion.
  q.finish(true);
  assert.equal(q.snapshot().state, "paused");
});

test("Tally unreachable before a run; waiting for the plan interval", () => {
  const p = createSyncProgress();
  p.fail(null, "Tally is not reachable");
  assert.equal(p.snapshot().state, "failed");
  assert.equal(p.snapshot().error, "Tally is not reachable");
  p.waiting("Ravi Traders", 5000);
  assert.deepEqual([p.snapshot().state, p.snapshot().nextAt, p.snapshot().company], ["waiting", 5000, "Ravi Traders"]);
  // Waiting never interrupts a running sync.
  p.start("Ravi Traders", STEPS);
  p.waiting("Ravi Traders", 9000);
  assert.equal(p.snapshot().state, "syncing");
});
