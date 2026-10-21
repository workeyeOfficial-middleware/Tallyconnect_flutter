// Financial statements (`/api/financial/*`): P&L, Balance Sheet, Trial
// Balance and Expenses, built by the server from figures Tally computed and
// the TallyConnect Agent synced. The app only shows them.
library;

num _n(Object? v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
String _s(Object? v) => v == null ? '' : '$v';

/// A group (with children) or a ledger row of a statement.
class FinNode {
  const FinNode({
    required this.name,
    required this.amount,
    this.isGroup = false,
    this.guid,
    this.nature = '',
    this.children = const <FinNode>[],
  });
  final String name;

  /// Rupees. Trial Balance: + Dr, − Cr. Other reports: + is the normal
  /// side of the section (income / expense / asset / liability).
  final num amount;
  final bool isGroup;
  final String? guid;

  /// `asset` | `liability` | `income` | `expense` | `other` (top level).
  final String nature;
  final List<FinNode> children;

  static FinNode fromJson(Object? o) {
    final Map<Object?, Object?> m = o is Map ? o : const <Object?, Object?>{};
    final Object? ch = m['children'];
    return FinNode(
      name: _s(m['name']),
      amount: _n(m['amount']),
      isGroup: m['type'] == 'group',
      guid: m['guid'] == null ? null : _s(m['guid']),
      nature: _s(m['nature']),
      children: <FinNode>[
        if (ch is List)
          for (final Object? x in ch) FinNode.fromJson(x),
      ],
    );
  }

  static List<FinNode> list(Object? o) => <FinNode>[
    if (o is List)
      for (final Object? x in o) FinNode.fromJson(x),
  ];
}

/// One synced "as on" date.
class FinSnapshot {
  const FinSnapshot(this.asOn, this.fyFrom, [this.syncedAt]);
  final DateTime asOn, fyFrom;
  final DateTime? syncedAt;

  /// The last day of a month (Tally figures for month-wise periods).
  bool get monthEnd => asOn.add(const Duration(days: 1)).day == 1;
}

class FinPeriods {
  const FinPeriods({
    required this.snapshots,
    required this.groupsSynced,
    required this.company,
    this.message,
    this.stockNeeded = const <DateTime>[],
    this.canEnterStock = false,
    this.anyPeriod = false,
    this.booksFrom,
    this.stockDates = const <DateTime>[],
  });

  /// Any From–To period can be worked out (vouchers synced from the books'
  /// start); otherwise only the dates in [snapshots].
  final bool anyPeriod;

  /// The books' first day (the earliest From), when known.
  final DateTime? booksFrom;

  /// Dates with a closing stock value (P&L / Balance Sheet need one on the
  /// day before From and on To), oldest first.
  final List<DateTime> stockDates;

  /// A closing stock value exists for [d].
  bool hasStock(DateTime d) => stockDates.any(
    (DateTime x) => x.year == d.year && x.month == d.month && x.day == d.day,
  );

  /// Newest first.
  final List<FinSnapshot> snapshots;
  final bool groupsSynced;
  final String company;

  /// Why there is no report date yet, in the server's words (or null).
  final String? message;

  /// Year ends whose closing stock is missing (newest first): that year's
  /// P&L / Balance Sheet need it. The admin can enter it.
  final List<DateTime> stockNeeded;

  /// This login may enter a closing stock (the account admin).
  final bool canEnterStock;

  bool get ready => groupsSynced && snapshots.isNotEmpty;
  FinSnapshot? get latest => snapshots.isEmpty ? null : snapshots.first;

  /// Has figures exactly on [d].
  bool has(DateTime d) => snapshots.any(
    (FinSnapshot s) =>
        s.asOn.year == d.year && s.asOn.month == d.month && s.asOn.day == d.day,
  );

  static FinPeriods fromJson(Object? o) {
    final Map<Object?, Object?> m = o is Map ? o : const <Object?, Object?>{};
    final Object? ss = m['snapshots'];
    final Object? need = m['stock_needed'];
    final Object? sd = m['stock_dates'];
    DateTime? d(Object? v) => DateTime.tryParse(_s(v));
    return FinPeriods(
      anyPeriod: m['any_period'] == true,
      booksFrom: d(m['books_from']),
      stockDates: <DateTime>[
        if (sd is List)
          for (final Object? x in sd)
            if (d(x) != null) d(x)!,
      ],
      company: _s(m['company']),
      groupsSynced: m['groups_synced'] == true,
      message: _s(m['message']).isEmpty ? null : _s(m['message']),
      canEnterStock: m['can_enter_stock'] == true,
      stockNeeded: <DateTime>[
        if (need is List)
          for (final Object? x in need)
            if (d(x) != null) d(x)!,
      ],
      snapshots: <FinSnapshot>[
        if (ss is List)
          for (final Object? x in ss)
            if (x is Map && d(x['as_on']) != null && d(x['fy_from']) != null)
              FinSnapshot(
                d(x['as_on'])!,
                d(x['fy_from'])!,
                d(x['synced_at'])?.toLocal(),
              ),
      ],
    );
  }
}

/// One report as the server built it (`kind`: pl | bs | tb | exp).
class FinReport {
  const FinReport(this.kind, this.m);
  final String kind;
  final Map<Object?, Object?> m;

  num n(String k) => _n(m[k]);
  num sub(String a, String b) {
    final Object? x = m[a];
    return x is Map ? _n(x[b]) : 0;
  }

  List<FinNode> nodes(String k) => FinNode.list(m[k]);
  List<FinNode> subNodes(String a, String b) {
    final Object? x = m[a];
    return x is Map ? FinNode.list(x[b]) : const <FinNode>[];
  }

  String get company => _s(m['company']);
  DateTime? date(String k) => DateTime.tryParse(_s(m[k]));

  /// Expenses: month-wise totals.
  List<(DateTime, num)> get byMonth {
    final Object? x = m['by_month'];
    return <(DateTime, num)>[
      if (x is List)
        for (final Object? e in x)
          if (e is Map && DateTime.tryParse(_s(e['as_on'])) != null)
            (DateTime.parse(_s(e['as_on'])), _n(e['amount'])),
    ];
  }

  /// Cash Flow: month rows `(first day, money in, money out)`.
  List<(DateTime, num, num)> get cashMonths {
    final Object? x = m['months'];
    return <(DateTime, num, num)>[
      if (x is List)
        for (final Object? e in x)
          if (e is Map && DateTime.tryParse('${_s(e['month'])}-01') != null)
            (
              DateTime.parse('${_s(e['month'])}-01'),
              _n(e['inflow']),
              _n(e['outflow']),
            ),
    ];
  }

  /// Cash Flow: `(name, amount)` rows of [k] (`inflow_groups` …).
  List<(String, num)> pairs(String k) {
    final Object? x = m[k];
    return <(String, num)>[
      if (x is List)
        for (final Object? e in x)
          if (e is Map) (_s(e['name']), _n(e['amount'])),
    ];
  }

  /// Cash Flow: cash / bank accounts `(name, opening, closing)`.
  List<(String, num, num)> get cashAccounts {
    final Object? x = m['accounts'];
    return <(String, num, num)>[
      if (x is List)
        for (final Object? e in x)
          if (e is Map) (_s(e['name']), _n(e['opening']), _n(e['closing'])),
    ];
  }
}

/// One voucher line of a ledger (Ledger Vouchers, Tally's drill-down).
class LedgerVoucherRow {
  const LedgerVoucherRow({
    required this.guid,
    required this.date,
    required this.type,
    required this.ref,
    required this.particulars,
    required this.debit,
    required this.credit,
    required this.balance,
  });
  final String guid, type, ref, particulars;
  final DateTime? date;
  final num debit, credit;

  /// Running balance, Tally sign: Cr +, Dr −.
  final num balance;
}

/// `/api/financial/ledger-vouchers`: one ledger's vouchers in a period.
class LedgerVouchers {
  const LedgerVouchers({
    required this.name,
    required this.group,
    required this.from,
    required this.to,
    required this.opening,
    required this.closing,
    required this.totalDebit,
    required this.totalCredit,
    required this.rows,
    required this.truncated,
    this.guid,
  });
  final String name, group;
  final String? guid;
  final DateTime? from, to;

  /// Tally sign: Cr +, Dr −.
  final num opening, closing;
  final num totalDebit, totalCredit;
  final List<LedgerVoucherRow> rows;
  final bool truncated;

  static LedgerVouchers fromJson(Object? o) {
    final Map<Object?, Object?> m = o is Map ? o : const <Object?, Object?>{};
    final Object? l = m['ledger'];
    final Map<Object?, Object?> led = l is Map ? l : const <Object?, Object?>{};
    final Object? rs = m['rows'];
    DateTime? d(Object? v) => DateTime.tryParse(_s(v));
    return LedgerVouchers(
      name: _s(led['name']),
      guid: led['guid'] == null ? null : _s(led['guid']),
      group: _s(led['group']),
      from: d(m['from']),
      to: d(m['to']),
      opening: _n(m['opening']),
      closing: _n(m['closing']),
      totalDebit: _n(m['total_debit']),
      totalCredit: _n(m['total_credit']),
      truncated: m['truncated'] == true,
      rows: <LedgerVoucherRow>[
        if (rs is List)
          for (final Object? x in rs)
            if (x is Map)
              LedgerVoucherRow(
                guid: _s(x['guid']),
                date: d(x['date']),
                type: _s(x['type']),
                ref: _s(x['ref']),
                particulars: _s(x['particulars']),
                debit: _n(x['debit']),
                credit: _n(x['credit']),
                balance: _n(x['balance']),
              ),
      ],
    );
  }
}
