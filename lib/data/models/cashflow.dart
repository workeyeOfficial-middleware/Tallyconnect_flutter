// Cash flow forecast (`GET /api/cashflow/forecast`, `/api/cashflow/week`):
// 13 weeks of opening, money in, money out and closing, worked out on the
// server from the open bills (receivables moved by each party's usual
// payment delay) and today's cash + bank balance. Read-only.
library;

num _n(Object? v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
num? _nn(Object? v) => v is num ? v : num.tryParse('${v ?? ''}');
int _i(Object? v) => _n(v).toInt();
String _s(Object? v) => v == null ? '' : '$v';
DateTime? _d(Object? v) => v == null ? null : DateTime.tryParse('$v');
Map<Object?, Object?> _m(Object? v) =>
    v is Map ? v : const <Object?, Object?>{};
List<Map<Object?, Object?>> _list(Object? v) => <Map<Object?, Object?>>[
  if (v is List)
    for (final Object? x in v)
      if (x is Map) x,
];

/// One Monday–Sunday week.
class CashWeek {
  const CashWeek({
    required this.start,
    required this.end,
    required this.opening,
    required this.inflow,
    required this.outflow,
    required this.closing,
    required this.inBills,
    required this.outBills,
    required this.overdueIn,
    required this.shortfall,
  });
  final DateTime start, end;

  /// Null when the cash / bank balance is not known.
  final num? opening, closing;
  final num inflow, outflow, overdueIn;
  final int inBills, outBills;
  final bool shortfall;

  num get net => inflow - outflow;

  static CashWeek fromJson(Map<Object?, Object?> m) => CashWeek(
    start: _d(m['start']) ?? DateTime(2000),
    end: _d(m['end']) ?? DateTime(2000),
    opening: _nn(m['opening']),
    inflow: _n(m['inflow']),
    outflow: _n(m['outflow']),
    closing: _nn(m['closing']),
    inBills: _i(m['inflow_bills']),
    outBills: _i(m['outflow_bills']),
    overdueIn: _n(m['overdue_inflow']),
    shortfall: m['shortfall'] == true,
  );
}

/// A cash / bank account in the opening balance.
class CashAccount {
  const CashAccount(this.name, this.group, this.balance);
  final String name, group;
  final num balance;
}

/// A party owing the most, with the payment delay used for it.
class CashParty {
  const CashParty({
    required this.party,
    required this.amount,
    required this.delayDays,
    required this.delaySource,
    required this.historyBills,
    this.onTimePct,
    this.method,
  });
  final String party;
  final num amount;
  final int delayDays, historyBills;

  /// `party` | `blend` | `company` | `none`.
  final String delaySource;
  final int? onTimePct;

  /// `alloc`: from Tally's bill-wise receipts (exact); `fifo`: estimated;
  /// null: no history of its own.
  final String? method;

  bool get exact => method == 'alloc';
}

class CashForecast {
  const CashForecast({
    required this.company,
    required this.asOn,
    required this.mode,
    required this.weeks,
    required this.opening,
    required this.openingBasedOn,
    required this.openingReason,
    required this.accounts,
    required this.totalIn,
    required this.totalOut,
    required this.laterIn,
    required this.laterOut,
    required this.doubtfulAmount,
    required this.doubtfulBills,
    required this.doubtfulDays,
    required this.noDueBills,
    required this.shortfallWeek,
    required this.companyDelay,
    required this.companyBills,
    required this.companyOnTimePct,
    required this.partiesWithHistory,
    required this.top,
    required this.receivableBills,
    required this.payableBills,
    this.delayMethod = 'fifo',
    this.partiesExact = 0,
    this.advancesChecked = false,
    this.advancesIn = 0,
    this.advancesInBills = 0,
    this.advancesOut = 0,
    this.advancesOutBills = 0,
  });

  /// How customers' delays were found: `alloc` (Tally's bill-wise
  /// receipts), `fifo` (estimated) or `mixed`.
  final String delayMethod;
  final int partiesExact;

  /// Bills' Dr / Cr known, so advances are left out.
  final bool advancesChecked;

  /// Advances received from customers / paid to suppliers (not counted).
  final num advancesIn, advancesOut;
  final int advancesInBills, advancesOutBills;

  final String company, mode;
  final DateTime? asOn, openingBasedOn, shortfallWeek;
  final List<CashWeek> weeks;

  /// Cash + bank today (null: financial figures not synced).
  final num? opening;

  /// Why [opening] is missing (`financial_not_synced`, …).
  final String openingReason;
  final List<CashAccount> accounts;
  final num totalIn, totalOut, laterIn, laterOut, doubtfulAmount;
  final int doubtfulBills, doubtfulDays, noDueBills;

  /// Company-wide usual delay of customers (days; null: no history).
  final num? companyDelay;
  final int companyBills, partiesWithHistory, receivableBills, payableBills;
  final int? companyOnTimePct;
  final List<CashParty> top;

  bool get adjusted => mode != 'due';
  bool get empty => receivableBills == 0 && payableBills == 0;

  /// Closing balance after the last week (null without an opening).
  num? get endBalance => weeks.isEmpty ? opening : weeks.last.closing;

  static CashForecast fromJson(Object? o) {
    final Map<Object?, Object?> root = _m(o);
    final Map<Object?, Object?> d = root['data'] is Map
        ? _m(root['data'])
        : root;
    final Map<Object?, Object?> op = _m(d['opening']);
    final Map<Object?, Object?> tot = _m(d['totals']);
    final Map<Object?, Object?> later = _m(d['later']);
    final Map<Object?, Object?> doubt = _m(d['doubtful']);
    final Map<Object?, Object?> noDue = _m(d['no_due_date']);
    final Map<Object?, Object?> dl = _m(d['delays']);
    final Map<Object?, Object?> counts = _m(d['counts']);
    final Map<Object?, Object?> adv = _m(d['advances']);
    final Map<Object?, Object?> advIn = _m(adv['received']);
    final Map<Object?, Object?> advOut = _m(adv['paid']);
    return CashForecast(
      company: _s(d['company']),
      asOn: _d(d['as_on']),
      mode: _s(d['mode']).isEmpty ? 'adjusted' : _s(d['mode']),
      weeks: <CashWeek>[
        for (final Map<Object?, Object?> w in _list(d['weeks']))
          CashWeek.fromJson(w),
      ],
      opening: _nn(op['amount']),
      openingBasedOn: _d(op['based_on']),
      openingReason: _s(op['reason']),
      accounts: <CashAccount>[
        for (final Map<Object?, Object?> a in _list(op['accounts']))
          CashAccount(_s(a['name']), _s(a['group']), _n(a['balance'])),
      ],
      totalIn: _n(tot['inflow']),
      totalOut: _n(tot['outflow']),
      laterIn: _n(later['inflow']),
      laterOut: _n(later['outflow']),
      doubtfulAmount: _n(doubt['amount']),
      doubtfulBills: _i(doubt['bills']),
      doubtfulDays: doubt['days'] == null ? 90 : _i(doubt['days']),
      noDueBills: _i(noDue['bills']),
      shortfallWeek: _d(d['shortfall_week']),
      companyDelay: _nn(dl['company_median']),
      companyBills: _i(dl['company_bills']),
      companyOnTimePct: _nn(dl['company_on_time_pct'])?.toInt(),
      partiesWithHistory: _i(dl['parties_with_history']),
      top: <CashParty>[
        for (final Map<Object?, Object?> x in _list(d['top_receivables']))
          CashParty(
            party: _s(x['party']),
            amount: _n(x['amount']),
            delayDays: _i(x['delay_days']),
            delaySource: _s(x['delay_source']),
            historyBills: _i(x['history_bills']),
            onTimePct: _nn(x['on_time_pct'])?.toInt(),
            method: _s(x['method']).isEmpty ? null : _s(x['method']),
          ),
      ],
      receivableBills: _i(counts['receivable_bills']),
      payableBills: _i(counts['payable_bills']),
      delayMethod: _s(dl['method']).isEmpty ? 'fifo' : _s(dl['method']),
      partiesExact: _i(dl['parties_exact']),
      advancesChecked: d['advances_checked'] == true,
      advancesIn: _n(advIn['amount']),
      advancesInBills: _i(advIn['bills']),
      advancesOut: _n(advOut['amount']),
      advancesOutBills: _i(advOut['bills']),
    );
  }
}

/// One bill expected in a week.
class CashLine {
  const CashLine({
    required this.party,
    required this.bill,
    required this.due,
    required this.expected,
    required this.amount,
    required this.delayDays,
    required this.delaySource,
    required this.overdue,
  });
  final String party, bill, delaySource;
  final DateTime? due, expected;
  final num amount;
  final int delayDays;
  final bool overdue;

  static CashLine fromJson(Map<Object?, Object?> m) => CashLine(
    party: _s(m['party']),
    bill: _s(m['bill']),
    due: _d(m['due']),
    expected: _d(m['expected']),
    amount: _n(m['amount']),
    delayDays: _i(m['delay_days']),
    delaySource: _s(m['delay_source']),
    overdue: m['overdue'] == true,
  );
}

/// The bills behind one week (`GET /api/cashflow/week`).
class CashWeekDetail {
  const CashWeekDetail({
    required this.week,
    required this.inflows,
    required this.outflows,
  });
  final CashWeek week;
  final List<CashLine> inflows, outflows;

  static CashWeekDetail fromJson(Object? o) {
    final Map<Object?, Object?> root = _m(o);
    final Map<Object?, Object?> d = root['data'] is Map
        ? _m(root['data'])
        : root;
    return CashWeekDetail(
      week: CashWeek.fromJson(d),
      inflows: <CashLine>[
        for (final Map<Object?, Object?> x in _list(d['inflows']))
          CashLine.fromJson(x),
      ],
      outflows: <CashLine>[
        for (final Map<Object?, Object?> x in _list(d['outflows']))
          CashLine.fromJson(x),
      ],
    );
  }
}
