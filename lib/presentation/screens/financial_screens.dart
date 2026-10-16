// Financial statements: Profit & Loss, Balance Sheet, Trial Balance and
// Expenses — Tally's own figures (synced by the Agent), shown as KPI tiles
// and expandable group → ledger lists, with period chips and PDF / WhatsApp
// sharing. Read-only.
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

/// Reports screen: the four statement tiles (only when allowed).
class FinancialTiles extends ConsumerWidget {
  const FinancialTiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    if (c.finCanView != true) return const SizedBox.shrink();
    final TcPalette p = Tc.of(context);
    const List<(String, String, String, String)> tiles =
        <(String, String, String, String)>[
          ('pl', 'Profit & Loss', 'Income, expenses, profit', 'chart'),
          ('bs', 'Balance Sheet', 'Assets and liabilities', 'building'),
          ('tb', 'Trial Balance', 'Every ledger, Dr / Cr', 'file'),
          ('exp', 'Expenses', 'Where the money goes', 'out'),
          ('cf', 'Cash Flow', 'Money in and out, from Tally', 'cash'),
        ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Sec(
          'Financial statements',
          margin: EdgeInsets.fromLTRB(8, 4, 8, 8),
        ),
        Grid(
          cols: 2,
          children: <Widget>[
            for (final (String, String, String, String) t in tiles)
              Tap(
                key: ValueKey<String>('fin-${t.$1}'),
                // Tally's own figures when the Agent fetched them.
                onTap: () => c.openStatement(t.$1),
                child: Glass(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 112),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Ico(t.$4, size: IcoSize.sm, color: p.acc),
                            const Spacer(),
                            if (c.hasTallyReport(t.$1))
                              Container(
                                key: ValueKey<String>('fin-tally-${t.$1}'),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: mix(p.pos, .14),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Tally',
                                  style: ts(11, w: w800, c: p.pos),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(t.$2, style: rtStyle(context)),
                        const SizedBox(height: 2),
                        Text(t.$3, style: rsStyle(context)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class FinancialReportScreen extends ConsumerWidget {
  const FinancialReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final FinReport? r = c.finData;
    final String title = AppController.kFinTitles[c.finKind] ?? 'Financials';
    final bool fresh = r != null && r.kind == c.finKind;
    return Scr(
      children: <Widget>[
        BackNav(
          actions: <Widget>[
            CBtn(
              'file',
              key: const ValueKey<String>('finShare'),
              onTap: fresh ? () => c.previewDoc(finDoc(c, r)) : null,
            ),
            CBtn('sync', onTap: c.finBusy ? null : c.loadFinancial),
          ],
        ),
        H1(title, afterNav: true),
        Sub(
          <String>[
            if ((r?.company ?? '').isNotEmpty) r!.company else c.companyName,
            if (c.finPeriodLabel.isNotEmpty) c.finPeriodLabel,
          ].join(' · '),
        ),
        if (c.finPresets.isNotEmpty)
          Chips(
            margin: const EdgeInsets.only(top: 2, bottom: 14),
            children: <Widget>[
              for (final (String, String) x in c.finPresets)
                ChipBtn(
                  x.$2,
                  key: ValueKey<String>('finPreset-${x.$1}'),
                  height: 38,
                  fontSize: 13.5,
                  icon: x.$1 == 'pick' ? 'calendar' : null,
                  on: c.finPreset == x.$1,
                  onTap: c.finBusy ? null : () => c.setFinPreset(x.$1),
                ),
            ],
          ),
        if (c.finError != null)
          InfoBox(c.finError!, icon: 'info')
        else if (!fresh)
          EmptyBox(c.finBusy ? 'Loading Tally figures…' : 'Choose a period.')
        else ...<Widget>[
          if (c.finBusy)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          ...switch (c.finKind) {
            'bs' => _balanceSheet(context, c, r),
            'tb' => _trialBalance(context, c, r),
            'exp' => _expenses(context, c, r),
            _ => _profitLoss(context, c, r),
          },
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Figures as computed by Tally and synced by the TallyConnect '
              'Agent. Tap a group to see its ledgers.',
              style: ts(12.5, h: 1.4, c: Tc.of(context).ink3),
            ),
          ),
        ],
      ],
    );
  }

  // ------------------------------------------------------- P&L
  List<Widget> _profitLoss(BuildContext context, AppController c, FinReport r) {
    final num net = r.n('net_profit');
    return <Widget>[
      _Kpis(<_Kpi>[
        _Kpi(
          net >= 0 ? 'Net profit' : 'Net loss',
          net.abs(),
          tone: net >= 0 ? 'pos' : 'neg',
          main: true,
        ),
        _Kpi(
          'Gross profit',
          r.n('gross_profit'),
          tone: r.n('gross_profit') >= 0 ? null : 'neg',
        ),
        _Kpi('Revenue', r.n('total_revenue')),
        _Kpi('Expenses', r.n('total_expenses')),
      ]),
      _Card(
        title: 'Trading account',
        children: <Widget>[
          _Head('Income'),
          _Tree(c, r.subNodes('trading', 'income'), 'ti'),
          _Line('Closing stock', r.sub('trading', 'closing_stock')),
          _Head('Expenses'),
          _Line('Opening stock', r.sub('trading', 'opening_stock')),
          _Tree(c, r.subNodes('trading', 'expense'), 'te'),
          _Total(
            r.n('gross_profit') >= 0 ? 'Gross profit' : 'Gross loss',
            r.n('gross_profit').abs(),
            tone: r.n('gross_profit') >= 0 ? 'pos' : 'neg',
          ),
        ],
      ),
      _Card(
        title: 'Profit & Loss account',
        children: <Widget>[
          _Head('Indirect income'),
          _Tree(c, r.subNodes('indirect', 'income'), 'ii', empty: 'None'),
          _Head('Indirect expenses'),
          _Tree(c, r.subNodes('indirect', 'expense'), 'ie', empty: 'None'),
          _Total(
            net >= 0 ? 'Net profit' : 'Net loss',
            net.abs(),
            tone: net >= 0 ? 'pos' : 'neg',
          ),
        ],
      ),
    ];
  }

  // --------------------------------------------- Balance Sheet
  List<Widget> _balanceSheet(
    BuildContext context,
    AppController c,
    FinReport r,
  ) {
    final num diff = r.n('difference');
    return <Widget>[
      _Kpis(<_Kpi>[
        _Kpi('Total assets', r.n('total_assets'), main: true),
        _Kpi('Total liabilities', r.n('total_liabilities')),
        _Kpi(
          'Profit this year',
          r.sub('profit_loss', 'current_period'),
          tone: r.sub('profit_loss', 'current_period') >= 0 ? 'pos' : 'neg',
        ),
      ]),
      if (diff.abs() >= 0.01) _Diff(diff),
      _Card(
        title: 'Liabilities',
        trailing: r.n('total_liabilities'),
        children: <Widget>[
          _Tree(c, r.nodes('liabilities'), 'l'),
          _Line('Profit & Loss A/c', r.sub('profit_loss', 'total'), bold: true),
          _Line(
            '   Opening balance',
            r.sub('profit_loss', 'opening'),
            sub: true,
          ),
          _Line(
            '   Current period',
            r.sub('profit_loss', 'current_period'),
            sub: true,
          ),
        ],
      ),
      _Card(
        title: 'Assets',
        trailing: r.n('total_assets'),
        children: <Widget>[_Tree(c, r.nodes('assets'), 'a')],
      ),
    ];
  }

  // --------------------------------------------- Trial Balance
  List<Widget> _trialBalance(
    BuildContext context,
    AppController c,
    FinReport r,
  ) {
    final num diff = r.n('difference');
    final List<String> ug = <String>[
      if (r.m['ungrouped'] is List)
        for (final Object? x in r.m['ungrouped']! as List<Object?>) '$x',
    ];
    return <Widget>[
      _Kpis(<_Kpi>[
        _Kpi('Total debit', r.n('total_debit'), main: true),
        _Kpi('Total credit', r.n('total_credit')),
      ]),
      if (diff.abs() >= 0.01) _Diff(diff),
      for (final FinNode s in r.nodes('sections'))
        _Card(
          title: s.name,
          trailing: s.amount,
          drcr: true,
          children: <Widget>[_Tree(c, s.children, 'tb/${s.name}', drcr: true)],
        ),
      if (ug.isNotEmpty)
        InfoBox(
          'Ledgers whose group is not synced yet: ${ug.take(5).join(', ')}'
          '${ug.length > 5 ? ' and ${ug.length - 5} more' : ''}.',
          icon: 'info',
        ),
    ];
  }

  // ------------------------------------------------- Expenses
  List<Widget> _expenses(BuildContext context, AppController c, FinReport r) {
    final TcPalette p = Tc.of(context);
    final List<(DateTime, num)> months = r.byMonth;
    final num maxM = months.fold<num>(
      0,
      (num a, (DateTime, num) x) => x.$2 > a ? x.$2 : a,
    );
    final List<FinNode> top = r.nodes('top_ledgers');
    return <Widget>[
      _Kpis(<_Kpi>[
        _Kpi('Total expenses', r.n('total'), main: true),
        if (top.isNotEmpty)
          _Kpi('Largest: ${top.first.name}', top.first.amount),
      ]),
      GlassList(
        margin: const EdgeInsets.only(bottom: 12),
        children: <Widget>[
          RowX(
            key: const ValueKey<String>('finPurchases'),
            minHeight: 56,
            onTap: c.finBusy ? null : c.toggleFinPurchases,
            children: <Widget>[
              const Expanded(
                child: RTx(
                  'Include purchases',
                  'Purchase accounts as an expense',
                ),
              ),
              Sw(c.finPurchases),
            ],
          ),
        ],
      ),
      if (months.length > 1)
        _Card(
          title: 'Month-wise',
          children: <Widget>[
            for (final (DateTime, num) m in months)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 64,
                      child: Text(
                        '${kMonths[m.$1.month - 1]} ${m.$1.year % 100}',
                        style: ts(13, c: p.ink2),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 10,
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(
                          color: navyA(.07),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: FractionallySizedBox(
                          widthFactor: maxM <= 0
                              ? 0
                              : (m.$2 / maxM).clamp(0, 1).toDouble(),
                          child: Container(
                            decoration: BoxDecoration(
                              color: p.acc,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 96,
                      child: Text(
                        inr(m.$2),
                        textAlign: TextAlign.right,
                        style: amtStyle(context, size: 13.5),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      if (top.isNotEmpty)
        _Card(
          title: 'Top expense ledgers',
          children: <Widget>[
            for (final FinNode n in top) _Line(n.name, n.amount),
          ],
        ),
      _Card(
        title: 'By group',
        trailing: r.n('total'),
        children: <Widget>[
          _Tree(
            c,
            r.nodes('sections'),
            'x',
            empty: 'No expenses in this period.',
          ),
        ],
      ),
    ];
  }
}

// ---------------------------------------------------------------- pieces

class _Kpi {
  const _Kpi(this.label, this.value, {this.tone, this.main = false});
  final String label;
  final num value;
  final String? tone;
  final bool main;
}

class _Kpis extends StatelessWidget {
  const _Kpis(this.items);
  final List<_Kpi> items;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          const double gap = 10;
          final double w = (box.maxWidth - gap) / 2;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: <Widget>[
              for (final _Kpi k in items)
                SizedBox(
                  width: k.main && items.length.isOdd ? box.maxWidth : w,
                  child: Glass(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          k.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ts(12.5, w: w600, c: p.ink3),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            inr(k.value),
                            style: ts(
                              k.main ? 22 : 17,
                              w: w800,
                              c: k.tone == 'neg'
                                  ? p.neg
                                  : (k.tone == 'pos' || k.main ? p.acc : p.ink),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.children,
    this.trailing,
    this.drcr = false,
  });
  final String title;
  final List<Widget> children;
  final num? trailing;
  final bool drcr;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Glass(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text(title, style: rtStyle(context, 16.5))),
                if (trailing != null)
                  Text(
                    _amt(trailing!, drcr),
                    style: amtStyle(context, size: 15),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
  }
}

String _amt(num v, bool drcr) => drcr
    ? (v == 0 ? inr(0) : '${inr(v.abs())} ${v > 0 ? 'Dr' : 'Cr'}')
    : inr(v);

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 2),
    child: Text(
      text.toUpperCase(),
      style: ts(11.5, w: w800, ls: .8, c: Tc.of(context).ink3),
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.bold = false, this.sub = false});
  final String label;
  final num value;
  final bool bold, sub;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: ts(
                sub ? 13.5 : 14.5,
                w: bold ? w700 : w400,
                c: sub ? p.ink2 : p.ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(inr(value), style: amtStyle(context, size: sub ? 13.5 : 14.5)),
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total(this.label, this.value, {this.tone});
  final String label;
  final num value;
  final String? tone;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final Color fg = tone == 'neg' ? p.neg : p.acc;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: ts(15, w: w800, c: fg),
            ),
          ),
          Text(
            inr(value),
            style: ts(16, w: w800, c: fg),
          ),
        ],
      ),
    );
  }
}

class _Diff extends StatelessWidget {
  const _Diff(this.diff);
  final num diff;

  @override
  Widget build(BuildContext context) => InfoBox(
    'Difference in opening balances: ${inr(diff.abs())}. Tally shows the '
    'same difference until the opening balances are corrected there.',
    icon: 'alert',
    margin: const EdgeInsets.only(bottom: 12),
  );
}

/// Groups (tap to open) and ledgers, indented by depth.
class _Tree extends StatelessWidget {
  const _Tree(this.c, this.nodes, this.path, {this.drcr = false, this.empty});
  final AppController c;
  final List<FinNode> nodes;
  final String path;
  final bool drcr;
  final String? empty;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final List<Widget> rows = <Widget>[];
    void add(FinNode n, String at, int depth) {
      final String key = '$at/${n.name}';
      final bool open = c.finOpen.contains(key);
      rows.add(
        InkWell(
          key: ValueKey<String>('finNode-$key'),
          onTap: n.isGroup && n.children.isNotEmpty
              ? () => c.toggleFinNode(key)
              : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: EdgeInsets.fromLTRB(depth * 14.0, 8, 0, 8),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 18,
                  child: n.isGroup && n.children.isNotEmpty
                      ? AnimatedRotation(
                          turns: open ? .25 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: Ic('chevR', size: IcSize.xs, color: p.ink3),
                        )
                      : null,
                ),
                Expanded(
                  child: Text(
                    n.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: ts(
                      14.5,
                      w: n.isGroup ? w700 : w400,
                      c: n.isGroup ? p.ink : p.ink2,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _amt(n.amount, drcr),
                  style: amtStyle(context, size: n.isGroup ? 14.5 : 13.5),
                ),
              ],
            ),
          ),
        ),
      );
      if (open) {
        for (final FinNode ch in n.children) {
          add(ch, key, depth + 1);
        }
      }
    }

    for (final FinNode n in nodes) {
      add(n, path, 0);
    }
    if (rows.isEmpty && empty != null) {
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(empty!, style: ts(13.5, c: p.ink3)),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

/// "Pick month": the month-end dates with Tally figures.
class FinPickSheet extends ConsumerWidget {
  const FinPickSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    return Sheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SheetHead(
            c.finAsOn ? 'As on month end' : 'Pick a month',
            sub: 'Months with Tally figures synced by the Agent',
          ),
          GlassList(
            children: <Widget>[
              for (final DateTime d in c.finMonths)
                RowX(
                  key: ValueKey<String>('finMonth-${d.year}-${d.month}'),
                  minHeight: 56,
                  onTap: () => c.pickFinMonth(d),
                  children: <Widget>[
                    Expanded(
                      child: RTx(
                        monthYear(d),
                        c.finAsOn
                            ? 'As on ${dmy(d)}'
                            : '1 – ${d.day} ${kMonths[d.month - 1]}',
                      ),
                    ),
                    chevR(),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          Btn(label: 'Cancel', kind: BtnKind.g, onTap: c.closeOv),
        ],
      ),
    );
  }
}

/// PDF of the open statement (every group and ledger, indented).
ShareDoc finDoc(AppController c, FinReport r) {
  final List<List<String>> rows = <List<String>>[];
  final bool drcr = r.kind == 'tb';
  void walk(List<FinNode> ns, int depth) {
    for (final FinNode n in ns) {
      rows.add(<String>['${'   ' * depth}${n.name}', _amt(n.amount, drcr)]);
      walk(n.children, depth + 1);
    }
  }

  void head(String t) => rows.add(<String>[t.toUpperCase(), '']);
  final List<(String, String)> totals = <(String, String)>[];
  switch (r.kind) {
    case 'bs':
      head('Liabilities');
      walk(r.nodes('liabilities'), 1);
      rows.add(<String>[
        '   Profit & Loss A/c',
        inr(r.sub('profit_loss', 'total')),
      ]);
      head('Assets');
      walk(r.nodes('assets'), 1);
      totals.addAll(<(String, String)>[
        ('Total liabilities', inr(r.n('total_liabilities'))),
        ('Total assets', inr(r.n('total_assets'))),
      ]);
    case 'tb':
      for (final FinNode s in r.nodes('sections')) {
        rows.add(<String>[s.name.toUpperCase(), _amt(s.amount, true)]);
        walk(s.children, 1);
      }
      totals.addAll(<(String, String)>[
        ('Total debit', inr(r.n('total_debit'))),
        ('Total credit', inr(r.n('total_credit'))),
      ]);
    case 'exp':
      walk(r.nodes('sections'), 0);
      totals.add(('Total expenses', inr(r.n('total'))));
    default:
      head('Trading — income');
      walk(r.subNodes('trading', 'income'), 1);
      rows.add(<String>[
        '   Closing stock',
        inr(r.sub('trading', 'closing_stock')),
      ]);
      head('Trading — expenses');
      rows.add(<String>[
        '   Opening stock',
        inr(r.sub('trading', 'opening_stock')),
      ]);
      walk(r.subNodes('trading', 'expense'), 1);
      head('Indirect income');
      walk(r.subNodes('indirect', 'income'), 1);
      head('Indirect expenses');
      walk(r.subNodes('indirect', 'expense'), 1);
      totals.addAll(<(String, String)>[
        ('Gross profit', inr(r.n('gross_profit'))),
        ('Net profit', inr(r.n('net_profit'))),
      ]);
  }
  final String title = AppController.kFinTitles[r.kind] ?? 'Financials';
  return ShareDoc(
    title: title,
    subtitle: c.finPeriodLabel,
    company: r.company.isNotEmpty ? r.company : c.companyName,
    fileStem: title.replaceAll(RegExp(r'[^A-Za-z]+'), '_'),
    facts: <(String, String)>[
      ('Period', c.finPeriodLabel),
      ('Source', 'Tally (via TallyConnect Agent)'),
    ],
    table: DocTable(
      const <String>['Particulars', 'Amount'],
      rows,
      right: const <int>{1},
    ),
    totals: totals,
  );
}
