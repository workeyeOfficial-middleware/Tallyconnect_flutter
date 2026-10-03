// Real backend implementation of [TallyRepository]
// (https://tallyconnect-wlup.onrender.com, see BACKEND_API_REFERENCE.md).
//
// Loads every data set the screens need, keeps the last good snapshot,
// records a [DataStatus] per set (loading / ready / error) and combines
// endpoints here — never in the UI.
library;

import 'dart:async';

import '../../core/network/api_client.dart';
import '../../core/storage/session_store.dart';
import '../../core/utils/format.dart';
import '../accounting.dart';
import '../api/adapters.dart';
import '../api/tally_api.dart';
import '../mock/mock_data.dart';
import '../models/models.dart';
import 'tally_repository.dart';

/// Data-set names used with [TallyRepository.status].
abstract final class DataSet {
  static const String companies = 'companies';
  static const String profile = 'profile';
  static const String ledgers = 'ledgers';
  static const String bills = 'bills';
  static const String vouchers = 'vouchers';
  static const String items = 'items';
  static const String stock = 'stock';
  static const String activity = 'activity';
  static const String notifications = 'notifications';
  static const String team = 'team';
  static const String alerts = 'alerts';
  static const String party = 'party';
  static const String voucher = 'voucher';
}

class ApiTallyRepository extends TallyRepository {
  ApiTallyRepository({
    ApiClient? client,
    SessionStore? sessions,
    DateTime Function()? clock,
  }) : _client = client ?? ApiClient(),
       _sessions = sessions ?? SecureSessionStore(),
       _clock = clock ?? DateTime.now {
    _api = TallyApi(_client);
  }

  final ApiClient _client;
  final SessionStore _sessions;
  final DateTime Function() _clock;
  late final TallyApi _api;

  AuthUser? _user;
  Profile? _profile;
  bool _expired = false;

  List<Company> _companies = const <Company>[];
  String? _active;
  final Map<String, SyncInfo> _sync = <String, SyncInfo>{};

  List<LedgerRow> _ledgers = const <LedgerRow>[];
  List<Bill> _recv = const <Bill>[], _pay = const <Bill>[];
  num? _serverRecv, _serverPay;
  List<Party> _parties = const <Party>[];
  List<Voucher> _vouchers = const <Voucher>[];
  bool _vouchersComplete = true;
  List<Item> _items = const <Item>[];
  List<StockRow> _stock = const <StockRow>[];
  List<Act> _acts = const <Act>[];
  List<Notif> _notifs = const <Notif>[];
  List<Member> _team = const <Member>[];
  Map<String, bool>? _alerts;
  final Map<String, PartyDetail> _partyDetail = <String, PartyDetail>{};
  final Map<String, List<LedgerLine>> _voucherLines =
      <String, List<LedgerLine>>{};
  final Map<String, DataStatus> _status = <String, DataStatus>{};
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _client.close();
    super.dispose();
  }

  @override
  bool get isRemote => true;

  @override
  DateTime get today {
    final DateTime n = _clock();
    return DateTime(n.year, n.month, n.day);
  }

  // ------------------------------------------------------------ session
  @override
  AuthUser? get user => _user;
  @override
  Profile? get profile => _profile;
  @override
  bool get sessionExpired => _expired;

  @override
  Future<AuthUser> login(
    String email,
    String password,
    String loginType,
  ) async {
    final Object? body = await _api.login(
      email.trim().toLowerCase(),
      password,
      loginType,
    );
    final ({String token, AuthUser user}) r = loginResult(body);
    _client.token = r.token;
    _user = r.user;
    _expired = false;
    await _sessions.write(r.token, r.user);
    _notify();
    return r.user;
  }

  @override
  Future<bool> restoreSession() async {
    final ({String token, AuthUser user})? s = await _sessions.read();
    if (s == null) return false;
    _client.token = s.token;
    _user = s.user;
    _expired = false;
    return true;
  }

  @override
  Future<void> logout() async {
    _client.token = null;
    _user = null;
    _profile = null;
    _expired = false;
    _companies = const <Company>[];
    _active = null;
    _sync.clear();
    _ledgers = const <LedgerRow>[];
    _recv = _pay = const <Bill>[];
    _serverRecv = _serverPay = null;
    _parties = const <Party>[];
    _vouchers = const <Voucher>[];
    _items = const <Item>[];
    _stock = const <StockRow>[];
    _acts = const <Act>[];
    _notifs = const <Notif>[];
    _team = const <Member>[];
    _alerts = null;
    _partyDetail.clear();
    _voucherLines.clear();
    _status.clear();
    await _sessions.clear();
    _notify();
  }

  @override
  Future<void> sendResetCode(String email) async {
    await _api.sendOtp(email.trim());
  }

  // ------------------------------------------------------------ loading
  @override
  DataStatus status(String set) => _status[set] ?? DataStatus.idle;

  /// Runs one load, recording its status. A 401 marks the session expired.
  Future<void> _run(String set, Future<void> Function() load) async {
    _status[set] = const DataStatus(LoadState.loading);
    _notify();
    try {
      await load();
      _status[set] = const DataStatus(LoadState.ready);
    } on ApiException catch (e) {
      if (e.kind == ApiErrorKind.unauthorized) {
        _expired = true;
        _client.token = null;
        await _sessions.clear();
      }
      _status[set] = DataStatus(LoadState.error, e.userMessage);
    } on FormatException catch (e) {
      _status[set] = DataStatus(LoadState.error, 'Unexpected data: ${e.message}');
    } catch (e) {
      _status[set] = DataStatus(LoadState.error, 'Could not load: $e');
    }
    _notify();
  }

  @override
  Future<void> refreshAll() async {
    if (_client.token == null) return;
    await _run(DataSet.companies, _loadCompanies);
    if (_expired) return;
    await Future.wait(<Future<void>>[
      _run(DataSet.profile, () async => _profile = profileFrom(await _api.me())),
      _run(DataSet.ledgers, _loadLedgers),
      _run(DataSet.bills, _loadBills),
      _run(DataSet.vouchers, _loadVouchers),
      _run(DataSet.items, _loadItems),
      _run(DataSet.stock, _loadStock),
      _run(DataSet.activity, _loadActivity),
      _run(DataSet.notifications, _loadNotifs),
      _run(DataSet.alerts, _loadAlerts),
      if (_user?.isAdmin ?? false) _run(DataSet.team, _loadTeam),
    ]);
    _rebuildParties();
    _notify();
  }

  @override
  Future<void> refreshActivity() => _run(DataSet.activity, _loadActivity);

  @override
  Future<void> refreshNotifications() =>
      _run(DataSet.notifications, _loadNotifs);

  Future<void> _loadCompanies() async {
    final List<Object?> r = await Future.wait(<Future<Object?>>[
      _api.companiesSelected(),
      _api.companyActive(),
    ]);
    _companies = rows(r[0]).map(companyFrom).toList();
    final Object? a = r[1];
    _active = a is Map && a['company_guid'] is String
        ? a['company_guid'] as String
        : null;
    if (_active != null && !_companies.any((Company c) => c.id == _active)) {
      _companies = <Company>[
        ..._companies,
        Company(_active!, _active!, 'Active company'),
      ];
    }
    await Future.wait(<Future<void>>[
      for (final Company c in _companies) _loadSync(c.id),
    ]);
  }

  Future<void> _loadSync(String guid) async {
    try {
      _sync[guid] = syncFrom(await _api.syncStatus(guid));
    } on ApiException catch (e) {
      if (e.kind == ApiErrorKind.unauthorized) rethrow;
    }
  }

  Future<void> _loadLedgers() async {
    _ledgers = rows(await _api.ledgers()).map(ledgerFrom).toList();
  }

  /// `GET /bill` returns every company of the admin and is not limited to a
  /// USER's ledgers, so both filters are applied here.
  Future<void> _loadBills() async {
    final List<Map<String, Object?>> all = rows(await _api.bills());
    final List<Bill> recv = <Bill>[], pay = <Bill>[];
    for (final Map<String, Object?> m in all) {
      if (_active == null || str(m['company_guid']) != _active) continue;
      final Bill? b = billFrom(m, today);
      if (b == null) continue;
      (b.kind == 'pay' ? pay : recv).add(b);
    }
    int byDue(Bill a, Bill b) => (a.dueDate ?? DateTime(9999)).compareTo(
      b.dueDate ?? DateTime(9999),
    );
    _recv = recv..sort(byDue);
    _pay = pay..sort(byDue);
    _serverRecv = _serverPay = null;
    if ((_user?.isAdmin ?? false) && _active != null) {
      final Object? s = await _api.dashboardSummary(_active!);
      if (s is Map) {
        _serverRecv = toNum(s['receivables']);
        _serverPay = toNum(s['payables']);
      }
    }
  }

  /// The complete voucher history of the active company (no year / month
  /// filter), page by page until the server says there is no more. The
  /// server already limits rows to the active company and, for a USER, to
  /// the allowed vouchers. Soft-deleted rows (`is_active=false`) are dropped,
  /// duplicates (rows shifting between pages) are removed by GUID, and the
  /// server order (newest first) is kept.
  ///
  /// The list is only marked complete when every row of `meta.total` was
  /// received; otherwise month totals show `—` instead of a partial sum.
  Future<void> _loadVouchers() async {
    final List<Voucher> out = <Voucher>[];
    final Set<String> seen = <String>{};
    int page = 1;
    int? expected;
    bool complete = true;
    while (true) {
      final Object? body = await _api.vouchersPaged(page: page);
      final List<Map<String, Object?>> rs = rows(body);
      final Object? meta = body is Map ? body['meta'] : null;
      if (meta is Map && meta['total'] is num && expected == null) {
        expected = (meta['total']! as num).toInt();
      }
      int fresh = 0;
      for (final Map<String, Object?> m in rs) {
        final String g = str(m['voucher_guid']);
        if (g.isNotEmpty && !seen.add(g)) continue; // duplicate
        fresh++;
        final Voucher? v = voucherFrom(m);
        if (v != null) out.add(v);
      }
      final bool more = meta is Map && meta['hasMore'] == true;
      if (!more) break;
      if (rs.isEmpty || fresh == 0) {
        // Server claims more but sends nothing new: stop, never loop.
        complete = false;
        break;
      }
      page++;
    }
    if (expected != null && seen.length < expected) complete = false;
    _vouchers = out;
    _vouchersComplete = complete;
  }

  @override
  bool get vouchersComplete => _vouchersComplete;

  Future<void> _loadItems() async {
    _items = rows(await _api.inventoryMobile(), 'items').map(itemFrom).toList();
  }

  Future<void> _loadStock() async {
    _stock = rows(await _api.inventory()).map(stockFrom).toList();
  }

  Future<void> _loadActivity() async {
    if (_active == null) {
      _acts = const <Act>[];
      return;
    }
    final DateTime now = _clock();
    _acts = rows(
      await _api.queueActivity(_active!),
    ).map((Map<String, Object?> m) => actFrom(m, now)).toList();
  }

  Future<void> _loadNotifs() async {
    final DateTime now = _clock();
    _notifs = rows(
      await _api.notifications(),
      'notifications',
    ).map((Map<String, Object?> m) => notifFrom(m, now)).toList();
  }

  Future<void> _loadAlerts() async {
    final Object? b = await _api.notificationConfig();
    final Object? c = b is Map ? b['config'] : null;
    _alerts = c is Map
        ? <String, bool>{
            for (final MapEntry<Object?, Object?> e in c.entries)
              '${e.key}': e.value == true,
          }
        : null;
  }

  Future<void> _loadTeam() async {
    _team = rows(await _api.users()).map(memberFrom).toList();
  }

  /// Parties = every ledger `/ledger` returns for the active company (and,
  /// for a USER, only the permitted ones). Customer / supplier comes only
  /// from the Tally group; all other ledgers are `o`. Balance = pending
  /// bills: customer r − p, supplier p − r, other r − p (signed: positive =
  /// they owe you).
  void _rebuildParties() {
    final Map<String, num> recvBy = <String, num>{}, payBy = <String, num>{};
    String key(Bill b) => b.ledgerGuid ?? b.party;
    for (final Bill b in _recv) {
      recvBy[key(b)] = (recvBy[key(b)] ?? 0) + b.amt;
    }
    for (final Bill b in _pay) {
      payBy[key(b)] = (payBy[key(b)] ?? 0) + b.amt;
    }
    final List<Party> out = <Party>[];
    final Set<String> seen = <String>{};
    for (final LedgerRow l in _ledgers) {
      if (l.guid.isNotEmpty && seen.contains(l.guid)) continue; // duplicate
      final num r = recvBy[l.guid] ?? recvBy[l.name] ?? 0;
      final num p = payBy[l.guid] ?? payBy[l.name] ?? 0;
      final String t = partyTypeOf(l.group);
      seen.add(l.guid);
      seen.add(l.name);
      out.add(
        Party(
          l.name,
          t,
          '',
          paise(t == 's' ? p - r : r - p),
          guid: l.guid,
          group: l.group,
          email: l.email,
          phone: l.phone,
          opening: l.opening,
          closing: l.closing,
          lastDate: l.lastDate,
        ),
      );
    }
    _parties = out;
    // A USER only sees permitted ledgers; keep their bills only.
    if (!(_user?.isAdmin ?? true)) {
      bool ok(Bill b) =>
          seen.contains(b.ledgerGuid ?? '') || seen.contains(b.party);
      _recv = _recv.where(ok).toList();
      _pay = _pay.where(ok).toList();
    }
  }

  // ---------------------------------------------------------- snapshots
  @override
  List<Company> companies() => _companies;
  @override
  String? get activeCompanyId => _active;
  @override
  SyncInfo? syncInfo(String companyId) => _sync[companyId];

  @override
  Future<void> setActiveCompany(String id) async {
    await _api.setActiveCompany(id);
    _active = id;
    _partyDetail.clear();
    _voucherLines.clear();
    await refreshAll();
  }

  @override
  List<Voucher> vouchers() => _vouchers;
  @override
  List<Bill> receivables() => _recv;
  @override
  List<Bill> payables() => _pay;

  @override
  OutstandingSummary outstanding(bool recv) => summarise(
    recv ? _recv : _pay,
    today,
    serverTotal: recv ? _serverRecv : _serverPay,
  );

  @override
  MonthTotals monthTotals() =>
      computeMonth(_vouchers, today, complete: _vouchersComplete);

  @override
  List<Party> parties() => _parties;
  @override
  List<Item> items() => _items;
  @override
  List<StockRow> stockRows() => _stock;

  @override
  List<BillLine> billLines(String billNo) =>
      <Bill>[..._recv, ..._pay]
          .where((Bill b) => b.key == billNo || b.no == billNo)
          .firstOrNull
          ?.lines ??
      const <BillLine>[];

  @override
  List<Opt> ledgers() => <Opt>[
    for (final LedgerRow l in _ledgers) Opt(l.name, l.group),
  ];

  @override
  List<Opt> accounts() => <Opt>[
    for (final LedgerRow l in _ledgers)
      if (isCashOrBank(l.group)) Opt(l.name, l.group),
  ];

  @override
  List<Notif> notifications() => _notifs;
  @override
  List<Act> activity() => _acts;
  @override
  List<Member> team() => _team;
  @override
  List<Workspace> workspaces() => kWorkspaces;
  @override
  List<Report> reports() => kReports;

  /// Plans and prices live in the external licence system — no endpoint.
  @override
  List<Plan> plans() => const <Plan>[];
  @override
  List<Faq> faqs() => kFaqs;

  @override
  Map<String, SumCard> moneyCards() {
    final MonthTotals m = monthTotals();
    final OutstandingSummary r = outstanding(true), p = outstanding(false);
    final String month = monthYear(today);
    final bool ok = status(DataSet.vouchers).state == LoadState.ready &&
        _vouchersComplete;
    final bool billsOk = status(DataSet.bills).state == LoadState.ready;
    return <String, SumCard>{
      'toGet': kSums['toGet']!.withValue(billsOk ? r.total : null),
      'toGive': kSums['toGive']!.withValue(billsOk ? p.total : null),
      'mIn': kSums['mIn']!.withValue(ok ? (m.amount['receipt'] ?? 0) : null, month),
      'mOut': kSums['mOut']!.withValue(ok ? (m.amount['payment'] ?? 0) : null, month),
      'sales': kSums['sales']!.withValue(ok ? (m.amount['sales'] ?? 0) : null, month),
      'purch': kSums['purch']!.withValue(ok ? (m.amount['purchase'] ?? 0) : null, month),
      // Cash / bank balances need Dr/Cr from the server (not sent).
      'cash': kSums['cash']!.withValue(null, 'Not available from server'),
      'bank': kSums['bank']!.withValue(null, 'Not available from server'),
    };
  }

  // ---------------------------------------------------------------- alerts
  @override
  Map<String, bool>? alertConfig() => _alerts;

  @override
  Future<void> saveAlert(String key, bool on) async {
    final Object? b = await _api.saveNotificationConfig(<String, bool>{key: on});
    final Object? c = b is Map ? b['config'] : null;
    if (c is Map) {
      _alerts = <String, bool>{
        for (final MapEntry<Object?, Object?> e in c.entries)
          '${e.key}': e.value == true,
      };
    }
    _notify();
  }

  // --------------------------------------------------- detail on demand
  @override
  PartyDetail? partyDetail(String partyKey) => _partyDetail[partyKey];

  @override
  Future<void> loadPartyDetail(Party p) async {
    final String? g = p.guid;
    if (g == null || g.isEmpty) return;
    await _run(DataSet.party, () async {
      final List<Object?> r = await Future.wait(<Future<Object?>>[
        _api.ledgerVouchers(g),
        _api.ledgerItems(g),
        _api.ledgerBills(g),
      ]);
      final List<Voucher> entries = rows(r[0])
          .map((Map<String, Object?> m) => ledgerVoucherFrom(m, p.name))
          .toList()
        ..sort(
          (Voucher a, Voucher b) =>
              (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)),
        );
      _partyDetail[g] = PartyDetail(
        entries: entries,
        items: <BillLine>[
          for (final Map<String, Object?> m in rows(r[1]))
            BillLine(
              str(m['item_name']),
              '',
              str(m['total_qty']),
              dateOnly(m['last_date']) == null
                  ? ''
                  : 'last ${dmy(dateOnly(m['last_date']))}',
              toNum(m['total_amount']) ?? 0,
            ),
        ],
        bills: rows(r[2])
            .map((Map<String, Object?> m) => billFrom(m, today))
            .whereType<Bill>()
            .toList(),
      );
    });
  }

  @override
  List<LedgerLine>? voucherLines(String guid) => _voucherLines[guid];

  @override
  Future<void> loadVoucherLines(String guid) => _run(DataSet.voucher, () async {
    _voucherLines[guid] = ledgerLinesFrom(await _api.voucherDetail(guid));
  });

  // -------------------------------------------------------- notifications
  @override
  Future<void> markNotifRead(String id) async {
    _notifs = _notifs.map((Notif n) => n.id == id ? n.read() : n).toList();
    _notify();
    try {
      await _api.markNotificationRead(id);
    } on ApiException catch (e) {
      if (e.kind == ApiErrorKind.unauthorized) _expired = true;
      await refreshNotifications();
    }
  }

  /// No bulk endpoint exists: one request per unread alert.
  @override
  Future<void> markAllNotifsRead() async {
    final List<String> ids = _notifs
        .where((Notif n) => n.unread)
        .map((Notif n) => n.id)
        .toList();
    _notifs = _notifs.map((Notif n) => n.read()).toList();
    _notify();
    for (final String id in ids) {
      try {
        await _api.markNotificationRead(id);
      } on ApiException {
        await refreshNotifications();
        return;
      }
    }
  }

  // --------------------------------------------------------------- entries
  @override
  String? entryBlocker(EntryDraft d) {
    if (d.type == 'purchase') {
      return 'Purchase cannot be sent yet: the server records the supplier '
          'on the debit side (reversed). Saved entries would be wrong in Tally.';
    }
    if (_active == null) return 'No active company on the server.';
    return null;
  }

  @override
  Future<SubmitResult> submitEntry(EntryDraft d) async {
    final String? block = entryBlocker(d);
    if (block != null) return SubmitResult(ok: false, message: block);
    try {
      final Object? body = switch (d.type) {
        'sales' => await _api.createSalesPurchase(salesBody(d)),
        'receipt' => await _api.createReceipt(receiptBody(d)),
        'payment' => await _api.createPayment(paymentBody(d)),
        'journal' => await _api.createJournal(journalBody(d)),
        _ => throw ApiException(
          ApiErrorKind.badRequest,
          'Unsupported entry type ${d.type}',
        ),
      };
      final SubmitResult r = submitResultFrom(body);
      unawaited(refreshActivity());
      return r;
    } on ApiException catch (e) {
      if (e.kind == ApiErrorKind.unauthorized) {
        _expired = true;
        _notify();
      }
      return SubmitResult(ok: false, message: e.userMessage);
    }
  }

  @override
  Future<bool> pushEntry(Act entry, {Duration delay = Duration.zero}) async =>
      false;
}

// ----------------------------------------------------- request bodies

String? _opt(String s) => s.trim().isEmpty ? null : s.trim();

Map<String, Object?> _clean(Map<String, Object?> m) =>
    <String, Object?>{
      for (final MapEntry<String, Object?> e in m.entries)
        if (e.value != null) e.key: e.value,
    };

/// Sales body (`POST /api/mobile-voucher-command/create`). GST is split
/// equally into CGST / SGST because the endpoint has no IGST field.
Map<String, Object?> salesBody(EntryDraft d) {
  num sub = 0, tax = 0;
  final List<Map<String, Object?>> items = <Map<String, Object?>>[];
  for (final Line l in d.lines) {
    final num amount = paise(l.rate * l.qty);
    final num gst = paise(amount * l.gst / 100);
    sub += amount;
    tax += gst;
    items.add(
      _clean(<String, Object?>{
        'name': l.name,
        'item_guid': l.guid,
        'qty': l.qty,
        'unit': l.unit,
        'rate': l.rate,
        'gst': l.gst,
        'hsn': l.hsn,
        'amount': amount,
        'gst_amount': gst,
      }),
    );
  }
  sub = paise(sub);
  tax = paise(tax);
  final num cgst = paise(tax / 2);
  final num sgst = paise(tax - cgst);
  final num total = paise(sub + tax);
  final num got = paise(d.amount);
  return _clean(<String, Object?>{
    'voucher_type': 'Sales',
    'voucher_date': d.date,
    'voucher_no': _opt(d.no),
    'party_name': d.party,
    'due_date': _opt(d.due),
    'narration': _opt(d.note),
    'items': items,
    'summary': <String, Object?>{
      'subtotal': sub,
      'discount': 0,
      'cgst': cgst,
      'sgst': sgst,
      'total_amount': total,
    },
    'payment': <String, Object?>{
      'payment_mode': d.mode,
      'amount_received': got,
      'balance_due': paise(total - got > 0 ? total - got : 0),
    },
  });
}

/// Receipt body (`…/receipt/create`). The reference / UTR goes to the field
/// that matches the payment mode.
Map<String, Object?> receiptBody(EntryDraft d) {
  final String? utr = _opt(d.utr);
  return _clean(<String, Object?>{
    'voucher_date': d.date,
    'voucher_no': _opt(d.no),
    'party_name': d.party,
    'amount_received': paise(d.amount),
    'reference_no': _opt(d.ref),
    'narration': _opt(d.note),
    'payment': _clean(<String, Object?>{
      'payment_mode': d.mode,
      'deposit_account': _opt(d.account),
      if (d.mode != 'cash') 'bank_name': _opt(d.bank),
      if (d.mode == 'upi') 'upi_ref': utr,
      if (d.mode == 'cheque') 'cheque_number': utr,
      if (d.mode == 'bank' || d.mode == 'other') 'other_ref': utr,
    }),
  });
}

/// Payment body (`…/payment/create`) — field names differ from Receipt.
Map<String, Object?> paymentBody(EntryDraft d) => _clean(<String, Object?>{
  'voucher_date': d.date,
  'voucher_no': _opt(d.no),
  'party_name': d.party,
  'amount_paid': paise(d.amount),
  'reference_no': _opt(d.ref),
  'narration': _opt(d.note),
  'payment': _clean(<String, Object?>{
    'payment_mode': d.mode,
    'bank_account': _opt(d.account),
    if (d.mode != 'cash') 'transaction_instrument_no': _opt(d.utr),
    if (d.mode != 'cash') 'remarks': _opt(d.bank),
  }),
});

/// Journal body (`…/journal/create`): Dr → is_debit true, Cr → false.
Map<String, Object?> journalBody(EntryDraft d) => _clean(<String, Object?>{
  'voucher_date': d.date,
  'voucher_no': _opt(d.no),
  'narration': _opt(d.note),
  'ledger_entries': <Map<String, Object?>>[
    for (final JLine j in d.journal)
      <String, Object?>{
        'ledger_name': j.name,
        'amount': paise(j.amt),
        'is_debit': j.side == 'Dr',
      },
  ],
});
