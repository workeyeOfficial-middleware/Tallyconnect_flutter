// =====================================================================
//  COMPANY PROBE — can this Tally answer for each open company?
//  ---------------------------------------------------------------------
//  Multi-company sync asks Tally for each company by name
//  (SVCURRENTCOMPANY). Most Tally builds answer for every company LOADED
//  (open) in Tally; if this one only answers for the company on screen,
//  multi-company sync must stay off. Run ONCE on the Tally PC with two or
//  more companies open in Tally (the Agent may keep running):
//
//      node tools/company-probe.cjs
//      (TALLY_URL=http://localhost:9000 by default)
//
//  Light, read-only requests only (company list, ledger NAMES per company).
// =====================================================================
"use strict";
const axios = require("axios");
const xml2js = require("xml2js");

const TALLY_URL = (process.env.TALLY_URL || "http://localhost:9000").replace(/\/+$/, "");
const clean = (x) => String(x).replace(/&#(?:x0*[0-8bcef]|x0*1[0-9a-f]|0*[0-8]|0*1[1-2]|0*1[4-9]|0*2[0-9]|0*3[01]);/gi, "");
const text = (v) => (v == null ? "" : typeof v === "string" ? v.trim() : v._ != null ? String(v._).trim() : String(v).trim());
const list = (v) => (v == null ? [] : Array.isArray(v) ? v : [v]);
const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

function xml(type, fetch, company) {
  return `<ENVELOPE><HEADER><VERSION>1</VERSION><TALLYREQUEST>Export Data</TALLYREQUEST><TYPE>Collection</TYPE><ID>TCProbe${type}</ID></HEADER>
<BODY><DESC><STATICVARIABLES><SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>${company ? `<SVCURRENTCOMPANY>${esc(company)}</SVCURRENTCOMPANY>` : ""}</STATICVARIABLES>
<TDL><TDLMESSAGE><COLLECTION NAME="TCProbe${type}"><TYPE>${type}</TYPE><FETCH>${fetch}</FETCH></COLLECTION></TDLMESSAGE></TDL></DESC></BODY></ENVELOPE>`;
}

async function ask(type, fetch, company) {
  const r = await axios.post(TALLY_URL, xml(type, fetch, company), { timeout: 120000, headers: { "Content-Type": "text/xml" } });
  const p = await new xml2js.Parser({ explicitArray: false }).parseStringPromise(clean(r.data));
  return list(p?.ENVELOPE?.BODY?.DATA?.COLLECTION?.[type.toUpperCase()]);
}

(async () => {
  console.log(`Tally: ${TALLY_URL}\n`);
  let companies;
  try {
    companies = (await ask("Company", "NAME, GUID")).map((c) => ({ name: text(c.$?.NAME) || text(c.NAME), guid: text(c.GUID) })).filter((c) => c.name);
  } catch (e) {
    console.log(`❌ Could not reach Tally: ${e.message}. Open Tally with the XML server on, then run again.`);
    process.exit(1);
  }
  console.log(`Companies open in Tally: ${companies.length}`);
  for (const c of companies) console.log(`  • ${c.name}`);
  if (companies.length < 2) {
    console.log("\n➡️  Open at least TWO companies in Tally (F3 / Alt+F3 → Select Company), then run again.");
    return;
  }
  console.log("");
  const seen = [];
  for (const c of companies) {
    const t = Date.now();
    try {
      const names = (await ask("Ledger", "NAME", c.name)).map((l) => text(l.$?.NAME) || text(l.NAME)).filter(Boolean);
      const sig = `${names.length}|${names.slice(0, 5).join(",")}`;
      seen.push({ name: c.name, sig });
      console.log(`  ✅ ${c.name.padEnd(36)} ${String(names.length).padStart(6)} ledgers  (${((Date.now() - t) / 1000).toFixed(1)} s)  e.g. ${names.slice(0, 3).join(", ")}`);
    } catch (e) {
      console.log(`  ❌ ${c.name.padEnd(36)} ${e.message}`);
      seen.push({ name: c.name, sig: null });
    }
  }
  console.log("");
  const ok = seen.filter((x) => x.sig);
  const distinct = new Set(ok.map((x) => x.sig)).size;
  if (ok.length < seen.length) {
    console.log("➡️  Tally did not answer for every company: keep multi-company sync OFF and send this output to support.");
  } else if (distinct < ok.length) {
    console.log("➡️  Tally answered the SAME ledgers for different companies: it only serves the company on screen.");
    console.log("    Keep multi-company sync OFF on this PC (the active company still syncs as before).");
  } else {
    console.log("➡️  Each company answered with its own data: you can switch on");
    console.log("    Agent → Companies → \"Sync all enabled companies\".");
  }
})();
