// =====================================================================
//  TALLY PROBE — read-only checks before changing how the Agent syncs
//  ---------------------------------------------------------------------
//  Run on the Tally PC, outside working hours, with the TallyConnect Agent
//  STOPPED and the company open in TallyPrime. Watch the Tally screen while
//  it runs (note any message box that pops up).
//
//      node tools/tally-probe.cjs "GI Apr 25-26"
//      node tools/tally-probe.cjs "GI Apr 25-26" --reports   (+ Tally's own
//                         Trial Balance, P&L, Balance Sheet, Cash Flow reports)
//      node tools/tally-probe.cjs "GI Apr 25-26" --heavy     (+ stock values)
//      node tools/tally-probe.cjs "GI Apr 25-26" --heavy --risky
//                         (+ stock with a date range: the request kind that
//                          froze Tally before — only while you watch Tally)
//
//  Options: --gap=5000 (ms between requests)  --window-limit=90000 and
//  --heavy-limit=120000 (ms a request may take)  --agent-ok (skip the
//  "is the Agent running?" check)  TALLY_URL=http://localhost:9000
//
//  What it checks, one request at a time, lightest first:
//    1. open companies; the company's change counters (ALTVCHID / ALTMSTID),
//       books / period dates
//    2. company isolation: ledger lists and the last 7 days of vouchers of
//       each open company must differ
//    3. Voucher Register timings: 3 days, this month, the next 200 days
//    4. vouchers changed after an AlterID (new / edited / back- or
//       future-dated, any date), and "nothing new" with the latest AlterID
//    5. --heavy: closing value of 20 stock items; Stock Summary as on the
//       last month end   6. --risky: Stock-in-Hand with a date range
//  After every request a tiny request checks Tally answers again; if Tally
//  stays busy or a request times out, the probe stops at once.
//
//  Read-only: only "Export Data" requests to Tally; nothing is changed in
//  Tally and nothing is sent anywhere else. Results (summary.json plus the
//  first 300 KB of each answer) go to tally-probe-out/ — they contain your
//  business data, keep them private. Send back the printed summary and
//  summary.json.
//
//  Tip: run it, change one OLD voucher in Tally (e.g. its narration), run it
//  again — both summaries together show whether the counters move and the
//  edited voucher is found by its AlterID.
// =====================================================================
"use strict";
const fs = require("fs");
const http = require("http");
const path = require("path");
const axios = require("axios");

const argv = process.argv.slice(2);
const flag = (n) => argv.includes(`--${n}`);
const opt = (n, d) => {
  const a = argv.find((x) => x.startsWith(`--${n}=`));
  return a ? Number(a.split("=")[1]) : d;
};
const company = argv.find((x) => !x.startsWith("--"));
const TALLY_URL = (process.env.TALLY_URL || "http://localhost:9000").replace(/\/+$/, "");
const GAP_MS = opt("gap", 5000);
const HEAVY = flag("heavy");
const RISKY = flag("risky");
const REPORTS = flag("reports");
const LIMIT = { light: 30000, window: opt("window-limit", 90000), heavy: opt("heavy-limit", 120000) };
const PING_OK_MS = 5000; // Tally counts as idle when the tiny request answers within this
const PING_WAIT_MS = 60000; // how long to wait for Tally to answer again before stopping
const SAMPLE_BYTES = 300 * 1024;

if (!company) {
  console.log('Usage: node tools/tally-probe.cjs "<company name exactly as in Tally>" [--heavy] [--risky] [--gap=5000]');
  process.exit(1);
}

const stamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
const OUT = path.join(process.env.PROBE_OUT || path.join(process.cwd(), "tally-probe-out"), `${company.replace(/[^A-Za-z0-9]+/g, "_")}_${stamp}`);

// One socket: Tally answers one request at a time.
const tally = axios.create({
  httpAgent: new http.Agent({ keepAlive: true, maxSockets: 1 }),
  headers: { "Content-Type": "text/xml" },
  responseType: "text",
  transformResponse: (x) => x,
});

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const esc = (s) => String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const pad = (n) => String(n).padStart(2, "0");
const ymd = (d) => `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}`;
const addDays = (d, n) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
const decode = (s) =>
  String(s ?? "")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .trim();

// ------------------------------------------------------------ requests
function collectionXml(id, type, fetch, { co, filter, from, to } = {}) {
  return `<ENVELOPE>
 <HEADER><VERSION>1</VERSION><TALLYREQUEST>Export Data</TALLYREQUEST><TYPE>Collection</TYPE><ID>${id}</ID></HEADER>
 <BODY><DESC>
  <STATICVARIABLES>
   <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>${co ? `\n   <SVCURRENTCOMPANY>${esc(co)}</SVCURRENTCOMPANY>` : ""}${
    from ? `\n   <SVFROMDATE>${from}</SVFROMDATE><SVTODATE>${to}</SVTODATE>` : ""
  }
  </STATICVARIABLES>
  <TDL><TDLMESSAGE>
   <COLLECTION NAME="${id}"><TYPE>${type}</TYPE><FETCH>${fetch}</FETCH>${filter ? `<FILTER>${id}Filter</FILTER>` : ""}</COLLECTION>${
    filter ? `\n   <SYSTEM TYPE="Formulae" NAME="${id}Filter">${filter}</SYSTEM>` : ""
  }
  </TDLMESSAGE></TDL>
 </DESC></BODY>
</ENVELOPE>`;
}

function reportXml(name, co, from, to) {
  return `<ENVELOPE>
 <HEADER><TALLYREQUEST>Export Data</TALLYREQUEST></HEADER>
 <BODY><EXPORTDATA><REQUESTDESC>
  <REPORTNAME>${esc(name)}</REPORTNAME>
  <STATICVARIABLES>
   <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
   <SVCURRENTCOMPANY>${esc(co)}</SVCURRENTCOMPANY>${from ? `\n   <SVFROMDATE>${from}</SVFROMDATE>` : ""}
   <SVTODATE>${to}</SVTODATE>
  </STATICVARIABLES>
 </REQUESTDESC></EXPORTDATA></BODY>
</ENVELOPE>`;
}

const PING_XML = collectionXml("TCProbePing", "Company", "NAME");
const nameFilter = (names) => names.map((n) => `$Name = "${esc(String(n).replace(/"/g, ""))}"`).join(" OR ");

// ------------------------------------------------------------- reading
const blocks = (xml, tag) => {
  const out = [];
  // <TAG …>…</TAG> or a self-closing <TAG …/>
  const re = new RegExp(`<${tag}\\b([^>]*?)(?:/>|>([\\s\\S]*?)</${tag}>)`, "g");
  let m;
  while ((m = re.exec(String(xml || "")))) out.push({ attrs: m[1], body: m[2] || "" });
  return out;
};
const field = (body, f) => {
  const m = new RegExp(`<${f}\\b[^>]*>([^<]*)</${f}>`).exec(body);
  return m ? decode(m[1]) : "";
};
const nameOf = (b) => decode((/\bNAME="([^"]*)"/.exec(b.attrs) || [])[1] || "") || field(b.body, "NAME");
const lineError = (xml) => {
  const m = /<LINEERROR>([\s\S]*?)<\/LINEERROR>/i.exec(String(xml || ""));
  return m ? decode(m[1]).slice(0, 200) : null;
};

/** Vouchers of an answer: [{guid, alterid, date, type}] (one per GUID). */
function vouchersOf(xml) {
  const seen = new Map();
  for (const b of blocks(xml, "VOUCHER")) {
    const guid = field(b.body, "GUID");
    if (!guid || seen.has(guid)) continue;
    const alter = Number(field(b.body, "ALTERID"));
    seen.set(guid, {
      guid,
      alterid: Number.isFinite(alter) && field(b.body, "ALTERID") !== "" ? alter : null,
      date: field(b.body, "DATE").replace(/[^0-9]/g, ""),
      type: field(b.body, "VOUCHERTYPENAME"),
    });
  }
  return [...seen.values()];
}

function hashNames(names) {
  let h = 0;
  for (const s of [...names].sort().join("\n")) h = (h * 31 + s.charCodeAt(0)) | 0;
  return (h >>> 0).toString(16);
}

// ------------------------------------------------------------ the probe
const results = [];
let stopped = null;

async function send(xml, timeout) {
  const t0 = Date.now();
  try {
    const res = await tally.post(TALLY_URL, xml, { timeout });
    const body = String(res.data || "");
    return { ok: true, ms: Date.now() - t0, body };
  } catch (e) {
    const timedOut = e.code === "ECONNABORTED" || /timeout/i.test(String(e.message));
    return { ok: false, ms: Date.now() - t0, timedOut, error: timedOut ? `no answer in ${timeout / 1000} s` : e.message };
  }
}

/** Does Tally answer the tiny request quickly? Waits up to PING_WAIT_MS. */
async function tallyIdle() {
  const t0 = Date.now();
  while (Date.now() - t0 < PING_WAIT_MS) {
    const r = await send(PING_XML, PING_WAIT_MS);
    if (r.ok && r.ms <= PING_OK_MS) return { idle: true, ms: r.ms, waited: Date.now() - t0 };
    if (!r.ok && r.timedOut) break;
    await sleep(3000);
  }
  return { idle: false, ms: null, waited: Date.now() - t0 };
}

/**
 * One check: rest, make sure Tally is idle, send, save a sample, read it,
 * then see how quickly Tally answers again.
 */
async function step(id, title, kind, xml, read = () => ({})) {
  if (stopped) return null;
  await sleep(GAP_MS);
  const before = await tallyIdle();
  if (!before.idle) {
    stopped = `Tally did not answer a tiny request before "${title}" — stopped.`;
    results.push({ id, title, kind, skipped: true, note: stopped });
    return null;
  }
  process.stdout.write(`  ${title} … `);
  const r = await send(xml, LIMIT[kind]);
  const row = { id, title, kind, seconds: +(r.ms / 1000).toFixed(1) };
  if (!r.ok) {
    row.error = r.error;
    console.log(`❌ ${r.error}`);
    if (r.timedOut) stopped = `"${title}" got no answer in ${LIMIT[kind] / 1000} s — stopped (Tally may stay busy for a while; wait until it responds).`;
    results.push(row);
    return null;
  }
  row.kb = Math.round(r.body.length / 1024);
  fs.writeFileSync(path.join(OUT, `${id}.xml`), r.body.slice(0, SAMPLE_BYTES));
  const err = lineError(r.body);
  if (err) row.tally_error = err;
  let info = {};
  try {
    info = read(r.body) || {};
  } catch (e) {
    info = { read_error: e.message };
  }
  Object.assign(row, info);
  const after = await tallyIdle();
  row.tally_answers_again_s = after.idle ? +(after.waited / 1000).toFixed(1) : null;
  console.log(`${row.seconds} s · ${row.kb} KB${err ? ` · Tally: ${err}` : ""}${info.note ? ` · ${info.note}` : ""}`);
  results.push(row);
  if (!after.idle) stopped = `Tally stayed busy for over ${PING_WAIT_MS / 1000} s after "${title}" — stopped.`;
  return { body: r.body, row };
}

async function agentRunning() {
  try {
    await axios.get("http://localhost:5001/", { timeout: 2000 });
    return true;
  } catch (e) {
    return !!e.response; // any HTTP answer means something is listening
  }
}

(async () => {
  if (!flag("agent-ok") && (await agentRunning())) {
    console.log("The TallyConnect Agent seems to be running (http://localhost:5001 answers).");
    console.log("Stop it first so the probe has Tally to itself, or add --agent-ok.");
    process.exit(2);
  }
  fs.mkdirSync(OUT, { recursive: true });
  const today = new Date();
  const T = ymd(today);
  console.log(`Tally ${TALLY_URL} · company "${company}" · gap ${GAP_MS / 1000} s${REPORTS ? " · reports" : ""}${HEAVY ? " · heavy" : ""}${RISKY ? " · risky" : ""}\n`);

  // ---- 1. companies, counters, dates
  console.log("1. Companies and change counters");
  const open = [];
  await step("01_companies", "Open companies", "light", collectionXml("TCProbeCompanies", "Company", "NAME, GUID"), (x) => {
    for (const b of blocks(x, "COMPANY")) open.push({ name: nameOf(b), guid: field(b.body, "GUID") });
    return { open_companies: open.map((c) => c.name), note: `${open.length} open: ${open.map((c) => c.name).join(", ")}` };
  });
  if (!stopped && !open.some((c) => c.name === company)) {
    stopped = `"${company}" is not open in Tally (open: ${open.map((c) => c.name).join(", ") || "none"}).`;
  }
  let counters = {};
  await step(
    "02_company_info",
    "Change counters and dates",
    "light",
    collectionXml("TCProbeCompanyInfo", "Company", "NAME, GUID, STARTINGFROM, BOOKSFROM, ALTVCHID, ALTMSTID, LASTVOUCHERDATE, PERTODATE, YEARENDS", { co: company }),
    (x) => {
      const all = blocks(x, "COMPANY").map((b) => ({
        name: nameOf(b),
        altvchid: field(b.body, "ALTVCHID") || null,
        altmstid: field(b.body, "ALTMSTID") || null,
        starting_from: field(b.body, "STARTINGFROM") || null,
        books_from: field(b.body, "BOOKSFROM") || null,
        last_voucher_date: field(b.body, "LASTVOUCHERDATE") || null,
        period_to: field(b.body, "PERTODATE") || null,
        year_ends: field(b.body, "YEARENDS") || null,
      }));
      counters = all.find((c) => c.name === company) || {};
      return {
        companies_returned: all.map((c) => c.name),
        target: counters,
        note: `ALTVCHID=${counters.altvchid ?? "—"} ALTMSTID=${counters.altmstid ?? "—"} books ${counters.books_from || counters.starting_from || "—"} · answered for ${all.length} compan${all.length === 1 ? "y" : "ies"}`,
      };
    }
  );

  // ---- 2. company isolation
  console.log("\n2. Company isolation (each company must get its own data)");
  const ledgerSets = {};
  for (const c of open) {
    await step(`03_ledgers_${c.name.replace(/[^A-Za-z0-9]+/g, "_")}`, `Ledger list of "${c.name}"`, "light", collectionXml("TCProbeLedgers", "Ledger", "NAME", { co: c.name }), (x) => {
      const names = blocks(x, "LEDGER").map(nameOf).filter(Boolean);
      ledgerSets[c.name] = { count: names.length, hash: hashNames(names) };
      return { ledgers: names.length, names_hash: ledgerSets[c.name].hash, note: `${names.length} ledgers` };
    });
  }
  const from7 = ymd(addDays(today, -6));
  const vch7 = {};
  for (const c of open) {
    await step(`04_vouchers7_${c.name.replace(/[^A-Za-z0-9]+/g, "_")}`, `Last 7 days of vouchers of "${c.name}"`, "window", reportXml("Voucher Register", c.name, from7, T), (x) => {
      const v = vouchersOf(x);
      vch7[c.name] = v;
      const outside = v.filter((z) => z.date && (z.date < from7 || z.date > T)).length;
      return { vouchers: v.length, outside_range: outside, note: `${v.length} vouchers${outside ? `, ${outside} OUTSIDE the 7 days (whole book?)` : ""}` };
    });
  }

  // ---- 3. window timings
  console.log("\n3. Voucher windows");
  const monthFrom = `${T.slice(0, 6)}01`;
  await step("05_window_3d", "Voucher Register, 3 days", "window", reportXml("Voucher Register", company, ymd(addDays(today, -2)), T), (x) => {
    const v = vouchersOf(x);
    return { vouchers: v.length, note: `${v.length} vouchers` };
  });
  await step("06_window_month", "Voucher Register, this month", "window", reportXml("Voucher Register", company, monthFrom, T), (x) => {
    const v = vouchersOf(x);
    const outside = v.filter((z) => z.date && (z.date < monthFrom || z.date > T)).length;
    return { vouchers: v.length, outside_range: outside, note: `${v.length} vouchers${outside ? `, ${outside} outside the month` : ""}` };
  });
  const futTo = ymd(addDays(today, 200));
  await step("07_window_future", "Voucher Register, next 200 days", "window", reportXml("Voucher Register", company, ymd(addDays(today, 1)), futTo), (x) => {
    const v = vouchersOf(x);
    return { vouchers: v.length, months: [...new Set(v.map((z) => z.date.slice(0, 6)))], note: `${v.length} future-dated vouchers` };
  });

  // ---- 4. vouchers by AlterID
  console.log("\n4. Changed vouchers by AlterID");
  const sample = vch7[company] || [];
  const sampleMax = Math.max(0, ...sample.map((v) => v.alterid || 0));
  const counterMax = Number(counters.altvchid) || 0;
  const top = Math.max(sampleMax, counterMax);
  const alterInfo = { sample_max_alterid: sampleMax || null, altvchid: counterMax || null };
  if (!top) {
    results.push({ id: "08_alterid", title: "Vouchers after an AlterID", skipped: true, note: "no AlterID known (no ALTVCHID, no ALTERID in the 7-day vouchers)" });
    console.log("  skipped: no AlterID known");
  } else {
    const after = Math.max(0, top - 25);
    const fetch = "GUID, ALTERID, DATE, VOUCHERTYPENAME, VOUCHERNUMBER, ISCANCELLED, ISOPTIONAL";
    await step("08_alterid_25", `Vouchers with AlterID > ${after}`, "window", collectionXml("TCProbeAlter", "Voucher", fetch, { co: company, filter: `$AlterId &gt; ${after}` }), (x) => {
      const v = vouchersOf(x);
      const ids = v.map((z) => z.alterid).filter((n) => n !== null);
      const bad = ids.filter((n) => n <= after).length;
      const expect = sample.filter((s) => s.alterid !== null && s.alterid > after);
      const got = new Set(v.map((z) => z.guid));
      const missing = expect.filter((s) => !got.has(s.guid)).length;
      const dates = v.map((z) => z.date).filter(Boolean).sort();
      return {
        ...alterInfo,
        after,
        vouchers: v.length,
        not_above_after: bad,
        sample_expected: expect.length,
        sample_missing: missing,
        dates: dates.length ? [dates[0], dates[dates.length - 1]] : [],
        cancelled: blocks(x, "VOUCHER").filter((b) => /^yes$/i.test(field(b.body, "ISCANCELLED"))).length,
        optional: blocks(x, "VOUCHER").filter((b) => /^yes$/i.test(field(b.body, "ISOPTIONAL"))).length,
        note: `${v.length} vouchers (wanted ≤ 25-ish), ${bad} not above ${after}, ${missing}/${expect.length} recent ones missing, dates ${dates[0] || "—"}…${dates[dates.length - 1] || "—"}`,
      };
    });
    await step("09_alterid_none", `Vouchers with AlterID > ${top} (nothing new)`, "window", collectionXml("TCProbeAlterNone", "Voucher", "GUID, ALTERID", { co: company, filter: `$AlterId &gt; ${top}` }), (x) => {
      const v = vouchersOf(x);
      return { after: top, vouchers: v.length, note: `${v.length} vouchers (0 expected unless something changed meanwhile)` };
    });
  }

  // ---- 5. Tally's own reports, as displayed (P&L / Balance Sheet value stock)
  if (REPORTS) {
    console.log("\n5. Tally's own reports (year to date)");
    const fyStart = today.getMonth() >= 3 ? `${today.getFullYear()}0401` : `${today.getFullYear() - 1}0401`;
    for (const [id, name] of [
      ["14_report_tb", "Trial Balance"],
      ["15_report_pl", "Profit and Loss"],
      ["16_report_bs", "Balance Sheet"],
      ["17_report_cf", "Cash Flow"],
    ]) {
      await step(id, `${name} report ${fyStart}–${T}`, "heavy", reportXml(name, company, fyStart, T), (x) => {
        const amounts = (x.match(/-?\d[\d,]*\.\d{2}/g) || []).length;
        return { from: fyStart, to: T, amounts, note: `${amounts} amounts` };
      });
    }
  }

  // ---- 6. stock values (Tally values stock: can be heavy)
  if (HEAVY) {
    console.log("\n5. Stock values");
    let items = [];
    await step("10_stock_names", "Stock item names", "light", collectionXml("TCProbeItems", "StockItem", "NAME", { co: company }), (x) => {
      items = blocks(x, "STOCKITEM").map(nameOf).filter(Boolean);
      return { items: items.length, note: `${items.length} items` };
    });
    if (items.length) {
      const some = items.slice(0, 20);
      await step("11_stock_20", "Closing value of 20 items (current period)", "heavy", collectionXml("TCProbeItemValues", "StockItem", "NAME, CLOSINGVALUE", { co: company, filter: nameFilter(some) }), (x) => {
        const n = blocks(x, "STOCKITEM").length;
        return { items: n, note: `${n} items valued` };
      });
      const monthEnd = ymd(new Date(today.getFullYear(), today.getMonth(), 0));
      await step("12_stock_summary", `Stock Summary as on ${monthEnd}`, "heavy", reportXml("Stock Summary", company, null, monthEnd), (x) => {
        const amounts = (x.match(/-?\d[\d,]*\.\d{2}/g) || []).length;
        return { as_on: monthEnd, amounts, note: `${amounts} amounts` };
      });
      if (RISKY) {
        const fyFrom = today.getMonth() >= 3 ? `${today.getFullYear()}0401` : `${today.getFullYear() - 1}0401`;
        await step(
          "13_stock_in_hand_range",
          `Stock-in-Hand ${fyFrom}–${monthEnd} (date range)`,
          "heavy",
          collectionXml("TCProbeStockGroup", "Group", "NAME, CLOSINGBALANCE", { co: company, from: fyFrom, to: monthEnd, filter: `$Name = $$GroupStock OR $Name = "Stock-in-Hand"` }),
          (x) => ({ value: field(x, "CLOSINGBALANCE") || null, note: `closing ${field(x, "CLOSINGBALANCE") || "—"}` })
        );
      }
    }
  }

  // ---- summary
  const ran = results.filter((r) => typeof r.seconds === "number");
  const slowest = [...ran].sort((a, b) => b.seconds - a.seconds)[0];
  const names = Object.keys(ledgerSets);
  const dupLedgers = names.length > 1 && new Set(names.map((n) => ledgerSets[n].hash)).size < names.length;
  const vNames = Object.keys(vch7);
  let sharedVouchers = 0;
  if (vNames.length > 1) {
    const sets = vNames.map((n) => new Set(vch7[n].map((v) => v.guid)));
    for (const g of sets[0]) if (sets.slice(1).some((s) => s.has(g))) sharedVouchers++;
  }
  const alter = results.find((r) => r.id === "08_alterid_25");
  const findings = {
    counters_returned: { altvchid: !!counters.altvchid, altmstid: !!counters.altmstid },
    company_info_answers_for: (results.find((r) => r.id === "02_company_info") || {}).companies_returned || null,
    isolation: names.length < 2 ? (open.length < 2 ? "only one company open — open a second company to test" : "not tested") : dupLedgers || sharedVouchers ? `BROKEN (same ledger list: ${dupLedgers}, vouchers shared: ${sharedVouchers})` : "ok",
    alterid_filter: !alter
      ? "not tested"
      : alter.error
        ? `failed: ${alter.error}`
        : alter.vouchers === 0
          ? "returned nothing — filter not usable on this Tally"
          : alter.not_above_after || alter.sample_missing
            ? "unreliable (see 08_alterid_25)"
            : "works",
    slowest: slowest ? `${slowest.title}: ${slowest.seconds} s` : null,
    stopped,
  };
  fs.writeFileSync(path.join(OUT, "summary.json"), JSON.stringify({ company, tally: TALLY_URL, at: new Date().toISOString(), gap_ms: GAP_MS, heavy: HEAVY, risky: RISKY, findings, results }, null, 2));

  console.log("\nFindings");
  console.log(`  Change counters returned: ALTVCHID ${findings.counters_returned.altvchid ? "yes" : "NO"}, ALTMSTID ${findings.counters_returned.altmstid ? "yes" : "NO"}`);
  console.log(`  Company isolation: ${findings.isolation}`);
  console.log(`  AlterID filter on vouchers: ${findings.alterid_filter}`);
  console.log(`  Slowest request: ${findings.slowest || "—"}`);
  if (stopped) console.log(`  ⚠️ ${stopped}`);
  console.log(`\nSaved in ${OUT}`);
  console.log("Send back this summary and summary.json (the .xml files hold your business data — keep them private).");
})();
