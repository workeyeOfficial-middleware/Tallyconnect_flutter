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
import { addDaysIso, ledgerRowsAt, plOpeningAt, profitLoss } from "./financialCore.js";

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

  /** Closing stock on [d] (null: not known). */
  function stockAt(ctx, d) {
    if (d === ctx.today && ctx.todayStock !== null) return ctx.todayStock;
    return ctx.stock.has(d) ? ctx.stock.get(d) : null;
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

  return { context, offeredDates, missingReason, snapshotAt, plOpening, monthSnapshots, fyOf, dataCheck };
}
