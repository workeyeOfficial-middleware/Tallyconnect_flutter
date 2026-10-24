/* =========================================================
   SALES TEAM ATTENDANCE — pure helpers (no database): India dates, session
   durations, a person's status for a day, request validation.
========================================================= */

/** Minutes without the app being seen before "Active" becomes "Idle". */
export const ACTIVE_MINUTES = 15;
/** Longest history range one request may ask for. */
export const MAX_HISTORY_DAYS = 92;
export const MAX_NOTE = 300;

const IST_MS = 330 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

/** The India (IST) date of [d]: "YYYY-MM-DD". */
export function istDate(d) {
  return new Date(new Date(d).getTime() + IST_MS).toISOString().slice(0, 10);
}

export const isIsoDate = (s) =>
  typeof s === "string" && /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(Date.parse(`${s}T00:00:00Z`)) &&
  new Date(`${s}T00:00:00Z`).toISOString().slice(0, 10) === s;

export function addDays(iso, n) {
  return new Date(Date.parse(`${iso}T00:00:00Z`) + n * DAY_MS).toISOString().slice(0, 10);
}

/** Days from [a] to [b], both included. */
export const daysBetween = (a, b) => Math.round((Date.parse(`${b}T00:00:00Z`) - Date.parse(`${a}T00:00:00Z`)) / DAY_MS) + 1;

/** A note: trimmed, one line, at most MAX_NOTE characters; empty → null. */
export function cleanNote(v) {
  if (v === undefined || v === null) return { ok: true, value: null };
  if (typeof v !== "string") return { ok: false, message: "note must be text" };
  const s = v.replace(/[\r\n\t]+/g, " ").replace(/\s{2,}/g, " ").trim();
  if (s.length > MAX_NOTE) return { ok: false, message: `note must be at most ${MAX_NOTE} characters` };
  return { ok: true, value: s || null };
}

/** An optional retry key from the app: letters, digits, - and _, ≤ 80. */
export function cleanKey(v) {
  if (v === undefined || v === null || v === "") return { ok: true, value: null };
  if (typeof v !== "string" || !/^[A-Za-z0-9_-]{8,80}$/.test(v)) {
    return { ok: false, message: "idempotency_key must be 8–80 letters, digits, - or _" };
  }
  return { ok: true, value: v };
}

/** From / To of a history request (defaults: the last 30 days to today). */
export function historyRange(q, today) {
  const to = q?.to === undefined || q?.to === "" ? today : String(q.to);
  const from = q?.from === undefined || q?.from === "" ? addDays(to, -29) : String(q.from);
  if (!isIsoDate(from) || !isIsoDate(to)) return { ok: false, message: "Dates must be YYYY-MM-DD" };
  if (from > to) return { ok: false, message: "From must be on or before To" };
  if (daysBetween(from, to) > MAX_HISTORY_DAYS) {
    return { ok: false, message: `Choose at most ${MAX_HISTORY_DAYS} days` };
  }
  return { ok: true, from, to };
}

const iso = (d) => (d ? new Date(d).toISOString() : null);

/** Whole minutes of a session (an open one counts up to [now]). */
export function minutesOf(s, now) {
  const end = s.check_out_at ? new Date(s.check_out_at) : new Date(now);
  return Math.max(0, Math.floor((end.getTime() - new Date(s.check_in_at).getTime()) / 60000));
}

/** A session as the app gets it. */
export function sessionOut(s, now) {
  return {
    id: Number(s.id),
    work_date: String(s.work_date).slice(0, 10),
    check_in_at: iso(s.check_in_at),
    check_out_at: iso(s.check_out_at),
    last_seen_at: iso(s.last_seen_at),
    in_note: s.in_note ?? null,
    out_note: s.out_note ?? null,
    closed_by: s.closed_by ?? null,
    open: !s.check_out_at,
    minutes: minutesOf(s, now),
  };
}

/**
 * One person's day from their sessions (oldest first):
 *   active      checked in, the app seen in the last ACTIVE_MINUTES
 *   idle        checked in, not seen for longer
 *   checked_out sessions today, none open
 *   absent      no session today
 */
export function dayStatus(sessions, now) {
  const list = [...sessions].sort((a, b) => new Date(a.check_in_at) - new Date(b.check_in_at));
  const open = list.find((s) => !s.check_out_at) || null;
  let status = "absent";
  if (open) {
    const seen = new Date(open.last_seen_at || open.check_in_at).getTime();
    status = new Date(now).getTime() - seen <= ACTIVE_MINUTES * 60000 ? "active" : "idle";
  } else if (list.length) {
    status = "checked_out";
  }
  const closed = list.filter((s) => s.check_out_at);
  return {
    status,
    first_in: list.length ? iso(list[0].check_in_at) : null,
    last_out: !open && closed.length ? iso(closed[closed.length - 1].check_out_at) : null,
    last_seen_at: open ? iso(open.last_seen_at) : null,
    total_minutes: list.reduce((a, s) => a + minutesOf(s, now), 0),
    auto_closed: list.some((s) => s.closed_by === "auto"),
    sessions: list.map((s) => sessionOut(s, now)),
  };
}

/** Sessions grouped by work date, newest day first, with day totals. */
export function historyDays(sessions, now) {
  const by = new Map();
  for (const s of sessions) {
    const d = String(s.work_date).slice(0, 10);
    if (!by.has(d)) by.set(d, []);
    by.get(d).push(s);
  }
  return [...by.keys()]
    .sort((a, b) => b.localeCompare(a))
    .map((d) => {
      const x = dayStatus(by.get(d), now);
      return {
        date: d,
        first_in: x.first_in,
        last_out: x.last_out,
        total_minutes: x.total_minutes,
        auto_closed: x.auto_closed,
        sessions: x.sessions,
      };
    });
}

/** Counts per status for the admin dashboard. */
export function statusCounts(members) {
  const c = { active: 0, idle: 0, checked_out: 0, absent: 0, exempt: 0, checked_in: 0, total: members.length };
  for (const m of members) {
    c[m.status] += 1;
    if (m.status === "active" || m.status === "idle") c.checked_in += 1;
  }
  return c;
}
