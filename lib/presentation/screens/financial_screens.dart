// Financial statements: Profit & Loss, Balance Sheet, Trial Balance and
// Expenses — Tally's own figures (synced by the Agent), shown as KPI tiles
// and expandable group → ledger lists, with period chips and PDF / WhatsApp
// sharing. Read-only.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/design/tc_fields.dart';
import '../../core/design/tc_icons.dart';
import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';
import '../../core/share/share_doc.dart';
import '../../core/utils/format.dart';
import '../../data/models/models.dart';
import '../widgets/common.dart';
import '../widgets/report_loader.dart';
import '../widgets/report_card.dart';
import 'cashflow_screens.dart' show CashflowTile, FromToBar;
import 'einvoice_screens.dart' show EinvoiceTile;
import 'fin_charts.dart' show FinChartCard;

/// Reports screen: the Financial statements section (only when allowed) —
/// Balance Sheet, P&L, Trial Balance, Cash Flow, Cash Flow Forecast and
/// Expenses, each the same square card.
class FinancialTiles extends ConsumerWidget {
  const FinancialTiles({super.key, this.title = true});

  /// Shows the "Financial statements" heading (not under its own tab).
  final bool title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    if (c.finCanView != true) return const SizedBox.shrink();
    Widget tile(String k, String title, String sub, String icon) => ReportCard(
      key: ValueKey<String>('fin-$k'),
      icon: icon,
      title: title,
      subtitle: sub,
      onTap: () {
        if (c.guardTap('fin', k)) c.openStatement(k);
      },
    );
    final bool live = c.repo.isRemote && !c.demo;
    // Each tile is a card: long-press to pin, hide, share or drag it.
    final ({List<(String, Widget)> rows, int hidden, VoidCallback unhide})
    v = c.listView<(String, Widget)>('fin', <(String, Widget)>[
      ('bs', tile('bs', 'Balance Sheet', 'Assets and liabilities', 'building')),
      ('pl', tile('pl', 'Profit & Loss', 'Income, expenses, profit', 'chart')),
      (
        'tb',
        tile('tb', 'Trial Balance', 'Every ledger, Debit / Credit', 'file'),
      ),
      (
        'cf',
        tile('cf', 'Cash Flow', 'Cash and bank: money in and out', 'cash'),
      ),
      if (live) ('cfcast', const CashflowTile()),
      ('exp', tile('exp', 'Expenses', 'Where the money goes', 'out')),
      if (live) ('einv', const EinvoiceTile()),
    ], ((String, Widget) x) => x.$1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (title)
          const Sec(
            'Financial statements',
            margin: EdgeInsets.fromLTRB(8, 4, 8, 8),
          ),
        Grid(
          cols: 2,
          children: <Widget>[
            for (final (String, Widget) x in v.rows)
              LRow(
                list: 'fin',
                lk: x.$1,
                radius: 22,
                pinCorner: true,
                child: x.$2,
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
        const SizedBox(height: 4),
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
    // Only the report of the period now chosen (never another period's).
    final bool fresh = r != null && c.finDataCurrent;
    // Shared from the Reports card menu: once the statement is loaded.
    if (fresh && !c.finBusy && c.takePendingShare(c.finKind)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => c.previewDoc(finDoc(c, r)),
      );
    }
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
        // From / To (Tally's F2 period) on every statement: any dates when
        // the vouchers are synced from the books' start, else the synced
        // month ends (checked in the sheet); the drill-down keeps them.
        if (c.finTo != null)
          FromToBar(
            from: c.finFrom ?? c.finTo!,
            to: c.finTo!,
            fromLabel: c.finAsOn ? 'Period from' : 'From',
            toLabel: c.finAsOn ? 'As at' : 'To',
            onTap: c.finBusy ? null : c.openFinRange,
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
        // A year end whose closing stock is missing: that year's P&L /
        // Balance Sheet need it. The admin enters it (Tally can't be asked
        // for a past date's stock without freezing it).
        for (final DateTime d
            in c.finPeriods?.stockNeeded ?? const <DateTime>[]) ...<Widget>[
          InfoBox(
            c.finPeriods!.canEnterStock
                ? 'Closing stock as on ${dmy(d)} is missing — needed for the '
                      'year after it. Enter it from TallyPrime\'s Stock Summary.'
                : 'Closing stock as on ${dmy(d)} is missing. Ask your admin to '
                      'enter it.',
            icon: 'info',
            margin: const EdgeInsets.only(bottom: 10),
          ),
          if (c.finPeriods!.canEnterStock)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Btn(
                key: ValueKey<String>('finStock-${d.year}-${d.month}-${d.day}'),
                label: 'Enter closing stock as on ${dmy(d)}',
                kind: BtnKind.g,
                onTap: () => c.openFinStock(d),
              ),
            ),
        ],
        if (c.finError != null)
          InfoBox(c.finError!, icon: 'info')
        else if (!fresh)
          (c.finBusy ? const ReportLoader() : EmptyBox('Choose a period.'))
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
            'cf' => _cashFlow(context, c, r),
            _ => _profitLoss(context, c, r),
          },
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              c.finKind == 'cf'
                  ? 'Counted as TallyPrime\'s Cash Flow: the vouchers Tally '
                        'marks as cash flow, each by its other side. Transfers '
                        'between your own cash / bank accounts are neither in '
                        'nor out. Tap a month to see just that month.'
                  : 'Worked out from Tally\'s ledgers, vouchers and closing '
                        'stock, synced by the TallyConnect Agent. Tap a group '
                        'to open it, a ledger to see its vouchers.',
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
      // Graph of the same figures (chart type / series switchable).
      FinChartCard(r),
      // Tally's Profit & Loss A/c: each group on the side its balance is on
      // (an income group with a debit balance shows on the debit side).
      ..._plTally(c, r),
    ];
  }

  List<Widget> _plTally(AppController c, FinReport r) {
    final num gp = r.n('gross_profit');
    final num net = r.n('net_profit');
    final num os = r.sub('trading', 'opening_stock');
    final num cs = r.sub('trading', 'closing_stock');
    final List<FinNode> ti = r.subNodes('trading', 'income');
    final List<FinNode> te = r.subNodes('trading', 'expense');
    final List<FinNode> ii = r.subNodes('indirect', 'income');
    final List<FinNode> ie = r.subNodes('indirect', 'expense');
    num pos(List<FinNode> ns) => sumRupees(<num>[
      for (final FinNode n in ns)
        if (n.amount >= 0) n.amount,
    ]);
    num neg(List<FinNode> ns) => sumRupees(<num>[
      for (final FinNode n in ns)
        if (n.amount < 0) -n.amount,
    ]);
    final num tradingTotal = sumRupees(<num>[
      os,
      pos(te),
      neg(ti),
      if (gp >= 0) gp,
    ]);
    final num plTotal = sumRupees(<num>[
      if (gp < 0) -gp,
      pos(ie),
      neg(ii),
      if (net >= 0) net,
    ]);
    List<Widget> side(List<(FinNode, int, String)> ns) {
      final List<Widget> out = <Widget>[];
      for (final (FinNode, int, String) x in ns) {
        _nodeRows(c, x.$1, x.$2, x.$3, 0, out);
      }
      return out;
    }

    final num big = _maxAbs(<num>[tradingTotal, plTotal, os, cs]);
    return <Widget>[
      _Card(
        title: 'Trading account',
        table: big,
        children: <Widget>[
          const _Head('Debit'),
          _TRow('Opening Stock', a: os, bold: true),
          ...side(<(FinNode, int, String)>[
            for (final FinNode n in te)
              if (n.amount >= 0) (n, 1, 'te'),
            for (final FinNode n in ti)
              if (n.amount < 0) (n, -1, 'ti'),
          ]),
          if (gp >= 0)
            _TRow('Gross Profit c/o', a: gp, bold: true, italic: true),
          _TTotal('Total', tradingTotal),
          const _Head('Credit'),
          ...side(<(FinNode, int, String)>[
            for (final FinNode n in ti)
              if (n.amount >= 0) (n, 1, 'ti'),
          ]),
          _TRow('Closing Stock', a: cs, bold: true),
          ...side(<(FinNode, int, String)>[
            for (final FinNode n in te)
              if (n.amount < 0) (n, -1, 'te'),
          ]),
          if (gp < 0) _TRow('Gross Loss c/o', a: -gp, bold: true, italic: true),
          _TTotal('Total', tradingTotal),
        ],
      ),
      _Card(
        title: 'Profit & Loss account',
        table: big,
        children: <Widget>[
          const _Head('Debit'),
          if (gp < 0) _TRow('Gross Loss b/f', a: -gp, bold: true, italic: true),
          ...side(<(FinNode, int, String)>[
            for (final FinNode n in ie)
              if (n.amount >= 0) (n, 1, 'ie'),
            for (final FinNode n in ii)
              if (n.amount < 0) (n, -1, 'ii'),
          ]),
          if (net >= 0) _TRow('Nett Profit', a: net, bold: true, italic: true),
          _TTotal('Total', plTotal),
          const _Head('Credit'),
          if (gp >= 0)
            _TRow('Gross Profit b/f', a: gp, bold: true, italic: true),
          ...side(<(FinNode, int, String)>[
            for (final FinNode n in ii)
              if (n.amount >= 0) (n, 1, 'ii'),
            for (final FinNode n in ie)
              if (n.amount < 0) (n, -1, 'ie'),
          ]),
          if (net < 0) _TRow('Nett Loss', a: -net, bold: true, italic: true),
          _TTotal('Total', plTotal),
        ],
      ),
    ];
  }

  // --------------------------------------------- Balance Sheet
  /// Tally's Balance Sheet: Liabilities and Assets, each group on the side
  /// its balance is on (a Capital Account with a debit balance shows under
  /// Assets), the Profit & Loss A/c with its Opening Balance and Current
  /// Period, any difference in opening balances, equal totals.
  List<Widget> _balanceSheet(
    BuildContext context,
    AppController c,
    FinReport r,
  ) {
    final List<FinNode> liab = r.nodes('liabilities');
    final List<FinNode> assets = r.nodes('assets');
    final num pl = r.sub('profit_loss', 'total');
    final int plSign = pl >= 0 ? 1 : -1;
    final List<(FinNode, int, String)> lSide = <(FinNode, int, String)>[
      for (final FinNode n in liab)
        if (n.amount >= 0) (n, 1, 'l'),
      for (final FinNode n in assets)
        if (n.amount < 0) (n, -1, 'a'),
    ];
    final List<(FinNode, int, String)> aSide = <(FinNode, int, String)>[
      for (final FinNode n in assets)
        if (n.amount >= 0) (n, 1, 'a'),
      for (final FinNode n in liab)
        if (n.amount < 0) (n, -1, 'l'),
    ];
    num total(List<(FinNode, int, String)> s, bool withPl) => sumRupees(<num>[
      for (final (FinNode, int, String) x in s) x.$1.amount * x.$2,
      if (withPl) pl.abs(),
    ]);
    final num sumL = total(lSide, pl >= 0);
    final num sumA = total(aSide, pl < 0);
    final num diff = paise(sumA - sumL); // > 0: liabilities short
    final num grand = diff > 0 ? sumA : sumL;

    List<Widget> rows(
      List<(FinNode, int, String)> s,
      bool plHere,
      bool diffHere,
    ) {
      final List<Widget> out = <Widget>[];
      for (final (FinNode, int, String) x in s) {
        _nodeRows(c, x.$1, x.$2, x.$3, 0, out);
      }
      if (plHere) {
        out.addAll(<Widget>[
          _TRow('Profit & Loss A/c', a: pl.abs(), bold: true),
          _TRow(
            'Opening Balance',
            a: r.sub('profit_loss', 'opening') * plSign,
            depth: 1,
            italic: true,
            signed: true,
          ),
          _TRow(
            'Current Period',
            a: r.sub('profit_loss', 'current_period') * plSign,
            depth: 1,
            italic: true,
            signed: true,
          ),
        ]);
      }
      if (diffHere) {
        out.add(
          _TRow('Difference in opening balances', a: diff.abs(), italic: true),
        );
      }
      return out;
    }

    return <Widget>[
      // Graph of the same figures (chart type / series switchable).
      FinChartCard(r),
      _Card(
        title: 'Liabilities',
        table: grand,
        signed: true,
        children: <Widget>[
          ...rows(lSide, pl >= 0, diff > 0),
          _TTotal('Total', grand),
        ],
      ),
      _Card(
        title: 'Assets',
        table: grand,
        signed: true,
        children: <Widget>[
          ...rows(aSide, pl < 0, diff < 0),
          _TTotal('Total', grand),
        ],
      ),
    ];
  }

  // --------------------------------------------- Trial Balance
  /// Tally's Trial Balance: Particulars | Debit | Credit. A group shows the
  /// debit balances and the credit balances of its ledgers separately (as
  /// Tally does), the Profit & Loss A/c and any difference in opening
  /// balances below, then the Grand Total.
  List<Widget> _trialBalance(
    BuildContext context,
    AppController c,
    FinReport r,
  ) {
    final num diff = r.n('difference'); // Dr − Cr
    final List<String> ug = <String>[
      if (r.m['ungrouped'] is List)
        for (final Object? x in r.m['ungrouped']! as List<Object?>) '$x',
    ];
    final List<FinNode> sections = r.nodes('sections');
    final List<Widget> rows = <Widget>[
      const _THead(<String>['Particulars', 'Debit', 'Credit']),
    ];
    for (final FinNode s in sections) {
      if (s.nature == 'other') continue;
      _tbRows(c, s, 'tb', 0, rows);
    }
    // Ledgers directly under Primary (e.g. Profit & Loss A/c).
    for (final FinNode s in sections) {
      if (s.nature != 'other') continue;
      for (final FinNode l in s.children) {
        _tbRows(c, l, 'tb/other', 0, rows);
      }
    }
    if (diff.abs() >= 0.01) {
      rows.add(
        _TRow(
          'Difference in opening balances',
          a: diff < 0 ? -diff : null,
          b: diff > 0 ? diff : null,
          two: true,
          italic: true,
        ),
      );
    }
    final num grandDr = sumRupees(<num>[
      r.n('total_debit'),
      if (diff < 0) -diff,
    ]);
    final num grandCr = sumRupees(<num>[
      r.n('total_credit'),
      if (diff > 0) diff,
    ]);
    rows.add(_TTotal('Grand Total', grandDr, b: grandCr, two: true));
    return <Widget>[
      // Graph of the same figures (chart type / series switchable).
      FinChartCard(r),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Glass(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          // Columns as wide as the Grand Total (the largest amount).
          child: _TTable(
            max: _maxAbs(<num>[grandDr, grandCr]),
            two: true,
            children: rows,
          ),
        ),
      ),
      if (ug.isNotEmpty)
        InfoBox(
          'Ledgers whose group is not synced yet: ${ug.take(5).join(', ')}'
          '${ug.length > 5 ? ' and ${ug.length - 5} more' : ''}.',
          icon: 'info',
        ),
    ];
  }

  // ------------------------------------------------- Cash Flow
  /// Cash Flow statement for the period, from the cash / bank vouchers.
  List<Widget> _cashFlow(BuildContext context, AppController c, FinReport r) {
    final List<(DateTime, num, num)> months = r.cashMonths;
    final List<(String, num)> ins = r.pairs('inflow_groups');
    final List<(String, num)> outs = r.pairs('outflow_groups');
    final List<(String, num, num)> accts = r.cashAccounts;
    if (r.n('cash_ledgers') == 0) {
      return <Widget>[
        const InfoBox(
          'No cash or bank ledgers are synced for this company yet (ledgers '
          'under Cash-in-Hand or Bank Accounts).',
          icon: 'info',
        ),
      ];
    }
    return <Widget>[
      _Kpis(<_Kpi>[
        _Kpi('Closing balance', r.n('closing'), main: true),
        _Kpi('Opening balance', r.n('opening')),
        _Kpi('Money in', r.n('inflow'), tone: 'pos'),
        _Kpi('Money out', r.n('outflow'), tone: 'neg'),
      ]),
      FinChartCard(r),
      _Card(
        title: 'Month-wise',
        table: _maxAbs(<num>[r.n('inflow'), r.n('outflow'), r.n('net')]),
        two: true,
        signed: true,
        children: <Widget>[
          const _THead(<String>['Month', 'Money in', 'Money out']),
          for (final (DateTime, num, num) m in months)
            _TRow(
              '${kMonths[m.$1.month - 1]} ${m.$1.year}',
              key: ValueKey<String>('cfMonth-${m.$1.year}-${m.$1.month}'),
              a: m.$2 == 0 ? null : m.$2,
              b: m.$3 == 0 ? null : m.$3,
              two: true,
              onTap: months.length > 1 ? () => c.pickCashMonth(m.$1) : null,
            ),
          _TTotal('Total', r.n('inflow'), b: r.n('outflow'), two: true),
          _TRow('Nett flow', a: r.n('net'), bold: true, signed: true),
        ],
      ),
      // Cash / bank moved by vouchers Tally's Cash Flow does not count (as
      // in Tally): opening + nett flow + this = closing.
      if (r.n('not_in_flow').abs() >= .01)
        InfoBox(
          '${r.n('not_in_flow') < 0 ? '−' : ''}${inr2(r.n('not_in_flow').abs())} '
          'of cash / bank movement is not in Cash Flow, as in Tally: vouchers '
          'Tally did not mark as cash flow (e.g. journals entered before a '
          'ledger was moved under Cash-in-Hand). Opening + Nett flow + this '
          '= Closing.',
          key: const ValueKey<String>('cfNotInFlow'),
          icon: 'info',
        ),
      _Card(
        title: 'Money in, by group',
        table: _maxAbs(ins.map(((String, num) g) => g.$2)),
        children: <Widget>[
          if (ins.isEmpty) const _TRow('None'),
          for (final (String, num) g in ins) _TRow(g.$1, a: g.$2),
        ],
      ),
      _Card(
        title: 'Money out, by group',
        table: _maxAbs(outs.map(((String, num) g) => g.$2)),
        children: <Widget>[
          if (outs.isEmpty) const _TRow('None'),
          for (final (String, num) g in outs) _TRow(g.$1, a: g.$2),
        ],
      ),
      if (accts.isNotEmpty)
        _Card(
          title: 'Cash and bank accounts',
          table: _maxAbs(<num>[
            for (final (String, num, num) x in accts) ...<num>[x.$2, x.$3],
          ]),
          two: true,
          signed: true,
          children: <Widget>[
            const _THead(<String>['Account', 'Opening', 'Closing']),
            for (final (String, num, num) x in accts)
              _TRow(x.$1, a: x.$2, b: x.$3, two: true, signed: true),
          ],
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
      FinChartCard(r),
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
          table: _maxAbs(top.map((FinNode n) => n.amount)),
          children: <Widget>[
            for (final FinNode n in top)
              _TRow(n.name, a: n.amount, onTap: () => c.openFinLedger(n)),
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
    this.table,
    this.two = false,
    this.signed = false,
  });
  final String title;
  final List<Widget> children;
  final num? trailing;

  /// The largest amount of a Tally table card (its columns fit it; see
  /// [_TTable]); null: a plain card.
  final num? table;
  final bool two, signed;

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
                  Text(inr(trailing!), style: amtStyle(context, size: 15)),
              ],
            ),
            const SizedBox(height: 6),
            if (table == null)
              ...children
            else
              _TTable(
                max: table!,
                two: two,
                signed: signed,
                children: children,
              ),
          ],
        ),
      ),
    );
  }
}

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

/// Tally's amount: Indian grouping, two decimals, no ₹ sign.
String tAmt(num v) => inr2(v.abs()).replaceAll('₹', '').replaceAll('−', '');

/// A group (tap to open / close) or a ledger (tap for its vouchers) and,
/// when open, its children — one amount column; [sign] −1 shows a group on
/// the other side (its balance flipped, as Tally does).
void _nodeRows(
  AppController c,
  FinNode n,
  int sign,
  String at,
  int depth,
  List<Widget> out,
) {
  final String key = '$at/${n.name}';
  final bool expandable = n.isGroup && n.children.isNotEmpty;
  final bool open = expandable && c.finOpen.contains(key);
  out.add(
    _TRow(
      n.name,
      key: ValueKey<String>('finNode-$key'),
      a: n.amount * sign,
      depth: depth,
      bold: n.isGroup && depth == 0,
      signed: depth > 0,
      open: expandable ? open : null,
      onTap: expandable
          ? () => c.toggleFinNode(key)
          : (n.isGroup ? null : () => c.openFinLedger(n)),
    ),
  );
  if (open) {
    for (final FinNode ch in n.children) {
      _nodeRows(c, ch, sign, key, depth + 1, out);
    }
  }
}

/// A Trial Balance row's Debit and Credit: a group's debit balances and
/// credit balances apart (plus what its ledgers don't explain — Stock-in-
/// Hand's value — on its side); a ledger's balance in its column. Shared by
/// the table and its graph, so both show the same figures.
(num, num) tbDrCr(FinNode n) {
  if (!n.isGroup) return n.amount >= 0 ? (n.amount, 0) : (0, -n.amount);
  final List<num> ds = <num>[], cs = <num>[];
  void walk(FinNode x) {
    if (!x.isGroup) {
      (x.amount >= 0 ? ds : cs).add(x.amount.abs());
      return;
    }
    for (final FinNode ch in x.children) {
      walk(ch);
    }
  }

  walk(n);
  num dr = sumRupees(ds);
  num cr = sumRupees(cs);
  final num rest = paise(n.amount - (dr - cr));
  if (rest > 0) dr = sumRupees(<num>[dr, rest]);
  if (rest < 0) cr = sumRupees(<num>[cr, -rest]);
  return (dr, cr);
}

/// Trial Balance rows: a group shows its debit balances and its credit
/// balances apart; a ledger its balance in the Debit or Credit column.
void _tbRows(
  AppController c,
  FinNode n,
  String at,
  int depth,
  List<Widget> out,
) {
  final String key = '$at/${n.name}';
  final bool expandable = n.isGroup && n.children.isNotEmpty;
  final bool open = expandable && c.finOpen.contains(key);
  final (num dr, num cr) = tbDrCr(n);
  out.add(
    _TRow(
      n.name,
      key: ValueKey<String>('finNode-$key'),
      a: dr == 0 ? null : dr,
      b: cr == 0 ? null : cr,
      two: true,
      depth: depth,
      bold: n.isGroup && depth == 0,
      open: expandable ? open : null,
      onTap: expandable
          ? () => c.toggleFinNode(key)
          : (n.isGroup ? null : () => c.openFinLedger(n)),
    ),
  );
  if (open) {
    for (final FinNode ch in n.children) {
      _tbRows(c, ch, key, depth + 1, out);
    }
  }
}

/// The largest absolute amount of [vs] (0 when none).
num _maxAbs(Iterable<num> vs) =>
    vs.fold<num>(0, (num a, num v) => v.abs() > a ? v.abs() : a);

/// Amount column width outside a [_TTable] (and the narrowest one inside).
const double _kAmtW = 92;

/// Space kept between two amount columns (and before the first one).
const double _kColGap = 12;

/// Narrowest the Particulars column may get before the amounts move to a
/// line of their own under the name (names wrap to two lines above it).
const double _kMinLabel = 96;

/// One size for every amount of a table (rows, groups and totals alike), so
/// the columns line up and read evenly; groups and totals are only bolder.
const double _kAmtSize = 14;

/// The amount columns of the table around: their width (fits the largest
/// amount at full size) and whether each row puts its amounts on a line of
/// their own (a phone too narrow for name + columns side by side).
class _Cols extends InheritedWidget {
  const _Cols({
    required this.w,
    required this.stacked,
    required super.child,
    this.scale = 1,
  });
  final double w;
  final bool stacked;

  /// Below 1 only when even a line of their own is too narrow for the
  /// columns at full size: every amount of the table shrinks alike (equal
  /// sizes, still aligned, nothing clipped).
  final double scale;

  static _Cols? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Cols>();

  @override
  bool updateShouldNotify(_Cols old) =>
      old.w != w || old.stacked != stacked || old.scale != scale;
}

/// A Tally table: amount columns as wide as the largest amount ([max], at
/// the total row's bold size) plus a gap — never squeezed, clipped or
/// touching. When name + columns do not fit the width, every row shows its
/// name on one line and its amounts right-aligned under it.
class _TTable extends StatelessWidget {
  const _TTable({
    required this.max,
    required this.children,
    this.two = false,
    this.signed = false,
  });
  final num max;
  final List<Widget> children;
  final bool two, signed;

  @override
  Widget build(BuildContext context) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: '${signed ? '(−) ' : ''}${tAmt(max)}',
        style: amtStyle(
          context,
          size: _kAmtSize,
        ).copyWith(fontWeight: FontWeight.w800),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final double textW = tp.width.ceilToDouble();
    final double full = math.max(_kAmtW, textW + _kColGap);
    tp.dispose();
    final int n = two ? 2 : 1;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double avail = box.maxWidth;
        final bool stacked =
            avail.isFinite && avail < n * full + 18 + _kMinLabel;
        double w = full, scale = 1;
        if (stacked && n * full > avail) {
          w = avail / n;
          scale = ((w - _kColGap) / textW).clamp(.5, 1).toDouble();
        }
        return _Cols(
          w: w,
          stacked: stacked,
          scale: scale,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        );
      },
    );
  }
}

/// [s] at the table's amount scale (see [_Cols.scale]).
TextStyle _scaled(BuildContext context, TextStyle s) {
  final double f = _Cols.of(context)?.scale ?? 1;
  return f >= 1 ? s : s.copyWith(fontSize: (s.fontSize ?? 14) * f);
}

/// One amount cell: right-aligned in its column; only shrinks if the text
/// is larger than measured (e.g. a bigger amount than the table's max).
Widget _amtCell(double w, String? text, TextStyle style) => SizedBox(
  width: w,
  child: text == null
      ? null
      : Padding(
          padding: const EdgeInsets.only(left: _kColGap),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(text, maxLines: 1, style: style),
          ),
        ),
);

/// Name, then the amounts — side by side, or (stacked) the amounts on a
/// line of their own, right-aligned under the name.
Widget _nameAndAmounts(bool stacked, Widget name, List<Widget> amounts) =>
    stacked
    ? Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          name,
          const SizedBox(height: 3),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: amounts),
        ],
      )
    : Row(
        children: <Widget>[
          Expanded(child: name),
          ...amounts,
        ],
      );

/// Column headings: Particulars | Debit | Credit (or the given names).
class _THead extends StatelessWidget {
  const _THead(this.cols);
  final List<String> cols;

  @override
  Widget build(BuildContext context) {
    final TextStyle st = ts(11.5, w: w800, ls: .6, c: Tc.of(context).ink3);
    final _Cols? tc = _Cols.of(context);
    final double w = tc?.w ?? _kAmtW;
    return Container(
      padding: const EdgeInsets.only(bottom: 6, top: 2),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: navyA(.12))),
      ),
      child: _nameAndAmounts(
        tc?.stacked ?? false,
        Text(
          cols.first.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: st,
        ),
        <Widget>[
          for (final String h in cols.skip(1))
            SizedBox(
              width: w,
              child: Text(
                h.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: st,
              ),
            ),
        ],
      ),
    );
  }
}

/// One Tally row: particulars (indented, with a chevron when it opens) and
/// one or two right-aligned amount columns.
class _TRow extends StatelessWidget {
  const _TRow(
    this.label, {
    super.key,
    this.a,
    this.b,
    this.two = false,
    this.depth = 0,
    this.bold = false,
    this.italic = false,
    this.signed = false,
    this.open,
    this.onTap,
  });
  final String label;
  final num? a, b;
  final bool two, bold, italic, signed;
  final int depth;

  /// null: not expandable; else whether it is open.
  final bool? open;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final _Cols? cols = _Cols.of(context);
    final double w = cols?.w ?? _kAmtW;
    final double size = depth > 0 ? 13.5 : 14.5;
    // In a table every amount has the same size (only weight differs).
    final TextStyle amt = _scaled(
      context,
      amtStyle(context, size: cols == null ? size : _kAmtSize).copyWith(
        fontWeight: bold ? FontWeight.w800 : null,
        fontStyle: italic ? FontStyle.italic : null,
      ),
    );
    String? text(num? v) =>
        v == null ? null : '${signed && v < 0 ? '(−) ' : ''}${tAmt(v)}';
    // Only the name is indented (a line of amounts keeps the full width).
    final Widget name = Row(
      children: <Widget>[
        SizedBox(width: depth * 14.0),
        SizedBox(
          width: 18,
          child: open == null
              ? null
              : AnimatedRotation(
                  turns: open! ? .25 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Ic('chevR', size: IcSize.xs, color: p.ink3),
                ),
        ),
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: ts(
              size,
              w: bold ? w700 : w400,
              c: depth > 0 ? p.ink2 : p.ink,
            ).copyWith(fontStyle: italic ? FontStyle.italic : null),
          ),
        ),
      ],
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        // Top-level rows of a table: a hairline between them, so each
        // name reads with its own amounts.
        decoration: cols != null && depth == 0
            ? BoxDecoration(
                border: Border(bottom: BorderSide(color: navyA(.07))),
              )
            : null,
        child: _nameAndAmounts(cols?.stacked ?? false, name, <Widget>[
          _amtCell(w, text(a), amt),
          if (two) _amtCell(w, text(b), amt),
        ]),
      ),
    );
  }
}

/// The bold total row under a ruled line.
class _TTotal extends StatelessWidget {
  const _TTotal(this.label, this.a, {this.b, this.two = false});
  final String label;
  final num a;
  final num? b;
  final bool two;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final _Cols? cols = _Cols.of(context);
    final double w = cols?.w ?? _kAmtW;
    final TextStyle amt = _scaled(
      context,
      amtStyle(
        context,
        size: cols == null ? 15 : _kAmtSize,
      ).copyWith(fontWeight: FontWeight.w800),
    );
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border.symmetric(horizontal: BorderSide(color: navyA(.18))),
      ),
      child: _nameAndAmounts(
        cols?.stacked ?? false,
        // Only the name is indented (a line of amounts keeps the width).
        Padding(
          padding: const EdgeInsets.only(left: 18),
          child: Text(
            label,
            style: ts(15, w: w800, c: p.ink),
          ),
        ),
        <Widget>[
          _amtCell(w, tAmt(a), amt),
          if (two) _amtCell(w, tAmt(b ?? 0), amt),
        ],
      ),
    );
  }
}

/// Groups (tap to open) and ledgers, indented by depth.
class _Tree extends StatelessWidget {
  const _Tree(this.c, this.nodes, this.path, {this.empty});
  final AppController c;
  final List<FinNode> nodes;
  final String path;
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
              : (n.isGroup ? null : () => c.openFinLedger(n)),
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
                  inr(n.amount),
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

/// Tally's balance with Dr / Cr (Tally sign: Cr +, Dr −).
String _drCr(num v) =>
    paise(v) == 0 ? tAmt(0) : '${tAmt(v)} ${v < 0 ? 'Dr' : 'Cr'}';

/// Drill-down from a report's ledger: its vouchers in the report's period
/// (Tally's Ledger Vouchers) — opening balance, each voucher with Debit /
/// Credit and the running balance, totals, closing balance. Tap a voucher
/// to open it.
class FinLedgerScreen extends ConsumerWidget {
  const FinLedgerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final LedgerVouchers? l = c.finLed;
    final String name = l?.name.isNotEmpty == true
        ? l!.name
        : (c.finLedName ?? 'Ledger');
    return Scr(
      children: <Widget>[
        BackNav(
          actions: <Widget>[
            CBtn('sync', onTap: c.finLedBusy ? null : c.loadFinLedger),
          ],
        ),
        H1(name, afterNav: true),
        Sub(
          <String>[
            if ((l?.group ?? '').isNotEmpty) l!.group,
            'Ledger vouchers',
          ].join(' · '),
        ),
        if (c.finTo != null)
          FromToBar(
            from: c.finFrom ?? c.finTo!,
            to: c.finTo!,
            onTap: c.finLedBusy ? null : c.openFinRange,
          ),
        if (c.finLedError != null)
          InfoBox(c.finLedError!, icon: 'info')
        else if (l == null)
          (c.finLedBusy
              ? const ReportLoader(text: 'Loading the vouchers…')
              : EmptyBox('No vouchers.'))
        else ...<Widget>[
          if (c.finLedBusy)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Glass(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: _TTable(
                max: _maxAbs(<num>[
                  l.opening,
                  l.closing,
                  l.totalDebit,
                  l.totalCredit,
                ]),
                two: true,
                children: <Widget>[
                  const _THead(<String>['Particulars', 'Debit', 'Credit']),
                  _TRow(
                    'Opening Balance',
                    key: const ValueKey<String>('finLedOpening'),
                    a: l.opening < 0 ? -l.opening : null,
                    b: l.opening > 0 ? l.opening : null,
                    two: true,
                    bold: true,
                    italic: true,
                  ),
                  if (l.rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No vouchers in this period.',
                        style: ts(13.5, c: p.ink3),
                      ),
                    ),
                  for (final LedgerVoucherRow v in l.rows)
                    _VoucherRow(
                      v,
                      key: ValueKey<String>('finLedRow-${v.guid}'),
                      onTap: v.guid.isEmpty ? null : () => c.openFinVoucher(v),
                    ),
                  _TTotal(
                    'Current Total',
                    l.totalDebit,
                    b: l.totalCredit,
                    two: true,
                  ),
                  _TRow(
                    'Closing Balance',
                    key: const ValueKey<String>('finLedClosing'),
                    a: l.closing < 0 ? -l.closing : null,
                    b: l.closing > 0 ? l.closing : null,
                    two: true,
                    bold: true,
                    italic: true,
                  ),
                ],
              ),
            ),
          ),
          if (l.truncated)
            InfoBox(
              'Showing the first ${l.rows.length} vouchers. Choose a shorter '
              'period to see the rest.',
              icon: 'info',
            ),
        ],
      ],
    );
  }
}

class _VoucherRow extends StatelessWidget {
  const _VoucherRow(this.v, {super.key, this.onTap});
  final LedgerVoucherRow v;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final _Cols? cols = _Cols.of(context);
    final double w = cols?.w ?? _kAmtW;
    final TextStyle amt = _scaled(context, amtStyle(context, size: _kAmtSize));
    final List<Widget> amounts = <Widget>[
      _amtCell(w, v.debit == 0 ? null : tAmt(v.debit), amt),
      _amtCell(w, v.credit == 0 ? null : tAmt(v.credit), amt),
    ];
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: navyA(.06))),
        ),
        child: _nameAndAmounts(
          cols?.stacked ?? false,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                v.particulars.isEmpty ? '—' : v.particulars,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: ts(14, w: w600, c: p.ink),
              ),
              const SizedBox(height: 2),
              Text(
                <String>[
                  dmy(v.date),
                  if (v.type.isNotEmpty) v.type,
                  if (v.ref.isNotEmpty) 'No. ${v.ref}',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ts(12, c: p.ink3),
              ),
              Text('Bal ${_drCr(v.balance)}', style: ts(12, c: p.ink3)),
            ],
          ),
          amounts,
        ),
      ),
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

/// Closing stock on a year end, entered by the admin.
class FinStockSheet extends ConsumerWidget {
  const FinStockSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final DateTime? d = c.finStockDate;
    if (d == null) return const SizedBox.shrink();
    final String? err = c.finStockError;
    return Sheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SheetHead('Closing stock', sub: 'As on ${dmy(d)}'),
          Fld(
            label: 'Closing stock value (₹)',
            req: true,
            child: Inp(
              key: const ValueKey<String>('finStockValue'),
              value: c.f('fsValue'),
              onChanged: (String v) => c.setF('fsValue', v),
              placeholder: '0.00',
              keyboard: const TextInputType.numberWithOptions(decimal: true),
            ),
          ),
          if (err != null)
            InfoBox(err, icon: 'info', margin: const EdgeInsets.only(top: 12)),
          InfoBox(
            'From TallyPrime: Stock Summary as on ${dmy(d)}, closing value '
            'total. It is this day\'s closing stock and the next year\'s '
            'opening stock in the reports.',
            icon: 'info',
            margin: const EdgeInsets.only(top: 12, bottom: 14),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: Btn(label: 'Cancel', kind: BtnKind.g, onTap: c.closeOv),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Btn(
                  key: const ValueKey<String>('finStockSave'),
                  label: c.finStockBusy ? 'Saving…' : 'Save',
                  icon: 'check',
                  enabled: !c.finStockBusy,
                  onTap: c.saveFinStock,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _amt(num v, bool drcr) => drcr
    ? (v == 0 ? inr(0) : '${inr(v.abs())} ${v > 0 ? 'Dr' : 'Cr'}')
    : inr(v);

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
    case 'cf':
      rows.add(<String>['Opening balance', inr(r.n('opening'))]);
      head('Month-wise (in / out)');
      for (final (DateTime, num, num) m in r.cashMonths) {
        rows.add(<String>[
          '   ${kMonths[m.$1.month - 1]} ${m.$1.year}',
          '${inr(m.$2)} / ${inr(m.$3)}',
        ]);
      }
      head('Money in, by group');
      for (final (String, num) g in r.pairs('inflow_groups')) {
        rows.add(<String>['   ${g.$1}', inr(g.$2)]);
      }
      head('Money out, by group');
      for (final (String, num) g in r.pairs('outflow_groups')) {
        rows.add(<String>['   ${g.$1}', inr(g.$2)]);
      }
      totals.addAll(<(String, String)>[
        ('Money in', inr(r.n('inflow'))),
        ('Money out', inr(r.n('outflow'))),
        ('Closing balance', inr(r.n('closing'))),
      ]);
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
      ('Source', 'Tally data synced by the TallyConnect Agent'),
    ],
    table: DocTable(
      const <String>['Particulars', 'Amount'],
      rows,
      right: const <int>{1},
    ),
    totals: totals,
  );
}
