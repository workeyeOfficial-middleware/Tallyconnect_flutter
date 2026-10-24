// Tests for the bill sync's bill date (node --test
// --experimental-test-module-mocks). The Agent always sent each bill's date
// from Tally ("4-Apr-24"); the server did not save it, so Bill date and
// Credit period were blank in the app. No database or network.
//   node --test --experimental-test-module-mocks test/billSync.test.mjs
import { test, describe, after, mock } from "node:test";
import assert from "node:assert/strict";
import express from "express";

const queries = [];
const pool = {
  query: async (sql, params) => {
    queries.push({ sql, params });
    if (/FROM ledgers/.test(sql)) return { rows: [{ ledger_guid: "L1" }], rowCount: 1 };
    return { rows: [], rowCount: 1 };
  },
};
mock.module(new URL("../db.js", import.meta.url).href, { defaultExport: pool });
mock.module(new URL("../middleware/requireAuth.js", import.meta.url).href, {
  defaultExport: (req, _res, next) => {
    req.user = { id: 7, adminId: 7, role: "ADMIN" };
    next();
  },
});
mock.module(new URL("../utils/notification.js", import.meta.url).href, {
  namedExports: { createNotification: async () => {} },
});
const { default: bills, tallyDate } = await import("../routes/bills.js");

const app = express();
app.use(express.json());
app.use("/bill", bills);
const server = app.listen(0);
after(() => {
  server.closeAllConnections();
  server.close();
});
const base = `http://127.0.0.1:${server.address().port}`;
const sync = (body) =>
  fetch(`${base}/bill/sync`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) }).then((r) => r.json());

describe("bill date", () => {
  test("Tally's date formats → YYYY-MM-DD; anything else → not known", () => {
    assert.equal(tallyDate("4-Apr-24"), "2024-04-04");
    assert.equal(tallyDate("04-Apr-2024"), "2024-04-04");
    assert.equal(tallyDate("20240404"), "2024-04-04");
    assert.equal(tallyDate("2024-04-04"), "2024-04-04");
    assert.equal(tallyDate("31-Feb-24"), null);
    assert.equal(tallyDate("1-Xyz-24"), null);
    assert.equal(tallyDate(""), null);
    assert.equal(tallyDate(null), null);
  });

  test("saved with the bill; a bill sent without one keeps what is stored", async () => {
    const body = {
      company_guid: "C1",
      ledger_name: "Kanojia Enterprises",
      bill_name: "KE/247",
      pending_amount: 26314,
      due_date: "4-May-24",
      bill_date: "4-Apr-24",
      bill_type: "RECEIVABLE",
    };
    assert.equal((await sync(body)).success, true);
    const ins = queries.find((q) => /INSERT INTO bills/.test(q.sql));
    assert.match(ins.sql, /bill_date = COALESCE\(EXCLUDED\.bill_date, bills\.bill_date\)/);
    assert.equal(ins.params.at(-1), "2024-04-04");
    assert.equal(ins.params[8], "4-May-24"); // due date as before
    queries.length = 0;
    await sync({ ...body, bill_date: undefined });
    assert.equal(queries.find((q) => /INSERT INTO bills/.test(q.sql)).params.at(-1), null);
  });
});
