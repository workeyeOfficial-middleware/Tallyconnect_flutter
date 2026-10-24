/* =========================================================
   ATTENDANCE RULES — who must check in (pure helpers, no database)

   The admin gives each team member a position (Sales Executive, Manager…)
   and lists the positions that do not check in (e.g. Manager, Director).
   Each member's rule: "auto" (by position — the default), "required" or
   "exempt" (the admin's choice for that person, whatever the position).
   Before the admin sets anything every team member checks in (as before).

   Range summary per member (admin): days present, hours, leave days,
   absent working days, first check-in / last check-out on average.
========================================================= */
import { addDays, minutesOf } from "./attendanceCore.js";
import { dayKind } from "./leaveCore.js";

export const RULES = ["auto", "required", "exempt"];
export const MAX_POSITION = 40;
export const MAX_EXEMPT = 20;

/** Suggested positions (the admin may type any). */
export const POSITION_SUGGESTIONS = Object.freeze([
  "Sales Executive",
  "Field Executive",
  "Accountant",
  "Manager",
  "Sales Manager",
  "Director",
  "Owner",
]);

/** Exempt positions before the admin chooses (none: everyone checks in). */
export const DEFAULT_EXEMPT = Object.freeze([]);

const keyOf = (s) => String(s ?? "").trim().replace(/\s+/g, " ").toLowerCase();

/** A position from the admin: one line, ≤ 40 characters; null clears it. */
export function cleanPosition(v) {
  if (v === null || v === undefined) return { ok: true, value: null };
  if (typeof v !== "string") return { ok: false, message: "Position must be text" };
  // eslint-disable-next-line no-control-regex
  const s = v.replace(/[\u0000-\u001F\u007F]+/g, " ").replace(/\s+/g, " ").trim();
  if (s.length > MAX_POSITION) return { ok: false, message: `Position: at most ${MAX_POSITION} characters` };
  return { ok: true, value: s || null };
}

/** The exempt positions list: distinct (case ignored), ≤ 20, each a position. */
export function cleanExempt(v) {
  if (!Array.isArray(v)) return { ok: false, message: "exempt_positions must be a list" };
  const out = [];
  const seen = new Set();
  for (const x of v) {
    const p = cleanPosition(x);
    if (!p.ok) return p;
    if (!p.value || seen.has(keyOf(p.value))) continue;
    seen.add(keyOf(p.value));
    out.push(p.value);
  }
  if (out.length > MAX_EXEMPT) return { ok: false, message: `At most ${MAX_EXEMPT} positions` };
  return { ok: true, value: out };
}

/**
 * Must [member] ({position, rule}) check in? → {required, reason}:
 * reason "rule" (the admin's choice for that person), "position" (an
 * exempt position) or "default" (everyone else checks in).
 */
export function checkInRule(member, exempt) {
  const rule = RULES.includes(member?.rule) ? member.rule : "auto";
  if (rule === "required") return { required: true, reason: "rule" };
  if (rule === "exempt") return { required: false, reason: "rule" };
  const pos = keyOf(member?.position);
  if (pos && (exempt || []).some((x) => keyOf(x) === pos)) return { required: false, reason: "position" };
  return { required: true, reason: "default" };
}

const istTime = (iso) => {
  if (!iso) return null;
  const t = new Date(new Date(iso).getTime() + 330 * 60000);
  return t.getUTCHours() * 60 + t.getUTCMinutes();
};
const hhmm = (m) => (m === null ? null : `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(Math.round(m % 60)).padStart(2, "0")}`);

/**
 * One member's [from]…[to] (dates up to [today] count; later ones are
 * ahead): sessions, approved leave, the account's leave settings and
 * holidays (Set of dates).
 */
export function memberSummary({ from, to, today, now, sessions, leaves, settings, holidays }) {
  const last = to < today ? to : today;
  const byDay = new Map();
  for (const s of sessions) {
    const d = String(s.work_date).slice(0, 10);
    if (!byDay.has(d)) byDay.set(d, []);
    byDay.get(d).push(s);
  }
  // Leave per date: 1 (full day) or 0.5 (half day), working days only.
  const leaveOn = new Map();
  for (const r of leaves) {
    for (let d = r.from > from ? r.from : from; d <= r.to && d <= to; d = addDays(d, 1)) {
      if (dayKind(d, settings, holidays) !== "working") continue;
      leaveOn.set(d, Math.min(1, (leaveOn.get(d) || 0) + (r.half_day ? 0.5 : 1)));
    }
  }
  let present = 0;
  let minutes = 0;
  let working = 0;
  let absent = 0;
  let leaveDays = 0;
  let holidaysN = 0;
  let weeklyOff = 0;
  const ins = [];
  const outs = [];
  for (let d = from; d <= last; d = addDays(d, 1)) {
    const kind = dayKind(d, settings, holidays);
    if (kind === "holiday") holidaysN += 1;
    if (kind === "weekly_off") weeklyOff += 1;
    if (kind === "working") working += 1;
    const ses = (byDay.get(d) || []).sort((a, b) => new Date(a.check_in_at) - new Date(b.check_in_at));
    const lv = leaveOn.get(d) || 0;
    leaveDays += lv;
    if (ses.length) {
      present += 1;
      minutes += ses.reduce((a, s) => a + minutesOf(s, now), 0);
      ins.push(istTime(ses[0].check_in_at));
      const closed = ses.filter((s) => s.check_out_at);
      if (closed.length && closed.length === ses.length) outs.push(istTime(closed[closed.length - 1].check_out_at));
    } else if (kind === "working" && lv < 1 && d < today) {
      // A working day gone by with no check-in and no full day of leave.
      absent += 1;
    }
  }
  const avg = (a) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : null);
  return {
    present_days: present,
    working_days: working,
    leave_days: Math.round(leaveDays * 10) / 10,
    absent_days: absent,
    holidays: holidaysN,
    weekly_off: weeklyOff,
    total_minutes: minutes,
    avg_minutes: present ? Math.round(minutes / present) : 0,
    avg_in: hhmm(avg(ins) === null ? null : Math.round(avg(ins))),
    avg_out: hhmm(avg(outs) === null ? null : Math.round(avg(outs))),
  };
}
