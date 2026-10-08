// Backend JSON → app models. Pure functions (unit-tested). Rules:
//  • NUMERIC / COUNT columns arrive as strings — always parsed, never
//    defaulted to a made-up value (missing → null / 0 only where 0 is true);
//  • DATE columns arrive as midnight-UTC ISO strings — read as calendar dates
//    from the UTC fields, never shifted by the phone's time zone;
//  • TIMESTAMP columns (created_at, last_sync_at) are converted to local time.
library;

import '../../core/utils/format.dart';
import '../accounting.dart';
import '../models/models.dart';

num? toNum(Object? v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v.trim());
  return null;
}

String str(Object? v) => v == null ? '' : '$v'.trim();

/// Calendar date from a DATE column / `YYYY-MM-DD` string.
DateTime? dateOnly(Object? v) {
  if (v is! String || v.isEmpty) return null;
  final DateTime? d = DateTime.tryParse(v);
  if (d == null) return null;
  final DateTime u = d.isUtc ? d : d.toUtc();
  // A bare `YYYY-MM-DD` parses as local midnight; keep its own fields.
  return v.length <= 10
      ? DateTime(d.year, d.month, d.day)
      : DateTime(u.year, u.month, u.day);
}

/// Instant from a TIMESTAMP column, in local time.
DateTime? instant(Object? v) {
  if (v is! String || v.isEmpty) return null;
  return DateTime.tryParse(v)?.toLocal();
}

/// `{success, data:[…]}`, `{success, <key>:[…]}` or a raw array → list of maps.
List<Map<String, Object?>> rows(Object? body, [String key = 'data']) {
  Object? l = body;
  if (body is Map) l = body[key] ?? body['data'];
  if (l is! List) return const <Map<String, Object?>>[];
  return <Map<String, Object?>>[
    for (final Object? e in l)
      if (e is Map) e.cast<String, Object?>(),
  ];
}

// ----------------------------------------------------------------- auth

({String token, AuthUser user}) loginResult(Object? body) {
  if (body is! Map) throw const FormatException('Unexpected login response');
  final Object? t = body['token'];
  final AuthUser? u = AuthUser.fromJson(body['user']);
  if (t is! String || t.isEmpty || u == null) {
    throw const FormatException('Login response has no token');
  }
  return (token: t, user: u);
}

Profile profileFrom(Object? body) {
  final Map<String, Object?> m = body is Map
      ? body.cast<String, Object?>()
      : const <String, Object?>{};
  return Profile(
    username: str(m['username']),
    email: str(m['email']),
    role: str(m['role']),
    company: m['company'] is String ? m['company'] as String : null,
    adminEmail: m['admin_email'] is String ? m['admin_email'] as String : null,
  );
}

// -------------------------------------------------------------- company

Company companyFrom(Map<String, Object?> m) => Company(
  str(m['company_guid']),
  str(m['name']).isEmpty ? str(m['company_guid']) : str(m['name']),
  m['starting_from'] is String
      ? 'Tally company · from ${fdate(m['starting_from'] as String)}'
      : 'Tally company',
);

SyncInfo syncFrom(Object? body) {
  final Map<Object?, Object?> m = body is Map
      ? body
      : const <Object?, Object?>{};
  return SyncInfo(instant(m['last_sync_at']), m['sync_in_progress'] == true);
}

// -------------------------------------------------------------- ledgers

/// `c` / `s` / `o` from the ledger's Tally group (`parent_group`), the only
/// classification the backend sends. Sundry Debtors → customer, Sundry
/// Creditors → supplier; every other ledger is `o` (never guessed). A custom
/// sub-group under Debtors / Creditors whose name lacks those words stays
/// `o` — BACKEND_CHANGE_REQUIRED (primary group not sent).
String partyTypeOf(String? group) {
  final String g = (group ?? '').toLowerCase();
  if (g.contains('debtor')) return 'c';
  if (g.contains('creditor')) return 's';
  return 'o';
}

bool isCashOrBank(String? group) {
  final String g = (group ?? '').toLowerCase();
  return g.contains('cash') || g.contains('bank');
}

class LedgerRow {
  const LedgerRow({
    required this.guid,
    required this.name,
    required this.group,
    this.email,
    this.phone,
    this.opening,
    this.closing,
    this.lastDate,
    this.search = '',
  });
  final String guid, name, group;

  /// Lower-case `name group`, built once (in the parsing isolate).
  final String search;
  final String? email, phone;
  final num? opening, closing;
  final DateTime? lastDate;
}

LedgerRow ledgerFrom(Map<String, Object?> m) => LedgerRow(
  guid: str(m['ledger_guid']),
  name: str(m['name']),
  group: str(m['parent_group']),
  email: str(m['email']).isEmpty ? null : str(m['email']),
  phone: str(m['phone']).isEmpty ? null : str(m['phone']),
  opening: toNum(m['opening_balance']),
  closing: toNum(m['closing_balance']),
  lastDate: dateOnly(m['date']),
  search: '${str(m['name'])} ${str(m['parent_group'])}'.toLowerCase(),
);

// ---------------------------------------------------------------- bills

/// A `GET /bill` row → [Bill]. Returns null for settled / zero rows.
Bill? billFrom(Map<String, Object?> m, DateTime today) {
  final num? pending = toNum(m['pending_amount']);
  if (pending == null || pending <= 0) return null;
  final DateTime? due = dateOnly(m['due_date']);
  final DateTime? billDate = dateOnly(m['bill_date']);
  final ({String st, String txt}) s = billStatus(due, today);
  final bool pay = str(m['bill_type']).toUpperCase() == 'PAYABLE';
  final String credit = (due != null && billDate != null)
      ? '${dayDiff(billDate, due)} days'
      : '—';
  final String guid = str(m['bill_guid']);
  return Bill(
    str(m['ledger_name']),
    str(m['bill_name']),
    dmy(billDate),
    dmy(due),
    credit,
    pending,
    s.st,
    s.txt,
    '',
    pay ? 'pay' : 'recv',
    '${str(m['ledger_guid'])}|${guid.isEmpty ? str(m['bill_name']) : guid}',
    str(m['ledger_guid']).isEmpty ? null : str(m['ledger_guid']),
    due,
    toNum(m['bill_amount']),
    _billItems(m['items']),
  );
}

List<BillLine> _billItems(Object? v) => <BillLine>[
  if (v is List)
    for (final Object? e in v)
      if (e is Map)
        BillLine(
          str(e['item_name']),
          '',
          str(e['total_qty']),
          '',
          toNum(e['total_amount']) ?? 0,
        ),
];

// ------------------------------------------------------------- vouchers

/// A `/voucher-entry/paged` row → [Voucher].
/// `amount` is Tally's voucher net amount; its sign convention is not
/// documented, so the magnitude is used and the voucher type gives the
/// direction.
///
/// `is_active` is not a deletion flag on this backend: a voucher deleted in
/// Tally is removed from the table by the agent's cleanup, while
/// `is_active = false` is only the start-of-full-sync reset (`/reset-active`)
/// left on vouchers a sync run did not re-post. Those are real Tally
/// vouchers (the server's total equals Tally's own voucher count), so every
/// row is kept — dropping them emptied whole types (Journal, Contra,
/// Physical Stock) whose rows carried the stale flag.
Voucher? voucherFrom(Map<String, Object?> m) {
  final DateTime? d = dateOnly(m['voucher_date']);
  final String type = str(m['voucher_type']);
  final num amt = (toNum(m['amount']) ?? 0).abs();
  return Voucher(
    voucherKind(type),
    str(m['party_name']).isEmpty ? '—' : str(m['party_name']),
    str(m['reference_no']).isEmpty ? type : str(m['reference_no']),
    d?.day ?? 0,
    amt,
    guid: str(m['voucher_guid']),
    date: d,
    type: type,
    items: <VoucherItem>[
      if (m['items'] is List)
        for (final Object? e in m['items']! as List)
          if (e is Map)
            VoucherItem(
              str(e['item_name']),
              toNum(e['quantity']),
              toNum(e['rate']),
              toNum(e['amount']),
            ),
    ],
  );
}

/// A `/voucher-entry/ledger/:guid` row (party view: this ledger's debit /
/// credit in the voucher).
Voucher ledgerVoucherFrom(Map<String, Object?> m, String party) {
  final DateTime? d = dateOnly(m['voucher_date']);
  final String type = str(m['voucher_type']);
  final num dr = toNum(m['debit']) ?? 0, cr = toNum(m['credit']) ?? 0;
  return Voucher(
    voucherKind(type),
    party,
    str(m['reference_no']).isEmpty ? type : str(m['reference_no']),
    d?.day ?? 0,
    (dr - cr).abs(),
    guid: str(m['id']),
    date: d,
    type: type,
  );
}

List<LedgerLine> ledgerLinesFrom(Object? body) {
  final Object? l = body is Map ? body['ledger_entries'] : null;
  return <LedgerLine>[
    if (l is List)
      for (final Object? e in l)
        if (e is Map)
          LedgerLine(
            str(e['ledger_name']),
            (toNum(e['amount']) ?? 0).abs(),
            e['is_debit'] == true,
          ),
  ];
}

// ---------------------------------------------------------------- items

/// A `/inventory/mobile` row. Closing qty / value come from Tally's stock
/// summary, opening qty / value from the stock-item master; the unit is kept
/// exactly as Tally names it (it is sent back to Tally in vouchers).
/// Tally exports stock values with its Dr / Cr sign: a debit (an asset —
/// stock held) is negative, e.g. `OPENINGVALUE -3576.38` for 301 bottles
/// worth ₹3,576.38, while quantities are plain (301). The agent and server
/// store and return those values as exported, and the server's `rate` is
/// `closing_value ÷ closing_qty`, so it carries the same sign. Converted
/// here into an ordinary stock value (Dr → positive): a genuine credit
/// stock value stays negative — this is a sign convention, not `abs`.
num? _stockValue(Object? tallySigned) {
  final num? v = toNum(tallySigned);
  return v == null ? null : (v == 0 ? 0 : -v);
}

Item itemFrom(Map<String, Object?> m) {
  final num qty = toNum(m['closing_qty']) ?? 0;
  final num? value = _stockValue(m['closing_value']);
  return Item(
    str(m['name']),
    qty,
    str(m['unit']),
    _stockValue(m['rate']) ?? 0,
    // The server always sends minStock 0, so "running low" cannot be known.
    // Items without a unit carry value only, so value also counts as stock.
    (qty > 0 || (value ?? 0) > 0) ? 'ok' : 'out',
    guid: str(m['item_guid']),
    value: value,
    hsn: str(m['hsn_code']).isEmpty ? null : str(m['hsn_code']),
    gst: toNum(m['gst_rate']),
    group: str(m['group']).isEmpty ? null : str(m['group']),
    openingQty: toNum(m['opening_qty']),
    openingValue: _stockValue(m['opening_value']),
    search: '${str(m['name'])} ${str(m['group'])} ${str(m['hsn_code'])}'
        .toLowerCase(),
  );
}

/// A `/ledger-items/item/:itemName/parties` row.
ItemParty itemPartyFrom(Map<String, Object?> m) => ItemParty(
  name: str(m['party_name']),
  qty: toNum(m['total_qty']),
  amount: toNum(m['total_amount']),
  invoices: toNum(m['invoices'])?.toInt(),
  lastDate: dateOnly(m['last_date']),
);

StockRow stockFrom(Map<String, Object?> m) => StockRow(
  str(m['name']),
  toNum(m['opening']),
  toNum(m['inward']),
  toNum(m['outward']),
  toNum(m['closing']),
);

// ------------------------------------------------------------- activity

const Map<String, String> _queueStatus = <String, String>{
  'success': 'ok',
  'failed': 'fail',
  'pending': 'wait',
  'processing': 'wait',
};

/// A `/api/mobile-sync-queue/activity` row → [Act].
Act actFrom(Map<String, Object?> m, DateTime now) {
  final Map<Object?, Object?> p = m['payload'] is Map
      ? m['payload']! as Map
      : const <Object?, Object?>{};
  final String type = str(p['voucher_type']);
  final String kind = voucherKind(type);
  num amt = 0;
  final Object? summary = p['summary'];
  if (summary is Map && toNum(summary['total_amount']) != null) {
    amt = toNum(summary['total_amount'])!;
  } else if (toNum(p['amount_received']) != null) {
    amt = toNum(p['amount_received'])!;
  } else if (toNum(p['amount_paid']) != null) {
    amt = toNum(p['amount_paid'])!;
  } else if (p['ledger_entries'] is List) {
    for (final Object? e in p['ledger_entries']! as List) {
      if (e is Map && e['is_debit'] == true) amt += toNum(e['amount']) ?? 0;
    }
  }
  String party = str(p['party_name']);
  if (party.isEmpty && p['ledger_entries'] is List) {
    final List<Object?> le = p['ledger_entries']! as List<Object?>;
    if (le.isNotEmpty && le.first is Map) {
      party = str((le.first! as Map)['ledger_name']);
    }
  }
  final DateTime? at = instant(m['created_at']);
  final Object? pay = p['payment'];
  final List<(String, String)> rowsOut = <(String, String)>[
    ('Voucher type', type.isEmpty ? '—' : type),
    ('Date', fdate(str(p['voucher_date']))),
    if (str(p['due_date']).isNotEmpty) ('Pay by', fdate(str(p['due_date']))),
    if (pay is Map && str(pay['payment_mode']).isNotEmpty)
      ('Paid by', str(pay['payment_mode'])),
    if (str(p['reference_no']).isNotEmpty)
      ('Reference no.', str(p['reference_no'])),
    if (str(p['narration']).isNotEmpty) ('Note', str(p['narration'])),
    if (at != null) ('Saved', '${dmy(at)} · ${clock(at)}'),
    if (instant(m['processed_at']) != null)
      (
        'Processed',
        '${dmy(instant(m['processed_at']))} · ${clock(instant(m['processed_at'])!)}',
      ),
  ];
  final List<(String, String, num)> itemsOut = <(String, String, num)>[
    if (p['items'] is List)
      for (final Object? e in p['items']! as List)
        if (e is Map)
          (
            // Agent contract keys; older queued entries used name/qty/gst.
            str(e['item_name'] ?? e['name']),
            'Qty: ${str(e['quantity'] ?? e['qty'])} ${str(e['unit'])} · Rate: ${inr(toNum(e['rate']) ?? 0)}'
                '${toNum(e['gst_rate'] ?? e['gst']) != null ? ' · GST ${str(e['gst_rate'] ?? e['gst'])}%' : ''}',
            toNum(e['amount']) ?? 0,
          ),
    if (p['ledger_entries'] is List && type.toLowerCase() == 'journal')
      for (final Object? e in p['ledger_entries']! as List)
        if (e is Map)
          (
            str(e['ledger_name']),
            e['is_debit'] == true ? 'Goes to (Dr)' : 'Comes from (Cr)',
            toNum(e['amount']) ?? 0,
          ),
  ];
  return Act(
    'q${str(m['id'])}',
    kind,
    str(p['voucher_no']).isEmpty ? '#${str(m['id'])}' : str(p['voucher_no']),
    party.isEmpty ? '—' : party,
    amt,
    at == null ? '' : stamp(at, now),
    _queueStatus[str(m['status']).toLowerCase()] ?? 'wait',
    str(m['error']),
    rowsOut,
    itemsOut,
  );
}

// -------------------------------------------------------- notifications

/// Icon, colour and target screen per server notification type.
const Map<String, (String, String, NavTo)> kNotifTypes =
    <String, (String, String, NavTo)>{
      'create_entry': ('plus', 'activity', NavTo('activity')),
      'entry_failed': ('xCircle', 'payment', NavTo('activity')),
      'sync_failed': ('xCircle', 'payment', NavTo('activity')),
      'sync_completed': ('sync', 'activity', NavTo('activity')),
      'voucher_sync': (
        'receipt',
        'vouchers',
        NavTo('vList', <String, Object?>{'vFilter': 'all', 'vPeriod': 'month'}),
      ),
      'party_sync': ('person', 'party', NavTo('party')),
      'ledger_sync': ('person', 'party', NavTo('party')),
      'item_sync': ('box', 'items', NavTo('items')),
      'tally_connection': ('laptop', 'activity', NavTo('activity')),
      'system_alerts': ('bell', 'acc', NavTo('notifs')),
    };

/// Prefix of web-dashboard alert ids (`w:<id>`) and of web preference keys
/// in the alert switches (`web.<key>`).
const String kWebNotif = 'w:';
const String kWebPref = 'web.';

/// Web-dashboard alert types shown in the app: title, icon, colour, target.
/// Other web types (none with a switch) are not shown.
const Map<String, (String, String, String, NavTo)> kWebNotifTypes =
    <String, (String, String, String, NavTo)>{
      'BILL': ('Bill Created', 'file', 'sales', NavTo('outHub')),
      'MONTHLY_REPORT': ('Monthly Report', 'chart', 'acc', NavTo('reports')),
      'USER_CREATED': ('Team Member Added', 'userPlus', 'team', NavTo('team')),
      'USER_INVITE': ('Team Invite Sent', 'mail', 'team', NavTo('team')),
      'USER_DELETED': ('Team Member Removed', 'person', 'team', NavTo('team')),
      'VOUCHER_CREATED': (
        'Voucher Created',
        'receipt',
        'vouchers',
        NavTo('activity'),
      ),
      'VOUCHER_DELETED': (
        'Voucher Deleted',
        'trash',
        'vouchers',
        NavTo('activity'),
      ),
    };

/// A `/admin/notifications` row → [Notif] (id `w:<id>`).
Notif webNotifFrom(Map<String, Object?> m, DateTime now) {
  final (String, String, String, NavTo) t = kWebNotifTypes[str(m['type'])]!;
  final DateTime? at = instant(m['created_at']);
  return Notif(
    '$kWebNotif${str(m['id'])}',
    t.$1,
    str(m['message']),
    at == null ? '' : ago(at, now),
    t.$2,
    t.$3,
    m['is_read'] != true,
    t.$4,
  );
}

Notif notifFrom(Map<String, Object?> m, DateTime now) {
  final (String, String, NavTo) t =
      kNotifTypes[str(m['type'])] ?? ('bell', 'acc', const NavTo('notifs'));
  final DateTime? at = instant(m['created_at']);
  return Notif(
    str(m['id']),
    str(m['title']),
    str(m['message']),
    at == null ? '' : ago(at, now),
    t.$1,
    t.$2,
    m['is_read'] != true,
    t.$3,
  );
}

// ----------------------------------------------------------------- team

Member memberFrom(Map<String, Object?> m) => Member(
  str(m['id']),
  str(m['username']).isEmpty ? str(m['email']) : str(m['username']),
  str(m['email']),
  str(m['role']).toUpperCase() == 'ADMIN' ? 'Admin' : 'Team member',
  'active',
);

// ------------------------------------------------------- entry results

SubmitResult submitResultFrom(Object? body) {
  final Map<Object?, Object?> m = body is Map
      ? body
      : const <Object?, Object?>{};
  final bool dup = m['duplicate'] == true;
  return SubmitResult(
    ok: m['success'] == true,
    duplicate: dup,
    commandId: m['command_id'] == null ? null : '${m['command_id']}',
    message: dup
        ? 'This entry was already sent'
        : (str(m['status']).toUpperCase() == 'QUEUED'
              ? 'Saved! It will reach Tally by itself'
              : str(m['message'])),
  );
}
