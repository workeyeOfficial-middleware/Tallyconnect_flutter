// E-invoice tracking (`/api/einvoice/*`): each sales invoice's e-invoice as
// TallyPrime created it (IRN, acknowledgement, signed QR, e-way bill), its
// status and alerts. The e-invoice itself is created in Tally; the app only
// shows and tracks it.
library;

num _n(Object? v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
num? _nn(Object? v) => v == null ? null : _n(v);
String _s(Object? v) => v == null ? '' : '$v';
String? _os(Object? v) => _s(v).trim().isEmpty ? null : _s(v).trim();
DateTime? _d(Object? v) {
  final DateTime? x = DateTime.tryParse(_s(v));
  return x == null ? null : DateTime(x.year, x.month, x.day);
}

List<Object?> _list(Object? v) => v is List ? v : const <Object?>[];
Map<Object?, Object?> _map(Object? v) =>
    v is Map ? v : const <Object?, Object?>{};

/// `done` (e-invoiced), `pending` (needed, not done yet), `cancelled`, or
/// `notNeeded` (customer without GST, proforma, purchase …).
enum EinvStatus { done, pending, cancelled, notNeeded }

EinvStatus einvStatusOf(Object? v) => switch ('$v') {
  'done' => EinvStatus.done,
  'pending' => EinvStatus.pending,
  'cancelled' => EinvStatus.cancelled,
  _ => EinvStatus.notNeeded,
};

extension EinvStatusLabel on EinvStatus {
  String get label => switch (this) {
    EinvStatus.done => 'E-invoiced',
    EinvStatus.pending => 'E-invoice pending',
    EinvStatus.cancelled => 'E-invoice cancelled',
    EinvStatus.notNeeded => 'Not needed',
  };
}

/// What an alert means, for the person reading it.
String einvAlertLabel(String a) => switch (a) {
  'overdue' => 'More than 30 days old without an e-invoice',
  'due_soon' => 'E-invoice due within 7 days',
  'late_report' => 'E-invoiced more than 30 days after the invoice',
  'ack_before_invoice' =>
    'Acknowledged before the invoice date — check whether the invoice was '
        'changed after e-invoicing',
  _ => a,
};

/// One invoice's e-invoice details.
class EinvRow {
  const EinvRow({
    required this.voucherGuid,
    required this.date,
    required this.status,
    this.voucherType,
    this.voucherNo,
    this.partyName,
    this.partyGstin,
    this.registrationType,
    this.companyGstin,
    this.placeOfSupply,
    this.amount,
    this.irn,
    this.ackNo,
    this.ackDate,
    this.signedQr,
    this.ewayApplicable,
    this.eway = const <String, String>{},
    this.daysSince = 0,
    this.daysLeft,
    this.alerts = const <String>[],
  });
  final String voucherGuid;
  final DateTime? date, ackDate;
  final EinvStatus status;
  final String? voucherType, voucherNo, partyName, partyGstin;
  final String? registrationType, companyGstin, placeOfSupply;
  final num? amount;
  final String? irn, ackNo, signedQr;
  final bool? ewayApplicable;

  /// E-way bill fields as Tally names them (empty: none).
  final Map<String, String> eway;
  final int daysSince;

  /// Days left of the 30 to e-invoice (pending only).
  final int? daysLeft;
  final List<String> alerts;

  static EinvRow fromJson(Object? o) {
    final Map<Object?, Object?> m = _map(o);
    final Map<Object?, Object?> ew = _map(m['eway']);
    return EinvRow(
      voucherGuid: _s(m['voucher_guid']),
      date: _d(m['date']),
      status: einvStatusOf(m['status']),
      voucherType: _os(m['voucher_type']),
      voucherNo: _os(m['voucher_no'])?.replaceAll(RegExp(r'\s+'), ' '),
      partyName: _os(m['party_name']),
      partyGstin: _os(m['party_gstin']),
      registrationType: _os(m['registration_type']),
      companyGstin: _os(m['company_gstin']),
      placeOfSupply: _os(m['place_of_supply']),
      amount: _nn(m['amount']),
      irn: _os(m['irn']),
      ackNo: _os(m['ack_no']),
      ackDate: _d(m['ack_date']),
      signedQr: _os(m['signed_qr']),
      ewayApplicable: m['eway_applicable'] is bool
          ? m['eway_applicable']! as bool
          : null,
      eway: <String, String>{
        for (final MapEntry<Object?, Object?> e in ew.entries)
          if (_os(e.value) != null) '${e.key}': _s(e.value),
      },
      daysSince: _n(m['days_since']).toInt(),
      daysLeft: m['days_left'] == null ? null : _n(m['days_left']).toInt(),
      alerts: <String>[for (final Object? a in _list(m['alerts'])) _s(a)],
    );
  }
}

/// Counts of a period.
class EinvSummary {
  const EinvSummary({
    this.total = 0,
    this.done = 0,
    this.pending = 0,
    this.cancelled = 0,
    this.notNeeded = 0,
    this.overdue = 0,
    this.dueSoon = 0,
    this.lateReport = 0,
    this.ackBeforeInvoice = 0,
  });
  final int total, done, pending, cancelled, notNeeded;
  final int overdue, dueSoon, lateReport, ackBeforeInvoice;

  int get alerts => overdue + dueSoon + lateReport + ackBeforeInvoice;

  static EinvSummary fromJson(Object? o) {
    final Map<Object?, Object?> m = _map(o);
    int i(String k) => _n(m[k]).toInt();
    return EinvSummary(
      total: i('total'),
      done: i('done'),
      pending: i('pending'),
      cancelled: i('cancelled'),
      notNeeded: i('not_needed'),
      overdue: i('overdue'),
      dueSoon: i('due_soon'),
      lateReport: i('late_report'),
      ackBeforeInvoice: i('ack_before_invoice'),
    );
  }
}

/// `GET /api/einvoice/list`.
class EinvList {
  const EinvList({
    this.from,
    this.to,
    this.status = 'all',
    this.company = '',
    this.summary = const EinvSummary(),
    this.rows = const <EinvRow>[],
    this.truncated = false,
  });
  final DateTime? from, to;
  final String status, company;
  final EinvSummary summary;
  final List<EinvRow> rows;
  final bool truncated;

  static EinvList fromJson(Object? o) {
    final Map<Object?, Object?> m = _map(o);
    return EinvList(
      from: _d(m['from']),
      to: _d(m['to']),
      status: _s(m['status']).isEmpty ? 'all' : _s(m['status']),
      company: _s(m['company']),
      summary: EinvSummary.fromJson(m['summary']),
      rows: <EinvRow>[
        for (final Object? x in _list(m['rows'])) EinvRow.fromJson(x),
      ],
      truncated: m['truncated'] == true,
    );
  }
}
