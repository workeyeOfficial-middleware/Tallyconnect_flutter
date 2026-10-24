/* =========================================================
   AI FINANCIAL ASSISTANT — read-only data tools

   Every query is limited to the login's account (admin_id) and its ACTIVE
   company (active_company, read on the server). USER logins see only the
   ledgers in user_ledger_permissions and the vouchers in their
   voucher_selection_permissions — the same rules as the app's own lists.
   Nothing here writes anything.
========================================================= */
import { capJson, isoOrNull, textArg, todayIso } from "./assistantCore.js";
import { hasVoucherStatusColumns, IN_BOOKS } from "./voucherStatus.js";

const num = (v) => Math.round(Number(v || 0) * 100) / 100;
const iso = (d) => {
  if (!d) return null;
  if (d instanceof Date) {
    const p = (x) => String(x).padStart(2, "0");
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
  }
  return String(d).slice(0, 10);
};

/**
 * @param {{query: Function}} db
 * @param {{adminId: number, company: string, isAdmin: boolean, userId: number}} s
 * @param {() => Date} now
 */
export function createTools(db, s, now = () => new Date()) {
  const today = todayIso(now());

  // Permission filters (USER logins), appended with the next $ index.
  const ledgerPerm = (col, params) => {
    if (s.isAdmin) return "";
    params.push(s.userId);
    return ` AND ${col} IN (SELECT ledger_guid FROM user_ledger_permissions WHERE user_id = $${params.length})`;
  };
  const voucherPerm = (col, params) => {
    if (s.isAdmin) return "";
    params.push(s.userId);
    return (
      ` AND ${col} IN (SELECT jsonb_array_elements_text(u.voucher_selection_permissions->'allowed_vouchers')` +
      ` FROM users u WHERE u.id = $${params.length})`
    );
  };
  const range = (args, days = 30) => {
    let to = isoOrNull(args?.to) || today;
    let from = isoOrNull(args?.from);
    if (!from) {
      const d = new Date(`${to}T00:00:00Z`);
      d.setUTCDate(d.getUTCDate() - days);
      from = d.toISOString().slice(0, 10);
    }
    if (from > to) [from, to] = [to, from];
    return { from, to };
  };

  const tools = {
    async outstanding_summary(args) {
      const kind = args?.kind === "payable" ? "payable" : "receivable";
      const params = [s.adminId, s.company, kind];
      const perm = ledgerPerm("b.ledger_guid", params);
      const r = await db.query(
        `SELECT b.ledger_name, COUNT(*)::int AS bills,
                SUM(b.pending_amount) AS pending,
                SUM(CASE WHEN b.due_date < CURRENT_DATE THEN b.pending_amount ELSE 0 END) AS overdue
           FROM bills b
          WHERE b.admin_id = $1 AND b.company_guid = $2 AND b.pending_amount > 0
            AND (CASE WHEN UPPER(COALESCE(b.bill_type, 'RECEIVABLE')) = 'PAYABLE'
                      THEN 'payable' ELSE 'receivable' END) = $3${perm}
          GROUP BY b.ledger_name
          ORDER BY pending DESC`,
        params
      );
      const rows = r.rows.map((x) => ({
        party: x.ledger_name,
        bills: Number(x.bills),
        pending: num(x.pending),
        overdue: num(x.overdue),
      }));
      return {
        kind,
        as_on: today,
        total_pending: num(rows.reduce((a, x) => a + x.pending, 0)),
        total_overdue: num(rows.reduce((a, x) => a + x.overdue, 0)),
        bills: rows.reduce((a, x) => a + x.bills, 0),
        parties: rows.length,
        top_parties: rows.slice(0, 15),
      };
    },

    async party_bills(args) {
      const party = textArg(args?.party);
      if (!party) return { error: "party name is required" };
      const lp = [s.adminId, s.company, party];
      const lperm = ledgerPerm("ledger_guid", lp);
      const l = await db.query(
        `SELECT ledger_guid, name FROM ledgers
          WHERE admin_id = $1 AND company_guid = $2 AND name ILIKE '%' || $3 || '%'${lperm}
          ORDER BY (LOWER(name) = LOWER($3)) DESC, name ASC
          LIMIT 6`,
        lp
      );
      if (!l.rows.length) return { party, found: false, note: "No party with this name is available to this user." };
      const exact = l.rows.find((x) => x.name.toLowerCase() === party.toLowerCase());
      if (!exact && l.rows.length > 1) {
        return { party, found: false, did_you_mean: l.rows.map((x) => x.name) };
      }
      const led = exact || l.rows[0];
      const r = await db.query(
        `SELECT bill_name, bill_date, due_date, pending_amount, bill_type
           FROM bills
          WHERE admin_id = $1 AND company_guid = $2
            AND (ledger_guid = $3 OR (ledger_guid IS NULL AND ledger_name = $4))
            AND pending_amount > 0
          ORDER BY due_date ASC NULLS LAST
          LIMIT 50`,
        [s.adminId, s.company, led.ledger_guid, led.name]
      );
      const bills = r.rows.map((b) => {
        const due = iso(b.due_date);
        return {
          bill: b.bill_name,
          kind: String(b.bill_type || "").toUpperCase() === "PAYABLE" ? "payable" : "receivable",
          bill_date: iso(b.bill_date),
          due_date: due,
          pending: num(b.pending_amount),
          overdue_days: due && due < today ? Math.round((Date.parse(today) - Date.parse(due)) / 86400000) : 0,
        };
      });
      return {
        party: led.name,
        found: true,
        pending_total: num(bills.reduce((a, b) => a + b.pending, 0)),
        bills,
      };
    },

    async search_ledgers(args) {
      const q = textArg(args?.query);
      const params = [s.adminId, s.company, q];
      const perm = ledgerPerm("ledger_guid", params);
      const r = await db.query(
        `SELECT name, parent_group, opening_balance, closing_balance
           FROM ledgers
          WHERE admin_id = $1 AND company_guid = $2
            AND ($3 = '' OR name ILIKE '%' || $3 || '%' OR parent_group ILIKE '%' || $3 || '%')${perm}
          ORDER BY ABS(COALESCE(closing_balance, 0)) DESC, name ASC
          LIMIT 20`,
        params
      );
      return {
        query: q,
        note: "Balances are as synced from Tally, without Dr/Cr.",
        ledgers: r.rows.map((x) => ({
          name: x.name,
          group: x.parent_group,
          opening_balance: num(x.opening_balance),
          closing_balance: num(x.closing_balance),
        })),
      };
    },

    async voucher_summary(args) {
      const type = textArg(args?.voucher_type, 60) || "Sales";
      const { from, to } = range(args, 365);
      const params = [s.adminId, s.company, type, from, to];
      const perm = voucherPerm("v.voucher_guid", params);
      // Cancelled / optional vouchers left out once known (voucherStatus.js).
      const books = (await hasVoucherStatusColumns(db)) ? ` AND ${IN_BOOKS("v")}` : "";
      const where = `v.admin_id = $1 AND v.company_guid = $2 AND LOWER(v.voucher_type) = LOWER($3)
            AND v.voucher_date >= $4::date AND v.voucher_date <= $5::date${perm}${books}`;
      const tot = await db.query(
        `SELECT COUNT(*)::int AS n, COALESCE(SUM(ABS(COALESCE(v.net_amount, 0))), 0) AS total
           FROM vouchers v WHERE ${where}`,
        params
      );
      const top = await db.query(
        `SELECT COALESCE(v.party_name, '—') AS party, COUNT(*)::int AS n,
                SUM(ABS(COALESCE(v.net_amount, 0))) AS total
           FROM vouchers v WHERE ${where}
          GROUP BY COALESCE(v.party_name, '—') ORDER BY total DESC LIMIT 10`,
        params
      );
      const months = await db.query(
        `SELECT TO_CHAR(DATE_TRUNC('month', v.voucher_date), 'YYYY-MM') AS month,
                COUNT(*)::int AS n, SUM(ABS(COALESCE(v.net_amount, 0))) AS total
           FROM vouchers v WHERE ${where}
          GROUP BY 1 ORDER BY 1 LIMIT 24`,
        params
      );
      return {
        voucher_type: type,
        from,
        to,
        count: Number(tot.rows[0]?.n || 0),
        total: num(tot.rows[0]?.total),
        top_parties: top.rows.map((x) => ({ party: x.party, entries: Number(x.n), total: num(x.total) })),
        by_month: months.rows.map((x) => ({ month: x.month, entries: Number(x.n), total: num(x.total) })),
      };
    },

    async list_transactions(args) {
      const { from, to } = range(args, 30);
      const limit = Math.min(Math.max(Number.parseInt(args?.limit, 10) || 10, 1), 25);
      const params = [s.adminId, s.company, from, to];
      let extra = "";
      const type = textArg(args?.voucher_type, 60);
      if (type) {
        params.push(type);
        extra += ` AND LOWER(v.voucher_type) = LOWER($${params.length})`;
      }
      const party = textArg(args?.party);
      if (party) {
        params.push(party);
        extra += ` AND v.party_name ILIKE '%' || $${params.length} || '%'`;
      }
      extra += voucherPerm("v.voucher_guid", params);
      params.push(limit);
      const r = await db.query(
        `SELECT v.voucher_date, v.voucher_type, v.reference_no, v.party_name, v.net_amount
           FROM vouchers v
          WHERE v.admin_id = $1 AND v.company_guid = $2
            AND v.voucher_date >= $3::date AND v.voucher_date <= $4::date${extra}
          ORDER BY v.voucher_date DESC, v.voucher_guid DESC
          LIMIT $${params.length}`,
        params
      );
      return {
        from,
        to,
        entries: r.rows.map((x) => ({
          date: iso(x.voucher_date),
          type: x.voucher_type,
          number: x.reference_no,
          party: x.party_name,
          amount: num(Math.abs(Number(x.net_amount || 0))),
        })),
      };
    },
  };

  /** Runs one tool call from Gemini; unknown tools / errors become data. */
  return async function run(name, args) {
    const fn = Object.prototype.hasOwnProperty.call(tools, name) ? tools[name] : null;
    if (!fn) return { error: `Unknown tool ${String(name).slice(0, 40)}` };
    return capJson(await fn(args || {}));
  };
}
