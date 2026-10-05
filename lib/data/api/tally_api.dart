// One method per backend endpoint used by the app (BACKEND_API_REFERENCE.md).
// Paths, query names and body fields are the backend's own; nothing here
// interprets data — that is the adapters' job.
library;

import '../../core/network/api_client.dart';

typedef Json = Map<String, Object?>;

class TallyApi {
  TallyApi(this.http);
  final ApiClient http;

  // ------------------------------------------------------------ auth (§2)
  /// POST /auth/login — `loginType` is `ADMIN` or `USER` (exact case).
  Future<Object?> login(String email, String password, String loginType) =>
      http.post(
        '/auth/login',
        auth: false,
        body: <String, Object?>{
          'username': email,
          'password': password,
          'loginType': loginType,
        },
      );

  /// POST /api/auth/send-otp
  Future<Object?> sendOtp(String email) => http.post(
    '/api/auth/send-otp',
    auth: false,
    body: <String, Object?>{'email': email},
  );

  // ------------------------------------------------------- profile (§3)
  Future<Object?> me() => http.get('/users/me');

  // ------------------------------------------------------- company (§4)
  Future<Object?> companiesSelected() => http.get('/company/selected');
  Future<Object?> companyActive() => http.get('/company/active');
  Future<Object?> setActiveCompany(String guid) => http.post(
    '/company/set-active',
    body: <String, Object?>{'company_guid': guid},
  );

  // ----------------------------------------------------- dashboard (§5)
  Future<Object?> dashboardSummary(String companyGuid) => http.get(
    '/dashboard/summary',
    query: <String, Object?>{'company_guid': companyGuid},
  );
  Future<Object?> syncStatus(String companyGuid) => http.get(
    '/agent-status/sync-status',
    query: <String, Object?>{'company_guid': companyGuid},
  );

  // ------------------------------------------------------- parties (§6)
  Future<Object?> ledgers() => http.get('/ledger');
  Future<Object?> ledgerVouchers(String guid) =>
      http.get('/voucher-entry/ledger/${Uri.encodeComponent(guid)}');
  Future<Object?> ledgerItems(String guid) =>
      http.get('/ledger-items/ledger/${Uri.encodeComponent(guid)}');
  Future<Object?> ledgerBills(String guid) =>
      http.get('/bill/ledger/${Uri.encodeComponent(guid)}');

  // --------------------------------------------------------- items (§7)
  Future<Object?> inventoryMobile() => http.get('/inventory/mobile');
  Future<Object?> inventory() => http.get('/inventory');

  /// GET /ledger-items/item/:itemName/parties?type=Sales|Purchase
  Future<Object?> itemParties(String itemName, String type) => http.get(
    '/ledger-items/item/${Uri.encodeComponent(itemName)}/parties',
    query: <String, Object?>{'type': type},
  );

  // ---------------------------------------------- entries (§8–§12)
  Future<Object?> createSalesPurchase(Json body) =>
      http.post('/api/mobile-voucher-command/create', body: body);
  Future<Object?> createReceipt(Json body) =>
      http.post('/api/mobile-voucher-command/receipt/create', body: body);
  Future<Object?> createPayment(Json body) =>
      http.post('/api/mobile-voucher-command/payment/create', body: body);
  Future<Object?> createJournal(Json body) =>
      http.post('/api/mobile-voucher-command/journal/create', body: body);

  // ------------------------------------------------------ vouchers (§13)
  Future<Object?> vouchersPaged({
    int page = 1,
    int limit = 200,
    int? year,
    int? month,
    String sortBy = 'date_desc',
  }) => http.get(
    '/voucher-entry/paged',
    query: <String, Object?>{
      'page': page,
      'limit': limit,
      'year': year,
      'month': month,
      'sort_by': sortBy,
    },
  );
  Future<Object?> voucherDetail(String guid) =>
      http.get('/voucher-entry/${Uri.encodeComponent(guid)}');

  // --------------------------------------------------- outstanding (§14)
  Future<Object?> bills() => http.get('/bill');

  // ------------------------------------------------------ activity (§16)
  Future<Object?> queueActivity(String companyGuid) => http.get(
    '/api/mobile-sync-queue/activity',
    query: <String, Object?>{'company_guid': companyGuid},
  );

  // ---------------------------------------------------------- team (§17)
  Future<Object?> users() => http.get('/users');

  // ------------------------------------------------- notifications (§19)
  Future<Object?> notifications() => http.get('/api/mobile/notifications');
  Future<Object?> markNotificationRead(String id) =>
      http.post('/api/mobile/notifications/${Uri.encodeComponent(id)}/read');
  Future<Object?> notificationConfig() =>
      http.get('/api/mobile/notifications/config');
  Future<Object?> saveNotificationConfig(Map<String, bool> cfg) =>
      http.put('/api/mobile/notifications/config', body: cfg);
}
