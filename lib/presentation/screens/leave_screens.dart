// Leave management: a member's leave (balances, Apply, requests), the
// admin's requests (approve / reject), one member's leave year, and Leave
// settings where the admin sets every rule (on / off, leave year, weekly
// off, half days, leave types and quotas, holidays).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/design/tc_fields.dart';
import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';
import '../../core/utils/format.dart';
import '../../data/models/models.dart';
import '../widgets/common.dart';
import '../widgets/report_loader.dart';
import '../widgets/voice_search.dart' show MicBtn, VoiceNote;

Color leaveColor(TcPalette p, LeaveStatus s) => switch (s) {
  LeaveStatus.pending => p.warn,
  LeaveStatus.approved => p.pos,
  LeaveStatus.rejected => p.neg,
  LeaveStatus.cancelled => p.ink3,
};

BadgeKind _badge(LeaveStatus s) => switch (s) {
  LeaveStatus.pending => BadgeKind.warn,
  LeaveStatus.approved => BadgeKind.ok,
  LeaveStatus.rejected => BadgeKind.bad,
  LeaveStatus.cancelled => BadgeKind.info,
};

/// "20 Oct 2026", "20 – 26 Oct 2026", "20 Oct 2026 · First half".
String leaveDates(LeaveRequest r) {
  final DateTime? a = r.from, b = r.to;
  if (a == null) return '—';
  if (b == null || ymd(a) == ymd(b)) {
    return r.halfLabel == null ? dmy(a) : '${dmy(a)} · ${r.halfLabel}';
  }
  if (a.year == b.year && a.month == b.month) return '${a.day} – ${dmy(b)}';
  return '${dmy(a)} – ${dmy(b)}';
}

/* ------------------------------------------------------------ pieces */

/// Balance tiles: available of entitled per leave type.
class _Balances extends StatelessWidget {
  const _Balances(this.list);
  final List<LeaveBalance> list;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    if (list.isEmpty) {
      return const InfoBox(
        'No leave types yet. The admin adds them in Leave settings.',
        icon: 'info',
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Grid(
        cols: 2,
        gap: 10,
        children: <Widget>[
          for (final LeaveBalance b in list)
            Glass(
              key: ValueKey<String>('leaveBal-${b.typeId}'),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    b.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ts(13.5, w: w700, c: p.ink2),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    b.unlimited
                        ? leaveDays(b.used)
                        : leaveDays(b.available ?? 0),
                    style: ts(
                      24,
                      w: w800,
                      c: !b.unlimited && (b.available ?? 0) <= 0
                          ? p.neg
                          : p.ink,
                    ),
                  ),
                  Text(
                    b.unlimited
                        ? 'taken · no limit'
                        : 'left of ${leaveDays(b.entitled ?? 0)}',
                    style: ts(12.5, w: w600, c: p.ink3),
                  ),
                  if (b.pending > 0 || b.carried > 0)
                    Text(
                      <String>[
                        if (b.pending > 0) '${leaveDays(b.pending)} waiting',
                        if (b.carried > 0) '${leaveDays(b.carried)} carried',
                      ].join(' · '),
                      style: ts(12, c: p.warn),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One request in a list.
class _ReqRow extends ConsumerWidget {
  const _ReqRow(this.r, {this.showName = false});
  final LeaveRequest r;
  final bool showName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final String name = c.attName(r.userId, r.username);
    return RowX(
      key: ValueKey<String>('leaveReq-${r.id}'),
      minHeight: 64,
      onTap: () => c.openLeaveReq(r),
      children: <Widget>[
        if (showName) Av(initials(name)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                showName ? name : r.typeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ts(15.5, w: w700, c: p.ink),
              ),
              Text(
                showName ? '${r.typeName} · ${leaveDates(r)}' : leaveDates(r),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: ts(13, c: p.ink2),
              ),
              const SizedBox(height: 4),
              Bdg(r.status.label, kind: _badge(r.status), fontSize: 11.5),
            ],
          ),
        ),
        Text(leaveDaysLabel(r.days), style: amtStyle(context, size: 14)),
      ],
    );
  }
}

/// A leave year bar: ‹ 2026-27 ›.
class _YearBar extends StatelessWidget {
  const _YearBar({required this.label, this.onPrev, this.onNext});
  final String label;
  final VoidCallback? onPrev, onNext;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Glass(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        children: <Widget>[
          CBtn(
            'chevL',
            key: const ValueKey<String>('leaveYearPrev'),
            small: true,
            onTap: onPrev,
          ),
          Expanded(
            child: Text(
              label.isEmpty ? 'Leave year' : 'Leave year $label',
              key: const ValueKey<String>('leaveYear'),
              textAlign: TextAlign.center,
              style: rtStyle(context, 15.5),
            ),
          ),
          CBtn(
            'chevR',
            key: const ValueKey<String>('leaveYearNext'),
            small: true,
            onTap: onNext,
          ),
        ],
      ),
    ),
  );
}

/// "On leave today" / "Holiday today" note (null: a working day).
String? leaveTodayNote(LeaveMe? m) {
  final LeaveToday? t = m?.today;
  if (t == null) return null;
  if (t.leave != null) {
    return 'You are on ${t.leave!.typeName} today'
        '${t.leave!.halfLabel == null ? '' : ' (${t.leave!.halfLabel!.toLowerCase()})'}.';
  }
  if (t.kind == 'holiday') {
    final String name =
        m!.holidays
            .where(
              (LeaveHoliday h) =>
                  h.date != null &&
                  t.date != null &&
                  ymd(h.date!) == ymd(t.date!),
            )
            .firstOrNull
            ?.name ??
        '';
    return name.isEmpty ? 'Today is a holiday.' : 'Today is a holiday: $name.';
  }
  if (t.kind == 'weekly_off') return 'Today is your weekly off.';
  return null;
}

/* ------------------------------------------------------- member screen */

/// A team member's leave: balances, Apply, requests of the leave year.
class LeaveScreen extends ConsumerWidget {
  const LeaveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final LeaveMe? m = c.leaveMe;
    final String? todayNote = leaveTodayNote(m);
    return Scr(
      children: <Widget>[
        BackNav(
          actions: <Widget>[
            CBtn('sync', onTap: c.leaveLoading ? null : c.loadLeave),
          ],
        ),
        const H1('Leave', afterNav: true),
        Sub(
          <String>[
            c.repo.profile?.username ?? c.repo.user?.username ?? '',
            if (m != null && m.enabled)
              'Weekly off: ${m.settings.weeklyOffLabel}',
          ].where((String s) => s.isNotEmpty).join(' · '),
        ),
        if (c.leaveError != null) ...<Widget>[
          InfoBox(c.leaveError!, icon: 'info'),
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 14),
            child: Btn(label: 'Try again', kind: BtnKind.g, onTap: c.loadLeave),
          ),
        ] else if (m == null)
          (c.leaveLoading
              ? const ReportLoader(text: 'Loading leave…')
              : const EmptyBox('Not loaded yet.'))
        else if (m.isAdmin)
          const InfoBox(
            'Leave is applied by your team members. See their requests under '
            'Leave requests.',
            icon: 'info',
          )
        else if (!m.enabled)
          const InfoBox(
            'Leave is not turned on for your company yet. Ask your admin.',
            icon: 'info',
          )
        else ...<Widget>[
          if (todayNote != null) InfoBox(todayNote, icon: 'calendar'),
          _YearBar(
            label: m.year.label,
            onPrev: c.leaveLoading ? null : () => c.shiftLeaveYear(-1),
            onNext: c.leaveLoading ? null : () => c.shiftLeaveYear(1),
          ),
          if (c.leaveLoading)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          _Balances(
            m.balances
                .where(
                  (LeaveBalance b) => b.active || b.used > 0 || b.pending > 0,
                )
                .toList(),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Btn(
              key: const ValueKey<String>('leaveApplyBtn'),
              label: 'Apply for leave',
              icon: 'plus',
              enabled: c.leaveTypesToApply.isNotEmpty,
              onTap: c.openApplyLeave,
            ),
          ),
          const Sec('My requests'),
          if (m.requests.isEmpty)
            const EmptyBox('No leave in this leave year.')
          else
            GlassList(
              margin: const EdgeInsets.only(bottom: 12),
              children: <Widget>[
                for (final LeaveRequest r in m.requests) _ReqRow(r),
              ],
            ),
          if (m.holidays.isNotEmpty) ...<Widget>[
            const Sec('Holidays'),
            GlassList(
              margin: const EdgeInsets.only(bottom: 12),
              children: <Widget>[
                for (final LeaveHoliday h in m.holidays)
                  RowX(
                    minHeight: 52,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          h.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ts(15, w: w700, c: p.ink),
                        ),
                      ),
                      Text(dmy(h.date), style: ts(13.5, c: p.ink2)),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}

/* -------------------------------------------------------- admin screens */

/// Admin: leave requests (Pending first) with the settings button.
class LeaveReqsScreen extends ConsumerWidget {
  const LeaveReqsScreen({super.key});

  static const List<(String, String)> kStatuses = <(String, String)>[
    ('pending', 'Pending'),
    ('approved', 'Approved'),
    ('rejected', 'Rejected'),
    ('cancelled', 'Cancelled'),
    ('all', 'All'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final List<LeaveRequest>? l = c.leaveReqs;
    return Scr(
      children: <Widget>[
        BackNav(
          actions: <Widget>[
            CBtn(
              'gear',
              key: const ValueKey<String>('leaveSettingsBtn'),
              onTap: c.openLeaveSettings,
            ),
            CBtn('sync', onTap: c.leaveReqsBusy ? null : c.loadLeaveRequests),
          ],
        ),
        const H1('Leave requests', afterNav: true),
        Sub(
          c.leavePending == 0
              ? 'Nothing waiting for you'
              : '${c.leavePending} waiting for approval',
        ),
        Chips(
          children: <Widget>[
            for (final (String, String) s in kStatuses)
              ChipBtn(
                s.$2,
                key: ValueKey<String>('leaveStatus-${s.$1}'),
                on: c.leaveReqStatus == s.$1,
                onTap: () => c.setLeaveReqStatus(s.$1),
              ),
          ],
        ),
        if (c.leaveReqsError != null)
          InfoBox(c.leaveReqsError!, icon: 'info')
        else if (l == null)
          (c.leaveReqsBusy
              ? const ReportLoader(text: 'Loading leave…')
              : EmptyBox('Not loaded yet.'))
        else ...<Widget>[
          if (c.leaveReqsBusy)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (l.isEmpty)
            EmptyBox(
              c.leaveReqStatus == 'pending'
                  ? 'No requests waiting.'
                  : 'No requests in this list.',
            )
          else
            GlassList(
              margin: const EdgeInsets.only(bottom: 12),
              children: <Widget>[
                for (final LeaveRequest r in l) _ReqRow(r, showName: true),
              ],
            ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Tap a request to approve or reject it. Leave types, quotas, '
            'holidays and weekly off are set in Leave settings (gear).',
            style: ts(12.5, h: 1.4, c: Tc.of(context).ink3),
          ),
        ),
      ],
    );
  }
}

/// Admin: one member's leave year (balances and requests).
class LeaveMemberScreen extends ConsumerWidget {
  const LeaveMemberScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final LeaveMe? m = c.leaveMemberData;
    return Scr(
      children: <Widget>[
        BackNav(
          actions: <Widget>[
            CBtn('sync', onTap: c.leaveMemberBusy ? null : c.loadLeaveMember),
          ],
        ),
        H1(
          c.leaveMemberName.isEmpty ? 'Team member' : c.leaveMemberName,
          afterNav: true,
        ),
        Sub(
          m == null || m.year.label.isEmpty
              ? 'Leave'
              : 'Leave · year ${m.year.label}',
        ),
        if (c.leaveMemberError != null)
          InfoBox(c.leaveMemberError!, icon: 'info')
        else if (m == null)
          (c.leaveMemberBusy
              ? const ReportLoader(text: 'Loading leave…')
              : EmptyBox('Not loaded yet.'))
        else ...<Widget>[
          if (!m.settings.enabled)
            const InfoBox(
              'Leave management is off. Turn it on in Leave settings.',
              icon: 'info',
            ),
          _Balances(m.balances),
          const Sec('Requests'),
          if (m.requests.isEmpty)
            const EmptyBox('No leave in this leave year.')
          else
            GlassList(
              margin: const EdgeInsets.only(bottom: 12),
              children: <Widget>[
                for (final LeaveRequest r in m.requests) _ReqRow(r),
              ],
            ),
        ],
      ],
    );
  }
}

/// Admin: Leave settings. Every change is saved at once.
class LeaveSettingsScreen extends ConsumerWidget {
  const LeaveSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final LeaveAdmin? a = c.leaveAdmin;
    final LeaveSettings? s = a?.settings;
    final bool idle = !c.leaveSaving;
    Widget toggle(
      String key,
      String title,
      String sub,
      bool on,
      VoidCallback f,
    ) => RowX(
      key: ValueKey<String>(key),
      minHeight: 60,
      onTap: idle ? f : null,
      children: <Widget>[
        Expanded(child: RTx(title, sub)),
        Sw(on),
      ],
    );
    Widget stepper(String key, String title, String sub, String value) => RowX(
      key: ValueKey<String>('leaveStep-$key'),
      minHeight: 60,
      children: <Widget>[
        Expanded(child: RTx(title, sub)),
        Stepper2(
          label: value,
          onDec: idle ? () => c.stepLeaveSetting(key, -1) : null,
          onInc: idle ? () => c.stepLeaveSetting(key, 1) : null,
        ),
      ],
    );
    return Scr(
      children: <Widget>[
        BackNav(
          actions: <Widget>[
            CBtn('sync', onTap: c.leaveAdminBusy ? null : c.loadLeaveSettings),
          ],
        ),
        const H1('Leave settings', afterNav: true),
        const Sub('Only you (admin) can change these'),
        if (c.leaveAdminError != null)
          InfoBox(c.leaveAdminError!, icon: 'info')
        else if (a == null || s == null)
          (c.leaveAdminBusy
              ? const ReportLoader(text: 'Loading leave…')
              : EmptyBox('Not loaded yet.'))
        else ...<Widget>[
          if (c.leaveSaving || c.leaveAdminBusy)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          GlassList(
            margin: const EdgeInsets.only(bottom: 4),
            children: <Widget>[
              toggle(
                'leaveEnabled',
                'Leave management',
                s.enabled
                    ? 'On: team members can apply for leave'
                    : 'Off: team members do not see leave',
                s.enabled,
                () => c.saveLeaveSettings(<String, Object?>{
                  'enabled': !s.enabled,
                }),
              ),
            ],
          ),
          const Sec('Rules'),
          GlassList(
            children: <Widget>[
              stepper(
                'year_start_month',
                'Leave year starts',
                'Balances start again each year',
                kLeaveMonths[s.yearStartMonth - 1],
              ),
              toggle(
                'leaveHalfDay',
                'Half-day leave',
                s.halfDay ? 'Allowed (counts as 0.5 day)' : 'Not allowed',
                s.halfDay,
                () => c.saveLeaveSettings(<String, Object?>{
                  'half_day': !s.halfDay,
                }),
              ),
              stepper(
                'backdate_days',
                'Apply for past days',
                s.backdateDays == 0
                    ? 'Not allowed (today onwards)'
                    : 'Up to ${s.backdateDays} days back',
                '${s.backdateDays}',
              ),
              stepper(
                'max_request_days',
                'Longest request',
                'Calendar days in one request',
                '${s.maxRequestDays}',
              ),
            ],
          ),
          const Sec('Weekly off'),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                // Monday first.
                for (final int d in const <int>[1, 2, 3, 4, 5, 6, 0])
                  ChipBtn(
                    kLeaveWeekdays[d].substring(0, 3),
                    key: ValueKey<String>('weeklyOff-$d'),
                    on: s.weeklyOff.contains(d),
                    onTap: idle ? () => c.toggleWeeklyOff(d) : null,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 0),
            child: Text(
              'Weekly off days and holidays are not counted as leave.',
              style: ts(12.5, c: p.ink3),
            ),
          ),
          const Sec('Leave types'),
          if (a.types.isEmpty) ...<Widget>[
            const InfoBox(
              'No leave types yet. Add your own, or start with Casual (12 '
              'days), Sick (6 days) and Unpaid (no limit) and change them.',
              icon: 'info',
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Btn(
                key: const ValueKey<String>('leaveDefaults'),
                label: 'Add default types',
                kind: BtnKind.g,
                enabled: idle,
                onTap: c.addDefaultLeaveTypes,
              ),
            ),
          ] else
            GlassList(
              margin: const EdgeInsets.only(bottom: 10),
              children: <Widget>[
                for (final LeaveType t in a.types)
                  RowX(
                    key: ValueKey<String>('leaveType-${t.id}'),
                    minHeight: 60,
                    onTap: () => c.openLeaveType(t),
                    children: <Widget>[
                      Expanded(
                        child: RTx(
                          t.name,
                          t.summary,
                          titleStyle: t.active
                              ? null
                              : ts(16, w: w700, c: p.ink3),
                        ),
                      ),
                      chevR(),
                    ],
                  ),
              ],
            ),
          Btn(
            key: const ValueKey<String>('leaveAddType'),
            label: 'Add leave type',
            icon: 'plus',
            kind: BtnKind.g,
            enabled: idle,
            onTap: () => c.openLeaveType(),
          ),
          const Sec('Holidays'),
          _YearBar(
            label: a.year.label,
            onPrev: c.leaveAdminBusy ? null : () => c.shiftLeaveAdminYear(-1),
            onNext: c.leaveAdminBusy ? null : () => c.shiftLeaveAdminYear(1),
          ),
          if (a.holidays.isEmpty)
            const EmptyBox('No holidays in this leave year.')
          else
            GlassList(
              margin: const EdgeInsets.only(bottom: 10),
              children: <Widget>[
                for (final LeaveHoliday h in a.holidays)
                  RowX(
                    key: ValueKey<String>(
                      'holiday-${h.date == null ? '' : ymd(h.date!)}',
                    ),
                    minHeight: 56,
                    children: <Widget>[
                      Expanded(child: RTx(h.name, dmy(h.date))),
                      CBtn(
                        'trash',
                        small: true,
                        onTap: idle ? () => c.deleteHoliday(h) : null,
                      ),
                    ],
                  ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 14),
            child: Btn(
              key: const ValueKey<String>('leaveAddHoliday'),
              label: 'Add holiday',
              icon: 'plus',
              kind: BtnKind.g,
              enabled: idle,
              onTap: c.openAddHoliday,
            ),
          ),
        ],
      ],
    );
  }
}

/// Team page (admin): leave requests waiting and who is on leave today.
class TeamLeaveCard extends ConsumerWidget {
  const TeamLeaveCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    if (!c.isAdmin || !c.repo.isRemote || c.demo) {
      return const SizedBox.shrink();
    }
    final int onLeave = c.leaveTeamToday?.leaves.length ?? 0;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Tap(
        key: const ValueKey<String>('teamLeaveCard'),
        onTap: () {
          if (c.guardTap('teamCards', 'leave')) c.openLeaveRequests();
        },
        child: Glass(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: <Widget>[
              Ico('calendar', size: IcoSize.xs, color: p.acc),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Leave', style: rtStyle(context, 16.5)),
                    Text(
                      <String>[
                        c.leavePending == 0
                            ? 'No requests waiting'
                            : '${c.leavePending} waiting for approval',
                        if (onLeave > 0) '$onLeave on leave today',
                      ].join(' · '),
                      key: const ValueKey<String>('teamLeaveLine'),
                      style: ts(13.5, c: c.leavePending > 0 ? p.warn : p.ink3),
                    ),
                  ],
                ),
              ),
              if (c.leavePending > 0) ...<Widget>[
                Bdg('${c.leavePending}', kind: BadgeKind.warn),
                const SizedBox(width: 8),
              ],
              chevR(),
            ],
          ),
        ),
      ),
    );
  }
}

/* --------------------------------------------------------------- sheets */

/// Apply for leave: type, From–To (or a half day), reason (voice too).
class LeaveApplySheet extends ConsumerWidget {
  const LeaveApplySheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final LeaveSettings s = c.leaveMe?.settings ?? const LeaveSettings();
    final List<LeaveBalance> types = c.leaveTypesToApply;
    final String? err = c.leaveApplyError;
    final num days = c.leaveApplyDays;
    final bool half = c.f('lvHalf').isNotEmpty;
    return Sheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SheetHead('Apply for leave'),
          Fld(
            label: 'Leave type',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final LeaveBalance b in types)
                  ChipBtn(
                    b.unlimited
                        ? b.name
                        : '${b.name} · ${leaveDays(b.available ?? 0)} left',
                    key: ValueKey<String>('lvType-${b.typeId}'),
                    on: c.f('lvType') == '${b.typeId}',
                    onTap: () => c.setF('lvType', '${b.typeId}'),
                  ),
              ],
            ),
          ),
          if (s.halfDay)
            Seg(
              key: const ValueKey<String>('lvHalfSeg'),
              items: const <String>['Full days', 'First half', 'Second half'],
              selected: switch (c.f('lvHalf')) {
                'first' => 1,
                'second' => 2,
                _ => 0,
              },
              onPick: (int i) => c.setLeaveHalf(switch (i) {
                1 => 'first',
                2 => 'second',
                _ => '',
              }),
            ),
          Row(
            children: <Widget>[
              Expanded(
                child: Fld(
                  label: half ? 'Date' : 'From',
                  child: DateInp(
                    key: const ValueKey<String>('lvFrom'),
                    value: c.f('lvFrom'),
                    onChanged: c.setLeaveFrom,
                  ),
                ),
              ),
              if (!half) ...<Widget>[
                const SizedBox(width: 12),
                Expanded(
                  child: Fld(
                    label: 'To',
                    child: DateInp(
                      key: const ValueKey<String>('lvTo'),
                      value: c.f('lvTo'),
                      onChanged: c.setLeaveTo,
                    ),
                  ),
                ),
              ],
            ],
          ),
          Fld(
            label: 'Reason (optional)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Inp(
                  key: const ValueKey<String>('lvReason'),
                  value: c.f('lvReason'),
                  onChanged: (String v) => c.setF('lvReason', v),
                  placeholder: c.voiceOnFor('lvReason')
                      ? 'Listening…'
                      : 'e.g. Family function',
                  maxLength: 300,
                  trailing: const MicBtn('lvReason'),
                ),
                const VoiceNote('lvReason'),
              ],
            ),
          ),
          Text(
            err ??
                '${leaveDaysLabel(days)} of leave (weekly off and holidays not counted)',
            key: const ValueKey<String>('lvSummary'),
            style: ts(13.5, w: w700, c: err == null ? p.ink2 : p.neg),
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
                  key: const ValueKey<String>('lvSend'),
                  label: c.leaveBusy ? 'Sending…' : 'Apply',
                  icon: 'send',
                  enabled: err == null && !c.leaveBusy,
                  onTap: c.applyLeave,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One request: details and what this login may do with it.
class LeaveReqSheet extends ConsumerWidget {
  const LeaveReqSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final LeaveRequest? r = c.leaveSel;
    if (r == null) return const SizedBox.shrink();
    final String name = c.attName(r.userId, r.username);
    final bool admin = c.isAdmin;
    final bool canDecide = admin && r.pending;
    final bool canCancel =
        (!admin && r.pending) || (admin && r.status == LeaveStatus.approved);
    Widget line(String k, String v) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              k,
              style: ts(13.5, w: w600, c: p.ink3),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: ts(14.5, w: w600, c: p.ink),
            ),
          ),
        ],
      ),
    );
    return Sheet(
      child: Column(
        key: const ValueKey<String>('leaveReqSheet'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SheetHead(admin ? name : r.typeName, sub: r.status.label),
          Glass(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (admin) line('Leave', r.typeName),
                line('Dates', leaveDates(r)),
                line('Days', leaveDaysLabel(r.days)),
                if (r.reason != null) line('Reason', r.reason!),
                if (r.createdAt != null) line('Applied', dmy(r.createdAt)),
                if (r.decisionNote != null) line('Note', r.decisionNote!),
              ],
            ),
          ),
          if (admin && r.pending)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Tap(
                key: const ValueKey<String>('leaveSeeBalance'),
                onTap: () {
                  c.closeOv();
                  c.openLeaveMember(r.userId, name);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 4,
                  ),
                  child: Text(
                    "See $name's leave balance",
                    style: ts(14, w: w700, c: p.acc),
                  ),
                ),
              ),
            ),
          if (canDecide || (admin && canCancel)) ...<Widget>[
            const SizedBox(height: 10),
            Fld(
              label: 'Note to ${admin ? name : 'admin'} (optional)',
              child: Inp(
                key: const ValueKey<String>('lvNote'),
                value: c.f('lvNote'),
                onChanged: (String v) => c.setF('lvNote', v),
                placeholder: canDecide
                    ? 'e.g. Enjoy your leave'
                    : 'e.g. Needed at work',
                maxLength: 300,
              ),
            ),
          ] else
            const SizedBox(height: 14),
          if (canDecide)
            Row(
              children: <Widget>[
                Expanded(
                  child: Btn(
                    key: const ValueKey<String>('leaveReject'),
                    label: 'Reject',
                    icon: 'close',
                    kind: BtnKind.g,
                    enabled: !c.leaveBusy,
                    onTap: () => c.decideLeave('reject'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Btn(
                    key: const ValueKey<String>('leaveApprove'),
                    label: c.leaveBusy ? 'Saving…' : 'Approve',
                    icon: 'check',
                    enabled: !c.leaveBusy,
                    onTap: () => c.decideLeave('approve'),
                  ),
                ),
              ],
            )
          else if (canCancel)
            Btn(
              key: const ValueKey<String>('leaveCancel'),
              label: admin ? 'Cancel this leave' : 'Cancel request',
              icon: 'xCircle',
              kind: BtnKind.g,
              enabled: !c.leaveBusy,
              onTap: () => c.decideLeave('cancel'),
            )
          else
            Btn(label: 'Close', kind: BtnKind.g, onTap: c.closeOv),
        ],
      ),
    );
  }
}

/// Admin: add or change a leave type.
class LeaveTypeSheet extends ConsumerWidget {
  const LeaveTypeSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final LeaveType? t = c.leaveTypeEdit;
    final String? err = c.leaveTypeError;
    final bool carry = c.f('ltCarry').isNotEmpty;
    Widget flag(String key, String title, String sub) => RowX(
      key: ValueKey<String>(key),
      minHeight: 56,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      onTap: () => c.toggleLeaveTypeFlag(key),
      children: <Widget>[
        Expanded(child: RTx(title, sub)),
        Sw(c.f(key).isNotEmpty),
      ],
    );
    return Sheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SheetHead(t == null ? 'Add leave type' : 'Leave type'),
          Fld(
            label: 'Name',
            req: true,
            child: Inp(
              key: const ValueKey<String>('ltName'),
              value: c.f('ltName'),
              onChanged: (String v) => c.setF('ltName', v),
              placeholder: 'e.g. Casual Leave',
              maxLength: 40,
              capitalization: TextCapitalization.words,
            ),
          ),
          Fld(
            label: 'Days a year (empty: no limit)',
            child: Inp(
              key: const ValueKey<String>('ltQuota'),
              value: c.f('ltQuota'),
              onChanged: (String v) => c.setF('ltQuota', v),
              placeholder: 'No limit',
              keyboard: const TextInputType.numberWithOptions(decimal: true),
              maxLength: 5,
            ),
          ),
          flag('ltPaid', 'Paid leave', 'Unpaid leave is shown as unpaid'),
          flag(
            'ltCarry',
            'Carry forward',
            'Unused days move to the next leave year',
          ),
          if (carry)
            Fld(
              label: 'Carry at most (empty: all)',
              child: Inp(
                key: const ValueKey<String>('ltMaxCarry'),
                value: c.f('ltMaxCarry'),
                onChanged: (String v) => c.setF('ltMaxCarry', v),
                placeholder: 'All unused days',
                keyboard: const TextInputType.numberWithOptions(decimal: true),
                maxLength: 5,
              ),
            ),
          if (t != null)
            flag(
              'ltActive',
              'Members can choose it',
              'Off hides it; past leave stays',
            ),
          if (err != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                err,
                style: ts(13.5, w: w700, c: Tc.of(context).neg),
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
                  key: const ValueKey<String>('ltSave'),
                  label: c.leaveSaving ? 'Saving…' : 'Save',
                  icon: 'check',
                  enabled: err == null && !c.leaveSaving,
                  onTap: c.saveLeaveType,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Admin: add a holiday.
class LeaveHolidaySheet extends ConsumerWidget {
  const LeaveHolidaySheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final String? err = c.holidayError;
    return Sheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SheetHead('Add holiday', sub: 'Not counted as leave'),
          Fld(
            label: 'Date',
            child: DateInp(
              key: const ValueKey<String>('hdDate'),
              value: c.f('hdDate'),
              onChanged: (String v) => c.setF('hdDate', v),
            ),
          ),
          Fld(
            label: 'Name',
            req: true,
            child: Inp(
              key: const ValueKey<String>('hdName'),
              value: c.f('hdName'),
              onChanged: (String v) => c.setF('hdName', v),
              placeholder: 'e.g. Diwali',
              maxLength: 60,
              capitalization: TextCapitalization.words,
            ),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: Btn(label: 'Cancel', kind: BtnKind.g, onTap: c.closeOv),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Btn(
                  key: const ValueKey<String>('hdSave'),
                  label: c.leaveSaving ? 'Saving…' : 'Add',
                  icon: 'check',
                  enabled: err == null && !c.leaveSaving,
                  onTap: c.saveHoliday,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
