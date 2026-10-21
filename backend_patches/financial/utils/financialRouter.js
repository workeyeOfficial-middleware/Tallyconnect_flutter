/* =========================================================
   FINANCIAL REPORTS — routes (factory; dependencies passed in)

   Agent (account admin login, the one the Tally Agent signs in with):
     POST /api/financial/agent/groups            the group tree (replace)
     POST /api/financial/agent/snapshot/begin    {company_guid, as_on, fy_from} → {batch_id}
     POST /api/financial/agent/snapshot/rows     {batch_id, ledgers[], groups[]} (chunks)
     POST /api/financial/agent/snapshot/commit   {batch_id, ledger_count, group_count}
     POST /api/financial/agent/stock-values      {company_guid, values:[{as_on, value}]}
     POST /api/financial/agent/books             {company_guid, books_from, vouchers_from, fy_from, opening_stock}
   Agents from 2026-10-15 send no balances by default: the server starts
   from the ledger opening balances at the books' start (fin_books) and
   carries each year into the next (needs the year-end closing stock).
   Current agents upload, per financial year, ONE anchor (kind "anchor":
   Tally's closing balances the day before the synced vouchers begin) and
   month-end closing stock values; reports for any date are computed from
   the anchor plus the synced voucher entries (financialData.js).
   A snapshot becomes visible only on commit, all at once; an unfinished
   upload never shows partial figures.

   App (admins always; team users only when the admin granted access):
     GET /api/financial/me
     GET /api/financial/periods
     GET /api/financial/trial-balance?as_on=
     GET /api/financial/profit-loss?from=&to=
     GET /api/financial/balance-sheet?as_on=
     GET /api/financial/expenses?from=&to=&purchases=1
     GET /api/financial/cash-flow?from=&to=         cash / bank in and out
     GET /api/financial/ledger-vouchers?guid=|name=&from=&to=
   When the synced vouchers begin with the books, every report takes any
   From–To period (Tally's F2): Trial Balance / Balance Sheet as on `to`
   with `from` as the period start (as_on still accepted).
   Account admin:
     GET /api/financial/access
     PUT /api/financial/access/:userId           {enabled}
     PUT /api/financial/stock-values             {as_on, value} — a closing
         stock the admin enters (e.g. a year end, so that year's opening
         stock is known); /periods lists the missing ones as stock_needed

   Everything is scoped to the login's account and its ACTIVE company.
   Read-only for the app; nothing is written to Tally.
========================================================= */
import express from "express";
import {
  balanceSheet,
  cleanRow,
  dayBefore,
  expenseMonths,
  expenseReport,
  isIsoDate,
  profitLoss,
  trialBalance,
} from "./financialCore.js";
import { createFinancialData, todayIst } from "./financialData.js";

const MAX_ROWS_PER_CALL = 5000;

const isoOf = (d) => (d instanceof Date ? d.toISOString().slice(0, 10) : String(d).slice(0, 10));

/** True for the last day of a month. */
function isMonthEnd(d) {
  const x = new Date(`${d}T00:00:00Z`);
  x.setUTCDate(x.getUTCDate() + 1);
  return x.getUTCDate() === 1;
}

class HttpError extends Error {
  constructor(status, message, code) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export function createFinancialRouter({ db, auth, log = console, now = () => new Date() }) {
  const router = express.Router();
  const data = createFinancialData(db, now);

  const handle = (fn) => async (req, res) => {
    try {
      await fn(req, res);
    } catch (err) {
      if (err instanceof HttpError) {
        return res.status(err.status).json({
          success: false,
          message: err.message,
          ...(err.code ? { code: err.code } : {}),
        });
      }
      log.error("financial error:", err?.message || err);
      if (!res.headersSent) res.status(500).json({ success: false, message: "Server error" });
    }
  };

  const adminIdOf = (u) => u?.adminId ?? (u?.role === "ADMIN" ? u?.id : null);

  /** One SQL transaction when the pool supports it (pg). */
  async function tx(fn) {
    if (typeof db.connect !== "function") return fn(db);
    const client = await db.connect();
    try {
      await client.query("BEGIN");
      const out = await fn(client);
      await client.query("COMMIT");
      return out;
    } catch (e) {
      await client.query("ROLLBACK").catch(() => {});
      throw e;
    } finally {
      client.release?.();
    }
  }

  /* ------------------------------------------------- agent: upload */
  async function agentScope(req, companyGuid) {
    const u = req.user || {};
    if (u.role !== "ADMIN") throw new HttpError(403, "Only the account admin's agent can upload", "forbidden");
    const adminId = adminIdOf(u);
    const g = String(companyGuid || "").trim();
    if (!g || g.length > 100) throw new HttpError(400, "company_guid is required");
    const c = await db.query(`SELECT 1 FROM companies WHERE company_guid = $1 AND admin_id = $2`, [g, adminId]);
    if (!c.rowCount) throw new HttpError(403, "This company does not belong to this account", "forbidden");
    return { adminId, company: g };
  }

  router.post(
    "/api/financial/agent/groups",
    auth,
    handle(async (req, res) => {
      const s = await agentScope(req, req.body?.company_guid);
      const list = Array.isArray(req.body?.groups) ? req.body.groups : null;
      if (!list || list.length > MAX_ROWS_PER_CALL) throw new HttpError(400, "groups must be a list (max 5000)");
      const groups = list.map((g) => cleanRow(g, "master")).filter(Boolean);
      await tx(async (q) => {
        await q.query(`DELETE FROM tally_groups WHERE admin_id = $1 AND company_guid = $2`, [s.adminId, s.company]);
        if (groups.length) {
          await q.query(
            `INSERT INTO tally_groups (admin_id, company_guid, name, parent, is_revenue, is_deemed_positive, affects_gross_profit)
             SELECT $1, $2, x.name, x.parent, x.is_revenue, x.is_deemed_positive, x.affects_gross_profit
               FROM jsonb_to_recordset($3::jsonb)
                 AS x(name text, parent text, is_revenue boolean, is_deemed_positive boolean, affects_gross_profit boolean)
             ON CONFLICT (admin_id, company_guid, name) DO NOTHING`,
            [s.adminId, s.company, JSON.stringify(groups)]
          );
        }
      });
      res.json({ success: true, count: groups.length });
    })
  );

  router.post(
    "/api/financial/agent/snapshot/begin",
    auth,
    handle(async (req, res) => {
      const s = await agentScope(req, req.body?.company_guid);
      const { as_on: asOn, fy_from: fyFrom } = req.body || {};
      if (!isIsoDate(asOn) || !isIsoDate(fyFrom) || fyFrom > asOn) {
        throw new HttpError(400, "as_on and fy_from must be YYYY-MM-DD dates (fy_from ≤ as_on)");
      }
      // "anchor": a year's starting balances (current agents); anything else
      // is an older agent's per-date snapshot.
      const kind = req.body?.kind === "anchor" ? "anchor" : "snapshot";
      // Unfinished uploads older than a day are dropped.
      await db.query(
        `DELETE FROM fin_batches WHERE admin_id = $1 AND committed_at IS NULL AND created_at < NOW() - INTERVAL '1 day'`,
        [s.adminId]
      );
      const b = await db.query(
        `INSERT INTO fin_batches (admin_id, company_guid, as_on, fy_from, kind) VALUES ($1, $2, $3, $4, $5) RETURNING id`,
        [s.adminId, s.company, asOn, fyFrom, kind]
      );
      res.json({ success: true, batch_id: Number(b.rows[0].id) });
    })
  );

  async function batchFor(req) {
    const u = req.user || {};
    if (u.role !== "ADMIN") throw new HttpError(403, "Only the account admin's agent can upload", "forbidden");
    const id = Number.parseInt(req.body?.batch_id, 10);
    if (!Number.isInteger(id) || id <= 0) throw new HttpError(400, "batch_id is required");
    const b = await db.query(
      `SELECT id, admin_id, company_guid, as_on, fy_from, kind, committed_at FROM fin_batches WHERE id = $1 AND admin_id = $2`,
      [id, adminIdOf(u)]
    );
    const row = b.rows[0];
    if (!row) throw new HttpError(404, "Upload not found");
    if (row.committed_at) throw new HttpError(409, "Upload already committed");
    return row;
  }

  router.post(
    "/api/financial/agent/snapshot/rows",
    auth,
    handle(async (req, res) => {
      const b = await batchFor(req);
      const ledgers = Array.isArray(req.body?.ledgers) ? req.body.ledgers : [];
      const groups = Array.isArray(req.body?.groups) ? req.body.groups : [];
      if (ledgers.length + groups.length > MAX_ROWS_PER_CALL) throw new HttpError(400, "At most 5000 rows per call");
      const L = ledgers.map((x) => cleanRow(x, "ledger")).filter(Boolean);
      const G = groups.map((x) => cleanRow(x, "group")).filter(Boolean);
      if (L.length) {
        await db.query(
          `INSERT INTO fin_ledger_balances (batch_id, ledger_guid, ledger_name, parent, closing, opening)
           SELECT $1, x.guid, x.name, x.parent, x.closing, x.opening
             FROM jsonb_to_recordset($2::jsonb) AS x(guid text, name text, parent text, closing numeric, opening numeric)`,
          [b.id, JSON.stringify(L)]
        );
      }
      if (G.length) {
        await db.query(
          `INSERT INTO fin_group_balances (batch_id, group_name, parent, closing, opening)
           SELECT $1, x.name, x.parent, x.closing, x.opening
             FROM jsonb_to_recordset($2::jsonb) AS x(name text, parent text, closing numeric, opening numeric)`,
          [b.id, JSON.stringify(G)]
        );
      }
      res.json({ success: true, ledgers: L.length, groups: G.length });
    })
  );

  router.post(
    "/api/financial/agent/snapshot/commit",
    auth,
    handle(async (req, res) => {
      const b = await batchFor(req);
      const counts = await db.query(
        `SELECT (SELECT COUNT(*)::int FROM fin_ledger_balances WHERE batch_id = $1) AS ledgers,
                (SELECT COUNT(*)::int FROM fin_group_balances WHERE batch_id = $1) AS groups`,
        [b.id]
      );
      const got = counts.rows[0] || { ledgers: 0, groups: 0 };
      const want = { ledgers: Number(req.body?.ledger_count), groups: Number(req.body?.group_count) };
      if (got.ledgers !== want.ledgers || got.groups !== want.groups) {
        throw new HttpError(
          409,
          `Upload incomplete: ${got.ledgers}/${want.ledgers} ledgers, ${got.groups}/${want.groups} groups`,
          "incomplete"
        );
      }
      await tx(async (q) => {
        const old = await q.query(
          `SELECT batch_id FROM fin_snapshots WHERE admin_id = $1 AND company_guid = $2 AND as_on = $3`,
          [b.admin_id, b.company_guid, b.as_on]
        );
        await q.query(
          `INSERT INTO fin_snapshots (admin_id, company_guid, as_on, fy_from, batch_id, kind, synced_at)
           VALUES ($1, $2, $3, $4, $5, $6, NOW())
           ON CONFLICT (admin_id, company_guid, as_on)
           DO UPDATE SET fy_from = EXCLUDED.fy_from, batch_id = EXCLUDED.batch_id,
                         kind = EXCLUDED.kind, synced_at = NOW()`,
          [b.admin_id, b.company_guid, b.as_on, b.fy_from, b.id, b.kind || "snapshot"]
        );
        await q.query(`UPDATE fin_batches SET committed_at = NOW() WHERE id = $1`, [b.id]);
        const drop = async (id) => {
          await q.query(`DELETE FROM fin_ledger_balances WHERE batch_id = $1`, [id]);
          await q.query(`DELETE FROM fin_group_balances WHERE batch_id = $1`, [id]);
          await q.query(`DELETE FROM fin_batches WHERE id = $1`, [id]);
        };
        const oldId = old.rows[0]?.batch_id;
        if (oldId && Number(oldId) !== Number(b.id)) await drop(oldId);
        // Older agents' daily snapshots replace earlier daily ones (month
        // ends and anchors are kept), so figures do not pile up per day.
        const asOn = isoOf(b.as_on);
        if (b.kind !== "anchor" && !isMonthEnd(asOn)) {
          const daily = await q.query(
            `SELECT as_on, batch_id, kind FROM fin_snapshots
              WHERE admin_id = $1 AND company_guid = $2 AND as_on < $3`,
            [b.admin_id, b.company_guid, asOn]
          );
          for (const x of daily.rows) {
            if (x.kind === "anchor" || isMonthEnd(isoOf(x.as_on))) continue;
            await q.query(
              `DELETE FROM fin_snapshots WHERE admin_id = $1 AND company_guid = $2 AND as_on = $3`,
              [b.admin_id, b.company_guid, x.as_on]
            );
            await drop(x.batch_id);
          }
        }
      });
      res.json({ success: true, as_on: b.as_on });
    })
  );

  router.post(
    "/api/financial/agent/stock-values",
    auth,
    handle(async (req, res) => {
      const s = await agentScope(req, req.body?.company_guid);
      const list = Array.isArray(req.body?.values) ? req.body.values : null;
      if (!list || list.length > 500) throw new HttpError(400, "values must be a list (max 500)");
      const vals = [];
      for (const v of list) {
        const n = Number(v?.value);
        if (!isIsoDate(v?.as_on) || !Number.isFinite(n)) throw new HttpError(400, "Each value needs as_on (YYYY-MM-DD) and a number");
        vals.push({ as_on: v.as_on, value: Math.round(Math.abs(n) * 100) / 100 });
      }
      if (vals.length) {
        await db.query(
          `INSERT INTO fin_stock_values (admin_id, company_guid, as_on, value)
           SELECT $1, $2, x.as_on, x.value FROM jsonb_to_recordset($3::jsonb) AS x(as_on date, value numeric)
           ON CONFLICT (admin_id, company_guid, as_on)
           DO UPDATE SET value = EXCLUDED.value, synced_at = NOW()`,
          [s.adminId, s.company, JSON.stringify(vals)]
        );
      }
      res.json({ success: true, count: vals.length });
    })
  );

  // The books-beginning date, where the synced vouchers begin and the
  // items' opening values (light masters): the server starts from the
  // ledger opening balances it already has.
  router.post(
    "/api/financial/agent/books",
    auth,
    handle(async (req, res) => {
      const s = await agentScope(req, req.body?.company_guid);
      const b = req.body || {};
      const stock = Number(b.opening_stock ?? 0);
      if (!isIsoDate(b.books_from)) throw new HttpError(400, "books_from must be YYYY-MM-DD");
      if (b.vouchers_from != null && !isIsoDate(b.vouchers_from)) throw new HttpError(400, "vouchers_from must be YYYY-MM-DD");
      if (b.fy_from != null && !isIsoDate(b.fy_from)) throw new HttpError(400, "fy_from must be YYYY-MM-DD");
      if (!Number.isFinite(stock)) throw new HttpError(400, "opening_stock must be a number");
      await db.query(
        `INSERT INTO fin_books (admin_id, company_guid, books_from, vouchers_from, fy_from, opening_stock)
         VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (admin_id, company_guid)
         DO UPDATE SET books_from = EXCLUDED.books_from, vouchers_from = EXCLUDED.vouchers_from,
                       fy_from = EXCLUDED.fy_from, opening_stock = EXCLUDED.opening_stock, synced_at = NOW()`,
        [s.adminId, s.company, b.books_from, b.vouchers_from ?? null, b.fy_from ?? b.books_from, Math.round(Math.abs(stock) * 100) / 100]
      );
      res.json({ success: true });
    })
  );

  /** What the app says when no report date is available yet. */
  const REASONS = {
    not_synced: "Financial figures are not synced yet. Update the TallyConnect Agent on the Tally computer and let it sync once.",
    vouchers_after_books:
      "Entries are synced from a later date than the start of your books in Tally. Set Sync Start to the start of your books, or ask support to turn on opening balances from Tally.",
    stock_values:
      "Closing stock values are not synced yet. P&L and Balance Sheet need Tally's closing stock at the year end; ask support to turn on closing stock sync for your Agent.",
  };

  /* ---------------------------------------------- app: read reports */
  async function readScope(req) {
    const u = req.user || {};
    if (!u.id) throw new HttpError(401, "Unauthorized");
    const adminId = adminIdOf(u);
    if (!adminId) throw new HttpError(403, "Access denied", "forbidden");
    const isAdmin = u.role === "ADMIN";
    if (!isAdmin) {
      const a = await db.query(
        `SELECT 1 FROM financial_report_access WHERE admin_id = $1 AND user_id = $2`,
        [adminId, u.id]
      );
      if (!a.rowCount) {
        throw new HttpError(403, "Ask your admin for access to financial reports.", "no_access");
      }
    }
    const c = await db.query(
      `SELECT ac.company_guid, c.name AS company_name
         FROM active_company ac
         LEFT JOIN companies c ON c.company_guid = ac.company_guid AND c.admin_id = ac.admin_id
        WHERE ac.admin_id = $1 LIMIT 1`,
      [adminId]
    );
    const company = c.rows[0]?.company_guid;
    if (!company) throw new HttpError(409, "No company is selected for this account.", "no_company");
    return { adminId, company, companyName: c.rows[0]?.company_name || "", isAdmin };
  }

  /** The company's figures: groups, anchors, stock (see financialData.js). */
  async function contextOf(s) {
    const ctx = await data.context(s);
    if (!ctx.groups.length || !ctx.anchors.length) {
      throw new HttpError(
        409,
        "Financial reports are not synced yet. Update the TallyConnect Agent and let it sync once.",
        "not_synced"
      );
    }
    return ctx;
  }

  /** The figures on [d], or a 404 that names the reason. */
  async function at(s, ctx, d) {
    if (!isIsoDate(d)) throw new HttpError(400, "Dates must be YYYY-MM-DD");
    const snap = await data.snapshotAt(s, ctx, d);
    if (!snap) {
      throw new HttpError(
        404,
        `No Tally figures for ${d} yet. Choose one of the available dates (month ends and today).`,
        "no_snapshot"
      );
    }
    return snap;
  }

  /** `to` + the day before `from` (null on the year start). */
  async function periodPair(s, ctx, from, to) {
    if (!isIsoDate(from) || !isIsoDate(to) || from > to) {
      throw new HttpError(400, "from and to must be YYYY-MM-DD dates (from ≤ to)");
    }
    const end = await at(s, ctx, to);
    if (from < end.fy_from) {
      throw new HttpError(400, "Choose a period within one financial year.", "cross_year");
    }
    if (from === end.fy_from) return { end, prev: null };
    const prev = await data.snapshotAt(s, ctx, dayBefore(from));
    if (!prev || prev.fy_from !== end.fy_from) {
      throw new HttpError(
        404,
        `No Tally figures for the day before ${from}. Periods start on the 1st of a synced month.`,
        "no_snapshot"
      );
    }
    return { end, prev };
  }

  const meta = (s, extra) => ({ company: s.companyName, ...extra });

  /**
   * The period of a request: [to] = `to` (or `as_on`); [from] = `from`, else
   * the start of [to]'s financial year (what the reports showed before).
   */
  function periodOf(req, ctx) {
    const to = String(req.query.to || req.query.as_on || "");
    if (!isIsoDate(to)) throw new HttpError(400, "Dates must be YYYY-MM-DD");
    const from = req.query.from ? String(req.query.from) : data.fyStartFor(ctx, to);
    if (!isIsoDate(from) || from > to) throw new HttpError(400, "from and to must be YYYY-MM-DD dates (from ≤ to)");
    return { from, to };
  }

  const dmy = (d) => `${d.slice(8, 10)}-${d.slice(5, 7)}-${d.slice(0, 4)}`;

  /** Figures for [from] … [to] (any period), or a 404 naming the stock dates missing. */
  async function figures(s, ctx, from, to, opts) {
    const x = await data.periodFigures(s, ctx, from, to, opts);
    if (x.missing) {
      throw new HttpError(
        404,
        `Tally's closing stock on ${x.missing.map(dmy).join(" and ")} is not synced yet. The TallyConnect Agent ` +
          `reads it from Tally (year ends and month ends first, then every day) — try again later or choose other dates.`,
        "no_stock"
      );
    }
    return x;
  }

  /** Vouchers synced from the books' start (any period possible), else the reason. */
  function needBooks(ctx) {
    if (!data.booksAnchored(ctx)) {
      throw new HttpError(409, REASONS.vouchers_after_books, "vouchers_after_books");
    }
  }

  router.get(
    "/api/financial/me",
    auth,
    handle(async (req, res) => {
      try {
        const s = await readScope(req);
        res.json({ success: true, can_view: true, is_admin: s.isAdmin });
      } catch (err) {
        if (err instanceof HttpError && err.code === "no_access") {
          return res.json({ success: true, can_view: false, is_admin: false });
        }
        throw err;
      }
    })
  );

  router.get(
    "/api/financial/periods",
    auth,
    handle(async (req, res) => {
      const s = await readScope(req);
      const ctx = await data.context(s);
      const ready = ctx.groups.length > 0 && ctx.anchors.length > 0;
      const reason = await data.missingReason(ctx);
      res.json({
        success: true,
        company: s.companyName,
        groups_synced: ready,
        snapshots: ready ? await data.offeredDates(ctx) : [],
        // Year ends whose closing stock is missing (the admin can enter them).
        stock_needed: ready ? await data.neededStock(ctx) : [],
        can_enter_stock: s.isAdmin,
        // Any From–To period can be worked out (vouchers from the books' start);
        // the dates with a closing stock value (P&L / Balance Sheet need one).
        any_period: ready && data.booksAnchored(ctx),
        books_from: ctx.books ? ctx.books.from : null,
        stock_dates: ready ? data.stockDates(ctx) : [],
        ...(reason ? { reason, message: REASONS[reason] } : {}),
      });
    })
  );

  router.get(
    "/api/financial/trial-balance",
    auth,
    handle(async (req, res) => {
      const s = await readScope(req);
      const ctx = await contextOf(s);
      if (data.booksAnchored(ctx)) {
        // Tally's Trial Balance for a period: closing balances on [to];
        // income / expense ledgers for the period; the Profit & Loss A/c
        // with the profit made before [from]; opening stock the day before.
        const { from, to } = periodOf(req, ctx);
        const x = await figures(s, ctx, from, to, { closingStock: false });
        const ledgers = x.snap.ledgers.map((l) => (x.plName && l.name === x.plName ? { ...l, closing: x.plOpening } : l));
        if (!x.plName && x.plOpening !== 0) {
          ledgers.push({ name: "Profit & Loss A/c", guid: null, parent: "Primary", closing: x.plOpening, opening: 0 });
        }
        const tb = trialBalance(ctx.groups, { ...x.snap, ledgers });
        return res.json({ success: true, data: meta(s, { ...tb, from: x.from, to }) });
      }
      const snap = await at(s, ctx, String(req.query.as_on || req.query.to || ""));
      res.json({ success: true, data: meta(s, trialBalance(ctx.groups, snap)) });
    })
  );

  router.get(
    "/api/financial/profit-loss",
    auth,
    handle(async (req, res) => {
      const s = await readScope(req);
      const ctx = await contextOf(s);
      if (data.booksAnchored(ctx)) {
        // Any period, across financial years too (Tally's F2 period).
        const { from, to } = periodOf(req, ctx);
        const x = await figures(s, ctx, from, to);
        return res.json({ success: true, data: meta(s, { ...profitLoss(ctx.groups, x.snap, null), from: x.from, to }) });
      }
      const { end, prev } = await periodPair(s, ctx, String(req.query.from || ""), String(req.query.to || ""));
      res.json({ success: true, data: meta(s, { ...profitLoss(ctx.groups, end, prev), from: String(req.query.from) }) });
    })
  );

  router.get(
    "/api/financial/balance-sheet",
    auth,
    handle(async (req, res) => {
      const s = await readScope(req);
      const ctx = await contextOf(s);
      if (data.booksAnchored(ctx)) {
        // As on [to]; the Profit & Loss A/c split like Tally: Opening Balance
        // (its own + profit before [from]) and Current Period ([from] … [to]).
        const { from, to } = periodOf(req, ctx);
        const x = await figures(s, ctx, from, to);
        const check = await data.unbalanced(s, dayBefore(ctx.books.from), to);
        const bs = balanceSheet(ctx.groups, x.snap, { plOpening: x.plOpening });
        return res.json({ success: true, data: meta(s, { ...bs, from: x.from, to, data_check: check }) });
      }
      const snap = await at(s, ctx, String(req.query.as_on || req.query.to || ""));
      const [plOpening, check] = await Promise.all([data.plOpening(s, ctx, snap), data.dataCheck(s, ctx, snap.as_on)]);
      res.json({ success: true, data: meta(s, { ...balanceSheet(ctx.groups, snap, { plOpening }), data_check: check }) });
    })
  );

  router.get(
    "/api/financial/expenses",
    auth,
    handle(async (req, res) => {
      const s = await readScope(req);
      const ctx = await contextOf(s);
      const includePurchases = req.query.purchases === "1";
      if (data.booksAnchored(ctx)) {
        // Any period; stock is not part of this report.
        const { from: f0, to } = periodOf(req, ctx);
        const x = await figures(s, ctx, f0, to, { stock: false });
        const monthly = await data.monthlyMovements(s, dayBefore(x.from), to);
        const rep = expenseReport(ctx.groups, x.snap, null, { includePurchases, months: [] });
        rep.by_month = expenseMonths(ctx.groups, ctx.masters, monthly, { includePurchases, to });
        return res.json({ success: true, data: meta(s, { ...rep, from: x.from, to }) });
      }
      const from = String(req.query.from || "");
      const { end, prev } = await periodPair(s, ctx, from, String(req.query.to || ""));
      // Month-wise trend straight from the voucher movements.
      const months = await data.monthSnapshots(s, ctx, end, prev ? prev.as_on : null);
      res.json({
        success: true,
        data: meta(s, {
          ...expenseReport(ctx.groups, end, prev, { includePurchases: req.query.purchases === "1", months }),
          from,
        }),
      });
    })
  );

  // Cash Flow statement for a period, from the cash / bank vouchers (no stock,
  // nothing estimated). Separate from the Cash Flow Forecast (/api/cashflow).
  router.get(
    "/api/financial/cash-flow",
    auth,
    handle(async (req, res) => {
      const s = await readScope(req);
      const ctx = await contextOf(s);
      needBooks(ctx);
      const { from, to } = periodOf(req, ctx);
      res.json({ success: true, data: meta(s, await data.cashFlow(s, ctx, from, to)) });
    })
  );

  // One ledger's vouchers in a period (drill-down from a report row).
  router.get(
    "/api/financial/ledger-vouchers",
    auth,
    handle(async (req, res) => {
      const s = await readScope(req);
      const ctx = await contextOf(s);
      needBooks(ctx);
      const { from, to } = periodOf(req, ctx);
      const guid = req.query.guid ? String(req.query.guid).slice(0, 100) : null;
      const name = req.query.name ? String(req.query.name).slice(0, 300) : null;
      if (!guid && !name) throw new HttpError(400, "guid or name is required");
      const out = await data.ledgerVouchers(s, ctx, { guid, name }, from, to);
      if (!out) throw new HttpError(404, "Ledger not found", "no_ledger");
      res.json({ success: true, data: meta(s, out) });
    })
  );

  /* ------------------------------- admin: a closing stock entered by hand */
  // Tally's closing stock on a past date can only be asked of Tally with a
  // date range, which froze it; the admin can enter the figure instead
  // (e.g. the audited closing stock of 31-03, so that year's opening stock
  // is known). Active company only; replaces a value saved for that date.
  router.put(
    "/api/financial/stock-values",
    auth,
    handle(async (req, res) => {
      const s = await readScope(req);
      if (!s.isAdmin) throw new HttpError(403, "Only the admin can enter closing stock.", "forbidden");
      const asOn = String(req.body?.as_on || "");
      const raw = req.body?.value;
      const value = typeof raw === "number" ? raw : Number(String(raw ?? "").replace(/,/g, "").trim());
      if (!isIsoDate(asOn)) throw new HttpError(400, "as_on must be a YYYY-MM-DD date");
      if (asOn > todayIst(now())) throw new HttpError(400, "The date cannot be in the future");
      if (raw === null || raw === undefined || String(raw).trim() === "" || !Number.isFinite(value) || value < 0 || value > 1e13) {
        throw new HttpError(400, "value must be a closing stock amount (0 or more)");
      }
      const v = Math.round(value * 100) / 100;
      await db.query(
        `INSERT INTO fin_stock_values (admin_id, company_guid, as_on, value)
         VALUES ($1, $2, $3::date, $4)
         ON CONFLICT (admin_id, company_guid, as_on)
         DO UPDATE SET value = EXCLUDED.value, synced_at = NOW()`,
        [s.adminId, s.company, asOn, v]
      );
      res.json({ success: true, as_on: asOn, value: v });
    })
  );

  /* ------------------------------------------- admin: who can view */
  const requireAccountAdmin = (req, res, next) => {
    if (req.user?.role !== "ADMIN") {
      return res.status(403).json({ success: false, message: "Only the admin can change access." });
    }
    next();
  };

  router.get(
    "/api/financial/access",
    auth,
    requireAccountAdmin,
    handle(async (req, res) => {
      const r = await db.query(
        `SELECT user_id FROM financial_report_access WHERE admin_id = $1`,
        [adminIdOf(req.user)]
      );
      res.json({ success: true, user_ids: r.rows.map((x) => Number(x.user_id)) });
    })
  );

  router.put(
    "/api/financial/access/:userId",
    auth,
    requireAccountAdmin,
    handle(async (req, res) => {
      const adminId = adminIdOf(req.user);
      const userId = Number.parseInt(req.params.userId, 10);
      if (!Number.isInteger(userId) || userId <= 0 || String(userId) !== req.params.userId) {
        throw new HttpError(400, "Invalid user id");
      }
      if (typeof req.body?.enabled !== "boolean") throw new HttpError(400, "enabled must be true or false");
      // Only this account's own team members.
      const u = await db.query(`SELECT id FROM users WHERE id = $1 AND admin_id = $2 AND role <> 'ADMIN'`, [userId, adminId]);
      if (!u.rowCount) throw new HttpError(404, "Team member not found");
      if (req.body.enabled) {
        await db.query(
          `INSERT INTO financial_report_access (admin_id, user_id, granted_by)
           VALUES ($1, $2, $3) ON CONFLICT (admin_id, user_id) DO NOTHING`,
          [adminId, userId, req.user.id]
        );
      } else {
        await db.query(`DELETE FROM financial_report_access WHERE admin_id = $1 AND user_id = $2`, [adminId, userId]);
      }
      res.json({ success: true, enabled: req.body.enabled });
    })
  );

  return router;
}
