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

  /// GET /company — every company of the admin (also the ones not synced
  /// yet); the same list the sync agent shows as "All companies".
  Future<Object?> companiesAll() => http.get('/company');
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
  /// GET /users — every user of the admin with their layout permissions
  /// (`ledger_permissions`, `vouchers_permissions`, `orders_permissions`,
  /// `inventory_permissions`; each `{ columns: { <field>: bool } }`).
  Future<Object?> users() => http.get('/users');

  /// POST /users `{ email, password }` (ADMIN) → `{ user: { id, username,
  /// email } }`. The server names the login after the email (`username` =
  /// part before `@`) and stores nothing else; 400 `User already exists`,
  /// 403 `Upgrade your plan to create more users`.
  Future<Object?> createUser(String email, String password) => http.post(
    '/users',
    body: <String, Object?>{'email': email, 'password': password},
  );

  /// DELETE /users/:id
  Future<Object?> deleteUser(String id) =>
      http.delete('/users/${Uri.encodeComponent(id)}');

  /// POST /send-invite — emails the user their login.
  Future<Object?> sendInvite(String email, String username) => http.post(
    '/send-invite',
    body: <String, Object?>{'email': email, 'username': username},
  );

  /// PUT /users/:id/{ledger|voucher|orders|inventory}-permissions — the
  /// whole permission object (stored as sent).
  Future<Object?> saveLayoutPermissions(
    String id,
    String route,
    Map<String, Object?> body,
  ) => http.put('/users/${Uri.encodeComponent(id)}/$route', body: body);

  /// GET /users/:id/ledgers → `[ { ledger_guid } ]`
  Future<Object?> userLedgers(String id) =>
      http.get('/users/${Uri.encodeComponent(id)}/ledgers');

  /// POST /ledger/user-ledgers `{ userId, ledgers: [guid] }` (replaces).
  Future<Object?> saveUserLedgers(int id, List<String> guids) => http.post(
    '/ledger/user-ledgers',
    body: <String, Object?>{'userId': id, 'ledgers': guids},
  );

  /// GET /voucher-entry/user-vouchers/:id → `{ vouchers: [guid] }`
  Future<Object?> userVouchers(String id) =>
      http.get('/voucher-entry/user-vouchers/${Uri.encodeComponent(id)}');

  /// POST /voucher-entry/user-vouchers `{ userId, vouchers }` (replaces).
  Future<Object?> saveUserVouchers(int id, List<String> guids) => http.post(
    '/voucher-entry/user-vouchers',
    body: <String, Object?>{'userId': id, 'vouchers': guids},
  );

  /// GET /orders — the active company's order book (admin: all orders).
  Future<Object?> orders() => http.get('/orders');

  /// GET /orders/user-orders/:id → `{ orders: [guid] }`
  Future<Object?> userOrders(String id) =>
      http.get('/orders/user-orders/${Uri.encodeComponent(id)}');

  /// POST /orders/user-orders `{ userId, orders }` (replaces).
  Future<Object?> saveUserOrders(int id, List<String> guids) => http.post(
    '/orders/user-orders',
    body: <String, Object?>{'userId': id, 'orders': guids},
  );

  /// GET /inventory/user-inventory/:id → `[ { item_name } ]`
  Future<Object?> userInventory(String id) =>
      http.get('/inventory/user-inventory/${Uri.encodeComponent(id)}');

  /// POST /inventory/user-inventory `{ userId, items: [item_name] }`
  /// (replaces).
  Future<Object?> saveUserInventory(int id, List<String> items) => http.post(
    '/inventory/user-inventory',
    body: <String, Object?>{'userId': id, 'items': items},
  );

  // ------------------------------------------------- notifications (§19)
  Future<Object?> notifications() => http.get('/api/mobile/notifications');
  Future<Object?> markNotificationRead(String id) =>
      http.post('/api/mobile/notifications/${Uri.encodeComponent(id)}/read');
  Future<Object?> notificationConfig() =>
      http.get('/api/mobile/notifications/config');
  Future<Object?> saveNotificationConfig(Map<String, bool> cfg) =>
      http.put('/api/mobile/notifications/config', body: cfg);

  /// Web-dashboard notifications of this user (`notifications` table:
  /// BILL, MONTHLY_REPORT, USER_CREATED / USER_DELETED, VOUCHER_CREATED /
  /// VOUCHER_DELETED), already filtered by the user's web preferences.
  Future<Object?> markWebNotificationRead(String id) =>
      http.post('/admin/notifications/${Uri.encodeComponent(id)}/read');

  /// The user's web notification preferences (`users.notification_
  /// preferences`: bill_created, monthly_reports, new_voucher,
  /// user_created, user_deleted, payment_due, low_stock). PUT replaces the
  /// whole object, so callers send every key.
  Future<Object?> webNotificationPrefs() => http.get('/users/me/notifications');
  Future<Object?> saveWebNotificationPrefs(Map<String, Object?> prefs) =>
      http.put('/users/me/notifications', body: prefs);

  // ------------------------------------------- raw JSON text (big lists)
  // Same endpoints and parameters as above, returned undecoded so the app
  // parses them in a background isolate and can cache the text as is.

  Future<String> meText() => http.getText('/users/me');
  Future<String> ledgersText() => http.getText('/ledger');
  Future<String> billsText() => http.getText('/bill');
  Future<String> inventoryMobileText() => http.getText('/inventory/mobile');
  Future<String> inventoryText() => http.getText('/inventory');
  Future<String> usersText() => http.getText('/users');
  Future<String> notificationsText() =>
      http.getText('/api/mobile/notifications');
  Future<String> notificationConfigText() =>
      http.getText('/api/mobile/notifications/config');
  Future<String> webNotificationsText() =>
      http.getText('/admin/notifications');
  Future<String> webNotificationPrefsText() =>
      http.getText('/users/me/notifications');
  Future<String> queueActivityText(String companyGuid) => http.getText(
    '/api/mobile-sync-queue/activity',
    query: <String, Object?>{'company_guid': companyGuid},
  );

  /// GET /voucher-entry/paged (page, limit ≤ 200, type, search, year,
  /// month, sort_by) as raw text.
  Future<String> vouchersPagedText({
    int page = 1,
    int limit = 100,
    int? year,
    int? month,
    String? type,
    String? search,
    String sortBy = 'date_desc',
  }) => http.getText(
    '/voucher-entry/paged',
    query: <String, Object?>{
      'page': page,
      'limit': limit,
      'year': year,
      'month': month,
      'type': type,
      'search': search,
      'sort_by': sortBy,
    },
  );
}
