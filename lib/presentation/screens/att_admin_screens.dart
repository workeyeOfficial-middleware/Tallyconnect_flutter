// Sales Team admin: Employee attendance (each member's days, hours, leave
// and absences in a From–To, one card each) and Check-in rules (who must
// check in: positions, the positions that do not, and per-person
// "always" / "exempt"). The server applies the rules and counts the days.
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

/// Sales Team page (admin): one link card — Employee attendance or
/// Check-in rules. A card of the card system (long-press: pin, drag, hide,
/// share; Check-in rules can also go on Home).
class TeamLinkCard extends ConsumerWidget {
  const TeamLinkCard(this.id, {super.key, this.list = 'teamCards'});

  /// `attEmployees` or `attRules`.
  final String id;

  /// The card list it is shown in (`teamCards` or `home`).
  final String list;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    if (!c.isAdmin || !c.repo.isRemote || c.demo) {
      return const SizedBox.shrink();
    }
    final bool rules = id == 'attRules';
    return GlassList(
      margin: const EdgeInsets.only(top: 12),
      children: <Widget>[
        RowX(
          key: ValueKey<String>(rules ? 'teamAttRules' : 'teamAttEmployees'),
          minHeight: 64,
          onTap: () {
            if (!c.guardTap(list, id)) return;
            rules ? c.openAttRules() : c.openAttEmployees();
          },
          children: <Widget>[
            Ico(
              rules ? 'shield' : 'calendar',
              size: IcoSize.xs,
              color: rules ? p.navy : p.acc,
              icon: IcSize.s,
            ),
            Expanded(
              child: RTx(
                rules ? 'Check-in rules' : 'Employee attendance',
                rules
                    ? 'Who checks in: positions, managers exempt'
                    : 'Days, hours, leave and absences for any dates',
              ),
            ),
            chevR(),
          ],
        ),
      ],
    );
  }
}

/// Admin: every member's figures for a From–To, one card each.
class AttEmployeesScreen extends ConsumerWidget {
  const AttEmployeesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final AttSummary? s = c.attSum;
    final (DateTime from, DateTime to) = c.attSumRange;
    final List<AttSumRow> rows = s?.members ?? const <AttSumRow>[];
    final int tracked = rows.where((AttSumRow r) => r.required).length;
    return Scr(
      children: <Widget>[
        BackNav(
          actions: <Widget>[
            CBtn('sync', onTap: c.attSumBusy ? null : c.loadAttSummary),
          ],
        ),
        const H1('Employee attendance', afterNav: true),
        Sub(
          <String>[
            if ((s?.company ?? '').isNotEmpty) s!.company else c.companyName,
            from == to ? dmy(from) : '${dmy(from)} – ${dmy(to)}',
          ].join(' · '),
        ),
        Chips(
          margin: const EdgeInsets.only(bottom: 12),
          children: <Widget>[
            for (final (String, String) x in AppController.kAttSumPresets)
              ChipBtn(
                x.$2,
                key: ValueKey<String>('attSum-${x.$1}'),
                height: 38,
                fontSize: 13.5,
                on: c.attSumPreset == x.$1,
                onTap: c.attSumBusy ? null : () => c.setAttSumPreset(x.$1),
              ),
            ChipBtn(
              c.attSumPreset == 'range'
                  ? '${dm(from)} – ${dm(to)}'
                  : 'Custom dates',
              key: const ValueKey<String>('attSum-range'),
              icon: 'calendar',
              height: 38,
              fontSize: 13.5,
              on: c.attSumPreset == 'range',
              onTap: c.attSumBusy ? null : () => c.setAttSumPreset('range'),
            ),
          ],
        ),
        if (c.attSumError != null)
          InfoBox(c.attSumError!, icon: 'info')
        else if (s == null)
          (c.attSumBusy
              ? const ReportLoader(text: 'Working out attendance…')
              : EmptyBox('Not loaded yet.'))
        else ...<Widget>[
          if (c.attSumBusy)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (rows.isEmpty)
            const InfoBox(
              'No team members yet. Add people on the Sales Team page.',
              icon: 'info',
            )
          else ...<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
              child: Text(
                '${rows.length} ${rows.length == 1 ? 'member' : 'members'}'
                '${tracked == rows.length ? '' : ' · ${rows.length - tracked} not tracked'}',
                key: const ValueKey<String>('attSumCount'),
                style: ts(13.5, w: w700, c: Tc.of(context).ink2),
              ),
            ),
            for (final AttSumRow r in rows) _EmployeeCard(c: c, r: r),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Absent: a working day gone by with no check-in and no '
              'approved leave (weekly off and holidays from Leave settings). '
              'Members not tracked by the Check-in rules are never absent.',
              style: ts(12.5, h: 1.4, c: Tc.of(context).ink3),
            ),
          ),
        ],
      ],
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({required this.c, required this.r});
  final AppController c;
  final AttSumRow r;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final String name = c.attName(r.userId, r.username);
    Widget stat(String k, String v, String label, Color col) => Expanded(
      child: Column(
        children: <Widget>[
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              v,
              key: ValueKey<String>('attSum-${r.userId}-$k'),
              maxLines: 1,
              style: ts(17, w: w800, c: col),
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ts(12, w: w600, c: p.ink3),
          ),
        ],
      ),
    );
    final String leave = r.leaveDays == r.leaveDays.roundToDouble()
        ? '${r.leaveDays.toInt()}'
        : r.leaveDays.toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Tap(
        key: ValueKey<String>('attSumCard-${r.userId}'),
        onTap: () => c.openAttSumMember(r),
        child: Glass(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Av(initials(name)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: rtStyle(context, 16),
                        ),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: <Widget>[
                            if (r.position != null)
                              Bdg(
                                r.position!,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                              ),
                            if (!r.required)
                              const Bdg(
                                'Not tracked',
                                kind: BadgeKind.info,
                                padding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  chevR(),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  stat(
                    'present',
                    '${r.presentDays}/${r.workingDays}',
                    'Present',
                    p.pos,
                  ),
                  stat('hours', hoursMinutes(r.totalMinutes), 'Hours', p.ink),
                  stat('leave', leave, 'Leave', p.navy2),
                  stat(
                    'absent',
                    '${r.absentDays}',
                    'Absent',
                    r.absentDays > 0 ? p.neg : p.ink3,
                  ),
                ],
              ),
              if (r.presentDays > 0) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  'Avg in ${_hm(r.avgIn)} · out ${_hm(r.avgOut)} · '
                  '${hoursMinutes(r.avgMinutes)} a day',
                  key: ValueKey<String>('attSum-${r.userId}-avg'),
                  style: ts(12.5, c: p.ink3),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "09:40" (India time) → "9:40 AM".
String _hm(String? s) {
  if (s == null) return '—';
  final List<String> x = s.split(':');
  final int? h = int.tryParse(x.first), m = int.tryParse(x.last);
  if (h == null || m == null) return s;
  return clock(DateTime(2000, 1, 1, h, m));
}

/// Admin: who checks in (Sales Team → Check-in rules).
class AttRulesScreen extends ConsumerWidget {
  const AttRulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final AttRules? r = c.attRules;
    final List<String> positions = <String>[
      ...?r?.positions,
      for (final String x in r?.exemptPositions ?? const <String>[])
        if (!(r?.positions ?? const <String>[]).any(
          (String y) => y.toLowerCase() == x.toLowerCase(),
        ))
          x,
    ];
    final int tracked =
        r?.members.where((AttRuleMember m) => m.required).length ?? 0;
    return Scr(
      children: <Widget>[
        BackNav(
          actions: <Widget>[
            CBtn('sync', onTap: c.attRulesBusy ? null : c.loadAttRules),
          ],
        ),
        const H1('Check-in rules', afterNav: true),
        Sub(
          r == null
              ? 'Who must check in and out'
              : '$tracked of ${r.members.length} check in',
        ),
        if (c.attRulesError != null) InfoBox(c.attRulesError!, icon: 'info'),
        if (r == null)
          (c.attRulesBusy
              ? const ReportLoader(text: 'Loading check-in rules…')
              : EmptyBox('Not loaded yet.'))
        else ...<Widget>[
          if (!r.ready)
            const InfoBox(
              'Check-in rules are not available on the server yet, so every '
              'team member checks in.',
              icon: 'info',
            ),
          const Sec(
            'Positions that do not check in',
            margin: EdgeInsets.fromLTRB(8, 6, 8, 8),
          ),
          Chips(
            margin: const EdgeInsets.only(bottom: 6),
            children: <Widget>[
              for (final String x in positions)
                ChipBtn(
                  x,
                  key: ValueKey<String>('attExempt-$x'),
                  height: 38,
                  fontSize: 13.5,
                  icon: r.exemptPosition(x) ? 'check' : null,
                  on: r.exemptPosition(x),
                  onTap: c.attRulesBusy || !r.ready
                      ? null
                      : () => c.toggleExemptPosition(x),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Text(
              'Ticked positions (e.g. Manager, Director) are not asked to '
              'check in and never count as absent. Everyone else checks in.',
              style: ts(12.5, h: 1.4, c: p.ink3),
            ),
          ),
          const Sec('Team members', margin: EdgeInsets.fromLTRB(8, 6, 8, 8)),
          if (r.members.isEmpty)
            const InfoBox(
              'No team members yet. Add people on the Sales Team page.',
              icon: 'info',
            )
          else
            GlassList(
              children: <Widget>[
                for (final AttRuleMember m in r.members)
                  RowX(
                    key: ValueKey<String>('attRule-${m.userId}'),
                    minHeight: 62,
                    onTap: !r.ready ? null : () => c.editAttRuleMember(m),
                    children: <Widget>[
                      Av(initials(c.attName(m.userId, m.username))),
                      Expanded(
                        child: RTx(
                          c.attName(m.userId, m.username),
                          '${m.position ?? 'No position'} · ${ruleText(m)}',
                          ell: true,
                        ),
                      ),
                      Bdg(
                        m.required ? 'Checks in' : 'Exempt',
                        kind: m.required ? BadgeKind.ok : BadgeKind.info,
                      ),
                    ],
                  ),
              ],
            ),
        ],
      ],
    );
  }
}

/// Why a member does / does not check in.
String ruleText(AttRuleMember m) => switch (m.rule) {
  'required' => 'always checks in',
  'exempt' => 'exempted',
  _ => m.reason == 'position' ? 'exempt by position' : 'checks in by position',
};

/// Admin: one member's position and rule.
class AttRuleMemberSheet extends ConsumerWidget {
  const AttRuleMemberSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final AttRuleMember? m = c.attRuleEdit;
    final AttRules? r = c.attRules;
    if (m == null || r == null) return const SizedBox.shrink();
    final String pos = c.f('arPosition').trim();
    final bool exemptPos = r.exemptPosition(pos);
    const List<(String, String)> rules = <(String, String)>[
      ('auto', 'By position'),
      ('required', 'Always'),
      ('exempt', 'Exempt'),
    ];
    final String rule = c.f('arRule').isEmpty ? m.rule : c.f('arRule');
    final bool will = switch (rule) {
      'required' => true,
      'exempt' => false,
      _ => !exemptPos,
    };
    return Sheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SheetHead(c.attName(m.userId, m.username), sub: m.email),
          Fld(
            label: 'Position',
            child: Inp(
              key: const ValueKey<String>('arPosition'),
              value: c.f('arPosition'),
              onChanged: (String s) => c.setF('arPosition', s),
              placeholder: 'e.g. Sales Executive',
              maxLength: 40,
            ),
          ),
          Chips(
            margin: const EdgeInsets.only(bottom: 12),
            children: <Widget>[
              for (final String x in r.positions)
                ChipBtn(
                  x,
                  height: 34,
                  fontSize: 13,
                  on: pos.toLowerCase() == x.toLowerCase(),
                  onTap: () => c.setF('arPosition', x),
                ),
            ],
          ),
          const Sec('Check-in', margin: EdgeInsets.fromLTRB(8, 0, 8, 8)),
          Seg(
            key: const ValueKey<String>('arRule'),
            items: rules.map(((String, String) x) => x.$2).toList(),
            selected: rules
                .indexWhere(((String, String) x) => x.$1 == rule)
                .clamp(0, 2),
            onPick: (int i) => c.setF('arRule', rules[i].$1),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Text(
              will
                  ? 'Checks in and out every working day.'
                  : 'Does not check in; never counted as absent.',
              key: const ValueKey<String>('arResult'),
              style: ts(13.5, w: w700, c: will ? p.pos : p.navy2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Row(
              children: <Widget>[
                Expanded(
                  flex: 10,
                  child: Btn(
                    label: 'Cancel',
                    kind: BtnKind.g,
                    onTap: c.closeOv,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 17,
                  child: Btn(
                    key: const ValueKey<String>('arSave'),
                    label: c.attRulesBusy ? 'Saving…' : 'Save',
                    icon: 'check',
                    enabled: !c.attRulesBusy,
                    onTap: () => c.saveAttRuleMember(rule),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
