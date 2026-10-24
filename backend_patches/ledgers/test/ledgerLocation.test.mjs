// Tests for ledger location (state, PIN, country, address from Tally) in
// the ledger sync and list (node --test --experimental-test-module-mocks).
// No database or network: a fake pg pool records every query.
//   node --test --experimental-test-module-mocks test/ledgerLocation.test.mjs
import { test, describe, beforeEach, after, mock } from "node:test";
import assert from "node:assert/strict";
import express from "express";

const fake = { cols: true, queries: [] };
const pool = {
  query: async (sql, params) => {
    fake.queries.push({ sql, params });
    if (/information_schema\.columns/.test(sql)) return { rows: fake.cols ? Array(4).fill({}) : [] };
    if (/FROM companies/.test(sql)) return { rows: [{}], rowCount: 1 };
    if (/INSERT INTO ledgers/.test(sql)) return { rows: [{ ledger_guid: params[1] }], rowCount: 1 };
    if (/FROM ledgers l/.test(sql)) {
      return {
        rows: [{ ledger_guid: "L1", name: "3SDM BUSINESS SOLUTIONS PVT LTD", state: "Maharashtra", pincode: "401208", address: "Waliv, Vasai East -401208" }],
      };
    }
    return { rows: [], rowCount: 0 };
  },
};
let role = "ADMIN";
mock.module(new URL("../db.js", import.meta.url).href, { defaultExport: pool });
mock.module(new URL("../middleware/requireAuth.js", import.meta.url).href, {
  defaultExport: (req, _res, next) => {
    req.user = { id: role === "ADMIN" ? 7 : 21, adminId: 7, role };
    next();
  },
});
mock.module(new URL("../middleware/requireAdmin.js", import.meta.url).href, {
  defaultExport: (_req, _res, next) => next(),
});
mock.module(new URL("../utils/mobileNotification.js", import.meta.url).href, {
  namedExports: { createMobileNotificationForAdmin: async () => {} },
});
const { default: ledgers } = await import("../routes/ledgers.js");
const { locationOf, resetLocationCache } = await import("../utils/ledgerLocation.js");

const app = express();
app.use(express.json());
app.use("/ledger", ledgers);
const server = app.listen(0);
after(() => {
  server.closeAllConnections();
  server.close();
});
const base = `http://127.0.0.1:${server.address().port}`;
const post = (b) =>
  fetch(`${base}/ledger/sync`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(b) }).then((r) => r.json());
const LEDGER = {
  ledger_guid: "L1",
  company_guid: "C1",
  name: "3SDM BUSINESS SOLUTIONS PVT LTD",
  parent_group: "Sundry Creditors",
  type: "Party",
};
const q = (re) => fake.queries.filter((x) => re.test(x.sql));

beforeEach(() => {
  fake.cols = true;
  fake.queries = [];
  role = "ADMIN";
  resetLocationCache();
});

describe("ledger location", () => {
  test("cleaned: one line, limited, empty = not sent", () => {
    assert.deepEqual(locationOf({ state: " Maharashtra ", pincode: "401208", country: "India", address: "201, Jinam\nWaliv,   Vasai" }), {
      state: "Maharashtra",
      pincode: "401208",
      country: "India",
      address: "201, Jinam Waliv, Vasai",
    });
    assert.deepEqual(locationOf({}), { state: null, pincode: null, country: null, address: null });
    assert.equal(locationOf({ address: "x".repeat(900) }).address.length, 500);
  });

  test("sync stores it; an Agent without it keeps what is stored", async () => {
    await post({ ...LEDGER, state: "Maharashtra", pincode: "401208", country: "India", address: "Waliv, Vasai East -401208" });
    const ins = q(/INSERT INTO ledgers/)[0];
    assert.match(ins.sql, /state, pincode, country, address/);
    assert.match(ins.sql, /state = COALESCE\(EXCLUDED\.state, ledgers\.state\)/);
    assert.deepEqual(ins.params.slice(-4), ["Maharashtra", "401208", "India", "Waliv, Vasai East -401208"]);
    fake.queries = [];
    await post(LEDGER);
    assert.deepEqual(q(/INSERT INTO ledgers/)[0].params.slice(-4), [null, null, null, null]);
  });

  test("list returns it to admins and team members (their allowed ledgers)", async () => {
    let r = await fetch(`${base}/ledger`).then((x) => x.json());
    assert.equal(r.data[0].state, "Maharashtra");
    assert.match(q(/FROM ledgers l/)[0].sql, /l\.state, l\.pincode, l\.country, l\.address/);
    fake.queries = [];
    role = "USER";
    r = await fetch(`${base}/ledger`).then((x) => x.json());
    assert.match(q(/FROM ledgers l/)[0].sql, /user_ledger_permissions/);
    assert.match(q(/FROM ledgers l/)[0].sql, /l\.state/);
  });

  test("before the SQL: exactly today's statements", async () => {
    fake.cols = false;
    await post({ ...LEDGER, state: "Maharashtra" });
    await fetch(`${base}/ledger`);
    for (const x of fake.queries) {
      if (/information_schema/.test(x.sql)) continue;
      assert.doesNotMatch(x.sql, /\bstate\b|pincode|address/);
    }
    assert.equal(q(/INSERT INTO ledgers/)[0].params.length, 10);
  });
});
