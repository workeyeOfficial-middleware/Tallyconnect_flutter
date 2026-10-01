// Backend seam. Screens never read mock constants directly for business data;
// they go through [TallyRepository]. Today [MockTallyRepository] serves the
// prototype's sample data; a real Tally bridge implements the same interface.
library;

import '../mock/mock_data.dart';
import '../models/models.dart';

abstract interface class TallyRepository {
  List<Company> companies();
  List<Voucher> vouchers();
  List<Bill> receivables();
  List<Bill> payables();
  List<Party> parties();
  List<Item> items();
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

  /// Sends a saved entry towards Tally. Mock: resolves after [delay].
  Future<bool> pushEntry(Act entry, {Duration delay});
}

class MockTallyRepository implements TallyRepository {
  const MockTallyRepository();

  @override
  List<Company> companies() => kCompanies;
  @override
  List<Voucher> vouchers() => kVouchers;
  @override
  List<Bill> receivables() => kRecv;
  @override
  List<Bill> payables() => kPayb;
  @override
  List<Party> parties() => kParties;
  @override
  List<Item> items() => kItems;
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
  Future<bool> pushEntry(
    Act entry, {
    Duration delay = const Duration(seconds: 5),
  }) => Future<bool>.delayed(delay, () => true);
}
