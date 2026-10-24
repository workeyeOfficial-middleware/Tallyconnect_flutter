// Tests for editing and retrying mobile entries (node --test
// --experimental-test-module-mocks). The real routes run against an
// in-memory fake database: an edit goes through the entry type's own
// create handler (Receipt here) and is saved over the waiting entry or as
// one ALTER of the Tally voucher; retry never re-sends what is in Tally.
//   node --test --experimental-test-module-mocks test/mobileEdits.test.mjs
import { test, describe, beforeEach, after, mock } from "node:test";
import assert from "node:assert/strict";
import express from "express";

const CO = "44acb1ff-18e7-40de-822e-c7f32ad504e4";
const T1 = `${CO}-000093af`; // a Tally voucher GUID

const db = {
  cols: true,
  queue: [],
  vouchers: [],
  users: [{ id: 21, allowed: [T1] }],
  nextId: 1,
  reset() {
    this.cols = true;
    this.queue = [];
    this.vouchers = [
      { voucher_guid: T1, voucher_type: "Receipt", reference_no: "R/9", voucher_date: "2026-10-01", is_active: true },
      { voucher_guid: `${CO}-000093b0`, voucher_type: "Sales GST", reference_no: "S/1", voucher_date: "2026-10-01", is_active: true },
    ];
    this.nextId = 1;
  },
  async query(sql, p = []) {
    const s = sql.replace(/\s+/g, " ").trim();
    const out = (rows) => ({ rows: rows.map((r) => ({ ...r })), rowCount: rows.length });
    if (/information_schema\.columns/.test(s)) return out(this.cols ? Array(6).fill({}) : []);
    if (s.includes("FROM active_company")) return out([{ company_guid: CO }]);
    if (s.includes("FROM vouchers v") || s.startsWith("SELECT voucher_guid FROM vouchers")) {
      if (s.includes("v.voucher_guid = $3")) return out(this.vouchers.filter((v) => v.voucher_guid === p[2]));
      return out(this.vouchers.filter((v) => v.voucher_type.toLowerCase() === String(p[2]).toLowerCase() && v.reference_no === p[3]));
    }
    if (s.includes("FROM users u WHERE u.id = $1 AND $2 = ANY")) {
      const u = this.users.find((x) => x.id === p[0]);
      return out(u && u.allowed.includes(p[1]) ? [{}] : []);
    }
    const Q = this.queue;
    if (s.startsWith("INSERT INTO mobile_sync_queue")) {
      const alter = s.includes("'ALTER'");
      const row = alter
        ? { id: this.nextId++, admin_id: p[0], company_guid: p[1], entity_guid: p[2], action: "ALTER", payload: p[3], payload_hash: p[4],
            status: "pending", target_guid: p[2], edit_of: p[5], created_by: p[6] }
        : { id: this.nextId++, admin_id: p[0], company_guid: p[1], entity_guid: p[2], action: "CREATE", payload: p[3], payload_hash: p[4],
            status: "pending", created_by: null };
      Q.push(row);
      return out([{ id: row.id }]);
    }
    if (s.startsWith("UPDATE mobile_sync_queue SET created_by")) {
      const r = Q.find((x) => x.id === p[0]);
      if (r) r.created_by = p[1];
      return out([]);
    }
    if (s.includes("FROM mobile_sync_queue WHERE admin_id = $1 AND company_guid = $2 AND entity_type = 'VOUCHER' AND action = 'CREATE' AND payload_hash")) {
      return out(Q.filter((x) => x.action === "CREATE" && x.payload_hash === p[2] && ["pending", "processing", "success"].includes(x.status)));
    }
    if (s.includes("FROM mobile_sync_queue WHERE id = $1 AND admin_id = $2 AND company_guid = $3")) {
      return out(Q.filter((x) => x.id === p[0] && x.admin_id === p[1] && x.company_guid === p[2]));
    }
    if (s.includes("action = 'ALTER' AND target_guid = $3")) {
      return out(Q.filter((x) => x.action === "ALTER" && x.target_guid === p[2] && ["pending", "processing", "failed"].includes(x.status)).reverse());
    }
    if (s.startsWith("UPDATE mobile_sync_queue SET payload = $2")) {
      const r = Q.find((x) => x.id === p[0] && (!s.includes("status IN") || ["pending", "failed"].includes(x.status)));
      if (!r) return out([]);
      Object.assign(r, { payload: p[1], payload_hash: p[2], status: "pending", error: null });
      return out([{ id: r.id }]);
    }
    if (s.startsWith("UPDATE mobile_sync_queue SET status = 'pending', error = NULL, retry_count")) {
      const r = Q.find((x) => x.id === p[0] && ["failed", "processing"].includes(x.status));
      if (!r) return out([]);
      Object.assign(r, { status: "pending", error: null, retry_count: (r.retry_count || 0) + 1 });
      return out([{ id: r.id, retry_count: r.retry_count }]);
    }
    if (s.startsWith("UPDATE mobile_sync_queue SET status = 'success'")) {
      const r = Q.find((x) => x.id === Number(p[0]));
      Object.assign(r, { status: "success", tally_guid: p[1] ?? r.tally_guid ?? r.target_guid });
      return out([]);
    }
    throw new Error(`FakeDb: unhandled SQL ${s}`);
  },
};

let user = { id: 7, adminId: 7, role: "ADMIN" };
mock.module(new URL("../db.js", import.meta.url).href, { defaultExport: db });
mock.module(new URL("../middleware/requireAuth.js", import.meta.url).href, {
  defaultExport: (req, _res, next) => {
    req.user = { ...user };
    next();
  },
});
mock.module(new URL("../utils/notification.js", import.meta.url).href, { namedExports: { createNotification: async () => {} } });
mock.module(new URL("../utils/mobileNotification.js", import.meta.url).href, {
  namedExports: { createMobileNotificationForAdmin: async () => {} },
});
const { default: cmd } = await import("../routes/UniversalUpdate/mobileVoucherCommand.js");
const { default: queue } = await import("../routes/mobileSyncQueueRoutes.js");
const { resetEditCache } = await import("../utils/mobileEdits.js");

const app = express();
app.use(express.json());
app.use("/api/mobile-voucher-command", cmd);
app.use("/api/mobile-sync-queue", queue);
const server = app.listen(0);
after(() => {
  server.closeAllConnections();
  server.close();
});
const base = `http://127.0.0.1:${server.address().port}`;
const post = async (path, body = {}) => {
  const r = await fetch(base + path, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
  return { status: r.status, body: await r.json() };
};
const RECEIPT = {
  voucher_date: "2026-10-01",
  party_name: "Mehta Electricals",
  amount_received: 5000,
  narration: "Cash",
  payment: { payment_mode: "Cash" },
};

beforeEach(() => {
  db.reset();
  user = { id: 7, adminId: 7, role: "ADMIN" };
  resetEditCache();
});

describe("edit", () => {
  test("a waiting (or failed) entry: changed where it waits — still one entry", async () => {
    const c = await post("/api/mobile-voucher-command/receipt/create", RECEIPT);
    assert.equal(c.status, 200);
    const id = c.body.command_id;
    assert.equal(db.queue[0].created_by, 7); // who made it
    const guid = db.queue[0].payload.voucher_guid;
    const e = await post("/api/mobile-voucher-command/edit", { ...RECEIPT, type: "receipt", queue_id: id, amount_received: 6000 });
    assert.equal(e.status, 200);
    assert.deepEqual([e.body.edited, e.body.command_id], [true, id]);
    assert.equal(db.queue.length, 1);
    assert.equal(db.queue[0].payload.voucher_guid, guid); // same entry
    assert.equal(db.queue[0].status, "pending");
    db.queue[0].status = "failed";
    await post("/api/mobile-voucher-command/edit", { ...RECEIPT, type: "receipt", queue_id: id, amount_received: 6500 });
    assert.equal(db.queue[0].status, "pending");
    assert.equal(db.queue.length, 1);
    // Being sent right now: refused, nothing changed.
    db.queue[0].status = "processing";
    const busy = await post("/api/mobile-voucher-command/edit", { ...RECEIPT, type: "receipt", queue_id: id });
    assert.equal(busy.status, 409);
    assert.equal(busy.body.code, "sending");
  });

  test("an entry Tally confirmed: one ALTER of that voucher; a newer edit replaces it", async () => {
    const c = await post("/api/mobile-voucher-command/receipt/create", RECEIPT);
    await post(`/api/mobile-sync-queue/${c.body.command_id}/success`, { tally_guid: T1 });
    assert.equal(db.queue[0].tally_guid, T1);
    const e = await post("/api/mobile-voucher-command/edit", { ...RECEIPT, type: "receipt", queue_id: c.body.command_id, amount_received: 7000 });
    assert.equal(e.status, 200);
    assert.equal(e.body.alter, true);
    const a = db.queue.find((x) => x.action === "ALTER");
    assert.deepEqual([a.target_guid, a.payload.voucher_guid, a.edit_of], [T1, T1, c.body.command_id]);
    await post("/api/mobile-voucher-command/edit", { ...RECEIPT, type: "receipt", queue_id: c.body.command_id, amount_received: 7100 });
    assert.equal(db.queue.filter((x) => x.action === "ALTER").length, 1); // replaced, not doubled
    assert.equal(Number(db.queue.find((x) => x.action === "ALTER").payload.ledger_entries?.[0]?.amount ?? 7100), 7100);
  });

  test("an entry Tally took before it could be linked: explains, no ALTER", async () => {
    const c = await post("/api/mobile-voucher-command/receipt/create", RECEIPT);
    db.queue[0].status = "success"; // an older Agent: no tally_guid
    const e = await post("/api/mobile-voucher-command/edit", { ...RECEIPT, type: "receipt", queue_id: c.body.command_id });
    assert.equal(e.status, 409);
    assert.equal(e.body.code, "not_linked");
    assert.equal(db.queue.length, 1);
  });

  test("a synced voucher: ALTER by its GUID; custom types, wrong type, no access refused", async () => {
    const e = await post("/api/mobile-voucher-command/edit", { ...RECEIPT, type: "receipt", voucher_guid: T1 });
    assert.equal(e.status, 200);
    assert.equal(db.queue[0].action, "ALTER");
    assert.equal(db.queue[0].target_guid, T1);
    assert.equal((await post("/api/mobile-voucher-command/edit", { type: "sales", voucher_guid: `${CO}-000093b0` })).body.code, "type_not_editable");
    assert.equal((await post("/api/mobile-voucher-command/edit", { ...RECEIPT, type: "payment", voucher_guid: T1 })).status, 422);
    assert.equal((await post("/api/mobile-voucher-command/edit", { type: "stock", voucher_guid: T1 })).status, 400);
    assert.equal((await post("/api/mobile-voucher-command/edit", { type: "receipt", voucher_guid: "nope" })).status, 404);
    user = { id: 22, adminId: 7, role: "USER" }; // no access to T1
    assert.equal((await post("/api/mobile-voucher-command/edit", { ...RECEIPT, type: "receipt", voucher_guid: T1 })).status, 403);
    user = { id: 21, adminId: 7, role: "USER" }; // allowed
    assert.equal((await post("/api/mobile-voucher-command/edit", { ...RECEIPT, type: "receipt", voucher_guid: T1 })).status, 200);
  });

  test("a team member edits only the entries they made", async () => {
    user = { id: 21, adminId: 7, role: "USER" };
    const c = await post("/api/mobile-voucher-command/receipt/create", RECEIPT);
    assert.equal((await post("/api/mobile-voucher-command/edit", { ...RECEIPT, type: "receipt", queue_id: c.body.command_id })).status, 200);
    user = { id: 22, adminId: 7, role: "USER" };
    assert.equal((await post("/api/mobile-voucher-command/edit", { ...RECEIPT, type: "receipt", queue_id: c.body.command_id })).status, 403);
  });

  test("before the SQL: edit explains; create works as before", async () => {
    db.cols = false;
    const c = await post("/api/mobile-voucher-command/receipt/create", RECEIPT);
    assert.equal(c.status, 200);
    assert.equal(db.queue[0].created_by, null);
    const e = await post("/api/mobile-voucher-command/edit", { ...RECEIPT, type: "receipt", queue_id: c.body.command_id });
    assert.equal(e.status, 503);
    assert.equal(e.body.code, "not_ready");
  });
});

describe("retry", () => {
  test("failed → waiting again; waiting / sending / in Tally are not re-sent", async () => {
    const c = await post("/api/mobile-voucher-command/receipt/create", RECEIPT);
    const id = c.body.command_id;
    let r = await post(`/api/mobile-sync-queue/${id}/retry`);
    assert.equal(r.body.already, true); // still waiting
    db.queue[0].status = "failed";
    r = await post(`/api/mobile-sync-queue/${id}/retry`);
    assert.equal(r.status, 200);
    assert.equal(db.queue[0].status, "pending");
    assert.equal(db.queue[0].retry_count, 1);
    db.queue[0].status = "processing";
    db.queue[0].updated_at = new Date().toISOString();
    assert.equal((await post(`/api/mobile-sync-queue/${id}/retry`)).body.code, "sending");
    db.queue[0].updated_at = new Date(Date.now() - 20 * 60000).toISOString(); // stuck
    assert.equal((await post(`/api/mobile-sync-queue/${id}/retry`)).status, 200);
    db.queue[0].status = "success";
    assert.equal((await post(`/api/mobile-sync-queue/${id}/retry`)).body.code, "done");
    assert.equal((await post("/api/mobile-sync-queue/999/retry")).status, 404);
  });

  test("a create Tally may already have (same type and number): not sent again", async () => {
    const c = await post("/api/mobile-voucher-command/receipt/create", { ...RECEIPT, voucher_no: "R/9" });
    db.queue[0].status = "failed";
    const r = await post(`/api/mobile-sync-queue/${c.body.command_id}/retry`);
    assert.equal(r.status, 409);
    assert.equal(r.body.code, "in_tally");
    assert.equal(db.queue[0].status, "failed");
  });

  test("a team member retries only theirs", async () => {
    const c = await post("/api/mobile-voucher-command/receipt/create", RECEIPT); // made by the admin
    db.queue[0].status = "failed";
    user = { id: 21, adminId: 7, role: "USER" };
    assert.equal((await post(`/api/mobile-sync-queue/${c.body.command_id}/retry`)).status, 403);
  });
});
