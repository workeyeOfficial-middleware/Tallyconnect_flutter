// VOUCHERS HUB (869–889), VOUCHER LIST (891–925), ENTRY DETAIL (927–944).
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
import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import '../widgets/common.dart';

/// `vsum` (2501): the four month totals shared by Vouchers and Reports.
List<Widget> monthSums(BuildContext context, AppController c) {
  final TcPalette p = Tc.of(context);
  final List<(String, int, Color, String, String)> v =
      <(String, int, Color, String, String)>[
        ('Sales', 348690, mix(p.acc, .09), 'sales', ''),
        ('Purchase', 126850, mix(p.navy2, .08), 'purchase', ''),
        ('Money in', 215000, mix(p.pos, .10), 'receipt', 'in'),
        ('Money out', 98450, mix(p.warn, .09), 'payment', 'out'),
      ];
  return <Widget>[
    for (final (String, int, Color, String, String) m in v)
      Tap(
        onTap: () => c.go('vList', <String, Object?>{
          'vFilter': m.$4,
          'vPeriod': 'month',
        }),
        radius: 16,
        child: Tot(
          bg: m.$3,
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(m.$1, style: rsStyle(context)),
              Text(inr(m.$2), style: amtStyle(context, size: 18, cls: m.$5)),
            ],
          ),
        ),
      ),
  ];
}

class VHubScreen extends ConsumerWidget {
  const VHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    const List<(String, String, String, String)> tiles =
        <(String, String, String, String)>[
          ('all', 'All', 'receipt', 'vouchers'),
          ('sales', 'Sales', 'bag', 'sales'),
          ('purchase', 'Purchase', 'cart', 'purchase'),
          ('receipt', 'Money In', 'in', 'receipt'),
          ('payment', 'Money Out', 'out', 'payment'),
          ('journal', 'Adjustment', 'book', 'journal'),
          ('contra', 'Bank ↔ Cash', 'swap', 'contra'),
        ];
    final List<Voucher> vs = c.repo.vouchers();
    return Scr(
      children: <Widget>[
        const BackNav(),
        const H1('Vouchers', afterNav: true),
        const Sub('Entries you have already saved'),
        Glass(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              LtBadge(
                Text(
                  'September 2026 · ${c.companyName}',
                  style: ts(13.5, w: w700, c: p.ink3),
                ),
              ),
              Grid(cols: 2, children: monthSums(context, c)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Grid(
          cols: 3,
          children: <Widget>[
            for (final (String, String, String, String) t in tiles)
              Tap(
                onTap: () => c.go('vList', <String, Object?>{
                  'vFilter': t.$1,
                  'vPeriod': 'month',
                }),
                child: Glass(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 136),
                    padding: const EdgeInsets.fromLTRB(6, 16, 6, 14),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Ico(t.$3, color: p.cat(t.$4), icon: IcSize.l),
                        const SizedBox(height: 9),
                        Text(
                          t.$2,
                          textAlign: TextAlign.center,
                          style: ts(15, w: w800, h: 1.1, c: p.ink),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${vs.where((Voucher v) => t.$1 == 'all' || v.kind == t.$1).length} this month',
                          textAlign: TextAlign.center,
                          style: ts(12.5, c: p.ink3),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

const List<(String, String)> kVF = <(String, String)>[
  ('all', 'All'),
  ('sales', 'Sales'),
  ('purchase', 'Purchase'),
  ('receipt', 'Money In'),
  ('payment', 'Money Out'),
  ('journal', 'Adjustment'),
  ('contra', 'Bank ↔ Cash'),
];

class VListScreen extends ConsumerWidget {
  const VListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final List<Voucher> vrows = c.repo
        .vouchers()
        .where(
          (Voucher v) =>
              (c.vFilter == 'all' || v.kind == c.vFilter) &&
              (c.vPeriod == 'month' ||
                  (c.vPeriod == 'week' ? v.day >= 20 : v.day == 26)),
        )
        .toList();
    final String ic = c.vFilter == 'all' ? 'receipt' : kKinds[c.vFilter]!.ic;
    final String cc = c.vFilter == 'all' ? 'vouchers' : kKinds[c.vFilter]!.c;
    final String title = c.vFilter == 'all'
        ? 'All Vouchers'
        : kVF.firstWhere(((String, String) x) => x.$1 == c.vFilter).$2;
    final ({List<Voucher> rows, int hidden, VoidCallback unhide}) v = c
        .listView<Voucher>('vouchers', vrows, (Voucher x) => x.no);
    const List<(String, String)> periods = <(String, String)>[
      ('month', 'This month'),
      ('week', 'Last 7 days'),
      ('today', 'Today'),
    ];
    return Scr(
      children: <Widget>[
        BackNav(
          actions: <Widget>[
            CBtn('search', onTap: () => c.openOverlay('search')),
            CBtn('sync', onTap: c.refreshNow),
            CBtn('plus', onTap: () => c.go('newEntry')),
            CBtn(
              'file',
              onTap: () => c.previewDoc(
                docVouchers(
                  title,
                  vrows,
                  c.companyName,
                  periods
                      .firstWhere(((String, String) e) => e.$1 == c.vPeriod)
                      .$2,
                ),
              ),
            ),
          ],
        ),
        H1(title, afterNav: true),
        Sub('${c.companyName} · September 2026'),
        GlassRow(
          minHeight: 72,
          children: <Widget>[
            Ico(ic, size: IcoSize.sm, color: p.cat(cc)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Entries', style: rsStyle(context)),
                  Text('${vrows.length}', style: rtStyle(context, 22)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text('Total value', style: rsStyle(context)),
                const SizedBox(height: 4),
                Text(
                  inr(vrows.fold<int>(0, (int s, Voucher x) => s + x.amt)),
                  style: amtStyle(context, size: 22),
                ),
              ],
            ),
          ],
        ),
        Chips(
          margin: const EdgeInsets.only(top: 4, bottom: 14),
          children: <Widget>[
            for (final (String, String) x in kVF)
              ChipBtn(
                x.$2,
                on: c.vFilter == x.$1,
                onTap: () => c.update(() => c.vFilter = x.$1),
              ),
          ],
        ),
        Seg(
          items: periods.map(((String, String) e) => e.$2).toList(),
          selected: periods.indexWhere(
            ((String, String) e) => e.$1 == c.vPeriod,
          ),
          onPick: (int i) => c.update(() => c.vPeriod = periods[i].$1),
        ),
        GlassList(
          children: <Widget>[
            for (final Voucher x in v.rows)
              LRow(
                list: 'vouchers',
                lk: x.no,
                child: RowX(
                  onTap: () {
                    if (c.guardTap('vouchers', x.no)) {
                      c.go('entryDetail', <String, Object?>{'entry': x});
                    }
                  },
                  children: <Widget>[
                    Ico(
                      kKinds[x.kind]!.ic,
                      size: IcoSize.xs,
                      color: p.cat(kKinds[x.kind]!.c),
                      icon: IcSize.s,
                    ),
                    Expanded(
                      child: RTx(x.party, '${x.no} · ${x.day} Sep', ell: true),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Text(
                          '${x.kind == 'receipt' ? '+' : (x.kind == 'payment' ? '−' : '')}${inr(x.amt)}',
                          style: amtStyle(
                            context,
                            cls: x.kind == 'receipt'
                                ? 'in'
                                : (x.kind == 'payment' ? 'out' : ''),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Bdg(
                          'Synced',
                          kind: BadgeKind.ok,
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          fontSize: 11,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (v.hidden > 0)
              HidRow('${v.hidden} hidden · Unhide', onTap: v.unhide),
            if (vrows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  'No entries in this time.',
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

class EntryDetailScreen extends ConsumerWidget {
  const EntryDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final Voucher e = c.entry ?? c.repo.vouchers().first;
    final Kind k = kKinds[e.kind]!;
    void share() => c.shareDoc(docEntry(e, c.companyName));
    return FlowScr(
      foot: <Widget>[
        Expanded(
          flex: 10,
          child: Btn(
            label: 'Share',
            icon: 'share',
            kind: BtnKind.g,
            onTap: share,
          ),
        ),
        Expanded(
          flex: 17,
          child: Btn(
            label: 'See bill PDF',
            icon: 'file',
            onTap: () => c.openPdf(
              PdfInfo(
                party: e.party,
                no: e.no,
                date: '${e.day} Sep 2026',
                due: '—',
                total: e.amt,
                kind: k.t,
                city:
                    c.repo
                        .parties()
                        .where((Party x) => x.name == e.party)
                        .firstOrNull
                        ?.city ??
                    '',
              ),
            ),
          ),
        ),
      ],
      children: <Widget>[
        BackNav(actions: <Widget>[CBtn('share', onTap: share)]),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Glass(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: <Widget>[
                Ico(k.ic, color: p.cat(k.c), icon: IcSize.l),
                const SizedBox(height: 8),
                Text(
                  '${k.long} · ${e.no}',
                  textAlign: TextAlign.center,
                  style: ts(13.5, w: w700, c: p.ink3),
                ),
                const SizedBox(height: 8),
                Text(
                  inr(e.amt),
                  style: amtStyle(
                    context,
                    cls:
                        'big ${e.kind == 'receipt' ? 'in' : (e.kind == 'payment' ? 'out' : '')}',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  e.party,
                  textAlign: TextAlign.center,
                  style: rtStyle(context),
                ),
                const SizedBox(height: 8),
                const Bdg('Synced with Tally', kind: BadgeKind.ok, dot: true),
              ],
            ),
          ),
        ),
        KvList(<(String, String, bool)>[
          ('Type', k.long, false),
          ('Number', e.no, false),
          ('Date', '${e.day} Sep 2026', false),
          ('Party / account', e.party, false),
          ('Amount', inr(e.amt), false),
          ('Company', c.companyName, false),
        ], margin: const EdgeInsets.only(top: 12)),
      ],
    );
  }
}
