// =====================================================================
//  CASH FLOW PROBE — can this Tally export its own Cash Flow reports?
//  ---------------------------------------------------------------------
//  Run ONCE on the Tally PC, outside business hours, with the company open
//  in Tally and the TallyConnect Agent STOPPED:
//
//      node tools/cashflow-probe.cjs "GI Apr 25-26"
//      (TALLY_URL=http://localhost:9000 by default)
//
//  It asks Tally for its "Cash Flow" (past months: cash in / out) and
//  "Cash Flow Projection" (future: receivables / payables by due date)
//  reports under the names Tally versions use, one request at a time, each
//  with a 120-second limit, and saves every answer to
//      cashflow-probe-out/<report>.xml
//  It stops at the first request Tally does not answer in time (Tally may
//  then stay busy for a while — wait until Tally responds again).
//  Read-only: nothing is changed in Tally or sent anywhere else.
//
//  Send back: the summary printed at the end + the .xml files (zip the
//  cashflow-probe-out folder). They show which report name works, how long
//  Tally takes, and what the figures look like.
// =====================================================================
"use strict";
const fs = require("fs");
const path = require("path");
const axios = require("axios");

const TALLY_URL = (process.env.TALLY_URL || "http://localhost:9000").replace(/\/+$/, "");
const company = process.argv[2];
const LIMIT_MS = 120000;
const OUT = path.join(process.cwd(), "cashflow-probe-out");

if (!company) {
  console.log('Usage: node tools/cashflow-probe.cjs "<company name exactly as in Tally>"');
  process.exit(1);
}

const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const ymd = (d) => `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, "0")}${String(d.getDate()).padStart(2, "0")}`;

const today = new Date();
// Past: the last 3 full months (Cash Flow is history).
const pastFrom = new Date(today.getFullYear(), today.getMonth() - 3, 1);
const pastTo = new Date(today.getFullYear(), today.getMonth(), 0);
// Future: the next 13 weeks (Cash Flow Projection).
const nextTo = new Date(today.getFullYear(), today.getMonth(), today.getDate() + 91);

/** Export request for one report (what the Agent would send). */
function reportXml(name, from, to) {
  return `
<ENVELOPE>
 <HEADER>
  <TALLYREQUEST>Export Data</TALLYREQUEST>
 </HEADER>
 <BODY>
  <EXPORTDATA>
   <REQUESTDESC>
    <REPORTNAME>${esc(name)}</REPORTNAME>
    <STATICVARIABLES>
     <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
     <SVCURRENTCOMPANY>${esc(company)}</SVCURRENTCOMPANY>
     <SVFROMDATE>${ymd(from)}</SVFROMDATE>
     <SVTODATE>${ymd(to)}</SVTODATE>
    </STATICVARIABLES>
   </REQUESTDESC>
  </EXPORTDATA>
 </BODY>
</ENVELOPE>`;
}

// Names Tally versions use for these reports (first that answers wins).
const TRIES = [
  { kind: "Cash Flow (past)", names: ["Cash Flow", "Cash Flow Statement", "Cash Flow Summary"], from: pastFrom, to: pastTo },
  {
    kind: "Cash Flow Projection (future)",
    names: ["Cash Flow Projection", "CashFlowProjection", "Cash Flow Projection Report"],
    from: today,
    to: nextTo,
  },
  { kind: "Funds Flow (past, for comparison)", names: ["Funds Flow", "Fund Flow"], from: pastFrom, to: pastTo },
];

/** What came back: not found / error / data, with a short look inside. */
function readAnswer(xml) {
  const s = String(xml || "");
  if (/could not find (report|the report)/i.test(s) || /Report\s*'[^']*'\s*does not exist/i.test(s)) {
    return { found: false, note: "report name not known to this Tally" };
  }
  const err = /<LINEERROR>([\s\S]*?)<\/LINEERROR>/i.exec(s);
  if (err) return { found: false, note: `Tally error: ${err[1].trim().slice(0, 160)}` };
  const tags = [...s.matchAll(/<([A-Z][A-Z0-9.]{2,40})[\s>]/g)].map((m) => m[1]);
  const top = Object.entries(tags.reduce((a, t) => ((a[t] = (a[t] || 0) + 1), a), {}))
    .sort((a, b) => b[1] - a[1])
    .slice(0, 8)
    .map(([t, n]) => `${t}×${n}`)
    .join(", ");
  const amounts = (s.match(/-?\d[\d,]*\.\d{2}/g) || []).length;
  if (s.length < 300 && !amounts) return { found: false, note: `empty answer: ${s.replace(/\s+/g, " ").trim().slice(0, 160)}` };
  return { found: true, note: `${amounts} amounts · tags: ${top}` };
}

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  console.log(`Tally: ${TALLY_URL}   Company: ${company}`);
  console.log(`Past period ${ymd(pastFrom)}–${ymd(pastTo)} · next 13 weeks ${ymd(today)}–${ymd(nextTo)}\n`);
  const summary = [];
  outer: for (const t of TRIES) {
    console.log(`${t.kind}`);
    let got = false;
    for (const name of t.names) {
      const started = Date.now();
      try {
        const res = await axios.post(TALLY_URL, reportXml(name, t.from, t.to), {
          timeout: LIMIT_MS,
          headers: { "Content-Type": "text/xml" },
          responseType: "text",
          transformResponse: (x) => x,
        });
        const secs = ((Date.now() - started) / 1000).toFixed(1);
        const body = String(res.data || "");
        const file = path.join(OUT, `${name.replace(/[^A-Za-z0-9]+/g, "_")}.xml`);
        fs.writeFileSync(file, body);
        const a = readAnswer(body);
        const kb = Math.round(body.length / 1024);
        console.log(`  ${a.found ? "✅" : "➖"} "${name}"  ${secs}s  ${kb} KB  ${a.note}`);
        summary.push({ kind: t.kind, name, found: a.found, secs: Number(secs), kb, note: a.note });
        if (a.found) {
          got = true;
          break;
        }
      } catch (e) {
        const secs = ((Date.now() - started) / 1000).toFixed(1);
        const slow = e.code === "ECONNABORTED" || /timeout/i.test(String(e.message));
        console.log(`  ❌ "${name}"  ${secs}s  ${slow ? "NO ANSWER IN 120 s — stopping (Tally may stay busy for a while)" : e.message}`);
        summary.push({ kind: t.kind, name, found: false, secs: Number(secs), note: slow ? "timeout" : e.message });
        if (slow) break outer;
      }
    }
    if (!got) console.log("  → none of these names worked on this Tally");
    console.log("");
  }
  fs.writeFileSync(path.join(OUT, "summary.json"), JSON.stringify({ company, tally: TALLY_URL, at: new Date().toISOString(), summary }, null, 2));
  console.log(`Saved in ${OUT}`);
  console.log("Send back this summary and the files in that folder (zip it).");
})();
