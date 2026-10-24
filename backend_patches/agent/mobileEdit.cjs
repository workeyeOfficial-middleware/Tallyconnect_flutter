// Mobile entries in Tally: the GUID Tally gave a created voucher, and how
// an edit names the voucher it alters.
//
// Tally does not keep a GUID sent with a NEW voucher: it gives the voucher
// its own — the company GUID and the voucher's id in hex
// ("44acb1ff-…-c7f32ad504e4-000093af", as every synced voucher has). Its
// import reply carries that id (LASTVCHID), so the GUID is worked out from
// it and kept by the server: an edit later alters exactly that voucher.
"use strict";

/** Tally's GUID of the voucher a create reply made, or null. */
function mobileTallyGuid(reply, companyGuid) {
  const m = String(reply || "").match(/<LASTVCHID>\s*(\d+)\s*<\/LASTVCHID>/i);
  const id = m ? Number(m[1]) : 0;
  if (!id || !companyGuid || !/^[0-9a-f-]{36}$/i.test(String(companyGuid))) return null;
  return `${companyGuid}-${id.toString(16).padStart(8, "0")}`;
}

/**
 * An ALTER's XML names the voucher it changes: REMOTEID = its Tally GUID
 * on the <VOUCHER> element (the <GUID> inside stays). Unchanged when it is
 * already there or the GUID is missing.
 */
function withRemoteId(xml, guid) {
  const g = String(guid || "").trim();
  if (!g || /<VOUCHER[^>]*REMOTEID=/i.test(xml)) return xml;
  const esc = g.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");
  return xml.replace(/<VOUCHER(\s)/, `<VOUCHER REMOTEID="${esc}"$1`);
}

module.exports = { mobileTallyGuid, withRemoteId };
