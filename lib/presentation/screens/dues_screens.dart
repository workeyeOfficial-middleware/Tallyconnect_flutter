// OUTSTANDING HUB (946–965), OUTSTANDING LIST (967–996), BILL DETAIL
// (998–1025); view models 2522–2551.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/design/tc_icons.dart';
import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';
import '../../core/share/share_doc.dart';
import '../../core/utils/format.dart';
import '../../data/accounting.dart';
import '../../data/models/models.dart';
import '../../data/repositories/api_tally_repository.dart' show DataSet;
import '../../core/share/report_data.dart';
import '../widgets/bulk_bar.dart';
import '../widgets/common.dart';
import '../widgets/voice_search.dart';
import '../widgets/report_chart.dart';

class OutHubScreen extends ConsumerWidget {
  const OutHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    // Date range on: only bills dated in it (totals of exactly those).
    final bool rng = c.outRange && c.range != null;
    final List<Bill> recv = c.inOutRange(c.repo.receivables()),
        payb = c.inOutRange(c.repo.payables());
    final OutstandingSummary rs = rng
            ? summarise(recv, c.today)
            : c.repo.outstanding(true),
        ps = rng ? summarise(payb, c.today) : c.repo.outstanding(false);
    final List<
      (String, String, String, String, num, String, String, num, String)
    >
    cards =
        <(String, String, String, String, num, String, String, num, String)>[
          (
            'Receivable',
            'Customers owe you',
            'in',
            'receipt',
            rs.total,
            'big in',
            '${rs.parties} parties',
            rs.late,
            'recv',
          ),
          (
            'Payable',
            'You owe suppliers',
            'out',
            'payment',
            ps.total,
            'big out',
            '${ps.parties} parties',
            ps.late,
            'pay',
          ),
        ];
    final List<Bill> soon = dueSoon(recv, payb, c.today);
    // Long-press a card to pin, hide, share or drag it.
    final ({
      List<(String, String, String, String, num, String, String, num, String)>
      rows,
      int hidden,
      VoidCallback unhide,
    })
    oc = c
        .listView<
          (String, String, String, String, num, String, String, num, String)
        >(
          'outCards',
          cards,
          (
            (String, String, String, String, num, String, String, num, String)
            o,
          ) => o.$9,
        );
    return Scr(
      children: <Widget>[
        // Compact action icons (as in every header with several actions).
        NavDense(
          on: true,
          child: NavRow(
            gap: MediaQuery.sizeOf(context).width < 360 ? 5 : 8,
            children: <Widget>[
              CBtn(
                'menu',
                size: 44,
                iconSize: IcSize.m,
                onTap: () => c.openOverlay('menu'),
              ),
              // Shrinks with "…" on narrow phones (the buttons always fit).
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Bdg(
                    c.repo.isRemote ? 'As on ${dmy(c.today)}' : 'Sample data',
                    kind: BadgeKind.acc,
                  ),
                ),
              ),
              CBtn(
                'calendar',
                key: const ValueKey<String>('outRangeBtn'),
                dot: rng,
                onTap: () => c.openRange('out'),
              ),
              CBtn(
                'search',
                key: const ValueKey<String>('outSearchBtn'),
                onTap: c.toggleOutSearch,
              ),
              // Payment reminder settings: before / after the due date,
              // Automatic / Manual (the admin edits; others see them).
              if (c.emBlocked == null)
                CBtn(
                  'gear',
                  key: const ValueKey<String>('outRemSettingsBtn'),
                  onTap: c.openReminderSettings,
                ),
              // All active reminders (dot: one is due now).
              CBtn(
                'bell',
                key: const ValueKey<String>('remindersBtn'),
                dot: c.dueReminders.isNotEmpty,
                onTap: () => c.openOverlay('reminders'),
              ),
            ],
          ),
        ),
        const H1('Outstanding', afterNav: true),
        const Sub('Receivable and payable bills still to be settled'),
        const PeriodBar(target: 'out'),
        if (c.outSearch) ...<Widget>[
          OutSearchBox(c: c),
          if (c.outQuery.trim().isNotEmpty) ...<Widget>[
            Builder(
              builder: (BuildContext context) {
                final List<Bill> hits = c.memo<List<Bill>>(
                  'out-hub-search',
                  '${c.repo.version}|${c.outQuery}|$rng|${c.range?.key}',
                  () => <Bill>[
                    ...c.searchBills(recv).map((Bill b) => b.withKind('recv')),
                    ...c.searchBills(payb).map((Bill b) => b.withKind('pay')),
                  ],
                );
                return Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                  child: Text(
                    '${grouped(hits.length)} ${hits.length == 1 ? 'bill' : 'bills'} found',
                    style: rsStyle(context),
                  ),
                );
              },
            ),
            lazyList<Bill>(
              margin: const EdgeInsets.only(bottom: 14),
              rows: c.memo<List<Bill>>(
                'out-hub-search',
                '${c.repo.version}|${c.outQuery}|$rng|${c.range?.key}',
                () => <Bill>[
                  ...c.searchBills(recv).map((Bill b) => b.withKind('recv')),
                  ...c.searchBills(payb).map((Bill b) => b.withKind('pay')),
                ],
              ),
              row: (BuildContext context, Bill b) => _BillRow(c: c, b: b),
              empty: 'No pending bill matches “${c.outQuery.trim()}”.',
            ),
          ],
        ],
        for (final (
              String,
              String,
              String,
              String,
              num,
              String,
              String,
              num,
              String,
            )
            o
            in oc.rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: LRow(
              list: 'outCards',
              lk: o.$9,
              radius: 22,
              child: Tap(
                onTap: () {
                  if (!c.guardTap('outCards', o.$9)) return;
                  c.go('outList', <String, Object?>{
                    'outKind': o.$9,
                    'outFilter': 'all',
                  });
                },
                child: Glass(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Ico(o.$3, color: p.cat(o.$4), icon: IcSize.l),
                          const SizedBox(width: 12),
                          Expanded(child: RTx(o.$1, o.$2, titleSize: 20)),
                          const SizedBox(width: 12),
                          const Ic('chevR', color: kChev),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                Text('Total', style: rsStyle(context)),
                                const SizedBox(height: 2),
                                // Directly under "Total", left-aligned with it.
                                AmtText(
                                  inr(o.$5),
                                  align: Alignment.centerLeft,
                                  style: amtStyle(context, cls: o.$6),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.sizeOf(context).width * .38,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: <Widget>[
                                Bdg(o.$7),
                                const SizedBox(height: 4),
                                Bdg('${inr(o.$8)} late', kind: BadgeKind.bad),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (oc.hidden > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: HidRow('${oc.hidden} hidden · Unhide', onTap: oc.unhide),
          ),
        const H2Row('Due in the next 7 days', top: 10),
        if (soon.isEmpty)
          GlassList(
            children: <Widget>[
              EmptyBox(
                c.emptyText(DataSet.bills, 'Nothing due in the next 7 days.'),
              ),
            ],
          )
        else
          lazyList<Bill>(
            rows: soon,
            row: (BuildContext context, Bill b) => RowX(
              onTap: () => c.go('billDetail', <String, Object?>{'bill': b}),
              children: <Widget>[
                Ico(
                  b.kind == 'recv' ? 'in' : 'out',
                  size: IcoSize.xs,
                  color: p.cat(b.kind == 'recv' ? 'receipt' : 'payment'),
                  icon: IcSize.s,
                ),
                Expanded(child: RTx(b.party, '${b.no} · ${b.txt}', ell: true)),
                Text(
                  '${b.kind == 'recv' ? '+' : '−'}${inr(b.amt)}',
                  style: amtStyle(
                    context,
                    cls: b.kind == 'recv' ? 'in' : 'out',
                  ),
                ),
              ],
            ),
          ),
        if (c.activeReminders.isNotEmpty) ...<Widget>[
          const H2Row('Your reminders', top: 18),
          GlassList(
            children: <Widget>[
              for (final Reminder rm in c.activeReminders)
                Builder(
                  builder: (BuildContext context) {
                    final DateTime? d = rm.day;
                    final DateTime? at = rm.at;
                    final int left = d == null ? 1 : dayDiff(c.today, d);
                    // Overdue once its date AND time have passed.
                    final bool overdue =
                        at != null && at.isBefore(DateTime.now());
                    final bool recvR = rm.kind == 'recv';
                    return RowX(
                      onTap: () => c.openReminderBill(rm),
                      cross: CrossAxisAlignment.start,
                      children: <Widget>[
                        Ico(
                          'bell',
                          size: IcoSize.xs,
                          color: p.cat(recvR ? 'receipt' : 'payment'),
                          icon: IcSize.s,
                        ),
                        Expanded(
                          child: RTx(
                            rm.party,
                            <String>[
                              rm.billNo,
                              c.reminderWhen(rm),
                              if (rm.note.isNotEmpty) rm.note,
                            ].join(' · '),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.sizeOf(context).width * .4,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: <Widget>[
                              AmtText(
                                '${recvR ? '+' : '−'}${inr(rm.amount)}',
                                style: amtStyle(
                                  context,
                                  cls: recvR ? 'in' : 'out',
                                ),
                              ),
                              const SizedBox(height: 4),
                              Bdg(
                                overdue
                                    ? 'Overdue'
                                    : (left <= 0
                                          ? 'Due today'
                                          : 'In $left ${left == 1 ? 'day' : 'days'}'),
                                kind: overdue
                                    ? BadgeKind.bad
                                    : (left <= 0
                                          ? BadgeKind.warn
                                          : BadgeKind.ok),
                                dot: true,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class OutListScreen extends ConsumerWidget {
  const OutListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final bool isR = c.outKind == 'recv';
    // Date range on: only bills dated in it (totals of exactly those).
    final bool rng = c.outRange && c.range != null;
    final List<Bill> bl = c.inOutRange(
      isR ? c.repo.receivables() : c.repo.payables(),
    );
    final OutstandingSummary sm = rng
        ? summarise(bl, c.today)
        : c.repo.outstanding(isR);
    final num totO = sm.total, late30 = sm.late;
    int pct(num v) => totO <= 0 ? 0 : (v / totO * 100).round();
    final List<Bill> lateBills = bl.where((Bill b) => b.st == 'late').toList();
    // Paid / settled in Tally: own tab, never part of the totals above.
    final List<Bill> settled = c.inOutRange(c.repo.settledBills(isR));
    final bool showSettled = c.outFilter == 'settled';
    final List<(String, String)> of = <(String, String)>[
      ('all', 'All'),
      ('late', 'Late'),
      ('soon', 'Due soon'),
      ('ok', 'Later'),
      ('settled', 'Settled (${grouped(settled.length)})'),
    ];
    final List<(String, num, int, Color)> ageing = <(String, num, int, Color)>[
      ('Not due', sm.ageing[0], pct(sm.ageing[0]), p.pos),
      (
        'Overdue 1–30 days',
        sm.ageing[1],
        sm.ageing[1] > 0 ? pct(sm.ageing[1]).clamp(2, 100) : 0,
        p.warn,
      ),
      (
        'Overdue 31–60 days',
        sm.ageing[2],
        sm.ageing[2] > 0 ? pct(sm.ageing[2]).clamp(2, 100) : 0,
        p.neg,
      ),
      (
        'Overdue above 60 days',
        sm.ageing[3],
        sm.ageing[3] > 0 ? pct(sm.ageing[3]).clamp(2, 100) : 0,
        p.acc3,
      ),
    ];
    // Filtered / ordered once per data, filter or list-preference change.
    final ({List<Bill> rows, int hidden, VoidCallback unhide})
    v = c.memo<({List<Bill> rows, int hidden, VoidCallback unhide})>(
      'bills-view',
      '${c.repo.version}|${bl.length}|${settled.length}|${c.outKind}|${c.outFilter}|${c.prefsVersion}|${c.outQuery}|$rng|${c.range?.key}',
      () => c.listView<Bill>(
        'bills',
        c
            .searchBills(showSettled ? settled : bl)
            .where(
              (Bill b) =>
                  showSettled || c.outFilter == 'all' || b.st == c.outFilter,
            )
            .map((Bill b) => b.withKind(c.outKind))
            .toList(),
        (Bill b) => b.key,
      ),
    );
    final bool selecting = c.bSelecting;
    return Scr(
      bottomBar: selecting ? _BillSelectBar(c: c, rows: v.rows) : null,
      children: <Widget>[
        BackNav(
          actions: <Widget>[
            CBtn('search', onTap: c.toggleOutSearch),
            CBtn(
              'bell',
              dot: c.dueReminders.isNotEmpty,
              onTap: () => c.openOverlay('reminders'),
            ),
            CBtn(
              'calendar',
              key: const ValueKey<String>('outRangeBtn'),
              dot: rng,
              onTap: () => c.openRange('out'),
            ),
            CBtn(
              'file',
              onTap: () => c.previewDoc(
                docBills(
                  isR,
                  v.rows,
                  c.companyName,
                  c.today,
                  rng ? c.range!.label : null,
                ),
              ),
            ),
            CBtn('sync', onTap: c.refreshNow),
          ],
        ),
        H1(isR ? 'Receivable' : 'Payable', afterNav: true),
        Sub(
          isR
              ? 'Money customers owe you (Outstanding)'
              : 'Money you owe suppliers (Outstanding)',
        ),
        const PeriodBar(target: 'out'),
        if (c.outSearch) ...<Widget>[
          OutSearchBox(c: c),
          if (c.outQuery.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
              child: Text(
                '${grouped(v.rows.length)} of ${grouped(bl.length)} bills match',
                style: rsStyle(context),
              ),
            ),
        ],
        Glass(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Ico(
                    isR ? 'in' : 'out',
                    size: IcoSize.sm,
                    color: p.cat(isR ? 'receipt' : 'payment'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          isR ? 'Customers owe you' : 'You owe suppliers',
                          style: rsStyle(context),
                        ),
                        const SizedBox(height: 2),
                        AmtText(
                          inr(totO),
                          align: Alignment.centerLeft,
                          style: amtStyle(
                            context,
                            cls: isR ? 'big in' : 'big out',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    Bdg('${sm.parties} parties'),
                    Bdg('${inr(late30)} late', kind: BadgeKind.bad),
                    Bdg('As on ${dmy(c.today)}'),
                    if (sm.mismatch)
                      Bdg(
                        'Server total ${inr(sm.serverTotal)} differs',
                        kind: BadgeKind.warn,
                      ),
                  ],
                ),
              ),
              if (!isR)
                Btn(
                  label:
                      'Pay ${lateBills.length} late ${lateBills.length == 1 ? 'bill' : 'bills'}',
                  icon: 'out',
                  kind: BtnKind.g,
                  color: p.acc,
                  enabled: lateBills.isNotEmpty,
                  onTap: () {
                    if (lateBills.isEmpty) return;
                    final Bill b = c.repo.isRemote
                        ? lateBills.first
                        : (lateBills
                                  .where((Bill x) => x.no == 'PI-0002')
                                  .firstOrNull ??
                              lateBills.first);
                    c.startFlow('payment', <String, String>{
                      'yParty': b.party,
                      'yAmt': '${b.amt}',
                      'yRef': 'Against ${b.no}',
                    });
                  },
                ),
            ],
          ),
        ),
        // Receivables: email a customer a reminder of their pending bills.
        if (isR)
          GlassRow(
            key: const ValueKey<String>('outEmailRem'),
            margin: const EdgeInsets.only(top: 12),
            onTap: c.openEmailReminder,
            children: <Widget>[
              Ico('mail', size: IcoSize.xs, color: p.navy, icon: IcSize.s),
              Expanded(
                child: RTx(
                  'Email reminder',
                  c.emBlocked ?? 'Email a customer their pending bills',
                ),
              ),
              chevR(),
            ],
          ),
        if (!isR)
          GlassRow(
            margin: const EdgeInsets.only(top: 12),
            onTap: c.toggleAutoRemind,
            children: <Widget>[
              Ico('bell', size: IcoSize.xs, color: p.navy, icon: IcSize.s),
              Expanded(
                child: RTx(
                  'Payment alerts',
                  c.autoRemind
                      ? 'Alert me ${c.remRuleText(c.remSettings)}'
                      : 'Alerts are off',
                ),
              ),
              Sw(c.autoRemind),
            ],
          ),
        // What bill PDFs show: logo, fields, address — saved for this user
        // and company; a share can change it once.
        GlassRow(
          key: const ValueKey<String>('outBillLayoutRow'),
          margin: const EdgeInsets.only(top: 12),
          onTap: c.openBillLayout,
          children: <Widget>[
            Ico('file', size: IcoSize.xs, color: p.navy, icon: IcSize.s),
            const Expanded(
              child: RTx(
                'Bill PDF layout',
                'Logo, fields and address on shared bills',
              ),
            ),
            const Ic('chevR', color: kChev),
          ],
        ),
        Seg(
          margin: const EdgeInsets.only(top: 12, bottom: 0),
          items: const <String>['List', 'Graph'],
          selected: c.outView == 'graph' ? 1 : 0,
          onPick: (int i) =>
              c.update(() => c.outView = i == 1 ? 'graph' : 'list'),
        ),
        if (c.outView == 'list')
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Glass(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('Ageing', style: rtStyle(context, 17)),
                  ),
                  for (final (String, num, int, Color) a in ageing) ...<Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(a.$1, style: ts(14.5, h: 1.3, c: p.ink2)),
                        ),
                        Text(inr(a.$2), style: amtStyle(context, size: 14.5)),
                      ],
                    ),
                    Container(
                      height: 10,
                      margin: const EdgeInsets.fromLTRB(0, 6, 0, 12),
                      decoration: BoxDecoration(
                        color: navyA(.08),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: (a.$3 / 100).clamp(0, 1),
                        child: Container(
                          decoration: BoxDecoration(
                            color: a.$4,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        Chips(
          margin: const EdgeInsets.only(top: 14, bottom: 14),
          children: <Widget>[
            // Select several bills to share them together.
            if (c.outView == 'list')
              ChipBtn(
                selecting ? 'Done' : 'Select',
                key: const ValueKey<String>('bSelect'),
                icon: selecting ? 'close' : 'check',
                on: selecting,
                onTap: selecting ? c.endBillSelect : c.startBillSelect,
              ),
            for (final (String, String) x in of)
              ChipBtn(
                x.$2,
                on: c.outFilter == x.$1,
                onTap: () => c.update(() => c.outFilter = x.$1),
              ),
          ],
        ),
        if (showSettled)
          const InfoBox(
            'Bills paid or settled in Tally. They are not part of the '
            'outstanding total above.',
            icon: 'info',
          ),
        if (c.outView == 'graph' && !showSettled)
          _OutGraph(
            recv: isR,
            // Exactly the bills the list shows (same kind and filter).
            bills: bl
                .where((Bill b) => c.outFilter == 'all' || b.st == c.outFilter)
                .toList(),
          )
        else
          lazyList<Bill>(
            rows: v.rows,
            row: (BuildContext context, Bill b) => LRow(
              list: 'bills',
              lk: b.key,
              child: RowX(
                key: selecting ? ValueKey<String>('bPick-${b.key}') : null,
                onTap: () {
                  if (selecting) {
                    c.toggleBillPicked(b);
                    return;
                  }
                  if (c.guardTap('bills', b.key)) {
                    c.go('billDetail', <String, Object?>{'bill': b});
                  }
                },
                children: <Widget>[
                  if (selecting)
                    SizedBox(
                      width: 34,
                      height: 34,
                      child: Center(
                        child: SelectBox(checked: c.bPicked.containsKey(b.key)),
                      ),
                    )
                  else
                    Av(initials(b.party), size: Av.sm),
                  Expanded(
                    child: RTx(
                      b.party,
                      '${b.no} · ${b.city.isNotEmpty ? b.city : 'Due ${b.due}'}',
                      ell: true,
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      if (b.st == 'settled')
                        // Last pending amount when the server has it.
                        Text(
                          b.billAmt == null ? '—' : inr(b.billAmt),
                          style: amtStyle(context).copyWith(color: p.ink3),
                        )
                      else
                        Text(
                          '${isR ? '+' : '−'}${inr(b.amt)}',
                          style: amtStyle(context, cls: isR ? 'in' : 'out'),
                        ),
                      const SizedBox(height: 4),
                      Bdg(
                        b.txt,
                        kind: b.st == 'settled'
                            ? BadgeKind.info
                            : billKind(b.st),
                        dot: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            hidden: v.hidden,
            unhide: v.unhide,
            empty: c.outQuery.trim().isNotEmpty
                ? 'No ${showSettled ? 'settled' : 'pending'} bill matches “${c.outQuery.trim()}”.'
                : (showSettled
                      ? 'No settled bills yet.'
                      : c.emptyText(DataSet.bills, 'No pending bills.')),
          ),
      ],
    );
  }
}

/// Selecting bills (floating): how many / how much, Select all / Clear,
/// WhatsApp (one message), one list PDF or one PDF per bill.
class _BillSelectBar extends StatelessWidget {
  const _BillSelectBar({required this.c, required this.rows});
  final AppController c;
  final List<Bill> rows;

  @override
  Widget build(BuildContext context) {
    final int n = c.bPicked.length;
    final bool all =
        rows.isNotEmpty &&
        n >= rows.length &&
        rows.every((Bill b) => c.bPicked.containsKey(b.key));
    final Party? party = c.pickedBillParty;
    return BulkBar(
      key: const ValueKey<String>('bSelectBarFloat'),
      keyPrefix: 'bSelect',
      count: n,
      detail:
          '${inr(c.pickedBillsTotal)}${party != null ? ' · ${party.name}' : ''}',
      allSelected: all,
      selectAllLabel: 'Select all (${rows.length})',
      emptyText: 'Tap bills to select them',
      onSelectAll: () => c.selectAllBills(rows),
      onClear: c.clearBillPicked,
      onWhatsApp: c.whatsAppPickedBills,
      actions: <BulkAction>[
        BulkAction(
          'List',
          'file',
          c.sharePickedBillsList,
          key: const ValueKey<String>('bShareList'),
        ),
        BulkAction(
          'PDFs',
          'share',
          c.sharePickedBillsEach,
          key: const ValueKey<String>('bShareEach'),
        ),
        // One PDF each with a layout changed for this share only.
        BulkAction(
          'Layout',
          'edit',
          c.customizePickedBills,
          key: const ValueKey<String>('bShareCustom'),
        ),
      ],
    );
  }
}

/// Search field for outstanding bills (party, bill no., place, dates,
/// status, amount). Filters the bills already loaded.
class OutSearchBox extends StatelessWidget {
  const OutSearchBox({super.key, required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: VoiceSearchField(
        field: 'outQuery',
        value: c.outQuery,
        onChanged: c.setOutQuery,
        placeholder: 'Party, bill no., amount…',
        extra: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: c.toggleOutSearch,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(child: Ic('close', color: p.ink3)),
          ),
        ),
      ),
    );
  }
}

/// One search result row (receivable or payable).
class _BillRow extends StatelessWidget {
  const _BillRow({required this.c, required this.b});
  final AppController c;
  final Bill b;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final bool r = b.kind == 'recv';
    return RowX(
      onTap: () => c.go('billDetail', <String, Object?>{'bill': b}),
      children: <Widget>[
        Ico(
          r ? 'in' : 'out',
          size: IcoSize.xs,
          color: p.cat(r ? 'receipt' : 'payment'),
          icon: IcSize.s,
        ),
        Expanded(
          child: RTx(
            b.party,
            '${r ? 'Receivable' : 'Payable'} · ${b.no} · Due ${b.due}',
            ell: true,
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              '${r ? '+' : '−'}${inr(b.amt)}',
              style: amtStyle(context, cls: r ? 'in' : 'out'),
            ),
            const SizedBox(height: 4),
            Bdg(b.txt, kind: billKind(b.st), dot: true),
          ],
        ),
      ],
    );
  }
}

class BillDetailScreen extends ConsumerWidget {
  const BillDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final Bill? b0 = c.bill ?? c.repo.receivables().firstOrNull;
    if (b0 == null) {
      return const Scr(
        children: <Widget>[BackNav(), EmptyBox('No bill selected.')],
      );
    }
    final Bill b = b0;
    final bool r = b.kind == 'recv';
    // Paid / settled in Tally: nothing to collect, pay or remind.
    final bool settled = b.st == 'settled';
    final PdfInfo info = c.billPdfInfo(b);
    final ShareDoc invoice = docInvoice(info, c.companyName);
    final Reminder? rem = c.reminderFor(b);
    void share() => c.shareDoc(invoice);
    void pdf() => c.openPdf(info);
    Widget tile(String ic, String cc, String t, VoidCallback f) => Tap(
      onTap: f,
      child: Glass(
        child: Container(
          constraints: const BoxConstraints(minHeight: 100),
          padding: const EdgeInsets.fromLTRB(6, 16, 6, 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Ico(ic, size: IcoSize.xs, color: p.cat(cc), icon: IcSize.s),
              const SizedBox(height: 9),
              Text(
                t,
                textAlign: TextAlign.center,
                style: rtStyle(context, 13.5),
              ),
            ],
          ),
        ),
      ),
    );
    return FlowScr(
      foot: settled
          ? null
          : <Widget>[
              // Local reminder on this bill (receivable or payable).
              Expanded(
                flex: 10,
                child: Btn(
                  label: rem == null
                      ? 'Remind'
                      : 'Remind · ${rem.day == null ? rem.date : dm(rem.day!)}',
                  icon: 'bell',
                  kind: BtnKind.g,
                  onTap: () => c.openReminder(b),
                ),
              ),
              Expanded(
                flex: 17,
                child: Btn(
                  label: r ? 'Record Receipt' : 'Record Payment',
                  icon: r ? 'in' : 'out',
                  kind: BtnKind.a,
                  onTap: () => r
                      ? c.startFlow('receipt', <String, String>{
                          'rParty': b.party,
                          'rAmt': '${b.amt}',
                          'rRef': 'Against ${b.no}',
                        })
                      : c.startFlow('payment', <String, String>{
                          'yParty': b.party,
                          'yAmt': '${b.amt}',
                          'yRef': 'Against ${b.no}',
                        }),
                ),
              ),
            ],
      children: <Widget>[
        BackNav(actions: <Widget>[CBtn('share', onTap: share)]),
        const H1('Bill details', afterNav: true),
        Sub('${b.no} · ${r ? 'Sales' : 'Purchase'}'),
        Glass(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Av(initials(b.party)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(b.party, style: rtStyle(context, 18)),
                        const SizedBox(height: 2),
                        Row(
                          children: <Widget>[
                            Bdg(
                              r ? 'Customer' : 'Supplier',
                              kind: BadgeKind.acc,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                            ),
                            Text(
                              ' ${b.city.isNotEmpty ? b.city : 'Due ${b.due}'}',
                              style: rsStyle(context),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Container(
                height: 1,
                color: navyA(.08),
                margin: const EdgeInsets.symmetric(vertical: 14),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          settled
                              ? 'Last pending amount'
                              : (r ? 'Still to get' : 'Still to pay'),
                          style: rsStyle(context),
                        ),
                        AmtText(
                          settled
                              ? (b.billAmt == null ? '—' : inr(b.billAmt))
                              : inr(b.amt),
                          style: settled
                              ? amtStyle(context, cls: 'big')
                              : amtStyle(
                                  context,
                                  cls: r ? 'big in' : 'big out',
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * .38,
                    ),
                    child: Bdg(
                      b.txt,
                      kind: settled ? BadgeKind.info : billKind(b.st),
                      dot: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (settled)
          const InfoBox(
            'This bill is paid or settled in Tally, so it is not in the '
            'outstanding total.',
            icon: 'check',
            margin: EdgeInsets.only(top: 12),
          ),
        Sec('Bill PDF · ${b.no.replaceFirst(' ', '_')}.pdf'),
        Grid(
          cols: 3,
          gap: 10,
          children: <Widget>[
            tile('file', 'navy', 'See PDF', pdf),
            tile('share', 'sales', 'Share PDF', share),
            tile(
              'download',
              'purchase',
              'Download',
              () => c.downloadDoc(invoice),
            ),
          ],
        ),
        const Sec('Bill information'),
        KvList(<(String, String, bool)>[
          ('Bill number', b.no, false),
          ('Bill type', r ? 'Sales' : 'Purchase', false),
          ('Bill date', b.bill, false),
          ('Due date', b.due, false),
          ('Credit period', b.credit, false),
          if (!settled && b.billAmt != null && b.billAmt != b.amt)
            ('Bill amount', inr(b.billAmt), false),
          ('Status', b.txt, false),
        ]),
      ],
    );
  }
}

/// Graph view of the same outstanding bills as the list: ageing buckets or
/// party-wise outstanding, drawn with the report chart (bar / pie / line).
class _OutGraph extends ConsumerWidget {
  const _OutGraph({required this.recv, required this.bills});
  final bool recv;
  final List<Bill> bills;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final bool byAge = c.outChart != 'party';
    final OutstandingSummary sm = summarise(bills, c.today);
    final List<ChartPoint> pts;
    if (byAge) {
      const List<String> labels = <String>[
        'Not due',
        '1–30 days',
        '31–60 days',
        'Above 60 days',
      ];
      pts = <ChartPoint>[
        for (int i = 0; i < 4; i++) ChartPoint(labels[i], sm.ageing[i]),
      ];
    } else {
      final Map<String, num> by = sumByRupees(
        bills.map((Bill b) => (b.party, b.amt)),
      );
      final List<MapEntry<String, num>> sorted = by.entries.toList()
        ..sort(
          (MapEntry<String, num> a, MapEntry<String, num> b) =>
              b.value.compareTo(a.value),
        );
      // Top 8 parties; the rest are summed (real total, not dropped).
      final num rest = sumRupees(
        sorted.skip(8).map((MapEntry<String, num> e) => e.value),
      );
      pts = <ChartPoint>[
        for (final MapEntry<String, num> e in sorted.take(8))
          ChartPoint(e.key, paise(e.value)),
        if (rest > 0) ChartPoint('${sorted.length - 8} others', paise(rest)),
      ];
    }
    final String key =
        'out-${recv ? 'recv' : 'pay'}-${byAge ? 'age' : 'party'}';
    final ReportData data = ReportData(
      report: Report(
        key,
        'accounts',
        byAge ? 'Ageing' : 'By Party',
        recv ? 'Receivable' : 'Payable',
        'chart',
        recv ? 'receipt' : 'payment',
      ),
      rows: <ReportRow>[
        for (final ChartPoint x in pts)
          ReportRow(initials(x.label), x.label, '', inr(x.value), '', x.value),
      ],
      total: inr(sm.total),
      totalLabel: recv ? 'Customers owe you' : 'You owe suppliers',
      points: pts,
      lineFirst: false,
      period: 'As on ${dmy(c.today)}',
    );
    final bool empty = pts.every((ChartPoint x) => x.value <= 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Seg(
          margin: const EdgeInsets.only(bottom: 12),
          items: const <String>['By Ageing', 'By Party'],
          selected: byAge ? 0 : 1,
          onPick: (int i) =>
              c.update(() => c.outChart = i == 0 ? 'age' : 'party'),
        ),
        if (empty)
          EmptyBox(c.emptyText('bills', 'No pending bills to chart.'))
        else ...<Widget>[
          ReportChart(
            data: data,
            type: c.chartType[key] ?? 'bar',
            onType: (String t) => c.update(() => c.chartType[key] = t),
          ),
          // The chart's numbers, row by row.
          KvList(<(String, String, bool)>[
            for (final ChartPoint x in pts) (x.label, inr(x.value), false),
            ('Total', inr(sm.total), true),
          ], margin: const EdgeInsets.only(top: 12)),
          if (byAge)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
              child: Text(
                'Overdue days are counted from each bill\'s due date.',
                style: ts(12.5, c: p.ink3),
              ),
            ),
        ],
      ],
    );
  }
}
