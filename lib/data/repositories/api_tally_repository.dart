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
import '../../core/storage/snapshot_cache.dart';
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
  static const String item = 'item';
  static const String voucher = 'voucher';
}

class ApiTallyRepository extends TallyRepository {
  ApiTallyRepository({
    ApiClient? client,
    SessionStore? sessions,
    SnapshotCache? cache,
    DateTime Function()? clock,
  }) : _client = client ?? ApiClient(),
       _sessions = sessions ?? SecureSessionStore(),
       _cache = cache ?? FileSnapshotCache(),
       _clock = clock ?? DateTime.now {
    _api = TallyApi(_client);
  }

  final ApiClient _client;
  final SessionStore _sessions;
  final SnapshotCache _cache;
  final DateTime Function() _clock;
  late final TallyApi _api;

  /// A full reload finished less than this long ago is not repeated unless
  /// forced (explicit refresh / pull-to-refresh force it).
  static const Duration kFreshFor = Duration(seconds: 30);

  /// Detail screens reuse data loaded less than this long ago.
  static const Duration kDetailFreshFor = Duration(seconds: 60);

  AuthUser? _user;
  Profile? _profile;
  bool _expired = false;

  List<Company> _companies = const <Company>[];
  String? _active;
  final Map<String, SyncInfo> _sync = <String, SyncInfo>{};

  List<LedgerRow> _ledgers = const <LedgerRow>[];

  /// Every pending bill of the active company as the server sent it…
  List<Bill> _recvAll = const <Bill>[], _payAll = const <Bill>[];

  /// …and the bills this user may see (USER: permitted ledgers only).
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
  final Map<String, ItemDetail> _itemDetail = <String, ItemDetail>{};
  final Map<String, List<LedgerLine>> _voucherLines =
      <String, List<LedgerLine>>{};
  final Map<String, DataStatus> _status = <String, DataStatus>{};

  /// Last good raw payload per data set (what the snapshot cache stores).
  final Map<String, Object?> _payloads = <String, Object?>{};

  /// Sets that hold real data (from the server or the snapshot cache).
  final Set<String> _loaded = <String>{};

  /// One in-flight load per key: concurrent callers share it.
  final Map<String, Future<void>> _inflight = <String, Future<void>>{};
  final Map<String, DateTime> _detailAt = <String, DateTime>{};
  Future<void>? _refreshing;
  DateTime? _lastFull;
  bool _disposed = false;

  static const List<String> _order = <String>[
    DataSet.companies,
    DataSet.profile,
    DataSet.ledgers,
    DataSet.bills,
    DataSet.vouchers,
    DataSet.items,
    DataSet.stock,
    DataSet.activity,
    DataSet.notifications,
    DataSet.alerts,
    DataSet.team,
  ];

  String get _cacheKey => 'u${_user?.id ?? 0}';

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
    if (_user != null && _user!.id != r.user.id) _clearData();
    _client.token = r.token;
    _user = r.user;
    _expired = false;
    await _sessions.write(r.token, r.user);
    await _hydrate();
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
    await _hydrate();
    return true;
  }

  @override
  Future<void> logout() async {
    final String key = _cacheKey;
    _client.token = null;
    _user = null;
    _profile = null;
    _expired = false;
    _clearData();
    _status.clear();
    _lastFull = null;
    await _sessions.clear();
    // Accounting data must not stay on the phone after logout.
    await _cache.clear(key);
    _notify();
  }

  /// Drops every loaded data set (logout, other user, company switch).
  void _clearData({bool keepCompanies = false}) {
    if (!keepCompanies) {
      _companies = const <Company>[];
      _active = null;
      _sync.clear();
    }
    _ledgers = const <LedgerRow>[];
    _recvAll = _payAll = _recv = _pay = const <Bill>[];
    _serverRecv = _serverPay = null;
    _parties = const <Party>[];
    _vouchers = const <Voucher>[];
    _vouchersComplete = true;
    _items = const <Item>[];
    _stock = const <StockRow>[];
    _acts = const <Act>[];
    _notifs = const <Notif>[];
    _team = const <Member>[];
    _alerts = null;
    _partyDetail.clear();
    _itemDetail.clear();
    _voucherLines.clear();
    _detailAt.clear();
    _payloads.removeWhere(
      (String k, _) => !(keepCompanies && k == DataSet.companies),
    );
    _loaded.removeWhere(
      (String k) => !(keepCompanies && k == DataSet.companies),
    );
  }

  @override
  Future<void> sendResetCode(String email) async {
    await _api.sendOtp(email.trim());
  }

  // ------------------------------------------------------- snapshot cache

  /// Shows the last saved real data at once (before the network answers).
  Future<void> _hydrate() async {
    final Map<String, Object?>? c = await _cache.read(_cacheKey);
    final Object? sets = c?['sets'];
    if (sets is! Map) return;
    for (final String set in _order) {
      final Object? payload = sets[set];
      if (payload == null || _loaded.contains(set)) continue;
      try {
        _apply(set, payload);
        _payloads[set] = payload;
        _loaded.add(set);
      } catch (_) {
        // A corrupt entry is skipped; the next load replaces it.
      }
    }
    _rebuild();
    _notify();
  }

  Future<void> _persist() async {
    if (_user == null || _payloads.isEmpty) return;
    await _cache.write(_cacheKey, <String, Object?>{
      'saved': _clock().toIso8601String(),
      'sets': Map<String, Object?>.of(_payloads),
    });
  }

  // ------------------------------------------------------------ loading
  @override
  DataStatus status(String set) => _status[set] ?? DataStatus.idle;

  @override
  bool hasData(String set) => _loaded.contains(set);

  @override
  String? lastError() {
    for (final String set in _order) {
      final DataStatus s = status(set);
      if (s.failed) return s.message;
    }
    return null;
  }

  /// Runs [body] once per [key] at a time; a second caller gets the same
  /// future instead of a duplicate request.
  Future<void> _once(String key, Future<void> Function() body) {
    final Future<void>? running = _inflight[key];
    if (running != null) return running;
    // The callback must not return the removed future: whenComplete would
    // wait on it, i.e. the load would wait on itself forever.
    final Future<void> f = body().whenComplete(() {
      _inflight.remove(key);
    });
    _inflight[key] = f;
    return f;
  }

  /// Records [set]'s status around [body]. On failure the previous data is
  /// left untouched; a 401 ends the session.
  Future<void> _track(String set, Future<void> Function() body) async {
    _status[set] = const DataStatus(LoadState.loading);
    _notify();
    try {
      await body();
      _status[set] = const DataStatus(LoadState.ready);
    } on ApiException catch (e) {
      if (e.kind == ApiErrorKind.unauthorized) {
        _expired = true;
        _client.token = null;
        await _sessions.clear();
        await _cache.clear(_cacheKey);
      }
      _status[set] = DataStatus(LoadState.error, e.userMessage);
    } on FormatException catch (e) {
      _status[set] = DataStatus(
        LoadState.error,
        'Unexpected data: ${e.message}',
      );
    } catch (e) {
      _status[set] = DataStatus(LoadState.error, 'Could not load: $e');
    }
    _notify();
  }

  /// Fetches one data set and, only when it fully succeeds, swaps it in.
  Future<void> _load(String set) => _once(
    set,
    () => _track(set, () async {
      final Object? payload = await _fetch(set);
      _apply(set, payload);
      _payloads[set] = payload;
      _loaded.add(set);
      if (set == DataSet.ledgers || set == DataSet.bills) _rebuild();
    }),
  );

  @override
  Future<void> refreshAll({bool force = false}) {
    if (_client.token == null) return Future<void>.value();
    final Future<void>? running = _refreshing;
    if (running != null) return running;
    final DateTime? last = _lastFull;
    if (!force && last != null && _clock().difference(last) < kFreshFor) {
      return Future<void>.value();
    }
    final Future<void> f = _refreshAll().whenComplete(() {
      _refreshing = null;
    });
    _refreshing = f;
    return f;
  }

  Future<void> _refreshAll() async {
    await _load(DataSet.companies);
    if (_expired) return;
    await Future.wait(<Future<void>>[
      for (final String set in _order.skip(1))
        if (set != DataSet.team || (_user?.isAdmin ?? false)) _load(set),
    ]);
    _rebuild();
    _lastFull = _clock();
    _notify();
    if (!_expired) await _persist();
  }

  @override
  Future<void> refreshActivity() async {
    await _load(DataSet.activity);
    await _persist();
  }

  @override
  Future<void> refreshNotifications() async {
    await _load(DataSet.notifications);
    await _persist();
  }

  /// Network part of a data set: the raw, JSON-serialisable payload.
  Future<Object?> _fetch(String set) async {
    switch (set) {
      case DataSet.companies:
        final List<Object?> r = await Future.wait(<Future<Object?>>[
          _api.companiesSelected(),
          _api.companyActive(),
        ]);
        final Set<String> ids = <String>{
          for (final Map<String, Object?> m in rows(r[0]))
            str(m['company_guid']),
          if (r[1] is Map && (r[1]! as Map)['company_guid'] is String)
            (r[1]! as Map)['company_guid'] as String,
        }..remove('');
        final Map<String, Object?> sync = <String, Object?>{};
        await Future.wait(<Future<void>>[
          for (final String id in ids)
            _api
                .syncStatus(id)
                .then(
                  (Object? b) => sync[id] = b,
                  onError: (Object e) {
                    if (e is ApiException &&
                        e.kind == ApiErrorKind.unauthorized) {
                      throw e;
                    }
                    return null; // sync line is optional
                  },
                ),
        ]);
        return <String, Object?>{
          'selected': r[0],
          'active': r[1],
          'sync': sync,
        };
      case DataSet.profile:
        return _api.me();
      case DataSet.ledgers:
        return _api.ledgers();
      case DataSet.bills:
        final Object? bills = await _api.bills();
        Object? summary;
        if ((_user?.isAdmin ?? false) && _active != null) {
          summary = await _api.dashboardSummary(_active!);
        }
        return <String, Object?>{'bills': bills, 'summary': summary};
      case DataSet.vouchers:
        return _fetchVouchers();
      case DataSet.items:
        return _api.inventoryMobile();
      case DataSet.stock:
        return _api.inventory();
      case DataSet.activity:
        if (_active == null) return const <Object?>[];
        return _api.queueActivity(_active!);
      case DataSet.notifications:
        return _api.notifications();
      case DataSet.alerts:
        return _api.notificationConfig();
      case DataSet.team:
        return _api.users();
    }
    throw ArgumentError(set);
  }

  /// The complete voucher history of the active company (no year / month
  /// filter), page by page until the server says there is no more. The
  /// server limits rows to the active company and, for a USER, to the
  /// allowed vouchers. Duplicates (rows shifting between pages) are removed
  /// by GUID; server order (newest first) is kept. Marked complete only when
  /// every row of `meta.total` arrived.
  Future<Map<String, Object?>> _fetchVouchers() async {
    final List<Map<String, Object?>> out = <Map<String, Object?>>[];
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
        out.add(m);
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
    return <String, Object?>{'rows': out, 'complete': complete};
  }

  /// Parses a payload into the snapshot. Each branch builds locals first and
  /// assigns at the end, so a parse error never leaves half-applied data.
  void _apply(String set, Object? payload) {
    final DateTime now = _clock();
    switch (set) {
      case DataSet.companies:
        final Map<Object?, Object?> m = payload is Map
            ? payload
            : const <Object?, Object?>{};
        List<Company> cos = rows(m['selected']).map(companyFrom).toList();
        final Object? a = m['active'];
        final String? active = a is Map && a['company_guid'] is String
            ? a['company_guid'] as String
            : null;
        if (active != null && !cos.any((Company c) => c.id == active)) {
          cos = <Company>[...cos, Company(active, active, 'Active company')];
        }
        final Object? sy = m['sync'];
        final Map<String, SyncInfo> sync = <String, SyncInfo>{
          if (sy is Map)
            for (final MapEntry<Object?, Object?> e in sy.entries)
              if (e.value != null) '${e.key}': syncFrom(e.value),
        };
        // The admin switched company elsewhere: other sets belong to the
        // previous company, so they are dropped before the new ones load.
        if (_active != null && active != _active) _clearData();
        _companies = cos;
        _active = active;
        _sync
          ..clear()
          ..addAll(sync);
      case DataSet.profile:
        _profile = profileFrom(payload);
      case DataSet.ledgers:
        _ledgers = rows(payload).map(ledgerFrom).toList();
      case DataSet.bills:
        // `GET /bill` returns every company of the admin: keep the active
        // company's pending bills only.
        final Map<Object?, Object?> m = payload is Map
            ? payload
            : const <Object?, Object?>{};
        final List<Bill> recv = <Bill>[], pay = <Bill>[];
        for (final Map<String, Object?> b in rows(m['bills'])) {
          if (_active == null || str(b['company_guid']) != _active) continue;
          final Bill? x = billFrom(b, today);
          if (x == null) continue;
          (x.kind == 'pay' ? pay : recv).add(x);
        }
        int byDue(Bill a, Bill b) => (a.dueDate ?? DateTime(9999)).compareTo(
          b.dueDate ?? DateTime(9999),
        );
        final Object? s = m['summary'];
        _recvAll = recv..sort(byDue);
        _payAll = pay..sort(byDue);
        _serverRecv = s is Map ? toNum(s['receivables']) : null;
        _serverPay = s is Map ? toNum(s['payables']) : null;
      case DataSet.vouchers:
        final Map<Object?, Object?> m = payload is Map
            ? payload
            : const <Object?, Object?>{};
        final List<Voucher> vs = <Voucher?>[
          if (m['rows'] is List)
            for (final Object? r in m['rows']! as List)
              if (r is Map) voucherFrom(r.cast<String, Object?>()),
        ].whereType<Voucher>().toList();
        _vouchers = vs;
        _vouchersComplete = m['complete'] != false;
      case DataSet.items:
        _items = rows(payload, 'items').map(itemFrom).toList();
      case DataSet.stock:
        _stock = rows(payload).map(stockFrom).toList();
      case DataSet.activity:
        _acts = rows(
          payload,
        ).map((Map<String, Object?> m) => actFrom(m, now)).toList();
      case DataSet.notifications:
        _notifs = rows(
          payload,
          'notifications',
        ).map((Map<String, Object?> m) => notifFrom(m, now)).toList();
      case DataSet.alerts:
        final Object? c = payload is Map ? payload['config'] : null;
        _alerts = c is Map
            ? <String, bool>{
                for (final MapEntry<Object?, Object?> e in c.entries)
                  '${e.key}': e.value == true,
              }
            : null;
      case DataSet.team:
        _team = rows(payload).map(memberFrom).toList();
    }
  }

  @override
  bool get vouchersComplete => _vouchersComplete;

  /// Parties and visible bills, derived from ledgers + bills.
  ///
  /// Parties = every ledger `/ledger` returns for the active company (USER:
  /// permitted ones). Customer / supplier comes only from the Tally group;
  /// other ledgers are `o`. Balance = pending bills: customer r − p,
  /// supplier p − r, other r − p (positive = they owe you).
  ///
  /// `/bill` is not limited to a USER's ledgers, so a USER only sees bills
  /// of ledgers `/ledger` returned — none until ledgers are known.
  void _rebuild() {
    final Set<String> seen = <String>{};
    for (final LedgerRow l in _ledgers) {
      seen.add(l.guid);
      seen.add(l.name);
    }
    final bool admin = _user?.isAdmin ?? false;
    bool ok(Bill b) =>
        admin || seen.contains(b.ledgerGuid ?? '') || seen.contains(b.party);
    _recv = _recvAll.where(ok).toList();
    _pay = _payAll.where(ok).toList();

    final Map<String, num> recvBy = <String, num>{}, payBy = <String, num>{};
    String key(Bill b) => b.ledgerGuid ?? b.party;
    for (final Bill b in _recv) {
      recvBy[key(b)] = (recvBy[key(b)] ?? 0) + b.amt;
    }
    for (final Bill b in _pay) {
      payBy[key(b)] = (payBy[key(b)] ?? 0) + b.amt;
    }
    final List<Party> out = <Party>[];
    final Set<String> done = <String>{};
    for (final LedgerRow l in _ledgers) {
      if (l.guid.isNotEmpty && !done.add(l.guid)) continue; // duplicate
      final num r = recvBy[l.guid] ?? recvBy[l.name] ?? 0;
      final num p = payBy[l.guid] ?? payBy[l.name] ?? 0;
      final String t = partyTypeOf(l.group);
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
    // Another company's figures must never show under the new name.
    _clearData(keepCompanies: true);
    _active = id;
    await _cache.clear(_cacheKey);
    _notify();
    await refreshAll(force: true);
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
    // Last good data stays on screen during a refresh (stale-while-refresh).
    final bool ok = hasData(DataSet.vouchers) && _vouchersComplete;
    final bool billsOk = hasData(DataSet.bills);
    return <String, SumCard>{
      'toGet': kSums['toGet']!.withValue(billsOk ? r.total : null),
      'toGive': kSums['toGive']!.withValue(billsOk ? p.total : null),
      'mIn': kSums['mIn']!.withValue(
        ok ? (m.amount['receipt'] ?? 0) : null,
        month,
      ),
      'mOut': kSums['mOut']!.withValue(
        ok ? (m.amount['payment'] ?? 0) : null,
        month,
      ),
      'sales': kSums['sales']!.withValue(
        ok ? (m.amount['sales'] ?? 0) : null,
        month,
      ),
      'purch': kSums['purch']!.withValue(
        ok ? (m.amount['purchase'] ?? 0) : null,
        month,
      ),
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
    final Object? b = await _api.saveNotificationConfig(<String, bool>{
      key: on,
    });
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

  bool _fresh(String key, bool force) {
    final DateTime? at = _detailAt[key];
    return !force && at != null && _clock().difference(at) < kDetailFreshFor;
  }

  @override
  Future<void> loadPartyDetail(Party p, {bool force = false}) async {
    final String? g = p.guid;
    if (g == null || g.isEmpty) return;
    if (_fresh('party:$g', force)) return;
    await _once(
      'party:$g',
      () => _track(DataSet.party, () async {
        final List<Object?> r = await Future.wait(<Future<Object?>>[
          _api.ledgerVouchers(g),
          _api.ledgerItems(g),
          _api.ledgerBills(g),
        ]);
        final List<Voucher> entries =
            rows(r[0])
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
        _detailAt['party:$g'] = _clock();
      }),
    );
  }

  @override
  ItemDetail? itemDetail(String itemName) => _itemDetail[itemName];

  /// Customers / suppliers of one item (`/ledger-items/item/:name/parties`,
  /// `type=Sales` and `type=Purchase`).
  @override
  Future<void> loadItemDetail(Item it, {bool force = false}) async {
    final String n = it.name;
    if (n.isEmpty || _fresh('item:$n', force)) return;
    await _once(
      'item:$n',
      () => _track(DataSet.item, () async {
        final List<Object?> r = await Future.wait(<Future<Object?>>[
          _api.itemParties(n, 'Sales'),
          _api.itemParties(n, 'Purchase'),
        ]);
        _itemDetail[n] = ItemDetail(
          customers: rows(r[0]).map(itemPartyFrom).toList(),
          suppliers: rows(r[1]).map(itemPartyFrom).toList(),
        );
        _detailAt['item:$n'] = _clock();
      }),
    );
  }

  @override
  List<LedgerLine>? voucherLines(String guid) => _voucherLines[guid];

  /// Ledger lines of a synced voucher do not change — loaded once.
  @override
  Future<void> loadVoucherLines(String guid) async {
    if (_voucherLines.containsKey(guid)) return;
    await _once(
      'voucher:$guid',
      () => _track(DataSet.voucher, () async {
        _voucherLines[guid] = ledgerLinesFrom(await _api.voucherDetail(guid));
      }),
    );
  }

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

Map<String, Object?> _clean(Map<String, Object?> m) => <String, Object?>{
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
