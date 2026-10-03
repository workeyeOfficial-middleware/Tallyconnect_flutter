// Report detail data (Main.dc.html renderVals 2602–2613), shared by the
// report screen, its chart and the Share / PDF exports.
library;

import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import '../../data/repositories/tally_repository.dart';
import '../utils/format.dart';

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
  });
  final Report report;
  final List<ReportRow> rows;
  final String total, totalLabel;

  /// Chart series built from the same rows; empty when the report has no
  /// numeric data (Quiet customers, Items not moving).
  final List<ChartPoint> points;

  /// Time series (Day Book) default to the Line chart.
  final bool lineFirst;

  bool get hasChart => points.isNotEmpty;
}

ReportData reportData(TallyRepository repo, String id) {
  final List<Report> all = repo.reports();
  final Report r0 =
      all.where((Report r) => r.id == id).firstOrNull ?? all.first;
  final List<Bill> recv = repo.receivables();
  final List<Voucher> vs = repo.vouchers();
  final List<Item> items = repo.items();
  List<ReportRow> rows;
  String tot, tl = 'Total';
  List<ChartPoint> pts = <ChartPoint>[];
  bool lineFirst = false;
  switch (r0.id) {
    case 'top':
      final List<Bill> t5 = (List<Bill>.of(
        recv,
      )..sort((Bill a, Bill b) => b.amt - a.amt)).take(5).toList();
      rows = <ReportRow>[
        for (int i = 0; i < t5.length; i++)
          ReportRow(
            '${i + 1}',
            t5[i].party,
            '${t5[i].city} · ${t5[i].no}',
            inr(t5[i].amt),
            'in',
            t5[i].amt,
          ),
      ];
      tot = inr(t5.fold<int>(0, (int s, Bill x) => s + x.amt));
      tl = 'Top 5 owe you';
    case 'exp':
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
    case 'inC':
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
      tot = '2';
      tl = 'Quiet customers';
    case 'inI':
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
      tot = '2';
      tl = 'Items not moving';
    case 'day':
      final List<Voucher> d = List<Voucher>.of(vs)
        ..sort((Voucher a, Voucher b) => b.day - a.day);
      rows = <ReportRow>[
        for (final Voucher v in d)
          ReportRow(
            '${v.day}',
            v.party,
            '${kKinds[v.kind]!.t} · ${v.no}',
            inr(v.amt),
            '',
            v.amt,
          ),
      ];
      tot = inr(918490);
      tl = '21 entries · value';
      // Day Book charts the value per day (oldest → newest).
      final Map<int, int> byDay = <int, int>{};
      for (final Voucher v in vs) {
        byDay[v.day] = (byDay[v.day] ?? 0) + v.amt;
      }
      pts = (byDay.keys.toList()..sort())
          .map((int k) => ChartPoint('$k Sep', byDay[k]!))
          .toList();
      lineFirst = true;
    case 'sreg':
    case 'preg':
      final String kk = r0.id == 'sreg' ? 'sales' : 'purchase';
      final List<Voucher> l2 = vs.where((Voucher v) => v.kind == kk).toList();
      rows = <ReportRow>[
        for (final Voucher v in l2)
          ReportRow(
            '${v.day}',
            v.party,
            '${v.no} · ${v.day} Sep',
            inr(v.amt),
            '',
            v.amt,
          ),
      ];
      tot = inr(l2.fold<int>(0, (int s, Voucher v) => s + v.amt));
      tl = '${l2.length} bills';
    default:
      rows = <ReportRow>[
        for (final Item x in items)
          ReportRow(
            initials(x.name),
            x.name,
            '${x.stock} ${x.unit} × ${inr(x.rate)}',
            inr(x.stock * x.rate),
            '',
            x.stock * x.rate,
          ),
      ];
      tot = inr(items.fold<int>(0, (int s, Item x) => s + x.stock * x.rate));
      tl = 'Stock value';
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
  );
}
