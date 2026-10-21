/* =========================================================
   FINANCIAL REPORTS — figures for any date, from synced data

   Per financial year the Agent uploads ONE anchor (Tally's closing
   balances on the day before the synced vouchers begin, normally the day
   before the year starts, with Stock-in-Hand that day) and the closing
   stock at each month end. Balances on a date are then:
       anchor balance (income / expense ledgers restart at 0 each year)
     + voucher movements after the anchor (voucher_entries, already synced)
   Closing stock: the month-end values, today's from stock_summary.
   Tally is never asked to recalculate a report per date.
========================================================= */
import {
  addDaysIso,
  groupIndex,
  isPrimaryParent,
  ledgerRowsAt,
  nameKey,
  PL_LEDGER_RE,
  plOpeningAt,
  profitLoss,
} from "./financialCore.js";

/** Tally's cash / bank groups (their sub-groups count too). */
const CASH_GROUPS = new Set(["cash-in-hand", "bank accounts", "bank od a/c", "bank occ a/c"]);
const r2 = (n) => Math.round(Number(n || 0) * 100) / 100;
/** SQL: a ledger name as Tally compares it (see nameKey). */
const NAME_KEY = (col) => `lower(btrim(regexp_replace(${col}, '[[:space:]]+', ' ', 'g')))`;

const iso = (d) => (d instanceof Date ? d.toISOString().slice(0, 10) : String(d).slice(0, 10));
const yearAfter = (s) => `${Number(s.slice(0, 4)) + 1}${s.slice(4)}`;
const yearBefore = (s) => `${Number(s.slice(0, 4)) - 1}${s.slice(4)}`;

/** Start of the financial year holding [d] (years start on [fyFrom]'s MM-DD). */
function fyStartOf(d, fyFrom) {
  const same = `${d.slice(0, 4)}-${fyFrom.slice(5)}`;
  return same <= d ? same : yearBefore(same);
}

/** Today as YYYY-MM-DD in India time. */
export function todayIst(now = new Date()) {
  return new Date(now.getTime() + 330 * 60000).toISOString().slice(0, 10);
}

/** Voucher types that never change balances in Tally. */
const NON_ACCOUNTING = "(memorandum|reversing journal|optional)";

/*
 * Signed amount of a voucher line, Cr + / Dr − (the convention of every
 * figure here). The Agent stores is_debit = (ISDEEMEDPOSITIVE = "No"),
 * which in Tally's XML marks a CREDIT line, and writes vouchers back the
 * same way (is_debit → ISDEEMEDPOSITIVE No, positive amount). So a stored
 * is_debit = TRUE is a credit: +amount.
 */
const SIGNED = "CASE WHEN ve.is_debit THEN ve.amount ELSE -ve.amount END";
const COUNTED = `ve.admin_id = $1 AND ve.company_guid = $2
          AND ve.voucher_date > $3::date AND ve.voucher_date <= $4::date
          AND COALESCE(ve.is_active, TRUE) = TRUE
          AND COALESCE(ve.voucher_type, '') !~* '${NON_ACCOUNTING}'`;

export function createFinancialData(db, now = () => new Date()) {
  /**
   * Everything needed for one company: groups, anchors per financial year,
   * stock values, today's stock, ledger masters.
   */
  async function context(s) {
    const [g, a, sv, ss, lm, bk] = await Promise.all([
      db.query(
        `SELECT name, parent, is_revenue, is_deemed_positive, affects_gross_profit
           FROM tally_groups WHERE admin_id = $1 AND company_guid = $2`,
        [s.adminId, s.company]
      ),
      db.query(
        `SELECT as_on, fy_from, batch_id, synced_at FROM fin_snapshots
          WHERE admin_id = $1 AND company_guid = $2 AND kind = 'anchor'
          ORDER BY as_on ASC`,
        [s.adminId, s.company]
      ),
      db.query(
        `SELECT as_on, value FROM fin_stock_values WHERE admin_id = $1 AND company_guid = $2`,
        [s.adminId, s.company]
      ),
      db.query(
        `SELECT COUNT(*)::int AS n, COALESCE(SUM(closing_value), 0) AS value
           FROM stock_summary WHERE admin_id = $1 AND company_guid = $2`,
        [s.adminId, s.company]
      ),
      db.query(
        `SELECT name, ledger_guid AS guid, parent_group AS parent, opening_balance AS opening
           FROM ledgers WHERE admin_id = $1 AND company_guid = $2`,
        [s.adminId, s.company]
      ),
      // Books-beginning date and opening stock (older servers: no table).
      db
        .query(
          `SELECT books_from, vouchers_from, fy_from, opening_stock FROM fin_books
            WHERE admin_id = $1 AND company_guid = $2`,
          [s.adminId, s.company]
        )
        .catch(() => ({ rows: [] })),
    ]);
    const stock = new Map();
    for (const x of sv.rows) stock.set(iso(x.as_on), Math.abs(Number(x.value || 0)));
    // Anchors: the financial year each one serves.
    const anchors = a.rows.map((x) => {
      const asOn = iso(x.as_on);
      const anchorFy = iso(x.fy_from);
      // The day before a year → serves the next year; else its own year.
      const fy = addDaysIso(asOn, 1) === yearAfter(anchorFy) ? yearAfter(anchorFy) : anchorFy;
      return { asOn, anchorFy, fy, batchId: x.batch_id, syncedAt: x.synced_at };
    });
    const today = todayIst(now());
    // The books' own start: ledger OPENING balances (masters) + the items'
    // opening values — no balances from Tally — when the synced vouchers
    // begin with the books. An uploaded anchor for that year wins.
    const b = bk.rows[0];
    const books = b
      ? {
          from: iso(b.books_from),
          vouchersFrom: b.vouchers_from ? iso(b.vouchers_from) : null,
          fy: b.fy_from ? iso(b.fy_from) : iso(b.books_from),
          openingStock: Math.abs(Number(b.opening_stock || 0)),
        }
      : null;
    if (books && (!books.vouchersFrom || books.vouchersFrom <= books.from) && !anchors.some((x) => x.fy === books.fy)) {
      const asOn = addDaysIso(books.from, -1);
      anchors.unshift({ asOn, anchorFy: asOn < books.fy ? yearBefore(books.fy) : books.fy, fy: books.fy, books: true, batchId: `books:${books.from}` });
    }
    // Later years with no anchor of their own: carried forward from the
    // year before (needs the closing stock at that year end).
    if (anchors.length) {
      const fys = anchors.map((x) => x.fy).sort();
      for (let f = fys[0]; f <= fyStartOf(today, fys[0]); f = yearAfter(f)) {
        if (!anchors.some((x) => x.fy === f)) {
          anchors.push({ asOn: addDaysIso(f, -1), anchorFy: yearBefore(f), fy: f, derived: true, batchId: `derived:${f}` });
        }
      }
    }
    return {
      s,
      books,
      groups: g.rows,
      anchors,
      stock,
      todayStock: Number(ss.rows[0]?.n || 0) > 0 ? Math.abs(Number(ss.rows[0].value || 0)) : null,
      masters: lm.rows.map((x) => ({ ...x, opening: Number(x.opening || 0) })),
      today,
      anchorRows: new Map(), // batchId → rows (loaded on demand)
      anchorStock: new Map(),
    };
  }

  async function rowsOf(ctx, anchor) {
    if (!ctx.anchorRows.has(anchor.batchId) && anchor.books) {
      ctx.anchorRows.set(
        anchor.batchId,
        ctx.masters.map((m) => ({ name: m.name, guid: m.guid, parent: m.parent, closing: m.opening }))
      );
      ctx.stock.set(anchor.asOn, ctx.books.openingStock);
      // Books starting inside a year: nothing before them, same stock.
      if (anchor.asOn >= anchor.fy) ctx.stock.set(addDaysIso(anchor.fy, -1), ctx.books.openingStock);
    }
    if (!ctx.anchorRows.has(anchor.batchId) && anchor.derived) {
      // Closing balances at the year end, from the year before.
      const prev = anchorFor(ctx, yearBefore(anchor.fy));
      const prevRows = prev ? await rowsOf(ctx, prev) : [];
      const mv = prev ? await movements(ctx.s, prev.asOn, anchor.asOn) : new Map();
      ctx.anchorRows.set(
        anchor.batchId,
        ledgerRowsAt({ groups: ctx.groups, anchorRows: prevRows, carryRevenue: !!prev && prev.anchorFy === prev.fy, masters: ctx.masters, movements: mv })
      );
    }
    if (!ctx.anchorRows.has(anchor.batchId)) {
      const [l, g] = await Promise.all([
        db.query(
          `SELECT ledger_name AS name, ledger_guid AS guid, parent, closing
             FROM fin_ledger_balances WHERE batch_id = $1`,
          [anchor.batchId]
        ),
        db.query(`SELECT group_name AS name, closing FROM fin_group_balances WHERE batch_id = $1`, [anchor.batchId]),
      ]);
      ctx.anchorRows.set(
        anchor.batchId,
        l.rows.map((x) => ({ ...x, closing: Number(x.closing) }))
      );
      const st = g.rows.find((x) => /^stock[\s-]*in[\s-]*hand$/i.test(String(x.name)));
      ctx.anchorStock.set(anchor.batchId, st ? Math.abs(Number(st.closing)) : 0);
      ctx.stock.set(anchor.asOn, ctx.anchorStock.get(anchor.batchId));
    }
    return ctx.anchorRows.get(anchor.batchId);
  }

  /** The anchor serving the year [fy] (latest upload wins). */
  const anchorFor = (ctx, fy) => [...ctx.anchors].reverse().find((x) => x.fy === fy) || null;

  /** Financial year (start) of a date, among the years with an anchor. */
  function fyOf(ctx, d) {
    const ys = [...new Set(ctx.anchors.map((x) => x.fy))].sort();
    let f = null;
    for (const y of ys) if (y <= d && d < yearAfter(y)) f = y;
    return f;
  }

  /**
   * Closing stock on [d] (null: not known). A value saved for the date wins
   * (the Agent's daily stock value from Tally, or one the admin entered);
   * for today, else the stock items' values (stock_summary).
   */
  function stockAt(ctx, d) {
    if (ctx.stock.has(d)) return ctx.stock.get(d);
    if (d === ctx.today && ctx.todayStock !== null) return ctx.todayStock;
    return null;
  }

  /**
   * Year ends whose closing stock is missing (each year's opening stock):
   * without it that year's P&L / Balance Sheet cannot be shown. Newest
   * first — the admin can enter them (PUT /api/financial/stock-values).
   */
  async function neededStock(ctx) {
    const out = [];
    for (const fy of [...new Set(ctx.anchors.map((x) => x.fy))]) {
      if ((await openingStock(ctx, fy)) === null) out.push(addDaysIso(fy, -1));
    }
    return out.sort((a, b) => (a < b ? 1 : -1));
  }

  /** Opening stock of the year [fy] = closing stock the day before. */
  async function openingStock(ctx, fy) {
    const a = anchorFor(ctx, fy);
    if (a) await rowsOf(ctx, a); // the anchor day's stock joins ctx.stock
    return stockAt(ctx, addDaysIso(fy, -1));
  }

  /** Why no date can be offered (null: there are dates). */
  async function missingReason(ctx) {
    if (!ctx.groups.length) return "not_synced";
    if (!ctx.anchors.length) {
      if (ctx.books && ctx.books.vouchersFrom && ctx.books.vouchersFrom > ctx.books.from) return "vouchers_after_books";
      return "not_synced";
    }
    return (await offeredDates(ctx)).length ? null : "stock_values";
  }

  /** Dates reports can be shown for, newest first: [{as_on, fy_from}]. */
  async function offeredDates(ctx) {
    const out = [];
    for (const fy of [...new Set(ctx.anchors.map((x) => x.fy))]) {
      const a = anchorFor(ctx, fy);
      if ((await openingStock(ctx, fy)) === null) continue;
      const end = yearAfter(fy);
      const add = (d) => {
        if (d < end && d >= fy && d >= a.asOn && !out.some((x) => x.as_on === d)) out.push({ as_on: d, fy_from: fy });
      };
      for (const d of ctx.stock.keys()) if (d > a.asOn && d <= ctx.today) add(d);
      if (ctx.today >= fy && ctx.today < end && ctx.todayStock !== null) add(ctx.today);
      // An anchor inside the year is itself a date with Tally's figures.
      if (a.asOn >= fy) add(a.asOn);
    }
    return out.sort((x, y) => (x.as_on < y.as_on ? 1 : -1));
  }

  /** Net voucher movements per ledger in (after, upto] (Cr +, Dr −). */
  async function movements(s, after, upto) {
    const r = await db.query(
      `SELECT ve.ledger_name AS name,
              SUM(${SIGNED}) AS net
         FROM voucher_entries ve
        WHERE ${COUNTED}
        GROUP BY ve.ledger_name`,
      [s.adminId, s.company, after, upto]
    );
    const m = new Map();
    for (const x of r.rows) m.set(String(x.name), Number(x.net || 0));
    return m;
  }

  /** Month-by-month movements per ledger in (after, upto]. */
  async function monthlyMovements(s, after, upto) {
    const r = await db.query(
      `SELECT ve.ledger_name AS name, TO_CHAR(ve.voucher_date, 'YYYY-MM') AS month,
              SUM(${SIGNED}) AS net
         FROM voucher_entries ve
        WHERE ${COUNTED}
        GROUP BY ve.ledger_name, TO_CHAR(ve.voucher_date, 'YYYY-MM')`,
      [s.adminId, s.company, after, upto]
    );
    return r.rows.map((x) => ({ name: String(x.name), month: String(x.month), net: Number(x.net || 0) }));
  }

  /**
   * Vouchers in (after, upto] whose lines do not add up to zero. Each one
   * makes the Balance Sheet differ by its gap; normally none.
   */
  async function unbalanced(s, after, upto) {
    const r = await db.query(
      `SELECT COUNT(*)::int AS n, COALESCE(SUM(gap), 0) AS gap FROM (
         SELECT ABS(SUM(${SIGNED})) AS gap
           FROM voucher_entries ve
          WHERE ${COUNTED}
          GROUP BY ve.voucher_guid
         HAVING ABS(SUM(${SIGNED})) >= 0.01) x`,
      [s.adminId, s.company, after, upto]
    );
    return { unbalanced_vouchers: Number(r.rows[0]?.n || 0), unbalanced_amount: Math.round(Number(r.rows[0]?.gap || 0) * 100) / 100 };
  }

  /** Data check for figures on [d]: vouchers since the year's anchor. */
  async function dataCheck(s, ctx, d) {
    const fy = fyOf(ctx, d);
    const a = fy && anchorFor(ctx, fy);
    return a ? unbalanced(s, a.asOn, d) : { unbalanced_vouchers: 0, unbalanced_amount: 0 };
  }

  /**
   * The figures on [d] in the shape the report builders take:
   * {as_on, fy_from, ledgers, groups:[Stock-in-Hand closing / opening]}.
   */
  async function snapshotAt(s, ctx, d) {
    const fy = fyOf(ctx, d);
    if (!fy) return null;
    const a = anchorFor(ctx, fy);
    if (!a || d < a.asOn) return null;
    const anchorRows = await rowsOf(ctx, a); // also adds the anchor day's stock
    const close = stockAt(ctx, d);
    const open = await openingStock(ctx, fy);
    if (close === null || open === null) return null;
    const mv = d > a.asOn ? await movements(s, a.asOn, d) : new Map();
    const ledgers = ledgerRowsAt({
      groups: ctx.groups,
      anchorRows,
      carryRevenue: a.anchorFy === fy,
      masters: ctx.masters,
      movements: mv,
    });
    return {
      as_on: d,
      fy_from: fy,
      ledgers,
      groups: [{ name: "Stock-in-Hand", parent: "Current Assets", closing: -close, opening: -open }],
    };
  }

  /** The Profit & Loss A/c brought forward into the year of [snap]. */
  async function plOpening(s, ctx, snap) {
    const a = anchorFor(ctx, snap.fy_from);
    if (a.asOn >= snap.fy_from) {
      // Anchor inside the year: remove this year's profit up to the anchor.
      const anchorSnap = await snapshotAt(s, ctx, a.asOn);
      return plOpeningAt(ctx.groups, anchorSnap, {
        profitToAnchor: profitLoss(ctx.groups, anchorSnap, null).net_profit,
      });
    }
    // Anchor the day before the year: balances then are the openings.
    const rows = await rowsOf(ctx, a);
    const openSnap = {
      ledgers: ledgerRowsAt({ groups: ctx.groups, anchorRows: rows, carryRevenue: false, masters: ctx.masters, movements: new Map() }),
      groups: [{ name: "Stock-in-Hand", closing: -(await openingStock(ctx, snap.fy_from)), opening: 0 }],
    };
    return plOpeningAt(ctx.groups, openSnap);
  }

  /** Snapshots at each month end in (after, to] plus [to], for trends. */
  async function monthSnapshots(s, ctx, to, after) {
    const fy = to.fy_from;
    const a = anchorFor(ctx, fy);
    const rows = await rowsOf(ctx, a);
    const start = after || a.asOn;
    const ms = await monthlyMovements(s, a.asOn, to.as_on);
    const months = [...new Set(ms.map((x) => x.month))].sort();
    const out = [];
    const cum = new Map();
    for (const mo of months) {
      for (const x of ms) if (x.month === mo) cum.set(x.name, (cum.get(x.name) || 0) + x.net);
      const endOfMonth = (() => {
        const [y, m] = mo.split("-").map(Number);
        const d = new Date(Date.UTC(y, m, 0));
        return d.toISOString().slice(0, 10);
      })();
      const asOn = endOfMonth < to.as_on ? endOfMonth : to.as_on;
      if (asOn <= start) continue;
      out.push({
        as_on: asOn,
        fy_from: fy,
        ledgers: ledgerRowsAt({ groups: ctx.groups, anchorRows: rows, carryRevenue: a.anchorFy === fy, masters: ctx.masters, movements: new Map(cum) }),
        groups: [],
      });
    }
    return out;
  }

  /* --------------------------------------------- any period (Tally's F2) */
  /**
   * The synced vouchers begin with the books: figures for ANY period can be
   * worked out from the ledger openings + vouchers (no anchors needed).
   */
  function booksAnchored(ctx) {
    return !!(ctx.books && (!ctx.books.vouchersFrom || ctx.books.vouchersFrom <= ctx.books.from));
  }

  /** Start of the financial year holding [d] (the books' year start). */
  function fyStartFor(ctx, d) {
    return fyStartOf(d, ctx.books ? ctx.books.fy : `${d.slice(0, 4)}-04-01`);
  }

  /**
   * Closing stock on [d], the books' opening stock the day before they
   * begin. A date after today (a period ending in the future): nothing has
   * moved after today, so its closing stock is today's.
   */
  function stockOn(ctx, d) {
    if (ctx.books && d === addDaysIso(ctx.books.from, -1) && !ctx.stock.has(d)) return ctx.books.openingStock;
    if (ctx.today && d > ctx.today && !ctx.stock.has(d)) return stockAt(ctx, ctx.today);
    return stockAt(ctx, d);
  }

  /** Every ledger's balance on [d] since the books began (Tally sign, Cr +). */
  async function rawRows(s, ctx, d) {
    const mv = await movements(s, addDaysIso(ctx.books.from, -1), d);
    return ledgerRowsAt({ groups: ctx.groups, anchorRows: [], carryRevenue: false, masters: ctx.masters, movements: mv });
  }

  /**
   * Figures for the period [from] … [to], the way Tally shows a period
   * (F2): balance-sheet ledgers as on [to]; income / expense ledgers = their
   * movement in the period; the Profit & Loss A/c brings the profit made
   * before [from] (income − expenses + closing stock the day before [from]
   * − the books' opening stock); Stock-in-Hand opening = the day before
   * [from], closing = [to]. → {snap, plOpening, from} for the builders, or
   * {missing: [dates]} when a stock value is not known yet.
   */
  async function periodFigures(s, ctx, from, to, { closingStock = true, stock = true } = {}) {
    const f = from < ctx.books.from ? ctx.books.from : from;
    const prev = addDaysIso(f, -1);
    // stock false (Expenses): stock is not part of the report — unknown = 0.
    const stockPrev = stockOn(ctx, prev) ?? (stock ? null : 0);
    const stockTo = stockOn(ctx, to) ?? (stock ? null : 0);
    const missing = [];
    if (stockPrev === null) missing.push(prev);
    if (closingStock && stockTo === null) missing.push(to);
    if (missing.length) return { missing };
    const [raw, mvRange] = await Promise.all([rawRows(s, ctx, to), movements(s, prev, to)]);
    const idx = groupIndex(ctx.groups);
    const isRev = (parent) => {
      const i = idx.info(parent);
      return !!i && (i.nature === "income" || i.nature === "expense");
    };
    const inRange = new Map();
    for (const [n, v] of mvRange) inRange.set(nameKey(n), (inRange.get(nameKey(n)) || 0) + Number(v || 0));
    let revBefore = 0;
    const ledgers = raw.map((l) => {
      if (!isRev(l.parent)) return l;
      const mv = r2(inRange.get(nameKey(l.name)) || 0);
      revBefore += Number(l.closing) - mv;
      return { ...l, closing: mv };
    });
    const pl = ledgers.find((l) => isPrimaryParent(l.parent) && PL_LEDGER_RE.test(String(l.name)));
    const profitBefore = r2(revBefore + stockPrev - ctx.books.openingStock);
    return {
      from: f,
      plOpening: r2((pl ? Number(pl.closing) : 0) + profitBefore),
      plName: pl ? pl.name : null,
      snap: {
        as_on: to,
        fy_from: f,
        ledgers,
        groups: [{ name: "Stock-in-Hand", parent: "Current Assets", closing: -(stockTo ?? 0), opening: -stockPrev }],
      },
    };
  }

  /** Cash / bank ledgers (name keys): under Cash-in-Hand, Bank Accounts, Bank OD / OCC. */
  function cashKeys(ctx) {
    const up = new Map(ctx.groups.map((g) => [nameKey(g.name), nameKey(g.parent)]));
    const isCash = (parent) => {
      let g = nameKey(parent);
      const seen = new Set();
      while (g && !seen.has(g)) {
        if (CASH_GROUPS.has(g)) return true;
        seen.add(g);
        g = up.get(g) || "";
      }
      return false;
    };
    return new Set(ctx.masters.filter((m) => isCash(m.parent)).map((m) => nameKey(m.name)));
  }

  // The Cash Flow columns the Agent fills (vouchers.has_cash_flow,
  // voucher_entries.gross_dr / gross_cr); looked up again every 10 minutes
  // so the report works before and after they are added.
  let cfCols = null;
  async function cashFlowColumns() {
    if (cfCols && Date.now() - cfCols.at < 10 * 60 * 1000) return cfCols.on;
    const r = await db.query(
      `SELECT table_name, column_name FROM information_schema.columns
        WHERE table_schema = current_schema()
          AND ((table_name = 'vouchers' AND column_name = 'has_cash_flow')
            OR (table_name = 'voucher_entries' AND column_name IN ('gross_dr', 'gross_cr')))`
    );
    cfCols = { at: Date.now(), on: r.rows.length === 3 };
    return cfCols.on;
  }

  /**
   * Cash flow statement for [from] … [to] as TallyPrime's Cash Flow counts
   * it (nothing estimated):
   *   - the vouchers Tally marks as cash flow (its HASCASHFLOW flag, saved
   *     with each voucher; a voucher synced before the flag was: one with a
   *     cash / bank line);
   *   - each voucher by its other side, line by line: a Cr line is money in,
   *     a Dr line money out (the ledger's gross Dr / Cr when synced, else its
   *     net), by that ledger's group; cash / bank lines themselves are not
   *     counted, so a transfer between cash / bank accounts is neither;
   *   - a flagged voucher without a cash / bank line (its ledger moved group
   *     after it was entered): its party ledger is its cash side.
   * Opening and closing are the real cash + bank balances; not_in_flow is
   * their change that Tally's Cash Flow leaves out (vouchers saved without
   * the flag, e.g. before a ledger was moved under Cash-in-Hand).
   */
  async function cashFlow(s, ctx, from, to) {
    const f = from < ctx.books.from ? ctx.books.from : from;
    const prev = addDaysIso(f, -1);
    const cash = cashKeys(ctx);
    const keys = [...cash];
    const masterOf = new Map(ctx.masters.map((m) => [nameKey(m.name), m]));
    // The other side's own group (Sundry Debtors, Office Expenses, …).
    const groupOf = (name) => {
      const m = masterOf.get(nameKey(name));
      return (m && m.parent) || "Other ledgers";
    };
    const flagged = await cashFlowColumns();
    const [before, after, lines] = await Promise.all([
      rawRows(s, ctx, prev),
      rawRows(s, ctx, to),
      keys.length || flagged
        ? db.query(
            `SELECT ve.voucher_guid AS guid, ve.voucher_date::text AS d, ve.ledger_name AS name, ${SIGNED} AS net,
                    ${flagged ? "ve.gross_dr AS gdr, ve.gross_cr AS gcr, v.has_cash_flow AS hcf" : "NULL AS gdr, NULL AS gcr, NULL AS hcf"},
                    v.party_name AS party
               FROM voucher_entries ve
               LEFT JOIN vouchers v
                 ON v.admin_id = ve.admin_id AND v.company_guid = ve.company_guid AND v.voucher_guid = ve.voucher_guid
              WHERE ${COUNTED}
                AND ve.voucher_guid IN (
                  SELECT c.voucher_guid FROM voucher_entries c
                   WHERE c.admin_id = $1 AND c.company_guid = $2
                     AND c.voucher_date > $3::date AND c.voucher_date <= $4::date
                     AND COALESCE(c.is_active, TRUE) = TRUE
                     AND ${NAME_KEY("c.ledger_name")} = ANY($5::text[])${
                       flagged
                         ? `
                  UNION
                  SELECT fv.voucher_guid FROM vouchers fv
                   WHERE fv.admin_id = $1 AND fv.company_guid = $2 AND fv.has_cash_flow = TRUE`
                         : ""
                     })`,
            [s.adminId, s.company, prev, to, keys]
          )
        : { rows: [] },
    ]);
    // Cash held (Dr) is negative in Tally's sign: balance = −closing.
    const accounts = after
      .filter((l) => cash.has(nameKey(l.name)))
      .map((l) => {
        const b = before.find((x) => nameKey(x.name) === nameKey(l.name));
        return { name: l.name, group: l.parent, opening: r2(-(b ? b.closing : 0)), closing: r2(-l.closing) };
      })
      .filter((a) => a.opening !== 0 || a.closing !== 0)
      .sort((a, b) => b.closing - a.closing);
    const num = (v) => (v === null || v === undefined ? null : Number(v));
    const byVoucher = new Map();
    for (const x of lines.rows) {
      if (!byVoucher.has(x.guid)) {
        byVoucher.set(x.guid, { d: String(x.d).slice(0, 10), flag: x.hcf === null || x.hcf === undefined ? null : !!x.hcf, party: x.party, lines: [] });
      }
      byVoucher.get(x.guid).lines.push({ name: x.name, net: Number(x.net || 0), dr: num(x.gdr), cr: num(x.gcr) });
    }
    const months = new Map();
    for (let m = f.slice(0, 7); m <= to.slice(0, 7); ) {
      months.set(m, { inflow: 0, outflow: 0 });
      const [y, mo] = m.split("-").map(Number);
      m = mo === 12 ? `${y + 1}-01` : `${y}-${String(mo + 1).padStart(2, "0")}`;
    }
    const inG = new Map();
    const outG = new Map();
    let inflow = 0;
    let outflow = 0;
    for (const v of byVoucher.values()) {
      const hasCash = v.lines.some((l) => cash.has(nameKey(l.name)));
      // Tally's flag decides; before it was synced, a cash / bank line does.
      if (v.flag === false || (v.flag === null && !hasCash)) continue;
      const party = nameKey(v.party || "");
      const cashSide = hasCash ? (l) => cash.has(nameKey(l.name)) : (l) => !!party && nameKey(l.name) === party;
      const mo = months.get(v.d.slice(0, 7));
      for (const l of v.lines) {
        if (cashSide(l)) continue;
        // Cr + in the stored sign: a Cr line brings money in.
        const cr = l.cr ?? Math.max(l.net, 0);
        const dr = l.dr ?? Math.max(-l.net, 0);
        const g = groupOf(l.name);
        if (cr > 0) {
          inG.set(g, (inG.get(g) || 0) + cr);
          inflow += cr;
          if (mo) mo.inflow += cr;
        }
        if (dr > 0) {
          outG.set(g, (outG.get(g) || 0) + dr);
          outflow += dr;
          if (mo) mo.outflow += dr;
        }
      }
    }
    const cashTotal = (rows) => r2(rows.filter((l) => cash.has(nameKey(l.name))).reduce((a, l) => a - Number(l.closing), 0));
    const opening = cashTotal(before);
    const closing = cashTotal(after);
    const list = (m) =>
      [...m]
        .map(([name, amount]) => ({ name, amount: r2(amount) }))
        .filter((x) => x.amount !== 0)
        .sort((a, b) => b.amount - a.amount);
    return {
      from: f,
      to,
      opening,
      inflow: r2(inflow),
      outflow: r2(outflow),
      net: r2(inflow - outflow),
      closing,
      // Cash / bank moved by vouchers Tally's Cash Flow does not count.
      not_in_flow: r2(closing - opening - (inflow - outflow)),
      months: [...months].map(([month, x]) => ({ month, inflow: r2(x.inflow), outflow: r2(x.outflow), net: r2(x.inflow - x.outflow) })),
      inflow_groups: list(inG),
      outflow_groups: list(outG),
      accounts,
      cash_ledgers: keys.length,
    };
  }

  /**
   * One ledger's vouchers in [from] … [to] (Tally's Ledger Vouchers):
   * opening balance (balance-sheet ledgers since the books began; income /
   * expense ledgers since the start of [from]'s financial year), each voucher
   * with the other side's ledger, debit / credit, running balance, closing.
   * Amounts in Tally's sign (Cr +). At most [limit] vouchers.
   */
  async function ledgerVouchers(s, ctx, { guid, name }, from, to, limit = 2000) {
    const master = (guid && ctx.masters.find((m) => m.guid === guid)) || (name && ctx.masters.find((m) => nameKey(m.name) === nameKey(name))) || null;
    const ledger = master ? master.name : name;
    if (!ledger) return null;
    const key = nameKey(ledger);
    const f = from < ctx.books.from ? ctx.books.from : from;
    const prev = addDaysIso(f, -1);
    const idx = groupIndex(ctx.groups);
    const info = master ? idx.info(master.parent) : null;
    const rev = !!info && (info.nature === "income" || info.nature === "expense");
    const openFrom = rev ? addDaysIso(fyStartFor(ctx, f), -1) : addDaysIso(ctx.books.from, -1);
    const [openMv, rows] = await Promise.all([
      prev > openFrom
        ? db.query(
            `SELECT COALESCE(SUM(${SIGNED}), 0) AS net FROM voucher_entries ve
              WHERE ${COUNTED} AND ${NAME_KEY("ve.ledger_name")} = $5`,
            [s.adminId, s.company, openFrom, prev, key]
          )
        : { rows: [{ net: 0 }] },
      db.query(
        `SELECT ve.voucher_guid AS guid, MIN(ve.voucher_date)::text AS d, MAX(COALESCE(ve.voucher_type, '')) AS type,
                MAX(COALESCE(ve.reference_no, '')) AS ref, SUM(${SIGNED}) AS net
           FROM voucher_entries ve
          WHERE ${COUNTED} AND ${NAME_KEY("ve.ledger_name")} = $5
          GROUP BY ve.voucher_guid
          ORDER BY MIN(ve.voucher_date), ve.voucher_guid
          LIMIT ${Number(limit) + 1}`,
        [s.adminId, s.company, prev, to, key]
      ),
    ]);
    // Unknown name: no master and no voucher line under it.
    if (!master && !rows.rows.length && !Number(openMv.rows[0]?.net || 0)) return null;
    const truncated = rows.rows.length > limit;
    const list = rows.rows.slice(0, limit);
    // The other side of each voucher (Tally's "Particulars").
    const other = new Map();
    if (list.length) {
      const o = await db.query(
        `SELECT ve.voucher_guid AS guid, ve.ledger_name AS name, ${SIGNED} AS net
           FROM voucher_entries ve
          WHERE ve.admin_id = $1 AND ve.company_guid = $2 AND COALESCE(ve.is_active, TRUE) = TRUE
            AND ve.voucher_guid = ANY($3::text[]) AND ${NAME_KEY("ve.ledger_name")} <> $4`,
        [s.adminId, s.company, list.map((x) => x.guid), key]
      );
      for (const x of o.rows) {
        if (!other.has(x.guid)) other.set(x.guid, []);
        other.get(x.guid).push({ name: x.name, net: Number(x.net || 0) });
      }
    }
    const masterOpening = rev || !master ? 0 : Number(master.opening || 0);
    const opening = r2(masterOpening + Number(openMv.rows[0]?.net || 0));
    let bal = opening;
    let dr = 0;
    let cr = 0;
    const out = list.map((x) => {
      const net = r2(Number(x.net || 0));
      bal = r2(bal + net);
      if (net < 0) dr += -net;
      else cr += net;
      const opp = (other.get(x.guid) || []).filter((l) => (net < 0 ? l.net > 0 : l.net < 0)).sort((a, b) => Math.abs(b.net) - Math.abs(a.net));
      const any = opp.length ? opp : (other.get(x.guid) || []);
      return {
        guid: x.guid,
        date: String(x.d).slice(0, 10),
        type: x.type || "",
        ref: x.ref || "",
        particulars: any.length ? any[0].name + (any.length > 1 ? " (and more)" : "") : "",
        debit: net < 0 ? -net : 0,
        credit: net > 0 ? net : 0,
        balance: bal,
      };
    });
    return {
      ledger: { name: ledger, guid: master ? master.guid : null, group: master ? master.parent : null, nature: info ? info.nature : null },
      from: f,
      to,
      opening,
      closing: bal,
      total_debit: r2(dr),
      total_credit: r2(cr),
      rows: out,
      truncated,
    };
  }

  /** Dates with a closing stock value (newest last) — what a period can use. */
  function stockDates(ctx) {
    const out = new Set(ctx.stock.keys());
    if (ctx.books) out.add(addDaysIso(ctx.books.from, -1));
    if (ctx.todayStock !== null) out.add(ctx.today);
    return [...out].sort();
  }

  return {
    context,
    offeredDates,
    missingReason,
    neededStock,
    snapshotAt,
    plOpening,
    monthSnapshots,
    monthlyMovements,
    fyOf,
    dataCheck,
    unbalanced,
    booksAnchored,
    fyStartFor,
    periodFigures,
    cashFlow,
    ledgerVouchers,
    stockDates,
  };
}
