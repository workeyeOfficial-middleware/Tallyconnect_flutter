// =====================================================================
//  FINANCIAL PROBE — how long Tally takes for each financial request
//  ---------------------------------------------------------------------
//  Run ONCE on the Tally PC, outside business hours, with the company open
//  in Tally and the TallyConnect Agent STOPPED:
//
//      node tools/fin-probe.cjs "GI Apr 25-26"
//      (TALLY_URL=http://localhost:9000 by default)
//
//  It sends the requests the Agent's financial step may send, one at a
//  time, each with a 120-second limit, and prints how long each took.
//  It stops at the first request Tally does not answer in time (Tally
//  may then stay busy for a while — wait until Tally responds again).
//  Read-only: nothing is changed in Tally or sent anywhere else.
//
//  Result:
//    - light requests (groups, books date, item openings) must be quick;
//    - "closing stock" under ~30 s → you may set FIN_STOCK_FROM_TALLY=1
//      for this Agent so P&L / Balance Sheet get month and year ends.
// =====================================================================
"use strict";
const path = require("path");
const axios = require("axios");
const xml2js = require("xml2js");
const { createFinancialSync, fyStartOf, addDays, iso } = require(path.join(__dirname, "..", "lib", "financialSync.cjs"));

const TALLY_URL = (process.env.TALLY_URL || "http://localhost:9000").replace(/\/+$/, "");
const company = process.argv[2];
const LIMIT_MS = 120000;

if (!company) {
  console.log('Usage: node tools/fin-probe.cjs "<company name exactly as in Tally>"');
  process.exit(1);
}

// Same number parsing and XML cleaning as the Agent.
function parseNumber(val = "0") {
  if (val === null || val === undefined) return 0;
  if (typeof val === "object") val = val._ !== undefined ? val._ : "0";
  return Number(String(val).replace(/\(/g, "-").replace(/\)/g, "").replace(/,/g, "").replace(/[^0-9.-]/g, "")) || 0;
}
const clean = (x) => String(x).replace(/&#(?:x0*[0-8bcef]|x0*1[0-9a-f]|0*[0-8]|0*1[1-2]|0*1[4-9]|0*2[0-9]|0*3[01]);/gi, "");

const fin = createFinancialSync({
  tallyPost: (xml) => axios.post(TALLY_URL, xml, { timeout: LIMIT_MS, headers: { "Content-Type": "text/xml" } }),
  parseXml: (x) => new xml2js.Parser({ explicitArray: false }).parseStringPromise(clean(x)),
  parseNumber,
  post: async () => ({ data: {} }),
});

async function timed(label, fn) {
  const t = Date.now();
  try {
    const v = await fn();
    const s = ((Date.now() - t) / 1000).toFixed(1);
    console.log(`  ✅ ${label.padEnd(44)} ${s.padStart(6)} s   ${v}`);
    return { ok: true, secs: Number(s) };
  } catch (e) {
    const s = ((Date.now() - t) / 1000).toFixed(1);
    const slow = e.code === "ECONNABORTED" || /timeout/i.test(String(e.message));
    console.log(`  ❌ ${label.padEnd(44)} ${s.padStart(6)} s   ${slow ? "NO ANSWER IN 120 s" : e.message}`);
    return { ok: false, slow, secs: Number(s) };
  }
}

(async () => {
  console.log(`Tally: ${TALLY_URL}   Company: ${company}\n`);
  const results = [];
  let booksFrom = null;
  const steps = [
    ["Group list (light)", async () => `${(await fin.fetchGroups(company)).length} groups`],
    ["Books-beginning date (light)", async () => (booksFrom = await fin.fetchBooksFrom(company)) || "not found"],
    ["Item opening values (light)", async () => `opening stock ₹${await fin.fetchOpeningStock(company)}`],
  ];
  for (const [label, fn] of steps) {
    const r = await timed(label, fn);
    results.push({ label, ...r });
    if (!r.ok) break;
  }
  if (results.every((r) => r.ok) && booksFrom) {
    // The year end after the books begin and the last month end: heavy.
    const today = iso(new Date());
    const fy = fyStartOf(booksFrom, booksFrom);
    const yearEnd = addDays(`${Number(fy.slice(0, 4)) + 1}${fy.slice(4)}`, -1);
    const d = new Date();
    const lastMonthEnd = iso(new Date(d.getFullYear(), d.getMonth(), 0));
    for (const asOn of [...new Set([yearEnd <= today ? yearEnd : null, lastMonthEnd].filter(Boolean))]) {
      const label = `Closing stock on ${asOn} (HEAVY)`;
      const r = await timed(label, async () => `₹${Math.abs(await fin.fetchStock(company, fyStartOf(asOn, booksFrom), asOn))}`);
      results.push({ label, heavy: true, ...r });
      if (!r.ok) break;
    }
  }
  console.log("");
  const light = results.filter((r) => !r.heavy);
  const heavy = results.filter((r) => r.heavy);
  if (light.some((r) => !r.ok)) {
    console.log("➡️  A light request failed: keep FIN_SYNC=off for this Agent and send this output to support.");
  } else if (!heavy.length) {
    console.log("➡️  Light requests are fine. (No date to test closing stock yet.)");
  } else if (heavy.every((r) => r.ok && r.secs <= 30)) {
    console.log("➡️  All quick. You may set FIN_STOCK_FROM_TALLY=1 for this Agent (one stock date per sync).");
  } else {
    console.log("➡️  Closing stock is slow on this company: leave FIN_STOCK_FROM_TALLY unset.");
    console.log("    Reports then need closing-stock figures another way; send this output to support.");
  }
})();
