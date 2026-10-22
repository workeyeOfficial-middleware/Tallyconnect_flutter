// Cash flow forecast: 13 weeks of opening balance, money in, money out and
// closing balance from the open bills (customers' bills moved by how late
// each customer usually pays) and today's cash + bank balance. Read-only;
// shown to admins and team members allowed to see financial reports.
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
import '../../data/models/models.dart';
import '../widgets/common.dart';
import '../widgets/report_card.dart';
import '../widgets/report_chart.dart' show compactInr;
import 'stock_party_screens.dart' show StatBox;

/// "12–18 Oct" (or "28 Sep – 4 Oct" across months).
String cfWeekLabel(DateTime start, DateTime end) => start.month == end.month
    ? '${start.day}–${dm(end)}'
    : '${dm(start)} – ${dm(end)}';

/// Reports screen: the Cash flow forecast tile (when allowed).
class CashflowTile extends ConsumerWidget {
  const CashflowTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    if (c.finCanView != true || !c.repo.isRemote || c.demo) {
      return const SizedBox.shrink();
    }
    return ReportCard(
      key: const ValueKey<String>('cashflowTile'),
      icon: 'calendar',
      title: 'Cash Flow Forecast',
      subtitle: 'Coming weeks: money in, money out, balance',
      onTap: c.openCashflow,
    );
  }
}

/// The From / To of a report, in its header: tap to change (the date-range
/// sheet). [fromLabel] / [toLabel] name the two dates ("As at" for a
/// Balance Sheet's To).
class FromToBar extends StatelessWidget {
  const FromToBar({
    super.key,
    required this.from,
    required this.to,
    required this.onTap,
    this.fromLabel = 'From',
    this.toLabel = 'To',
  });
  final DateTime from, to;
  final VoidCallback? onTap;
  final String fromLabel, toLabel;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    Widget box(String k, String label, DateTime d) => Expanded(
      child: Tap(
        key: ValueKey<String>(k),
        onTap: onTap,
        child: Glass(
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 9),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: ts(11.5, w: w600, c: p.ink3),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        dmy(d),
                        style: ts(15, w: w700, c: p.ink),
                      ),
                    ),
                  ],
                ),
              ),
              Ic('calendar', size: IcSize.xs, color: p.ink3),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: <Widget>[
          box('periodFrom', fromLabel, from),
          const SizedBox(width: 10),
          box('periodTo', toLabel, to),
        ],
      ),
    );
  }
}

class CashflowScreen extends ConsumerWidget {
  const CashflowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final CashForecast? f = c.cfData;
    final TcPalette p = Tc.of(context);
    return Scr(
      children: <Widget>[
        BackNav(
          actions: <Widget>[
            CBtn(
              'file',
              key: const ValueKey<String>('cfShare'),
              onTap: f == null || c.cfBusy
                  ? null
                  : () => c.previewDoc(cashflowDoc(c, f)),
            ),
            CBtn(
              'sync',
              key: const ValueKey<String>('cfRefresh'),
              onTap: c.cfBusy ? null : () => c.loadCashflow(refresh: true),
            ),
          ],
        ),
        const H1('Cash flow forecast', afterNav: true),
        Sub(
          <String>[
            if ((f?.company ?? '').isNotEmpty) f!.company else c.companyName,
            'Next ${c.cfWeeks} weeks',
          ].join(' · '),
        ),
        // From (this week) / To: how many weeks ahead.
        FromToBar(
          from: c.cfStart,
          to: c.cfEnd,
          onTap: c.cfBusy ? null : c.openCfRange,
        ),
        Seg(
          key: const ValueKey<String>('cfMode'),
          items: const <String>['Payment habits', 'Due dates'],
          selected: c.cfMode == 'due' ? 1 : 0,
          onPick: (int i) => c.setCfMode(i == 1 ? 'due' : 'adjusted'),
        ),
        if (c.cfError != null)
          InfoBox(c.cfError!, icon: 'info')
        else if (f == null)
          EmptyBox(c.cfBusy ? 'Working out the forecast…' : 'No forecast yet.')
        else ...<Widget>[
          if (c.cfBusy)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          _Headline(f),
          if (f.shortfallWeek != null)
            Banner2(
              'Cash may run short in the week of ${dm(f.shortfallWeek!)}',
              ok: false,
              icon: 'alert',
              margin: const EdgeInsets.only(bottom: 12),
            ),
          if (f.empty)
            const EmptyBox('No open bills to forecast.')
          else ...<Widget>[
            Glass(
              key: const ValueKey<String>('cfChart'),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      _Key(p.pos, 'Money in'),
                      const SizedBox(width: 12),
                      _Key(p.neg, 'Money out'),
                      if (f.opening != null) ...<Widget>[
                        const SizedBox(width: 12),
                        _Key(p.navy2, 'Balance', line: true),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  _WeeksChart(
                    weeks: f.weeks,
                    onTap: (int i) => c.openCfWeek(f.weeks[i]),
                  ),
                ],
              ),
            ),
            const Sec('Week by week'),
            GlassList(
              children: <Widget>[
                for (int i = 0; i < f.weeks.length; i++)
                  _WeekRow(
                    key: ValueKey<String>('cfWeek-$i'),
                    w: f.weeks[i],
                    onTap: () => c.openCfWeek(f.weeks[i]),
                  ),
              ],
            ),
            if (f.laterIn > 0 || f.laterOut > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
                child: Text(
                  'After these ${f.weeks.length} weeks: ${inr(f.laterIn)} to come in, '
                  '${inr(f.laterOut)} to pay.',
                  style: rsStyle(context),
                ),
              ),
            _Doubtful(f),
            if (f.top.isNotEmpty) ...<Widget>[
              const Sec('How customers pay'),
              GlassList(
                children: <Widget>[
                  for (final CashParty x in f.top)
                    _PartyRow(x, adjusted: f.adjusted),
                ],
              ),
            ],
          ],
          _Notes(f),
        ],
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key(this.color, this.label, {this.line = false});
  final Color color;
  final String label;
  final bool line;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Container(
        width: line ? 14 : 10,
        height: line ? 3 : 10,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: ts(12, w: w700, c: Tc.of(context).ink2),
      ),
    ],
  );
}

/// Opening balance, 13-week totals and the balance at the end.
class _Headline extends StatelessWidget {
  const _Headline(this.f);
  final CashForecast f;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    Widget tile(String label, String value, {Color? color, Key? key}) => Glass(
      key: key,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ts(12.5, w: w600, c: p.ink3),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: ts(17, w: w800, c: color ?? p.ink, tab: true),
            ),
          ),
        ],
      ),
    );
    final num? end = f.endBalance;
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
              SizedBox(
                width: box.maxWidth,
                child: Glass(
                  key: const ValueKey<String>('cfOpening'),
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Cash + bank today',
                        style: ts(12.5, w: w600, c: p.ink3),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          f.opening == null ? 'Not available' : inr(f.opening),
                          style: ts(
                            24,
                            w: w800,
                            c: f.opening == null
                                ? p.ink3
                                : (f.opening! < 0 ? p.neg : p.acc),
                            tab: true,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        f.opening == null
                            ? 'Sync Financial Reports to see balances; money in and out are still shown.'
                            : '${f.accounts.length} cash / bank '
                                  '${f.accounts.length == 1 ? 'account' : 'accounts'}'
                                  '${f.openingBasedOn != null ? ' · Tally figures of ${dmy(f.openingBasedOn)} + later entries' : ''}',
                        maxLines: 2,
                        style: ts(12, h: 1.3, c: p.ink3),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: w,
                child: tile(
                  'Money in (13 wk)',
                  inr(f.totalIn),
                  color: p.pos,
                  key: const ValueKey<String>('cfIn'),
                ),
              ),
              SizedBox(
                width: w,
                child: tile(
                  'Money out (13 wk)',
                  inr(f.totalOut),
                  color: p.neg,
                  key: const ValueKey<String>('cfOut'),
                ),
              ),
              SizedBox(
                width: box.maxWidth,
                child: tile(
                  end == null
                      ? 'Net change over ${f.weeks.length} weeks'
                      : 'Balance after ${f.weeks.length} weeks',
                  inr(end ?? (f.totalIn - f.totalOut)),
                  color: (end ?? (f.totalIn - f.totalOut)) < 0 ? p.neg : p.ink,
                  key: const ValueKey<String>('cfEnd'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One week: dates, in, out and the closing balance.
class _WeekRow extends StatelessWidget {
  const _WeekRow({super.key, required this.w, required this.onTap});
  final CashWeek w;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return RowX(
      onTap: onTap,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                cfWeekLabel(w.start, w.end),
                style: ts(14.5, w: w800, c: p.ink),
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      if (w.inflow == 0 && w.outflow == 0)
                        const TextSpan(text: 'No bills')
                      else ...<InlineSpan>[
                        TextSpan(
                          text: '+${compactInr(w.inflow)}',
                          style: TextStyle(color: p.pos, fontWeight: w700),
                        ),
                        const TextSpan(text: '   '),
                        TextSpan(
                          text: '−${compactInr(w.outflow)}',
                          style: TextStyle(color: p.neg, fontWeight: w700),
                        ),
                      ],
                      if (w.overdueIn > 0)
                        TextSpan(
                          text: '   · ${compactInr(w.overdueIn)} overdue',
                          style: TextStyle(color: p.ink3),
                        ),
                    ],
                  ),
                  style: ts(12.5, c: p.ink2, tab: true),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * .36,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              AmtText(
                w.closing == null ? inr(w.net) : inr(w.closing),
                style: amtStyle(
                  context,
                  cls: (w.closing ?? w.net) < 0 ? 'out' : '',
                ),
              ),
              const SizedBox(height: 3),
              Text(
                w.closing == null ? 'net' : (w.shortfall ? 'short' : 'balance'),
                style: rsStyle(context, 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        chevR(),
      ],
    );
  }
}

/// Bills too far past due to count on, and the switch to count them.
class _Doubtful extends ConsumerWidget {
  const _Doubtful(this.f);
  final CashForecast f;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    if (f.doubtfulBills == 0 && !c.cfDoubtful) return const SizedBox.shrink();
    final TcPalette p = Tc.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Glass(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Over ${f.doubtfulDays} days late',
                    style: ts(14.5, w: w800, c: p.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    c.cfDoubtful
                        ? 'Counted as coming in this week.'
                        : '${inr(f.doubtfulAmount)} in ${f.doubtfulBills} '
                              '${f.doubtfulBills == 1 ? 'bill' : 'bills'} · not counted',
                    style: rsStyle(context, 12.5),
                  ),
                ],
              ),
            ),
            ChipBtn(
              c.cfDoubtful ? 'Counted' : 'Count them',
              key: const ValueKey<String>('cfDoubtful'),
              on: c.cfDoubtful,
              height: 36,
              fontSize: 13,
              onTap: c.cfBusy ? null : () => c.setCfDoubtful(!c.cfDoubtful),
            ),
          ],
        ),
      ),
    );
  }
}

/// A customer owing the most, and how late they usually pay.
class _PartyRow extends StatelessWidget {
  const _PartyRow(this.x, {required this.adjusted});
  final CashParty x;
  final bool adjusted;

  @override
  Widget build(BuildContext context) {
    final String habit = switch (x.delaySource) {
      'party' || 'blend' =>
        x.delayDays > 0
            ? 'Pays ~${x.delayDays} days late'
            : (x.delayDays < 0
                  ? 'Pays ~${-x.delayDays} days early'
                  : 'Pays on time'),
      'company' => 'No history · company average ${x.delayDays} days',
      _ => 'No payment history',
    };
    final String basis = x.historyBills > 0
        ? ' · ${x.historyBills} ${x.historyBills == 1 ? 'bill' : 'bills'}'
              '${x.exact ? ' (exact)' : ' (estimated)'}'
        : '';
    return RowX(
      children: <Widget>[
        Expanded(
          child: RTx(
            x.party,
            '$habit$basis${adjusted ? '' : ' (not applied)'}',
            ell: true,
          ),
        ),
        const SizedBox(width: 10),
        AmtText(inr(x.amount), style: amtStyle(context, cls: 'in')),
      ],
    );
  }
}

class _Notes extends StatelessWidget {
  const _Notes(this.f);
  final CashForecast f;

  @override
  Widget build(BuildContext context) {
    final List<String> notes = <String>[
      f.adjusted
          ? 'Customers\' bills are placed on their due date plus how late that customer usually paid in the last 12 months'
                '${f.companyDelay != null ? ' (all customers: ~${f.companyDelay} days)' : ''}. '
                'Suppliers\' bills are on their due dates.'
          : 'Every bill is placed on its due date.',
      if (f.adjusted)
        switch (f.delayMethod) {
          'alloc' => 'Delays are exact: from the bill-wise receipts in Tally.',
          'mixed' =>
            'Delays are exact for ${f.partiesExact} '
                '${f.partiesExact == 1 ? 'customer' : 'customers'} (bill-wise receipts in Tally); '
                'estimated for the others.',
          _ =>
            'Delays are estimated (oldest bills paid first) until bill-wise receipts are synced.',
        },
      if (f.advancesInBills > 0)
        'Advances received: ${inr(f.advancesIn)} in ${f.advancesInBills} '
            '${f.advancesInBills == 1 ? 'bill' : 'bills'} — not counted as money to come in.',
      if (f.advancesOutBills > 0)
        'Advances paid: ${inr(f.advancesOut)} in ${f.advancesOutBills} '
            '${f.advancesOutBills == 1 ? 'bill' : 'bills'} — not counted as money to pay.',
      'Bills already late are counted in this week.',
      if (f.noDueBills > 0)
        '${f.noDueBills} ${f.noDueBills == 1 ? 'bill has' : 'bills have'} no due date: counted as due today.',
      'Only bills synced from Tally are included — not salaries, rent, taxes or loan payments.',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: InfoBox(notes.join('\n'), icon: 'info', margin: EdgeInsets.zero),
    );
  }
}

/// Money in (up) and out (down) per week, the balance as a line; a tap
/// opens that week.
class _WeeksChart extends StatelessWidget {
  const _WeeksChart({required this.weeks, required this.onTap});
  final List<CashWeek> weeks;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double w = box.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (TapUpDetails d) {
            if (weeks.isEmpty) return;
            final int i = (d.localPosition.dx / (w / weeks.length))
                .floor()
                .clamp(0, weeks.length - 1);
            onTap(i);
          },
          child: CustomPaint(
            size: Size(w, 190),
            painter: _WeeksPainter(
              weeks,
              inC: p.pos,
              outC: p.neg,
              lineC: p.navy2,
              axisC: p.ink3,
              label: ts(10.5, w: w600, c: p.ink3),
            ),
          ),
        );
      },
    );
  }
}

class _WeeksPainter extends CustomPainter {
  _WeeksPainter(
    this.weeks, {
    required this.inC,
    required this.outC,
    required this.lineC,
    required this.axisC,
    required this.label,
  });
  final List<CashWeek> weeks;
  final Color inC, outC, lineC, axisC;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    if (weeks.isEmpty) return;
    const double bottomPad = 18, topPad = 6;
    final double h = size.height - bottomPad - topPad;
    double hi = 0, lo = 0;
    for (final CashWeek x in weeks) {
      hi = math.max(hi, x.inflow.toDouble());
      lo = math.min(lo, -x.outflow.toDouble());
      if (x.closing != null) {
        hi = math.max(hi, x.closing!.toDouble());
        lo = math.min(lo, x.closing!.toDouble());
      }
    }
    if (hi - lo <= 0) hi = 1;
    double y(double v) => topPad + (hi - v) / (hi - lo) * h;
    final double slot = size.width / weeks.length;
    final double bw = math.max(2, math.min(slot * .34, 14));
    final double y0 = y(0);

    canvas.drawLine(
      Offset(0, y0),
      Offset(size.width, y0),
      Paint()
        ..color = axisC.withValues(alpha: .35)
        ..strokeWidth = 1,
    );
    final Paint inP = Paint()..color = inC.withValues(alpha: .85);
    final Paint outP = Paint()..color = outC.withValues(alpha: .8);
    final Path line = Path();
    bool started = false;
    for (int i = 0; i < weeks.length; i++) {
      final CashWeek x = weeks[i];
      final double cx = slot * i + slot / 2;
      if (x.inflow > 0) {
        canvas.drawRRect(
          RRect.fromLTRBR(
            cx - bw - 1,
            y(x.inflow.toDouble()),
            cx - 1,
            y0,
            const Radius.circular(3),
          ),
          inP,
        );
      }
      if (x.outflow > 0) {
        canvas.drawRRect(
          RRect.fromLTRBR(
            cx + 1,
            y0,
            cx + bw + 1,
            y(-x.outflow.toDouble()),
            const Radius.circular(3),
          ),
          outP,
        );
      }
      if (x.closing != null) {
        final Offset pt = Offset(cx, y(x.closing!.toDouble()));
        if (!started) {
          line.moveTo(pt.dx, pt.dy);
          started = true;
        } else {
          line.lineTo(pt.dx, pt.dy);
        }
      }
    }
    if (started) {
      canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = lineC,
      );
      for (int i = 0; i < weeks.length; i++) {
        final num? c = weeks[i].closing;
        if (c == null) continue;
        final Offset pt = Offset(slot * i + slot / 2, y(c.toDouble()));
        canvas.drawCircle(pt, 3.4, Paint()..color = Colors.white);
        canvas.drawCircle(pt, 2.4, Paint()..color = c < 0 ? outC : lineC);
      }
    }
    // Dates under the first, middle and last week.
    for (final int i in <int>{0, weeks.length ~/ 2, weeks.length - 1}) {
      final TextPainter tp = TextPainter(
        text: TextSpan(text: dm(weeks[i].start), style: label),
        textDirection: TextDirection.ltr,
      )..layout();
      final double cx = slot * i + slot / 2;
      final double left = (cx - tp.width / 2).clamp(0, size.width - tp.width);
      tp.paint(canvas, Offset(left, size.height - tp.height));
    }
  }

  @override
  bool shouldRepaint(_WeeksPainter o) =>
      !identical(o.weeks, weeks) ||
      o.inC != inC ||
      o.outC != outC ||
      o.lineC != lineC;
}

/// The bills expected in one week.
class CashflowWeekScreen extends ConsumerWidget {
  const CashflowWeekScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final CashWeekDetail? d = c.cfWeekData;
    final DateTime? start = c.cfWeekStart;
    final String title = start == null
        ? 'Week'
        : cfWeekLabel(start, start.add(const Duration(days: 6)));
    return Scr(
      children: <Widget>[
        const BackNav(),
        H1(title, afterNav: true),
        Sub(
          c.cfMode == 'due'
              ? 'Bills due this week'
              : 'Bills expected this week (usual payment delays)',
        ),
        if (c.cfWeekError != null)
          InfoBox(c.cfWeekError!, icon: 'info')
        else if (d == null)
          EmptyBox(c.cfWeekBusy ? 'Loading…' : 'Nothing here.')
        else ...<Widget>[
          Grid(
            cols: 2,
            gap: 10,
            children: <Widget>[
              StatBox(inr(d.week.inflow), 'Money in', glass: true),
              StatBox(inr(d.week.outflow), 'Money out', glass: true),
            ],
          ),
          Sec('Coming in (${d.inflows.length})'),
          if (d.inflows.isEmpty)
            const EmptyBox('No customer bills this week.')
          else
            GlassList(
              children: <Widget>[
                for (final CashLine l in d.inflows) _LineRow(l, inflow: true),
              ],
            ),
          Sec('Going out (${d.outflows.length})'),
          if (d.outflows.isEmpty)
            const EmptyBox('No supplier bills this week.')
          else
            GlassList(
              children: <Widget>[
                for (final CashLine l in d.outflows) _LineRow(l, inflow: false),
              ],
            ),
        ],
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow(this.l, {required this.inflow});
  final CashLine l;
  final bool inflow;

  @override
  Widget build(BuildContext context) {
    final List<String> sub = <String>[
      l.bill,
      if (l.due != null) 'due ${dm(l.due!)}' else 'no due date',
      if (l.overdue) 'late',
      if (inflow && l.delayDays != 0 && !l.overdue && l.expected != null)
        'expected ${dm(l.expected!)}',
    ];
    return RowX(
      children: <Widget>[
        Expanded(child: RTx(l.party, sub.join(' · '), ell: true)),
        const SizedBox(width: 10),
        AmtText(
          inr(l.amount),
          style: amtStyle(context, cls: inflow ? 'in' : 'out'),
        ),
      ],
    );
  }
}

/// The forecast as a PDF: week table and the headline figures.
ShareDoc cashflowDoc(AppController c, CashForecast f) => ShareDoc(
  title: 'Cash flow forecast',
  subtitle:
      '${f.weeks.length} weeks from ${f.weeks.isEmpty ? dmy(f.asOn) : dmy(f.weeks.first.start)} · '
      '${f.adjusted ? 'with customers\' usual payment delays' : 'by due dates'}',
  company: f.company.isEmpty ? c.companyName : f.company,
  fileStem: 'Cash_flow_forecast',
  facts: <(String, String)>[
    ('Cash + bank today', f.opening == null ? 'Not available' : inr(f.opening)),
    ('Money in (${f.weeks.length} weeks)', inr(f.totalIn)),
    ('Money out (${f.weeks.length} weeks)', inr(f.totalOut)),
    if (f.doubtfulBills > 0 && !c.cfDoubtful)
      ('Over ${f.doubtfulDays} days late (not counted)', inr(f.doubtfulAmount)),
    if (f.shortfallWeek != null)
      ('Cash may run short', 'week of ${dmy(f.shortfallWeek)}'),
  ],
  table: DocTable(
    const <String>['Week', 'Opening', 'Money in', 'Money out', 'Closing'],
    <List<String>>[
      for (final CashWeek w in f.weeks)
        <String>[
          cfWeekLabel(w.start, w.end),
          w.opening == null ? '—' : inr(w.opening),
          inr(w.inflow),
          inr(w.outflow),
          w.closing == null ? '—' : inr(w.closing),
        ],
    ],
    right: const <int>{1, 2, 3, 4},
  ),
  totals: <(String, String)>[
    ('Total in', inr(f.totalIn)),
    ('Total out', inr(f.totalOut)),
    if (f.endBalance != null)
      ('Balance after ${f.weeks.length} weeks', inr(f.endBalance)),
  ],
);
