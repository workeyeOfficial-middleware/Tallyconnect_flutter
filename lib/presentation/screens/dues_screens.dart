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
import '../widgets/common.dart';

class OutHubScreen extends ConsumerWidget {
  const OutHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final List<Bill> recv = c.repo.receivables(), payb = c.repo.payables();
    final OutstandingSummary rs = c.repo.outstanding(true),
        ps = c.repo.outstanding(false);
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
    return Scr(
      children: <Widget>[
        NavRow(
          children: <Widget>[
            CBtn('menu', onTap: () => c.openOverlay('menu')),
            const Spacer(),
            Bdg(
              c.repo.isRemote ? 'As on ${dmy(c.today)}' : 'Sample data',
              kind: BadgeKind.acc,
            ),
          ],
        ),
        const H1('Outstanding', afterNav: true),
        const Sub('Receivable and payable bills still to be settled'),
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
            in cards)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Tap(
              onTap: () => c.go('outList', <String, Object?>{
                'outKind': o.$9,
                'outFilter': 'all',
              }),
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
                              Text(
                                inr(o.$5),
                                textAlign: TextAlign.right,
                                style: amtStyle(context, cls: o.$6),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: <Widget>[
                            Bdg(o.$7),
                            const SizedBox(height: 4),
                            Bdg('${inr(o.$8)} late', kind: BadgeKind.bad),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        const H2Row('Due in the next 7 days', top: 10),
        GlassList(
          children: <Widget>[
            for (final Bill b in soon)
              RowX(
                onTap: () => c.go('billDetail', <String, Object?>{'bill': b}),
                children: <Widget>[
                  Ico(
                    b.kind == 'recv' ? 'in' : 'out',
                    size: IcoSize.xs,
                    color: p.cat(b.kind == 'recv' ? 'receipt' : 'payment'),
                    icon: IcSize.s,
                  ),
                  Expanded(
                    child: RTx(b.party, '${b.no} · ${b.txt}', ell: true),
                  ),
                  Text(
                    '${b.kind == 'recv' ? '+' : '−'}${inr(b.amt)}',
                    style: amtStyle(
                      context,
                      cls: b.kind == 'recv' ? 'in' : 'out',
                    ),
                  ),
                ],
              ),
            if (soon.isEmpty)
              EmptyBox(
                c.emptyText(DataSet.bills, 'Nothing due in the next 7 days.'),
              ),
          ],
        ),
        if (c.companyReminders.isNotEmpty) ...<Widget>[
          const H2Row('Your reminders', top: 18),
          GlassList(
            children: <Widget>[
              for (final Reminder rm in c.companyReminders)
                Builder(
                  builder: (BuildContext context) {
                    final DateTime? d = rm.day;
                    final int left = d == null ? 1 : dayDiff(c.today, d);
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
                              d == null ? rm.date : dmy(d),
                              if (rm.note.isNotEmpty) rm.note,
                            ].join(' · '),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: <Widget>[
                            Text(
                              '${recvR ? '+' : '−'}${inr(rm.amount)}',
                              style: amtStyle(
                                context,
                                cls: recvR ? 'in' : 'out',
                              ),
                            ),
                            const SizedBox(height: 4),
                            Bdg(
                              left < 0
                                  ? 'Overdue'
                                  : (left == 0
                                        ? 'Due today'
                                        : 'In $left ${left == 1 ? 'day' : 'days'}'),
                              kind: left < 0
                                  ? BadgeKind.bad
                                  : (left == 0 ? BadgeKind.warn : BadgeKind.ok),
                              dot: true,
                            ),
                          ],
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
    final List<Bill> bl = isR ? c.repo.receivables() : c.repo.payables();
    final OutstandingSummary sm = c.repo.outstanding(isR);
    final num totO = sm.total, late30 = sm.late;
    int pct(num v) => totO <= 0 ? 0 : (v / totO * 100).round();
    final List<Bill> lateBills = bl.where((Bill b) => b.st == 'late').toList();
    final int lateParties = lateBills
        .map((Bill b) => b.ledgerGuid ?? b.party)
        .toSet()
        .length;
    const List<(String, String)> of = <(String, String)>[
      ('all', 'All'),
      ('late', 'Late'),
      ('soon', 'Due soon'),
      ('ok', 'Later'),
    ];
    final List<(String, num, int, Color)> ageing = <(String, num, int, Color)>[
      ('On time (not due yet)', sm.ageing[0], pct(sm.ageing[0]), p.pos),
      (
        '1–30 days late',
        sm.ageing[1],
        sm.ageing[1] > 0 ? pct(sm.ageing[1]).clamp(2, 100) : 0,
        p.warn,
      ),
      (
        '31–60 days late',
        sm.ageing[2],
        sm.ageing[2] > 0 ? pct(sm.ageing[2]).clamp(2, 100) : 0,
        p.neg,
      ),
      (
        'More than 60 days late',
        sm.ageing[3],
        sm.ageing[3] > 0 ? pct(sm.ageing[3]).clamp(2, 100) : 0,
        p.acc3,
      ),
    ];
    final ({List<Bill> rows, int hidden, VoidCallback unhide}) v = c
        .listView<Bill>(
          'bills',
          bl
              .where((Bill b) => c.outFilter == 'all' || b.st == c.outFilter)
              .map((Bill b) => b.withKind(c.outKind))
              .toList(),
          (Bill b) => b.key,
        );
    return Scr(
      children: <Widget>[
        BackNav(
          actions: <Widget>[
            CBtn(
              'file',
              onTap: () =>
                  c.previewDoc(docBills(isR, v.rows, c.companyName, c.today)),
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
                        Text(
                          inr(totO),
                          textAlign: TextAlign.right,
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
              Btn(
                label: isR
                    ? 'Send reminders to $lateParties late customers'
                    : 'Pay ${lateBills.length} late bills',
                icon: isR ? 'chat' : 'out',
                kind: BtnKind.g,
                color: p.acc,
                enabled: lateBills.isNotEmpty,
                onTap: isR
                    ? () => c.say(
                        c.repo.isRemote
                            ? 'WhatsApp reminders are not available yet on the server'
                            : 'WhatsApp reminders sent to $lateParties customers',
                      )
                    : () {
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
        GlassRow(
          margin: const EdgeInsets.only(top: 12),
          onTap: () => c.update(() => c.autoRemind = !c.autoRemind),
          children: <Widget>[
            Ico('bell', size: IcoSize.xs, color: p.navy, icon: IcSize.s),
            Expanded(
              child: RTx(
                isR ? 'Auto reminders' : 'Payment alerts',
                isR
                    ? (c.autoRemind
                          ? 'WhatsApp reminders are on'
                          : 'Reminders are off')
                    : (c.autoRemind
                          ? 'Alert me 3 days before due'
                          : 'Alerts are off'),
              ),
            ),
            Sw(c.autoRemind),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Glass(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('How late?', style: rtStyle(context, 17)),
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
          margin: const EdgeInsets.only(top: 4, bottom: 14),
          children: <Widget>[
            for (final (String, String) x in of)
              ChipBtn(
                x.$2,
                on: c.outFilter == x.$1,
                onTap: () => c.update(() => c.outFilter = x.$1),
              ),
          ],
        ),
        GlassList(
          children: <Widget>[
            for (final Bill b in v.rows)
              LRow(
                list: 'bills',
                lk: b.key,
                child: RowX(
                  onTap: () {
                    if (c.guardTap('bills', b.key)) {
                      c.go('billDetail', <String, Object?>{'bill': b});
                    }
                  },
                  children: <Widget>[
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
                        Text(
                          '${isR ? '+' : '−'}${inr(b.amt)}',
                          style: amtStyle(context, cls: isR ? 'in' : 'out'),
                        ),
                        const SizedBox(height: 4),
                        Bdg(b.txt, kind: billKind(b.st), dot: true),
                      ],
                    ),
                  ],
                ),
              ),
            if (v.hidden > 0)
              HidRow('${v.hidden} hidden · Unhide', onTap: v.unhide),
            if (v.rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  c.emptyText(DataSet.bills, 'No pending bills.'),
                  textAlign: TextAlign.center,
                  style: rsStyle(context, 15),
                ),
              ),
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
    final PdfInfo info = PdfInfo(
      party: b.party,
      no: b.no,
      date: b.bill,
      due: b.due,
      total: b.billAmt ?? b.amt,
      kind: r ? 'Sales bill' : 'Purchase bill',
      city: b.city,
      recv: r,
      lines: b.lines.isNotEmpty ? b.lines : c.repo.billLines(b.key),
    );
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
      foot: <Widget>[
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
        Sub('${b.no} · ${r ? 'Sales bill' : 'Purchase bill'}'),
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
                          r ? 'Still to get' : 'Still to pay',
                          style: rsStyle(context),
                        ),
                        Text(
                          inr(b.amt),
                          textAlign: TextAlign.right,
                          style: amtStyle(
                            context,
                            cls: r ? 'big in' : 'big out',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Bdg(b.txt, kind: billKind(b.st), dot: true),
                ],
              ),
            ],
          ),
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
          ('Bill type', r ? 'Sales bill' : 'Purchase bill', false),
          ('Bill date', b.bill, false),
          ('Pay by', b.due, false),
          ('Credit time', b.credit, false),
          if (b.billAmt != null && b.billAmt != b.amt)
            ('Bill amount', inr(b.billAmt), false),
          ('Status', b.txt, false),
        ]),
      ],
    );
  }
}
