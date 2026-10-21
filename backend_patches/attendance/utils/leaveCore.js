/* =========================================================
   LEAVE MANAGEMENT — pure helpers (no database): the account's settings,
   leave years, working days of a request, balances, request validation.
   Every rule comes from the admin's Leave settings; the values below are
   only what an account gets before the admin changes anything.
========================================================= */
import { addDays, cleanKey, cleanNote, daysBetween, isIsoDate } from "./attendanceCore.js";

export const DEFAULT_SETTINGS = Object.freeze({
  enabled: false,
  year_start_month: 4, // April, like the books
  weekly_off: [0], // Sunday
  half_day: true,
  backdate_days: 7,
  max_request_days: 30,
});

/** What "Add default types" creates (the admin can change or remove them). */
export const DEFAULT_TYPES = Object.freeze([
  { name: "Casual Leave", yearly_quota: 12, paid: true, carry_forward: false, max_carry: null },
  { name: "Sick Leave", yearly_quota: 6, paid: true, carry_forward: false, max_carry: null },
  { name: "Unpaid Leave", yearly_quota: null, paid: false, carry_forward: false, max_carry: null },
]);

export const STATUSES = ["pending", "approved", "rejected", "cancelled"];
/** Statuses that hold days (count against the balance, block other requests). */
export const HOLDING = ["pending", "approved"];
/** Longest calendar range one request may ask for. */
export const MAX_CALENDAR_DAYS = 92;

const num = (v) => (v === null || v === undefined ? null : Number(v));
const iso = (d) => (d ? new Date(d).toISOString() : null);
const day = (d) => (d instanceof Date ? d.toISOString().slice(0, 10) : String(d).slice(0, 10));
const pad = (n) => String(n).padStart(2, "0");
const isHalfStep = (n) => Number.isFinite(n) && Math.round(n * 2) === n * 2;

/** A settings row (or none) as the app gets it. */
export function settingsOut(row) {
  if (!row) return { ...DEFAULT_SETTINGS, weekly_off: [...DEFAULT_SETTINGS.weekly_off] };
  return {
    enabled: !!row.enabled,
    year_start_month: Number(row.year_start_month),
    weekly_off: (row.weekly_off || []).map(Number).sort((a, b) => a - b),
    half_day: !!row.half_day,
    backdate_days: Number(row.backdate_days),
    max_request_days: Number(row.max_request_days),
  };
}

/** A settings change from the admin, applied to [current]. Every field is optional. */
export function cleanSettings(body, current) {
  const b = body && typeof body === "object" ? body : {};
  const out = { ...current, weekly_off: [...current.weekly_off] };
  for (const k of ["enabled", "half_day"]) {
    if (b[k] === undefined) continue;
    if (typeof b[k] !== "boolean") return { ok: false, message: `${k} must be true or false` };
    out[k] = b[k];
  }
  const ints = { year_start_month: [1, 12], backdate_days: [0, 365], max_request_days: [1, 366] };
  for (const [k, [lo, hi]] of Object.entries(ints)) {
    if (b[k] === undefined) continue;
    if (!Number.isInteger(b[k]) || b[k] < lo || b[k] > hi) return { ok: false, message: `${k} must be a whole number from ${lo} to ${hi}` };
    out[k] = b[k];
  }
  if (b.weekly_off !== undefined) {
    const w = b.weekly_off;
    if (!Array.isArray(w) || w.some((x) => !Number.isInteger(x) || x < 0 || x > 6)) {
      return { ok: false, message: "weekly_off must be a list of days 0 (Sunday) to 6 (Saturday)" };
    }
    const set = [...new Set(w)].sort((a, c) => a - c);
    if (set.length > 6) return { ok: false, message: "At least one day of the week must be a working day" };
    out.weekly_off = set;
  }
  return { ok: true, value: out };
}

/** A leave type as the app gets it. */
export function typeOut(r) {
  return {
    id: Number(r.id),
    name: r.name,
    yearly_quota: num(r.yearly_quota),
    paid: !!r.paid,
    carry_forward: !!r.carry_forward,
    max_carry: num(r.max_carry),
    active: !!r.active,
  };
}

/**
 * A leave type from the admin. [partial] = an edit (only the fields sent).
 * yearly_quota / max_carry: null = no limit; otherwise 0–366 in half days.
 */
export function cleanType(body, partial = false) {
  const b = body && typeof body === "object" ? body : {};
  const out = {};
  if (b.name !== undefined || !partial) {
    if (typeof b.name !== "string") return { ok: false, message: "name is required" };
    const n = b.name.replace(/\s+/g, " ").trim();
    if (!n || n.length > 40) return { ok: false, message: "name must be 1–40 characters" };
    out.name = n;
  }
  for (const k of ["yearly_quota", "max_carry"]) {
    if (b[k] === undefined) {
      if (!partial) out[k] = null;
      continue;
    }
    if (b[k] !== null && (typeof b[k] !== "number" || !isHalfStep(b[k]) || b[k] < 0 || b[k] > 366)) {
      return { ok: false, message: `${k} must be empty (no limit) or 0–366 days, in half days` };
    }
    out[k] = b[k];
  }
  const bools = { paid: true, carry_forward: false, active: true };
  for (const [k, def] of Object.entries(bools)) {
    if (b[k] === undefined) {
      if (!partial) out[k] = def;
      continue;
    }
    if (typeof b[k] !== "boolean") return { ok: false, message: `${k} must be true or false` };
    out[k] = b[k];
  }
  if (partial && !Object.keys(out).length) return { ok: false, message: "Nothing to change" };
  return { ok: true, value: out };
}

/** A holiday from the admin. */
export function cleanHoliday(body) {
  const b = body && typeof body === "object" ? body : {};
  if (!isIsoDate(b.date)) return { ok: false, message: "date must be YYYY-MM-DD" };
  if (typeof b.name !== "string") return { ok: false, message: "name is required" };
  const n = b.name.replace(/\s+/g, " ").trim();
  if (!n || n.length > 60) return { ok: false, message: "name must be 1–60 characters" };
  return { ok: true, value: { date: b.date, name: n } };
}

/** The leave year holding [date]: { from, to, label } ("2026-27", or "2026" from January). */
export function leaveYear(date, startMonth) {
  const y = Number(date.slice(0, 4));
  const m = Number(date.slice(5, 7));
  const start = m >= startMonth ? y : y - 1;
  const from = `${start}-${pad(startMonth)}-01`;
  const to = addDays(`${start + 1}-${pad(startMonth)}-01`, -1);
  return { from, to, label: startMonth === 1 ? String(start) : `${start}-${String(start + 1).slice(2)}` };
}

const weekday = (d) => new Date(`${d}T00:00:00Z`).getUTCDay();

/** What a date is for the account: "holiday" | "weekly_off" | "working". */
export function dayKind(date, settings, holidays) {
  if (holidays.has(date)) return "holiday";
  if (settings.weekly_off.includes(weekday(date))) return "weekly_off";
  return "working";
}

/**
 * Working days of a request: weekly off and holidays left out, a half day
 * is 0.5. [holidays]: Set of "YYYY-MM-DD".
 */
export function requestDays({ from, to, half_day }, settings, holidays) {
  if (half_day) {
    const k = dayKind(from, settings, holidays);
    if (k !== "working") return { ok: false, message: `${from} is a ${k === "holiday" ? "holiday" : "weekly off"}` };
    return { ok: true, days: 0.5 };
  }
  let n = 0;
  for (let d = from; d <= to; d = addDays(d, 1)) if (dayKind(d, settings, holidays) === "working") n += 1;
  if (!n) return { ok: false, message: "These dates are all weekly off or holidays" };
  return { ok: true, days: n };
}

/** A leave request from a team member. [today]: India date. */
export function cleanRequest(body, settings, today) {
  const b = body && typeof body === "object" ? body : {};
  const typeId = b.type_id;
  if (!Number.isInteger(typeId) || typeId <= 0) return { ok: false, message: "Choose a leave type" };
  const from = b.from;
  const to = b.to === undefined || b.to === null || b.to === "" ? from : b.to;
  if (!isIsoDate(from) || !isIsoDate(to)) return { ok: false, message: "Dates must be YYYY-MM-DD" };
  if (from > to) return { ok: false, message: "From must be on or before To" };
  const half = b.half_day === undefined || b.half_day === null || b.half_day === "" ? null : b.half_day;
  if (half !== null) {
    if (!settings.half_day) return { ok: false, message: "Half-day leave is not allowed" };
    if (half !== "first" && half !== "second") return { ok: false, message: "half_day must be first or second" };
    if (from !== to) return { ok: false, message: "A half day is one date" };
  }
  if (daysBetween(from, to) > settings.max_request_days) {
    return { ok: false, message: `One request can cover at most ${settings.max_request_days} days` };
  }
  if (from < addDays(today, -settings.backdate_days)) {
    return {
      ok: false,
      message: settings.backdate_days
        ? `Leave can start at most ${settings.backdate_days} days back`
        : "Leave cannot start before today",
    };
  }
  const yf = leaveYear(from, settings.year_start_month);
  if (to > yf.to) return { ok: false, message: `Apply separately for each leave year (this one ends ${yf.to})` };
  const reason = cleanNote(b.reason);
  if (!reason.ok) return { ok: false, message: reason.message.replace("note", "reason") };
  const key = cleanKey(b.idempotency_key);
  if (!key.ok) return { ok: false, message: key.message };
  return { ok: true, value: { type_id: typeId, from, to, half_day: half, reason: reason.value, key: key.value } };
}

/** Do two requests take the same time? Two half days of one date only when the same half. */
export function overlaps(a, b) {
  if (a.from > b.to || b.from > a.to) return false;
  if (a.half_day && b.half_day && a.from === b.from && a.half_day !== b.half_day) return false;
  return true;
}

/** A request row as the app gets it. */
export function requestOut(r) {
  return {
    id: Number(r.id),
    user_id: Number(r.user_id),
    username: r.username ?? undefined,
    type_id: Number(r.leave_type_id),
    type_name: r.type_name ?? null,
    from: day(r.from_date),
    to: day(r.to_date),
    half_day: r.half_day ?? null,
    days: Number(r.days),
    reason: r.reason ?? null,
    status: r.status,
    decided_by: r.decided_by == null ? null : Number(r.decided_by),
    decided_at: iso(r.decided_at),
    decision_note: r.decision_note ?? null,
    created_at: iso(r.created_at),
  };
}

const r1 = (n) => Math.round(n * 10) / 10;

/**
 * Balances of one person for the leave year starting [yearFrom].
 * [requests]: their pending + approved requests (any year; a request
 * belongs to the year of its From date).
 *   entitled  = quota + carried (carried: what was left of last year,
 *               capped at max_carry, when the type carries forward;
 *               nothing before the year the type was added)
 *   used      = approved days this year; pending = waiting for the admin
 *   available = entitled − used − pending (null when there is no limit)
 */
export function balances(types, requests, settings, yearFrom) {
  const sm = settings.year_start_month;
  const usedIn = (typeId, yf, statuses) =>
    requests
      .filter((r) => Number(r.leave_type_id) === typeId && statuses.includes(r.status))
      .filter((r) => leaveYear(day(r.from_date), sm).from === yf)
      .reduce((a, r) => a + Number(r.days), 0);
  const prevYear = (yf) => leaveYear(addDays(yf, -1), sm).from;

  return types
    .filter((t) => t.active || requests.some((r) => Number(r.leave_type_id) === Number(t.id)))
    .map((raw) => {
      const t = typeOut(raw);
      const firstYear = leaveYear(day(raw.created_at || yearFrom), sm).from;
      const entitled = (yf) => {
        if (t.yearly_quota === null) return null;
        if (yf < firstYear) return 0;
        return t.yearly_quota + carried(yf);
      };
      const carried = (yf) => {
        if (!t.carry_forward || t.yearly_quota === null || yf <= firstYear) return 0;
        const py = prevYear(yf);
        const left = Math.max(0, entitled(py) - usedIn(t.id, py, ["approved"]));
        return t.max_carry === null ? left : Math.min(left, t.max_carry);
      };
      const used = usedIn(t.id, yearFrom, ["approved"]);
      const pending = usedIn(t.id, yearFrom, ["pending"]);
      const ent = entitled(yearFrom);
      return {
        type_id: t.id,
        name: t.name,
        paid: t.paid,
        active: t.active,
        quota: t.yearly_quota,
        carried: ent === null ? 0 : r1(carried(yearFrom)),
        entitled: ent === null ? null : r1(ent),
        used: r1(used),
        pending: r1(pending),
        available: ent === null ? null : r1(ent - used - pending),
      };
    });
}

/** The last date of [date]'s month. */
export function monthEnd(date) {
  const y = Number(date.slice(0, 4));
  const m = Number(date.slice(5, 7));
  return addDays(m === 12 ? `${y + 1}-01-01` : `${y}-${pad(m + 1)}-01`, -1);
}

/** From / To of a calendar request (defaults: this month). */
export function calendarRange(q, today) {
  const from = q?.from === undefined || q?.from === "" ? `${today.slice(0, 7)}-01` : String(q.from);
  if (!isIsoDate(from)) return { ok: false, message: "Dates must be YYYY-MM-DD" };
  const to = q?.to === undefined || q?.to === "" ? monthEnd(from) : String(q.to);
  if (!isIsoDate(to)) return { ok: false, message: "Dates must be YYYY-MM-DD" };
  if (from > to) return { ok: false, message: "From must be on or before To" };
  if (daysBetween(from, to) > MAX_CALENDAR_DAYS) return { ok: false, message: `Choose at most ${MAX_CALENDAR_DAYS} days` };
  return { ok: true, from, to };
}
