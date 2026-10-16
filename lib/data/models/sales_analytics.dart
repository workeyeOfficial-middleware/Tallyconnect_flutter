// Sales analytics dashboard (`GET /api/analytics/sales`): headline numbers
// vs the previous period, trend, top customers / items, item groups and
// new vs repeat customers — all worked out on the server from the synced
// vouchers of the active company (team users: only their vouchers).
library;

num _n(Object? v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
String _s(Object? v) => v == null ? '' : '$v';
List<Map<Object?, Object?>> _list(Object? v) => <Map<Object?, Object?>>[
  if (v is List)
    for (final Object? x in v)
      if (x is Map) x,
];

class SalesPoint {
  const SalesPoint(this.key, this.sales, this.invoices);

  /// `YYYY-MM-DD` (by day) or `YYYY-MM` (by month).
  final String key;
  final num sales;
  final int invoices;
}

class SalesParty {
  const SalesParty(this.party, this.sales, this.invoices, this.share);
  final String party;
  final num sales;
  final int invoices;

  /// Share of the period's sales, in %.
  final num share;
}

class SalesItem {
  const SalesItem(this.item, this.amount, this.qty, this.invoices);
  final String item;

  /// Taxable value (excl. GST).
  final num amount, qty;
  final int invoices;
}

class SalesDash {
  const SalesDash({
    required this.company,
    required this.from,
    required this.to,
    required this.sales,
    required this.invoices,
    required this.avgInvoice,
    required this.customers,
    required this.returns,
    required this.netSales,
    required this.prevSales,
    required this.growthPct,
    required this.byDay,
    required this.points,
    required this.topCustomers,
    required this.topItems,
    required this.topItemsQty,
    required this.groups,
    required this.newCustomers,
    required this.repeatCustomers,
  });

  final String company, from, to;

  /// Incl. GST, as on the invoices.
  final num sales, avgInvoice, returns, netSales, prevSales;
  final int invoices, customers, newCustomers, repeatCustomers;

  /// vs the previous period of the same length (null: nothing to compare).
  final num? growthPct;

  /// Trend points by day (short periods) or by month.
  final bool byDay;
  final List<SalesPoint> points;
  final List<SalesParty> topCustomers;
  final List<SalesItem> topItems, topItemsQty;
  final List<(String, num)> groups;

  bool get empty => invoices == 0 && returns == 0;

  static SalesDash fromJson(Object? o) {
    final Map<Object?, Object?> root = o is Map ? o : const <Object?, Object?>{};
    final Map<Object?, Object?> d = root['data'] is Map ? root['data']! as Map<Object?, Object?> : root;
    final Map<Object?, Object?> k = d['kpis'] is Map ? d['kpis']! as Map<Object?, Object?> : const <Object?, Object?>{};
    final Map<Object?, Object?> t = d['trend'] is Map ? d['trend']! as Map<Object?, Object?> : const <Object?, Object?>{};
    final Map<Object?, Object?> cu = d['customers'] is Map ? d['customers']! as Map<Object?, Object?> : const <Object?, Object?>{};
    SalesItem item(Map<Object?, Object?> x) =>
        SalesItem(_s(x['item']), _n(x['amount']), _n(x['qty']), _n(x['invoices']).toInt());
    return SalesDash(
      company: _s(d['company']),
      from: _s(d['from']),
      to: _s(d['to']),
      sales: _n(k['sales']),
      invoices: _n(k['invoices']).toInt(),
      avgInvoice: _n(k['avg_invoice']),
      customers: _n(k['customers']).toInt(),
      returns: _n(k['returns']),
      netSales: _n(k['net_sales']),
      prevSales: _n(k['prev_sales']),
      growthPct: k['growth_pct'] is num ? k['growth_pct']! as num : null,
      byDay: t['unit'] == 'day',
      points: <SalesPoint>[
        for (final Map<Object?, Object?> x in _list(t['points']))
          SalesPoint(_s(x['key']), _n(x['sales']), _n(x['invoices']).toInt()),
      ],
      topCustomers: <SalesParty>[
        for (final Map<Object?, Object?> x in _list(d['top_customers']))
          SalesParty(_s(x['party']), _n(x['sales']), _n(x['invoices']).toInt(), _n(x['share'])),
      ],
      topItems: <SalesItem>[for (final Map<Object?, Object?> x in _list(d['top_items'])) item(x)],
      topItemsQty: <SalesItem>[for (final Map<Object?, Object?> x in _list(d['top_items_qty'])) item(x)],
      groups: <(String, num)>[
        for (final Map<Object?, Object?> x in _list(d['item_groups'])) (_s(x['group']), _n(x['amount'])),
      ],
      newCustomers: _n(cu['new']).toInt(),
      repeatCustomers: _n(cu['repeat']).toInt(),
    );
  }
}
