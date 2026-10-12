// Demo data for every account: the sample data set ([MockTallyRepository])
// listed as "Demo Company" beside the account's real companies, strictly
// apart from the real data.
//
// One object stands in for the repository. Data calls go to the source being
// shown ([demoOn] → sample data, else the real backend); the session (login,
// token, logout, feedback) always belongs to the real account. The two
// sources never share state: sample data lives only in memory, is never
// written to the phone's real cache and has no server connection at all —
// so nothing made in demo mode can reach the server or Tally.
library;

import '../models/models.dart';
import 'tally_repository.dart';
import 'team_admin.dart';

/// The sample company listed beside the account's real companies. Its id
/// can never be a Tally company GUID.
const String kDemoCompanyName = 'Demo Company';
const String kDemoCompanyId = 'tc-demo-company';
const Company kDemoCompany = Company(
  kDemoCompanyId,
  kDemoCompanyName,
  'Sample data · not from Tally',
);

class DemoAwareRepository extends TallyRepository {
  DemoAwareRepository({required this.live, TallyRepository? demo})
    : demo = demo ?? MockTallyRepository() {
    live.addListener(_relay);
    this.demo.addListener(_relay);
  }

  /// The account's real data (backend + its cache).
  final TallyRepository live;

  /// Sample data (in memory only).
  final TallyRepository demo;

  bool _demoOn = false;

  /// Sample data is shown instead of the real data.
  bool get demoOn => _demoOn;

  /// Bumped on every switch so cached views are rebuilt from the new source.
  int _epoch = 0;

  void setDemo(bool on) {
    if (on == _demoOn) return;
    _demoOn = on;
    _epoch++;
    notifyListeners();
  }

  TallyRepository get _src => _demoOn ? demo : live;

  void _relay() => notifyListeners();

  @override
  void dispose() {
    live.removeListener(_relay);
    demo.removeListener(_relay);
    super.dispose();
  }

  // ----------------------------------------------------- what is shown
  @override
  bool get isRemote => _src.isRemote;
  @override
  DateTime get today => _src.today;
  @override
  int get version => (_epoch << 24) + _src.version;

  // ---------------------------------------------- session: always real
  @override
  AuthUser? get user => live.user;
  @override
  Profile? get profile => live.profile;
  @override
  bool get sessionExpired => live.sessionExpired;
  @override
  Future<AuthUser> login(String email, String password, String loginType) =>
      live.login(email, password, loginType);
  @override
  Future<bool> restoreSession() => live.restoreSession();
  @override
  Future<void> logout() => live.logout();
  @override
  Future<void> sendResetCode(String email) => live.sendResetCode(email);
  @override
  Future<void> resetPassword(String email, String code, String password) =>
      live.resetPassword(email, code, password);
  @override
  Future<int> sendFeedback(FeedbackDraft f) => live.sendFeedback(f);

  // ---------------------------------------------------------- loading
  /// The real data is always refreshed (also while demo data is shown), so
  /// the app can tell when the account's first Tally sync has arrived.
  @override
  Future<void> refreshAll({bool force = false}) => live.refreshAll(force: force);
  @override
  Future<void> refreshActivity() => _src.refreshActivity();
  @override
  Future<void> refreshNotifications() => _src.refreshNotifications();
  @override
  Future<bool> checkNewSync() => live.checkNewSync();
  @override
  DataStatus status(String set) => _src.status(set);
  @override
  bool hasData(String set) => _src.hasData(set);
  @override
  Future<void> ensure(String set) => _src.ensure(set);
  @override
  TeamAdmin? get teamAdmin => _src.teamAdmin;
  @override
  VoucherPager voucherPager(VoucherQuery q) => _src.voucherPager(q);
  @override
  Future<List<Voucher>> searchVouchers(String query) =>
      _src.searchVouchers(query);
  @override
  Voucher? voucherByKey(String key) => _src.voucherByKey(key);
  @override
  HistoryTotals? get historyTotals => _src.historyTotals;
  @override
  Future<void> scanHistory() => _src.scanHistory();
  @override
  VoucherCounts? voucherCounts(String period) => _src.voucherCounts(period);
  @override
  Future<void> loadVoucherCounts(String period) =>
      _src.loadVoucherCounts(period);
  @override
  String? lastError() => _src.lastError();

  // -------------------------------------------------------- companies
  /// Every account sees its own real companies (from the server, with its
  /// permissions) and, last, the same read-only "Demo Company". Demo never
  /// replaces, hides or changes a real company.
  @override
  List<Company> companies() => <Company>[...live.companies(), kDemoCompany];

  /// Demo: the Demo Company; else the account's active company (server).
  @override
  String? get activeCompanyId =>
      _demoOn ? kDemoCompanyId : live.activeCompanyId;

  @override
  SyncInfo? syncInfo(String companyId) =>
      companyId == kDemoCompanyId ? null : live.syncInfo(companyId);

  /// Demo Company → sample data, on this phone only (the server's active
  /// company is untouched). A real company → its real data; the server's
  /// active company changes only when a different real company is picked.
  @override
  Future<void> setActiveCompany(String id) async {
    if (id == kDemoCompanyId) {
      setDemo(true);
      return;
    }
    setDemo(false);
    if (id != live.activeCompanyId) await live.setActiveCompany(id);
  }

  // ------------------------------------------------------------- data
  @override
  List<Voucher> vouchers() => _src.vouchers();
  @override
  bool get vouchersComplete => _src.vouchersComplete;
  @override
  List<Bill> receivables() => _src.receivables();
  @override
  List<Bill> payables() => _src.payables();
  @override
  List<Bill> settledBills(bool recv) => _src.settledBills(recv);
  @override
  OutstandingSummary outstanding(bool recv) => _src.outstanding(recv);
  @override
  MonthTotals monthTotals() => _src.monthTotals();
  @override
  List<Party> parties() => _src.parties();
  @override
  List<Item> items() => _src.items();
  @override
  List<StockRow> stockRows() => _src.stockRows();
  @override
  List<String> stockGroups() => _src.stockGroups();
  @override
  List<BillLine> billLines(String billNo) => _src.billLines(billNo);
  @override
  List<Opt> ledgers() => _src.ledgers();
  @override
  List<Opt> accounts() => _src.accounts();
  @override
  List<Notif> notifications() => _src.notifications();
  @override
  List<Act> activity() => _src.activity();
  @override
  List<Member> team() => _src.team();
  @override
  List<Workspace> workspaces() => _src.workspaces();
  @override
  List<Report> reports() => _src.reports();
  @override
  List<Plan> plans() => _src.plans();
  @override
  List<Faq> faqs() => _src.faqs();
  @override
  Map<String, SumCard> moneyCards() => _src.moneyCards();
  @override
  Map<String, bool>? alertConfig() => _src.alertConfig();
  @override
  Future<void> saveAlert(String key, bool on) => _src.saveAlert(key, on);
  @override
  Future<void> saveAlerts(Map<String, bool> changes) =>
      _src.saveAlerts(changes);
  @override
  PartyDetail? partyDetail(String partyKey) => _src.partyDetail(partyKey);
  @override
  Future<void> loadPartyDetail(Party p, {bool force = false}) =>
      _src.loadPartyDetail(p, force: force);
  @override
  ItemDetail? itemDetail(String itemName) => _src.itemDetail(itemName);
  @override
  Future<void> loadItemDetail(Item it, {bool force = false}) =>
      _src.loadItemDetail(it, force: force);
  @override
  List<LedgerLine>? voucherLines(String guid) => _src.voucherLines(guid);
  @override
  Future<void> loadVoucherLines(String guid) => _src.loadVoucherLines(guid);
  @override
  Future<void> markNotifRead(String id) => _src.markNotifRead(id);
  @override
  Future<void> markAllNotifsRead() => _src.markAllNotifsRead();

  // ----------------------------------------------------------- writes
  /// Demo: entries are never sent anywhere.
  @override
  String? entryBlocker(EntryDraft d) =>
      _demoOn ? kDemoWriteBlocked : live.entryBlocker(d);
  @override
  Future<SubmitResult> submitEntry(EntryDraft d) async {
    if (_demoOn) {
      return const SubmitResult(ok: false, message: kDemoWriteBlocked);
    }
    return live.submitEntry(d);
  }

  @override
  Future<bool> pushEntry(
    Act entry, {
    Duration delay = const Duration(seconds: 5),
  }) async {
    if (_demoOn) return false; // never sent (the app also blocks it first)
    return live.pushEntry(entry, delay: delay);
  }
}

/// Shown when an entry is tried on demo data.
const String kDemoWriteBlocked =
    'This is demo data. Connect Tally and switch to your data to create '
    'entries.';
