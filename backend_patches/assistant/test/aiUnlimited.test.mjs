// Tests for the AI testing exemption (node --test): the exact login
// workk72002@gmail.com (email read from the users table for the signed-in
// user id) has no token allowance; every other user keeps the limit; the
// env list can change or turn it off. No database or network.
import { test } from "node:test";
import assert from "node:assert/strict";

import { createAiUsage, unlimitedEmails } from "../utils/aiUsage.js";

function fakeDb(users) {
  const usage = new Map();
  return {
    async query(sql, p = []) {
      const s = sql.replace(/\s+/g, " ").trim();
      if (s.startsWith("SELECT email FROM users WHERE id = $1")) {
        const u = users.find((x) => x.id === p[0]);
        return { rows: u ? [{ email: u.email }] : [] };
      }
      if (s.startsWith("INSERT INTO ai_usage ")) {
        if (!usage.has(p[0])) usage.set(p[0], { plan_code: "free", tokens_used: 0, requests: 0 });
        return { rows: [] };
      }
      if (s.includes("FROM ai_usage u")) return { rows: [{ ...usage.get(p[0]) }] };
      if (s.startsWith("UPDATE ai_usage SET tokens_used = tokens_used + $2")) {
        usage.get(p[0]).tokens_used += p[1];
        return { rows: [] };
      }
      if (s.startsWith("INSERT INTO ai_usage_log")) return { rows: [] };
      throw new Error(`unhandled ${s}`);
    },
    usage,
  };
}

const USERS = [
  { id: 7, email: "Workk72002@Gmail.com" },
  { id: 8, email: "someone@x.in" },
  { id: 9, email: "workk72002@gmail.com.evil.in" },
];
const env = { AI_FREE_TOKENS: "100" };

test("the testing login: never used up; tokens still counted", async () => {
  const db = fakeDb(USERS);
  const u = createAiUsage(db, env);
  const me = { userId: 7, adminId: 7 };
  await u.status(me);
  await u.record(me, { provider: "x", model: "m", input: 90, output: 90, total: 180 });
  const s = await u.assertCanAsk(me);
  assert.equal(s.unlimited, true);
  assert.equal(s.exhausted, false);
  assert.equal(s.used, 180); // counted and logged as for everyone
  assert.equal(s.plan.code, "testing");
});

test("everyone else keeps the limit (no look-alike email)", async () => {
  const db = fakeDb(USERS);
  const u = createAiUsage(db, env);
  for (const id of [8, 9]) {
    const who = { userId: id, adminId: id };
    await u.status(who);
    await u.record(who, { provider: "x", model: "m", input: 60, output: 60, total: 120 });
    await assert.rejects(u.assertCanAsk(who), (e) => e.code === "ai_quota_exhausted" && e.http === 402);
    assert.notEqual((await u.status(who)).unlimited, true);
  }
});

test("the list comes from AI_UNLIMITED_EMAILS; empty turns it off", async () => {
  assert.deepEqual([...unlimitedEmails({})], ["workk72002@gmail.com"]);
  assert.deepEqual([...unlimitedEmails({ AI_UNLIMITED_EMAILS: " A@b.in , bad, c@d.in" })], ["a@b.in", "c@d.in"]);
  assert.equal(unlimitedEmails({ AI_UNLIMITED_EMAILS: "" }).size, 0);
  const db = fakeDb(USERS);
  const u = createAiUsage(db, { ...env, AI_UNLIMITED_EMAILS: "" });
  const me = { userId: 7, adminId: 7 };
  await u.status(me);
  await u.record(me, { provider: "x", model: "m", input: 60, output: 60, total: 120 });
  await assert.rejects(u.assertCanAsk(me), (e) => e.code === "ai_quota_exhausted");
});
