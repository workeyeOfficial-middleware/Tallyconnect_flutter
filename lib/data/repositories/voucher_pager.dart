// Page-by-page voucher list for one filter (`/voucher-entry/paged`), so a
// company with 100K+ vouchers never loads its whole history: page 1 when a
// list opens, the next page when the user nears the end.
library;

import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/format.dart';
import '../accounting.dart';
import '../models/models.dart';

/// What a voucher list shows.
class VoucherQuery {
  const VoucherQuery({
    this.filter = 'all',
    this.period = 'all',
    this.range,
    this.ym,
  });

  /// `all`, an app kind (sales, purchase, receipt, payment, journal, contra)
  /// or `type:<Tally voucher type name>`.
  final String filter;

  /// all | month | week | today | range ([range] From–To, both days
  /// included).
  final String period;
  final DateRange? range;

  /// One calendar month (server year / month filter) — set by the pager
  /// while it reads a date range month by month.
  final DateTime? ym;

  String get key =>
      '$filter|$period${period == 'range' ? '|${range?.key}' : ''}';

  /// The list of a period key (`all`, `month`, `week`, `today` or
  /// `range:<from>..<to>`, see [DateRange.period]).
  factory VoucherQuery.forPeriod(String period, {String filter = 'all'}) {
    final DateRange? r = DateRange.parse(period);
    return r == null
        ? VoucherQuery(filter: filter, period: period)
        : VoucherQuery(filter: filter, period: 'range', range: r);
  }

  /// The same list, one month of it (for reading a range).
  VoucherQuery inMonth(DateTime m) =>
      VoucherQuery(filter: filter, period: 'ym', ym: DateTime(m.year, m.month));

  /// Server `type` pre-filter. It is a loose `ILIKE %type%` match, so every
  /// row is still checked against the exact app rule ([matches]).
  String? get serverType {
    if (filter == 'all' || filter == 'other') return null;
    if (filter.startsWith('type:')) return filter.substring(5).trim();
    // Must match every type name [voucherKind] gives this kind: a Tally
    // type named just "Sale" is a sales voucher too (`%sales%` misses it).
    if (filter == 'sales') return 'sale';
    return filter;
  }

  bool matches(Voucher v) {
    if (filter == 'all') return true;
    // Tally type names: compared as the server's type filter does (case and
    // surrounding spaces do not make a different type).
    if (filter.startsWith('type:')) {
      return (v.type ?? '').trim().toLowerCase() ==
          filter.substring(5).trim().toLowerCase();
    }
    return v.kind == filter;
  }
}

/// A From–To date range (both days included, dates only).
class DateRange {
  DateRange(DateTime from, DateTime to)
    : from = DateTime(from.year, from.month, from.day),
      to = DateTime(to.year, to.month, to.day);

  final DateTime from, to;

  bool contains(DateTime? d) {
    if (d == null) return false;
    final DateTime x = DateTime(d.year, d.month, d.day);
    return !x.isBefore(from) && !x.isAfter(to);
  }

  /// Calendar months covered, newest first.
  List<DateTime> get monthsNewestFirst => <DateTime>[
    for (
      DateTime m = DateTime(to.year, to.month);
      !m.isBefore(DateTime(from.year, from.month));
      m = DateTime(m.year, m.month - 1)
    )
      m,
  ];

  String get key => '${ymd(from)}..${ymd(to)}';

  /// Period key used for counts / totals of this range.
  String get period => 'range:$key';

  /// The range of a `range:<from>..<to>` period key, else null.
  static DateRange? parse(String period) {
    if (!period.startsWith('range:')) return null;
    final List<String> p = period.substring(6).split('..');
    if (p.length != 2) return null;
    final DateTime? a = DateTime.tryParse(p[0]), b = DateTime.tryParse(p[1]);
    return a == null || b == null ? null : DateRange(a, b);
  }

  /// `01 Sep 2026 – 30 Sep 2026`.
  String get label => '${dmy(from)} – ${dmy(to)}';

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// One fetched page: its rows, all GUIDs, hasMore.
class FetchedPage {
  const FetchedPage(this.rows, this.guids, this.hasMore);
  final List<Voucher> rows;
  final List<String> guids;
  final bool hasMore;
}

typedef PageFetcher =
    Future<FetchedPage> Function(int page, VoucherQuery q, DateTime today);

class VoucherPager extends ChangeNotifier {
  VoucherPager(this.query, this._fetch, this._today);

  final VoucherQuery query;
  final PageFetcher _fetch;
  final DateTime _today;

  /// Rows shown so far (filtered, de-duplicated, newest first).
  final List<Voucher> rows = <Voucher>[];
  final Set<String> _seen = <String>{};
  int _page = 0;

  /// Date range: the month being read (index into its months, newest
  /// first) and the page within it.
  int _mi = 0, _mPage = 0;
  bool hasMore = true, loading = false;
  String? error;
  bool _disposed = false;

  /// Every row of this filter is loaded (count / total are then exact).
  bool get complete => !hasMore && error == null;

  /// Oldest date this period shows (week / today), else null.
  DateTime? get _cutoff => switch (query.period) {
    'today' => _today,
    'week' => _today.subtract(const Duration(days: 6)),
    _ => null,
  };

  bool _inPeriod(Voucher v) =>
      voucherInPeriod(v, query.period, _today, query.range);

  /// A date range: each month it covers is read with the server's year /
  /// month filter (newest month first) and cut to the exact days here.
  Future<int> _loadRange(int minNew) async {
    final DateRange r = query.range!;
    final List<DateTime> ms = r.monthsNewestFirst;
    int added = 0;
    while (hasMore && added < minNew) {
      final DateTime m = ms[_mi];
      final FetchedPage p = await _fetch(_mPage + 1, query.inMonth(m), _today);
      if (_disposed) return added;
      _mPage++;
      bool past = false;
      for (final Voucher v in p.rows) {
        final DateTime? d = v.date;
        // Only this month's rows (each month is read once).
        if (d == null || d.year != m.year || d.month != m.month) continue;
        final String g = v.guid ?? '';
        if (g.isNotEmpty && !_seen.add(g)) continue; // shifted row
        if (d.isBefore(r.from)) {
          past = true; // newest first: the rest are older still
          continue;
        }
        if (query.matches(v) && r.contains(d)) {
          rows.add(v);
          added++;
        }
      }
      if (past || !p.hasMore || p.guids.isEmpty) {
        _mi++;
        _mPage = 0;
      }
      hasMore = !past && _mi < ms.length;
    }
    return added;
  }

  /// Loads the next server page(s) until at least [minNew] matching rows
  /// arrive or the list ends (the loose server `type` match and date cut-off
  /// can make a page contribute few rows).
  Future<void> loadMore({int minNew = 30}) async {
    if (loading || !hasMore || _disposed) return;
    loading = true;
    error = null;
    _notify();
    int added = 0;
    try {
      if (query.period == 'range') {
        if (query.range == null) {
          hasMore = false;
        } else {
          await _loadRange(minNew);
        }
        if (_disposed) {
          loading = false;
          return;
        }
      }
      while (query.period != 'range' && hasMore && added < minNew) {
        final FetchedPage p = await _fetch(_page + 1, query, _today);
        if (_disposed) {
          loading = false;
          return;
        }
        _page++;
        bool past = false;
        for (int i = 0; i < p.rows.length; i++) {
          final Voucher v = p.rows[i];
          final String g = v.guid ?? '';
          if (g.isNotEmpty && !_seen.add(g)) continue; // shifted row
          final DateTime? cut = _cutoff;
          // Newest-first order: once rows are older than the period, stop.
          if (cut != null && v.date != null && v.date!.isBefore(cut)) {
            past = true;
            continue;
          }
          if (query.matches(v) && _inPeriod(v)) {
            rows.add(v);
            added++;
          }
        }
        // Count filtered rows as progress too.
        for (final String g in p.guids) {
          if (g.isNotEmpty) _seen.add(g);
        }
        // An empty page ends the list even if the server says otherwise
        // (never loops); pages of only shifted duplicates just advance.
        hasMore = p.hasMore && !past && p.guids.isNotEmpty;
      }
    } on ApiException catch (e) {
      error = e.userMessage;
    } catch (e) {
      error = 'Could not load: $e';
    }
    loading = false;
    _notify();
  }

  /// Sum of the loaded rows (exact for the filter once [complete]).
  num get loadedTotal => paise(sumRupees(rows.map((Voucher v) => v.amt)));

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Stops this list (company switch / refresh / evicted) without disposing
  /// it under a widget that may still be listening; late page results are
  /// ignored and the object is simply dropped.
  void detach() => _disposed = true;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Totals over the complete voucher history, streamed page by page and
/// never stored: count / amount per app kind and per Tally type, and the
/// sales / purchase summary of every item — the same rules as
/// [kindTotals] and [itemTrade], applied one voucher at a time.
class HistoryTotals {
  final Set<String> _seen = <String>{};

  /// Amounts in whole paise (exact over any number of vouchers).
  final Map<String, int> kindAmt = <String, int>{};
  final Map<String, int> kindCnt = <String, int>{};
  final Map<String, int> typeAmt = <String, int>{};
  final Map<String, int> typeCnt = <String, int>{};
  final Map<String, ItemAcc> _sales = <String, ItemAcc>{};
  final Map<String, ItemAcc> _purch = <String, ItemAcc>{};

  /// Rows read so far / rows the server reports.
  int scanned = 0;
  int? total;
  bool running = false, done = false;
  String? error;

  /// Every voucher was read (amounts are then complete).
  bool get complete => done && error == null;

  void add(FetchedPage p) {
    for (final String g in p.guids) {
      if (g.isNotEmpty) _seen.add(g);
    }
    scanned = _seen.length;
    for (final Voucher v in p.rows) {
      final int p = toPaise(v.amt);
      kindAmt[v.kind] = (kindAmt[v.kind] ?? 0) + p;
      kindCnt[v.kind] = (kindCnt[v.kind] ?? 0) + 1;
      final String t = v.type ?? '';
      typeAmt[t] = (typeAmt[t] ?? 0) + p;
      typeCnt[t] = (typeCnt[t] ?? 0) + 1;
      if (v.kind != 'sales' && v.kind != 'purchase') continue;
      final Map<String, ItemAcc> by = v.kind == 'sales' ? _sales : _purch;
      final Set<String> names = <String>{
        for (final VoucherItem i in v.items) i.name.trim().toLowerCase(),
      };
      for (final String n in names) {
        by.putIfAbsent(n, ItemAcc.new).add(v, n);
      }
    }
  }

  /// All-history totals per app kind ([kindTotals] shape).
  MonthTotals get byKind => MonthTotals(
    kindAmt.map((String k, int p) => MapEntry<String, num>(k, p / 100)),
    Map<String, int>.of(kindCnt),
  );

  /// Count and amount for a list filter (`all`, kind or `type:X`).
  (int, num) forFilter(String filter) {
    if (filter == 'all') {
      return (
        kindCnt.values.fold<int>(0, (int s, int n) => s + n),
        kindAmt.values.fold<int>(0, (int s, int n) => s + n) / 100,
      );
    }
    if (filter.startsWith('type:')) {
      final String t = filter.substring(5);
      return (typeCnt[t] ?? 0, (typeAmt[t] ?? 0) / 100);
    }
    return (kindCnt[filter] ?? 0, (kindAmt[filter] ?? 0) / 100);
  }

  ItemTrade itemTrade(String item, String kind) =>
      ((kind == 'sales' ? _sales : _purch)[item.trim().toLowerCase()] ??
              ItemAcc())
          .trade;

  /// Tally voucher types outside the main kinds, sorted.
  List<String> get otherTypes => kindCnt['other'] == null
      ? const <String>[]
      : (typeCnt.keys
            .where((String t) => t.isNotEmpty && voucherKind(t) == 'other')
            .toList()
          ..sort());
}

/// Exact voucher counts and amounts for one date period: all, per app kind
/// and per Tally voucher type (type keys lower-case).
class VoucherCounts {
  VoucherCounts({
    this.total,
    Map<String, int>? kind,
    Map<String, int>? type,
    this.totalAmt,
    Map<String, num>? kindAmt,
    Map<String, num>? typeAmt,
    this.complete = false,
    this.error,
  }) : kind = kind ?? <String, int>{},
       type = type ?? <String, int>{},
       kindAmt = kindAmt ?? <String, num>{},
       typeAmt = typeAmt ?? <String, num>{};

  int? total;
  final Map<String, int> kind;
  final Map<String, int> type;

  /// Amounts (voucher values, as the lists add them up).
  num? totalAmt;
  final Map<String, num> kindAmt;
  final Map<String, num> typeAmt;
  bool complete;
  String? error;

  /// Data reloaded since these were counted: not shown until recounted.
  bool stale = false;

  /// The amounts could not be trusted (server sums disagree): amounts show
  /// as unavailable, never as a wrong figure.
  bool amountsUnsure = false;

  /// Display name of each type key (as Tally spells it).
  final Map<String, String> names = <String, String>{};

  /// Other (non-book) voucher types present in this period, sorted.
  List<String> get otherTypes => <String>[
    for (final MapEntry<String, int> e in type.entries)
      if (e.key.isNotEmpty && e.value > 0 && voucherKind(e.key) == 'other')
        names[e.key] ?? e.key,
  ]..sort();

  /// Counts of [vs] (already filtered to the period) by the same rules as
  /// the voucher lists ([VoucherQuery.matches]).
  factory VoucherCounts.of(Iterable<Voucher> vs) {
    final VoucherCounts c = VoucherCounts(
      total: 0,
      totalAmt: 0,
      complete: true,
    );
    // Added up in whole paise (exact for any number of vouchers).
    int all = 0;
    final Map<String, int> kp = <String, int>{}, tp = <String, int>{};
    for (final Voucher v in vs) {
      final int p = toPaise(v.amt);
      c.total = c.total! + 1;
      all += p;
      c.kind[v.kind] = (c.kind[v.kind] ?? 0) + 1;
      kp[v.kind] = (kp[v.kind] ?? 0) + p;
      final String t = (v.type ?? '').toLowerCase();
      c.type[t] = (c.type[t] ?? 0) + 1;
      tp[t] = (tp[t] ?? 0) + p;
      c.names[t] ??= v.type ?? '';
    }
    c.totalAmt = all / 100;
    kp.forEach((String k, int p) => c.kindAmt[k] = p / 100);
    tp.forEach((String k, int p) => c.typeAmt[k] = p / 100);
    return c;
  }

  /// Total value for a list filter (`all`, a kind or `type:X`); null until
  /// complete.
  num? amountFor(String filter) {
    if (!complete || stale || amountsUnsure || totalAmt == null) return null;
    if (filter == 'all') return paise(totalAmt!);
    if (filter.startsWith('type:')) {
      return paise(typeAmt[filter.substring(5).trim().toLowerCase()] ?? 0);
    }
    return paise(kindAmt[filter] ?? 0);
  }

  /// Count for a list filter (`all`, a kind or `type:X`); null until
  /// complete.
  int? forFilter(String filter) {
    if (!complete || stale) return null;
    if (filter == 'all') return total;
    if (filter.startsWith('type:')) {
      return type[filter.substring(5).trim().toLowerCase()] ?? 0;
    }
    return kind[filter] ?? 0;
  }
}

/// [v] falls in [period] (`all`, `month`, `week`, `today`, `range` with
/// [range]) — the same date rules the voucher lists use.
bool voucherInPeriod(
  Voucher v,
  String period,
  DateTime today, [
  DateRange? range,
]) {
  final DateTime? d = v.date;
  final DateRange? r = range ?? DateRange.parse(period);
  if (r != null || period == 'range') return r != null && r.contains(d);
  switch (period) {
    case 'ym':
      return true;
    case 'today':
      return d != null && dayDiff(d, today) == 0;
    case 'week':
      if (d == null) return false;
      final int n = dayDiff(d, today);
      return n >= 0 && n <= 6;
    case 'month':
      return d != null && d.year == today.year && d.month == today.month;
  }
  return true;
}

/// SQL `ILIKE '%pattern%'` (case-insensitive; `%` / `_` are wildcards) —
/// how the server's `type` filter matches voucher type names.
bool ilikeContains(String pattern, String value) {
  final StringBuffer re = StringBuffer();
  for (final int r in pattern.runes) {
    final String ch = String.fromCharCode(r);
    re.write(
      ch == '%'
          ? '.*'
          : ch == '_'
          ? '.'
          : RegExp.escape(ch),
    );
  }
  return RegExp(
    re.toString(),
    caseSensitive: false,
    dotAll: true,
  ).hasMatch(value);
}

/// Exact count per voucher type from the server's loose counts:
/// `ilike[T]` = vouchers whose type matches `%T%`, i.e. the exact counts of
/// every type T' that T matches (T itself included). Solved from the most
/// specific types down: exact(T) = ilike(T) − Σ exact(T' ≠ T matched by T).
/// Types differing only in case are one group (keys lower-case).
Map<String, int> exactTypeCounts(Map<String, int> ilike) => _exactPerType(
  ilike,
  clampAtZero: true,
).map((String k, num v) => MapEntry<String, int>(k, v.toInt()));

/// The same for the server's `SUM(net_amount)` per `type` filter (sums
/// split by type exactly like counts; signed, as the server sums them).
Map<String, num> exactTypeSums(Map<String, num> ilike) =>
    _exactPerType(ilike, clampAtZero: false);

Map<String, num> _exactPerType(
  Map<String, num> ilike, {
  required bool clampAtZero,
}) {
  final Map<String, num> grp = <String, num>{};
  for (final MapEntry<String, num> e in ilike.entries) {
    final String k = e.key.toLowerCase();
    // Case variants match each other: their figures are the same number.
    grp[k] = grp.containsKey(k)
        ? (grp[k]!.abs() > e.value.abs() ? grp[k]! : e.value)
        : e.value;
  }
  final Map<String, num> exact = <String, num>{};
  final Set<String> busy = <String>{};
  num solve(String t) {
    final num? done = exact[t];
    if (done != null) return done;
    busy.add(t);
    num n = grp[t]!;
    for (final String o in grp.keys) {
      if (o == t || busy.contains(o)) continue;
      if (ilikeContains(t, o)) n -= solve(o);
    }
    busy.remove(t);
    return exact[t] = clampAtZero && n < 0 ? 0 : n;
  }

  for (final String t in grp.keys) {
    solve(t);
  }
  return exact;
}
