// Graphs on the financial statements (Balance Sheet, Profit & Loss, Trial
// Balance): the same figures the statement lists — its groups and totals for
// the period chosen — drawn as bar, column, line, scatter or pie. Nothing is
// worked out again; switching the chart never changes the report.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/design/tc_icons.dart';
import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';
import '../../core/share/report_data.dart' show ChartPoint;
import '../../core/utils/format.dart';
import '../../data/models/models.dart';
import '../widgets/report_chart.dart';
import 'financial_screens.dart' show tbDrCr;

/// One series a statement can draw: its key, chip label and points.
class FinChartSet {
  const FinChartSet(this.key, this.label, this.points, {this.adds = true});
  final String key, label;
  final List<ChartPoint> points;

  /// The parts add up to a real total (shown); false for a summary or a
  /// comparison (Revenue + Net profit is no figure).
  final bool adds;

  num get total => points.fold<num>(0, (num s, ChartPoint p) => s + p.value);
}

List<ChartPoint> _nonZero(Iterable<ChartPoint> pts) => <ChartPoint>[
  for (final ChartPoint p in pts)
    if (p.value.abs() >= .005) p,
];

/// The series of statement [kind] (`bs`, `pl`, `tb`) from its figures.
List<FinChartSet> finChartSets(FinReport r, String kind) {
  switch (kind) {
    case 'bs':
      // Each group on the side its balance is on (as the statement shows).
      final List<FinNode> liab = r.nodes('liabilities');
      final List<FinNode> assets = r.nodes('assets');
      final num pl = r.sub('profit_loss', 'total');
      final List<ChartPoint> a = _nonZero(<ChartPoint>[
        for (final FinNode n in assets)
          if (n.amount >= 0) ChartPoint(n.name, n.amount),
        for (final FinNode n in liab)
          if (n.amount < 0) ChartPoint(n.name, -n.amount),
        if (pl < 0) ChartPoint('Profit & Loss A/c', -pl),
      ]);
      final List<ChartPoint> l = _nonZero(<ChartPoint>[
        for (final FinNode n in liab)
          if (n.amount >= 0) ChartPoint(n.name, n.amount),
        for (final FinNode n in assets)
          if (n.amount < 0) ChartPoint(n.name, -n.amount),
        if (pl >= 0) ChartPoint('Profit & Loss A/c', pl),
      ]);
      return <FinChartSet>[
        FinChartSet('assets', 'Assets', a),
        FinChartSet('liabilities', 'Liabilities', l),
        FinChartSet('compare', 'Assets vs Liabilities', <ChartPoint>[
          ChartPoint('Assets', sumRupees(a.map((ChartPoint p) => p.value))),
          ChartPoint(
            'Liabilities',
            sumRupees(l.map((ChartPoint p) => p.value)),
          ),
        ], adds: false),
      ];
    case 'tb':
      // Top groups (and ledgers directly under Primary) with their Debit /
      // Credit, exactly as the table splits them.
      final List<FinNode> rows = <FinNode>[
        for (final FinNode s in r.nodes('sections'))
          if (s.nature != 'other') s,
        for (final FinNode s in r.nodes('sections'))
          if (s.nature == 'other') ...s.children,
      ];
      return <FinChartSet>[
        FinChartSet(
          'debit',
          'Debit',
          _nonZero(<ChartPoint>[
            for (final FinNode n in rows) ChartPoint(n.name, tbDrCr(n).$1),
          ]),
        ),
        FinChartSet(
          'credit',
          'Credit',
          _nonZero(<ChartPoint>[
            for (final FinNode n in rows) ChartPoint(n.name, tbDrCr(n).$2),
          ]),
        ),
        FinChartSet('compare', 'Debit vs Credit', <ChartPoint>[
          ChartPoint('Debit', r.n('total_debit')),
          ChartPoint('Credit', r.n('total_credit')),
        ], adds: false),
      ];
    default:
      // Profit & Loss: income groups, expense groups, the totals.
      final List<FinNode> ti = r.subNodes('trading', 'income');
      final List<FinNode> te = r.subNodes('trading', 'expense');
      final List<FinNode> ii = r.subNodes('indirect', 'income');
      final List<FinNode> ie = r.subNodes('indirect', 'expense');
      final num gp = r.n('gross_profit');
      final num net = r.n('net_profit');
      return <FinChartSet>[
        FinChartSet('summary', 'Summary', <ChartPoint>[
          ChartPoint('Revenue', r.n('total_revenue')),
          ChartPoint('Expenses', r.n('total_expenses')),
          ChartPoint(gp >= 0 ? 'Gross profit' : 'Gross loss', gp.abs()),
          ChartPoint(net >= 0 ? 'Net profit' : 'Net loss', net.abs()),
        ], adds: false),
        FinChartSet(
          'income',
          'Income',
          _nonZero(<ChartPoint>[
            for (final FinNode n in <FinNode>[...ti, ...ii])
              if (n.amount > 0) ChartPoint(n.name, n.amount),
          ]),
        ),
        FinChartSet(
          'expenses',
          'Expenses',
          _nonZero(<ChartPoint>[
            for (final FinNode n in <FinNode>[...te, ...ie])
              if (n.amount > 0) ChartPoint(n.name, n.amount),
          ]),
        ),
      ];
  }
}

/// The graph card on a statement: series chips, the chart type switch and
/// the interactive chart (tap a bar / point / slice to read it).
class FinChartCard extends ConsumerWidget {
  const FinChartCard(this.report, {super.key});
  final FinReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final String kind = c.finKind;
    final List<FinChartSet> sets = finChartSets(report, kind);
    if (sets.isEmpty) return const SizedBox.shrink();
    final FinChartSet set = sets.firstWhere(
      (FinChartSet s) => s.key == c.finChartSets[kind],
      orElse: () => sets.first,
    );
    return Padding(
      key: const ValueKey<String>('finChart'),
      padding: const EdgeInsets.only(bottom: 12),
      child: Glass(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // The header opens / closes the graph (kept on the phone).
            Tap(
              key: const ValueKey<String>('finChartToggle'),
              onTap: c.toggleFinChart,
              radius: 14,
              child: Row(
                children: <Widget>[
                  Ico('chart', size: IcoSize.xs, color: Tc.of(context).acc),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Graph', style: rtStyle(context, 16.5))),
                  if (c.finChartOpen && set.adds)
                    Text(
                      inr(set.total),
                      key: const ValueKey<String>('finChartTotal'),
                      style: amtStyle(context, size: 14),
                    ),
                  if (!c.finChartOpen)
                    Text(
                      'Show',
                      style: ts(14, w: w700, c: Tc.of(context).acc),
                    ),
                  const SizedBox(width: 6),
                  Ic(
                    c.finChartOpen ? 'chevU' : 'chevD',
                    size: IcSize.s,
                    color: Tc.of(context).ink3,
                  ),
                ],
              ),
            ),
            if (c.finChartOpen) ...<Widget>[
              Chips(
                margin: const EdgeInsets.only(top: 8, bottom: 10),
                children: <Widget>[
                  for (final FinChartSet s in sets)
                    ChipBtn(
                      s.label,
                      key: ValueKey<String>('finChartSet-${s.key}'),
                      height: 36,
                      fontSize: 13.5,
                      on: s.key == set.key,
                      onTap: () => c.setFinChartSet(kind, s.key),
                    ),
                ],
              ),
              if (set.points.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    'Nothing to draw for this period.',
                    textAlign: TextAlign.center,
                    style: rsStyle(context),
                  ),
                )
              else
                TcChart(
                  key: ValueKey<String>('finChart-$kind-${set.key}'),
                  points: set.points,
                  type: c.finChartType,
                  onType: c.setFinChartType,
                  types: ReportChart.kAllTypes,
                  total: set.adds ? inr(set.total) : '',
                ),
            ],
          ],
        ),
      ),
    );
  }
}
