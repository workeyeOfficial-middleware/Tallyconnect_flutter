// Real backend implementation of [TallyRepository]
// (https://tallyconnect-wlup.onrender.com, see BACKEND_API_REFERENCE.md).
//
// Loads every data set the screens need, keeps the last good snapshot,
// records a [DataStatus] per set (loading / ready / error) and combines
// endpoints here — never in the UI.
library;

import 'dart:async';
import 'dart:convert';

import '../../core/network/api_client.dart';
import '../../core/storage/session_store.dart';
import '../../core/storage/snapshot_cache.dart';
import '../../core/utils/format.dart';
import '../accounting.dart';
import '../api/adapters.dart';
import '../api/set_parsers.dart';
import '../api/tally_api.dart';
import '../mock/mock_data.dart';
import '../models/models.dart';
import 'tally_repository.dart';
import 'team_admin.dart';
import 'voucher_pager.dart';

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

  /// Settled bills (pending 0), same visibility rule.
  List<Bill> _sRecvAll = const <Bill>[], _sPayAll = const <Bill>[];
  List<Bill> _sRecv = const <Bill>[], _sPay = const <Bill>[];
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

  /// Sets that hold real data (from the server or the snapshot cache).
  final Set<String> _loaded = <String>{};

  /// One in-flight load per key: concurrent callers share it.
  final Map<String, Future<void>> _inflight = <String, Future<void>>{};
  final Map<String, DateTime> _detailAt = <String, DateTime>{};
  Future<void>? _refreshing;
  DateTime? _lastFull;
  bool _disposed = false;

  /// Bumped whenever a data set changes (lets the UI cache derived values).
  int _version = 0;

  /// Voucher lists by filter (most recently used last; at most 10 kept).
  final Map<String, VoucherPager> _pagers = <String, VoucherPager>{};

  /// All-history item sales / purchase totals, streamed when an item's
  /// detail opens.
  HistoryTotals? _history;

  /// Exact voucher counts per period, and periods to recount after a
  /// refresh (old counts stay on screen until the new ones arrive).
  final Map<String, VoucherCounts> _counts = <String, VoucherCounts>{};
  final Set<String> _countsStale = <String>{};
  VoucherCounts? _monthCounts;
  int _monthCountsV = -1;

  MonthTotals? _monthMemo;
  int _monthMemoV = -1;
  final Map<bool, (String, OutstandingSummary)> _outMemo =
      <bool, (String, OutstandingSummary)>{};

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

  /// Loaded at startup: what Home and the tab screens need. Items, stock,
  /// team and (for an admin) ledgers load when a screen first needs them;
  /// the voucher history is paged per list. A USER's ledgers load first
  /// because bills are filtered to the parties they may see.
  List<String> get _startup => <String>[
    DataSet.profile,
    if (!(_user?.isAdmin ?? false)) DataSet.ledgers,
    DataSet.bills,
    DataSet.vouchers,
    DataSet.activity,
    DataSet.notifications,
    DataSet.alerts,
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
  int get version => _version;

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
    _sRecvAll = _sPayAll = _sRecv = _sPay = const <Bill>[];
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
    _dropPagers();
    _history = null;
    _counts.clear();
    _countsStale.clear();
    _loaded.removeWhere(
      (String k) => !(keepCompanies && k == DataSet.companies),
    );
    _version++;
  }

  void _dropPagers() {
    for (final VoucherPager p in _pagers.values) {
      p.detach();
    }
    _pagers.clear();
  }

  @override
  Future<void> sendResetCode(String email) async {
    await _api.sendOtp(email.trim());
  }

  @override
  Future<void> resetPassword(String email, String code, String password) async {
    await _api.verifyOtp(email.trim(), code.trim(), password);
  }

  // ------------------------------------------------------- snapshot cache

  /// Shows the last saved real data at once (before the network answers).
  /// Each set is a separate file of server JSON, parsed off the UI thread.
  Future<void> _hydrate() async {
    for (final String set in _order) {
      if (_loaded.contains(set)) continue;
      final String? raw = await _cache.read(_cacheKey, set);
      if (raw == null) continue;
      try {
        _applyParsed(set, await parseSet(_in(set, raw)));
        _loaded.add(set);
      } catch (_) {
        // A corrupt entry is skipped; the next load replaces it.
      }
    }
    _rebuild();
    _version++;
    _notify();
  }

  ParseIn _in(String set, String raw) =>
      ParseIn(set, raw, _active, today, _clock());

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
      if (e.kind == ApiErrorKind.unauthorized) await _endSession();
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

  Future<void> _endSession() async {
    _expired = true;
    _client.token = null;
    await _sessions.clear();
    await _cache.clear(_cacheKey);
  }

  /// Fetches one data set and, only when it fully succeeds, swaps it in.
  /// The server text is parsed (in an isolate when large), written to the
  /// snapshot cache as is, and not kept in memory.
  @override
  late final TeamAdmin teamAdmin = TeamAdmin(_api, () async {
    await _load(DataSet.team);
    _notify();
  });

  Future<void> _load(String set) => _once(
    set,
    () => _track(set, () async {
      if (set == DataSet.vouchers) {
        await _loadMonth();
      } else {
        final String raw = await _fetchText(set);
        _applyParsed(set, await parseSet(_in(set, raw)));
        unawaited(_cache.write(_cacheKey, set, raw));
      }
      _loaded.add(set);
      if (set == DataSet.ledgers || set == DataSet.bills) _rebuild();
      _version++;
    }),
  );

  /// Loads [set] if it has no data yet (screens call this when they open).
  @override
  Future<void> ensure(String set) {
    if (_client.token == null || _loaded.contains(set)) {
      return Future<void>.value();
    }
    if (set == DataSet.team && !(_user?.isAdmin ?? false)) {
      return Future<void>.value();
    }
    return _load(set);
  }

  @override
  Future<void> refreshAll({bool force = false}) {
    if (_client.token == null) return Future<void>.value();
    final Future<void>? running = _refreshing;
    if (running != null) return running;
    final DateTime? last = _lastFull;
    if (!force && last != null && _clock().difference(last) < kFreshFor) {
      return Future<void>.value();
    }
    final Future<void> f = _refreshAll(force).whenComplete(() {
      _refreshing = null;
    });
    _refreshing = f;
    return f;
  }

  /// Reloads the startup sets plus every set already on screen (stale data
  /// stays visible until the fresh data replaces it). A forced refresh also
  /// restarts the voucher lists from page 1.
  Future<void> _refreshAll(bool force) async {
    // Counts are recounted when next shown (old ones stay until then).
    _countsStale.addAll(_counts.keys);
    if (force) {
      // Lists restart from page 1 now (not after the other sets reload), so
      // a list opened during a long refresh is never blanked at its end.
      _dropPagers();
      _history = null;
      _notify();
    }
    await _load(DataSet.companies);
    if (_expired) return;
    final Set<String> sets = <String>{..._startup, ..._loaded}
      ..remove(DataSet.companies);
    if (!(_user?.isAdmin ?? false)) sets.remove(DataSet.team);
    await Future.wait(<Future<void>>[for (final String s in sets) _load(s)]);
    _rebuild();
    _lastFull = _clock();
    _version++;
    _notify();
  }

  @override
  Future<void> refreshActivity() => _load(DataSet.activity);

  @override
  Future<void> refreshNotifications() => _load(DataSet.notifications);

  /// Server JSON text of one data set (small composites are encoded here).
  Future<String> _fetchText(String set) async {
    switch (set) {
      case DataSet.companies:
        // `/company/selected` only has companies with a sync-start row, so
        // a company the agent registered but has not synced yet was missing.
        // The list comes from `/company` (all of the admin's companies);
        // `/company/selected` still supplies each one's sync start month.
        final List<Object?> r = await Future.wait(<Future<Object?>>[
          _api.companiesSelected(),
          _api.companyActive(),
          _api.companiesAll(),
        ]);
        final Set<String> ids = <String>{
          for (final Map<String, Object?> m in rows(r[0]))
            str(m['company_guid']),
          for (final Map<String, Object?> m in rows(r[2]))
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
        return jsonEncode(<String, Object?>{
          'selected': r[0],
          'active': r[1],
          'all': r[2],
          'sync': sync,
        });
      case DataSet.profile:
        return _api.meText();
      case DataSet.ledgers:
        return _api.ledgersText();
      case DataSet.bills:
        final String bills = await _api.billsText();
        Object? summary;
        if ((_user?.isAdmin ?? false) && _active != null) {
          summary = await _api.dashboardSummary(_active!);
        }
        // Concatenated, not re-encoded: the bill list stays server text.
        return '{"bills":$bills,"summary":${jsonEncode(summary)}}';
      case DataSet.items:
        return _api.inventoryMobileText();
      case DataSet.stock:
        return _api.inventoryText();
      case DataSet.activity:
        if (_active == null) return '[]';
        return _api.queueActivityText(_active!);
      case DataSet.notifications:
        // Mobile alerts + the web-dashboard alerts (bill created, monthly
        // report, team, voucher updates). The web list is optional: if it
        // fails, the mobile alerts still show.
        final String nMobile = await _api.notificationsText();
        String nWeb = 'null';
        try {
          nWeb = await _api.webNotificationsText();
        } on ApiException {
          // Optional list: any failure only leaves the web alerts out (the
          // mobile request above already reports a real expired session).
        }
        return '{"mobile":$nMobile,"web":$nWeb}';
      case DataSet.alerts:
        // Mobile switches (/api/mobile/notifications/config) + web switches
        // (/users/me/notifications).
        final String aMobile = await _api.notificationConfigText();
        String aWeb = 'null';
        try {
          aWeb = await _api.webNotificationPrefsText();
        } on ApiException {
          // Optional: web switches stay unknown (shown off) on failure.
        }
        return '{"mobile":$aMobile,"web":$aWeb}';
      case DataSet.team:
        return _api.usersText();
    }
    throw ArgumentError(set);
  }

  /// The current month's vouchers (needed for the month totals on Home,
  /// Vouchers and Reports) — never the whole history. Pages of 200, each
  /// parsed off the UI thread; complete only when every row of
  /// `meta.total` arrived. Cached as the pages' own text.
  Future<void> _loadMonth() async {
    final DateTime t = today;
    final List<String> pages = <String>[];
    final List<Voucher> out = <Voucher>[];
    final Set<String> seen = <String>{};
    int page = 1;
    int? expected;
    bool complete = true;
    while (true) {
      final String raw = await _api.vouchersPagedText(
        page: page,
        limit: 200,
        year: t.year,
        month: t.month,
      );
      final VoucherPageParsed p = await parseVoucherPage(raw);
      pages.add(raw);
      expected ??= p.total;
      int fresh = 0;
      for (final String g in p.guids) {
        if (g.isEmpty || seen.add(g)) fresh++;
      }
      out.addAll(p.rows);
      if (!p.hasMore) break;
      if (p.guids.isEmpty || fresh == 0) {
        complete = false; // server claims more but sends nothing new
        break;
      }
      page++;
    }
    if (expected != null && seen.length < expected) complete = false;
    // Rows that shifted across pages appear twice: keep the first.
    final Set<String> once = <String>{};
    _vouchers = <Voucher>[
      for (final Voucher v in out)
        if ((v.guid ?? '').isEmpty || once.add(v.guid!)) v,
    ];
    _vouchersComplete = complete;
    unawaited(
      _cache.write(
        _cacheKey,
        DataSet.vouchers,
        '{"year":${t.year},"month":${t.month},"complete":$complete,'
        '"pages":[${pages.join(',')}]}',
      ),
    );
  }

  /// Puts a parsed data set into the snapshot.
  void _applyParsed(String set, Object? parsed) {
    switch (set) {
      case DataSet.companies:
        final Map<Object?, Object?> m = parsed is Map
            ? parsed
            : const <Object?, Object?>{};
        // Every company of the admin (sync status never filters the list);
        // the sync start month comes from the selected-companies rows.
        final Map<String, Map<String, Object?>> selected =
            <String, Map<String, Object?>>{
              for (final Map<String, Object?> s in rows(m['selected']))
                str(s['company_guid']): s,
            };
        final List<Map<String, Object?>> allRows = rows(m['all']);
        List<Company> cos = <Company>[
          for (final Map<String, Object?> c in allRows)
            if (str(c['company_guid']).isNotEmpty)
              companyFrom(<String, Object?>{
                ...c,
                'starting_from':
                    selected[str(c['company_guid'])]?['starting_from'],
              }),
          // Selected companies `/company` did not return (older cache) are
          // kept as before.
          for (final Map<String, Object?> s in selected.values)
            if (!allRows.any(
              (Map<String, Object?> c) =>
                  str(c['company_guid']) == str(s['company_guid']),
            ))
              companyFrom(s),
        ];
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
        if (_active != null && active != _active) {
          _clearData();
          unawaited(_cache.clear(_cacheKey));
        }
        _companies = cos;
        _active = active;
        _sync
          ..clear()
          ..addAll(sync);
      case DataSet.profile:
        _profile = parsed! as Profile;
      case DataSet.ledgers:
        _ledgers = parsed! as List<LedgerRow>;
      case DataSet.bills:
        final BillsParsed b = parsed! as BillsParsed;
        _recvAll = b.recv;
        _payAll = b.pay;
        _sRecvAll = b.settledRecv;
        _sPayAll = b.settledPay;
        _serverRecv = b.serverRecv;
        _serverPay = b.serverPay;
      case DataSet.vouchers:
        // Cached month set: only used while it is still this month.
        final MonthParsed mp = parsed! as MonthParsed;
        final DateTime t = today;
        if (mp.year != t.year || mp.month != t.month) {
          throw const FormatException('cached month is over');
        }
        _vouchers = mp.rows;
        _vouchersComplete = mp.complete;
      case DataSet.items:
        _items = parsed! as List<Item>;
      case DataSet.stock:
        _stock = parsed! as List<StockRow>;
      case DataSet.activity:
        _acts = parsed! as List<Act>;
      case DataSet.notifications:
        _notifs = parsed! as List<Notif>;
      case DataSet.alerts:
        _alerts = parsed as Map<String, bool>?;
      case DataSet.team:
        _team = parsed! as List<Member>;
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
    _sRecv = _sRecvAll.where(ok).toList();
    _sPay = _sPayAll.where(ok).toList();

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
          search: l.search,
        ),
      );
    }
    _parties = out;
  }

  // ------------------------------------------------------ voucher paging

  /// The paged list for [q] (cached: reopening a list never re-requests the
  /// pages it already has).
  @override
  VoucherPager voucherPager(VoucherQuery q) {
    final VoucherPager p =
        _pagers.remove(q.key) ?? VoucherPager(q, _fetchPage, today);
    _pagers[q.key] = p;
    while (_pagers.length > 10) {
      _pagers.remove(_pagers.keys.first)!.detach();
    }
    return p;
  }

  /// One `/voucher-entry/paged` page of 100 for a list. `month` uses the
  /// server's year / month filter; week / today read newest-first pages and
  /// the pager stops at the cut-off date.
  Future<FetchedPage> _fetchPage(int page, VoucherQuery q, DateTime t) async {
    try {
      final String raw = await _api.vouchersPagedText(
        page: page,
        year: q.period == 'month' ? t.year : null,
        month: q.period == 'month' ? t.month : null,
        type: q.serverType,
      );
      final VoucherPageParsed p = await parseVoucherPage(raw);
      return FetchedPage(p.rows, p.guids, p.hasMore);
    } on ApiException catch (e) {
      if (e.kind == ApiErrorKind.unauthorized) {
        await _endSession();
        _notify();
      }
      rethrow;
    }
  }

  // ------------------------------------------------------ voucher counts

  @override
  VoucherCounts? voucherCounts(String period) {
    if (period == 'month') {
      // The complete month set the This-month list shows (same filter).
      if (!hasData(DataSet.vouchers)) return null;
      if (_monthCounts == null || _monthCountsV != _version) {
        final DateTime t = today;
        _monthCounts = VoucherCounts.of(
          _vouchers.where((Voucher v) => voucherInPeriod(v, 'month', t)),
        )..complete = _vouchersComplete;
        _monthCountsV = _version;
      }
      return _monthCounts;
    }
    return _counts[period];
  }

  @override
  Future<void> loadVoucherCounts(String period) {
    if (period == 'month' || _client.token == null) {
      return Future<void>.value();
    }
    final VoucherCounts? have = _counts[period];
    if (have != null && have.error == null && !_countsStale.contains(period)) {
      return Future<void>.value();
    }
    return _once('counts|$period', () async {
      final VoucherCounts c;
      try {
        c = period == 'all'
            ? await _serverCounts()
            : await _periodCounts(period);
      } on ApiException catch (e) {
        if (e.kind == ApiErrorKind.unauthorized) await _endSession();
        _counts[period] = (_counts[period] ?? VoucherCounts())
          ..error = e.userMessage;
        _notify();
        return;
      } catch (e) {
        _counts[period] = (_counts[period] ?? VoucherCounts())
          ..error = 'Could not count: $e';
        _notify();
        return;
      }
      _counts[period] = c;
      _countsStale.remove(period);
      _notify();
    });
  }

  /// All history, counted by the server (`meta.total` of
  /// `/voucher-entry/paged`, one row per call — nothing is downloaded).
  /// The server's `type` filter is a loose `ILIKE '%type%'`, so each
  /// listed type is counted and the exact per-type counts are solved from
  /// them ([exactTypeCounts]); kinds are the sums of their types.
  Future<VoucherCounts> _serverCounts() async {
    Map<Object?, Object?> meta(String raw) {
      final Object? b = jsonDecode(raw);
      final Object? m = b is Map ? b['meta'] : null;
      return m is Map ? m : const <Object?, Object?>{};
    }

    int count(Map<Object?, Object?> m) =>
        m['total'] is num ? (m['total']! as num).toInt() : 0;
    num sum(Map<Object?, Object?> m) => toNum(m['totalAmount']) ?? 0;
    final Map<Object?, Object?> m0 = meta(
      await _api.vouchersPagedText(limit: 1),
    );
    final int total = count(m0);
    final num totalSum = sum(m0);
    final List<String> types = <String>[
      if (m0['types'] is List)
        for (final Object? t in m0['types']! as List<Object?>)
          if (t != null && '$t'.trim().isNotEmpty) '$t'.trim(),
    ];
    final Map<String, int> ilike = <String, int>{};
    final Map<String, num> ilikeSum = <String, num>{};
    // A few at a time, not one burst per type. Each answer carries the
    // filter's count and its amount total (`meta.totalAmount`).
    for (int i = 0; i < types.length; i += 4) {
      await Future.wait(<Future<void>>[
        for (final String t in types.skip(i).take(4))
          _api.vouchersPagedText(limit: 1, type: t).then((String raw) {
            final Map<Object?, Object?> m = meta(raw);
            ilike[t] = count(m);
            ilikeSum[t] = sum(m);
          }),
      ]);
    }
    final Map<String, int> exact = exactTypeCounts(ilike);
    final Map<String, num> exactSum = exactTypeSums(ilikeSum);
    final VoucherCounts c = VoucherCounts(
      total: total,
      type: exact,
      totalAmt: 0,
      complete: true,
    );
    // Voucher values are positive in the app (the server stores Dr / Cr
    // signs): each type's server total, as a size.
    num typedSum = 0;
    for (final MapEntry<String, num> e in exactSum.entries) {
      typedSum += e.value;
      final num v = e.value.abs();
      c.typeAmt[e.key] = v;
      c.totalAmt = c.totalAmt! + v;
      final String k = voucherKind(e.key);
      c.kindAmt[k] = (c.kindAmt[k] ?? 0) + v;
    }
    for (final String t in types) {
      c.names[t.toLowerCase()] ??= t;
    }
    int typed = 0;
    for (final MapEntry<String, int> e in exact.entries) {
      typed += e.value;
      final String k = voucherKind(e.key);
      c.kind[k] = (c.kind[k] ?? 0) + e.value;
    }
    // Vouchers with no type name are counted as other vouchers.
    if (total > typed) {
      c.kind['other'] = (c.kind['other'] ?? 0) + total - typed;
      c.type[''] = total - typed;
      final num rest = (totalSum - typedSum).abs();
      c.typeAmt[''] = rest;
      c.kindAmt['other'] = (c.kindAmt['other'] ?? 0) + rest;
      c.totalAmt = c.totalAmt! + rest;
    }
    return c;
  }

  /// Last 7 days / Today: the server cannot filter by day, so the list's own
  /// pager (same date and type rules, newest first, stops at the cut-off)
  /// is run to its end; only that period's pages are read.
  Future<VoucherCounts> _periodCounts(String period) async {
    final VoucherPager pg = VoucherPager(
      VoucherQuery(period: period),
      _fetchPage,
      today,
    );
    try {
      while (pg.hasMore && pg.error == null) {
        await pg.loadMore(minNew: 1 << 30);
      }
      if (pg.error != null) {
        throw ApiException(ApiErrorKind.server, pg.error!);
      }
      return VoucherCounts.of(pg.rows);
    } finally {
      pg.dispose();
    }
  }

  /// Server-side voucher search (`search` matches party, reference no.,
  /// type and date) — first 25 matches.
  @override
  Future<List<Voucher>> searchVouchers(String query) async {
    final String raw = await _api.vouchersPagedText(limit: 25, search: query);
    return (await parseVoucherPage(raw)).rows;
  }

  /// Finds a voucher already on the phone (this month or any loaded page).
  @override
  Voucher? voucherByKey(String key) {
    for (final Voucher v in _vouchers) {
      if (v.key == key) return v;
    }
    for (final VoucherPager p in _pagers.values) {
      for (final Voucher v in p.rows) {
        if (v.key == key) return v;
      }
    }
    return null;
  }

  @override
  HistoryTotals? get historyTotals => _history;

  /// Streams the complete voucher history once (pages of 200, parsed off
  /// the UI thread) into [HistoryTotals] without storing the rows. Only run
  /// when the user asks for all-history figures (Vouchers hub, item detail).
  @override
  Future<void> scanHistory() {
    final HistoryTotals? h0 = _history;
    if (h0 != null && (h0.running || h0.complete)) return Future<void>.value();
    return _once('history', () async {
      final HistoryTotals h = HistoryTotals()..running = true;
      _history = h;
      _notify();
      int page = 1;
      try {
        while (true) {
          final String raw = await _api.vouchersPagedText(
            page: page,
            limit: 200,
          );
          if (_history != h) return; // company changed / refreshed
          final VoucherPageParsed p = await parseVoucherPage(raw);
          h.total ??= p.total;
          final int before = h.scanned;
          h.add(FetchedPage(p.rows, p.guids, p.hasMore));
          _notify();
          if (!p.hasMore) break;
          if (p.guids.isEmpty || h.scanned == before) {
            h.error = 'The server list ended early';
            break;
          }
          page++;
        }
        h.done = true;
        if (h.total != null && h.scanned < h.total! && h.error == null) {
          h.error = 'Read ${h.scanned} of ${h.total} vouchers';
        }
      } on ApiException catch (e) {
        if (e.kind == ApiErrorKind.unauthorized) await _endSession();
        h.error = e.userMessage;
      } catch (e) {
        h.error = 'Could not read the history: $e';
      } finally {
        h.running = false;
        _notify();
      }
    });
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

  /// This month's vouchers (complete; drives the month totals).
  @override
  List<Voucher> vouchers() => _vouchers;
  @override
  List<Bill> receivables() => _recv;
  @override
  List<Bill> payables() => _pay;
  @override
  List<Bill> settledBills(bool recv) => recv ? _sRecv : _sPay;

  @override
  OutstandingSummary outstanding(bool recv) {
    // Same summary, computed once per data change / day, not per rebuild.
    final DateTime t = today;
    final List<Bill> bl = recv ? _recv : _pay;
    final String k =
        '$_version|${identityHashCode(bl)}|${t.year}-${t.month}-${t.day}';
    final (String, OutstandingSummary)? m = _outMemo[recv];
    if (m != null && m.$1 == k) return m.$2;
    final OutstandingSummary r = summarise(
      bl,
      t,
      serverTotal: recv ? _serverRecv : _serverPay,
    );
    _outMemo[recv] = (k, r);
    return r;
  }

  /// This month's totals (same calculation as before), computed once per
  /// data change instead of on every screen rebuild.
  @override
  MonthTotals monthTotals() {
    if (_monthMemoV != _version || _monthMemo == null) {
      _monthMemo = computeMonth(_vouchers, today, complete: _vouchersComplete);
      _monthMemoV = _version;
    }
    return _monthMemo!;
  }

  @override
  List<Party> parties() => _parties;
  @override
  List<Item> items() => _items;
  @override
  List<StockRow> stockRows() => _stock;

  @override
  List<String> stockGroups() => groupsOf(_items);

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
  Future<void> saveAlert(String key, bool on) =>
      saveAlerts(<String, bool>{key: on});

  /// Saves switches: plain keys → mobile config (PUT merges on the server);
  /// `web.<key>` → web preferences (PUT replaces, so the current object is
  /// read first and every key is sent). Then reloads the alert list, which
  /// the server filters by these switches.
  @override
  Future<void> saveAlerts(Map<String, bool> changes) async {
    final Map<String, bool> mobile = <String, bool>{
      for (final MapEntry<String, bool> e in changes.entries)
        if (!e.key.startsWith(kWebPref)) e.key: e.value,
    };
    final Map<String, bool> web = <String, bool>{
      for (final MapEntry<String, bool> e in changes.entries)
        if (e.key.startsWith(kWebPref))
          e.key.substring(kWebPref.length): e.value,
    };
    final Map<String, bool> next = <String, bool>{...?_alerts};
    if (mobile.isNotEmpty) {
      final Object? b = await _api.saveNotificationConfig(mobile);
      final Object? c = b is Map ? b['config'] : null;
      if (c is Map) {
        next.removeWhere((String k, bool _) => !k.startsWith(kWebPref));
        for (final MapEntry<Object?, Object?> e in c.entries) {
          next['${e.key}'] = e.value == true;
        }
      }
    }
    if (web.isNotEmpty) {
      final Object? cur = await _api.webNotificationPrefs();
      final Map<String, Object?> all = <String, Object?>{
        if (cur is Map)
          for (final MapEntry<Object?, Object?> e in cur.entries)
            '${e.key}': e.value,
        ...web,
      };
      await _api.saveWebNotificationPrefs(all);
      for (final MapEntry<String, Object?> e in all.entries) {
        next['$kWebPref${e.key}'] = e.value == true;
      }
    }
    _alerts = next;
    _notify();
    await refreshNotifications();
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
  /// Web-dashboard alerts carry `w:<id>` (own table and read route).
  Future<Object?> _markRead(String id) => id.startsWith(kWebNotif)
      ? _api.markWebNotificationRead(id.substring(kWebNotif.length))
      : _api.markNotificationRead(id);

  @override
  Future<void> markNotifRead(String id) async {
    _notifs = _notifs.map((Notif n) => n.id == id ? n.read() : n).toList();
    _notify();
    try {
      await _markRead(id);
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
        await _markRead(id);
      } on ApiException {
        await refreshNotifications();
        return;
      }
    }
  }

  // --------------------------------------------------------------- entries
  @override
  String? entryBlocker(EntryDraft d) {
    if (_active == null) return 'No active company on the server.';
    return null;
  }

  @override
  Future<SubmitResult> submitEntry(EntryDraft d) async {
    final String? block = entryBlocker(d);
    if (block != null) return SubmitResult(ok: false, message: block);
    try {
      final Object? body = switch (d.type) {
        'sales' || 'purchase' => await _api.createSalesPurchase(salesBody(d)),
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

/// Sales / Purchase body (`POST /api/mobile-voucher-command/create`). GST
/// is split equally into CGST / SGST because the endpoint has no IGST
/// field. The agent writes the sides from `voucher_type`: Sales → customer
/// Dr, stock out, Sales + GST Cr; Purchase → supplier Cr, stock in,
/// Purchase + input GST Dr.
Map<String, Object?> salesBody(EntryDraft d) {
  num sub = 0, tax = 0;
  final List<Map<String, Object?>> items = <Map<String, Object?>>[];
  for (final Line l in d.lines) {
    final num amount = paise(l.rate * l.qty);
    final num gst = paise(amount * l.gst / 100);
    sub += amount;
    tax += gst;
    // Field names are the sync agent's contract (agent.cjs:
    // processMobileVoucherCommands / buildVoucherXML): item_name, quantity,
    // rate, unit, hsn_code, gst_rate, group (group creates a new item under
    // that Tally stock group). The backend passes items[] through as is.
    items.add(
      _clean(<String, Object?>{
        'item_name': l.name,
        'item_guid': l.guid,
        'quantity': l.qty,
        'rate': l.rate,
        'unit': l.unit.trim().isEmpty ? null : l.unit,
        'hsn_code': (l.hsn ?? '').trim().isEmpty ? null : l.hsn,
        'gst_rate': l.gst,
        'group': (l.group ?? '').trim().isEmpty ? null : l.group,
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
    'voucher_type': d.type == 'purchase' ? 'Purchase' : 'Sales',
    'voucher_date': d.date,
    // Purchase without its own number: the supplier's bill number.
    'voucher_no':
        _opt(d.no) ?? (d.type == 'purchase' ? _opt(d.supplierInvoice) : null),
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
