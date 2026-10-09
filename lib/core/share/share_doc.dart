// Shareable documents (NEW feature — not in the prototype). Each builder
// turns the same data a screen shows into a [ShareDoc]: a plain-text summary
// for the share sheet plus the content of the PDF.
library;

import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import '../utils/format.dart';
import 'report_data.dart';

/// Bill / invoice layout data (the prototype's PDF "paper", 1563–1582).
/// Only real values: item lines and totals as Tally sent them. No tax split
/// is ever estimated — when the server sends no breakdown, none is shown.
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
    required this.total,
    required this.kind,
    this.sub,
    this.taxes = const <(String, num)>[],
    this.seller = const <String>[],
    this.note = '',
    this.accounts = const <(String, String, String)>[],
  });
  final String heading, toLabel, no, date, due, party, city, kind;

  /// Dr / Cr, ledger, amount — the voucher's accounts (empty when none).
  final List<(String, String, String)> accounts;

  /// A due date to show (vouchers have none).
  bool get hasDue => due.trim().isNotEmpty && due.trim() != '—';

  /// #, item, HSN, qty, rate, amount
  final List<(String, String, String, String, String, String)> lines;

  /// Sum of the item lines (null when there are no lines).
  final num? sub;

  /// Rows between subtotal and total (label, amount).
  final List<(String, num)> taxes;
  final num total;

  /// Seller address / GSTIN lines (sample data only — not sent by server).
  final List<String> seller;
  final String note;

  String get fileName => '${no.replaceFirst(' ', '_')}.pdf';
}

/// The prototype's sample Sales 9 seller block and party GSTIN.
const List<String> kSampleSeller = <String>[
  'Unit 4, Laxmi Industrial Estate, Andheri (E), Mumbai – 400093',
  'GSTIN: 27AAGFG4417K1Z5',
];

/// `pdf` view model (2553–2561), built only from [PdfInfo]'s real lines.
InvoiceSpec invoiceOf(PdfInfo pd) {
  final bool sample = pd.no == 'Sales 9' && pd.city == 'Mumbai';
  final bool purchase =
      pd.recv == false || RegExp('PI|Purchase').hasMatch(pd.kind);
  // Sales bills / vouchers are invoices; any other voucher is titled by its
  // own Tally type (Receipt, Payment, Journal, …).
  final bool sale =
      !purchase && (pd.recv == true || pd.kind.toLowerCase().contains('sale'));
  final String other = pd.kind.trim().isEmpty
      ? 'VOUCHER'
      : (pd.kind.toUpperCase().contains('VOUCHER')
            ? pd.kind.toUpperCase()
            : '${pd.kind.toUpperCase()} VOUCHER');
  final num? sub = pd.lines.isEmpty
      ? null
      : paise(sumRupees(pd.lines.map((BillLine l) => l.amt)));
  final num diff = sub == null ? 0 : paise(pd.total - sub);
  final List<(String, num)> taxes = <(String, num)>[
    if (sample) ...<(String, num)>[
      ('CGST @ 9%', diff / 2),
      ('SGST @ 9%', diff / 2),
    ] else if (sub != null && diff.abs() >= .01)
      ('Taxes & charges (as per Tally)', diff),
  ];
  return InvoiceSpec(
    heading: purchase ? 'PURCHASE BILL' : (sale ? 'TAX INVOICE' : other),
    toLabel: purchase ? 'BILL FROM' : (sale ? 'BILLED TO' : 'PARTY / ACCOUNT'),
    no: pd.no,
    date: pd.date,
    due: pd.due,
    party: pd.party,
    city: '${pd.city}${sample ? ' · GSTIN: 27AAKFS2291M1Z8' : ''}',
    kind: pd.kind,
    lines: <(String, String, String, String, String, String)>[
      for (int i = 0; i < pd.lines.length; i++)
        (
          '${i + 1}',
          pd.lines[i].name,
          pd.lines[i].hsn.isEmpty ? '—' : pd.lines[i].hsn,
          pd.lines[i].qty.isEmpty ? '—' : pd.lines[i].qty,
          pd.lines[i].rate.isEmpty ? '—' : pd.lines[i].rate,
          inr(pd.lines[i].amt),
        ),
    ],
    sub: sub,
    taxes: taxes,
    total: pd.total,
    seller: sample ? kSampleSeller : const <String>[],
    // Only real sections: with no item lines there is no item table and no
    // note about it.
    note: pd.lines.isEmpty || sample || taxes.isEmpty
        ? ''
        : 'Tax details are not sent by the server.',
    accounts: <(String, String, String)>[
      for (final LedgerLine l in pd.ledger)
        (l.debit ? 'Dr' : 'Cr', l.ledger, inr(l.amt)),
    ],
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
        '${switch (iv.toLabel) {
          'BILLED TO' => 'Billed to',
          'BILL FROM' => 'Bill from',
          _ => 'Party / account',
        }}: ${iv.party}',
      );
      b.writeln(
        iv.hasDue ? 'Date: ${iv.date} · Due: ${iv.due}' : 'Date: ${iv.date}',
      );
      for (final (String, String, String, String, String, String) l
          in iv.lines) {
        b.writeln('${l.$1}. ${l.$2} — ${l.$4} × ${l.$5} = ${l.$6}');
      }
      for (final (String, String, String) a in iv.accounts) {
        b.writeln('${a.$1} · ${a.$2}: ${a.$3}');
      }
      if (iv.sub != null) b.writeln('Subtotal: ${inr(iv.sub)}');
      for (final (String, num) t in iv.taxes) {
        b.writeln('${t.$1}: ${inr(t.$2)}');
      }
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

ShareDoc docInvoice(PdfInfo pd, String company) =>
    ShareDoc(title: pd.no, company: company, invoice: invoiceOf(pd));

/// Voucher date: real date when known, else the sample month.
String vDate(Voucher v) => v.date != null ? dmy(v.date) : '${v.day} Sep 2026';
String vDay(Voucher v) => v.date != null ? dm(v.date!) : '${v.day} Sep';

/// Everything one voucher has, for its PDF: the real item lines (when the
/// voucher has items) and the real Dr / Cr ledger lines (when loaded).
PdfInfo voucherPdfInfo(
  Voucher e, {
  List<LedgerLine>? lines,
  String city = '',
}) => PdfInfo(
  party: e.party,
  no: e.no,
  date: vDate(e),
  due: '',
  total: e.amt,
  kind: e.type ?? kKinds[e.kind]!.t,
  recv: e.kind == 'purchase' ? false : null,
  city: city,
  lines: <BillLine>[
    for (final VoucherItem i in e.items)
      BillLine(
        i.name,
        '',
        i.qty == null ? '' : qty(i.qty!),
        i.rate == null ? '' : inr(i.rate),
        i.amt ?? 0,
      ),
  ],
  ledger: lines ?? const <LedgerLine>[],
);

/// The one document of a voucher: Voucher Detail's See bill PDF, Share and
/// Download all use it.
ShareDoc docVoucher(
  Voucher e,
  String company, {
  List<LedgerLine>? lines,
  String city = '',
}) => docInvoice(voucherPdfInfo(e, lines: lines, city: city), company);

ShareDoc docBill(Bill b, String company) {
  final bool r = b.kind == 'recv';
  return ShareDoc(
    title: 'Bill details · ${b.no}',
    subtitle:
        '${b.party} · ${r ? 'Customer' : 'Supplier'}${b.city.isEmpty ? '' : ' · ${b.city}'}',
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
  DateTime today, {
  bool remote = false,
}) {
  final bool pc = p0.type == 'c';
  return ShareDoc(
    title: p0.name,
    subtitle:
        '${p0.kindLabel}${p0.city.isEmpty ? '' : ' · ${p0.city}'} · ${remote ? 'Outstanding' : 'Balance'} as on ${dmy(today)}',
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
                <String>[vDate(v), v.no, kKinds[v.kind]!.t, inr(v.amt)],
            ],
            right: const <int>{3},
          ),
    totals: <(String, String)>[
      remote
          ? ('Outstanding', inr(p0.bal.abs()))
          : (
              'Balance',
              '${inr(p0.bal)}${p0.bal != 0 ? (pc ? ' Dr' : ' Cr') : ''}',
            ),
    ],
  );
}

ShareDoc docReport(ReportData d, String company) => ShareDoc(
  title: d.report.t,
  subtitle: '${d.report.s} · ${d.period}',
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
  String period, [
  String month = 'September 2026',
]) => ShareDoc(
  title: title,
  subtitle: '$company · $month · $period',
  company: company,
  fileStem: 'Vouchers_$title',
  table: DocTable(
    const <String>['Date', 'Entry', 'Party / account', 'Type', 'Amount'],
    <List<String>>[
      for (final Voucher v in rows)
        <String>[vDay(v), v.no, v.party, v.type ?? kKinds[v.kind]!.t, _pm(v)],
    ],
    right: const <int>{4},
  ),
  totals: <(String, String)>[
    ('Entries', '${rows.length}'),
    ('Total value', inr(sumRupees(rows.map((Voucher v) => v.amt)))),
  ],
);

ShareDoc docBills(bool recv, List<Bill> rows, String company, DateTime today) =>
    ShareDoc(
      title: recv ? 'Receivable (Outstanding)' : 'Payable (Outstanding)',
      subtitle: 'As on ${dmy(today)}',
      company: company,
      fileStem: recv ? 'Receivable' : 'Payable',
      table: DocTable(
        const <String>['Party', 'Bill', 'Due', 'Status', 'Amount'],
        <List<String>>[
          for (final Bill b in rows)
            <String>[b.party, b.no, b.due, b.txt, inr(b.amt)],
        ],
        right: const <int>{4},
      ),
      totals: <(String, String)>[
        ('Total', inr(sumRupees(rows.map((Bill b) => b.amt)))),
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
        <String>[x.name, stockLabel(x), rateLabel(x), inr(x.worth)],
    ],
    right: const <int>{2, 3},
  ),
  totals: <(String, String)>[
    ('Total stock value', inr(sumRupees(rows.map((Item x) => x.worth)))),
  ],
);

/// Stock text: `12 pcs`; items without a quantity but with a value (no
/// unit in Tally) show `Value only`; nothing left → `Finished`.
String stockLabel(Item x) {
  if (x.stock > 0) {
    return x.unit.isEmpty ? qty(x.stock) : '${qty(x.stock)} ${x.unit}';
  }
  return x.worth > 0 ? 'Value only' : 'Finished';
}

/// Rate text: Tally closing rate, else the opening rate, else `—`
/// (never a made-up ₹0).
String rateLabel(Item x) {
  final num? r = x.rate > 0 ? x.rate : x.openingRate;
  if (r == null || r <= 0) return '—';
  return x.unit.isEmpty ? inr(paise(r)) : '${inr(paise(r))} / ${x.unit}';
}

ShareDoc docItem(Item x, String company) => ShareDoc(
  title: x.name,
  subtitle: 'Item · stock from Tally',
  company: company,
  fileStem: 'Item_${x.name}',
  facts: <(String, String)>[
    ('Stock', stockLabel(x)),
    if (x.openingQty != null && x.openingQty != 0)
      ('Opening stock', '${qty(x.openingQty!)} ${x.unit}'.trim()),
    if (x.openingValue != null) ('Opening value', inr(x.openingValue)),
    ('Rate', rateLabel(x)),
    (
      'Status',
      x.st == 'ok' ? 'In stock' : (x.st == 'low' ? 'Running low' : 'Finished'),
    ),
  ],
  totals: <(String, String)>[('Stock value', inr(x.worth))],
);

ShareDoc docParties(List<Party> rows, String company) => ShareDoc(
  title: 'Party · Customers and suppliers',
  company: company,
  fileStem: 'Parties',
  table: DocTable(
    const <String>['Party', 'Type', 'Group / city', 'Balance'],
    <List<String>>[
      for (final Party p in rows)
        <String>[
          p.name,
          p.kindLabel,
          p.city.isNotEmpty ? p.city : (p.group ?? ''),
          p.bal == 0
              ? (p.guid != null ? 'No pending bills' : 'Settled')
              : inr(p.bal.abs()),
        ],
    ],
    right: const <int>{3},
  ),
);

ShareDoc docPartyRow(
  Party p,
  String company, [
  bool remote = false,
]) => ShareDoc(
  title: p.name,
  subtitle: '${p.kindLabel} · ${p.city.isNotEmpty ? p.city : (p.group ?? '')}',
  company: company,
  fileStem: 'Party_${p.name}',
  totals: <(String, String)>[
    (
      remote ? 'Outstanding' : 'Balance',
      p.bal == 0
          ? (remote ? 'No pending bills' : 'Settled')
          : '${inr(p.bal.abs())} · ${p.type == 'c' || (p.type == 'o' && p.bal > 0) ? 'They owe you' : 'You owe'}',
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

/// One Activity entry: every detail row and item / account line of the
/// queued entry as the server returned it.
ShareDoc docAct(Act a, String company) => ShareDoc(
  title: '${kKinds[a.kind]!.long} · ${a.no}',
  subtitle: _stTxt[a.status]!,
  company: company,
  fileStem: 'Activity_${a.no}',
  facts: <(String, String)>[
    ('Entry number', a.no),
    ('Party / account', a.party),
    ('Amount', inr(a.amt)),
    if (a.rows.isEmpty) ('Saved', a.time),
    for (final (String, String) r in a.rows) (r.$1, r.$2),
    ('Status', _stTxt[a.status]!),
    if (a.note.isNotEmpty) ('Note', a.note),
  ],
  table: a.items.isEmpty
      ? null
      : DocTable(
          <String>[
            '#',
            a.kind == 'journal' ? 'Account' : 'Item',
            'Details',
            'Amount',
          ],
          <List<String>>[
            for (int i = 0; i < a.items.length; i++)
              <String>[
                '${i + 1}',
                a.items[i].$1,
                a.items[i].$2,
                inr(a.items[i].$3),
              ],
          ],
          right: const <int>{3},
        ),
  totals: <(String, String)>[('Amount', inr(a.amt))],
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

ShareDoc docSums(
  List<SumCard> sums,
  String company, [
  String period = 'September 2026 · Sample data',
]) => ShareDoc(
  title: 'Money summary',
  subtitle: period,
  company: company,
  fileStem: 'Money_summary',
  facts: <(String, String)>[
    for (final SumCard s in sums)
      ('${s.t} (${s.s})', s.v == null ? '—' : inr(s.v)),
  ],
);
