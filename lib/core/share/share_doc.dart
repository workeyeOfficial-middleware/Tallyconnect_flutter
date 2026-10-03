// Shareable documents (NEW feature — not in the prototype). Each builder
// turns the same data a screen shows into a [ShareDoc]: a plain-text summary
// for the share sheet plus the content of the PDF.
library;

import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import '../utils/format.dart';
import 'report_data.dart';

/// Bill / invoice layout data (the prototype's PDF "paper", 1563–1582).
class InvoiceSpec {
  const InvoiceSpec({
    required this.heading,
    required this.toLabel,
    required this.no,
    required this.date,
    required this.due,
    required this.party,
    required this.city,
    required this.lines,
    required this.sub,
    required this.cgst,
    required this.total,
    required this.kind,
  });
  final String heading, toLabel, no, date, due, party, city, kind;

  /// #, item, HSN, qty, rate, amount
  final List<(String, String, String, String, String, String)> lines;
  final int sub, cgst, total;

  String get fileName => '${no.replaceFirst(' ', '_')}.pdf';
}

/// `pdf` view model (2553–2561).
InvoiceSpec invoiceOf(PdfInfo pd, List<BillLine> sales9) {
  final bool s9 = pd.no == 'Sales 9';
  final int taxable = s9 ? 95000 : (pd.total / 1.18).round();
  final int cg = s9 ? 8550 : ((pd.total - taxable) / 2).round();
  final bool purchase =
      pd.recv == false || RegExp('PI|Purchase').hasMatch(pd.kind);
  return InvoiceSpec(
    heading: purchase ? 'PURCHASE BILL' : 'TAX INVOICE',
    toLabel: purchase ? 'BILL FROM' : 'BILLED TO',
    no: pd.no,
    date: pd.date,
    due: pd.due,
    party: pd.party,
    city: '${pd.city}${s9 ? ' · GSTIN: 27AAKFS2291M1Z8' : ''}',
    kind: pd.kind,
    lines: s9
        ? <(String, String, String, String, String, String)>[
            for (int i = 0; i < sales9.length; i++)
              (
                '${i + 1}',
                sales9[i].name,
                sales9[i].hsn,
                sales9[i].qty,
                sales9[i].rate,
                inr(sales9[i].amt),
              ),
          ]
        : <(String, String, String, String, String, String)>[
            ('1', 'Goods as per Tally entry', '—', '—', '—', inr(taxable)),
          ],
    sub: taxable,
    cgst: cg,
    total: pd.total,
  );
}

class DocTable {
  const DocTable(this.columns, this.rows, {this.right = const <int>{}});
  final List<String> columns;
  final List<List<String>> rows;

  /// Right-aligned column indexes (amounts).
  final Set<int> right;
}

class ShareDoc {
  const ShareDoc({
    required this.title,
    required this.company,
    this.subtitle = '',
    this.facts = const <(String, String)>[],
    this.table,
    this.totals = const <(String, String)>[],
    this.invoice,
    this.fileStem,
  });

  final String title, subtitle, company;
  final List<(String, String)> facts;
  final DocTable? table;
  final List<(String, String)> totals;
  final InvoiceSpec? invoice;
  final String? fileStem;

  String get fileName {
    if (invoice != null) return invoice!.fileName;
    final String stem = (fileStem ?? title)
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return 'TallyConnect_$stem.pdf';
  }

  /// Plain-text version used as the share-sheet message.
  String get text {
    final StringBuffer b = StringBuffer();
    final InvoiceSpec? iv = invoice;
    if (iv != null) {
      b.writeln('${iv.heading} · ${iv.no}');
      b.writeln(company);
      b.writeln(
        '${iv.toLabel == 'BILLED TO' ? 'Billed to' : 'Bill from'}: ${iv.party}',
      );
      b.writeln('Date: ${iv.date} · Due: ${iv.due}');
      for (final (String, String, String, String, String, String) l
          in iv.lines) {
        b.writeln('${l.$1}. ${l.$2} — ${l.$4} × ${l.$5} = ${l.$6}');
      }
      b.writeln('Subtotal: ${inr(iv.sub)}');
      b.writeln('CGST @ 9%: ${inr(iv.cgst)}');
      b.writeln('SGST @ 9%: ${inr(iv.cgst)}');
      b.write('Total: ${inr(iv.total)}');
      return b.toString();
    }
    b.writeln(title);
    if (subtitle.isNotEmpty) b.writeln(subtitle);
    b.writeln(company);
    if (facts.isNotEmpty) {
      b.writeln();
      for (final (String, String) f in facts) {
        b.writeln('${f.$1}: ${f.$2}');
      }
    }
    final DocTable? t = table;
    if (t != null && t.rows.isNotEmpty) {
      b.writeln();
      for (final List<String> r in t.rows) {
        b.writeln(r.where((String c) => c.isNotEmpty).join(' · '));
      }
    }
    if (totals.isNotEmpty) {
      b.writeln();
      for (final (String, String) f in totals) {
        b.writeln('${f.$1}: ${f.$2}');
      }
    }
    return b.toString().trimRight();
  }
}

// ------------------------------------------------------------- builders

ShareDoc docInvoice(PdfInfo pd, String company, List<BillLine> sales9) =>
    ShareDoc(title: pd.no, company: company, invoice: invoiceOf(pd, sales9));

ShareDoc docEntry(Voucher e, String company) {
  final Kind k = kKinds[e.kind]!;
  return ShareDoc(
    title: '${k.long} · ${e.no}',
    subtitle: 'Synced with Tally',
    company: company,
    fileStem: 'Entry_${e.no}',
    facts: <(String, String)>[
      ('Type', k.long),
      ('Number', e.no),
      ('Date', '${e.day} Sep 2026'),
      ('Party / account', e.party),
      ('Amount', inr(e.amt)),
      ('Company', company),
    ],
  );
}

ShareDoc docBill(Bill b, String company) {
  final bool r = b.kind == 'recv';
  return ShareDoc(
    title: 'Bill details · ${b.no}',
    subtitle: '${b.party} · ${r ? 'Customer' : 'Supplier'} · ${b.city}',
    company: company,
    fileStem: 'Bill_${b.no}',
    facts: <(String, String)>[
      ('Bill number', b.no),
      ('Bill type', r ? 'Sales bill' : 'Purchase bill'),
      ('Bill date', b.bill),
      ('Pay by', b.due),
      ('Credit time', b.credit),
      ('Status', b.txt),
    ],
    totals: <(String, String)>[
      (r ? 'Still to get' : 'Still to pay', inr(b.amt)),
    ],
  );
}

ShareDoc docParty(
  Party p0,
  String company,
  List<(String, String, bool)> rows,
  List<Voucher> entries,
) {
  final bool pc = p0.type == 'c';
  return ShareDoc(
    title: p0.name,
    subtitle:
        '${pc ? 'Customer' : 'Supplier'} · ${p0.city} · Balance as on 26 Sep 2026',
    company: company,
    fileStem: 'Party_${p0.name}',
    facts: <(String, String)>[
      for (final (String, String, bool) r in rows) (r.$1, r.$2),
    ],
    table: entries.isEmpty
        ? null
        : DocTable(
            const <String>['Date', 'Entry', 'Type', 'Amount'],
            <List<String>>[
              for (final Voucher v in entries)
                <String>[
                  '${v.day} Sep 2026',
                  v.no,
                  kKinds[v.kind]!.t,
                  inr(v.amt),
                ],
            ],
            right: const <int>{3},
          ),
    totals: <(String, String)>[
      ('Balance', '${inr(p0.bal)}${p0.bal != 0 ? (pc ? ' Dr' : ' Cr') : ''}'),
    ],
  );
}

ShareDoc docReport(ReportData d, String company) => ShareDoc(
  title: d.report.t,
  subtitle: '${d.report.s} · September 2026',
  company: company,
  fileStem: 'Report_${d.report.t}',
  table: DocTable(
    const <String>['#', 'Name', 'Detail', 'Value'],
    <List<String>>[
      for (final ReportRow r in d.rows) <String>[r.n, r.t, r.s, r.v],
    ],
    right: const <int>{3},
  ),
  totals: <(String, String)>[(d.totalLabel, d.total)],
);

String _pm(Voucher v) =>
    '${v.kind == 'receipt' ? '+' : (v.kind == 'payment' ? '−' : '')}${inr(v.amt)}';

ShareDoc docVouchers(
  String title,
  List<Voucher> rows,
  String company,
  String period,
) => ShareDoc(
  title: title,
  subtitle: '$company · September 2026 · $period',
  company: company,
  fileStem: 'Vouchers_$title',
  table: DocTable(
    const <String>['Date', 'Entry', 'Party / account', 'Type', 'Amount'],
    <List<String>>[
      for (final Voucher v in rows)
        <String>['${v.day} Sep', v.no, v.party, kKinds[v.kind]!.t, _pm(v)],
    ],
    right: const <int>{4},
  ),
  totals: <(String, String)>[
    ('Entries', '${rows.length}'),
    ('Total value', inr(rows.fold<int>(0, (int s, Voucher v) => s + v.amt))),
  ],
);

ShareDoc docBills(bool recv, List<Bill> rows, String company) => ShareDoc(
  title: recv ? 'To get (Receivable)' : 'To give (Payable)',
  subtitle: 'As on 26 Sep 2026',
  company: company,
  fileStem: recv ? 'Receivable' : 'Payable',
  table: DocTable(
    const <String>['Party', 'Bill', 'City', 'Status', 'Amount'],
    <List<String>>[
      for (final Bill b in rows)
        <String>[b.party, b.no, b.city, b.txt, inr(b.amt)],
    ],
    right: const <int>{4},
  ),
  totals: <(String, String)>[
    ('Total', inr(rows.fold<int>(0, (int s, Bill b) => s + b.amt))),
  ],
);

ShareDoc docItems(List<Item> rows, String company) => ShareDoc(
  title: 'Items · Stock summary',
  subtitle: 'Your stock from Tally',
  company: company,
  fileStem: 'Stock',
  table: DocTable(
    const <String>['Item', 'Stock', 'Rate', 'Value'],
    <List<String>>[
      for (final Item x in rows)
        <String>[
          x.name,
          x.stock > 0 ? '${x.stock} ${x.unit}' : 'Finished',
          '${inr(x.rate)} / ${x.unit}',
          inr(x.stock * x.rate),
        ],
    ],
    right: const <int>{2, 3},
  ),
  totals: <(String, String)>[
    (
      'Total stock value',
      inr(rows.fold<int>(0, (int s, Item x) => s + x.stock * x.rate)),
    ),
  ],
);

ShareDoc docItem(Item x, String company) => ShareDoc(
  title: x.name,
  subtitle: 'Item · stock from Tally',
  company: company,
  fileStem: 'Item_${x.name}',
  facts: <(String, String)>[
    ('Stock', x.stock > 0 ? '${x.stock} ${x.unit}' : 'Finished'),
    ('Rate', '${inr(x.rate)} / ${x.unit}'),
    (
      'Status',
      x.st == 'ok' ? 'In stock' : (x.st == 'low' ? 'Running low' : 'Finished'),
    ),
  ],
  totals: <(String, String)>[('Stock value', inr(x.stock * x.rate))],
);

ShareDoc docParties(List<Party> rows, String company) => ShareDoc(
  title: 'Party · Customers and suppliers',
  company: company,
  fileStem: 'Parties',
  table: DocTable(
    const <String>['Party', 'Type', 'City', 'Balance'],
    <List<String>>[
      for (final Party p in rows)
        <String>[
          p.name,
          p.type == 'c' ? 'Customer' : 'Supplier',
          p.city,
          p.bal == 0 ? 'Settled' : inr(p.bal),
        ],
    ],
    right: const <int>{3},
  ),
);

ShareDoc docPartyRow(Party p, String company) => ShareDoc(
  title: p.name,
  subtitle: '${p.type == 'c' ? 'Customer' : 'Supplier'} · ${p.city}',
  company: company,
  fileStem: 'Party_${p.name}',
  totals: <(String, String)>[
    (
      'Balance',
      p.bal == 0
          ? 'Settled'
          : '${inr(p.bal)} · ${p.type == 'c' ? 'They owe you' : 'You owe'}',
    ),
  ],
);

const Map<String, String> _stTxt = <String, String>{
  'ok': 'Sent',
  'wait': 'Waiting',
  'fail': 'Not sent',
};

ShareDoc docActs(List<Act> rows, String company) => ShareDoc(
  title: 'Activity · Entries on their way to Tally',
  company: company,
  fileStem: 'Activity',
  table: DocTable(
    const <String>['Time', 'Entry', 'Party / account', 'Status', 'Amount'],
    <List<String>>[
      for (final Act a in rows)
        <String>[
          a.time,
          '${kKinds[a.kind]!.t} · ${a.no}',
          a.party,
          _stTxt[a.status]!,
          inr(a.amt),
        ],
    ],
    right: const <int>{4},
  ),
);

ShareDoc docAct(Act a, String company) => ShareDoc(
  title: '${kKinds[a.kind]!.long} · ${a.no}',
  subtitle: _stTxt[a.status]!,
  company: company,
  fileStem: 'Activity_${a.no}',
  facts: <(String, String)>[
    ('Entry number', a.no),
    ('Party / account', a.party),
    ('Amount', inr(a.amt)),
    ('Saved', a.time),
    ('Status', _stTxt[a.status]!),
    if (a.note.isNotEmpty) ('Note', a.note),
  ],
);

ShareDoc docNotif(Notif n, String company) => ShareDoc(
  title: n.t,
  subtitle: n.time,
  company: company,
  fileStem: 'Alert_${n.t}',
  facts: <(String, String)>[('Alert', n.b)],
);

ShareDoc docMember(Member m, String company) => ShareDoc(
  title: m.name,
  subtitle: 'Sales Team',
  company: company,
  fileStem: 'Team_${m.name}',
  facts: <(String, String)>[
    ('Email / mobile', m.email),
    ('Role', m.role),
    (
      'Status',
      m.st == 'active'
          ? 'Active'
          : (m.st == 'pending' ? 'Invite sent' : 'Turned off'),
    ),
  ],
);

ShareDoc docSums(List<SumCard> sums, String company) => ShareDoc(
  title: 'Money summary',
  subtitle: 'September 2026 · Sample data',
  company: company,
  fileStem: 'Money_summary',
  facts: <(String, String)>[
    for (final SumCard s in sums) ('${s.t} (${s.s})', inr(s.v)),
  ],
);
