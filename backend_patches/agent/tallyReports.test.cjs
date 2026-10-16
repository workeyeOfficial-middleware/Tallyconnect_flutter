// Tests for the Agent's Tally-figures fetcher (node --test), run against
// tally-agent/lib/tallyReports.cjs with a FAKE Tally — no Tally needed.
// The point: small pieces, gaps, a few per run, adapting, never the heavy
// report screens.
//   AGENT_DIR=<path to tally-agent> node --test tallyReports.test.cjs
"use strict";
const { test, describe } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const AGENT_DIR = process.env.AGENT_DIR || path.join(__dirname, "..", "..", "..", "tally-agent");
const r = require(path.join(AGENT_DIR, "lib", "tallyReports.cjs"));

const VERSION_XML = `<ENVELOPE><BODY><DATA><COLLECTION>
 <COMPANY NAME="GI Apr 25-26"><ALTVCHID>24900</ALTVCHID><ALTMSTID>24832</ALTMSTID></COMPANY>
</COLLECTION></DATA></BODY></ENVELOPE>`;

/** A fake Tally answering ledger / stock pieces from a book of figures. */
function fakeTally({ ledgers = {}, stock = {}, slowMs = 0, timeoutOn = null, version = VERSION_XML } = {}) {
  const calls = [];
  let clockMs = 0;
  return {
    calls,
    clock: () => clockMs,
    tallyPost: async (xml, timeoutMs) => {
      const names = [...xml.matchAll(/\$Name = "([^"]*)"/g)].map((m) => m[1].replace(/&amp;/g, "&"));
      const kind = /TCReportsVersion/.test(xml) ? "version" : /TCLedgerPiece/.test(xml) ? "ledger" : /TCStockPiece/.test(xml) ? "stock" : /REPORTNAME/.test(xml) ? "REPORT" : "?";
      const to = (/<SVTODATE>(\d+)</.exec(xml) || [])[1];
      calls.push({ kind, names, to, timeoutMs });
      if (kind === "version") return { data: version };
      if (timeoutOn && timeoutOn(kind, names)) throw Object.assign(new Error("timeout of 30000ms exceeded"), { code: "ECONNABORTED" });
      clockMs += typeof slowMs === "function" ? slowMs(kind, names) : slowMs;
      if (kind === "ledger") {
        const body = names
          .filter((n) => ledgers[n])
          .map((n) => `<LEDGER NAME="${n.replace(/&/g, "&amp;")}"><PARENT>${ledgers[n].parent}</PARENT><OPENINGBALANCE>${ledgers[n].opening ?? 0}</OPENINGBALANCE><CLOSINGBALANCE>${ledgers[n].closing}</CLOSINGBALANCE></LEDGER>`)
          .join("");
        return { data: `<ENVELOPE><BODY><DATA><COLLECTION>${body}</COLLECTION></DATA></BODY></ENVELOPE>` };
      }
      if (kind === "stock") {
        const body = names.map((n) => `<STOCKITEM NAME="${n}"><CLOSINGVALUE>${(stock[n] || 0) * (to < "20260401" ? 0.5 : 1)}</CLOSINGVALUE></STOCKITEM>`).join("");
        return { data: `<ENVELOPE><BODY><DATA><COLLECTION>${body}</COLLECTION></DATA></BODY></ENVELOPE>` };
      }
      return { data: "<ENVELOPE></ENVELOPE>" };
    },
  };
}

const LEDGERS = {};
const LIST = [];
for (let i = 0; i < 50; i++) {
  const name = `Debtor ${String(i).padStart(2, "0")}`;
  LEDGERS[name] = { parent: "Sundry Debtors", closing: -100 };
  LIST.push({ name, parent: "Sundry Debtors" });
}
LEDGERS["HDFC Bank"] = { parent: "Bank Accounts", opening: -1000, closing: -2000 };
LIST.push({ name: "HDFC Bank", parent: "Bank Accounts" });
LEDGERS["Capital"] = { parent: "Capital Account", closing: 7000 };
LIST.push({ name: "Capital", parent: "Capital Account" });
const GROUPS = [{ name: "Bank Accounts", parent: "Current Assets" }];
const ITEMS = ["Pipe", "Wire", "Switch"].map((name) => ({ name }));
const STOCK = { Pipe: 1000, Wire: 500, Switch: 250 };

const NOW = new Date(2026, 9, 15, 14, 0, 0); // 15 Oct 2026
function setup(fakeOpts = {}, extra = {}) {
  const fake = fakeTally({ ledgers: LEDGERS, stock: STOCK, ...fakeOpts });
  const posts = [];
  const sleeps = [];
  const state = {};
  const t = r.createTallyReports({
    tallyPost: fake.tallyPost,
    post: async (p, body) => posts.push({ p, body }),
    sleep: async (ms) => sleeps.push(ms),
    clock: fake.clock,
  });
  const run = (over = {}) =>
    t.run({
      companyGuid: "CO-1",
      companyName: "GI Apr 25-26",
      ledgers: LIST,
      stockItems: ITEMS,
      getGroups: async () => GROUPS,
      state,
      saveState: () => {},
      now: NOW,
      config: { ledgerChunk: 20, stockChunk: 2, ...extra },
      ...over,
    });
  return { fake, posts, sleeps, state, run };
}

describe("small pieces", () => {
  test("requests: one name list per piece, no heavy report screens", () => {
    const x = r.ledgersXml("A & B", "2026-04-01", "2026-10-15", ['Mehta & "Sons"', "Cash"]);
    assert.match(x, /<TYPE>Ledger<\/TYPE>/);
    assert.match(x, /<FILTERS>TCPick<\/FILTERS>/);
    assert.match(x, /\$Name = "Mehta &amp; Sons" OR \$Name = "Cash"/);
    assert.match(x, /<SVCURRENTCOMPANY>A &amp; B<\/SVCURRENTCOMPANY>/);
    assert.doesNotMatch(x, /REPORTNAME/);
    assert.match(r.stockXml("X", "2026-04-01", "2026-10-15", ["Pipe"]), /CLOSINGVALUE/);
  });

  test("months, year start, cash / bank ledgers", () => {
    assert.deepEqual(r.monthsOf("2026-04-01", "2026-06-10"), [
      { from: "2026-04-01", to: "2026-04-30" },
      { from: "2026-05-01", to: "2026-05-31" },
      { from: "2026-06-01", to: "2026-06-10" },
    ]);
    assert.equal(r.fyStartOf("2026-02-10"), "2025-04-01");
    assert.deepEqual(r.cashLedgers(LIST, GROUPS), ["HDFC Bank"]);
  });

  test("a set of pieces: ledgers, stock (closing + opening), cash months", () => {
    const job = r.newJob({
      kind: "today",
      from: "2026-04-01",
      to: "2026-10-15",
      ledgers: LIST,
      stockItems: ITEMS,
      cashNames: ["HDFC Bank"],
      knownStock: {},
      version: "v",
    });
    assert.equal(job.queue.filter((q) => q.t === "ledger").length, 52);
    assert.equal(job.queue.filter((q) => q.t === "stockClose").length, 3);
    assert.equal(job.queue.filter((q) => q.t === "stockOpen").length, 3);
    assert.equal(job.queue.filter((q) => q.t === "cash").length, 7); // Apr–Oct
    // Opening stock already known (last year's close): not asked again.
    const known = r.newJob({ kind: "today", from: "2026-04-01", to: "2026-10-15", ledgers: LIST, stockItems: ITEMS, cashNames: [], knownStock: { "2026-03-31": 875 }, version: "v" });
    assert.equal(known.queue.filter((q) => q.t === "stockOpen").length, 0);
    assert.equal(known.stockOpen, 875);
  });
});

describe("never hang Tally", () => {
  test("a few pieces per run, a rest first and a gap between; resumes next run; one upload at the end", async () => {
    const s = setup({}, { piecesPerRun: 3 });
    const first = await s.run();
    const pieces = s.fake.calls.filter((c) => c.kind !== "version");
    assert.equal(pieces.length, 3);
    // 52 ledgers: 20, then bigger because Tally answered fast (20 → 25), then the rest.
    assert.deepEqual(pieces.map((c) => c.names.length), [20, 25, 7]);
    assert.deepEqual(s.sleeps, [10000, 8000, 8000]); // rest, then gaps
    assert.equal(first.done, 3);
    assert.equal(s.posts.length, 0); // not complete yet
    assert.ok(s.fake.calls.every((c) => c.kind !== "REPORT"));
    // Next runs carry on until everything is in, then ONE upload.
    for (let i = 0; i < 10 && !s.posts.length; i++) await s.run();
    assert.equal(s.posts.length, 1);
    const b = s.posts[0].body;
    assert.equal(s.posts[0].p, "/api/tally-reports/agent/snapshot");
    assert.equal(b.period_from, "2026-04-01");
    assert.equal(b.period_to, "2026-10-15");
    assert.equal(b.ledgers.length, 52);
    assert.deepEqual(b.stock, { closing: 1750, opening: 875 });
    assert.equal(b.cash_months.length, 7);
    assert.deepEqual(b.cash_months[0], { from: "2026-04-01", to: "2026-04-30", opening: -1000, closing: -2000 });
    assert.ok(s.state.tally_reports2.last.today);
    assert.equal(s.state.tally_reports2.job, null);
  });

  test("Tally slow on the tiny check: nothing this run", async () => {
    const s = setup({ version: null });
    s.fake.tallyPost = async () => {
      throw Object.assign(new Error("timeout"), { code: "ECONNABORTED" });
    };
    const t = r.createTallyReports({ tallyPost: s.fake.tallyPost, post: async () => {}, sleep: async () => {} });
    const out = await t.run({ companyGuid: "CO-1", companyName: "X", ledgers: LIST, state: {}, saveState: () => {}, now: NOW });
    assert.match(out.skipped, /busy/);
  });

  test("a slow piece: smaller pieces and stop this run; fast pieces grow again", async () => {
    const s = setup({ slowMs: (kind) => (kind === "ledger" ? 8000 : 10) }, { piecesPerRun: 5 });
    await s.run();
    const pieces = s.fake.calls.filter((c) => c.kind === "ledger");
    assert.equal(pieces.length, 1); // stopped after the slow one
    assert.equal(s.state.tally_reports2.size.ledger, 10); // 20 → 10
    await s.run();
    assert.equal(s.fake.calls.filter((c) => c.kind === "ledger").at(-1).names.length, 10);
  });

  test("a piece times out: Tally rests 30 min, pieces much smaller; progress kept", async () => {
    let n = 0;
    const s = setup({ timeoutOn: (kind) => kind === "ledger" && ++n === 2 }, { piecesPerRun: 5 });
    await s.run();
    const st = s.state.tally_reports2;
    assert.ok(st.cool_until > 0);
    assert.equal(st.size.ledger, 6); // max(5, floor(25 / 4)): it had grown to 25 after a fast piece
    assert.equal(st.job.queue.filter((q) => q.t === "ledger").length, 32); // first piece kept
    const rest = await s.run({ now: new Date(NOW.getTime() + 60000) });
    assert.match(rest.skipped, /resting/);
  });

  test("nothing changed in Tally: not fetched again the same day", async () => {
    const s = setup({}, { piecesPerRun: 100 });
    await s.run(); // today's figures
    await s.run(); // last year's close (the next sync)
    assert.equal(s.posts.length, 2);
    assert.equal(s.posts[1].body.period_to, "2026-03-31");
    assert.equal(s.posts[1].body.period_from, "2025-04-01");
    const calls = s.fake.calls.length;
    const later = await s.run({ now: new Date(NOW.getTime() + 7 * 3600000) });
    assert.equal(later.done, 0);
    assert.equal(s.fake.calls.length, calls + 1); // only the tiny check
  });

  test("server without the route / tables: pieces kept, tried again in an hour", async () => {
    const s = setup({}, { piecesPerRun: 100 });
    const t = r.createTallyReports({
      tallyPost: s.fake.tallyPost,
      post: async () => {
        throw Object.assign(new Error("404"), { response: { status: 404 } });
      },
      sleep: async () => {},
      clock: s.fake.clock,
    });
    const state = {};
    const args = { companyGuid: "CO-1", companyName: "GI", ledgers: LIST, stockItems: ITEMS, getGroups: async () => GROUPS, state, saveState: () => {}, now: NOW, config: { piecesPerRun: 100 } };
    await t.run(args);
    assert.ok(state.tally_reports2.off_until > 0);
    assert.equal(state.tally_reports2.job.queue.length, 0); // all pieces kept for the upload
  });
});
