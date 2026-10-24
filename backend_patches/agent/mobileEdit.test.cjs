// Tests for the Agent's mobile edit helpers (node --test), run against
// tally-agent/lib/mobileEdit.cjs.
//   AGENT_DIR=<path to tally-agent> node --test mobileEdit.test.cjs
"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const AGENT_DIR = process.env.AGENT_DIR || path.join(__dirname, "..", "..", "..", "tally-agent");
const { mobileTallyGuid, withRemoteId } = require(path.join(AGENT_DIR, "lib", "mobileEdit.cjs"));

const CO = "44acb1ff-18e7-40de-822e-c7f32ad504e4";

test("a created voucher's Tally GUID from the import reply (as the sync reads it)", () => {
  const reply = `<RESPONSE><CREATED>1</CREATED><ALTERED>0</ALTERED><LASTVCHID>37807</LASTVCHID><LASTMID>0</LASTMID></RESPONSE>`;
  assert.equal(mobileTallyGuid(reply, CO), `${CO}-000093af`);
  assert.equal(mobileTallyGuid("<LASTVCHID> 1 </LASTVCHID>", CO), `${CO}-00000001`);
  // No id, no / bad company: not known (never a made-up GUID).
  assert.equal(mobileTallyGuid("<CREATED>1</CREATED>", CO), null);
  assert.equal(mobileTallyGuid("<LASTVCHID>0</LASTVCHID>", CO), null);
  assert.equal(mobileTallyGuid("<LASTVCHID>12</LASTVCHID>", ""), null);
  assert.equal(mobileTallyGuid("<LASTVCHID>12</LASTVCHID>", "not-a-guid"), null);
});

test("an edit names the voucher it changes (REMOTEID), once", () => {
  const xml = `<TALLYMESSAGE>\n<VOUCHER\n  ACTION="Alter"\n  VCHTYPE="Receipt">\n<GUID>${CO}-000093af</GUID>\n</VOUCHER>`;
  const out = withRemoteId(xml, `${CO}-000093af`);
  assert.match(out, new RegExp(`<VOUCHER REMOTEID="${CO}-000093af"\\n  ACTION="Alter"`));
  assert.equal(withRemoteId(out, `${CO}-000093af`), out); // not twice
  assert.equal(withRemoteId(xml, ""), xml);
  assert.match(withRemoteId('<VOUCHER ACTION="Alter">', 'a"b'), /REMOTEID="a&quot;b"/);
});
