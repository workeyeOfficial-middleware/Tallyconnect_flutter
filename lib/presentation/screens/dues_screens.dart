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
import '../../data/models/models.dart';
import '../widgets/common.dart';

class OutHubScreen extends ConsumerWidget {
  const OutHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final List<Bill> recv = c.repo.receivables(), payb = c.repo.payables();
    final List<
      (String, String, String, String, int, String, String, int, String)
    >
    cards =
        <(String, String, String, String, int, String, String, int, String)>[
          (
            'To get',
            'Others owe you (Receivable)',
            'in',
            'receipt',
            348690,
            'big in',
            '6 parties',
            113870,
            'recv',
          ),
          (
            'To give',
            'You owe others (Payable)',
            'out',
            'payment',
            126850,
            'big out',
            '5 parties',
            17700,
            'pay',
          ),
        ];
    final List<Bill> soon = <Bill>[
      recv[4],
      payb[0].withKind('pay'),
      payb[2].withKind('pay'),
      recv[5],
    ];
    return Scr(
      children: <Widget>[
        NavRow(
          children: <Widget>[
            CBtn('menu', onTap: () => c.openOverlay('menu')),
            const Spacer(),
            const Bdg('Sample data', kind: BadgeKind.acc),
          ],
        ),
        const H1('Money due', afterNav: true),
        const Sub('Money still to be settled (Outstanding)'),
        for (final (
              String,
              String,
              String,
              String,
              int,
              String,
              String,
              int,
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
          ],
        ),
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
    final int onTime = isR ? 234820 : 109150,
        late30 = isR ? 113870 : 17700,
        totO = isR ? 348690 : 126850;
    const List<(String, String)> of = <(String, String)>[
      ('all', 'All'),
      ('late', 'Late'),
      ('soon', 'Due soon'),
      ('ok', 'Later'),
    ];
    final List<(String, int, int, Color)> ageing = <(String, int, int, Color)>[
      ('On time (not due yet)', onTime, (onTime / totO * 100).round(), p.pos),
      (
        '1–30 days late',
        late30,
        (late30 / totO * 100).round().clamp(2, 100),
        p.warn,
      ),
      ('31–60 days late', 0, 0, p.neg),
      ('More than 60 days late', 0, 0, p.acc3),
    ];
    final ({List<Bill> rows, int hidden, VoidCallback unhide}) v = c
        .listView<Bill>(
          'bills',
          bl
              .where((Bill b) => c.outFilter == 'all' || b.st == c.outFilter)
              .map((Bill b) => b.withKind(c.outKind))
              .toList(),
          (Bill b) => b.no,
        );
    return Scr(
      children: <Widget>[
        BackNav(
          actions: <Widget>[
            CBtn(
              'file',
              onTap: () => c.previewDoc(docBills(isR, v.rows, c.companyName)),
            ),
            CBtn('sync', onTap: c.refreshNow),
          ],
        ),
        H1(isR ? 'To get' : 'To give', afterNav: true),
        Sub(
          isR
              ? 'Money others owe you (Receivable)'
              : 'Money you owe others (Payable)',
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
                          isR ? 'Others owe you' : 'You owe others',
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
                    Bdg('${bl.length} parties'),
                    Bdg('${inr(late30)} late', kind: BadgeKind.bad),
                    const Bdg('As on 26 Sep 2026'),
                  ],
                ),
              ),
              Btn(
                label: isR
                    ? 'Send reminders to 2 late customers'
                    : 'Pay 2 late bills',
                icon: isR ? 'chat' : 'out',
                kind: BtnKind.g,
                color: p.acc,
                onTap: isR
                    ? () => c.say('WhatsApp reminders sent to 2 customers')
                    : () => c.startFlow('payment', <String, String>{
                        'yParty': 'Anchor Electricals',
                        'yAmt': '11800',
                        'yRef': 'Against PI-0002',
                      }),
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
                for (final (String, int, int, Color) a in ageing) ...<Widget>[
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
                lk: b.no,
                child: RowX(
                  onTap: () {
                    if (c.guardTap('bills', b.no)) {
                      c.go('billDetail', <String, Object?>{'bill': b});
                    }
                  },
                  children: <Widget>[
                    Av(initials(b.party), size: Av.sm),
                    Expanded(
                      child: RTx(b.party, '${b.no} · ${b.city}', ell: true),
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
    final Bill b = c.bill ?? c.repo.receivables().first;
    final bool r = b.kind == 'recv';
    final PdfInfo info = PdfInfo(
      party: b.party,
      no: b.no,
      date: b.bill,
      due: b.due,
      total: b.amt,
      kind: r ? 'Sales bill' : 'Purchase bill',
      city: b.city,
      recv: r,
    );
    final ShareDoc invoice = docInvoice(
      info,
      c.companyName,
      c.repo.billLines(b.no),
    );
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
        if (r)
          Expanded(
            flex: 10,
            child: Btn(
              label: 'Remind',
              icon: 'chat',
              kind: BtnKind.g,
              onTap: () => c.say('Reminder sent on WhatsApp to ${b.party}'),
            ),
          ),
        Expanded(
          flex: 17,
          child: Btn(
            label: r ? 'Record Money In' : 'Record Money Out',
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
                            Text(' ${b.city}', style: rsStyle(context)),
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
        ]),
      ],
    );
  }
}
