// Tests for the Agent's e-invoice details (node --test), run against
// tally-agent/lib/einvoiceSink.cjs. The vouchers are shaped like Rajlaxmi's
// real Voucher Register export of 15 Sep 2025 (values shortened).
//   AGENT_DIR=<path to tally-agent> node --test einvoiceSink.test.cjs
"use strict";
const { test, describe } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const AGENT_DIR = process.env.AGENT_DIR || path.join(__dirname, "..", "..", "..", "tally-agent");
const { createEinvoiceSink, einvoiceOf, isoDate } = require(path.join(AGENT_DIR, "lib", "einvoiceSink.cjs"));

const ev = (v) => (v == null ? null : typeof v === "string" ? v : typeof v === "object" && v._ ? v._ : null);
const QR = "eyJhbGciOiJSUzI1NiIs" + "x".repeat(926);

/** A voucher as the Agent's parsers give it (arrays of strings). */
function vch(over = {}) {
  const o = {
    GUID: ["g-srv-125"],
    DATE: ["20250915"],
    VOUCHERTYPENAME: ["Tally Service Invoice"],
    VOUCHERNUMBER: ["SRV/0125/25-26"],
    PERSISTEDVIEW: ["Invoice Voucher View"],
    PARTYLEDGERNAME: ["Manisha Steel Centre"],
    PARTYGSTIN: ["27AAIFM2182K1Z0"],
    GSTREGISTRATIONTYPE: ["Regular"],
    CMPGSTIN: ["27AAFCR3058P1ZT"],
    PLACEOFSUPPLY: ["Maharashtra"],
    ISOPTIONAL: ["No"],
    ISCANCELLED: ["No"],
    VCHGSTSTATUSISAPPLICABLE: ["Yes"],
    IRN: ["01352aca6a5d5f12468b" + "0".repeat(44)],
    IRNACKNO: ["122528944683651"],
    IRNACKDATE: ["20251004"],
    IRNQRCODE: [QR],
    IRNCANCELLED: ["No"],
    ISEWAYBILLAPPLICABLE: ["No"],
    "EWAYBILLDETAILS.LIST": [{}],
    "ALLLEDGERENTRIES.LIST": [
      { LEDGERNAME: ["Manisha Steel Centre"], AMOUNT: ["-3540.00"] },
      { LEDGERNAME: ["Service Income"], AMOUNT: ["3000.00"] },
      { LEDGERNAME: ["Output CGST"], AMOUNT: ["270.00"] },
      { LEDGERNAME: ["Output SGST"], AMOUNT: ["270.00"] },
    ],
  };
  for (const [k, v] of Object.entries(over)) {
    if (v === undefined) delete o[k];
    else o[k] = v;
  }
  return o;
}

describe("e-invoice details from a voucher", () => {
  test("an e-invoiced sale: every field Tally saved", () => {
    const r = einvoiceOf(vch(), ev, { voucher_guid: "g-srv-125", voucher_date: "2025-09-15", voucher_type: "Tally Service Invoice" });
    assert.deepEqual(
      { ...r, irn: r.irn.length, signed_qr: r.signed_qr.length },
      {
        voucher_guid: "g-srv-125",
        voucher_date: "2025-09-15",
        voucher_type: "Tally Service Invoice",
        voucher_no: "SRV/0125/25-26",
        party_name: "Manisha Steel Centre",
        party_gstin: "27AAIFM2182K1Z0",
        registration_type: "Regular",
        company_gstin: "27AAFCR3058P1ZT",
        place_of_supply: "Maharashtra",
        amount: 3540,
        is_sale: true,
        is_optional: false,
        is_cancelled: false,
        gst_applicable: true,
        irn: 64,
        ack_no: "122528944683651",
        ack_date: "2025-10-04",
        signed_qr: 946,
        irn_cancelled: false,
        eway_applicable: false,
        eway: null,
      }
    );
  });

  test("proforma (optional, GST not applicable), customer without GST, purchase", () => {
    const pro = einvoiceOf(vch({ IRN: undefined, ISOPTIONAL: ["Yes"], VCHGSTSTATUSISAPPLICABLE: ["No"] }), ev);
    assert.deepEqual([pro.is_optional, pro.gst_applicable, pro.irn], [true, false, null]);
    const b2c = einvoiceOf(vch({ IRN: undefined, PARTYGSTIN: undefined, GSTREGISTRATIONTYPE: ["Unregistered/Consumer"] }), ev);
    assert.deepEqual([b2c.party_gstin, b2c.registration_type], [null, "Unregistered/Consumer"]);
    const pur = einvoiceOf(
      vch({
        IRN: undefined,
        "ALLLEDGERENTRIES.LIST": [
          { LEDGERNAME: ["Manisha Steel Centre"], AMOUNT: ["23099.00"] },
          { LEDGERNAME: ["Purchase"], AMOUNT: ["-23099.00"] },
        ],
      }),
      ev
    );
    assert.deepEqual([pur.is_sale, pur.amount], [false, 23099]);
  });

  test("not an invoice: receipts / journals are not collected; an IRN always is", () => {
    assert.equal(einvoiceOf(vch({ IRN: undefined, PERSISTEDVIEW: ["Accounting Voucher View"] }), ev), null);
    assert.equal(einvoiceOf(vch({ IRN: undefined, PARTYLEDGERNAME: undefined }), ev), null);
    assert.ok(einvoiceOf(vch({ PERSISTEDVIEW: ["Accounting Voucher View"] }), ev).irn);
    assert.equal(einvoiceOf(vch({ GUID: undefined }), ev), null);
    assert.equal(einvoiceOf(null, ev), null);
  });

  test("e-way bill block: its fields as Tally names them", () => {
    const r = einvoiceOf(
      vch({ ISEWAYBILLAPPLICABLE: ["Yes"], "EWAYBILLDETAILS.LIST": [{ BILLNUMBER: ["331012345678"], BILLDATE: ["20250915"], "SUB.LIST": [{}] }] }),
      ev
    );
    assert.equal(r.eway_applicable, true);
    assert.deepEqual(r.eway, { BILLNUMBER: "331012345678", BILLDATE: "20250915" });
    assert.equal(isoDate("20251004"), "2025-10-04");
    assert.equal(isoDate(""), null);
  });
});

describe("the upload beside the voucher sync", () => {
  const quiet = { log() {}, warn() {} };

  test("collected while reading, sent once per voucher in batches", async () => {
    const posts = [];
    const sink = createEinvoiceSink({ post: async (b) => posts.push(b), log: quiet, batchSize: 2 });
    sink.add(vch(), ev);
    sink.add(vch(), ev); // the same voucher read twice: once
    sink.add(vch({ GUID: ["g2"] }), ev);
    sink.add(vch({ GUID: ["g3"] }), ev);
    sink.add(vch({ GUID: ["g4"], IRN: undefined, PERSISTEDVIEW: ["Accounting Voucher View"] }), ev); // a receipt
    assert.equal(sink.pending(), 3);
    const r = await sink.flush("CO-1");
    assert.deepEqual(r, { sent: 3, failed: 0 });
    assert.deepEqual(posts.map((p) => [p.company_guid, p.rows.length]), [["CO-1", 2], ["CO-1", 1]]);
    assert.equal(sink.pending(), 0);
  });

  test("never throws: a bad voucher, a failing server (kept), no route (turned off)", async () => {
    let fail = { response: { status: 503 } };
    const posts = [];
    const sink = createEinvoiceSink({
      post: async (b) => {
        if (fail) throw fail;
        posts.push(b);
      },
      log: quiet,
    });
    assert.doesNotThrow(() => sink.add({ get GUID() { throw new Error("broken"); } }, ev));
    sink.add(vch(), ev);
    assert.deepEqual(await sink.flush("CO-1"), { sent: 0, failed: 1 });
    fail = null;
    sink.add(vch({ GUID: ["g2"] }), ev);
    assert.deepEqual(await sink.flush("CO-1"), { sent: 2, failed: 0 }); // the kept batch too
    fail = { response: { status: 404 } };
    sink.add(vch({ GUID: ["g3"] }), ev);
    assert.deepEqual(await sink.flush("CO-1"), { sent: 0, failed: 0 });
    assert.equal(sink.disabled(), true);
    sink.add(vch({ GUID: ["g4"] }), ev);
    assert.equal(sink.pending(), 0);
  });
});
