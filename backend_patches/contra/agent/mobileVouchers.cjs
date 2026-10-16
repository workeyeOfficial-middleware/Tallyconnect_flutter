"use strict";
// Mobile entries → Tally: which voucher types carry a party, which take only
// ledgers that already exist in Tally, and the Contra voucher (cash ↔ bank)
// checks and XML. Pure functions (no Tally / backend calls) so they can be
// tested without Tally.

/** Types whose payload names a party (customer / supplier) ledger. */
const PARTY_TYPES = new Set(["Sales", "Purchase", "Receipt", "Payment"]);

/**
 * Types whose ledgers must already exist in Tally: the app only offers
 * synced ledgers, and creating a missing one (e.g. a typo) under some
 * default group would post the entry to the wrong account.
 */
const EXISTING_LEDGER_TYPES = new Set(["Journal", "Contra"]);

/** Tally's predefined groups a Contra may use (and their sub-groups). */
const CASH_BANK_GROUPS = new Set(["cash-in-hand", "bank accounts", "bank od a/c", "bank occ a/c"]);

class MobileVoucherError extends Error {
  constructor(message) {
    super(message);
    this.name = "ValidationError";
    // The Agent's retry loop does not retry these (the entry itself is wrong).
    this.isValidationError = true;
  }
}

const norm = (s) => String(s ?? "").trim().toLowerCase();
const typeOf = (payload) => String(payload?.voucher_type || "").trim();

function needsParty(voucherType) {
  return PARTY_TYPES.has(String(voucherType || "").trim());
}

function needsExistingLedgers(voucherType) {
  return EXISTING_LEDGER_TYPES.has(String(voucherType || "").trim());
}

/**
 * True when [parent] is a cash / bank group, directly or through its parent
 * groups. [groups]: [{name, parent}] from Tally.
 */
function isCashOrBankGroup(parent, groups) {
  const up = new Map((groups || []).map((g) => [norm(g.name), norm(g.parent)]));
  let g = norm(parent);
  const seen = new Set();
  while (g && !seen.has(g)) {
    if (CASH_BANK_GROUPS.has(g)) return true;
    seen.add(g);
    g = up.get(g) || "";
  }
  return false;
}

/**
 * Every ledger of a Journal / Contra must exist in Tally: returns the entries
 * with Tally's exact ledger names, or throws naming the missing ones.
 */
function resolveExistingLedgers(entries, tallyLedgers) {
  const byName = new Map((tallyLedgers || []).map((l) => [norm(l.name), l]));
  const missing = [];
  const out = (entries || []).map((e) => {
    const found = byName.get(norm(e.ledger_name));
    if (!found) missing.push(String(e.ledger_name || "").trim() || "(no name)");
    return found ? { ...e, ledger_name: found.name } : e;
  });
  if (missing.length) {
    throw new MobileVoucherError(
      `Ledger not found in Tally: ${missing.join(", ")}. Pick an existing ledger in the app (or create it in Tally first).`
    );
  }
  return out;
}

/**
 * A Contra moves money between cash and bank accounts only: at least two
 * lines, amounts above zero, debits = credits, no account on both sides,
 * every account under Cash-in-Hand / Bank Accounts / Bank OD (or a sub-group).
 * [tallyLedgers]: [{name, parent}]; [groups]: [{name, parent}].
 */
function checkContra(payload, tallyLedgers, groups) {
  const entries = Array.isArray(payload?.ledger_entries) ? payload.ledger_entries : [];
  if (entries.length < 2) throw new MobileVoucherError("Contra needs a 'from' and a 'to' account");
  let dr = 0;
  let cr = 0;
  for (const e of entries) {
    const a = Number(e.amount);
    if (!Number.isFinite(a) || a <= 0) {
      throw new MobileVoucherError(`Invalid Contra amount for ${e.ledger_name || "an account"}`);
    }
    if (typeof e.is_debit !== "boolean") throw new MobileVoucherError("Contra line without debit / credit side");
    if (e.is_debit) dr += a;
    else cr += a;
  }
  if (Math.abs(dr - cr) > 0.01) {
    throw new MobileVoucherError(`Contra not balanced. Debit: ${dr.toFixed(2)}, Credit: ${cr.toFixed(2)}`);
  }
  const resolved = resolveExistingLedgers(entries, tallyLedgers);
  const drNames = new Set(resolved.filter((e) => e.is_debit).map((e) => norm(e.ledger_name)));
  const both = resolved.find((e) => !e.is_debit && drNames.has(norm(e.ledger_name)));
  if (both) throw new MobileVoucherError(`'From' and 'to' must be different accounts (${both.ledger_name})`);
  const parentOf = new Map((tallyLedgers || []).map((l) => [norm(l.name), l.parent]));
  const notCash = resolved
    .filter((e) => !isCashOrBankGroup(parentOf.get(norm(e.ledger_name)), groups))
    .map((e) => e.ledger_name);
  if (notCash.length) {
    throw new MobileVoucherError(
      `Contra is only for cash and bank accounts: ${notCash.join(", ")} is not under Cash-in-Hand or Bank Accounts`
    );
  }
  return resolved;
}

/** Same escaping as agent.cjs escapeXML. */
function esc(value) {
  if (!value) return "";
  return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

/**
 * Contra voucher import XML. [date]: YYYYMMDD. Debit (money comes in) →
 * ISDEEMEDPOSITIVE Yes and a negative amount; credit → No and positive —
 * the same convention as the Agent's Journal / Receipt vouchers.
 */
function buildContraXml({ action, payload, companyName, date }) {
  if (!date) throw new MobileVoucherError("Voucher date missing");
  const entries = Array.isArray(payload.ledger_entries) ? payload.ledger_entries : [];
  const lines = entries
    .map((e) => {
      const amount = Number(e.amount || 0).toFixed(2);
      return `
        <ALLLEDGERENTRIES.LIST>
          <LEDGERNAME>${esc(String(e.ledger_name).trim())}</LEDGERNAME>
          <ISDEEMEDPOSITIVE>${e.is_debit ? "Yes" : "No"}</ISDEEMEDPOSITIVE>
          <AMOUNT>${e.is_debit ? `-${amount}` : amount}</AMOUNT>
        </ALLLEDGERENTRIES.LIST>`;
    })
    .join("");
  const opt = (tag, v) => (v ? `\n            <${tag}>${esc(v)}</${tag}>` : "");
  return `
<ENVELOPE>
  <HEADER>
    <TALLYREQUEST>Import Data</TALLYREQUEST>
  </HEADER>
  <BODY>
    <IMPORTDATA>
      <REQUESTDESC>
        <REPORTNAME>Vouchers</REPORTNAME>
        <STATICVARIABLES>
          <SVCOMPANY>${esc(companyName)}</SVCOMPANY>
        </STATICVARIABLES>
      </REQUESTDESC>
      <REQUESTDATA>
        <TALLYMESSAGE>
          <VOUCHER ACTION="${action === "ALTER" ? "Alter" : "Create"}" VCHTYPE="Contra">
            <DATE>${date}</DATE>
            <EFFECTIVEDATE>${date}</EFFECTIVEDATE>
            <VOUCHERTYPENAME>Contra</VOUCHERTYPENAME>${opt("VOUCHERNUMBER", payload.voucher_no)}${opt(
    "REFERENCE",
    payload.reference_no
  )}
            <PERSISTEDVIEW>Accounting Voucher View</PERSISTEDVIEW>
            <ISINVOICE>No</ISINVOICE>${opt("GUID", payload.voucher_guid)}${opt("NARRATION", payload.narration)}
${lines}
          </VOUCHER>
        </TALLYMESSAGE>
      </REQUESTDATA>
    </IMPORTDATA>
  </BODY>
</ENVELOPE>
`;
}

module.exports = {
  PARTY_TYPES,
  EXISTING_LEDGER_TYPES,
  MobileVoucherError,
  needsParty,
  needsExistingLedgers,
  isCashOrBankGroup,
  resolveExistingLedgers,
  checkContra,
  buildContraXml,
  typeOf,
};
