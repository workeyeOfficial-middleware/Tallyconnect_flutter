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
import '../../core/share/report_data.dart';
import '../../core/share/share_doc.dart';
import '../../core/utils/format.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import '../../data/repositories/api_tally_repository.dart' show DataSet;
import '../../data/repositories/voucher_pager.dart';
import '../widgets/common.dart';
import '../widgets/report_chart.dart';
import '../widgets/tab_bar.dart' show PillFilter;
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
    inr(sumRupees(c.repo.items().map((Item x) => x.worth)));

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final String period = c.repPeriod;
    // All time / a date range: that period's exact totals (counted once,
    // kept until the data changes).
    final String pk = c.periodKey(period);
    final bool counted = period == 'all' || period == 'range';
    if (counted && c.repo.isRemote) {
      Future<void>.microtask(() => c.repo.loadVoucherCounts(pk));
    }
    final VoucherCounts? vc = counted ? c.repo.voucherCounts(pk) : null;
    final Map<String, String> rv = c.memo<Map<String, String>>(
      'reports-cards',
      '${c.repo.version}|$pk|${identityHashCode(vc)}|${vc?.complete}|${vc?.stale}',
      () => <String, String>{
        for (final Report r in c.repo.reports())
          r.id: reportData(
            c.repo,
            r.id,
            period: period,
            range: c.range,
          ).card,
      },
    );
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
            CBtn(
              'calendar',
              key: const ValueKey<String>('repRangeBtn'),
              dot: period == 'range',
              onTap: () => c.openRange('rep'),
            ),
            CBtn(
              'file',
              onTap: () => c.previewDoc(c.docReportList(c.companyName)),
            ),
            CBtn('sync', onTap: c.refreshNow),
          ],
        ),
        const H1('Reports', afterNav: true),
        Sub('Easy views of your Tally data · ${c.companyName}'),
        ReportPeriodSeg(c: c),
        Glass(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              LtBadge(Text(c.periodLabel(period), style: rtStyle(context))),
              Grid(cols: 2, children: monthSums(context, c, period: period)),
            ],
          ),
        ),
        Chips(
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
                pinCorner: true,
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

/// This month / All time switch for the reports, and the Date range
/// option under it.
class ReportPeriodSeg extends StatelessWidget {
  const ReportPeriodSeg({super.key, required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Seg(
        margin: const EdgeInsets.only(bottom: 10),
        items: <String>[for (final (String, String) e in kReportPeriods) e.$2],
        selected: kReportPeriods.indexWhere(
          ((String, String) e) => e.$1 == c.repPeriod,
        ),
        onPick: (int i) => c.setRepPeriod(kReportPeriods[i].$1),
      ),
      RangeChip(target: 'rep', on: c.repPeriod == 'range'),
    ],
  );
}

/// Reports listing vouchers (All time: read page by page from the server).
const Map<String, String> kVoucherReports = <String, String>{
  'day': 'all',
  'sreg': 'sales',
  'preg': 'purchase',
};

class ReportScreen extends ConsumerWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final String? filter = kVoucherReports[c.report];
    final bool range = c.repPeriod == 'range' && c.range != null;
    if ((c.repPeriod == 'all' || range) && c.repo.isRemote && filter != null) {
      // The whole history (or range) is never loaded at once: the latest
      // pages, more near the end of the list; totals are the period's
      // exact figures.
      final VoucherPager pg = c.repo.voucherPager(
        range
            ? VoucherQuery(filter: filter, period: 'range', range: c.range)
            : VoucherQuery(filter: filter),
      );
      return ListenableBuilder(
        listenable: pg,
        builder: (BuildContext context, _) => _Report(c: c, pager: pg),
      );
    }
    return _Report(c: c, pager: null);
  }
}

class _Report extends StatelessWidget {
  const _Report({required this.c, required this.pager});
  final AppController c;
  final VoucherPager? pager;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final VoucherPager? pg = pager;
    final String pk = c.periodKey(c.repPeriod);
    if (pg != null) {
      if (pg.rows.isEmpty && pg.hasMore && !pg.loading && pg.error == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => pg.loadMore());
      }
      Future<void>.microtask(() => c.repo.loadVoucherCounts(pk));
    }
    final VoucherCounts? vc = pg == null ? null : c.repo.voucherCounts(pk);
    final ReportData d = c.memo<ReportData>(
      'report-data',
      '${c.repo.version}|${c.report}|$pk|${pg?.rows.length}|${pg?.complete}|${identityHashCode(vc)}|${vc?.complete}|${vc?.stale}',
      () => reportData(
        c.repo,
        c.report,
        period: c.repPeriod,
        range: c.range,
        loaded: pg?.rows,
        loadedAll: pg?.complete ?? false,
      ),
    );
    final Report r0 = d.report;
    final List<Color> av = <Color>[
      p.navy2,
      p.cat('sales'),
      p.cat('reports'),
      p.cat('items'),
      p.acc,
    ];
    final ShareDoc doc = docReport(d, c.companyName);
    final bool more =
        pg != null && (pg.hasMore || pg.loading || pg.error != null);
    return Scr(
      // Next page near the end; after a failed page only Retry reloads.
      onNearEnd: pg == null
          ? null
          : () {
              if (pg.error == null) pg.loadMore();
            },
      children: <Widget>[
        BackNav(
          actions: <Widget>[
            CBtn('file', onTap: () => c.previewDoc(doc)),
            CBtn('download', onTap: () => c.downloadDoc(doc)),
            CBtn('share', onTap: () => c.shareDoc(doc)),
          ],
        ),
        Row(
          children: <Widget>[
            Ico(r0.ic, color: p.cat(r0.c), icon: IcSize.l),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  H1(r0.t, size: 28, margin: EdgeInsets.zero),
                  const SizedBox(height: 2),
                  Text('${r0.s} · ${d.period}', style: rsStyle(context)),
                ],
              ),
            ),
          ],
        ),
        // Period applies to the voucher reports; Top customers can be
        // limited to bills dated in a range; other outstanding and stock
        // reports are as of today.
        if (kVoucherReports.containsKey(r0.id))
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: ReportPeriodSeg(c: c),
          )
        else if (r0.id == 'top')
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: RangeChip(target: 'rep', on: c.repPeriod == 'range'),
          ),
        // NEW: chart first (same rows as the list below).
        if (d.hasChart)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: ReportChart(
              data: d,
              type: c.chartType[r0.id] ?? (d.lineFirst ? 'line' : 'bar'),
              onType: (String t) => c.update(() => c.chartType[r0.id] = t),
            ),
          ),
        GlassRow(
          margin: EdgeInsets.only(top: d.hasChart ? 12 : 18),
          minHeight: 64,
          children: <Widget>[
            Expanded(child: Text(d.totalLabel, style: rsStyle(context))),
            Text(d.total, style: amtStyle(context, size: 22)),
          ],
        ),
        lazyList<int>(
          margin: const EdgeInsets.only(top: 12),
          rows: List<int>.generate(d.rows.length, (int i) => i),
          row: (BuildContext context, int i) => RowX(
            // Opens the party / item / voucher behind the row.
            onTap: d.rows[i].target == null
                ? null
                : () => c.openRowTarget(d.rows[i].target!),
            children: <Widget>[
              Av(
                d.rows[i].n,
                size: Av.sm,
                gradient: LinearGradient(
                  colors: <Color>[av[i % av.length], av[i % av.length]],
                ),
              ),
              Expanded(child: RTx(d.rows[i].t, d.rows[i].s, ell: true)),
              Text(d.rows[i].v, style: amtStyle(context, cls: d.rows[i].cls)),
              if (d.rows[i].target != null) ...<Widget>[
                const SizedBox(width: 6),
                chevR(),
              ],
            ],
          ),
          empty: d.note.isNotEmpty
              ? d.note
              : (pg != null && pg.loading
                    ? 'Loading…'
                    : c.emptyText(DataSet.vouchers, 'Nothing to show.')),
        ),
        if (more && d.rows.isNotEmpty)
          GlassRow(
            margin: const EdgeInsets.only(top: 12),
            onTap: pg.error != null ? pg.loadMore : null,
            children: <Widget>[
              Expanded(
                child: Text(
                  pg.error != null
                      ? 'Could not load more · tap to retry'
                      : 'Showing the latest ${grouped(d.rows.length)} · more load as you scroll',
                  style: rsStyle(context),
                ),
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
      ('receipt', 'Receipt'),
      ('payment', 'Payment'),
      ('journal', 'Journal'),
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
            CBtn(
              'file',
              onTap: () => c.previewDoc(docActs(v.rows, c.companyName)),
            ),
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
                            Text(
                              c.repo.isRemote
                                  ? 'Tally sync'
                                  : 'Tally connected',
                              style: rtStyle(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          c.repo.isRemote
                              ? '${c.companyName} · ${c.syncText(c.company)}'
                              : 'RAJESH-PC · ${c.companyName} · checks every 5 min',
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
                  StatBox('${count('ok')}', 'Sent', kind: 'c'),
                  StatBox('${count('wait')}', 'Waiting', kind: 'b'),
                  StatBox('${count('fail')}', 'Not sent', kind: 'n'),
                ],
              ),
            ],
          ),
        ),
        // Liquid-glass filter (same active lens as the tab bar); adapts to
        // any number of voucher types.
        PillFilter(
          items: af,
          selected: c.actFilter,
          onPick: (String k) => c.update(() => c.actFilter = k),
        ),
        lazyList<Act>(
          rows: v.rows,
          row: (BuildContext context, Act a) => LRow(
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
              ],
            ),
          ),
          hidden: v.hidden,
          unhide: v.unhide,
          empty: c.emptyText(DataSet.activity, 'Nothing here.'),
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
    final Act? af =
        c.acts.where((Act a) => a.id == c.act).firstOrNull ??
        c.acts.firstOrNull;
    if (af == null) {
      return const Scr(
        children: <Widget>[BackNav(), EmptyBox('No entry selected.')],
      );
    }
    final Act a0 = af;
    final Kind k = kKinds[a0.kind]!;
    final (String, BadgeKind) m = kStMeta[a0.status]!;
    final Color stColor = a0.status == 'ok'
        ? p.pos
        : (a0.status == 'wait' ? p.warn : p.neg);
    final bool s11 = !c.repo.isRemote && a0.no == 'Sales 11';
    final List<(String, String, bool)> rows = c.repo.isRemote
        ? <(String, String, bool)>[
            ('Entry number', a0.no, false),
            ('Party / account', a0.party, false),
            ('Amount', inr(a0.amt), false),
            for (final (String, String) r in a0.rows) (r.$1, r.$2, false),
            ('Status', m.$1, false),
            if (a0.note.isNotEmpty) ('Error', a0.note, false),
          ]
        : s11
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
        // Share / PDF of this entry (same exporter as bills and reports).
        Grid(
          cols: 3,
          gap: 10,
          children: <Widget>[
            for (final (String, String, String, VoidCallback) t
                in <(String, String, String, VoidCallback)>[
                  (
                    'share',
                    'sales',
                    'Share',
                    () => c.shareDoc(docAct(a0, c.companyName)),
                  ),
                  (
                    'file',
                    'navy',
                    'Preview PDF',
                    () => c.previewDoc(docAct(a0, c.companyName)),
                  ),
                  (
                    'download',
                    'purchase',
                    'Download PDF',
                    () => c.downloadDoc(docAct(a0, c.companyName)),
                  ),
                ])
              Tap(
                onTap: t.$4,
                child: Glass(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 92),
                    padding: const EdgeInsets.fromLTRB(6, 14, 6, 12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Ico(
                          t.$1,
                          size: IcoSize.xs,
                          color: p.cat(t.$2),
                          icon: IcSize.s,
                        ),
                        const SizedBox(height: 8),
                        AmtText(
                          t.$3,
                          align: Alignment.center,
                          style: rtStyle(context, 13.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const Sec('Entry details'),
        KvList(rows),
        if (a0.items.isNotEmpty) ...<Widget>[
          Sec(a0.kind == 'journal' ? 'Accounts' : 'Items'),
          GlassList(
            children: <Widget>[
              for (int i = 0; i < a0.items.length; i++)
                RowX(
                  children: <Widget>[
                    Expanded(
                      child: RTx(
                        a0.kind == 'journal'
                            ? a0.items[i].$1
                            : '${i + 1}. ${a0.items[i].$1}',
                        a0.items[i].$2,
                      ),
                    ),
                    Text(inr(a0.items[i].$3), style: amtStyle(context)),
                  ],
                ),
            ],
          ),
        ],
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
    if (!c.isAdmin) {
      return Scr(
        children: <Widget>[
          NavRow(
            children: <Widget>[
              CBtn('menu', onTap: () => c.openOverlay('menu')),
              const Spacer(),
            ],
          ),
          const TitleBadge('Sales Team'),
          const Sub('Add people and send invites'),
          const EmptyBox('Only your admin can see and manage the team.'),
        ],
      );
    }
    void invite() => c.update(() {
      c.overlay = 'invite';
      c.form['iEmail'] = '';
    });
    void create() => c.openNewUser();
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
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
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
                  c.emptyText(DataSet.team, 'No one here.'),
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
