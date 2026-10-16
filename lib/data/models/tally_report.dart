// Official Tally reports (`/api/tally-reports/*`): Trial Balance, Profit &
// Loss, Balance Sheet and Cash Flow exactly as TallyPrime calculated them,
// fetched by the TallyConnect Agent one at a time. The app only shows them.
library;

num _n(Object? v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
String _s(Object? v) => v == null ? '' : '$v';
DateTime? _d(Object? v) => v == null ? null : DateTime.tryParse('$v');
Map<Object?, Object?> _m(Object? v) =>
    v is Map ? v : const <Object?, Object?>{};
List<Map<Object?, Object?>> _list(Object? v) => <Map<Object?, Object?>>[
  if (v is List)
    for (final Object? x in v)
      if (x is Map) x,
];

/// Report keys used by the server, and their titles.
const Map<String, String> kTallyReportTitles = <String, String>{
  'trial_balance': 'Trial Balance',
  'profit_loss': 'Profit & Loss',
  'balance_sheet': 'Balance Sheet',
  'cash_flow': 'Cash Flow',
};

/// A ledger under a Balance Sheet / P&L line (Tally sign: Dr −, Cr +).
class TallyLedger {
  const TallyLedger(this.name, this.group, this.amount);
  final String name, group;
  final num amount;
}

/// One line of a Tally report, in Tally's order, with its amount columns.
class TallyRow {
  const TallyRow({
    required this.name,
    required this.amounts,
    this.ledgers = const <TallyLedger>[],
  });
  final String name;

  /// Tally's column tag → amount (Dr −, Cr +).
  final Map<String, num> amounts;
  final List<TallyLedger> ledgers;

  /// Tally's main column, else its sub-column (null: a heading line).
  num? get main {
    for (final String k in amounts.keys) {
      if (k.endsWith('MAINAMT')) return amounts[k];
    }
    for (final String k in amounts.keys) {
      if (k.endsWith('SUBAMT')) return amounts[k];
    }
    return amounts.isEmpty ? null : amounts.values.first;
  }

  static TallyRow fromJson(Map<Object?, Object?> m) => TallyRow(
    name: _s(m['name']),
    amounts: <String, num>{
      for (final MapEntry<Object?, Object?> e in _m(m['amounts']).entries)
        _s(e.key): _n(e.value),
    },
    ledgers: <TallyLedger>[
      for (final Map<Object?, Object?> l in _list(m['ledgers']))
        TallyLedger(_s(l['name']), _s(l['group']), _n(l['amount'])),
    ],
  );
}

/// A Trial Balance ledger (Tally sign: Dr −, Cr +).
class TbLedger {
  const TbLedger(this.name, this.parent, this.opening, this.closing);
  final String name, parent;
  final num opening, closing;
}

class TallyReport {
  const TallyReport({
    required this.report,
    required this.company,
    required this.from,
    required this.to,
    required this.rows,
    required this.ledgers,
    this.fetchedAt,
    this.fetchSeconds,
    this.balanced,
    this.difference = 0,
    this.debit = 0,
    this.credit = 0,
  });

  /// `trial_balance` | `profit_loss` | `balance_sheet` | `cash_flow`.
  final String report;
  final String company;
  final DateTime? from, to, fetchedAt;
  final num? fetchSeconds;

  /// P&L / Balance Sheet / Cash Flow lines.
  final List<TallyRow> rows;

  /// Trial Balance ledgers.
  final List<TbLedger> ledgers;

  /// Sides equal (null: not checked for this report).
  final bool? balanced;
  final num difference, debit, credit;

  String get title => kTallyReportTitles[report] ?? report;

  static TallyReport fromJson(Object? o) {
    final Map<Object?, Object?> root = _m(o);
    final Map<Object?, Object?> d = root['data'] is Map
        ? _m(root['data'])
        : root;
    final String report = _s(d['report']);
    final Map<Object?, Object?> ch = _m(d['checks']);
    final bool tb = report == 'trial_balance';
    return TallyReport(
      report: report,
      company: _s(d['company']),
      from: _d(d['period_from']),
      to: _d(d['period_to']),
      fetchedAt: _d(d['fetched_at'])?.toLocal(),
      fetchSeconds: d['fetch_seconds'] is num
          ? d['fetch_seconds']! as num
          : null,
      rows: tb
          ? const <TallyRow>[]
          : <TallyRow>[
              for (final Map<Object?, Object?> x in _list(d['rows']))
                TallyRow.fromJson(x),
            ],
      ledgers: tb
          ? <TbLedger>[
              for (final Map<Object?, Object?> x in _list(d['rows']))
                TbLedger(
                  _s(x['name']),
                  _s(x['parent']),
                  _n(x['opening']),
                  _n(x['closing']),
                ),
            ]
          : const <TbLedger>[],
      balanced: ch['balanced'] is bool ? ch['balanced']! as bool : null,
      difference: _n(ch['difference']),
      debit: _n(ch['debit'] ?? ch['debit_side']),
      credit: _n(ch['credit'] ?? ch['credit_side']),
    );
  }
}

/// One fetched period of a report.
class TallyPeriod {
  const TallyPeriod(this.from, this.to, [this.fetchedAt]);
  final DateTime from, to;
  final DateTime? fetchedAt;
}

/// What the Agent has fetched so far, per report (newest first).
class TallyReportPeriods {
  const TallyReportPeriods(this.company, this.reports);
  final String company;
  final Map<String, List<TallyPeriod>> reports;

  List<TallyPeriod> of(String report) =>
      reports[report] ?? const <TallyPeriod>[];
  bool has(String report) => of(report).isNotEmpty;

  static TallyReportPeriods fromJson(Object? o) {
    final Map<Object?, Object?> m = _m(o);
    final Map<Object?, Object?> r = _m(m['reports']);
    return TallyReportPeriods(_s(m['company']), <String, List<TallyPeriod>>{
      for (final MapEntry<Object?, Object?> e in r.entries)
        _s(e.key): <TallyPeriod>[
          for (final Map<Object?, Object?> x in _list(e.value))
            if (_d(x['from']) != null && _d(x['to']) != null)
              TallyPeriod(
                _d(x['from'])!,
                _d(x['to'])!,
                _d(x['fetched_at'])?.toLocal(),
              ),
        ],
    });
  }
}
