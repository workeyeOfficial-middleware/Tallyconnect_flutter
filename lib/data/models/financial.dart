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
  });

  /// Newest first.
  final List<FinSnapshot> snapshots;
  final bool groupsSynced;
  final String company;

  /// Why there is no report date yet, in the server's words (or null).
  final String? message;

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
    DateTime? d(Object? v) => DateTime.tryParse(_s(v));
    return FinPeriods(
      company: _s(m['company']),
      groupsSynced: m['groups_synced'] == true,
      message: _s(m['message']).isEmpty ? null : _s(m['message']),
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
}
