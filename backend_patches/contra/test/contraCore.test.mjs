// Tests for the mobile Contra entry (node --test): request checks, the
// queue payload (the Agent's contract) and the queue insert. In-memory fake
// database; no express / Postgres needed.
//   node --test backend_patches/contra/test/
import { test, describe } from "node:test";
import assert from "node:assert/strict";

import { validateContra, buildContraPayload, queueContra } from "../utils/contraCore.js";

class FakeDb {
  constructor({ active = { 7: "CO-1" } } = {}) {
    this.active = active;
    this.queue = [];
  }
  async query(sql, p = []) {
    const s = sql.replace(/\s+/g, " ").trim();
    if (s.startsWith("SELECT company_guid FROM active_company")) {
      return { rows: this.active[p[0]] ? [{ company_guid: this.active[p[0]] }] : [] };
    }
    if (s.startsWith("SELECT id FROM mobile_sync_queue")) {
      const r = this.queue.filter(
        (q) => q.admin_id === p[0] && q.company_guid === p[1] && q.payload_hash === p[2] && q.status !== "failed"
      );
      return { rows: r.slice(0, 1), rowCount: Math.min(r.length, 1) };
    }
    if (s.startsWith("INSERT INTO mobile_sync_queue")) {
      assert.match(s, /'VOUCHER', \$3, 'CREATE', \$4, \$5, 'MOBILE', 'pending'/);
      const row = { id: this.queue.length + 1, admin_id: p[0], company_guid: p[1], entity_guid: p[2], payload: p[3], payload_hash: p[4], status: "pending" };
      this.queue.push(row);
      return { rows: [{ id: row.id }], rowCount: 1 };
    }
    throw new Error(`Unexpected SQL: ${s}`);
  }
}

const body = (o = {}) => ({
  voucher_date: "2026-10-15",
  from_account: "Cash",
  to_account: "HDFC Bank – Current",
  amount: 5000,
  ...o,
});

describe("mobile Contra entry", () => {
  test("request checks", () => {
    assert.equal(validateContra(body()).error, undefined);
    const bad = (o, re) => assert.match(validateContra(body(o)).error || "", re);
    bad({ voucher_date: "" }, /voucher_date is required/);
    bad({ voucher_date: "2026-02-30" }, /must be a date/);
    bad({ voucher_date: "15-10-2026" }, /must be a date/);
    bad({ from_account: "  " }, /from_account is required/);
    bad({ to_account: undefined }, /to_account is required/);
    bad({ to_account: " cash " }, /must be different/);
    bad({ amount: 0 }, /greater than 0/);
    bad({ amount: -5 }, /greater than 0/);
    bad({ amount: "abc" }, /greater than 0/);
    bad({ amount: 0.001 }, /at least/);
    bad({ amount: 2e12 }, /too large/);
    bad({ voucher_no: "x".repeat(51) }, /voucher_no is too long/);
    assert.equal(validateContra(null).error, "voucher_date is required");
    // Text amounts, timestamps and paise rounding.
    const v = validateContra(body({ amount: "1234.567", voucher_date: "2026-10-15T00:00:00Z" })).value;
    assert.equal(v.amount, 1234.57);
    assert.equal(v.voucher_date, "2026-10-15");
  });

  test("payload: to account debit, from account credit (Journal shape)", () => {
    const v = validateContra(body({ voucher_no: "C-7", narration: " Cash deposited ", instrument_no: "UTR123" })).value;
    const p = buildContraPayload(v, { guid: "G-1", now: new Date(1000) });
    assert.deepEqual(p, {
      voucher_guid: "G-1",
      voucher_type: "Contra",
      voucher_date: "2026-10-15",
      voucher_no: "C-7",
      reference_no: "UTR123",
      narration: "Cash deposited",
      transfer: { from_account: "Cash", to_account: "HDFC Bank – Current", amount: 5000, instrument_no: "UTR123" },
      ledger_entries: [
        { ledger_name: "HDFC Bank – Current", amount: 5000, is_debit: true },
        { ledger_name: "Cash", amount: 5000, is_debit: false },
      ],
      total_debit: 5000,
      total_credit: 5000,
    });
    // No party_name: the Agent must not treat an account as a party.
    assert.equal("party_name" in p, false);
    const q = buildContraPayload(validateContra(body()).value, { guid: "G-2", now: new Date(1000) });
    assert.equal(q.reference_no, "MOBILE-CONTRA-1000");
    assert.equal(q.voucher_no, null);
  });

  test("queued for the active company; notifications sent", async () => {
    const db = new FakeDb();
    const sent = [];
    const r = await queueContra({
      db,
      adminId: 7,
      body: body(),
      notify: async (n) => sent.push(n.type),
      notifyMobile: async (n) => sent.push(`${n.type}:${n.meta.party_name}`),
      newGuid: () => "G-1",
    });
    await new Promise((res) => setImmediate(res));
    assert.equal(r.status, 200);
    assert.deepEqual(r.json, { success: true, command_id: 1, voucher_guid: "G-1", status: "QUEUED" });
    assert.equal(db.queue.length, 1);
    assert.equal(db.queue[0].company_guid, "CO-1");
    assert.equal(db.queue[0].payload.voucher_type, "Contra");
    assert.deepEqual(sent, ["VOUCHER_CREATED", "create_entry:Cash → HDFC Bank – Current"]);
  });

  test("bad request / no active company: nothing queued", async () => {
    const db = new FakeDb();
    const r = await queueContra({ db, adminId: 7, body: body({ amount: 0 }) });
    assert.equal(r.status, 400);
    assert.equal(r.json.success, false);
    const r2 = await queueContra({ db, adminId: 9, body: body() });
    assert.deepEqual(r2, { status: 400, json: { success: false, message: "No active company" } });
    assert.equal(db.queue.length, 0);
  });

  test("the same payload twice → the first command (duplicate)", async () => {
    const db = new FakeDb();
    const deps = { db, adminId: 7, body: body(), newGuid: () => "G-1", now: () => new Date(1000) };
    await queueContra(deps);
    const again = await queueContra(deps);
    assert.deepEqual(again.json, { success: true, duplicate: true, command_id: 1 });
    assert.equal(db.queue.length, 1);
  });

  test("a failing notification does not fail the entry", async () => {
    const db = new FakeDb();
    const r = await queueContra({
      db,
      adminId: 7,
      body: body(),
      notify: async () => {
        throw new Error("mail down");
      },
      notifyMobile: async () => {
        throw new Error("push down");
      },
      log: { error: () => {} },
    });
    await new Promise((res) => setImmediate(res));
    assert.equal(r.status, 200);
    assert.equal(db.queue.length, 1);
  });
});
