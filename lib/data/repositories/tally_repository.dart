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

/// Everything the entry flow collected, before it is mapped to a backend
/// request body by the repository.
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
  });

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

  // -------------------------------------------------------------- data
  /// Reloads every data set. Concurrent calls share one load; without
  /// [force] a load finished in the last few seconds is not repeated.
  /// Previous data stays visible until fresh data replaces it.
  Future<void> refreshAll({bool force = false});
  Future<void> refreshActivity();
  Future<void> refreshNotifications();
  DataStatus status(String set);

  /// True once the set has real data (from the server or the local cache).
  bool hasData(String set);

  /// First error of the last load, or null when everything loaded.
  String? lastError();

  List<Company> companies();
  String? get activeCompanyId;
  SyncInfo? syncInfo(String companyId);
  Future<void> setActiveCompany(String id);

  /// Every voucher available for the active company, newest first.
  List<Voucher> vouchers();

  /// False when the server's voucher history could not be read in full.
  bool get vouchersComplete;
  List<Bill> receivables();
  List<Bill> payables();
  OutstandingSummary outstanding(bool recv);
  MonthTotals monthTotals();
  List<Party> parties();
  List<Item> items();
  List<StockRow> stockRows();
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
  Future<void> refreshAll({bool force = false}) async {}
  @override
  bool hasData(String set) => true;
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
