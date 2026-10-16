// Sales analytics: the Reports tile and the dashboard — headline numbers vs
// the previous period, trend chart, top customers, top items (by amount or
// quantity), item groups, new vs repeat customers, PDF sharing. Worked out
// on the server from the synced vouchers. Read-only.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';
import '../../core/share/share_doc.dart';
import '../../core/utils/format.dart';
import '../../core/share/report_data.dart' show ChartPoint;
import '../../data/models/models.dart';
import '../widgets/common.dart';
import '../widgets/report_chart.dart';

/// Reports screen: the Sales analytics tile (real company only).
class SalesTile extends ConsumerWidget {
  const SalesTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    if (!c.repo.isRemote || c.demo) return const SizedBox.shrink();
    final TcPalette p = Tc.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Tap(
        key: const ValueKey<String>('salesTile'),
        onTap: c.openSalesAnalytics,
        child: Glass(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              Ico('chart', size: IcoSize.sm, color: p.acc),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Sales analytics', style: rtStyle(context)),
                    const SizedBox(height: 2),
                    Text(
                      'Trend, top customers and items, growth',
                      style: rsStyle(context),
                    ),
                  ],
                ),
              ),
              chevR(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Home: the Sales analytics card (right after New Entry) — the period's
/// sales and growth, the trend and three counts, from the same dashboard
/// data; a tap opens the full dashboard.
class SalesHomeCard extends ConsumerWidget {
  const SalesHomeCard({super.key, required this.open});

  /// Home's guarded open (no open while the card is being moved).
  final void Function(VoidCallback) open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    // Loads once per company and period (after this frame).
    WidgetsBinding.instance.addPostFrameCallback((_) => c.ensureHomeSales());
    final SalesDash? d = c.salesData;
    final String period = AppController.kSalesPresets
        .firstWhere(
          ((String, String) e) => e.$1 == c.salesPreset,
          orElse: () => ('custom', c.salesPeriodLabel),
        )
        .$2;
    final num? g = d?.growthPct;

    Widget note(String s, {Key? key}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(s, key: key, style: ts(13.5, h: 1.35, c: p.ink3)),
    );

    Widget stat(String label, String value) => Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
        decoration: BoxDecoration(
          color: whiteA(.42),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: whiteA(.7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ts(11.5, w: w600, c: p.ink3),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: ts(15, w: w800, c: p.ink, tab: true)),
            ),
          ],
        ),
      ),
    );

    final Widget body;
    if (d == null) {
      body = c.salesError != null && !c.salesBusy
          ? note(c.salesError!, key: const ValueKey<String>('homeSalesError'))
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: p.acc,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('Loading sales…', style: ts(13.5, c: p.ink3)),
                ],
              ),
            );
    } else if (d.empty) {
      body = note('No sales in this period yet.');
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    inr(d.sales),
                    key: const ValueKey<String>('homeSalesTotal'),
                    style: ts(26, w: w800, c: p.acc, tab: true),
                  ),
                ),
              ),
              if (g != null) ...<Widget>[
                const SizedBox(width: 10),
                Container(
                  key: const ValueKey<String>('homeSalesGrowth'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: mix(g >= 0 ? p.pos : p.neg, .12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${g >= 0 ? '+' : '−'}${g.abs()}%',
                    style: ts(12.5, w: w800, c: g >= 0 ? p.pos : p.neg),
                  ),
                ),
              ],
            ],
          ),
          Text(
            g == null
                ? 'Nothing to compare with the period before'
                : 'vs ${inr(d.prevSales)} the period before',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ts(12, c: p.ink3),
          ),
          if (d.points.length >= 2) ...<Widget>[
            const SizedBox(height: 10),
            SizedBox(
              height: 64,
              child: CustomPaint(
                key: const ValueKey<String>('homeSalesSpark'),
                painter: _Spark(
                  <double>[
                    for (final SalesPoint x in d.points) x.sales.toDouble(),
                  ],
                  p.acc,
                  p.navy2,
                ),
                size: Size.infinite,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              stat('Invoices', grouped(d.invoices)),
              const SizedBox(width: 8),
              stat('Avg invoice', compactInr(d.avgInvoice)),
              const SizedBox(width: 8),
              stat('Customers', grouped(d.customers)),
            ],
          ),
        ],
      );
    }

    return Tap(
      key: const ValueKey<String>('homeSalesCard'),
      onTap: () => open(c.openSalesAnalytics),
      child: Glass(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Ico(
                  'chart',
                  size: IcoSize.sm,
                  color: p.cat('sales'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Sales analytics',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ts(17, w: w800, c: p.ink),
                      ),
                      Text(
                        period,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ts(12.5, w: w600, c: p.ink3),
                      ),
                    ],
                  ),
                ),
                chevR(),
              ],
            ),
            const SizedBox(height: 12),
            AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: body,
            ),
          ],
        ),
      ),
    );
  }
}

/// The Home card's trend: a soft area under a gradient line, last point
/// marked (no axes; the dashboard has the full chart).
class _Spark extends CustomPainter {
  _Spark(this.v, this.a, this.b);
  final List<double> v;
  final Color a, b;

  @override
  void paint(Canvas canvas, Size size) {
    if (v.length < 2 || size.isEmpty) return;
    final double mx = v.reduce(math.max);
    final double mn = math.min(0, v.reduce(math.min));
    final double span = mx - mn == 0 ? 1 : mx - mn;
    const double pad = 5;
    final double h = size.height - pad * 2;
    Offset at(int i) => Offset(
      pad + (size.width - pad * 2) * i / (v.length - 1),
      pad + h - (v[i] - mn) / span * h,
    );
    final Path line = Path()..moveTo(at(0).dx, at(0).dy);
    for (int i = 1; i < v.length; i++) {
      final Offset p0 = at(i - 1), p1 = at(i);
      final double mid = (p0.dx + p1.dx) / 2;
      line.cubicTo(mid, p0.dy, mid, p1.dy, p1.dx, p1.dy);
    }
    final Path area = Path.from(line)
      ..lineTo(at(v.length - 1).dx, size.height)
      ..lineTo(at(0).dx, size.height)
      ..close();
    final Rect r = Offset.zero & size;
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[a.withValues(alpha: .28), a.withValues(alpha: 0)],
        ).createShader(r),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(colors: <Color>[b, a]).createShader(r),
    );
    final Offset last = at(v.length - 1);
    canvas.drawCircle(last, 5, Paint()..color = Colors.white);
    canvas.drawCircle(last, 3.4, Paint()..color = a);
  }

  @override
  bool shouldRepaint(_Spark o) =>
      !listEquals(o.v, v) || o.a != a || o.b != b;
}

class SalesDashScreen extends ConsumerWidget {
  const SalesDashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final SalesDash? d = c.salesData;
    final TcPalette p = Tc.of(context);
    return Scr(
      children: <Widget>[
        BackNav(
          actions: <Widget>[
            CBtn(
              'file',
              key: const ValueKey<String>('salesShare'),
              onTap: d == null || c.salesBusy
                  ? null
                  : () => c.previewDoc(salesDoc(c, d)),
            ),
            CBtn('sync', onTap: c.salesBusy ? null : c.loadSales),
          ],
        ),
        const H1('Sales analytics', afterNav: true),
        Sub(
          <String>[
            if ((d?.company ?? '').isNotEmpty) d!.company else c.companyName,
            c.salesPeriodLabel,
          ].join(' · '),
        ),
        Chips(
          margin: const EdgeInsets.only(top: 2, bottom: 14),
          children: <Widget>[
            for (final (String, String) x in AppController.kSalesPresets)
              ChipBtn(
                x.$2,
                key: ValueKey<String>('salesPreset-${x.$1}'),
                height: 38,
                fontSize: 13.5,
                on: c.salesPreset == x.$1,
                onTap: c.salesBusy ? null : () => c.setSalesPreset(x.$1),
              ),
            ChipBtn(
              'Dates',
              key: const ValueKey<String>('salesPreset-custom'),
              height: 38,
              fontSize: 13.5,
              icon: 'calendar',
              on: c.salesPreset == 'custom',
              onTap: c.salesBusy ? null : () => c.setSalesPreset('custom'),
            ),
          ],
        ),
        if (c.salesError != null)
          InfoBox(c.salesError!, icon: 'info')
        else if (d == null)
          EmptyBox(c.salesBusy ? 'Working out your sales…' : 'Choose a period.')
        else ...<Widget>[
          if (c.salesBusy)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (d.empty)
            const EmptyBox('No sales in this period.')
          else ...<Widget>[
            _Headline(d),
            _Card(
              key: const ValueKey<String>('salesTrend'),
              title: d.byDay ? 'Sales by day' : 'Sales by month',
              children: <Widget>[
                TcChart(
                  key: const ValueKey<String>('salesTrendChart'),
                  points: <ChartPoint>[
                    for (final SalesPoint x in d.points)
                      ChartPoint(trendLabel(x.key, d.byDay), x.sales),
                  ],
                  type: c.chartType['sales-trend'] ?? 'line',
                  onType: (String t) =>
                      c.update(() => c.chartType['sales-trend'] = t),
                  types: const <(String, String)>[
                    ('line', 'Line'),
                    ('bar', 'Bar'),
                    ('pie', 'Pie'),
                  ],
                  hBarsUpTo: 0,
                ),
              ],
            ),
            _Card(
              key: const ValueKey<String>('salesCustomers'),
              title: 'Top customers',
              children: <Widget>[
                if (d.topCustomers.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: TcChart(
                      key: const ValueKey<String>('salesCustomersChart'),
                      points: <ChartPoint>[
                        for (final SalesParty x in d.topCustomers)
                          ChartPoint(x.party, x.sales),
                      ],
                      type: c.chartType['sales-customers'] ?? 'pie',
                      onType: (String t) =>
                          c.update(() => c.chartType['sales-customers'] = t),
                      types: const <(String, String)>[
                        ('pie', 'Pie'),
                        ('bar', 'Bar'),
                      ],
                      hBarsUpTo: 0,
                      height: 190,
                    ),
                  ),
                for (final (int i, SalesParty x) in d.topCustomers.indexed)
                  _ShareRow(
                    key: ValueKey<String>('salesParty-${x.party}'),
                    color: chartColors(p)[i % 8],
                    title: x.party,
                    sub:
                        '${x.invoices} ${x.invoices == 1 ? 'invoice' : 'invoices'} · ${x.share}%',
                    amount: inr(x.sales),
                    share: x.share / 100,
                    onTap: x.party == '—'
                        ? null
                        : () => c.go('partyDetail', <String, Object?>{
                            'party': x.party,
                            'partyTab': 'summary',
                          }),
                  ),
                const SizedBox(height: 6),
                Text(
                  'New customers ${d.newCustomers} · Repeat customers ${d.repeatCustomers}',
                  key: const ValueKey<String>('salesMix'),
                  style: ts(13, w: w600, c: p.ink2),
                ),
              ],
            ),
            _Card(
              key: const ValueKey<String>('salesItems'),
              title: 'Top items',
              children: <Widget>[
                Seg(
                  items: const <String>['By amount', 'By quantity'],
                  selected: c.salesItemsBy == 'qty' ? 1 : 0,
                  onPick: (int i) =>
                      c.setSalesItemsBy(i == 1 ? 'qty' : 'amount'),
                  fontSize: 13.5,
                  margin: const EdgeInsets.only(bottom: 8),
                ),
                if (d.topItems.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No item details on these invoices.',
                      style: rsStyle(context),
                    ),
                  )
                else
                  for (final SalesItem x
                      in c.salesItemsBy == 'qty' ? d.topItemsQty : d.topItems)
                    _ShareRow(
                      key: ValueKey<String>('salesItem-${x.item}'),
                      title: x.item,
                      sub: 'Qty ${qty(x.qty)} · ${x.invoices} ${x.invoices == 1 ? 'invoice' : 'invoices'}',
                      amount: inr(x.amount),
                      share: _shareOf(
                        c.salesItemsBy == 'qty' ? x.qty : x.amount,
                        c.salesItemsBy == 'qty'
                            ? d.topItemsQty.first.qty
                            : d.topItems.first.amount,
                      ),
                      onTap: () => c.openItem(x.item),
                    ),
              ],
            ),
            if (d.groups.isNotEmpty)
              _Card(
                key: const ValueKey<String>('salesGroups'),
                title: 'Item groups',
                children: <Widget>[
                  TcChart(
                    key: const ValueKey<String>('salesGroupsChart'),
                    points: <ChartPoint>[
                      for (final (String, num) g in d.groups)
                        ChartPoint(g.$1, g.$2),
                    ],
                    type: c.chartType['sales-groups'] ?? 'pie',
                    onType: (String t) =>
                        c.update(() => c.chartType['sales-groups'] = t),
                    types: const <(String, String)>[
                      ('pie', 'Pie'),
                      ('bar', 'Bar'),
                    ],
                  ),
                ],
              ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Sales include GST, as on the invoices; item figures are the '
              'taxable value (without GST). Sales orders and deleted entries '
              'are not counted. Growth is against the period of the same '
              'length just before.',
              style: ts(12.5, h: 1.4, c: p.ink3),
            ),
          ),
        ],
      ],
    );
  }
}

double _shareOf(num v, num max) =>
    max <= 0 ? 0 : (v / max).clamp(0, 1).toDouble();

/// Sales (big), growth, invoices, average, customers, returns.
class _Headline extends StatelessWidget {
  const _Headline(this.d);
  final SalesDash d;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final num? g = d.growthPct;
    Widget tile(String label, String value, {Color? color, Key? key}) =>
        Glass(
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
                child: Text(value, style: ts(17, w: w800, c: color ?? p.ink)),
              ),
            ],
          ),
        );
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
                  key: const ValueKey<String>('salesTotal'),
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Sales', style: ts(12.5, w: w600, c: p.ink3)),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          inr(d.sales),
                          style: ts(24, w: w800, c: p.acc),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        g == null
                            ? 'No sales in the period before to compare'
                            : '${g >= 0 ? '+' : '−'}${g.abs()}% vs previous period (${inr(d.prevSales)})',
                        key: const ValueKey<String>('salesGrowth'),
                        maxLines: 2,
                        style: ts(
                          12.5,
                          w: w700,
                          c: g == null ? p.ink3 : (g >= 0 ? p.pos : p.neg),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: w, child: tile('Invoices', grouped(d.invoices))),
              SizedBox(width: w, child: tile('Average invoice', inr(d.avgInvoice))),
              SizedBox(width: w, child: tile('Customers', grouped(d.customers))),
              SizedBox(
                width: w,
                child: tile(
                  'Returns',
                  inr(d.returns),
                  color: d.returns > 0 ? p.neg : null,
                ),
              ),
              SizedBox(
                width: box.maxWidth,
                child: tile(
                  'Net sales (after returns)',
                  inr(d.netSales),
                  key: const ValueKey<String>('salesNet'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A trend key as a short label: `26 Sep` (by day) or `Sep 26` (by month).
String trendLabel(String k, bool byDay) {
  if (byDay) {
    final DateTime? t = DateTime.tryParse(k);
    return t == null ? k : dm(t);
  }
  final List<String> p = k.split('-');
  final int m = p.length > 1 ? int.tryParse(p[1]) ?? 1 : 1;
  return '${kMonths[(m - 1).clamp(0, 11)]} ${p[0].length == 4 ? p[0].substring(2) : p[0]}';
}

/// A name, a small share bar and an amount.
class _ShareRow extends StatelessWidget {
  const _ShareRow({
    super.key,
    required this.title,
    required this.amount,
    required this.share,
    this.sub,
    this.onTap,
    this.color,
  });
  final String title, amount;
  final String? sub;
  final double share;
  final VoidCallback? onTap;

  /// Bar colour (default: the accent).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final Widget body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ts(14.5, w: w700, c: p.ink),
                    ),
                    if (sub != null)
                      Text(sub!, style: ts(12.5, c: p.ink3)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(amount, style: amtStyle(context, size: 14.5)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 4,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(child: ColoredBox(color: navyA(.07))),
                  FractionallySizedBox(
                    widthFactor: share,
                    heightFactor: 1,
                    child: ColoredBox(color: (color ?? p.acc).withValues(alpha: .8)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return onTap == null ? body : Tap(onTap: onTap, child: body);
  }
}

class _Card extends StatelessWidget {
  const _Card({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Glass(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: rtStyle(context, 16.5)),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );
}

/// PDF of the dashboard: headline numbers, top customers, top items.
ShareDoc salesDoc(AppController c, SalesDash d) {
  final List<List<String>> rows = <List<String>>[
    <String>['TOP CUSTOMERS', ''],
    for (final SalesParty x in d.topCustomers)
      <String>['   ${x.party} (${x.share}%)', inr(x.sales)],
    <String>['TOP ITEMS (TAXABLE VALUE)', ''],
    for (final SalesItem x in d.topItems)
      <String>['   ${x.item} · qty ${qty(x.qty)}', inr(x.amount)],
    if (d.groups.isNotEmpty) <String>['ITEM GROUPS', ''],
    for (final (String, num) g in d.groups) <String>['   ${g.$1}', inr(g.$2)],
    <String>[d.byDay ? 'SALES BY DAY' : 'SALES BY MONTH', ''],
    for (final SalesPoint x in d.points)
      if (x.sales != 0) <String>['   ${x.key}', inr(x.sales)],
  ];
  return ShareDoc(
    title: 'Sales analytics',
    subtitle: c.salesPeriodLabel,
    company: d.company.isNotEmpty ? d.company : c.companyName,
    fileStem: 'Sales_analytics',
    facts: <(String, String)>[
      ('Period', c.salesPeriodLabel),
      ('Invoices', grouped(d.invoices)),
      ('Customers', '${d.customers} (new ${d.newCustomers}, repeat ${d.repeatCustomers})'),
      (
        'Growth',
        d.growthPct == null
            ? '—'
            : '${d.growthPct}% vs previous period (${inr(d.prevSales)})',
      ),
      ('Source', 'Tally (via TallyConnect Agent)'),
    ],
    table: DocTable(
      const <String>['Particulars', 'Amount'],
      rows,
      right: const <int>{1},
    ),
    totals: <(String, String)>[
      ('Sales (incl. GST)', inr(d.sales)),
      ('Returns', inr(d.returns)),
      ('Net sales', inr(d.netSales)),
    ],
  );
}
