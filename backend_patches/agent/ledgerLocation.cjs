// A ledger's location as saved in Tally: state (LEDSTATENAME, or the
// mailing details' state), PIN code, country and the address lines (joined
// with ", "). Tally has no separate city field: the city is part of the
// address. Sent with each ledger so the app can filter ledgers by location
// (state, city / area, PIN) and share them. Never throws; a field Tally
// does not have is left out (null).
"use strict";

/** The text of an xml2js value (string, { _ }, or an array of them). */
function txt(v) {
  if (Array.isArray(v)) return v.map(txt).filter(Boolean).join(", ");
  if (v == null) return null;
  if (typeof v === "string") return v.trim() || null;
  if (typeof v === "object" && typeof v._ === "string") return v._.trim() || null;
  return null;
}

function addressOf(list) {
  const arr = Array.isArray(list) ? list : list ? [list] : [];
  const lines = [];
  for (const a of arr) {
    const t = txt(a?.ADDRESS ?? a);
    if (t) lines.push(t);
  }
  const s = lines.join(", ").replace(/\s{2,}/g, " ").trim();
  return s ? s.slice(0, 500) : null;
}

function ledgerLocation(l) {
  try {
    if (!l || typeof l !== "object") return { state: null, pincode: null, country: null, address: null };
    const mailing = (() => {
      const m = l["MAILINGDETAILS.LIST"];
      const arr = Array.isArray(m) ? m : m ? [m] : [];
      return arr.find((x) => x && typeof x === "object") || null;
    })();
    const state = txt(l.LEDSTATENAME) || txt(mailing?.STATE) || null;
    const pincode = (txt(l.PINCODE) || txt(mailing?.PINCODE) || "").replace(/\s+/g, "") || null;
    const country = txt(l.COUNTRYNAME) || txt(mailing?.COUNTRY) || null;
    const address = addressOf(l["ADDRESS.LIST"]) || addressOf(mailing?.["ADDRESS.LIST"]) || txt(l.ADDRESS) || null;
    return {
      state: state ? state.slice(0, 80) : null,
      pincode: pincode ? pincode.slice(0, 12) : null,
      country: country ? country.slice(0, 60) : null,
      address,
    };
  } catch {
    return { state: null, pincode: null, country: null, address: null };
  }
}

module.exports = { ledgerLocation };
