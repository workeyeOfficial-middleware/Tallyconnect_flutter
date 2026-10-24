// Tests for the Agent's ledger location (node --test), run against
// tally-agent/lib/ledgerLocation.cjs. Shapes are Lumilo's ledgers as Tally
// exports them (state in LEDSTATENAME, address lines in ADDRESS.LIST).
//   AGENT_DIR=<path to tally-agent> node --test ledgerLocation.test.cjs
"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const AGENT_DIR = process.env.AGENT_DIR || path.join(__dirname, "..", "..", "..", "tally-agent");
const { ledgerLocation } = require(path.join(AGENT_DIR, "lib", "ledgerLocation.cjs"));
const { Parser } = require(path.join(AGENT_DIR, "node_modules", "xml2js"));

const XML = `<LEDGER NAME="3SDM BUSINESS SOLUTIONS PVT LTD">
  <ADDRESS.LIST TYPE="String">
    <ADDRESS TYPE="String">201, Jinam Industrial Est, Dhumal Nagar</ADDRESS>
    <ADDRESS TYPE="String">Waliv, Vasai East -401208</ADDRESS>
  </ADDRESS.LIST>
  <PINCODE TYPE="String">401208</PINCODE>
  <COUNTRYNAME TYPE="String">India</COUNTRYNAME>
  <LEDSTATENAME TYPE="String">Maharashtra</LEDSTATENAME>
</LEDGER>`;

test("Tally's state, PIN, country and address lines", async () => {
  const l = (await new Parser({ explicitArray: false }).parseStringPromise(XML)).LEDGER;
  assert.deepEqual(ledgerLocation(l), {
    state: "Maharashtra",
    pincode: "401208",
    country: "India",
    address: "201, Jinam Industrial Est, Dhumal Nagar, Waliv, Vasai East -401208",
  });
});

test("one address line; mailing details as the fallback; nothing → nulls", () => {
  assert.equal(ledgerLocation({ "ADDRESS.LIST": { ADDRESS: { _: "Andheri, Mumbai" } } }).address, "Andheri, Mumbai");
  assert.deepEqual(
    ledgerLocation({
      "MAILINGDETAILS.LIST": { STATE: "Karnataka", PINCODE: "560 001", "ADDRESS.LIST": { ADDRESS: ["MG Road", "Bengaluru"] } },
    }),
    { state: "Karnataka", pincode: "560001", country: null, address: "MG Road, Bengaluru" }
  );
  assert.deepEqual(ledgerLocation({}), { state: null, pincode: null, country: null, address: null });
  assert.deepEqual(ledgerLocation(null), { state: null, pincode: null, country: null, address: null });
});
