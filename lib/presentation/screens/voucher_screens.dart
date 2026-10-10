// VOUCHERS HUB (869–889), VOUCHER LIST (891–925), ENTRY DETAIL (927–944).
library;

import 'dart:math' as math;

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
import '../../data/repositories/tally_repository.dart'
    show VoucherCounts, VoucherPager, VoucherQuery;
import '../../data/repositories/api_tally_repository.dart' show DataSet;
import '../widgets/common.dart';

/// `vsum` (2501): the four totals shared by Vouchers and Reports, for
/// [period] (This month by default) from [AppController.periodAmount]
/// (null → `—` while loading). A card opens its list with the same period.
List<Widget> monthSums(
  BuildContext context,
  AppController c, {
  String period = 'month',
}) {
  final TcPalette p = Tc.of(context);
  String a(String k) => c.periodAmountText(period, k);
  final List<(String, String, Color, String, String)> v =
      <(String, String, Color, String, String)>[
        ('Sales', a('sales'), mix(p.acc, .09), 'sales', ''),
        ('Purchase', a('purchase'), mix(p.navy2, .08), 'purchase', ''),
        ('Receipts', a('receipt'), mix(p.pos, .10), 'receipt', 'in'),
        ('Payments', a('payment'), mix(p.warn, .09), 'payment', 'out'),
      ];
  return <Widget>[
    for (final (String, String, Color, String, String) m in v)
      Tap(
        onTap: () => c.go('vList', <String, Object?>{
          'vFilter': m.$4,
          'vPeriod': period,
        }),
        radius: 16,
        child: Tot(
          bg: m.$3,
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(m.$1, style: rsStyle(context)),
              AmtText(
                m.$2,
                align: Alignment.centerLeft,
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
    // Tile counts: the complete matching data of the selected period
    // (All time = the whole history, counted by the server).
    final String period = c.vPeriod;
    // Counts / totals key (a date range: its From–To).
    final String pk = c.periodKey(period);
    if (c.repo.isRemote) {
      Future<void>.microtask(() => c.repo.loadVoucherCounts(pk));
    }
    final VoucherCounts? vc = c.repo.voucherCounts(pk);
    // Other Tally voucher types present in the period get their own tile.
    final List<String> otherTypes = vc?.otherTypes ?? const <String>[];
    final List<(String, String, String, String)> tiles =
        <(String, String, String, String)>[
          ('all', 'All', 'receipt', 'vouchers'),
          ('sales', 'Sales', 'bag', 'sales'),
          ('purchase', 'Purchase', 'cart', 'purchase'),
          ('receipt', 'Receipt', 'in', 'receipt'),
          ('payment', 'Payment', 'out', 'payment'),
          ('journal', 'Journal', 'book', 'journal'),
          ('contra', 'Contra', 'swap', 'contra'),
          for (final String t in otherTypes)
            ('type:$t', t, 'receipt', 'vouchers'),
        ];
    final String unit = switch (period) {
      'month' => 'this month',
      'week' => 'in 7 days',
      'today' => 'today',
      'range' => 'in range',
      _ => 'total',
    };
    String countText(String k) {
      final int? n = vc?.forFilter(k);
      if (n != null) return '$n $unit';
      return vc?.error != null ? 'Count unavailable' : 'Counting…';
    }

    const List<(String, String)> periods = <(String, String)>[
      ('all', 'All time'),
      ('month', 'This month'),
      ('week', 'Last 7 days'),
      ('today', 'Today'),
    ];

    return Scr(
      children: <Widget>[
        const BackNav(),
        const H1('Vouchers', afterNav: true),
        const Sub('Entries you have already saved'),
        // One period for the summary amounts and the tile counts below.
        Seg(
          margin: const EdgeInsets.only(bottom: 10),
          items: periods.map(((String, String) e) => e.$2).toList(),
          // None of these while a date range is on.
          selected: period == 'range'
              ? -1
              : periods
                    .indexWhere(((String, String) e) => e.$1 == period)
                    .clamp(0, periods.length - 1),
          onPick: (int i) => c.update(() => c.vPeriod = periods[i].$1),
        ),
        RangeChip(target: 'v', on: period == 'range'),
        Glass(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              LtBadge(
                Text(
                  '${c.periodLabel(period)} · ${c.companyName}',
                  style: ts(13.5, w: w700, c: p.ink3),
                ),
              ),
              // Amounts follow the same period as the tile counts.
              Grid(cols: 2, children: monthSums(context, c, period: period)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (vc?.error != null)
          GlassRow(
            margin: const EdgeInsets.only(bottom: 12),
            onTap: () => c.repo.loadVoucherCounts(pk),
            children: <Widget>[
              Ico('sync', size: IcoSize.xs, color: p.neg, icon: IcSize.s),
              Expanded(child: RTx('Could not count vouchers', vc!.error!)),
              Text(
                'Retry',
                style: ts(14, w: w700, c: p.acc),
              ),
            ],
          ),
        Grid(
          cols: 3,
          children: <Widget>[
            for (final (String, String, String, String) t in tiles)
              Tap(
                onTap: () => c.go('vList', <String, Object?>{
                  'vFilter': t.$1,
                  'vPeriod': period,
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
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: ts(15, w: w800, h: 1.1, c: p.ink),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          countText(t.$1),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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
  ('journal', 'Journal'),
  ('contra', 'Contra'),
];

/// One voucher row (shared by the list and reports).
Widget voucherRow(BuildContext context, AppController c, Voucher x) {
  final TcPalette p = Tc.of(context);
  return LRow(
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
        // Number · date · voucher type (Tally sync status is not shown).
        Expanded(
          child: RTx(
            x.party,
            <String>[
              x.no,
              vDay(x),
              if ((x.type ?? '').trim().isNotEmpty) x.type!.trim(),
            ].where((String s) => s.isNotEmpty).join(' · '),
            ell: true,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${x.kind == 'receipt' ? '+' : (x.kind == 'payment' ? '−' : '')}${inr(x.amt)}',
          style: amtStyle(
            context,
            cls: x.kind == 'receipt'
                ? 'in'
                : (x.kind == 'payment' ? 'out' : ''),
          ),
        ),
      ],
    ),
  );
}

/// The list's filter and period (a date range carries its From–To).
VoucherQuery _query(AppController c) => VoucherQuery(
  filter: c.vFilter,
  period: c.vPeriod,
  range: c.vPeriod == 'range' ? c.range : null,
);

/// Voucher list. "This month" shows the month's vouchers already on the
/// phone (complete, exact totals); All time / Last 7 days / Today page
/// through `/voucher-entry/paged` (100 per page, next page near the end).
class VListScreen extends ConsumerWidget {
  const VListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final bool month = c.vPeriod == 'month' || !c.repo.isRemote;
    if (month) return _VList(c: c, pager: null);
    final VoucherPager pager = c.repo.voucherPager(_query(c));
    return ListenableBuilder(
      listenable: pager,
      builder: (BuildContext context, _) => _VList(c: c, pager: pager),
    );
  }
}

/// Voucher-type chips on ONE swipeable line (never wrapped), with a fixed
/// "More" (+) button at the end that opens every type in a sheet. A type
/// picked from the sheet is moved to the front of the extra types so it is
/// on screen.
class VoucherTypeRow extends StatelessWidget {
  const VoucherTypeRow({super.key, required this.c, required this.otherTypes});
  final AppController c;
  final List<String> otherTypes;

  @override
  Widget build(BuildContext context) {
    final String sel = c.vFilter.startsWith('type:')
        ? c.vFilter.substring(5)
        : '';
    final List<String> extra = <String>[
      if (sel.isNotEmpty) sel,
      for (final String t in otherTypes)
        if (t != sel) t,
    ];
    // The selected chip is scrolled fully into view (only when it is not).
    final GlobalKey selKey = GlobalKey();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? sc = selKey.currentContext;
      if (sc == null || !sc.mounted) return;
      for (final ScrollPositionAlignmentPolicy pol
          in <ScrollPositionAlignmentPolicy>[
            ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
            ScrollPositionAlignmentPolicy.keepVisibleAtStart,
          ]) {
        Scrollable.ensureVisible(
          sc,
          alignmentPolicy: pol,
          duration: const Duration(milliseconds: 250),
        );
      }
    });
    // 42 px chips + 16 px below them inside the row (the selected chip's
    // shadow is not clipped), same total height as before.
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SizedBox(
        height: 58,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: ShaderMask(
                // Soft fade at the right edge: more chips to swipe to.
                shaderCallback: (Rect r) => const LinearGradient(
                  colors: <Color>[Color(0xFFFFFFFF), Color(0x00FFFFFF)],
                  stops: <double>[.96, 1],
                ).createShader(r),
                blendMode: BlendMode.dstIn,
                // Clipped to its own width: chips scroll under the fade and
                // never paint under / over the "+" button.
                child: ListView(
                  key: const PageStorageKey<String>('vTypeRow'),
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.hardEdge,
                  padding: const EdgeInsets.only(
                    left: 2,
                    right: 16,
                    bottom: 16,
                  ),
                  children: <Widget>[
                    for (final (String, String) x in kVF) ...<Widget>[
                      HoverDwell(
                        key: c.vFilter == x.$1 ? selKey : null,
                        enabled: c.vFilter != x.$1,
                        onDwell: () => c.update(() => c.vFilter = x.$1),
                        child: ChipBtn(
                          x.$2,
                          on: c.vFilter == x.$1,
                          onTap: () => c.update(() => c.vFilter = x.$1),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    for (final String t in extra) ...<Widget>[
                      HoverDwell(
                        key: c.vFilter == 'type:$t' ? selKey : null,
                        enabled: c.vFilter != 'type:$t',
                        onDwell: () => c.update(() => c.vFilter = 'type:$t'),
                        child: ChipBtn(
                          t,
                          on: c.vFilter == 'type:$t',
                          onTap: () => c.update(() => c.vFilter = 'type:$t'),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            ChipBtn(
              otherTypes.isEmpty ? 'More' : '${otherTypes.length}',
              key: const ValueKey<String>('vTypesMore'),
              icon: 'plus',
              onTap: () => c.openVoucherTypes(otherTypes),
            ),
          ],
        ),
      ),
    );
  }
}

class _VList extends StatelessWidget {
  const _VList({required this.c, required this.pager});
  final AppController c;
  final VoucherPager? pager;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final DateTime today = c.today;
    final VoucherPager? pg = pager;
    if (pg != null &&
        pg.rows.isEmpty &&
        pg.hasMore &&
        !pg.loading &&
        pg.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => pg.loadMore());
    }
    final bool byType = c.vFilter.startsWith('type:');
    final String typeName = byType ? c.vFilter.substring(5) : '';
    final VoucherQuery q = _query(c);
    final String pk = c.periodKey(c.vPeriod);
    // Rows: this month's set (filtered once per data change) or the pages.
    final List<Voucher> vrows = pg != null
        ? pg.rows
        : c.memo<List<Voucher>>(
            'vlist-month',
            '${c.repo.version}|${q.key}',
            () => c.repo.vouchers().where((Voucher v) {
              if (!q.matches(v)) return false;
              final DateTime? d = v.date;
              if (c.vPeriod == 'range') return q.range?.contains(d) ?? false;
              if (c.vPeriod == 'today') {
                return d != null && dayDiff(d, today) == 0;
              }
              if (c.vPeriod == 'week') {
                if (d == null) return false;
                final int n = dayDiff(d, today);
                return n >= 0 && n <= 6;
              }
              if (c.vPeriod == 'month') {
                return d != null &&
                    d.year == today.year &&
                    d.month == today.month;
              }
              return true;
            }).toList(),
          );
    // Exact counts of the complete matching data for this period (the
    // pages on screen are only what has been read so far).
    if (pg != null) {
      Future<void>.microtask(() => c.repo.loadVoucherCounts(pk));
    }
    final VoucherCounts? vc = pg == null ? null : c.repo.voucherCounts(pk);
    final List<String> otherTypes = c.memo<List<String>>(
      'vlist-other',
      '${c.repo.version}|${pg?.rows.length}|${identityHashCode(vc)}',
      () => <String>{
        for (final Voucher v in <Voucher>[...c.repo.vouchers(), ...?pg?.rows])
          if (v.kind == 'other' && (v.type ?? '').isNotEmpty) v.type!,
        ...?vc?.otherTypes,
      }.toList()..sort(),
    );
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
        .memo<({List<Voucher> rows, int hidden, VoidCallback unhide})>(
          'vlist-view',
          '${identityHashCode(vrows)}|${vrows.length}|${c.prefsVersion}',
          () => c.listView<Voucher>('vouchers', vrows, (Voucher x) => x.key),
        );
    const List<(String, String)> periods = <(String, String)>[
      ('all', 'All time'),
      ('month', 'This month'),
      ('week', 'Last 7 days'),
      ('today', 'Today'),
    ];
    final String periodLabel = c.vPeriod == 'range'
        ? c.periodLabel('range')
        : periods
                  .where(((String, String) e) => e.$1 == c.vPeriod)
                  .firstOrNull
                  ?.$2 ??
              'All time';
    // Count / total: of the complete matching data for the period and
    // filter — the list's own rows once fully loaded, else the period's
    // exact totals (never the rows loaded so far).
    String countText;
    String totalText;
    // Page 1 not answered yet: loading, never "0" / "₹0".
    final bool waiting =
        pg != null && vrows.isEmpty && !pg.complete && pg.error == null;
    final int? exact = vc?.forFilter(c.vFilter);
    final num? exactAmt = vc?.amountFor(c.vFilter);
    if (pg == null || pg.complete) {
      // Every matching row is loaded: count and total of exactly the rows
      // the list shows.
      countText = grouped(vrows.length);
      totalText = inr(paise(sumRupees(vrows.map((Voucher x) => x.amt))));
    } else if (exact != null) {
      // Still paging: the complete matching count and total value.
      countText = grouped(exact);
      totalText = exactAmt == null ? '—' : inr(exactAmt);
    } else {
      countText = vc?.error != null ? '—' : '…';
      totalText = vc?.error != null ? '—' : '…';
    }
    final String scope = c.vPeriod == 'all'
        ? 'All history'
        : (c.vPeriod == 'month' ? monthYear(today) : periodLabel);
    final bool more =
        pg != null && (pg.hasMore || pg.loading || pg.error != null);
    final int extra = (v.hidden > 0 ? 1 : 0) + (more || vrows.isEmpty ? 1 : 0);
    return Scr(
      // Next page near the end; after a failed page only Retry reloads (no
      // automatic hammering of the server).
      onNearEnd: pg == null
          ? null
          : () {
              if (pg.error == null) pg.loadMore();
            },
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
                  pg == null || pg.complete
                      ? periodLabel
                      : '$periodLabel · first ${vrows.length} loaded',
                  c.vPeriod == 'all'
                      ? 'All history'
                      : (c.vPeriod == 'range'
                            ? periodLabel
                            : monthYear(today)),
                ),
              ),
            ),
          ],
        ),
        H1(title, afterNav: true),
        Sub('${c.companyName} · $scope'),
        VoucherSummaryRow(
          icon: ic,
          color: p.cat(cc),
          count: countText,
          total: totalText,
        ),
        VoucherTypeRow(c: c, otherTypes: otherTypes),
        Seg(
          hoverSelect: true,
          margin: const EdgeInsets.only(bottom: 10),
          items: periods.map(((String, String) e) => e.$2).toList(),
          selected: periods.indexWhere(
            ((String, String) e) => e.$1 == c.vPeriod,
          ),
          onPick: (int i) => c.update(() => c.vPeriod = periods[i].$1),
        ),
        RangeChip(target: 'v', on: c.vPeriod == 'range'),
        // Rows are built only while on screen.
        SliverGlassList(
          itemCount: v.rows.length + extra,
          itemBuilder: (BuildContext context, int i) {
            if (i < v.rows.length) return voucherRow(context, c, v.rows[i]);
            int k = i - v.rows.length;
            if (v.hidden > 0) {
              if (k == 0) {
                return HidRow('${v.hidden} hidden · Unhide', onTap: v.unhide);
              }
              k--;
            }
            return PageFooterRow(
              loading: (pg?.loading ?? false) || waiting,
              error: pg?.error,
              onRetry: pg == null ? null : () => pg.loadMore(),
              // "No entries" only once the server said there are none.
              text: vrows.isEmpty && (pg == null || pg.complete)
                  ? c.emptyText(DataSet.vouchers, 'No entries in this time.')
                  : '',
            );
          },
        ),
      ],
    );
  }
}

/// The list's Entries / Total value card. Count and value sit in two
/// columns split by a thin divider with clear space on both sides. Each
/// column is as wide as its own number; when both together are wider than
/// the row, both shrink by the same factor (so they keep one size) — they
/// never touch, overlap or clip, however large the numbers grow.
class VoucherSummaryRow extends StatelessWidget {
  const VoucherSummaryRow({
    super.key,
    required this.icon,
    required this.color,
    required this.count,
    required this.total,
  });
  final String icon, count, total;
  final Color color;

  /// Space on each side of the divider.
  static const double gap = 14;

  @override
  Widget build(BuildContext context) {
    final TextStyle countStyle = rtStyle(context, 22);
    final TextStyle totalStyle = amtStyle(context, size: 22);
    final TextStyle label = rsStyle(context);
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    double width(String s, TextStyle st) {
      final TextPainter tp = TextPainter(
        text: TextSpan(text: s, style: st),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final double w = tp.width;
      tp.dispose();
      return w;
    }

    return GlassRow(
      minHeight: 72,
      children: <Widget>[
        Ico(icon, size: IcoSize.sm, color: color),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              final double room = math.max(0, box.maxWidth - 2 * gap - 1);
              final double cw = width(count, countStyle);
              final double tw = width(total, totalStyle);
              // One shared factor: 1 when both fit at full size.
              final double s = cw + tw <= room ? 1 : room / (cw + tw);
              // Count column: its (scaled) number, at least its label, at
              // most 45 % of the row; the value column takes the rest.
              final double countW = math
                  .max(cw * s, math.min(width('Entries', label), room * .3))
                  .clamp(0, room * .45)
                  .toDouble();
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  SizedBox(
                    width: countW,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Entries',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: label,
                        ),
                        AmtText(
                          count,
                          align: Alignment.centerLeft,
                          style: countStyle,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    margin: const EdgeInsets.symmetric(horizontal: gap),
                    color: navyA(.12),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Text(
                          'Total value',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: label,
                        ),
                        AmtText(total, style: totalStyle),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
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
    // Share, See bill PDF and Download: the voucher's one complete document.
    void share() => c.shareVoucher(e);
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
            onTap: () => c.openVoucherPdf(e),
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
        // Item lines — only when this voucher has them.
        if (e.items.isNotEmpty) ...<Widget>[
          const Sec('Items'),
          GlassList(
            children: <Widget>[
              for (int i = 0; i < e.items.length; i++)
                RowX(
                  children: <Widget>[
                    Expanded(
                      child: RTx(
                        '${i + 1}. ${e.items[i].name}',
                        <String>[
                          if (e.items[i].qty != null)
                            'Qty ${qty(e.items[i].qty!)}',
                          if (e.items[i].rate != null)
                            'Rate ${inr(e.items[i].rate)}',
                        ].join(' · '),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      e.items[i].amt == null ? '—' : inr(e.items[i].amt),
                      style: amtStyle(context),
                    ),
                  ],
                ),
            ],
          ),
        ],
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
