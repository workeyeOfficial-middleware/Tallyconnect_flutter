// Graphs on the financial statements (Balance Sheet, Profit & Loss, Trial
// Balance, Cash Flow, Expenses) and Tally's own reports: the same figures the
// report lists — its groups and totals for the period chosen — drawn as bar,
// column, line, scatter or pie. Nothing is worked out again; switching the
// chart never changes the report.
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

/// The series of statement [kind] (`bs`, `pl`, `tb`, `cf`, `exp`)
/// from its figures.
List<FinChartSet> finChartSets(FinReport r, String kind) {
  String mon(DateTime d) => '${kMonths[d.month - 1]} ${d.year % 100}';
  switch (kind) {
    case 'cf':
      // Cash Flow: money in / out by group (as listed), by month, both.
      final List<(DateTime, num, num)> months = r.cashMonths;
      return <FinChartSet>[
        FinChartSet(
          'inflow',
          'Money in',
          _nonZero(<ChartPoint>[
            for (final (String, num) g in r.pairs('inflow_groups'))
              ChartPoint(g.$1, g.$2),
          ]),
        ),
        FinChartSet(
          'outflow',
          'Money out',
          _nonZero(<ChartPoint>[
            for (final (String, num) g in r.pairs('outflow_groups'))
              ChartPoint(g.$1, g.$2),
          ]),
        ),
        if (months.length > 1) ...<FinChartSet>[
          FinChartSet('monthIn', 'In by month', <ChartPoint>[
            for (final (DateTime, num, num) m in months)
              ChartPoint(mon(m.$1), m.$2),
          ]),
          FinChartSet('monthOut', 'Out by month', <ChartPoint>[
            for (final (DateTime, num, num) m in months)
              ChartPoint(mon(m.$1), m.$3),
          ]),
        ],
        FinChartSet('compare', 'In vs Out', <ChartPoint>[
          ChartPoint('Money in', r.n('inflow')),
          ChartPoint('Money out', r.n('outflow')),
        ], adds: false),
      ];
    case 'exp':
      // Expenses: by group (top level, as the tree), top ledgers, by month.
      final List<(DateTime, num)> months = r.byMonth;
      return <FinChartSet>[
        FinChartSet(
          'groups',
          'By group',
          _nonZero(<ChartPoint>[
            for (final FinNode n in r.nodes('sections'))
              if (n.amount > 0) ChartPoint(n.name, n.amount),
          ]),
        ),
        FinChartSet(
          'ledgers',
          'Top ledgers',
          _nonZero(<ChartPoint>[
            for (final FinNode n in r.nodes('top_ledgers'))
              if (n.amount > 0) ChartPoint(n.name, n.amount),
          ]),
          adds: false,
        ),
        if (months.length > 1)
          FinChartSet('months', 'By month', <ChartPoint>[
            for (final (DateTime, num) m in months) ChartPoint(mon(m.$1), m.$2),
          ]),
      ];
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
    case 'pl':
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
    default:
      return const <FinChartSet>[];
  }
}

/// The series of one of Tally's own reports (exactly its lines): Balance
/// Sheet / P&L by side (Cr: liabilities / income, Dr: assets / expenses),
/// Trial Balance debit / credit by group, Cash Flow lines.
List<FinChartSet> tallyChartSets(TallyReport r) {
  if (r.report == 'trial_balance') {
    final Map<String, num> dr = <String, num>{}, cr = <String, num>{};
    for (final TbLedger l in r.ledgers) {
      final String g = l.parent.isEmpty ? l.name : l.parent;
      if (l.closing < 0) dr[g] = (dr[g] ?? 0) - l.closing;
      if (l.closing > 0) cr[g] = (cr[g] ?? 0) + l.closing;
    }
    List<ChartPoint> pts(Map<String, num> m) => _nonZero(<ChartPoint>[
      for (final MapEntry<String, num> e in m.entries)
        ChartPoint(e.key, e.value),
    ])..sort((ChartPoint a, ChartPoint b) => b.value.compareTo(a.value));
    return <FinChartSet>[
      FinChartSet('debit', 'Debit', pts(dr)),
      FinChartSet('credit', 'Credit', pts(cr)),
    ];
  }
  List<ChartPoint> side(bool credit) => _nonZero(<ChartPoint>[
    for (final TallyRow x in r.rows)
      if (x.main != null && (credit ? x.main! > 0 : x.main! < 0))
        ChartPoint(x.name, x.main!.abs()),
  ]);
  return switch (r.report) {
    'balance_sheet' => <FinChartSet>[
      FinChartSet('liabilities', 'Liabilities', side(true)),
      FinChartSet('assets', 'Assets', side(false)),
    ],
    'profit_loss' => <FinChartSet>[
      FinChartSet('income', 'Income', side(true)),
      FinChartSet('expenses', 'Expenses', side(false)),
    ],
    _ => <FinChartSet>[
      FinChartSet('in', 'Inflow lines', side(true), adds: false),
      FinChartSet('out', 'Outflow lines', side(false), adds: false),
    ],
  };
}

/// The graph card on a statement: series chips, the chart type switch and
/// the interactive chart (tap a bar / point / slice to read it).
class FinChartCard extends ConsumerWidget {
  const FinChartCard(this.report, {super.key});
  final FinReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    return GraphCard(kind: c.finKind, sets: finChartSets(report, c.finKind));
  }
}

/// The graph card of any report: [sets] are its series; [kind] keeps the
/// chosen series (on the phone). Open / closed and the chart type are the
/// same for every report.
class GraphCard extends ConsumerWidget {
  const GraphCard({super.key, required this.kind, required this.sets});
  final String kind;
  final List<FinChartSet> sets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
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
