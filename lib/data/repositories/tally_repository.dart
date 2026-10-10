// Backend seam. Screens never read mock constants or call the API directly
// for business data; they go through [TallyRepository]:
//   UI → Riverpod (appProvider) → TallyRepository → ApiTallyRepository → API.
// [MockTallyRepository] serves the prototype's sample data (tests / demo);
// [ApiTallyRepository] serves the real backend.
//
// Getters return the latest loaded snapshot synchronously; `refresh…` /
// `load…` methods fetch and then notify listeners.
library;

import 'package:flutter/foundation.dart';

import '../../core/utils/format.dart';
import '../accounting.dart';
import '../mock/mock_data.dart';
import '../models/models.dart';
import 'team_admin.dart';
import 'voucher_pager.dart';

export 'voucher_pager.dart'
    show DateRange, HistoryTotals, VoucherCounts, VoucherPager, VoucherQuery;

/// Everything the entry flow collected, before it is mapped to a backend
/// request body by the repository.
/// A party created inline in an entry: sent with the voucher; the sync
/// agent creates the ledger in Tally (customer → Sundry Debtors, supplier →
/// Sundry Creditors) before posting the voucher.
class NewParty {
  const NewParty({
    required this.name,
    required this.type,
    this.phone = '',
    this.city = '',
  });
  final String name, phone, city;

  /// `c` customer | `s` supplier.
  final String type;

  String get group => type == 's' ? 'Sundry Creditors' : 'Sundry Debtors';

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'group': group,
    'type': type == 's' ? 'supplier' : 'customer',
    if (phone.isNotEmpty) 'phone': phone,
    if (city.isNotEmpty) 'city': city,
  };
}

class EntryDraft {
  const EntryDraft({
    required this.type,
    required this.no,
    required this.date,
    required this.party,
    this.due = '',
    this.note = '',
    this.amount = 0,
    this.ref = '',
    this.mode = 'cash',
    this.bank = '',
    this.utr = '',
    this.account = '',
    this.supplierInvoice = '',
    this.lines = const <Line>[],
    this.journal = const <JLine>[],
    this.newParty,
  });

  /// Set when [party] was created in this entry (not in Tally yet).
  final NewParty? newParty;

  /// sales | purchase | receipt | payment | journal
  final String type;
  final String no, date, party, due, note, ref, mode, bank, utr, account;
  final String supplierInvoice;

  /// Money received / paid now (sales, purchase, receipt, payment).
  final num amount;
  final List<Line> lines;
  final List<JLine> journal;
}

abstract class TallyRepository extends ChangeNotifier {
  TallyRepository();

  /// True for the real backend.
  bool get isRemote;

  /// "Today" used for due dates, ageing and month totals.
  DateTime get today;

  // ------------------------------------------------------------ session
  AuthUser? get user;
  Profile? get profile;

  /// Set when the server rejected the token (expired / invalid).
  bool get sessionExpired;

  Future<AuthUser> login(String email, String password, String loginType);
  Future<bool> restoreSession();
  Future<void> logout();
  Future<void> sendResetCode(String email);

  /// Sets a new password with the emailed code.
  Future<void> resetPassword(String email, String code, String password);

  // -------------------------------------------------------------- data
  /// Reloads every data set. Concurrent calls share one load; without
  /// [force] a load finished in the last few seconds is not repeated.
  /// Previous data stays visible until fresh data replaces it.
  Future<void> refreshAll({bool force = false});
  Future<void> refreshActivity();
  Future<void> refreshNotifications();

  /// True when the Tally agent finished a sync newer than the loaded data.
  Future<bool> checkNewSync() async => false;
  DataStatus status(String set);

  /// True once the set has real data (from the server or the local cache).
  bool hasData(String set);

  /// Loads [set] if it has no data yet (screens call this when they open,
  /// so big sets such as items / stock / team are not loaded at startup).
  Future<void> ensure(String set);

  /// Sales Team user configuration on the server (permissions, invite,
  /// delete); null with sample data, which has no server to save to.
  TeamAdmin? get teamAdmin => null;

  /// Bumped on every data change (cache key for derived values).
  int get version;

  /// Page-by-page voucher list for one filter / period.
  VoucherPager voucherPager(VoucherQuery q);

  /// Server-side voucher search (first matches only).
  Future<List<Voucher>> searchVouchers(String query);

  /// A voucher already loaded on the phone, by [Voucher.key].
  Voucher? voucherByKey(String key);

  /// All-history totals, once [scanHistory] has run (null before).
  HistoryTotals? get historyTotals;

  /// Reads the complete voucher history once, on request, into
  /// [historyTotals] without keeping the rows.
  Future<void> scanHistory();

  /// Exact voucher counts of the complete matching data for a period
  /// (`all`, `month`, `week`, `today`): total, per kind and per type. Null
  /// until loaded ([loadVoucherCounts]); last good counts stay while a
  /// refresh reloads them.
  VoucherCounts? voucherCounts(String period);

  /// Loads [voucherCounts] for [period] if missing or out of date (shared
  /// while running; cheap when nothing is needed).
  Future<void> loadVoucherCounts(String period);

  /// First error of the last load, or null when everything loaded.
  String? lastError();

  List<Company> companies();
  String? get activeCompanyId;
  SyncInfo? syncInfo(String companyId);
  Future<void> setActiveCompany(String id);

  /// This month's vouchers (complete), newest first — the basis of the
  /// month totals. Longer periods are paged ([voucherPager]).
  List<Voucher> vouchers();

  /// False when this month's vouchers could not be read in full.
  bool get vouchersComplete;
  List<Bill> receivables();
  List<Bill> payables();

  /// Bills paid / settled in Tally (not part of Outstanding totals).
  List<Bill> settledBills(bool recv);
  OutstandingSummary outstanding(bool recv);
  MonthTotals monthTotals();
  List<Party> parties();
  List<Item> items();
  List<StockRow> stockRows();

  /// Tally stock groups of the active company (from the loaded items).
  List<String> stockGroups();
  List<BillLine> billLines(String billNo);
  List<Opt> ledgers();
  List<Opt> accounts();
  List<Notif> notifications();
  List<Act> activity();
  List<Member> team();
  List<Workspace> workspaces();
  List<Report> reports();
  List<Plan> plans();
  List<Faq> faqs();
  Map<String, SumCard> moneyCards();

  /// Server alert switches (`/api/mobile/notifications/config`); null when
  /// not loaded or not supported.
  Map<String, bool>? alertConfig();
  Future<void> saveAlert(String key, bool on);

  /// Saves several switches at once (`web.<key>` = web preference).
  Future<void> saveAlerts(Map<String, bool> changes);

  PartyDetail? partyDetail(String partyKey);
  Future<void> loadPartyDetail(Party p, {bool force = false});
  ItemDetail? itemDetail(String itemName);
  Future<void> loadItemDetail(Item it, {bool force = false});
  List<LedgerLine>? voucherLines(String guid);
  Future<void> loadVoucherLines(String guid);

  Future<void> markNotifRead(String id);
  Future<void> markAllNotifsRead();

  /// Reason the server cannot take this entry correctly, or null.
  String? entryBlocker(EntryDraft d);
  Future<SubmitResult> submitEntry(EntryDraft d);

  /// Sends a saved entry towards Tally (sample data only).
  Future<bool> pushEntry(Act entry, {Duration delay});
}

class MockTallyRepository extends TallyRepository {
  MockTallyRepository();

  static final DateTime _today = DateTime(2026, 9, 26);

  @override
  bool get isRemote => false;
  @override
  DateTime get today => _today;

  @override
  AuthUser? get user => null;
  @override
  Profile? get profile => null;
  @override
  bool get sessionExpired => false;
  @override
  Future<AuthUser> login(
    String email,
    String password,
    String loginType,
  ) async =>
      const AuthUser(id: 0, username: 'workk72002', email: '', role: 'ADMIN');
  @override
  Future<bool> restoreSession() async => false;
  @override
  Future<void> logout() async {}
  @override
  Future<void> sendResetCode(String email) async {}
  @override
  Future<void> resetPassword(
    String email,
    String code,
    String password,
  ) async {}

  @override
  Future<void> refreshAll({bool force = false}) async {}
  @override
  bool hasData(String set) => true;
  @override
  Future<void> ensure(String set) async {}
  @override
  int get version => 0;

  static List<Voucher> get _newestFirst =>
      List<Voucher>.of(_vs)
        ..sort((Voucher a, Voucher b) => b.date!.compareTo(a.date!));

  @override
  VoucherPager voucherPager(VoucherQuery q) => VoucherPager(
    q,
    (int page, VoucherQuery q, DateTime t) async => FetchedPage(
      page == 1 ? _newestFirst : const <Voucher>[],
      const <String>[],
      false,
    ),
    _today,
  );

  @override
  Future<List<Voucher>> searchVouchers(String query) async {
    final String q = query.toLowerCase();
    return _newestFirst
        .where(
          (Voucher v) => '${v.party} ${v.no} ${kKinds[v.kind]!.t}'
              .toLowerCase()
              .contains(q),
        )
        .take(25)
        .toList();
  }

  @override
  Voucher? voucherByKey(String key) =>
      _vs.where((Voucher v) => v.key == key).firstOrNull;

  static final HistoryTotals _hist = HistoryTotals()
    ..add(FetchedPage(_vs, const <String>[], false))
    ..done = true;
  @override
  HistoryTotals? get historyTotals => _hist;
  @override
  Future<void> scanHistory() async {}

  @override
  VoucherCounts? voucherCounts(String period) => VoucherCounts.of(
    _vs.where((Voucher v) => voucherInPeriod(v, period, _today)),
  );
  @override
  Future<void> loadVoucherCounts(String period) async {}
  @override
  String? lastError() => null;
  @override
  Future<void> refreshActivity() async {}
  @override
  Future<void> refreshNotifications() async {}
  @override
  DataStatus status(String set) => const DataStatus(LoadState.ready);

  @override
  List<Company> companies() => kCompanies;
  @override
  String? get activeCompanyId => 'gi';
  @override
  SyncInfo? syncInfo(String companyId) => null;
  @override
  Future<void> setActiveCompany(String id) async {}

  static final List<Voucher> _vs = <Voucher>[
    for (final Voucher v in kVouchers)
      Voucher(
        v.kind,
        v.party,
        v.no,
        v.day,
        v.amt,
        date: DateTime(2026, 9, v.day),
      ),
  ];
  static List<Bill> _dated(List<Bill> l) => <Bill>[
    for (final Bill b in l)
      Bill(
        b.party,
        b.no,
        b.bill,
        b.due,
        b.credit,
        b.amt,
        b.st,
        b.txt,
        b.city,
        b.kind,
        null,
        null,
        parseDmy(b.due),
        b.amt,
        b.no == 'Sales 9' ? kSales9 : const <BillLine>[],
      ),
  ];
  static final List<Bill> _recv = _dated(kRecv), _pay = _dated(kPayb);

  @override
  List<Bill> settledBills(bool recv) => const <Bill>[];

  @override
  List<Voucher> vouchers() => _vs;
  @override
  bool get vouchersComplete => true;
  @override
  List<Bill> receivables() => _recv;
  @override
  List<Bill> payables() => _pay;
  @override
  OutstandingSummary outstanding(bool recv) =>
      summarise(recv ? _recv : _pay, _today);
  @override
  MonthTotals monthTotals() => computeMonth(_vs, _today);
  @override
  List<Party> parties() => kParties;
  @override
  List<Item> items() => kItems;
  @override
  List<StockRow> stockRows() => const <StockRow>[];
  @override
  List<String> stockGroups() => groupsOf(kItems);
  @override
  List<BillLine> billLines(String billNo) =>
      billNo == 'Sales 9' ? kSales9 : const <BillLine>[];
  @override
  List<Opt> ledgers() => kLedgers;
  @override
  List<Opt> accounts() => kAccounts;
  @override
  List<Notif> notifications() => kNotifs;
  @override
  List<Act> activity() => kActs;
  @override
  List<Member> team() => kTeam;
  @override
  List<Workspace> workspaces() => kWorkspaces;
  @override
  List<Report> reports() => kReports;
  @override
  List<Plan> plans() => kPlans;
  @override
  List<Faq> faqs() => kFaqs;
  @override
  Map<String, SumCard> moneyCards() => kSums;

  @override
  Map<String, bool>? alertConfig() => null;
  @override
  Future<void> saveAlert(String key, bool on) async {}
  @override
  Future<void> saveAlerts(Map<String, bool> changes) async {}

  @override
  PartyDetail? partyDetail(String partyKey) => null;
  @override
  Future<void> loadPartyDetail(Party p, {bool force = false}) async {}
  @override
  ItemDetail? itemDetail(String itemName) => null;
  @override
  Future<void> loadItemDetail(Item it, {bool force = false}) async {}
  @override
  List<LedgerLine>? voucherLines(String guid) => null;
  @override
  Future<void> loadVoucherLines(String guid) async {}

  @override
  Future<void> markNotifRead(String id) async {}
  @override
  Future<void> markAllNotifsRead() async {}

  @override
  String? entryBlocker(EntryDraft d) => null;
  @override
  Future<SubmitResult> submitEntry(EntryDraft d) async =>
      const SubmitResult(ok: true);

  @override
  Future<bool> pushEntry(
    Act entry, {
    Duration delay = const Duration(seconds: 5),
  }) => Future<bool>.delayed(delay, () => true);
}

/// Shared month-total helper (alias kept short for both repositories).
MonthTotals computeMonth(
  List<Voucher> vs,
  DateTime today, {
  bool complete = true,
}) => monthTotals(vs, today, complete: complete);

/// Distinct, sorted Tally stock groups of [items] (no invented groups:
/// only groups that items really belong to).
List<String> groupsOf(List<Item> items) {
  final Map<String, String> byKey = <String, String>{};
  for (final Item it in items) {
    final String g = (it.group ?? '').trim();
    if (g.isNotEmpty) byKey.putIfAbsent(g.toLowerCase(), () => g);
  }
  return byKey.values.toList()
    ..sort((String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()));
}
