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
import '../widgets/report_loader.dart';
import 'cashflow_screens.dart' show FromToBar;
import 'leave_screens.dart' show leaveDates, leaveTodayNote;

Color attColor(TcPalette p, AttStatus s) => switch (s) {
  AttStatus.active => p.pos,
  AttStatus.idle => p.warn,
  AttStatus.checkedOut => p.acc,
  AttStatus.absent => p.ink3,
  AttStatus.exempt => p.navy2,
};

String _t(DateTime? d) => d == null ? '—' : clock(d);

/// Why this login does not check in.
String attOffText(AttMe me) {
  if (me.isAdmin) {
    return 'Check-in is for your team members. See who is in under '
        'Team attendance.';
  }
  if (me.exempt) {
    return 'You do not need to check in'
        '${me.position == null ? '' : ' as ${me.position}'}: your admin '
        'set check-in rules for your team.';
  }
  return 'Check-in is not available for this login.';
}

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
                      attOffText(me),
                      key: const ValueKey<String>('profileAttOff'),
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
  const TeamAttCard({super.key, this.list = 'teamCards'});

  /// The card list it is shown in (`teamCards` on Sales Team, `home`).
  final String list;

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
        onTap: () {
          if (c.guardTap(list, 'attToday')) c.openAttTeam();
        },
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
      AttStatus.absent || AttStatus.exempt => '',
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
  // Calendar: one month, every day coloured; tap a day for its details.
  if (c.attView == 'calendar') {
    return <Widget>[
      AttViewSeg(c: c),
      if (c.attHistError != null)
        InfoBox(c.attHistError!, icon: 'info')
      else ...<Widget>[
        if (c.attHistBusy)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        AttCalendar(c: c),
      ],
    ];
  }
  return <Widget>[
    AttViewSeg(c: c),
    FromToBar(from: from, to: to, onTap: c.attHistBusy ? null : c.openAttRange),
    if (c.attHistError != null)
      InfoBox(c.attHistError!, icon: 'info')
    else if (h == null)
      (c.attHistBusy
          ? const ReportLoader(text: 'Loading attendance…')
          : EmptyBox('No history yet.'))
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
          (c.attLoading
              ? const ReportLoader(text: 'Loading attendance…')
              : const EmptyBox('Not loaded yet.'))
        else if (!me.enabled)
          InfoBox(
            attOffText(me),
            key: const ValueKey<String>('attOff'),
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

/// Admin: the sales team's day — date chips (Today / Yesterday / any day),
/// status counts (tap to filter) and the members as cards, a table or a
/// board of columns by status.
class AttTeamScreen extends ConsumerWidget {
  const AttTeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final AttTeam? t = c.attTeam;
    final DateTime d = c.attDay;
    final DateTime today = DateTime(c.today.year, c.today.month, c.today.day);
    final bool isToday = ymd(d) == ymd(today);
    final bool isYesterday =
        ymd(d) == ymd(today.subtract(const Duration(days: 1)));
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
    final String view = c.attTeamView;
    final int exempt = t?.count(AttStatus.exempt) ?? 0;
    Future<void> pick() async {
      final DateTime? x = await showDatePicker(
        context: context,
        initialDate: d,
        firstDate: DateTime(today.year - 2),
        lastDate: today,
      );
      if (x != null) c.pickAttDay(x);
    }

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
            if (t != null)
              '${t.checkedIn} of ${t.members.length - exempt} checked in',
            if (exempt > 0) '$exempt not tracked',
          ].join(' · '),
        ),
        // The day: quick chips, any day, one day back / forward.
        Chips(
          margin: const EdgeInsets.only(bottom: 8),
          children: <Widget>[
            ChipBtn(
              'Today',
              key: const ValueKey<String>('attDayToday'),
              height: 38,
              fontSize: 13.5,
              on: isToday,
              onTap: () => c.pickAttDay(today),
            ),
            ChipBtn(
              'Yesterday',
              key: const ValueKey<String>('attDayYesterday'),
              height: 38,
              fontSize: 13.5,
              on: isYesterday,
              onTap: () =>
                  c.pickAttDay(today.subtract(const Duration(days: 1))),
            ),
            ChipBtn(
              isToday || isYesterday ? 'Pick a day' : dmy(d),
              key: const ValueKey<String>('attDayPick'),
              icon: 'calendar',
              height: 38,
              fontSize: 13.5,
              on: !isToday && !isYesterday,
              onTap: pick,
            ),
          ],
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
                  child: Column(
                    children: <Widget>[
                      Text(
                        kWeekdayNames[d.weekday - 1],
                        key: const ValueKey<String>('attWeekday'),
                        style: ts(12.5, w: w700, c: p.ink3),
                      ),
                      Text(
                        isToday ? 'Today · ${dmy(d)}' : dmy(d),
                        key: const ValueKey<String>('attDate'),
                        textAlign: TextAlign.center,
                        style: rtStyle(context, 15.5),
                      ),
                    ],
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
        Seg(
          key: const ValueKey<String>('attTeamView'),
          items: const <String>['Cards', 'Table', 'Board'],
          selected: switch (view) {
            'table' => 1,
            'board' => 2,
            _ => 0,
          },
          onPick: (int i) =>
              c.setAttTeamView(const <String>['cards', 'table', 'board'][i]),
        ),
        if (c.attTeamError != null)
          InfoBox(c.attTeamError!, icon: 'info')
        else if (t == null)
          (c.attTeamBusy
              ? const ReportLoader(text: 'Loading attendance…')
              : const EmptyBox('Not loaded yet.'))
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
          else if (view == 'board')
            _AttBoard(c: c, day: d, members: rows)
          else if (rows.isEmpty)
            const EmptyBox('No one in this list.')
          else if (view == 'table')
            _AttTable(c: c, day: d, members: rows)
          else
            _AttCards(c: c, day: d, members: rows),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Active: checked in and the app was open in the last 15 '
            'minutes. Idle: checked in, app not open since. Check-ins left '
            'open close at 11:59 PM. Long-press a card to pin, hide, share '
            'or drag it.',
            style: ts(12.5, h: 1.4, c: p.ink3),
          ),
        ),
      ],
    );
  }
}

/// Monday … Sunday.
const List<String> kWeekdayNames = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// A member's day in words: "In 9:30 AM · Out 6:00 PM" etc.
(String, String) _inOut(AttMember m) {
  final DateTime? inAt =
      m.sessions.where((AttSession s) => s.open).firstOrNull?.checkIn ??
      m.firstIn;
  final String inT = inAt == null ? '—' : _t(inAt);
  final String outT = m.status.checkedIn
      ? 'Still in'
      : (m.lastOut == null ? '—' : _t(m.lastOut));
  return (inT, outT);
}

/// Members as cards (two columns on wider phones); each one a card of the
/// card system (long-press: pin, drag, hide, share).
class _AttCards extends StatelessWidget {
  const _AttCards({required this.c, required this.day, required this.members});
  final AppController c;
  final DateTime day;
  final List<AttMember> members;

  @override
  Widget build(BuildContext context) {
    final ({List<AttMember> rows, int hidden, VoidCallback unhide}) v = c
        .listView<AttMember>('attCards', members, (AttMember m) => m.userId);
    final bool two = MediaQuery.sizeOf(context).width >= 380;
    final List<Widget> cards = <Widget>[
      for (final AttMember m in v.rows)
        LRow(
          list: 'attCards',
          lk: m.userId,
          radius: 22,
          pinCorner: true,
          child: _AttCard(c: c, day: day, m: m),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (two)
          Grid(cols: 2, gap: 10, children: cards)
        else
          for (final Widget w in cards)
            Padding(padding: const EdgeInsets.only(bottom: 10), child: w),
        if (v.hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: HidRow(
              '${v.hidden} hidden · Unhide',
              onTap: v.unhide,
              inGrid: two,
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// One employee's day: name, position, weekday and date, check-in /
/// check-out, hours and status.
class _AttCard extends StatelessWidget {
  const _AttCard({required this.c, required this.day, required this.m});
  final AppController c;
  final DateTime day;
  final AttMember m;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final String name = c.attName(m.userId, m.username);
    final (String inT, String outT) = _inOut(m);
    final Color col = attColor(p, m.status);
    final LeaveRequest? leave = ymd(day) == ymd(c.today)
        ? c.leaveTodayOf(m.userId)
        : null;
    Widget time(String label, String v) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: ts(11.5, w: w700, c: p.ink3),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              v,
              maxLines: 1,
              style: ts(15, w: w800, c: p.ink),
            ),
          ),
        ],
      ),
    );
    return Tap(
      key: ValueKey<String>('attMember-${m.userId}'),
      onTap: () {
        if (c.guardTap('attCards', m.userId)) c.openAttMember(m);
      },
      child: Glass(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Av(initials(name), size: Av.sm),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: rtStyle(context, 15.5),
                      ),
                      Text(
                        '${m.position == null ? '' : '${m.position} · '}'
                        '${kWeekdayNames[day.weekday - 1].substring(0, 3)}, ${dmy(day)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ts(12, c: p.ink3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                time('Check-in', inT),
                time('Check-out', outT),
                time(
                  'Hours',
                  m.totalMinutes == 0 ? '—' : hoursMinutes(m.totalMinutes),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: col.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _Dot(col),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            m.status.label,
                            key: ValueKey<String>('attCardStatus-${m.userId}'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ts(12.5, w: w800, c: col),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (leave != null) ...<Widget>[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'On leave',
                      key: ValueKey<String>('attOnLeave-${m.userId}'),
                      maxLines: 1,
                      style: ts(12.5, w: w700, c: p.navy2),
                    ),
                  ),
                ],
                if (m.autoClosed) ...<Widget>[
                  const SizedBox(width: 6),
                  Text(
                    'Auto out',
                    style: ts(12, w: w700, c: p.warn),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Members as a table: name, status, in, out, hours (scrolls sideways on
/// narrow phones).
class _AttTable extends StatelessWidget {
  const _AttTable({required this.c, required this.day, required this.members});
  final AppController c;
  final DateTime day;
  final List<AttMember> members;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    TextStyle head = ts(12, w: w800, c: p.ink3);
    Widget cell(String s, {TextStyle? st, double w = 86}) => SizedBox(
      width: w,
      child: Text(
        s,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: st ?? ts(13.5, w: w600, c: p.ink),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Glass(
        key: const ValueKey<String>('attTable'),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: <Widget>[
                    cell('Employee', st: head, w: 140),
                    cell('Status', st: head, w: 112),
                    cell('In', st: head),
                    cell('Out', st: head),
                    cell('Hours', st: head, w: 72),
                  ],
                ),
              ),
              for (final AttMember m in members)
                Tap(
                  key: ValueKey<String>('attRow-${m.userId}'),
                  onTap: () => c.openAttMember(m),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: navyA(.08))),
                    ),
                    child: Row(
                      children: <Widget>[
                        cell(
                          c.attName(m.userId, m.username),
                          st: ts(14, w: w700, c: p.ink),
                          w: 140,
                        ),
                        SizedBox(
                          width: 112,
                          child: Row(
                            children: <Widget>[
                              _Dot(attColor(p, m.status)),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  m.status.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: ts(
                                    12.5,
                                    w: w700,
                                    c: attColor(p, m.status),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        cell(_inOut(m).$1),
                        cell(_inOut(m).$2),
                        cell(
                          m.totalMinutes == 0
                              ? '—'
                              : hoursMinutes(m.totalMinutes),
                          w: 72,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Members as a board: one column per status (scrolls sideways).
class _AttBoard extends StatelessWidget {
  const _AttBoard({required this.c, required this.day, required this.members});
  final AppController c;
  final DateTime day;
  final List<AttMember> members;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final List<(String, List<AttStatus>)> cols = <(String, List<AttStatus>)>[
      ('Checked in', <AttStatus>[AttStatus.active, AttStatus.idle]),
      ('Checked out', <AttStatus>[AttStatus.checkedOut]),
      ('Not in', <AttStatus>[AttStatus.absent]),
      ('Not tracked', <AttStatus>[AttStatus.exempt]),
    ];
    final double w = (MediaQuery.sizeOf(context).width * .72).clamp(220, 280);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SingleChildScrollView(
        key: const ValueKey<String>('attBoard'),
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final (String, List<AttStatus>) col in cols)
              () {
                final List<AttMember> l = members
                    .where((AttMember m) => col.$2.contains(m.status))
                    .toList();
                return Container(
                  width: w,
                  margin: const EdgeInsets.only(right: 10),
                  child: Glass(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            _Dot(attColor(p, col.$2.first)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                col.$1,
                                style: rtStyle(context, 14.5),
                              ),
                            ),
                            Text(
                              '${l.length}',
                              key: ValueKey<String>('attBoardN-${col.$1}'),
                              style: ts(14, w: w800, c: p.ink2),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (l.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text('No one', style: ts(13, c: p.ink3)),
                          ),
                        for (final AttMember m in l)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Tap(
                              onTap: () => c.openAttMember(m),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: whiteA(.45),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      c.attName(m.userId, m.username),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: ts(14, w: w800, c: p.ink),
                                    ),
                                    Text(
                                      'In ${_inOut(m).$1} · Out ${_inOut(m).$2}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: ts(12, c: p.ink3),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }(),
          ],
        ),
      ),
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
        Sub(
          <String>[
            if (c.attMemberPosition != null) c.attMemberPosition!,
            c.attPersonTracked
                ? 'Attendance and leave'
                : 'Not tracked (check-in rules)',
          ].join(' · '),
        ),
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

// ------------------------------------------------------------ calendar
/// What one day was for a person: worked (with hours), approved leave,
/// holiday, weekly off, absent (a working day gone by with no check-in),
/// ahead, or nothing to show.
enum AttDayKind { worked, leave, holiday, weeklyOff, absent, ahead, none }

/// [d] for the person on screen (own history, or the admin's member view).
(AttDayKind, AttDay?, LeaveRequest?, LeaveHoliday?) attDayOf(
  AppController c,
  DateTime d,
) {
  final DateTime t = DateTime(c.today.year, c.today.month, c.today.day);
  final AttDay? day = c.attHist?.days
      .where((AttDay x) => x.date != null && ymd(x.date!) == ymd(d))
      .firstOrNull;
  final LeaveCalendar? cal = c.attLeaveCal;
  final String? who = c.screen == 'attMember' ? c.attMemberId : null;
  final LeaveRequest? l = cal?.leaveOn(d, userId: who);
  final LeaveHoliday? h = cal?.holidayOn(d);
  if (day != null) return (AttDayKind.worked, day, l, h);
  if (d.isAfter(t)) return (AttDayKind.ahead, null, l, h);
  if (l != null) return (AttDayKind.leave, null, l, h);
  if (h != null) return (AttDayKind.holiday, null, l, h);
  if (cal?.weeklyOffOn(d) ?? d.weekday == DateTime.sunday) {
    return (AttDayKind.weeklyOff, null, l, h);
  }
  // Not expected to check in (exempt), or today (not over): never absent.
  if (!c.attPersonTracked || !d.isBefore(t)) {
    return (AttDayKind.none, null, l, h);
  }
  return (AttDayKind.absent, null, l, h);
}

/// A month: every day coloured by what it was; tap a day for its details.
class AttCalendar extends StatelessWidget {
  const AttCalendar({super.key, required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final DateTime t = DateTime(c.today.year, c.today.month, c.today.day);
    final DateTime m = c.attMonth ?? DateTime(t.year, t.month);
    final bool thisMonth = m.year == t.year && m.month == t.month;
    final int days = DateTime(m.year, m.month + 1, 0).day;
    // Weeks start on Monday.
    final int lead = (DateTime(m.year, m.month).weekday + 6) % 7;
    final List<(AttDayKind, AttDay?, LeaveRequest?, LeaveHoliday?)> month =
        <(AttDayKind, AttDay?, LeaveRequest?, LeaveHoliday?)>[
          for (int i = 1; i <= days; i++)
            attDayOf(c, DateTime(m.year, m.month, i)),
        ];
    Color? tint(AttDayKind k) => switch (k) {
      AttDayKind.worked => p.pos,
      AttDayKind.leave => p.navy2,
      AttDayKind.holiday => p.acc,
      AttDayKind.absent => p.neg,
      _ => null,
    };
    // What the day was, in words (screen readers; not drawn in the cell).
    String tag(AttDayKind k, AttDay? d, LeaveRequest? l) => switch (k) {
      AttDayKind.worked => 'Present, ${hoursShort(d!.totalMinutes)}',
      AttDayKind.leave => l?.halfDay == null ? 'Leave' : '½ Leave',
      AttDayKind.holiday => 'Holiday',
      AttDayKind.weeklyOff => 'Off',
      AttDayKind.absent => 'Absent',
      _ => '',
    };
    int n(AttDayKind k) => month
        .where(
          ((AttDayKind, AttDay?, LeaveRequest?, LeaveHoliday?) x) => x.$1 == k,
        )
        .length;
    final DateTime? sel = c.attCalDay;
    const List<String> week = <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Glass(
          key: const ValueKey<String>('attCalendar'),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  CBtn(
                    'chevL',
                    key: const ValueKey<String>('attMonthPrev'),
                    small: true,
                    onTap: c.attHistBusy ? null : () => c.shiftAttMonth(-1),
                  ),
                  Expanded(
                    child: Text(
                      '${kMonthsLong[m.month - 1]} ${m.year}',
                      key: const ValueKey<String>('attMonth'),
                      textAlign: TextAlign.center,
                      style: rtStyle(context, 16),
                    ),
                  ),
                  CBtn(
                    'chevR',
                    key: const ValueKey<String>('attMonthNext'),
                    small: true,
                    onTap: thisMonth || c.attHistBusy
                        ? null
                        : () => c.shiftAttMonth(1),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  for (final String w in week)
                    Expanded(
                      child: Text(
                        w,
                        textAlign: TextAlign.center,
                        style: ts(12, w: w700, c: p.ink3),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              for (int row = 0; row * 7 < lead + days; row++)
                Row(
                  children: <Widget>[
                    for (int col = 0; col < 7; col++)
                      Expanded(
                        child: _cell(
                          context,
                          p,
                          row * 7 + col - lead + 1,
                          days,
                          m,
                          t,
                          sel,
                          month,
                          tint,
                          tag,
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 8),
              // The month in numbers (days so far).
              Wrap(
                key: const ValueKey<String>('attCalTotals'),
                spacing: 10,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  for (final (AttDayKind, String, Color) x
                      in <(AttDayKind, String, Color)>[
                        (AttDayKind.worked, 'Present', p.pos),
                        (AttDayKind.leave, 'Leave', p.navy2),
                        (AttDayKind.holiday, 'Holiday', p.acc),
                        (AttDayKind.absent, 'Absent', p.neg),
                      ])
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _Dot(x.$3),
                        const SizedBox(width: 4),
                        Text(
                          '${x.$2} ${n(x.$1)}',
                          key: ValueKey<String>('attCalN-${x.$1.name}'),
                          style: ts(12.5, w: w700, c: p.ink2),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (sel != null) _CalDayDetail(c: c, d: sel),
      ],
    );
  }

  Widget _cell(
    BuildContext context,
    TcPalette p,
    int i,
    int days,
    DateTime m,
    DateTime t,
    DateTime? sel,
    List<(AttDayKind, AttDay?, LeaveRequest?, LeaveHoliday?)> month,
    Color? Function(AttDayKind) tint,
    String Function(AttDayKind, AttDay?, LeaveRequest?) tag,
  ) {
    if (i < 1 || i > days) return const SizedBox(height: 46);
    final DateTime d = DateTime(m.year, m.month, i);
    final (AttDayKind k, AttDay? day, LeaveRequest? l, LeaveHoliday? _) =
        month[i - 1];
    final bool isToday = ymd(d) == ymd(t);
    final bool picked = sel != null && ymd(sel) == ymd(d);
    final Color? col = tint(k);
    // Only the date in the cell: its colour (as in the legend below) says
    // what the day was; the words are for screen readers and the day's
    // details (tap).
    final String what = tag(k, day, l);
    return Semantics(
      label: what.isEmpty ? '$i' : '$i, $what',
      button: true,
      excludeSemantics: true,
      child: Tap(
        key: ValueKey<String>('attCal-${ymd(d)}'),
        onTap: () => c.pickAttCalDay(d),
        radius: 10,
        child: Container(
          height: 46,
          margin: const EdgeInsets.all(1.5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: col?.withValues(alpha: .18),
            borderRadius: BorderRadius.circular(10),
            border: picked || isToday
                ? Border.all(color: picked ? p.ink : p.acc, width: 1.6)
                : null,
          ),
          child: Text(
            '$i',
            style: ts(
              14.5,
              w: w800,
              c:
                  col ??
                  (k == AttDayKind.ahead || k == AttDayKind.weeklyOff
                      ? p.ink3
                      : p.ink),
            ),
          ),
        ),
      ),
    );
  }
}

/// The tapped day: its sessions, or what it was (leave / holiday / …).
class _CalDayDetail extends StatelessWidget {
  const _CalDayDetail({required this.c, required this.d});
  final AppController c;
  final DateTime d;

  @override
  Widget build(BuildContext context) {
    final (AttDayKind k, AttDay? day, LeaveRequest? l, LeaveHoliday? h) =
        attDayOf(c, d);
    if (k == AttDayKind.worked) return _DayCard(day!);
    final String sub = switch (k) {
      AttDayKind.leave =>
        '${l!.typeName}${l.halfLabel == null ? '' : ' · ${l.halfLabel}'} · ${leaveDates(l)}',
      AttDayKind.holiday => h!.name,
      AttDayKind.weeklyOff => 'Weekly off',
      AttDayKind.absent => 'A working day with no check-in',
      AttDayKind.ahead => 'Not yet',
      _ => 'No check-in',
    };
    final String title = switch (k) {
      AttDayKind.leave => 'On leave',
      AttDayKind.holiday => 'Holiday',
      AttDayKind.weeklyOff => 'Off',
      AttDayKind.absent => 'Absent',
      _ => '—',
    };
    return _OffDayCard(d, title, sub);
  }
}

/// "7h" / "7h30" / "45m" (a calendar cell).
String hoursShort(int minutes) {
  final int h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h${m.toString().padLeft(2, '0')}';
}

/// List / Calendar switch above a history.
class AttViewSeg extends StatelessWidget {
  const AttViewSeg({super.key, required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) => Seg(
    key: const ValueKey<String>('attView'),
    margin: const EdgeInsets.only(bottom: 12),
    items: const <String>['List', 'Calendar'],
    selected: c.attView == 'calendar' ? 1 : 0,
    onPick: (int i) => c.setAttView(i == 1 ? 'calendar' : 'list'),
  );
}
