/* =========================================================
   CASH FLOW FORECAST — the calculations (no database here)

   Payment delay of a party = the day money came in (or went out) − the
   bill's due date, from the synced vouchers: each party's receipts are
   applied to its oldest open invoices first ("first in, first out").
   Only real money counts as a payment (Receipt / Payment vouchers); credit
   notes and journals reduce the bill but are not a payment.

   Forecast: every open bill on its due date, receivables moved later by the
   party's usual delay; 13 weeks (Monday–Sunday) of opening, money in, money
   out, closing.
   Dates are 'YYYY-MM-DD' strings (India calendar days).
========================================================= */

/** Bills more than this many days past due are "doubtful" (not counted). */
export const DOUBTFUL_DAYS = 90;
/** Payment history looked at for delays. */
export const WINDOW_DAYS = 365;
/** Below this much history a party's delay leans on the company's. */
export const MIN_BILLS = 3;
export const MIN_AMOUNT = 10000;
/** Single delays outside this range are capped (typos, one-offs). */
export const CAP_EARLY = -30;
export const CAP_LATE = 180;

const DAY = 86400000;
const EPS = 0.005;

export function dayNum(iso) {
  const [y, m, d] = String(iso).slice(0, 10).split("-").map(Number);
  return Math.round(Date.UTC(y, m - 1, d) / DAY);
}
export const isoOf = (n) => new Date(n * DAY).toISOString().slice(0, 10);
export const addDays = (iso, n) => isoOf(dayNum(iso) + n);
export const daysBetween = (a, b) => dayNum(b) - dayNum(a);

/** Monday of the week holding [iso]. */
export function mondayOf(iso) {
  const n = dayNum(iso);
  const dow = new Date(n * DAY).getUTCDay(); // 0 = Sunday
  return isoOf(n - ((dow + 6) % 7));
}

const round2 = (n) => Math.round(n * 100) / 100;
const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

/** Weighted quantile of [{v, w}] (w > 0); null when empty. */
export function weightedQuantile(samples, q) {
  const xs = samples.filter((s) => s.w > 0).sort((a, b) => a.v - b.v);
  const total = xs.reduce((a, s) => a + s.w, 0);
  if (!xs.length || total <= 0) return null;
  let cum = 0;
  for (const s of xs) {
    cum += s.w;
    if (cum >= q * total - 1e-9) return s.v;
  }
  return xs[xs.length - 1].v;
}

/**
 * One party's history, oldest first, matched first-in-first-out.
 * events: [{date, amount > 0, side: 'charge' | 'settle', cash: bool,
 *           due?: 'YYYY-MM-DD'}] — charge = owes more (invoice),
 * settle = owes less (payment / credit note / journal).
 * opening: owed before the first event (> 0) or paid in advance (< 0).
 * Returns the payments of real invoices: [{date, due, amount, delay, bill}].
 */
export function fifoPayments(events, { opening = 0, openingDate = null } = {}) {
  const sorted = [...events].sort(
    (a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : a.side === b.side ? 0 : a.side === "charge" ? -1 : 1)
  );
  const open = []; // invoices still owed: {left, due, bill (index) | null}
  const credits = []; // money paid ahead: {left, date, cash}
  if (opening > EPS) open.push({ left: opening, due: openingDate, bill: null });
  else if (opening < -EPS) credits.push({ left: -opening, date: openingDate, cash: false });
  const out = [];
  let bill = 0;
  for (const e of sorted) {
    let left = Number(e.amount) || 0;
    if (left <= EPS) continue;
    if (e.side === "charge") {
      const id = bill++;
      const due = e.due || e.date;
      // Paid ahead (advance): settles this invoice at once.
      while (left > EPS && credits.length) {
        const c = credits[0];
        const x = Math.min(left, c.left);
        if (c.cash && c.date) out.push({ date: c.date, due, amount: round2(x), delay: daysBetween(due, c.date), bill: id });
        c.left -= x;
        left -= x;
        if (c.left <= EPS) credits.shift();
      }
      if (left > EPS) open.push({ left, due, bill: id });
    } else {
      while (left > EPS && open.length) {
        const o = open[0];
        const x = Math.min(left, o.left);
        if (e.cash && o.bill !== null && o.due) {
          out.push({ date: e.date, due: o.due, amount: round2(x), delay: daysBetween(o.due, e.date), bill: o.bill });
        }
        o.left -= x;
        left -= x;
        if (o.left <= EPS) open.shift();
      }
      if (left > EPS) credits.push({ left, date: e.date, cash: !!e.cash });
    }
  }
  return out;
}

/**
 * Delay figures from payments made on or after [since].
 * → {median, p75, average, on_time_pct, bills, amount} or null.
 */
export function delayStats(payments, { since = null } = {}) {
  const ps = payments.filter((p) => !since || p.date >= since);
  if (!ps.length) return null;
  const xs = ps.map((p) => ({ v: clamp(p.delay, CAP_EARLY, CAP_LATE), w: p.amount }));
  const amount = xs.reduce((a, s) => a + s.w, 0);
  if (amount <= 0) return null;
  const onTime = xs.filter((s) => s.v <= 0).reduce((a, s) => a + s.w, 0);
  return {
    median: weightedQuantile(xs, 0.5),
    p75: weightedQuantile(xs, 0.75),
    average: Math.round(xs.reduce((a, s) => a + s.v * s.w, 0) / amount),
    on_time_pct: Math.round((onTime / amount) * 100),
    bills: new Set(ps.map((p) => p.bill)).size,
    amount: round2(amount),
  };
}

/**
 * The delay used for a party: its own when it has enough history, blended
 * with the company's when it has a little, the company's when none.
 * → {days, source: 'party' | 'blend' | 'company' | 'none', bills, on_time_pct}
 */
export function delayFor(stats, company) {
  const base = company ? company.median : null;
  if (!stats) {
    return base === null ? { days: 0, source: "none", bills: 0 } : { days: base, source: "company", bills: 0 };
  }
  const weight = Math.min(1, stats.bills / MIN_BILLS, stats.amount / MIN_AMOUNT);
  if (weight >= 1 || base === null) {
    return { days: stats.median, source: "party", bills: stats.bills, on_time_pct: stats.on_time_pct };
  }
  return {
    days: Math.round(weight * stats.median + (1 - weight) * base),
    source: "blend",
    bills: stats.bills,
    on_time_pct: stats.on_time_pct,
  };
}

/**
 * Exact payments from Tally's bill-wise allocations (Phase 2): each
 * receipt (customers) / payment (suppliers) line "Agst Ref <bill>" is the
 * day that bill got paid.
 * rows: [{ledger_name, bill_name, ref_type, voucher_type, date, amount
 *         (Tally sign: Dr −, Cr +), credit_days}]
 * kindOf(party) → 'recv' | 'pay' | undefined (then from the voucher type)
 * dueOf(party, bill) → due date from the bills table, or null
 * creditOf(party, kind) → usual credit days, or null
 * → Map(party → {kind, payments: [{date, due, amount, delay, bill}]})
 */
export function allocationPayments(rows, { kindOf = () => undefined, dueOf = () => null, creditOf = () => null } = {}) {
  const made = new Map(); // party@bill → {date, credit} (New Ref = the bill)
  for (const r of rows) {
    if (r.ref_type !== "New Ref") continue;
    const k = `${r.ledger_name}@${r.bill_name}`;
    const cur = made.get(k);
    if (!cur || r.date < cur.date) made.set(k, { date: r.date, credit: r.credit_days ?? null });
  }
  const out = new Map();
  for (const r of rows) {
    if (r.ref_type !== "Agst Ref") continue;
    const type = String(r.voucher_type || "");
    const amount = Number(r.amount) || 0;
    const party = r.ledger_name;
    let kind = kindOf(party);
    if (!kind) kind = /receipt/i.test(type) ? "recv" : /payment/i.test(type) ? "pay" : undefined;
    if (!kind) continue;
    // Real money that lowers what is owed: a receipt credits the customer,
    // a payment debits the supplier.
    const cash = kind === "recv" ? /receipt/i.test(type) && amount > 0 : /payment/i.test(type) && amount < 0;
    if (!cash) continue;
    let due = dueOf(party, r.bill_name);
    if (!due) {
      const m = made.get(`${party}@${r.bill_name}`);
      if (m) due = addDays(m.date, m.credit ?? creditOf(party, kind) ?? 0);
    }
    if (!due) continue;
    if (!out.has(party)) out.set(party, { kind, payments: [] });
    out.get(party).payments.push({
      date: r.date,
      due,
      amount: round2(Math.abs(amount)),
      delay: daysBetween(due, r.date),
      bill: `${party}@${r.bill_name}`,
    });
  }
  return out;
}

/**
 * Open bills that are advances (Phase 2): their Dr / Cr is the opposite of
 * most bills of that kind (Tally's Bills Receivable / Payable report signs).
 * rows: [{bill_type: 'RECEIVABLE' | 'PAYABLE', ledger_name, bill_name, raw_amount}]
 * → Set of `${kind}|${party}@${bill}` (kind 'recv' | 'pay').
 */
export function advanceKeys(rows) {
  const by = { recv: [], pay: [] };
  for (const r of rows) {
    const raw = Number(r.raw_amount) || 0;
    if (!raw) continue;
    by[String(r.bill_type).toUpperCase() === "PAYABLE" ? "pay" : "recv"].push({ key: `${r.ledger_name}@${r.bill_name}`, raw });
  }
  const out = new Set();
  for (const kind of ["recv", "pay"]) {
    const xs = by[kind];
    if (!xs.length) continue;
    const neg = xs.filter((x) => x.raw < 0).length;
    const pos = xs.length - neg;
    // Usual side: the majority; on a tie Tally's own (receivable Dr = −).
    const normalNeg = neg === pos ? kind === "recv" : neg > pos;
    for (const x of xs) if (x.raw < 0 !== normalNeg) out.add(`${kind}|${x.key}`);
  }
  return out;
}

/** Usual credit days (due − invoice date) of a list of [{date, due}]. */
export function creditDays(pairs) {
  const xs = pairs
    .map((p) => daysBetween(p.date, p.due))
    .filter((d) => d >= 0 && d <= 365)
    .sort((a, b) => a - b);
  return xs.length ? xs[Math.floor((xs.length - 1) / 2)] : null;
}

/**
 * The weekly forecast.
 * receivables / payables: [{party, bill, due (may be null), amount}]
 * delayOf(party): {days, source, bills} — used for receivables in
 *   'adjusted' mode.
 * opening: cash + bank today (null when unknown).
 */
export function buildForecast({
  today,
  weeks = 13,
  opening = null,
  receivables = [],
  payables = [],
  delayOf = () => ({ days: 0, source: "none", bills: 0 }),
  mode = "adjusted",
  includeDoubtful = false,
  isAdvance = () => false,
}) {
  const start0 = mondayOf(today);
  const t = dayNum(today);
  const w0 = dayNum(start0);
  const rows = Array.from({ length: weeks }, (_, i) => ({
    start: isoOf(w0 + 7 * i),
    end: isoOf(w0 + 7 * i + 6),
    inflow: 0,
    outflow: 0,
    inflow_bills: 0,
    outflow_bills: 0,
    overdue_inflow: 0,
  }));
  const later = { inflow: 0, outflow: 0, inflow_bills: 0, outflow_bills: 0 };
  const doubtful = { amount: 0, bills: 0, days: DOUBTFUL_DAYS };
  const noDue = { amount: 0, bills: 0 };
  // Advances: paid ahead, nothing more to come in / go out for them.
  const advances = { received: { amount: 0, bills: 0 }, paid: { amount: 0, bills: 0 } };
  const lines = { inflows: [], outflows: [] };

  const place = (expectedN, amount, isIn) => {
    const i = Math.floor((expectedN - w0) / 7);
    if (i >= weeks) {
      if (isIn) {
        later.inflow += amount;
        later.inflow_bills++;
      } else {
        later.outflow += amount;
        later.outflow_bills++;
      }
      return null;
    }
    const r = rows[Math.max(0, i)];
    if (isIn) {
      r.inflow += amount;
      r.inflow_bills++;
    } else {
      r.outflow += amount;
      r.outflow_bills++;
    }
    return Math.max(0, i);
  };

  for (const b of receivables) {
    const amount = Number(b.amount) || 0;
    if (amount <= 0) continue;
    if (isAdvance("recv", b.party, b.bill)) {
      advances.received.amount += amount;
      advances.received.bills++;
      continue;
    }
    if (!b.due) {
      noDue.amount += amount;
      noDue.bills++;
    }
    const due = b.due || today;
    const pastDue = t - dayNum(due);
    if (pastDue > DOUBTFUL_DAYS && !includeDoubtful) {
      doubtful.amount += amount;
      doubtful.bills++;
      continue;
    }
    const d = mode === "adjusted" ? delayOf(b.party) : { days: 0, source: "due", bills: 0 };
    let expected = dayNum(due) + (d.days || 0);
    const overdue = expected < t;
    if (overdue) expected = t; // late already: expected from today
    const week = place(expected, amount, true);
    if (week !== null && overdue) rows[week].overdue_inflow += amount;
    lines.inflows.push({
      party: b.party,
      bill: b.bill,
      due: b.due || null,
      expected: isoOf(expected),
      amount: round2(amount),
      delay_days: d.days || 0,
      delay_source: d.source,
      overdue,
      week,
    });
  }
  for (const b of payables) {
    const amount = Number(b.amount) || 0;
    if (amount <= 0) continue;
    if (isAdvance("pay", b.party, b.bill)) {
      advances.paid.amount += amount;
      advances.paid.bills++;
      continue;
    }
    const due = b.due || today;
    // A payable past its due date is still owed: due now.
    const expected = Math.max(dayNum(due), t);
    const week = place(expected, amount, false);
    lines.outflows.push({
      party: b.party,
      bill: b.bill,
      due: b.due || null,
      expected: isoOf(expected),
      amount: round2(amount),
      overdue: dayNum(due) < t,
      week,
    });
  }

  let run = opening;
  let shortfall = null;
  for (const r of rows) {
    r.inflow = round2(r.inflow);
    r.outflow = round2(r.outflow);
    r.overdue_inflow = round2(r.overdue_inflow);
    r.net = round2(r.inflow - r.outflow);
    r.opening = run === null ? null : round2(run);
    r.closing = run === null ? null : round2(run + r.net);
    r.shortfall = r.closing !== null && r.closing < 0;
    if (r.shortfall && !shortfall) shortfall = r.start;
    run = run === null ? null : run + r.net;
  }
  const sum = (k) => round2(rows.reduce((a, r) => a + r[k], 0));
  const byExpected = (a, b) => (a.expected < b.expected ? -1 : a.expected > b.expected ? 1 : b.amount - a.amount);
  lines.inflows.sort(byExpected);
  lines.outflows.sort(byExpected);
  return {
    mode,
    first_week: start0,
    weeks: rows,
    totals: { inflow: sum("inflow"), outflow: sum("outflow"), net: round2(sum("inflow") - sum("outflow")) },
    later: { ...later, inflow: round2(later.inflow), outflow: round2(later.outflow) },
    doubtful: { ...doubtful, amount: round2(doubtful.amount) },
    no_due_date: { ...noDue, amount: round2(noDue.amount) },
    advances: {
      received: { ...advances.received, amount: round2(advances.received.amount) },
      paid: { ...advances.paid, amount: round2(advances.paid.amount) },
    },
    shortfall_week: shortfall,
    lines,
  };
}
