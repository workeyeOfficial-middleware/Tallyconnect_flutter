// =====================================================================
//  VOUCHER LEDGER LINES → one entry per ledger
//  ---------------------------------------------------------------------
//  A ledger can appear more than once in a voucher (an item invoice lists
//  the sales ledger once per item; a journal can hit a ledger twice).
//  Earlier code kept only the FIRST line and dropped the rest, which
//  under-stated those ledgers and left the voucher unbalanced. Here the
//  lines of one ledger are added up (Dr and Cr netted), so the stored
//  amount is what the voucher really posts to that ledger.
//
//  The stored flag keeps the existing convention exactly:
//    is_debit = (ISDEEMEDPOSITIVE === "No")
//  so a ledger that appears once is stored as before, byte for byte.
// =====================================================================
"use strict";

/**
 * @param {object[]} entryItems  ALLLEDGERENTRIES.LIST items (xml2js objects)
 * @param {(v: any) => any} extractValue
 * @returns {{ledger_name: string, amount: number, is_debit: boolean}[]}
 */
function mergeLedgerLines(entryItems, extractValue) {
  const byName = new Map();
  for (const e of entryItems) {
    const ledgerName = extractValue(e.LEDGERNAME?.[0]);
    const amountRaw = extractValue(e.AMOUNT?.[0]);
    if (!ledgerName || !amountRaw) continue;
    const amount = Math.abs(Number(amountRaw));
    if (!Number.isFinite(amount)) continue;
    const flag = extractValue(e.ISDEEMEDPOSITIVE?.[0]) === "No";
    const signed = flag ? amount : -amount;
    const cur = byName.get(ledgerName);
    if (cur) cur.net += signed;
    else byName.set(ledgerName, { net: signed, firstFlag: flag });
  }
  const out = [];
  for (const [ledger_name, { net, firstFlag }] of byName) {
    const rounded = Math.round(net * 100) / 100;
    out.push({
      ledger_name,
      amount: Math.abs(rounded),
      is_debit: rounded > 0 ? true : rounded < 0 ? false : firstFlag,
    });
  }
  return out;
}

module.exports = { mergeLedgerLines };
