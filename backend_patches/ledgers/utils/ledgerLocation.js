/* =========================================================
   LEDGER LOCATION — state, PIN code, country and address of a ledger, as
   saved in Tally (LEDSTATENAME, PINCODE, COUNTRYNAME, ADDRESS.LIST). Used
   by the app to filter ledgers by location (e.g. Mumbai) and share them.
   Columns added by sql/2026-10-23_ledger_location.sql; before that the
   ledger sync and list work exactly as before. Looked up every 10 minutes.
========================================================= */
let cached = null;

export async function hasLocationColumns(db) {
  if (cached && Date.now() - cached.at < 10 * 60 * 1000) return cached.on;
  try {
    const r = await db.query(
      `SELECT column_name FROM information_schema.columns
        WHERE table_schema = current_schema() AND table_name = 'ledgers'
          AND column_name IN ('state', 'pincode', 'country', 'address')`
    );
    cached = { at: Date.now(), on: (r?.rows || []).length === 4 };
  } catch {
    cached = { at: Date.now(), on: false };
  }
  return cached.on;
}

/** Tests: forget the cached lookup. */
export function resetLocationCache() {
  cached = null;
}

/** One line of text, at most [max] characters; null when empty / absent. */
function text(v, max) {
  if (v === undefined || v === null) return null;
  const s = String(v)
    // eslint-disable-next-line no-control-regex
    .replace(/[\u0000-\u001F\u007F]+/g, " ")
    .replace(/\s{2,}/g, " ")
    .trim();
  return s ? s.slice(0, max) : null;
}

/** The location fields the Agent sent → what is stored (null = not sent). */
export function locationOf(body = {}) {
  return {
    state: text(body.state, 80),
    pincode: text(body.pincode, 12),
    country: text(body.country, 60),
    address: text(body.address, 500),
  };
}
