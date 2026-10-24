// Tests for the Agent's voucher types / voucher status (node --test), run
// against tally-agent/lib/voucherTypes.cjs. The voucher types are Lumilo's
// as Tally exports them: "Delivery Note" renamed "Replacement", "Delivery
// Challan" made under it, "PROFORMA INVOICE" under Purchase Order, "Samples"
// under Sales.
//   AGENT_DIR=<path to tally-agent> node --test voucherTypes.test.cjs
"use strict";
const { test, describe } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const AGENT_DIR = process.env.AGENT_DIR || path.join(__dirname, "..", "..", "..", "tally-agent");
const { baseTypeMap, baseTypeOf, noteVoucherStatus, parseVoucherTypes, voucherFlag } = require(
  path.join(AGENT_DIR, "lib", "voucherTypes.cjs")
);
const { parseStringPromise } = require(path.join(AGENT_DIR, "node_modules", "xml2js"));

const vt = (name, reserved, parent) =>
  `<VOUCHERTYPE NAME="${name}" RESERVEDNAME="${reserved}"><PARENT TYPE="String">${parent}</PARENT></VOUCHERTYPE>`;
const XML = `<ENVELOPE><BODY><DATA><COLLECTION>
${vt("Sales", "Sales", "Sales")}
${vt("Purchase", "Purchase", "Purchase")}
${vt("Purchase Order", "Purchase Order", "Purchase Order")}
${vt("Replacement", "Delivery Note", "Delivery Note")}
${vt("Delivery Challan", "", "Replacement")}
${vt("PROFORMA INVOICE", "", "Purchase Order")}
${vt("PROFORMA INVOICE 1", "", "Sales")}
${vt("Samples", "", "Sales")}
${vt("Receipt Note", "Receipt Note", "Receipt Note")}
${vt("Loop A", "", "Loop B")}
${vt("Loop B", "", "Loop A")}
</COLLECTION></DATA></BODY></ENVELOPE>`;

async function types() {
  const p = await parseStringPromise(XML);
  return parseVoucherTypes(p.ENVELOPE.BODY[0].DATA[0].COLLECTION[0].VOUCHERTYPE);
}

describe("built-in type of each voucher type", () => {
  test("Lumilo's renamed and own types resolve to Tally's built-in type", async () => {
    const t = await types();
    assert.equal(baseTypeOf("Sales", t), "Sales");
    assert.equal(baseTypeOf("Replacement", t), "Delivery Note");
    assert.equal(baseTypeOf("Delivery Challan", t), "Delivery Note");
    assert.equal(baseTypeOf("PROFORMA INVOICE", t), "Purchase Order");
    assert.equal(baseTypeOf("PROFORMA INVOICE 1", t), "Sales");
    assert.equal(baseTypeOf("samples", t), "Sales"); // any case
    assert.equal(baseTypeOf("Receipt Note", t), "Receipt Note");
  });

  test("unknown, looping or empty: not known (null)", async () => {
    const t = await types();
    assert.equal(baseTypeOf("No Such Type", t), null);
    assert.equal(baseTypeOf("Loop A", t), null);
    assert.equal(baseTypeOf("Sales", new Map()), null);
    assert.equal(baseTypeOf("", t), null);
    assert.deepEqual(parseVoucherTypes(null), new Map());
    assert.deepEqual(parseVoucherTypes([null, 5, {}]), new Map());
  });

  test("the map holds only the types that resolve", async () => {
    const m = baseTypeMap(await types());
    assert.equal(m.get("delivery challan"), "Delivery Note");
    assert.equal(m.has("loop a"), false);
    assert.equal(m.size, 9);
  });
});

describe("voucher status sent with the voucher", () => {
  // Shaped like a Voucher Register voucher (arrays of strings).
  const v = (type, cancelled, optional) => ({
    $: { VCHTYPE: type },
    VOUCHERTYPENAME: [type],
    ISCANCELLED: cancelled == null ? undefined : [cancelled],
    ISOPTIONAL: optional == null ? undefined : [optional],
  });

  test("flags: Yes / No, not exported = not known", () => {
    assert.equal(voucherFlag(v("Sales", "Yes", "No"), "ISCANCELLED"), true);
    assert.equal(voucherFlag(v("Sales", "No", "No"), "ISCANCELLED"), false);
    assert.equal(voucherFlag(v("Sales"), "ISCANCELLED"), null);
    assert.equal(voucherFlag({ ISOPTIONAL: [{ _: "Yes" }] }, "ISOPTIONAL"), true);
    assert.equal(voucherFlag(null, "ISOPTIONAL"), null);
  });

  test("a cancelled sale, an optional challan, a purchase order", async () => {
    const m = baseTypeMap(await types());
    const a = noteVoucherStatus({ voucher_type: "Sales" }, v("Sales", "Yes", "No"), m);
    assert.deepEqual(a, { voucher_type: "Sales", is_cancelled: true, is_optional: false, base_type: "Sales" });
    const b = noteVoucherStatus({ voucher_type: "Delivery Challan" }, v("Delivery Challan", "No", "Yes"), m);
    assert.equal(b.is_optional, true);
    assert.equal(b.base_type, "Delivery Note");
    const c = noteVoucherStatus({ voucher_type: "PROFORMA INVOICE" }, v("PROFORMA INVOICE", "No", "No"), m);
    assert.equal(c.base_type, "Purchase Order");
  });

  test("nothing known: the voucher is sent exactly as before", () => {
    const vd = { voucher_type: "Sales", amount: 10 };
    noteVoucherStatus(vd, v("Sales"), null);
    assert.deepEqual(vd, { voucher_type: "Sales", amount: 10 });
    noteVoucherStatus(vd, null, undefined); // never throws
    assert.deepEqual(vd, { voucher_type: "Sales", amount: 10 });
  });
});
