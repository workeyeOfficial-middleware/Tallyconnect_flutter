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
import '../../data/repositories/api_tally_repository.dart' show DataSet;
import '../widgets/common.dart';

/// `vsum` (2501): the four month totals shared by Vouchers and Reports,
/// summed from this month's vouchers of each type (null → `—`).
List<Widget> monthSums(BuildContext context, AppController c) {
  final TcPalette p = Tc.of(context);
  final MonthTotals mt = c.repo.monthTotals();
  final bool ready =
      !c.repo.isRemote ||
      (c.repo.status(DataSet.vouchers).state == LoadState.ready &&
          // Incomplete lists report no amounts → show `—`.
          (mt.amount.isNotEmpty || mt.count.isEmpty));
  num? a(String k) => ready ? (mt.amount[k] ?? 0) : null;
  final List<(String, num?, Color, String, String)> v =
      <(String, num?, Color, String, String)>[
        ('Sales', a('sales'), mix(p.acc, .09), 'sales', ''),
        ('Purchase', a('purchase'), mix(p.navy2, .08), 'purchase', ''),
        ('Receipts', a('receipt'), mix(p.pos, .10), 'receipt', 'in'),
        ('Payments', a('payment'), mix(p.warn, .09), 'payment', 'out'),
      ];
  return <Widget>[
    for (final (String, num?, Color, String, String) m in v)
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
              Text(
                m.$2 == null ? '—' : inr(m.$2),
                style: amtStyle(context, size: 18, cls: m.$5),
              ),
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
          ('receipt', 'Receipt', 'in', 'receipt'),
          ('payment', 'Payment', 'out', 'payment'),
          ('journal', 'Adjustment', 'book', 'journal'),
          ('contra', 'Bank ↔ Cash', 'swap', 'contra'),
        ];
    final Map<String, int> cnt = c.repo.monthTotals().count;
    int count(String k) => k == 'all'
        ? cnt.values.fold<int>(0, (int s, int n) => s + n)
        : (cnt[k] ?? 0);
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
                  '${monthYear(c.today)} · ${c.companyName}',
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
                  'vPeriod': 'all',
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
                          '${count(t.$1)} this month',
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
  ('receipt', 'Receipt'),
  ('payment', 'Payment'),
  ('journal', 'Adjustment'),
  ('contra', 'Bank ↔ Cash'),
];

class VListScreen extends ConsumerWidget {
  const VListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final DateTime today = c.today;
    // `all` = the complete history loaded from the server (default).
    bool inPeriod(Voucher v) {
      if (c.vPeriod == 'all') return true;
      final DateTime? d = v.date;
      if (d == null) return false;
      if (c.vPeriod == 'today') return dayDiff(d, today) == 0;
      if (c.vPeriod == 'week') {
        final int n = dayDiff(d, today);
        return n >= 0 && n <= 6;
      }
      return d.year == today.year && d.month == today.month;
    }

    final List<Voucher> all = c.repo.vouchers();
    // Tally voucher types that are not one of the main kinds (orders,
    // notes, returns …) each get their own filter: `type:<name>`.
    final List<String> otherTypes =
        all
            .where((Voucher v) => v.kind == 'other' && (v.type ?? '').isNotEmpty)
            .map((Voucher v) => v.type!)
            .toSet()
            .toList()
          ..sort();
    final bool byType = c.vFilter.startsWith('type:');
    final String typeName = byType ? c.vFilter.substring(5) : '';
    bool inFilter(Voucher v) {
      if (c.vFilter == 'all') return true;
      if (byType) return v.type == typeName;
      return v.kind == c.vFilter;
    }

    final List<Voucher> vrows = all
        .where((Voucher v) => inFilter(v) && inPeriod(v))
        .toList();
    final Kind? fk = byType ? kKinds['other'] : kKinds[c.vFilter];
    final String ic = fk?.ic ?? 'receipt';
    final String cc = fk?.c ?? 'vouchers';
    final String title = c.vFilter == 'all'
        ? 'All Vouchers'
        : (byType
              ? typeName
              : kVF
                        .where(((String, String) x) => x.$1 == c.vFilter)
                        .firstOrNull
                        ?.$2 ??
                    'Vouchers');
    final ({List<Voucher> rows, int hidden, VoidCallback unhide}) v = c
        .listView<Voucher>('vouchers', vrows, (Voucher x) => x.key);
    const List<(String, String)> periods = <(String, String)>[
      ('all', 'All time'),
      ('month', 'This month'),
      ('week', 'Last 7 days'),
      ('today', 'Today'),
    ];
    final String periodLabel =
        periods
            .where(((String, String) e) => e.$1 == c.vPeriod)
            .firstOrNull
            ?.$2 ??
        'All time';
    final String scope = c.vPeriod == 'all'
        ? (c.repo.vouchersComplete
              ? 'All history'
              : 'History incomplete — server list could not be read in full')
        : monthYear(today);
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
                  periodLabel,
                  c.vPeriod == 'all' ? 'All history' : monthYear(today),
                ),
              ),
            ),
          ],
        ),
        H1(title, afterNav: true),
        Sub('${c.companyName} · $scope'),
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
                  inr(vrows.fold<num>(0, (num s, Voucher x) => s + x.amt)),
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
            for (final String t in otherTypes)
              ChipBtn(
                t,
                on: c.vFilter == 'type:$t',
                onTap: () => c.update(() => c.vFilter = 'type:$t'),
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
                lk: x.key,
                child: RowX(
                  onTap: () {
                    if (c.guardTap('vouchers', x.key)) {
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
                      child: RTx(x.party, '${x.no} · ${vDay(x)}', ell: true),
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
                  c.emptyText(DataSet.vouchers, 'No entries in this time.'),
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
    final Voucher? e0 = c.entry ?? c.repo.vouchers().firstOrNull;
    if (e0 == null) {
      return const Scr(
        children: <Widget>[BackNav(), EmptyBox('No entry selected.')],
      );
    }
    final Voucher e = e0;
    final Kind k = kKinds[e.kind]!;
    final List<LedgerLine>? lines = e.guid == null
        ? null
        : c.repo.voucherLines(e.guid!);
    void share() => c.shareDoc(docEntry(e, c.companyName, lines));
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
                date: vDate(e),
                due: '—',
                total: e.amt,
                kind: e.type ?? k.t,
                recv: e.kind == 'purchase' ? false : null,
                city:
                    c.repo
                        .parties()
                        .where((Party x) => x.name == e.party)
                        .firstOrNull
                        ?.city ??
                    '',
                lines: <BillLine>[
                  for (final VoucherItem i in e.items)
                    BillLine(
                      i.name,
                      '',
                      i.qty == null ? '' : qty(i.qty!),
                      i.rate == null ? '' : inr(i.rate),
                      i.amt ?? 0,
                    ),
                ],
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
          ('Type', e.type ?? k.long, false),
          ('Number', e.no, false),
          ('Date', vDate(e), false),
          ('Party / account', e.party, false),
          ('Amount', inr(e.amt), false),
          ('Company', c.companyName, false),
        ], margin: const EdgeInsets.only(top: 12)),
        if (c.repo.isRemote && e.guid != null) ...<Widget>[
          const Sec('Accounts in this entry (Dr / Cr)'),
          if (lines == null)
            EmptyBox(c.emptyText(DataSet.voucher, 'Loading…'))
          else if (lines.isEmpty)
            const EmptyBox('No ledger lines sent by the server.')
          else
            KvList(<(String, String, bool)>[
              for (final LedgerLine l in lines)
                ('${l.debit ? 'Dr' : 'Cr'} · ${l.ledger}', inr(l.amt), false),
            ]),
        ],
      ],
    );
  }
}
