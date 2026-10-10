// Report detail data (Main.dc.html renderVals 2602–2613), shared by the
// report screen, its chart and the Share / PDF exports. Built only from the
// repository's real rows; a report the server cannot supply says so instead
// of showing numbers.
library;

import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import '../../data/repositories/tally_repository.dart';
import '../utils/format.dart';
import 'share_doc.dart' show rateLabel, stockLabel;

/// What a report row opens: a party (`party`), an item (`item`) or a
/// voucher (`voucher`, [voucher] set). [kind] `''`: not tappable.
class RowTarget {
  const RowTarget.party(this.name) : kind = 'party', voucher = null;
  const RowTarget.item(this.name) : kind = 'item', voucher = null;
  RowTarget.voucher(Voucher this.voucher) : kind = 'voucher', name = '';
  final String kind, name;
  final Voucher? voucher;
}

class ReportRow {
  const ReportRow(
    this.n,
    this.t,
    this.s,
    this.v,
    this.cls, [
    this.value,
    this.target,
  ]);

  /// Opened when the row is tapped (null: nothing to open).
  final RowTarget? target;

  /// Avatar text (rank, day or initial).
  final String n;
  final String t, s;

  /// Display value (`inr(…)` or `—`).
  final String v;

  /// `.amt` modifier: `in`, `out` or ''.
  final String cls;

  /// Numeric value behind [v]; null when the row has no number.
  final num? value;
}

class ChartPoint {
  const ChartPoint(this.label, this.value);
  final String label;
  final num value;
}

class ReportData {
  const ReportData({
    required this.report,
    required this.rows,
    required this.total,
    required this.totalLabel,
    required this.points,
    required this.lineFirst,
    this.period = 'September 2026',
    this.note = '',
    this.card = '',
    this.partial = false,
  });

  /// All time: only the first pages of a long list are on the phone; the
  /// total and count are still the complete, exact figures.
  final bool partial;
  final Report report;
  final List<ReportRow> rows;
  final String total, totalLabel;

  /// Chart series built from the same rows; empty when the report has no
  /// numeric data (Quiet customers, Items not moving).
  final List<ChartPoint> points;

  /// Time series (Day Book) default to the Line chart.
  final bool lineFirst;

  /// Period label (month of the data).
  final String period;

  /// Shown instead of rows when the report cannot be built.
  final String note;

  /// Short value for the report card on the Reports screen.
  final String card;

  bool get hasChart => points.isNotEmpty;
}

/// Report periods: the current month, or the whole history (a From–To
/// date range is the separate Date range option).
const List<(String, String)> kReportPeriods = <(String, String)>[
  ('month', 'This month'),
  ('all', 'All time'),
];

/// The report [id] for [period] (`month` | `all` | `range` with [range]).
/// Voucher reports list that period; Top customers ranks the pending bills
/// dated in the range; other outstanding and stock reports are as of today.
/// All time / range on the server: [loaded] are the voucher pages read so
/// far ([loadedAll]: every one); totals and counts come from the period's
/// exact figures until then.
ReportData reportData(
  TallyRepository repo,
  String id, {
  String period = 'month',
  DateRange? range,
  List<Voucher>? loaded,
  bool loadedAll = false,
}) {
  final List<Report> all = repo.reports();
  final Report r0 =
      all.where((Report r) => r.id == id).firstOrNull ?? all.first;
  final DateTime today = repo.today;
  final bool remote = repo.isRemote;
  final DateRange? rg = period == 'range' ? range : null;
  final bool allTime = period == 'all';
  // Rows reach beyond this month (full dates, monthly chart).
  final bool wide = allTime || rg != null;
  final List<Bill> recv = rg == null
      ? repo.receivables()
      : <Bill>[
          for (final Bill b in repo.receivables())
            if (rg.contains(b.billDate)) b,
        ];
  final List<Voucher> vs = rg != null
      ? (remote
            ? (loaded ?? const <Voucher>[])
            : repo.vouchers().where((Voucher v) => rg.contains(v.date)).toList())
      : !allTime
      ? repo.vouchers().where((Voucher v) {
          final DateTime? d = v.date;
          return d == null || (d.year == today.year && d.month == today.month);
        }).toList()
      : (remote ? (loaded ?? const <Voucher>[]) : repo.vouchers());
  // All time / range on the server, list not fully read: exact figures.
  final bool partial = wide && remote && !loadedAll;
  final VoucherCounts? vc = partial
      ? repo.voucherCounts(rg?.period ?? 'all')
      : null;
  String amtOf(String filter) {
    final num? a = vc?.amountFor(filter);
    if (a != null) return inr(a);
    return vc == null || (!vc.complete && vc.error == null) || vc.stale
        ? '…'
        : '—';
  }

  String countOf(String filter) {
    final int? n = vc?.forFilter(filter);
    return n == null ? '…' : grouped(n);
  }

  String when(Voucher v) =>
      wide ? dmy(v.date) : '${v.day} ${kMonths[today.month - 1]}';
  final List<Item> items = repo.items();
  List<ReportRow> rows;
  String tot, tl = 'Total', note = '', card = '';
  List<ChartPoint> pts = <ChartPoint>[];
  bool lineFirst = false;
  switch (r0.id) {
    case 'top':
      // Customers ranked by what they still owe (pending receivable bills).
      final Map<String, num> by = sumByRupees(
        recv.map((Bill b) => (b.party, b.amt)),
      );
      final Map<String, int> bills = <String, int>{};
      for (final Bill b in recv) {
        bills[b.party] = (bills[b.party] ?? 0) + 1;
      }
      final List<MapEntry<String, num>> t5 =
          (by.entries.toList()..sort(
                (MapEntry<String, num> a, MapEntry<String, num> b) =>
                    b.value.compareTo(a.value),
              ))
              .take(5)
              .toList();
      String sub(String party) {
        if (!remote) {
          final Bill b = recv.firstWhere((Bill x) => x.party == party);
          return '${b.city} · ${b.no}';
        }
        final int n = bills[party] ?? 0;
        return '$n pending ${n == 1 ? 'bill' : 'bills'}';
      }

      rows = <ReportRow>[
        for (int i = 0; i < t5.length; i++)
          ReportRow(
            '${i + 1}',
            t5[i].key,
            sub(t5[i].key),
            inr(t5[i].value),
            'in',
            t5[i].value,
            RowTarget.party(t5[i].key),
          ),
      ];
      tot = inr(sumRupees(t5.map((MapEntry<String, num> x) => x.value)));
      tl = 'Top ${t5.length} owe you';
      card = t5.isEmpty ? 'No dues' : t5.first.key;
    case 'exp':
      if (remote) {
        rows = const <ReportRow>[];
        tot = '—';
        tl = 'Expenses';
        note =
            'The server has no expenses report yet, so no figures are shown.';
        card = 'Not available';
        break;
      }
      const List<(String, String, int)> e = <(String, String, int)>[
        ('Salaries A/c', 'Indirect expense', 120000),
        ('Rent A/c', 'Indirect expense', 35000),
        ('Depreciation A/c', 'Indirect expense', 24500),
        ('Freight Charges', 'Direct expense', 6950),
      ];
      rows = <ReportRow>[
        for (int i = 0; i < e.length; i++)
          ReportRow('${i + 1}', e[i].$1, e[i].$2, inr(e[i].$3), 'out', e[i].$3),
      ];
      tot = inr(186450);
      tl = 'All expenses · Sep';
      card = tot;
    case 'inC':
      if (remote) {
        // Customers with no Tally entry in the last 60 days (any type).
        final DateTime cut = today.subtract(const Duration(days: 60));
        final List<Party> q = repo
            .parties()
            .where(
              (Party x) =>
                  x.type == 'c' &&
                  (x.lastDate == null || x.lastDate!.isBefore(cut)),
            )
            .toList();
        rows = <ReportRow>[
          for (final Party x in q)
            ReportRow(
              initials(x.name),
              x.name,
              x.lastDate == null
                  ? 'No entry found'
                  : 'Last entry ${dmy(x.lastDate)}',
              '—',
              '',
              null,
              RowTarget.party(x.name),
            ),
        ];
      } else {
        rows = <ReportRow>[
          for (final Party x in repo.parties().where(
            (Party x) => x.type == 'c' && x.bal == 0,
          ))
            ReportRow(
              initials(x.name),
              x.name,
              '${x.city} · no sale in 60 days',
              '—',
              '',
              null,
              RowTarget.party(x.name),
            ),
        ];
      }
      tot = '${rows.length}';
      tl = 'Quiet customers';
      card = '${rows.length} customers';
    case 'inI':
      if (remote) {
        // No outward movement recorded in the synced stock summary.
        rows = <ReportRow>[
          for (final StockRow x in repo.stockRows().where(
            (StockRow x) => (x.outward ?? 0) == 0,
          ))
            ReportRow(
              initials(x.name),
              x.name,
              (x.closing ?? 0) <= 0
                  ? 'Finished · no outward movement'
                  : 'In stock · no outward movement',
              '—',
              '',
              null,
              RowTarget.item(x.name),
            ),
        ];
      } else {
        rows = <ReportRow>[
          for (final Item x in items.where((Item x) => x.st == 'out'))
            ReportRow(
              initials(x.name),
              x.name,
              'Finished · not sold this month',
              inr(0),
              '',
              null,
              RowTarget.item(x.name),
            ),
        ];
      }
      tot = '${rows.length}';
      tl = 'Items not moving';
      card = '${rows.length} items';
    case 'day':
      final List<Voucher> d = List<Voucher>.of(vs)
        ..sort((Voucher a, Voucher b) {
          final int c = (b.date ?? DateTime(0)).compareTo(
            a.date ?? DateTime(0),
          );
          return c != 0 ? c : b.day - a.day;
        });
      rows = <ReportRow>[
        for (final Voucher v in d)
          ReportRow(
            '${v.day}',
            v.party,
            '${v.type ?? kKinds[v.kind]!.t} · ${v.no}${wide ? ' · ${dmy(v.date)}' : ''}',
            inr(v.amt),
            '',
            v.amt,
            RowTarget.voucher(v),
          ),
      ];
      final String n = partial ? countOf('all') : grouped(d.length);
      tot = partial ? amtOf('all') : inr(sumRupees(d.map((Voucher v) => v.amt)));
      tl = '$n entries · value';
      card = '$n entries';
      if (!partial) {
        // Day Book charts the value per day (one month) or per month (All
        // time, a range over several months), oldest → newest.
        final bool monthly =
            allTime || (rg != null && rg.monthsNewestFirst.length > 1);
        final Map<int, num> by = sumByRupees(
          d.map(
            (Voucher v) => (
              monthly && v.date != null
                  ? v.date!.year * 100 + v.date!.month
                  : v.day,
              v.amt,
            ),
          ),
        );
        final String mon = kMonths[(rg?.from ?? today).month - 1];
        pts = (by.keys.toList()..sort())
            .map(
              (int k) => ChartPoint(
                monthly && k > 100
                    ? '${kMonths[k % 100 - 1]} ${k ~/ 100}'
                    : '$k $mon',
                by[k]!,
              ),
            )
            .toList();
        lineFirst = true;
      }
    case 'sreg':
    case 'preg':
      final String kk = r0.id == 'sreg' ? 'sales' : 'purchase';
      final List<Voucher> l2 = vs.where((Voucher v) => v.kind == kk).toList();
      rows = <ReportRow>[
        for (final Voucher v in l2)
          ReportRow(
            '${v.day}',
            v.party,
            '${v.no} · ${when(v)}',
            inr(v.amt),
            '',
            v.amt,
            RowTarget.voucher(v),
          ),
      ];
      tot = partial ? amtOf(kk) : inr(sumRupees(l2.map((Voucher v) => v.amt)));
      tl = '${partial ? countOf(kk) : grouped(l2.length)} bills';
      card = tot;
    default:
      rows = <ReportRow>[
        for (final Item x in items)
          ReportRow(
            initials(x.name),
            x.name,
            '${stockLabel(x)} · ${rateLabel(x)}',
            inr(x.worth),
            '',
            x.worth,
            RowTarget.item(x.name),
          ),
      ];
      tot = inr(sumRupees(items.map((Item x) => x.worth)));
      tl = 'Stock value';
      card = tot;
  }
  // A list that is only partly read never gets a chart (it would leave
  // out the rest of the history).
  final bool partRows =
      partial && (r0.id == 'day' || r0.id == 'sreg' || r0.id == 'preg');
  if (pts.isEmpty && r0.id != 'inC' && r0.id != 'inI' && !partRows) {
    pts = <ChartPoint>[
      for (final ReportRow r in rows)
        if (r.value != null) ChartPoint(r.t, r.value!),
    ];
  }
  return ReportData(
    report: r0,
    rows: rows,
    total: tot,
    totalLabel: tl,
    points: pts,
    lineFirst: lineFirst,
    period: wide
        ? '${rg?.label ?? 'All time'}${partRows ? ' · latest ${grouped(rows.length)}' : ''}'
        : monthYear(today),
    note: note,
    card: card,
    partial: partRows,
  );
}
