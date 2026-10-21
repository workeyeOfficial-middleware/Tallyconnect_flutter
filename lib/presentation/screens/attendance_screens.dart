// Sales team check-in / check-out: the member's own day and history, the
// admin's team view (who is active, idle, checked out or not checked in)
// and one person's history. Times come from the server.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/design/tc_fields.dart';
import '../../core/design/tc_icons.dart';
import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';
import '../../core/utils/format.dart';
import '../../data/models/models.dart';
import '../widgets/common.dart';
import 'cashflow_screens.dart' show FromToBar;
import 'leave_screens.dart' show leaveDates, leaveTodayNote;

Color attColor(TcPalette p, AttStatus s) => switch (s) {
  AttStatus.active => p.pos,
  AttStatus.idle => p.warn,
  AttStatus.checkedOut => p.acc,
  AttStatus.absent => p.ink3,
};

String _t(DateTime? d) => d == null ? '—' : clock(d);

/// Home top bar (before Feedback): the profile — a dot while checked in.
/// Opens the profile sheet with Check in / Check out for team members.
class ProfileButton extends ConsumerWidget {
  const ProfileButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    // Team members only (the admin's header has no profile button).
    if (c.isAdmin) return const SizedBox.shrink();
    return CBtn(
      'person',
      key: const ValueKey<String>('profileBtn'),
      size: 38, // the Home header's action size (kHomeActionSize)
      iconSize: IcSize.s,
      dot: c.attCheckedIn,
      onTap: c.openProfile,
    );
  }
}

/// The profile sheet: who is signed in; for a team member today's check-in
/// with Check in / Check out and their attendance; for the admin the team's
/// attendance.
class ProfileSheet extends ConsumerWidget {
  const ProfileSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final String name = c.repo.profile?.username ?? c.repo.user?.username ?? '';
    final String email = c.repo.profile?.email ?? c.repo.user?.email ?? '';
    final bool member = !c.isAdmin && c.repo.isRemote && !c.demo;
    final AttMe? me = c.attMe;
    final AttSession? open = me?.open;
    void go(VoidCallback f) {
      c.closeOv();
      f();
    }

    return Sheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Av(initials(name.isEmpty ? email : name), size: 50, accent: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      name.isEmpty ? 'Profile' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: rtStyle(context, 18),
                    ),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: rsStyle(context),
                    ),
                    Text(
                      c.isAdmin ? 'Admin' : 'Team member',
                      style: ts(13, w: w700, c: p.acc),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (member) ...<Widget>[
            Glass(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (c.attError != null)
                    Text(
                      c.attError!,
                      key: const ValueKey<String>('profileAttError'),
                      style: ts(14, c: p.ink2),
                    )
                  else if (me == null)
                    Text('Loading check-in…', style: ts(14, c: p.ink3))
                  else if (!me.enabled)
                    Text(
                      'Check-in is not available for this login.',
                      style: ts(14, c: p.ink2),
                    )
                  else ...<Widget>[
                    Row(
                      children: <Widget>[
                        _Dot(attColor(p, me.status)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            open != null
                                ? 'Checked in since ${_t(open.checkIn)}'
                                : (me.sessions.isEmpty
                                      ? 'Not checked in today'
                                      : 'Checked out'),
                            key: const ValueKey<String>('profileAttState'),
                            style: rtStyle(context, 16),
                          ),
                        ),
                        Text(
                          hoursMinutes(me.totalMinutes),
                          style: ts(14, w: w700, c: p.ink2),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (open == null)
                      Btn(
                        key: const ValueKey<String>('profileCheckIn'),
                        label: c.attBusy ? 'Checking in…' : 'Check in',
                        icon: 'in',
                        enabled: !c.attBusy,
                        onTap: c.checkIn,
                      )
                    else
                      Btn(
                        key: const ValueKey<String>('profileCheckOut'),
                        label: 'Check out',
                        icon: 'out',
                        kind: BtnKind.g,
                        enabled: !c.attBusy,
                        // The note sheet replaces this one.
                        onTap: c.openCheckOut,
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          GlassList(
            children: <Widget>[
              if (member)
                RowX(
                  key: const ValueKey<String>('profileMyAtt'),
                  minHeight: 56,
                  onTap: () => go(c.openAttendance),
                  children: <Widget>[
                    const Expanded(
                      child: RTx('My attendance', 'Check-ins day by day'),
                    ),
                    chevR(),
                  ],
                ),
              if (member && c.leaveOn)
                RowX(
                  key: const ValueKey<String>('profileMyLeave'),
                  minHeight: 56,
                  onTap: () => go(c.openLeave),
                  children: <Widget>[
                    Expanded(
                      child: RTx(
                        'My leave',
                        leaveTodayNote(c.leaveMe) ?? 'Balance and requests',
                      ),
                    ),
                    chevR(),
                  ],
                ),
              if (c.isAdmin && c.repo.isRemote && !c.demo)
                RowX(
                  key: const ValueKey<String>('profileLeaveReqs'),
                  minHeight: 56,
                  onTap: () => go(c.openLeaveRequests),
                  children: <Widget>[
                    Expanded(
                      child: RTx(
                        'Leave requests',
                        c.leavePending == 0
                            ? 'Nothing waiting'
                            : '${c.leavePending} waiting for approval',
                      ),
                    ),
                    chevR(),
                  ],
                ),
              if (c.isAdmin && c.repo.isRemote && !c.demo)
                RowX(
                  key: const ValueKey<String>('profileTeamAtt'),
                  minHeight: 56,
                  onTap: () => go(c.openAttTeam),
                  children: <Widget>[
                    const Expanded(
                      child: RTx('Team attendance', 'Who is in today'),
                    ),
                    chevR(),
                  ],
                ),
              RowX(
                minHeight: 56,
                onTap: () => go(
                  () =>
                      c.go('settings', <String, Object?>{'setTab': 'profile'}),
                ),
                children: <Widget>[
                  const Expanded(child: RTx('Profile and settings', null)),
                  chevR(),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Team page (admin): today's check-ins at a glance; opens Team attendance.
class TeamAttCard extends ConsumerWidget {
  const TeamAttCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    if (!c.isAdmin || !c.repo.isRemote || c.demo) {
      return const SizedBox.shrink();
    }
    final AttTeam? t = c.attTeam;
    final bool today =
        t != null && t.date != null && ymd(t.date!) == ymd(c.today);
    final List<(String, int, Color)> stats = <(String, int, Color)>[
      ('Active', today ? t.count(AttStatus.active) : 0, p.pos),
      ('Idle', today ? t.count(AttStatus.idle) : 0, p.warn),
      ('Out', today ? t.count(AttStatus.checkedOut) : 0, p.acc),
      ('Not in', today ? t.count(AttStatus.absent) : 0, p.ink3),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Tap(
        key: const ValueKey<String>('teamAttCard'),
        onTap: c.openAttTeam,
        child: Glass(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Ico('clock', size: IcoSize.xs, color: p.acc),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Today's check-ins",
                      style: rtStyle(context, 16.5),
                    ),
                  ),
                  chevR(),
                ],
              ),
              const SizedBox(height: 10),
              if (c.attTeamError != null && !today)
                Text(c.attTeamError!, style: ts(13.5, c: p.ink2))
              else if (!today)
                Text(
                  c.attTeamBusy ? 'Loading…' : 'Tap to see who is in.',
                  style: ts(13.5, c: p.ink3),
                )
              else
                Row(
                  children: <Widget>[
                    for (final (String, int, Color) s in stats)
                      Expanded(
                        child: Column(
                          children: <Widget>[
                            Text(
                              '${s.$2}',
                              style: ts(19, w: w800, c: s.$3),
                            ),
                            Text(
                              s.$1,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ts(12.5, w: w600, c: p.ink3),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Team page row (admin): the member's check-in today.
class AttStatusLine extends ConsumerWidget {
  const AttStatusLine(this.userId, {super.key});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final AttMember? m = c.attOf(userId);
    final LeaveRequest? leave = c.leaveTodayOf(userId);
    // On approved leave and not checked in: the leave, not "Not checked in".
    if (leave != null && (m == null || m.status == AttStatus.absent)) {
      return Padding(
        key: ValueKey<String>('teamLeave-$userId'),
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: <Widget>[
            _Dot(p.navy2),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'On leave · ${leave.typeName}${leave.halfLabel == null ? '' : ' (${leave.halfLabel!.toLowerCase()})'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ts(12.5, w: w700, c: p.navy2),
              ),
            ),
          ],
        ),
      );
    }
    if (m == null) return const SizedBox.shrink();
    final String when = switch (m.status) {
      AttStatus.active || AttStatus.idle =>
        ' · in ${_t(m.sessions.where((AttSession s) => s.open).firstOrNull?.checkIn ?? m.firstIn)}',
      AttStatus.checkedOut => ' · ${_t(m.firstIn)} – ${_t(m.lastOut)}',
      AttStatus.absent => '',
    };
    return Padding(
      key: ValueKey<String>('teamAtt-$userId'),
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: <Widget>[
          _Dot(attColor(p, m.status)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${m.status.label}$when',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ts(12.5, w: w700, c: attColor(p, m.status)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// One session: in – out (or "now"), its time, notes.
class _SessionRow extends StatelessWidget {
  const _SessionRow(this.s);
  final AttSession s;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final String out = s.open ? 'now' : _t(s.checkOut);
    final List<String> notes = <String>[
      if (s.inNote != null) 'In: ${s.inNote}',
      if (s.outNote != null) 'Out: ${s.outNote}',
      if (s.auto) 'Check-out was missed — closed at 11:59 PM',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${_t(s.checkIn)} – $out',
                  style: ts(14.5, w: w700, c: p.ink),
                ),
                for (final String n in notes)
                  Text(
                    n,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: ts(
                      12.5,
                      c: s.auto && n == notes.last ? p.warn : p.ink3,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(hoursMinutes(s.minutes), style: amtStyle(context, size: 14)),
        ],
      ),
    );
  }
}

/// A day of a history: date, first in / last out, total, its sessions.
class _DayCard extends StatelessWidget {
  const _DayCard(this.d);
  final AttDay d;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Glass(
        key: ValueKey<String>('attDay-${d.date == null ? '' : ymd(d.date!)}'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    d.date == null ? '—' : dmy(d.date),
                    style: rtStyle(context, 15.5),
                  ),
                ),
                Text(
                  hoursMinutes(d.totalMinutes),
                  style: ts(15, w: w800, c: p.acc),
                ),
              ],
            ),
            Text(
              'In ${_t(d.firstIn)} · Out ${d.lastOut == null ? '—' : _t(d.lastOut)}'
              '${d.autoClosed ? ' · auto check-out' : ''}',
              style: ts(12.5, c: d.autoClosed ? p.warn : p.ink3),
            ),
            const SizedBox(height: 4),
            for (final AttSession s in d.sessions) _SessionRow(s),
          ],
        ),
      ),
    );
  }
}

/// A day without check-ins that was approved leave or a holiday.
class _OffDayCard extends StatelessWidget {
  const _OffDayCard(this.date, this.title, this.sub);
  final DateTime date;
  final String title, sub;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Glass(
        key: ValueKey<String>('attOff-${ymd(date)}'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(dmy(date), style: rtStyle(context, 15.5)),
                  Text(sub, style: ts(12.5, c: p.ink3)),
                ],
              ),
            ),
            Bdg(title, kind: BadgeKind.info),
          ],
        ),
      ),
    );
  }
}

/// Days of [from]…[to] (newest first) with no check-in that were approved
/// leave or a holiday (weekly off is not listed).
List<(DateTime, _OffDayCard)> _offDays(
  AppController c,
  DateTime from,
  DateTime to,
  Set<String> worked,
) {
  final LeaveCalendar? cal = c.attLeaveCal;
  if (cal == null) return const <(DateTime, _OffDayCard)>[];
  // The admin's calendar holds the team; this screen is one person.
  final String? who = c.screen == 'attMember' ? c.attMemberId : null;
  final List<(DateTime, _OffDayCard)> out = <(DateTime, _OffDayCard)>[];
  for (
    DateTime d = to;
    !d.isBefore(from);
    d = DateTime(d.year, d.month, d.day - 1)
  ) {
    if (worked.contains(ymd(d))) continue;
    final LeaveRequest? l = cal.leaveOn(d, userId: who);
    final LeaveHoliday? hol = cal.holidayOn(d);
    if (l != null) {
      out.add((
        d,
        _OffDayCard(
          d,
          'On leave',
          '${l.typeName}${l.halfLabel == null ? '' : ' · ${l.halfLabel}'} · ${leaveDates(l)}',
        ),
      ));
    } else if (hol != null) {
      out.add((d, _OffDayCard(d, 'Holiday', hol.name)));
    }
  }
  return out;
}

/// History list (shared by the member's and the admin's screens).
List<Widget> _history(AppController c, BuildContext context) {
  final (DateTime from, DateTime to) = c.attRange;
  final AttHistory? h = c.attHist;
  final Set<String> worked = <String>{
    for (final AttDay d in h?.days ?? const <AttDay>[])
      if (d.date != null) ymd(d.date!),
  };
  final List<(DateTime, _OffDayCard)> off = _offDays(c, from, to, worked);
  // Worked days and leave / holidays together, newest first.
  final List<(DateTime, Widget)> rows = <(DateTime, Widget)>[
    for (final AttDay d in h?.days ?? const <AttDay>[])
      if (d.date != null) (d.date!, _DayCard(d)),
    ...off,
  ]..sort(((DateTime, Widget) a, (DateTime, Widget) b) => b.$1.compareTo(a.$1));
  final int leaveDaysShown = off
      .where(((DateTime, _OffDayCard) x) => x.$2.title == 'On leave')
      .length;
  return <Widget>[
    FromToBar(from: from, to: to, onTap: c.attHistBusy ? null : c.openAttRange),
    if (c.attHistError != null)
      InfoBox(c.attHistError!, icon: 'info')
    else if (h == null)
      EmptyBox(c.attHistBusy ? 'Loading…' : 'No history yet.')
    else ...<Widget>[
      if (c.attHistBusy)
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: LinearProgressIndicator(minHeight: 2),
        ),
      if (rows.isEmpty)
        const EmptyBox('No check-ins in these dates.')
      else ...<Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            '${h.days.length} ${h.days.length == 1 ? 'day' : 'days'} · '
            '${hoursMinutes(h.totalMinutes)} in all'
            '${leaveDaysShown == 0 ? '' : ' · $leaveDaysShown on leave'}',
            key: const ValueKey<String>('attHistTotal'),
            style: ts(13.5, w: w700, c: Tc.of(context).ink2),
          ),
        ),
        for (final (DateTime, Widget) r in rows) r.$2,
      ],
    ],
  ];
}

/// The member's own check-in screen.
class AttendanceScreen extends ConsumerWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final AttMe? me = c.attMe;
    final AttSession? open = me?.open;
    return Scr(
      children: <Widget>[
        BackNav(
          actions: <Widget>[
            CBtn(
              'sync',
              onTap: c.attLoading
                  ? null
                  : () {
                      c.loadAttendance();
                      c.loadAttHistory();
                    },
            ),
          ],
        ),
        H1('Check-in', afterNav: true),
        Sub(<String>[c.companyName, dmy(c.today)].join(' · ')),
        if (c.attError != null) ...<Widget>[
          InfoBox(c.attError!, icon: 'info'),
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 14),
            child: Btn(
              label: 'Try again',
              kind: BtnKind.g,
              onTap: c.loadAttendance,
            ),
          ),
        ] else if (me == null)
          EmptyBox(c.attLoading ? 'Loading…' : 'Not loaded yet.')
        else if (!me.enabled)
          InfoBox(
            me.isAdmin
                ? 'Check-in is for your team members. See who is in under '
                      'Team attendance.'
                : 'Check-in is not available for this login.',
            icon: 'info',
          )
        else ...<Widget>[
          // On leave / holiday / weekly off today: check-in still works.
          if (leaveTodayNote(c.leaveMe) case final String note)
            InfoBox(note, icon: 'calendar'),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Glass(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      _Dot(attColor(p, me.status)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          open != null
                              ? 'Checked in since ${_t(open.checkIn)}'
                              : (me.sessions.isEmpty
                                    ? 'Not checked in today'
                                    : 'Checked out'),
                          key: const ValueKey<String>('attState'),
                          style: rtStyle(context, 17),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Today: ${hoursMinutes(me.totalMinutes)}',
                    key: const ValueKey<String>('attToday'),
                    style: ts(14, c: p.ink2),
                  ),
                  const SizedBox(height: 14),
                  if (open == null)
                    Btn(
                      key: const ValueKey<String>('attCheckIn'),
                      label: c.attBusy ? 'Checking in…' : 'Check in',
                      icon: 'in',
                      enabled: !c.attBusy,
                      onTap: c.checkIn,
                    )
                  else
                    Btn(
                      key: const ValueKey<String>('attCheckOut'),
                      label: 'Check out',
                      icon: 'out',
                      kind: BtnKind.g,
                      enabled: !c.attBusy,
                      onTap: c.openCheckOut,
                    ),
                ],
              ),
            ),
          ),
          if (me.sessions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Glass(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text('Today', style: rtStyle(context, 15.5)),
                    for (final AttSession s in me.sessions) _SessionRow(s),
                  ],
                ),
              ),
            ),
        ],
        if (me != null && (me.enabled || me.sessions.isNotEmpty)) ...<Widget>[
          const Sec('History', margin: EdgeInsets.fromLTRB(8, 4, 8, 8)),
          ..._history(c, context),
        ],
      ],
    );
  }
}

/// Admin: the sales team's day.
class AttTeamScreen extends ConsumerWidget {
  const AttTeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final AttTeam? t = c.attTeam;
    final DateTime d = c.attDay;
    final bool isToday = ymd(d) == ymd(c.today);
    final List<(String, String, int, Color)> stats =
        <(String, String, int, Color)>[
          ('active', 'Active', t?.count(AttStatus.active) ?? 0, p.pos),
          ('idle', 'Idle', t?.count(AttStatus.idle) ?? 0, p.warn),
          (
            'checked_out',
            'Checked out',
            t?.count(AttStatus.checkedOut) ?? 0,
            p.acc,
          ),
          ('absent', 'Not in', t?.count(AttStatus.absent) ?? 0, p.ink3),
        ];
    final List<AttMember> rows = c.attTeamRows;
    return Scr(
      children: <Widget>[
        BackNav(
          actions: <Widget>[
            CBtn('sync', onTap: c.attTeamBusy ? null : c.loadAttTeam),
          ],
        ),
        H1('Team attendance', afterNav: true),
        Sub(
          <String>[
            if ((t?.company ?? '').isNotEmpty) t!.company else c.companyName,
            if (t != null) '${t.checkedIn} of ${t.members.length} checked in',
          ].join(' · '),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Glass(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              children: <Widget>[
                CBtn(
                  'chevL',
                  key: const ValueKey<String>('attPrev'),
                  small: true,
                  onTap: () => c.shiftAttDay(-1),
                ),
                Expanded(
                  child: Text(
                    isToday ? 'Today · ${dmy(d)}' : dmy(d),
                    key: const ValueKey<String>('attDate'),
                    textAlign: TextAlign.center,
                    style: rtStyle(context, 15.5),
                  ),
                ),
                CBtn(
                  'chevR',
                  key: const ValueKey<String>('attNext'),
                  small: true,
                  onTap: isToday ? null : () => c.shiftAttDay(1),
                ),
              ],
            ),
          ),
        ),
        Grid(
          cols: 2,
          gap: 10,
          children: <Widget>[
            for (final (String, String, int, Color) s in stats)
              Tap(
                key: ValueKey<String>('attStat-${s.$1}'),
                onTap: () =>
                    c.setAttTeamFilter(c.attTeamFilter == s.$1 ? 'all' : s.$1),
                child: Glass(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(
                    children: <Widget>[
                      _Dot(s.$4),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ts(
                            13.5,
                            w: c.attTeamFilter == s.$1 ? w800 : w600,
                            c: p.ink2,
                          ),
                        ),
                      ),
                      Text(
                        '${s.$3}',
                        style: ts(19, w: w800, c: p.ink),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (c.attTeamError != null)
          InfoBox(c.attTeamError!, icon: 'info')
        else if (t == null)
          EmptyBox(c.attTeamBusy ? 'Loading…' : 'Not loaded yet.')
        else ...<Widget>[
          if (c.attTeamBusy)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (t.members.isEmpty)
            const InfoBox(
              'No team members yet. Add people on the Sales Team page; they '
              'check in from their profile on Home.',
              icon: 'info',
            )
          else if (rows.isEmpty)
            const EmptyBox('No one in this list.')
          else
            GlassList(
              margin: const EdgeInsets.only(bottom: 12),
              children: <Widget>[for (final AttMember m in rows) _MemberRow(m)],
            ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Active: checked in and the app was open in the last 15 '
            'minutes. Idle: checked in, app not open since. Check-ins left '
            'open close at 11:59 PM.',
            style: ts(12.5, h: 1.4, c: p.ink3),
          ),
        ),
      ],
    );
  }
}

class _MemberRow extends ConsumerWidget {
  const _MemberRow(this.m);
  final AttMember m;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final String name = c.attName(m.userId, m.username);
    final String line = switch (m.status) {
      AttStatus.active || AttStatus.idle =>
        'In since ${_t(m.sessions.where((AttSession s) => s.open).firstOrNull?.checkIn ?? m.firstIn)}'
            '${m.status == AttStatus.idle && m.lastSeen != null ? ' · seen ${_t(m.lastSeen)}' : ''}',
      AttStatus.checkedOut => 'In ${_t(m.firstIn)} · Out ${_t(m.lastOut)}',
      AttStatus.absent => 'Not checked in',
    };
    // Approved leave on the day shown (today only: the Team page loads it).
    final LeaveRequest? leave = ymd(c.attDay) == ymd(c.today)
        ? c.leaveTodayOf(m.userId)
        : null;
    return RowX(
      key: ValueKey<String>('attMember-${m.userId}'),
      onTap: () => c.openAttMember(m),
      children: <Widget>[
        Av(initials(name)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ts(15.5, w: w700, c: p.ink),
              ),
              Row(
                children: <Widget>[
                  _Dot(attColor(p, m.status)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      m.status.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ts(12.5, w: w700, c: attColor(p, m.status)),
                    ),
                  ),
                ],
              ),
              if (leave != null)
                Text(
                  'On leave · ${leave.typeName}',
                  key: ValueKey<String>('attOnLeave-${m.userId}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ts(12.5, w: w700, c: p.navy2),
                ),
              Text(
                '$line${m.autoClosed ? ' · auto check-out' : ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: ts(12.5, c: p.ink3),
              ),
            ],
          ),
        ),
        Text(
          m.totalMinutes == 0 ? '—' : hoursMinutes(m.totalMinutes),
          style: amtStyle(context, size: 14),
        ),
      ],
    );
  }
}

/// Admin: one person's history.
class AttMemberScreen extends ConsumerWidget {
  const AttMemberScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    return Scr(
      children: <Widget>[
        BackNav(
          actions: <Widget>[
            CBtn('sync', onTap: c.attHistBusy ? null : c.loadAttHistory),
          ],
        ),
        H1(
          c.attMemberName.isEmpty ? 'Team member' : c.attMemberName,
          afterNav: true,
        ),
        const Sub('Attendance history'),
        GlassList(
          margin: const EdgeInsets.only(bottom: 12),
          children: <Widget>[
            RowX(
              key: const ValueKey<String>('attMemberLeave'),
              minHeight: 56,
              onTap: c.attMemberId == null
                  ? null
                  : () => c.openLeaveMember(c.attMemberId!, c.attMemberName),
              children: <Widget>[
                const Expanded(child: RTx('Leave', 'Balance and requests')),
                chevR(),
              ],
            ),
          ],
        ),
        ..._history(c, context),
      ],
    );
  }
}

/// The check-in popup: a team member who has not checked in today gets it
/// after login / opening the app. Check in here, or "Later" (not shown
/// again today; Check-in stays in the menu and the profile).
class CheckInPromptSheet extends ConsumerWidget {
  const CheckInPromptSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final String name = c.repo.profile?.username ?? c.repo.user?.username ?? '';
    return Sheet(
      child: Column(
        key: const ValueKey<String>('attPrompt'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Container(
              width: 64,
              height: 64,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: p.acc.withValues(alpha: .12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Ic('clock', size: IcSize.l, color: p.acc),
              ),
            ),
          ),
          Text(
            'Check in for today',
            textAlign: TextAlign.center,
            style: rtStyle(context, 20),
          ),
          const SizedBox(height: 6),
          Text(
            name.isEmpty
                ? 'You have not checked in yet today.'
                : 'Hi $name, you have not checked in yet today.',
            textAlign: TextAlign.center,
            style: ts(14.5, h: 1.35, c: p.ink2),
          ),
          if (c.attError != null) ...<Widget>[
            const SizedBox(height: 10),
            InfoBox(c.attError!, icon: 'info'),
          ],
          const SizedBox(height: 18),
          Btn(
            key: const ValueKey<String>('attPromptCheckIn'),
            label: c.attBusy ? 'Checking in…' : 'Check in',
            icon: 'in',
            enabled: !c.attBusy,
            onTap: c.checkIn,
          ),
          const SizedBox(height: 10),
          Btn(
            key: const ValueKey<String>('attPromptLater'),
            label: 'Later',
            kind: BtnKind.g,
            enabled: !c.attBusy,
            onTap: c.laterCheckIn,
          ),
        ],
      ),
    );
  }
}

/// Check out: optional note, confirm.
class CheckOutSheet extends ConsumerWidget {
  const CheckOutSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final AttSession? open = c.attMe?.open;
    return Sheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SheetHead(
            'Check out',
            sub: open == null
                ? null
                : 'Checked in at ${_t(open.checkIn)} · '
                      '${hoursMinutes(open.minutes)} so far',
          ),
          Fld(
            label: 'Note (optional)',
            child: Inp(
              key: const ValueKey<String>('attNote'),
              value: c.f('attNote'),
              onChanged: (String v) => c.setF('attNote', v),
              placeholder: 'e.g. Visited 4 customers',
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: Btn(label: 'Cancel', kind: BtnKind.g, onTap: c.closeOv),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Btn(
                  key: const ValueKey<String>('attCheckOutConfirm'),
                  label: c.attBusy ? 'Checking out…' : 'Check out',
                  icon: 'check',
                  enabled: !c.attBusy,
                  onTap: c.checkOut,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
