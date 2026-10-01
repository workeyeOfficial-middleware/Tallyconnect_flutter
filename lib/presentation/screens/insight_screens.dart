// REPORTS (1110–1137), REPORT DETAIL (1139–1151), ACTIVITY (1153–1182),
// ACTIVITY DETAIL (1184–1200), SALES TEAM (1202–1226).
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
import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import '../widgets/common.dart';
import 'stock_party_screens.dart' show StatBox;
import 'voucher_screens.dart' show monthSums;

const List<(String, String)> kRC = <(String, String)>[
  ('all', 'All'),
  ('sales', 'Sales'),
  ('party', 'Party'),
  ('stock', 'Stock'),
  ('accounts', 'Accounts'),
];

String stockValue(AppController c) =>
    inr(c.repo.items().fold<int>(0, (int s, Item x) => s + x.stock * x.rate));

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final Map<String, String> rv = <String, String>{
      'top': 'Shree Balaji Traders',
      'exp': inr(186450),
      'inC': '2 customers',
      'inI': '2 items',
      'day': '21 entries',
      'sreg': inr(348690),
      'preg': inr(126850),
      'stock': stockValue(c),
    };
    final ({List<Report> rows, int hidden, VoidCallback unhide}) v = c
        .listView<Report>(
          'reports',
          c.repo
              .reports()
              .where((Report r) => c.repCat == 'all' || r.cat == c.repCat)
              .toList(),
          (Report r) => r.id,
        );
    return Scr(
      children: <Widget>[
        NavRow(
          children: <Widget>[
            CBtn('menu', onTap: () => c.openOverlay('menu')),
            const Spacer(),
            CBtn('search', onTap: () => c.openOverlay('search')),
            CBtn('sync', onTap: c.refreshNow),
          ],
        ),
        const H1('Reports'),
        Sub('Easy views of your Tally data · ${c.companyName}'),
        Glass(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              LtBadge(Text('September 2026', style: rtStyle(context))),
              Grid(cols: 2, children: monthSums(context, c)),
            ],
          ),
        ),
        Chips(
          margin: const EdgeInsets.only(top: 18, bottom: 14),
          children: <Widget>[
            for (final (String, String) x in kRC)
              ChipBtn(
                x.$2,
                on: c.repCat == x.$1,
                onTap: () => c.update(() => c.repCat = x.$1),
              ),
          ],
        ),
        Grid(
          cols: 2,
          children: <Widget>[
            for (final Report r in v.rows)
              LRow(
                list: 'reports',
                lk: r.id,
                radius: 22,
                child: Tap(
                  onTap: () {
                    if (c.guardTap('reports', r.id)) {
                      c.go('report', <String, Object?>{'report': r.id});
                    }
                  },
                  child: Glass(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 150),
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Ico(r.ic, size: IcoSize.sm, color: p.cat(r.c)),
                          const SizedBox(height: 12),
                          Text(r.t, style: rtStyle(context)),
                          const SizedBox(height: 2),
                          Text(
                            rv[r.id] ?? '',
                            style: ts(15, w: w700, h: 1.25, c: p.cat(r.c)),
                          ),
                          const SizedBox(height: 2),
                          Text(r.s, style: rsStyle(context)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (v.hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: HidRow(
              '${v.hidden} hidden · Unhide',
              onTap: v.unhide,
              inGrid: true,
            ),
          ),
      ],
    );
  }
}

class ReportScreen extends ConsumerWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final Report r0 =
        c.repo.reports().where((Report r) => r.id == c.report).firstOrNull ??
        c.repo.reports().first;
    final List<Color> av = <Color>[
      p.navy2,
      p.cat('sales'),
      p.cat('reports'),
      p.cat('items'),
      p.acc,
    ];
    List<(String, String, String, String, String)> rows; // n, t, s, v, cls
    String tot, tl = 'Total';
    final List<Bill> recv = c.repo.receivables();
    final List<Voucher> vs = c.repo.vouchers();
    final List<Item> items = c.repo.items();
    switch (r0.id) {
      case 'top':
        final List<Bill> top = List<Bill>.of(recv)
          ..sort((Bill a, Bill b) => b.amt - a.amt);
        final List<Bill> t5 = top.take(5).toList();
        rows = <(String, String, String, String, String)>[
          for (int i = 0; i < t5.length; i++)
            (
              '${i + 1}',
              t5[i].party,
              '${t5[i].city} · ${t5[i].no}',
              inr(t5[i].amt),
              'in',
            ),
        ];
        tot = inr(t5.fold<int>(0, (int s, Bill x) => s + x.amt));
        tl = 'Top 5 owe you';
      case 'exp':
        const List<(String, String, int)> e = <(String, String, int)>[
          ('Salaries A/c', 'Indirect expense', 120000),
          ('Rent A/c', 'Indirect expense', 35000),
          ('Depreciation A/c', 'Indirect expense', 24500),
          ('Freight Charges', 'Direct expense', 6950),
        ];
        rows = <(String, String, String, String, String)>[
          for (int i = 0; i < e.length; i++)
            ('${i + 1}', e[i].$1, e[i].$2, inr(e[i].$3), 'out'),
        ];
        tot = inr(186450);
        tl = 'All expenses · Sep';
      case 'inC':
        rows = <(String, String, String, String, String)>[
          for (final Party x in c.repo.parties().where(
            (Party x) => x.type == 'c' && x.bal == 0,
          ))
            (
              initials(x.name),
              x.name,
              '${x.city} · no sale in 60 days',
              '—',
              '',
            ),
        ];
        tot = '2';
        tl = 'Quiet customers';
      case 'inI':
        rows = <(String, String, String, String, String)>[
          for (final Item x in items.where((Item x) => x.st == 'out'))
            (
              initials(x.name),
              x.name,
              'Finished · not sold this month',
              inr(0),
              '',
            ),
        ];
        tot = '2';
        tl = 'Items not moving';
      case 'day':
        final List<Voucher> d = List<Voucher>.of(vs)
          ..sort((Voucher a, Voucher b) => b.day - a.day);
        rows = <(String, String, String, String, String)>[
          for (final Voucher v in d)
            (
              '${v.day}',
              v.party,
              '${kKinds[v.kind]!.t} · ${v.no}',
              inr(v.amt),
              '',
            ),
        ];
        tot = inr(918490);
        tl = '21 entries · value';
      case 'sreg':
      case 'preg':
        final String kk = r0.id == 'sreg' ? 'sales' : 'purchase';
        final List<Voucher> l2 = vs.where((Voucher v) => v.kind == kk).toList();
        rows = <(String, String, String, String, String)>[
          for (final Voucher v in l2)
            ('${v.day}', v.party, '${v.no} · ${v.day} Sep', inr(v.amt), ''),
        ];
        tot = inr(l2.fold<int>(0, (int s, Voucher v) => s + v.amt));
        tl = '${l2.length} bills';
      default:
        rows = <(String, String, String, String, String)>[
          for (final Item x in items)
            (
              initials(x.name),
              x.name,
              '${x.stock} ${x.unit} × ${inr(x.rate)}',
              inr(x.stock * x.rate),
              '',
            ),
        ];
        tot = stockValue(c);
        tl = 'Stock value';
    }
    return Scr(
      children: <Widget>[
        BackNav(
          actions: <Widget>[CBtn('share', onTap: () => c.say('Report shared'))],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: <Widget>[
              Ico(r0.ic, color: p.cat(r0.c), icon: IcSize.l),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    H1(r0.t, size: 28, margin: EdgeInsets.zero),
                    const SizedBox(height: 2),
                    Text('${r0.s} · September 2026', style: rsStyle(context)),
                  ],
                ),
              ),
            ],
          ),
        ),
        GlassRow(
          margin: const EdgeInsets.only(top: 18),
          minHeight: 64,
          children: <Widget>[
            Expanded(child: Text(tl, style: rsStyle(context))),
            Text(tot, style: amtStyle(context, size: 22)),
          ],
        ),
        GlassList(
          margin: const EdgeInsets.only(top: 12),
          children: <Widget>[
            for (int i = 0; i < rows.length; i++)
              RowX(
                children: <Widget>[
                  Av(
                    rows[i].$1,
                    size: Av.sm,
                    gradient: LinearGradient(
                      colors: <Color>[av[i % av.length], av[i % av.length]],
                    ),
                  ),
                  Expanded(child: RTx(rows[i].$2, rows[i].$3, ell: true)),
                  Text(rows[i].$4, style: amtStyle(context, cls: rows[i].$5)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

const Map<String, (String, BadgeKind)> kStMeta = <String, (String, BadgeKind)>{
  'ok': ('Sent', BadgeKind.ok),
  'wait': ('Waiting', BadgeKind.warn),
  'fail': ('Not sent', BadgeKind.bad),
};

class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    const List<(String, String)> af = <(String, String)>[
      ('all', 'All'),
      ('sales', 'Sales'),
      ('purchase', 'Purchase'),
      ('receipt', 'Money In'),
      ('payment', 'Money Out'),
      ('journal', 'Adjustment'),
    ];
    final ({List<Act> rows, int hidden, VoidCallback unhide}) v = c
        .listView<Act>(
          'acts',
          c.acts
              .where((Act a) => c.actFilter == 'all' || a.kind == c.actFilter)
              .toList(),
          (Act a) => a.id,
        );
    int count(String s) => c.acts.where((Act a) => a.status == s).length;
    return Scr(
      children: <Widget>[
        NavRow(
          children: <Widget>[
            CBtn('menu', onTap: () => c.openOverlay('menu')),
            const Spacer(),
            CBtn('bell', onTap: () => c.go('notifs')),
            CBtn('sync', onTap: c.syncAll),
          ],
        ),
        const TitleBadge('Activity'),
        const Sub('Entries on their way to Tally'),
        Glass(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Ico('laptop', size: IcoSize.sm, color: p.cat('receipt')),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const LiveDot(),
                            const SizedBox(width: 6),
                            Text('Tally connected', style: rtStyle(context)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'RAJESH-PC · ${c.companyName} · checks every 5 min',
                          style: rsStyle(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Grid(
                cols: 3,
                gap: 10,
                children: <Widget>[
                  StatBox('${count('ok')}', 'Sent', kind: 'c', color: p.pos),
                  StatBox(
                    '${count('wait')}',
                    'Waiting',
                    kind: 'b',
                    color: p.warn,
                  ),
                  StatBox(
                    '${count('fail')}',
                    'Not sent',
                    kind: 'n',
                    color: p.neg,
                  ),
                ],
              ),
            ],
          ),
        ),
        Chips(
          margin: const EdgeInsets.only(top: 18, bottom: 14),
          children: <Widget>[
            for (final (String, String) x in af)
              ChipBtn(
                x.$2,
                on: c.actFilter == x.$1,
                onTap: () => c.update(() => c.actFilter = x.$1),
              ),
          ],
        ),
        GlassList(
          children: <Widget>[
            for (final Act a in v.rows)
              LRow(
                list: 'acts',
                lk: a.id,
                child: RowX(
                  cross: CrossAxisAlignment.start,
                  children: <Widget>[
                    Ico(
                      kKinds[a.kind]!.ic,
                      size: IcoSize.xs,
                      color: p.cat(kKinds[a.kind]!.c),
                      icon: IcSize.s,
                    ),
                    Expanded(
                      child: Tap(
                        onTap: () {
                          if (c.guardTap('acts', a.id)) {
                            c.go('actDetail', <String, Object?>{'act': a.id});
                          }
                        },
                        radius: 12,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    '${kKinds[a.kind]!.t} · ${a.no}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: rtStyle(context),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(a.time, style: rsStyle(context)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${a.party} · ${inr(a.amt)}',
                              style: rsStyle(context),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: <Widget>[
                                Bdg(
                                  kStMeta[a.status]!.$1,
                                  kind: kStMeta[a.status]!.$2,
                                  dot: true,
                                ),
                                Text(
                                  a.note.isNotEmpty
                                      ? a.note
                                      : (a.status == 'wait'
                                            ? 'Waiting for Tally to open'
                                            : ''),
                                  style: rsStyle(context, 12.5),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (a.status == 'fail')
                      ChipBtn(
                        'Try again',
                        height: 38,
                        fontSize: 13.5,
                        color: p.navy,
                        onTap: () => c.retry(a.id),
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
                  'Nothing here.',
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

class ActDetailScreen extends ConsumerWidget {
  const ActDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final Act a0 =
        c.acts.where((Act a) => a.id == c.act).firstOrNull ?? c.acts.first;
    final Kind k = kKinds[a0.kind]!;
    final (String, BadgeKind) m = kStMeta[a0.status]!;
    final Color stColor = a0.status == 'ok'
        ? p.pos
        : (a0.status == 'wait' ? p.warn : p.neg);
    final bool s11 = a0.no == 'Sales 11';
    final List<(String, String, bool)> rows = s11
        ? const <(String, String, bool)>[
            ('Entry number', 'Sales 11', false),
            ('Date', '26 Sep 2026', false),
            ('Pay by', '11 Oct 2026', false),
            ('Paid by', 'Cash · ₹5,000 received', false),
            ('Reference no.', 'MOBILE-1790574691025', false),
            ('Party GSTIN', '27AAQFO5582D1Z1', false),
            ('Place of supply', 'Maharashtra (27)', false),
            ('Status', 'Part paid · ₹5,000 received', false),
          ]
        : <(String, String, bool)>[
            ('Entry number', a0.no, false),
            ('Party / account', a0.party, false),
            ('Amount', inr(a0.amt), false),
            ('Saved', a0.time, false),
            ('Status', m.$1, false),
          ];
    final String banner = a0.status == 'ok'
        ? 'Reached Tally'
        : (a0.status == 'fail'
              ? 'Not sent — ${a0.note.isNotEmpty ? a0.note : 'Tally was closed'}'
              : 'Waiting for Tally · will send by itself when Tally is open');
    return Scr(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Glass(
            radius: 26,
            padding: const EdgeInsets.all(16),
            gradient: LinearGradient(
              begin: const Alignment(-.5, -1),
              end: const Alignment(.5, 1),
              colors: <Color>[
                mixWith(p.acc, .16, whiteA(.62)),
                mixWith(p.navy2, .10, whiteA(.4)),
              ],
            ),
            border: Border.all(color: whiteA(.82)),
            shadows: <BoxShadow>[css(0, 20, 38, -20, mix(p.acc3, .40))],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    CBtn('chevL', onTap: c.back),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(k.long, style: rtStyle(context, 18)),
                          Opacity(
                            opacity: .85,
                            child: Text(
                              'Entry no: ${a0.no}',
                              style: ts(13, c: p.ink),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Bdg(m.$1.toUpperCase(), bg: Colors.white, fg: stColor),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    PlusTile(
                      icon: k.ic,
                      size: 46,
                      radius: 15,
                      icSize: IcSize.m,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            inr(a0.amt),
                            style: ts(30, w: w800, ls: -.6, c: p.ink),
                          ),
                          Opacity(
                            opacity: .9,
                            child: Text(
                              a0.party,
                              style: ts(15, w: w600, c: p.ink),
                            ),
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
        Banner2(
          banner,
          ok: a0.status == 'ok',
          icon: a0.status == 'ok'
              ? 'check'
              : (a0.status == 'fail' ? 'xCircle' : 'sync'),
        ),
        const Sec('Entry details', margin: EdgeInsets.fromLTRB(8, 4, 8, 8)),
        KvList(rows),
        if (s11) ...<Widget>[
          const Sec('Items'),
          GlassList(
            children: <Widget>[
              for (final (String, String, int) x
                  in const <(String, String, int)>[
                    (
                      '1. Havells FR Wire 1.5 sq mm (90 m)',
                      'Qty: 2 coil · Rate: ₹1,850 · GST 18% · HSN 8544',
                      3700,
                    ),
                    (
                      '2. Anchor Roma Switch 6A',
                      'Qty: 100 pcs · Rate: ₹34 · GST 18% · HSN 8536',
                      3400,
                    ),
                    (
                      '3. Polycab LED Panel 18W',
                      'Qty: 10 pcs · Rate: ₹520 · GST 18% · HSN 9405',
                      5200,
                    ),
                  ])
                RowX(
                  children: <Widget>[
                    Expanded(child: RTx(x.$1, x.$2)),
                    Text(inr(x.$3), style: amtStyle(context)),
                  ],
                ),
            ],
          ),
        ],
        if (a0.status == 'fail')
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Btn(
              label: 'Try sending again',
              icon: 'sync',
              onTap: () => c.retry(a0.id),
            ),
          ),
      ],
    );
  }
}

const Map<String, (String, BadgeKind)> kTS = <String, (String, BadgeKind)>{
  'active': ('Active', BadgeKind.ok),
  'pending': ('Invite sent', BadgeKind.warn),
  'off': ('Turned off', BadgeKind.info),
};

class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final String q = c.f('teamQ').toLowerCase();
    final List<Member> trows = c.team
        .where(
          (Member m) =>
              (c.teamFilter == 'all' || m.st == c.teamFilter) &&
              (q.isEmpty || '${m.name} ${m.email}'.toLowerCase().contains(q)),
        )
        .toList();
    final ({List<Member> rows, int hidden, VoidCallback unhide}) v = c
        .listView<Member>('team', trows, (Member m) => m.email);
    const List<(String, String)> segs = <(String, String)>[
      ('all', 'All'),
      ('active', 'Active'),
      ('pending', 'Pending'),
      ('off', 'Off'),
    ];
    final List<(String, int, String, String)> stats =
        <(String, int, String, String)>[
          ('Total', c.team.length, 'team', 'team'),
          (
            'Active',
            c.team.where((Member m) => m.st == 'active').length,
            'check',
            'receipt',
          ),
          (
            'Pending',
            c.team.where((Member m) => m.st == 'pending').length,
            'clock',
            'payment',
          ),
          (
            'Off',
            c.team.where((Member m) => m.st == 'off').length,
            'lock',
            'settings',
          ),
        ];
    void invite() => c.update(() {
      c.overlay = 'invite';
      c.form['iEmail'] = '';
    });
    void create() => c.update(() {
      c.overlay = 'newUser';
      c.form['nuName'] = '';
      c.form['nuPhone'] = '';
    });
    return Scr(
      children: <Widget>[
        NavRow(
          children: <Widget>[
            CBtn('menu', onTap: () => c.openOverlay('menu')),
            const Spacer(),
            CBtn('mail', onTap: invite),
            CBtn('userPlus', onTap: create),
          ],
        ),
        const TitleBadge('Sales Team'),
        const Sub('Add people and send invites'),
        Grid(
          cols: 4,
          gap: 10,
          children: <Widget>[
            for (final (String, int, String, String) s in stats)
              StatBox(
                '${s.$2}',
                s.$1,
                glass: true,
                top: Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Ico(
                    s.$3,
                    size: IcoSize.xs,
                    box: 32,
                    radius: 10,
                    color: p.cat(s.$4),
                    icon: IcSize.xs,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Grid(
          cols: 2,
          children: <Widget>[
            Tap(
              onTap: create,
              radius: 26,
              child: HeroBox(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const PlusTile(
                      icon: 'userPlus',
                      size: 44,
                      radius: 14,
                      icSize: IcSize.m,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Add person',
                      style: ts(17, w: w800, c: p.acc3),
                    ),
                    const SizedBox(height: 10),
                    Text('Make their login now', style: ts(14, c: p.ink2)),
                  ],
                ),
              ),
            ),
            Tap(
              onTap: invite,
              child: Glass(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Ico(
                      'mail',
                      size: IcoSize.xs,
                      color: p.navy,
                      icon: IcSize.s,
                    ),
                    const SizedBox(height: 10),
                    Text('Invite by email', style: rtStyle(context, 17)),
                    const SizedBox(height: 10),
                    Text('They join with a link', style: rsStyle(context)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Inp(
          value: c.f('teamQ'),
          onChanged: (String s) => c.setF('teamQ', s),
          placeholder: 'Search by name or email',
          icon: 'search',
        ),
        Seg(
          margin: const EdgeInsets.only(top: 12, bottom: 14),
          fontSize: 14,
          items: segs.map(((String, String) e) => e.$2).toList(),
          selected: segs.indexWhere(
            ((String, String) e) => e.$1 == c.teamFilter,
          ),
          onPick: (int i) => c.update(() => c.teamFilter = segs[i].$1),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text('Team members', style: rtStyle(context, 18)),
              ),
              Text('${trows.length} people', style: rsStyle(context)),
            ],
          ),
        ),
        GlassList(
          children: <Widget>[
            for (final Member m in v.rows)
              LRow(
                list: 'team',
                lk: m.email,
                child: RowX(
                  onTap: () {
                    if (c.guardTap('team', m.email)) c.openMember(m);
                  },
                  children: <Widget>[
                    Av(initials(m.name)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            m.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: rtStyle(context),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            m.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: rsStyle(context),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: <Widget>[
                              Bdg(
                                kTS[m.st]!.$1,
                                kind: kTS[m.st]!.$2,
                                dot: true,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  m.role,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: rsStyle(context, 12.5),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Ic('dots', color: kChev),
                  ],
                ),
              ),
            if (v.hidden > 0)
              HidRow('${v.hidden} hidden · Unhide', onTap: v.unhide),
            if (trows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  'No one here.',
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
