// Voucher types and voucher status, as Tally keeps them.
//
// A company can rename a built-in voucher type ("Delivery Note" saved as
// "Replacement") or make its own under one ("Delivery Challan" under
// "Replacement", "PROFORMA INVOICE" under "Purchase Order"). Tally's
// VoucherType master keeps the built-in name in the RESERVEDNAME attribute
// (empty for a type the company made) and the type it was made under in
// PARENT. Following PARENT to a reserved type gives the built-in type every
// voucher really is, whatever the company calls it — that decides whether it
// posts to the books (Sales, Receipt, …) or not (orders, notes, stock).
//
// Cancelled (ISCANCELLED) and optional (ISOPTIONAL) vouchers are flags on the
// voucher itself: Tally's books leave both out.
//
// Everything here is read only and never throws: on anything unexpected the
// answer is null ("not known"), and the server keeps today's behaviour.

/** The leaf text of an xml2js field (array-wrapped, string or { _ }). */
function leaf(v) {
  if (Array.isArray(v)) v = v[0];
  if (v == null) return null;
  if (typeof v === "string") return v;
  if (typeof v === "object" && typeof v._ === "string") return v._;
  return null;
}

/**
 * Voucher types from Tally's VoucherType collection (FETCH NAME, PARENT; the
 * NAME / RESERVEDNAME attributes come with every item) → Map of lower-case
 * name → { name, parent, reserved }.
 */
function parseVoucherTypes(items) {
  const types = new Map();
  for (const it of Array.isArray(items) ? items : items ? [items] : []) {
    if (!it || typeof it !== "object") continue;
    const attrs = it.$ || {};
    const name = String(attrs.NAME ?? leaf(it.NAME) ?? "").trim();
    if (!name) continue;
    const parent = String(leaf(it.PARENT) ?? "").trim();
    const reserved = String(attrs.RESERVEDNAME ?? "").trim();
    types.set(name.toLowerCase(), { name, parent, reserved });
  }
  return types;
}

/**
 * The built-in (reserved) type behind voucher type [name], e.g.
 * "Delivery Challan" → "Delivery Note"; null when it cannot be told.
 */
function baseTypeOf(name, types) {
  if (!name || !types || !types.size) return null;
  let cur = types.get(String(name).trim().toLowerCase());
  for (let hops = 0; cur && hops < 20; hops++) {
    if (cur.reserved) return cur.reserved;
    if (!cur.parent || cur.parent.toLowerCase() === cur.name.toLowerCase()) return null;
    cur = types.get(cur.parent.toLowerCase());
  }
  return null;
}

/** Every voucher type → its built-in type (only those that resolve). */
function baseTypeMap(types) {
  const out = new Map();
  for (const t of types.values()) {
    const b = baseTypeOf(t.name, types);
    if (b) out.set(t.name.toLowerCase(), b);
  }
  return out;
}

/** A Yes / No flag on the voucher: true / false, null when not exported. */
function voucherFlag(src, key) {
  const v = src && typeof src === "object" ? leaf(src[key]) : null;
  const s = v == null ? "" : String(v).trim();
  return s === "Yes" ? true : s === "No" ? false : null;
}

/**
 * Sets is_cancelled, is_optional and base_type on the voucher sent to the
 * server (each only when known). [bases] is baseTypeMap(...) or null.
 */
function noteVoucherStatus(vd, src, bases) {
  try {
    const c = voucherFlag(src, "ISCANCELLED");
    if (c !== null) vd.is_cancelled = c;
    const o = voucherFlag(src, "ISOPTIONAL");
    if (o !== null) vd.is_optional = o;
    const type = vd.voucher_type || leaf(src?.VOUCHERTYPENAME) || src?.$?.VCHTYPE;
    const b = bases && type ? bases.get(String(type).trim().toLowerCase()) : null;
    if (b) vd.base_type = b;
  } catch {
    // never affects the voucher itself
  }
  return vd;
}

module.exports = { baseTypeMap, baseTypeOf, noteVoucherStatus, parseVoucherTypes, voucherFlag };
