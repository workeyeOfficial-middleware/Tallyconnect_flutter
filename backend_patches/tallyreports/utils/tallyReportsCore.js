/* =========================================================
   OFFICIAL TALLY REPORTS — checks and shaping (no database here)

   Each report is stored exactly as the Agent read it from TallyPrime:
     trial_balance  rows [{name, parent, opening, closing}]  (Dr negative)
     profit_loss    rows [{name, tag, amounts: {TAG: number}}] in Tally's order
     balance_sheet  rows [{name, tag, amounts: {...}}]
     cash_flow      rows [{name, tag, amounts: {...}}]
   Nothing is recalculated: the server only checks the figures (sides
   equal) and, for Balance Sheet / P&L, lists each group's ledgers from the
   Trial Balance of the same period (drill-down).
========================================================= */

export const REPORTS = {
  trial_balance: { table: "tally_trial_balance", label: "Trial Balance" },
  profit_loss: { table: "tally_profit_loss", label: "Profit & Loss" },
  balance_sheet: { table: "tally_balance_sheet", label: "Balance Sheet" },
  cash_flow: { table: "tally_cash_flow", label: "Cash Flow" },
};

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const MAX_ROWS = 50000;
const r2 = (n) => Math.round(Number(n) * 100) / 100;
const str = (v, max) => String(v ?? "").trim().slice(0, max);

function validDate(s) {
  if (!DATE_RE.test(s)) return false;
  const [y, m, d] = s.split("-").map(Number);
  const x = new Date(Date.UTC(y, m - 1, d));
  return x.getUTCFullYear() === y && x.getUTCMonth() === m - 1 && x.getUTCDate() === d;
}

/** Checks the Agent's upload. → {error} | {value} */
export function validateUpload(report, body) {
  if (!REPORTS[report]) return { error: "Unknown report" };
  const b = body && typeof body === "object" ? body : {};
  const from = str(b.period_from, 10);
  const to = str(b.period_to, 10);
  if (!validDate(from) || !validDate(to) || from > to) return { error: "period_from / period_to must be dates (from ≤ to)" };
  if (!Array.isArray(b.rows) || !b.rows.length) return { error: "rows are required" };
  if (b.rows.length > MAX_ROWS) return { error: "Too many rows" };
  const rows = [];
  for (const x of b.rows) {
    const name = str(x?.name, 300);
    if (!name) continue;
    if (report === "trial_balance") {
      const opening = r2(x?.opening ?? 0);
      const closing = r2(x?.closing ?? 0);
      if (!Number.isFinite(opening) || !Number.isFinite(closing)) continue;
      rows.push({ name, parent: str(x?.parent, 300) || "Primary", opening, closing });
    } else {
      const amounts = {};
      const src = x?.amounts && typeof x.amounts === "object" ? x.amounts : {};
      for (const [k, v] of Object.entries(src).slice(0, 20)) {
        const n = r2(v);
        if (/^[A-Z][A-Z0-9.]{0,40}$/.test(k) && Number.isFinite(n)) amounts[k] = n;
      }
      rows.push({ name, tag: str(x?.tag, 40), amounts });
    }
  }
  if (!rows.length) return { error: "rows are required" };
  return {
    value: {
      from,
      to,
      rows,
      report_name: str(b.report_name, 100),
      fetch_seconds: Number.isFinite(Number(b.fetch_seconds)) ? r2(b.fetch_seconds) : null,
      content_hash: str(b.content_hash, 64),
    },
  };
}

/** The row's main amount: Tally's main column, else its sub-column. */
export function mainAmount(row) {
  const a = row?.amounts || {};
  const keys = Object.keys(a);
  const main = keys.find((k) => /MAINAMT$/.test(k));
  if (main !== undefined) return a[main];
  const sub = keys.find((k) => /SUBAMT$/.test(k));
  if (sub !== undefined) return a[sub];
  return keys.length ? a[keys[0]] : null;
}

/**
 * Plain checks (nothing is changed):
 *  Trial Balance: Dr total = Cr total;
 *  Balance Sheet / P&L: the two sides cancel (Tally signs Dr −, Cr +).
 */
export function checksFor(report, rows) {
  if (report === "trial_balance") {
    let dr = 0;
    let cr = 0;
    for (const x of rows) {
      if (x.closing < 0) dr += -x.closing;
      else cr += x.closing;
    }
    const difference = r2(Math.abs(dr - cr));
    return { debit: r2(dr), credit: r2(cr), difference, balanced: difference < 1 };
  }
  if (report === "balance_sheet" || report === "profit_loss") {
    let pos = 0;
    let neg = 0;
    for (const x of rows) {
      const v = mainAmount(x);
      if (v === null || v === undefined) continue;
      if (v > 0) pos += v;
      else neg += -v;
    }
    const difference = r2(Math.abs(pos - neg));
    return { credit_side: r2(pos), debit_side: r2(neg), difference, balanced: difference < 1 };
  }
  return {};
}

/* ------------------------------------------------ built from pieces */
/**
 * The Agent's pieces (Tally's own ledger balances, stock values, cash /
 * bank balances) → the four reports. [builders] = {balanceSheet,
 * profitLoss} from financialCore.js (same rules as the app's statements);
 * [groups] = Tally's group tree (tally_groups).
 */
export function validateSnapshot(body) {
  const b = body && typeof body === "object" ? body : {};
  const from = str(b.period_from, 10);
  const to = str(b.period_to, 10);
  if (!validDate(from) || !validDate(to) || from > to) return { error: "period_from / period_to must be dates (from ≤ to)" };
  if (!Array.isArray(b.ledgers) || !b.ledgers.length) return { error: "ledgers are required" };
  if (b.ledgers.length > MAX_ROWS) return { error: "Too many ledgers" };
  const seen = new Set();
  const ledgers = [];
  for (const x of b.ledgers) {
    const name = str(x?.name, 300);
    if (!name || seen.has(name)) continue;
    seen.add(name);
    const opening = r2(x?.opening ?? 0);
    const closing = r2(x?.closing ?? 0);
    if (!Number.isFinite(opening) || !Number.isFinite(closing)) continue;
    ledgers.push({ name, parent: str(x?.parent, 300) || "Primary", opening, closing });
  }
  const s = b.stock && typeof b.stock === "object" ? b.stock : null;
  const stock = s ? { opening: Math.abs(r2(s.opening || 0)) || 0, closing: Math.abs(r2(s.closing || 0)) || 0 } : null;
  const cash = [];
  for (const m of Array.isArray(b.cash_months) ? b.cash_months.slice(0, 24) : []) {
    const f = str(m?.from, 10);
    const t = str(m?.to, 10);
    if (!validDate(f) || !validDate(t)) continue;
    cash.push({ from: f, to: t, opening: r2(m?.opening || 0) || 0, closing: r2(m?.closing || 0) || 0 });
  }
  return {
    value: {
      from,
      to,
      ledgers,
      stock,
      cash,
      pieces: Number.isFinite(Number(b.pieces)) ? Number(b.pieces) : null,
      fetch_seconds: Number.isFinite(Number(b.fetch_seconds)) ? r2(b.fetch_seconds) : null,
    },
  };
}

/** Leaf ledgers of a report tree (amounts converted with [sign]). */
function leaves(node, sign, out = []) {
  for (const c of node?.children || []) {
    if (c.type === "ledger") out.push({ name: c.name, group: node.name, amount: r2(sign * c.amount) });
    else leaves(c, sign, out);
  }
  return out;
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/**
 * → {trial_balance, balance_sheet, profit_loss, cash_flow} rows, in the
 * shapes the read routes serve (Tally sign: Dr −, Cr +).
 */
export function buildFromPieces(v, groups, { balanceSheet, profitLoss }) {
  const openStock = v.stock ? v.stock.opening : 0;
  const closeStock = v.stock ? v.stock.closing : 0;
  // Trial Balance: Tally's ledger balances + the year's opening stock (Dr).
  const tb = [...v.ledgers];
  if (v.stock && openStock) tb.push({ name: "Opening Stock", parent: "Stock-in-Hand", opening: -openStock, closing: -openStock });
  const out = { trial_balance: tb, balance_sheet: null, profit_loss: null, cash_flow: null };

  if (Array.isArray(groups) && groups.length) {
    const snap = {
      as_on: v.to,
      fy_from: v.from,
      ledgers: v.ledgers.map((l) => ({ name: l.name, guid: null, parent: l.parent, closing: l.closing })),
      groups: [{ name: "Stock-in-Hand", parent: "Current Assets", closing: -closeStock, opening: -openStock }],
    };
    const bs = balanceSheet(groups, snap);
    const bsRows = [];
    for (const g of bs.liabilities || []) bsRows.push({ name: g.name, tag: "BS", amounts: { BSMAINAMT: r2(g.amount) }, ledgers: leaves(g, 1) });
    bsRows.push({ name: "Profit & Loss A/c", tag: "BS", amounts: { BSMAINAMT: r2(bs.profit_loss.total) } });
    for (const g of bs.assets || []) bsRows.push({ name: g.name, tag: "BS", amounts: { BSMAINAMT: r2(-g.amount) }, ledgers: leaves(g, -1) });
    out.balance_sheet = bsRows;

    const pl = profitLoss(groups, snap, null);
    const plRows = [];
    const add = (name, amount, extra = {}) => plRows.push({ name, tag: "PL", amounts: { PLMAINAMT: r2(amount) }, ...extra });
    if (pl.trading.opening_stock) add("Opening Stock", -pl.trading.opening_stock);
    for (const g of pl.trading.expense) add(g.name, -g.amount, { ledgers: leaves(g, -1) });
    for (const g of pl.trading.income) add(g.name, g.amount, { ledgers: leaves(g, 1) });
    if (pl.trading.closing_stock) add("Closing Stock", pl.trading.closing_stock);
    for (const g of pl.indirect.expense) add(g.name, -g.amount, { ledgers: leaves(g, -1) });
    for (const g of pl.indirect.income) add(g.name, g.amount, { ledgers: leaves(g, 1) });
    // As in Tally: the profit closes the expense side (a loss the income side).
    add(pl.net_profit >= 0 ? "Net Profit" : "Net Loss", -pl.net_profit);
    out.profit_loss = plRows;
  }

  if (v.cash.length) {
    // Cash / bank: Dr (money held) is negative in Tally → shown as positive.
    out.cash_flow = v.cash.map((m) => {
      const [y, mo] = m.from.split("-").map(Number);
      const opening = r2(-m.opening);
      const closing = r2(-m.closing);
      return {
        name: `${MONTHS[mo - 1]} ${y}`,
        tag: "CF",
        amounts: { CFOPENING: opening, CFNET: r2(closing - opening), CFCLOSING: closing },
      };
    });
  }
  return out;
}

const norm = (s) =>
  String(s ?? "")
    .replace(/[\u0000-\u001f]/g, "")
    .trim()
    .toLowerCase();

/** The primary (top-level) group of [parent] in Tally's group tree. */
export function primaryGroup(parent, groups) {
  const up = new Map((groups || []).map((g) => [norm(g.name), g]));
  let name = norm(parent);
  const seen = new Set();
  let top = name;
  while (name && !seen.has(name)) {
    seen.add(name);
    top = name;
    const g = up.get(name);
    const p = norm(g?.parent);
    if (!g || !p || p === "primary") break;
    name = p;
  }
  return top;
}

/**
 * Balance Sheet / P&L rows with their ledgers (from the Trial Balance of the
 * same period): a ledger belongs to the row named like its primary group,
 * or like its own group. Amounts as in Tally (Dr −, Cr +).
 */
export function withLedgers(rows, tbRows, groups) {
  if (!Array.isArray(tbRows) || !tbRows.length) return rows;
  const byTop = new Map();
  const byParent = new Map();
  for (const l of tbRows) {
    if (!l.closing) continue;
    const item = { name: l.name, group: l.parent, amount: l.closing };
    const top = primaryGroup(l.parent, groups);
    if (!byTop.has(top)) byTop.set(top, []);
    byTop.get(top).push(item);
    const p = norm(l.parent);
    if (!byParent.has(p)) byParent.set(p, []);
    byParent.get(p).push(item);
  }
  const sorted = (xs) => [...xs].sort((a, b) => Math.abs(b.amount) - Math.abs(a.amount));
  return rows.map((row) => {
    const k = norm(row.name);
    const ledgers = byTop.get(k) || byParent.get(k);
    return ledgers ? { ...row, ledgers: sorted(ledgers).slice(0, 500) } : row;
  });
}
