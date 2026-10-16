/* =========================================================
   FINANCIAL REPORTS — pure builders (no database, no network)

   Input = what the Tally Agent uploads, all computed by Tally itself:
     groups:   [{name, parent, is_revenue, is_deemed_positive, affects_gross_profit}]
     snapshot: {as_on, fy_from, ledgers:[{name, guid, parent, closing}],
                groups:[{name, parent, closing, opening}]}
   Closing balances are "as on" a date, from the start of that financial
   year (SVFROMDATE = FY start, SVTODATE = date), exactly as Tally reports
   them: Tally's XML gives DEBIT balances as NEGATIVE numbers, CREDIT as
   positive.

   Nature of a group = flags of its PRIMARY group (Tally's own rule):
     is_revenue & is_deemed_positive    → expense   (Dr)
     is_revenue & !is_deemed_positive   → income    (Cr)
     !is_revenue & is_deemed_positive   → asset     (Dr)
     !is_revenue & !is_deemed_positive  → liability (Cr)
   affects_gross_profit = Trading account (direct) vs P&L (indirect).
========================================================= */

export const STOCK_GROUP_RE = /^stock[\s-]*in[\s-]*hand$/i;
const PL_LEDGER_RE = /^profit\s*(&|and)\s*loss/i;

/** Rupees → paise-exact sum helpers (no float drift in totals). */
const p = (n) => Math.round(Number(n || 0) * 100);
const r = (paise) => Math.round(paise) / 100;

/**
 * A ledger / group name as Tally compares it: capitals ignored, line breaks
 * and repeated spaces counted as one space, ends trimmed. Tally names can
 * carry double spaces or a line break that one sync path keeps and another
 * collapses ("DAIKIN  AIR…" in the masters, "DAIKIN AIR…" on voucher lines).
 */
export const nameKey = (s) =>
  String(s ?? "")
    .replace(/[ \t\r\n\f\v]+/g, " ")
    .trim()
    .toLowerCase();

const isPrimaryParent = (parent) => {
  const s = String(parent ?? "").replace(/[\u0000-\u001f]/g, "").trim().toLowerCase();
  return s === "" || s === "primary";
};

/** Index of the group tree: primary group + nature of every group. */
export function groupIndex(groups) {
  const byName = new Map();
  for (const g of groups || []) {
    if (g && g.name) byName.set(nameKey(g.name), g);
  }
  const primaryCache = new Map();
  function primaryOf(name) {
    const key = nameKey(name);
    if (primaryCache.has(key)) return primaryCache.get(key);
    let g = byName.get(key);
    let guard = 0;
    while (g && !isPrimaryParent(g.parent) && guard++ < 64) {
      const up = byName.get(nameKey(g.parent));
      if (!up) break;
      g = up;
    }
    const res = g || null;
    primaryCache.set(key, res);
    return res;
  }
  function natureOf(primary) {
    if (!primary) return null;
    const rev = !!primary.is_revenue;
    const dp = !!primary.is_deemed_positive;
    if (rev) return dp ? "expense" : "income";
    return dp ? "asset" : "liability";
  }
  function info(groupName) {
    const prim = primaryOf(groupName);
    return prim
      ? {
          primary: prim.name,
          nature: natureOf(prim),
          direct: !!prim.affects_gross_profit,
        }
      : null;
  }
  return { byName, primaryOf, info, size: byName.size };
}

/**
 * A tree of groups → sub-groups → ledgers under [rootNames], amounts as
 * [valueOf] (paise) per ledger. Stock-in-Hand (no ledgers in Tally) takes
 * [stockValue] when given. Zero rows are left out.
 */
function buildTree(idx, ledgers, rootPrimary, valueOf, stockValue) {
  const childGroups = new Map(); // lower(parent) → [group]
  for (const g of idx.byName.values()) {
    const k = nameKey(g.parent);
    if (!childGroups.has(k)) childGroups.set(k, []);
    childGroups.get(k).push(g);
  }
  const ledgersByGroup = new Map();
  for (const l of ledgers) {
    const k = nameKey(l.parent);
    if (!ledgersByGroup.has(k)) ledgersByGroup.set(k, []);
    ledgersByGroup.get(k).push(l);
  }
  function node(g, depth) {
    const key = nameKey(g.name);
    const children = [];
    if (depth < 32) {
      for (const sg of childGroups.get(key) || []) {
        const n = node(sg, depth + 1);
        if (n) children.push(n);
      }
    }
    for (const l of ledgersByGroup.get(key) || []) {
      const v = valueOf(l);
      if (v !== 0) {
        children.push({ type: "ledger", name: l.name, guid: l.guid || null, amount: r(v), _p: v });
      }
    }
    let total = children.reduce((a, c) => a + c._p, 0);
    if (STOCK_GROUP_RE.test(g.name) && stockValue !== undefined && stockValue !== null) {
      total += stockValue;
    }
    if (total === 0 && children.length === 0) return null;
    children.sort((a, b) => Math.abs(b._p) - Math.abs(a._p) || a.name.localeCompare(b.name));
    return { type: "group", name: g.name, amount: r(total), _p: total, children };
  }
  const root = idx.byName.get(nameKey(rootPrimary));
  return root ? node(root, 0) : null;
}

/** Removes the internal paise fields before sending. */
function clean(n) {
  if (!n) return n;
  const { _p, ...rest } = n;
  if (rest.children) rest.children = rest.children.map(clean);
  return rest;
}

function primaries(idx, pred) {
  return [...idx.byName.values()]
    .filter((g) => isPrimaryParent(g.parent))
    .map((g) => ({ g, info: idx.info(g.name) }))
    .filter((x) => x.info && pred(x.info, x.g));
}

/** Stock-in-Hand value (paise, positive) of a snapshot. */
export function stockOf(snapshot, { opening = false } = {}) {
  const g = (snapshot?.groups || []).find((x) => STOCK_GROUP_RE.test(String(x.name)));
  if (!g) return 0;
  return Math.abs(p(opening ? g.opening : g.closing));
}

/** A ledger row's identity across snapshots (GUID, else the name as Tally compares it). */
const ledgerKey = (l) => String(l?.guid || nameKey(l?.name));

function ledgerMap(snapshot) {
  const m = new Map();
  for (const l of snapshot?.ledgers || []) m.set(ledgerKey(l), l);
  return m;
}

/* ------------------------------------------------------- Trial Balance */
/**
 * Every ledger's closing balance as on the snapshot date, Dr / Cr, grouped
 * under its primary group. Stock is not a ledger: as in a classic Trial
 * Balance, Stock-in-Hand shows the OPENING stock of the year (closing stock
 * belongs to the P&L / Balance Sheet), which is what makes Dr = Cr.
 */
export function trialBalance(groups, snapshot) {
  const idx = groupIndex(groups);
  const ledgers = snapshot.ledgers || [];
  const sections = [];
  const openingStock = stockOf(snapshot, { opening: true });
  let dr = openingStock;
  let cr = 0;
  const order = { asset: 0, liability: 1, income: 2, expense: 3 };
  for (const { g, info } of primaries(idx, () => true).sort(
    (a, b) => order[a.info.nature] - order[b.info.nature] || a.g.name.localeCompare(b.g.name)
  )) {
    const tree = buildTree(idx, ledgers, g.name, (l) => -p(l.closing), openingStock || null);
    if (!tree) continue;
    sections.push({ ...clean(tree), nature: info.nature });
  }
  for (const l of ledgers) {
    const v = p(l.closing);
    if (v < 0) dr += -v;
    else cr += v;
  }
  // Ledgers directly under Primary (e.g. Profit & Loss A/c).
  const loose = ledgers.filter((l) => isPrimaryParent(l.parent) && p(l.closing) !== 0);
  if (loose.length) {
    sections.push({
      type: "group",
      name: "Other ledgers",
      nature: "other",
      amount: r(loose.reduce((a, l) => a - p(l.closing), 0)),
      children: loose.map((l) => ({ type: "ledger", name: l.name, guid: l.guid || null, amount: r(-p(l.closing)) })),
    });
  }
  const ungrouped = ledgers.filter(
    (l) => !isPrimaryParent(l.parent) && !idx.byName.has(nameKey(l.parent)) && p(l.closing) !== 0
  );
  return {
    as_on: snapshot.as_on,
    // amount > 0 = Dr, < 0 = Cr (Tally convention flipped for display)
    sections,
    opening_stock: r(openingStock),
    total_debit: r(dr),
    total_credit: r(cr),
    // Tally shows any gap as "Difference in opening balances".
    difference: r(dr - cr),
    ungrouped: ungrouped.map((l) => l.name),
  };
}

/* -------------------------------------------------------- Profit & Loss */
/**
 * P&L for (prev, to]: revenue ledgers' movement = closing(to) − closing(prev)
 * (prev = null when the period starts on the FY start: revenue ledgers start
 * the year at zero). Opening / closing stock from Stock-in-Hand.
 */
export function profitLoss(groups, to, prev = null) {
  const idx = groupIndex(groups);
  const before = ledgerMap(prev);
  const ledgers = to.ledgers || [];
  // Credit-positive movement in the period (income +, expense −).
  const move = (l) => p(l.closing) - (prev ? p(before.get(ledgerKey(l))?.closing) : 0);
  const openingStock = prev ? stockOf(prev) : stockOf(to, { opening: true });
  const closingStock = stockOf(to);
  const sectionFor = (pred, sign) =>
    primaries(idx, pred)
      .map(({ g }) => buildTree(idx, ledgers, g.name, (l) => sign * move(l), null))
      .filter(Boolean)
      .map(clean);
  const tradingIncome = sectionFor((i) => i.nature === "income" && i.direct, 1);
  const tradingExpense = sectionFor((i) => i.nature === "expense" && i.direct, -1);
  const indirectIncome = sectionFor((i) => i.nature === "income" && !i.direct, 1);
  const indirectExpense = sectionFor((i) => i.nature === "expense" && !i.direct, -1);
  const sum = (xs) => xs.reduce((a, x) => a + p(x.amount), 0);
  const gross = sum(tradingIncome) + closingStock - (sum(tradingExpense) + openingStock);
  const net = gross + sum(indirectIncome) - sum(indirectExpense);
  return {
    from: prev ? prev.as_on : to.fy_from,
    after: prev ? prev.as_on : null,
    to: to.as_on,
    trading: {
      income: tradingIncome,
      expense: tradingExpense,
      opening_stock: r(openingStock),
      closing_stock: r(closingStock),
      total_income: r(sum(tradingIncome) + closingStock),
      total_expense: r(sum(tradingExpense) + openingStock),
    },
    gross_profit: r(gross),
    indirect: {
      income: indirectIncome,
      expense: indirectExpense,
      total_income: r(sum(indirectIncome)),
      total_expense: r(sum(indirectExpense)),
    },
    net_profit: r(net),
    total_revenue: r(sum(tradingIncome) + sum(indirectIncome)),
    total_expenses: r(sum(tradingExpense) + sum(indirectExpense)),
  };
}

/* -------------------------------------------------------- Balance Sheet */
/**
 * Balance Sheet as on the snapshot date: liabilities (Cr) and assets (Dr)
 * from Tally's balances, Stock-in-Hand from Tally's stock value, and the
 * Profit & Loss A/c = its own (earlier years') balance + this year's net
 * profit up to the date.
 */
export function balanceSheet(groups, snapshot, { plOpening } = {}) {
  const idx = groupIndex(groups);
  const ledgers = snapshot.ledgers || [];
  const stock = stockOf(snapshot);
  const liabilities = primaries(idx, (i) => i.nature === "liability")
    .map(({ g }) => buildTree(idx, ledgers, g.name, (l) => p(l.closing), null))
    .filter(Boolean)
    .map(clean);
  const assets = primaries(idx, (i) => i.nature === "asset")
    .map(({ g }) => buildTree(idx, ledgers, g.name, (l) => -p(l.closing), stock))
    .filter(Boolean)
    .map(clean);
  const plLedger = ledgers.find((l) => isPrimaryParent(l.parent) && PL_LEDGER_RE.test(String(l.name)));
  // Brought forward: given (worked out from the year's anchor), else the
  // Profit & Loss A/c ledger's own balance.
  const plOpeningP =
    plOpening !== undefined && plOpening !== null ? p(plOpening) : plLedger ? p(plLedger.closing) : 0;
  const pl = profitLoss(groups, snapshot, null);
  const plTotal = plOpeningP + p(pl.net_profit);
  const sum = (xs) => xs.reduce((a, x) => a + p(x.amount), 0);
  const totalLiab = sum(liabilities) + plTotal;
  const totalAssets = sum(assets);
  return {
    as_on: snapshot.as_on,
    liabilities,
    assets,
    profit_loss: {
      opening: r(plOpeningP),
      current_period: pl.net_profit,
      total: r(plTotal),
    },
    total_liabilities: r(totalLiab),
    total_assets: r(totalAssets),
    // Tally shows any gap as "Difference in opening balances".
    difference: r(totalAssets - totalLiab),
  };
}

/* ------------------------------------------------------------- Expenses */
/**
 * Expenses in (prev, to]: every expense group (direct and indirect),
 * purchases only when asked, the largest ledgers, and month-wise totals
 * from the month-end snapshots in between.
 */
export function expenseReport(groups, to, prev = null, { includePurchases = false, months = [] } = {}) {
  const idx = groupIndex(groups);
  const isPurchase = (name) => /^purchase\s*accounts?$/i.test(String(name));
  const before = ledgerMap(prev);
  const move = (l) => -(p(l.closing) - (prev ? p(before.get(ledgerKey(l))?.closing) : 0));
  const sections = primaries(idx, (i, g) => i.nature === "expense" && (includePurchases || !isPurchase(g.name)))
    .map(({ g }) => buildTree(idx, to.ledgers || [], g.name, move, null))
    .filter(Boolean)
    .map(clean);
  const expenseLedger = (l) => {
    const i = idx.info(l.parent);
    if (!i || i.nature !== "expense") return false;
    return includePurchases || !isPurchase(i.primary);
  };
  const top = (to.ledgers || [])
    .filter(expenseLedger)
    .map((l) => ({ name: l.name, guid: l.guid || null, amount: r(move(l)) }))
    .filter((x) => x.amount !== 0)
    .sort((a, b) => b.amount - a.amount)
    .slice(0, 10);
  // Month-wise: consecutive month-end snapshots (prev → m1 → m2 …).
  const trend = [];
  let last = prev;
  for (const m of months) {
    const lm = ledgerMap(last);
    let t = 0;
    for (const l of m.ledgers || []) {
      if (!expenseLedger(l)) continue;
      t += -(p(l.closing) - (last && last.fy_from === m.fy_from ? p(lm.get(ledgerKey(l))?.closing) : 0));
    }
    trend.push({ month: m.as_on.slice(0, 7), as_on: m.as_on, amount: r(t) });
    last = m;
  }
  const total = sections.reduce((a, x) => a + p(x.amount), 0);
  return {
    from: prev ? prev.as_on : to.fy_from,
    after: prev ? prev.as_on : null,
    to: to.as_on,
    include_purchases: includePurchases,
    sections,
    total: r(total),
    top_ledgers: top,
    by_month: trend,
  };
}

/* ------------------------------------------- balances from vouchers */
/**
 * Every ledger's closing balance (Tally sign: Dr −, Cr +) on a date, from
 * the year's anchor (Tally's own closing balances on the anchor day) plus
 * the voucher movements after it.
 *   anchorRows: [{name, guid, parent, closing}]  Tally's figures on the anchor day
 *   carryRevenue: the anchor lies inside this financial year (else income
 *                 and expense ledgers start the year at zero)
 *   masters: [{name, guid, parent, opening}]     ledgers synced (for ones the
 *                 anchor does not have yet: created after it)
 *   movements: Map(ledger name → Cr+ net amount after the anchor)
 */
export function ledgerRowsAt({ groups, anchorRows, carryRevenue, masters, movements }) {
  const idx = groupIndex(groups);
  const isRevenue = (parent) => {
    const i = idx.info(parent);
    return !!i && (i.nature === "income" || i.nature === "expense");
  };
  // Everything keyed by the name as Tally compares it (nameKey): voucher
  // lines, masters and anchor rows can spell the same ledger differently
  // (double spaces, a line break, capitals) and must add up to ONE ledger.
  // The display name is the anchor's, else the master's.
  const byKey = new Map();
  for (const a of anchorRows || []) {
    const k = nameKey(a.name);
    const cur = byKey.get(k);
    if (cur) cur.base = Number(cur.base || 0) + Number(a.closing || 0);
    else byKey.set(k, { ...a, name: String(a.name), base: a.closing, fromAnchor: true });
  }
  for (const m of masters || []) {
    const k = nameKey(m.name);
    const cur = byKey.get(k);
    if (cur) {
      // Current group from the synced master (a ledger may have moved).
      if (m.parent) cur.parent = m.parent;
      if (!cur.guid && m.guid) cur.guid = m.guid;
      if (!cur.fromAnchor && !cur.fromMaster) cur.name = String(m.name);
      cur.fromMaster = true;
    } else {
      byKey.set(k, { name: String(m.name), guid: m.guid || null, parent: m.parent || "Primary", base: Number(m.opening || 0), fromAnchor: false, fromMaster: true });
    }
  }
  // Movements per key (several spellings of one ledger are added up).
  const moved = new Map();
  for (const [name, net] of movements?.entries?.() || []) {
    const k = nameKey(name);
    moved.set(k, (moved.get(k) || 0) + Number(net || 0));
    if (!byKey.has(k)) byKey.set(k, { name: String(name), guid: null, parent: "Primary", base: 0, fromAnchor: false });
  }
  const rows = [];
  for (const [k, x] of byKey) {
    const rev = isRevenue(x.parent);
    // An anchor on the day before the year: revenue ledgers restart at 0.
    // A ledger not in the anchor: its master opening only for balance-sheet
    // ledgers (revenue ledgers have no opening).
    const base = rev && (!carryRevenue || !x.fromAnchor) ? 0 : p(x.base);
    const closing = base + p(moved.get(k) || 0);
    rows.push({ name: x.name, guid: x.guid, parent: x.parent, closing: r(closing), opening: 0 });
  }
  return rows;
}

/**
 * The Profit & Loss A/c brought forward into the year: what makes the
 * balance sheet balance at the start of the year (assets incl. stock −
 * liabilities). For an anchor inside the year, this year's profit up to
 * the anchor is taken out again.
 */
export function plOpeningAt(groups, anchorSnap, { profitToAnchor = 0 } = {}) {
  const idx = groupIndex(groups);
  let sum = 0;
  for (const l of anchorSnap.ledgers || []) {
    if (isPrimaryParent(l.parent)) continue; // P&L A/c itself and other loose ledgers
    const i = idx.info(l.parent);
    if (!i || i.nature === "income" || i.nature === "expense") continue;
    sum += p(l.closing);
  }
  return r(-sum + stockOf(anchorSnap) - p(profitToAnchor));
}

/* --------------------------------------------------------- validation */
export const isIsoDate = (s) => typeof s === "string" && /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(Date.parse(`${s}T00:00:00Z`));

/** An ISO date [n] days later (negative: earlier). */
export function addDaysIso(iso, n) {
  const d = new Date(`${iso}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

/** Day before an ISO date. */
export function dayBefore(iso) {
  const d = new Date(`${iso}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() - 1);
  return d.toISOString().slice(0, 10);
}

/** Cleans one uploaded ledger / group row. */
export function cleanRow(x, kind) {
  if (!x || typeof x !== "object") return null;
  const name = String(x.name ?? "").replace(/[\u0000-\u001f]/g, "").trim().slice(0, 300);
  if (!name) return null;
  const num = (v) => {
    const n = Number(v);
    return Number.isFinite(n) ? Math.round(n * 100) / 100 : 0;
  };
  const parent = x.parent == null ? null : String(x.parent).replace(/[\u0000-\u001f]/g, "").trim().slice(0, 300);
  if (kind === "ledger") {
    return {
      name,
      guid: x.guid ? String(x.guid).slice(0, 120) : null,
      parent,
      closing: num(x.closing),
      opening: num(x.opening),
    };
  }
  if (kind === "group") {
    return { name, parent, closing: num(x.closing), opening: num(x.opening) };
  }
  // group master
  return {
    name,
    parent,
    is_revenue: x.is_revenue === true || x.is_revenue === "Yes",
    is_deemed_positive: x.is_deemed_positive === true || x.is_deemed_positive === "Yes",
    affects_gross_profit: x.affects_gross_profit === true || x.affects_gross_profit === "Yes",
  };
}
