/* =========================================================
   SALES ANALYTICS — one dashboard per period (factory; deps passed in)

   GET /api/analytics/sales?from=YYYY-MM-DD&to=YYYY-MM-DD
     → headline numbers (vs the previous period of the same length),
       trend (by day up to 62 days, else by month), top customers, top
       items (by amount and by quantity), item groups, new vs repeat
       customers, sales returns.

   Figures come from the synced vouchers (amount incl. GST, as on the
   invoice) and their item lines (taxable value, excl. GST). Sales =
   voucher types named like "Sales" (custom types such as "Sales GST"
   too), never orders, quotations or notes; returns = Credit Note /
   Sales Return. Deleted vouchers (is_active false) are left out, and —
   once known (voucherStatus.js) — cancelled and optional ones.

   Scoped to the login's account and ACTIVE company. Team users (USER)
   see only the vouchers they may see (voucher_selection_permissions),
   the same rule as the app's own lists. Read-only.
========================================================= */
import express from "express";
import { hasVoucherStatusColumns, IN_BOOKS } from "./voucherStatus.js";

export const SALES_TYPE = "v.voucher_type ~* 'sale' AND v.voucher_type !~* '(order|quotation|note|return|memo|rejection|reversing)'";
export const RETURN_TYPE = "v.voucher_type ~* '(credit note|sales return)'";
const ACTIVE = "COALESCE(v.is_active, TRUE) = TRUE";
/** A party as Tally compares names: capitals ignored, line breaks / repeated spaces = one space. */
const PARTY_KEY = "lower(btrim(regexp_replace(COALESCE(v.party_name, ''), '[[:space:]]+', ' ', 'g')))";
const MAX_DAYS = 5 * 366;

const num = (v) => Math.round(Number(v || 0) * 100) / 100;
export const isIsoDate = (s) => typeof s === "string" && /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(Date.parse(`${s}T00:00:00Z`));

export function addDays(iso, n) {
  const d = new Date(`${iso}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

export const daysBetween = (a, b) => Math.round((Date.parse(`${b}T00:00:00Z`) - Date.parse(`${a}T00:00:00Z`)) / 86400000);

/** The period of the same length just before [from, to]. */
export function previousPeriod(from, to) {
  const len = daysBetween(from, to);
  const pTo = addDays(from, -1);
  return { from: addDays(pTo, -len), to: pTo };
}

/** Growth in % (one decimal), or null when there is nothing to compare. */
export function growth(cur, prev) {
  if (!prev) return null;
  return Math.round(((cur - prev) / prev) * 1000) / 10;
}

/** Every day / month key of [from, to], so the chart has no holes. */
export function trendKeys(from, to, unit) {
  const out = [];
  if (unit === "day") {
    for (let d = from; d <= to; d = addDays(d, 1)) out.push(d);
    return out;
  }
  let y = Number(from.slice(0, 4));
  let m = Number(from.slice(5, 7));
  const end = to.slice(0, 7);
  for (;;) {
    const k = `${y}-${String(m).padStart(2, "0")}`;
    if (k > end) break;
    out.push(k);
    m++;
    if (m > 12) {
      m = 1;
      y++;
    }
  }
  return out;
}

class HttpError extends Error {
  constructor(status, message, code) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

/**
 * @param {object} deps
 * @param {{query: Function}} deps.db
 * @param {Function} deps.auth
 * @param {object} [deps.log]
 */
export function createSalesAnalyticsRouter({ db, auth, log = console }) {
  const router = express.Router();

  async function scope(req) {
    const u = req.user || {};
    if (!u.id) throw new HttpError(401, "Unauthorized");
    const adminId = u.adminId ?? (u.role === "ADMIN" ? u.id : null);
    if (!adminId) throw new HttpError(403, "Access denied", "forbidden");
    const r = await db.query(
      `SELECT ac.company_guid, c.name AS company_name
         FROM active_company ac
         LEFT JOIN companies c ON c.company_guid = ac.company_guid AND c.admin_id = ac.admin_id
        WHERE ac.admin_id = $1 LIMIT 1`,
      [adminId]
    );
    const company = r.rows[0]?.company_guid || null;
    if (!company) throw new HttpError(409, "No company is selected for this account.", "no_company");
    // Cancelled / optional vouchers are left out once the columns exist.
    const status = await hasVoucherStatusColumns(db);
    return { adminId, company, companyName: r.rows[0]?.company_name || "", isAdmin: u.role === "ADMIN", userId: u.id, status };
  }

  /** The WHERE part for vouchers of [s] in [from, to] (+ team-user rule). */
  function where(s, from, to, type) {
    const params = [s.adminId, s.company, from, to];
    let sql = `v.admin_id = $1 AND v.company_guid = $2 AND v.voucher_date >= $3::date AND v.voucher_date <= $4::date AND ${ACTIVE} AND ${type}`;
    if (s.status) sql += ` AND ${IN_BOOKS("v")}`;
    if (!s.isAdmin) {
      params.push(s.userId);
      sql +=
        ` AND v.voucher_guid IN (SELECT jsonb_array_elements_text(u.voucher_selection_permissions->'allowed_vouchers')` +
        ` FROM users u WHERE u.id = $${params.length})`;
    }
    return { sql, params };
  }

  async function totals(s, from, to) {
    const w = where(s, from, to, SALES_TYPE);
    const r = await db.query(
      `SELECT COUNT(*)::int AS n, COALESCE(SUM(ABS(COALESCE(v.net_amount, 0))), 0) AS total,
              COUNT(DISTINCT v.party_name)::int AS customers
         FROM vouchers v WHERE ${w.sql}`,
      w.params
    );
    const x = r.rows[0] || {};
    return { invoices: Number(x.n || 0), sales: num(x.total), customers: Number(x.customers || 0) };
  }

  async function returnsTotal(s, from, to) {
    const w = where(s, from, to, RETURN_TYPE);
    const r = await db.query(
      `SELECT COUNT(*)::int AS n, COALESCE(SUM(ABS(COALESCE(v.net_amount, 0))), 0) AS total FROM vouchers v WHERE ${w.sql}`,
      w.params
    );
    return { count: Number(r.rows[0]?.n || 0), amount: num(r.rows[0]?.total) };
  }

  async function trend(s, from, to, unit) {
    const w = where(s, from, to, SALES_TYPE);
    const key = unit === "day" ? "TO_CHAR(v.voucher_date, 'YYYY-MM-DD')" : "TO_CHAR(v.voucher_date, 'YYYY-MM')";
    const r = await db.query(
      `SELECT ${key} AS k, COALESCE(SUM(ABS(COALESCE(v.net_amount, 0))), 0) AS total, COUNT(*)::int AS n
         FROM vouchers v WHERE ${w.sql} GROUP BY 1`,
      w.params
    );
    const by = new Map(r.rows.map((x) => [String(x.k), x]));
    return trendKeys(from, to, unit).map((k) => ({ key: k, sales: num(by.get(k)?.total), invoices: Number(by.get(k)?.n || 0) }));
  }

  async function topCustomers(s, from, to, total) {
    const w = where(s, from, to, SALES_TYPE);
    const r = await db.query(
      // One customer however its name is spelt on the vouchers (capitals,
      // line breaks, repeated spaces — as Tally compares names).
      `SELECT COALESCE(NULLIF(MIN(TRIM(v.party_name)), ''), '—') AS party, COUNT(*)::int AS n,
              COALESCE(SUM(ABS(COALESCE(v.net_amount, 0))), 0) AS total
         FROM vouchers v WHERE ${w.sql}
        GROUP BY ${PARTY_KEY} ORDER BY total DESC, party ASC LIMIT 10`,
      w.params
    );
    return r.rows.map((x) => ({
      party: x.party,
      sales: num(x.total),
      invoices: Number(x.n),
      share: total ? Math.round((Number(x.total) / total) * 1000) / 10 : 0,
    }));
  }

  /** Item lines of the period's sales: totals per item (excl. GST). */
  async function items(s, from, to) {
    const w = where(s, from, to, SALES_TYPE);
    const r = await db.query(
      `SELECT li.item_name AS item, COALESCE(SUM(ABS(COALESCE(li.amount, 0))), 0) AS amount,
              COALESCE(SUM(ABS(COALESCE(li.quantity, 0))), 0) AS qty, COUNT(DISTINCT li.voucher_guid)::int AS n
         FROM ledger_items li
         JOIN vouchers v ON v.admin_id = li.admin_id AND v.company_guid = li.company_guid AND v.voucher_guid = li.voucher_guid
        WHERE ${w.sql} AND li.item_name IS NOT NULL
        GROUP BY li.item_name
        ORDER BY amount DESC LIMIT 1000`,
      w.params
    );
    const list = r.rows.map((x) => ({ item: String(x.item), amount: num(x.amount), qty: num(x.qty), invoices: Number(x.n) }));
    let groups = [];
    if (list.length) {
      const g = await db.query(
        `SELECT name, parent_group FROM stock_items WHERE admin_id = $1 AND company_guid = $2 AND name = ANY($3::text[])`,
        [s.adminId, s.company, list.map((x) => x.item)]
      );
      const of = new Map(g.rows.map((x) => [String(x.name), x.parent_group ? String(x.parent_group) : null]));
      const by = new Map();
      for (const x of list) {
        const k = of.get(x.item) || "Other items";
        by.set(k, num((by.get(k) || 0) + x.amount));
      }
      groups = [...by].map(([group, amount]) => ({ group, amount })).sort((a, b) => b.amount - a.amount).slice(0, 8);
    }
    return {
      byAmount: list.slice(0, 10),
      byQty: [...list].sort((a, b) => b.qty - a.qty || b.amount - a.amount).slice(0, 10),
      groups,
      total: num(list.reduce((a, x) => a + x.amount, 0)),
    };
  }

  /** Customers of the period: first sale in it (new) or before it (repeat). */
  async function customerMix(s, from, to) {
    const w = where(s, "1900-01-01", to, SALES_TYPE);
    w.params.push(from);
    const f = `$${w.params.length}::date`;
    const r = await db.query(
      `SELECT COUNT(*) FILTER (WHERE first_sale >= ${f})::int AS new_customers,
              COUNT(*) FILTER (WHERE first_sale < ${f})::int AS repeat_customers
         FROM (SELECT ${PARTY_KEY} AS party, MIN(v.voucher_date) AS first_sale, MAX(v.voucher_date) AS last_sale
                 FROM vouchers v WHERE ${w.sql} AND v.party_name IS NOT NULL
                GROUP BY 1) x
        WHERE last_sale >= ${f}`,
      w.params
    );
    return { new: Number(r.rows[0]?.new_customers || 0), repeat: Number(r.rows[0]?.repeat_customers || 0) };
  }

  router.get("/api/analytics/sales", auth, async (req, res) => {
    try {
      const from = String(req.query.from || "");
      const to = String(req.query.to || "");
      if (!isIsoDate(from) || !isIsoDate(to) || from > to) throw new HttpError(400, "from and to must be YYYY-MM-DD dates (from ≤ to)");
      if (daysBetween(from, to) > MAX_DAYS) throw new HttpError(400, "Choose a period of at most 5 years");
      const s = await scope(req);
      const unit = daysBetween(from, to) <= 62 ? "day" : "month";
      const prev = previousPeriod(from, to);
      const [cur, before, ret, tr, mix, it] = await Promise.all([
        totals(s, from, to),
        totals(s, prev.from, prev.to),
        returnsTotal(s, from, to),
        trend(s, from, to, unit),
        customerMix(s, from, to),
        items(s, from, to),
      ]);
      const top = await topCustomers(s, from, to, cur.sales);
      res.json({
        success: true,
        data: {
          company: s.companyName,
          from,
          to,
          previous: prev,
          kpis: {
            sales: cur.sales,
            invoices: cur.invoices,
            avg_invoice: cur.invoices ? num(cur.sales / cur.invoices) : 0,
            customers: cur.customers,
            returns: ret.amount,
            returns_count: ret.count,
            net_sales: num(cur.sales - ret.amount),
            prev_sales: before.sales,
            prev_invoices: before.invoices,
            prev_customers: before.customers,
            growth_pct: growth(cur.sales, before.sales),
          },
          trend: { unit, points: tr },
          top_customers: top,
          top_items: it.byAmount,
          top_items_qty: it.byQty,
          item_groups: it.groups,
          items_total: it.total,
          customers: mix,
        },
      });
    } catch (err) {
      if (err instanceof HttpError) {
        return res.status(err.status).json({ success: false, message: err.message, ...(err.code ? { code: err.code } : {}) });
      }
      log.error("analytics error:", err?.message || err);
      res.status(500).json({ success: false, message: "Server error" });
    }
  });

  return router;
}
