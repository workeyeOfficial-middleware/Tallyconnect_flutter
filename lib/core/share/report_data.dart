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

class ReportRow {
  const ReportRow(this.n, this.t, this.s, this.v, this.cls, [this.value]);

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
  });
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

ReportData reportData(TallyRepository repo, String id) {
  final List<Report> all = repo.reports();
  final Report r0 =
      all.where((Report r) => r.id == id).firstOrNull ?? all.first;
  final DateTime today = repo.today;
  final bool remote = repo.isRemote;
  final List<Bill> recv = repo.receivables();
  final List<Voucher> vs = repo.vouchers().where((Voucher v) {
    final DateTime? d = v.date;
    return d == null || (d.year == today.year && d.month == today.month);
  }).toList();
  final List<Item> items = repo.items();
  List<ReportRow> rows;
  String tot, tl = 'Total', note = '', card = '';
  List<ChartPoint> pts = <ChartPoint>[];
  bool lineFirst = false;
  switch (r0.id) {
    case 'top':
      // Customers ranked by what they still owe (pending receivable bills).
      final Map<String, num> by = <String, num>{};
      final Map<String, int> bills = <String, int>{};
      for (final Bill b in recv) {
        by[b.party] = (by[b.party] ?? 0) + b.amt;
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
          ),
      ];
      tot = inr(
        t5.fold<num>(0, (num s, MapEntry<String, num> x) => s + x.value),
      );
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
            '${v.type ?? kKinds[v.kind]!.t} · ${v.no}',
            inr(v.amt),
            '',
            v.amt,
          ),
      ];
      tot = inr(d.fold<num>(0, (num s, Voucher v) => s + v.amt));
      tl = '${d.length} entries · value';
      card = '${d.length} entries';
      // Day Book charts the value per day (oldest → newest).
      final Map<int, num> byDay = <int, num>{};
      for (final Voucher v in d) {
        byDay[v.day] = (byDay[v.day] ?? 0) + v.amt;
      }
      final String mon = kMonths[today.month - 1];
      pts = (byDay.keys.toList()..sort())
          .map((int k) => ChartPoint('$k $mon', byDay[k]!))
          .toList();
      lineFirst = true;
    case 'sreg':
    case 'preg':
      final String kk = r0.id == 'sreg' ? 'sales' : 'purchase';
      final List<Voucher> l2 = vs.where((Voucher v) => v.kind == kk).toList();
      final String mon = kMonths[today.month - 1];
      rows = <ReportRow>[
        for (final Voucher v in l2)
          ReportRow(
            '${v.day}',
            v.party,
            '${v.no} · ${v.day} $mon',
            inr(v.amt),
            '',
            v.amt,
          ),
      ];
      tot = inr(l2.fold<num>(0, (num s, Voucher v) => s + v.amt));
      tl = '${l2.length} bills';
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
          ),
      ];
      tot = inr(items.fold<num>(0, (num s, Item x) => s + x.worth));
      tl = 'Stock value';
      card = tot;
  }
  if (pts.isEmpty && r0.id != 'inC' && r0.id != 'inI') {
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
    period: monthYear(today),
    note: note,
    card: card,
  );
}
