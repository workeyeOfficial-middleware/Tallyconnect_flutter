// Backend integration tests — no network: a fake HTTP client answers with
// the exact JSON shapes documented in BACKEND_API_REFERENCE.md (numbers as
// strings, DATE columns as midnight-UTC ISO strings).
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show Size;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/network/api_client.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/core/storage/session_store.dart';
import 'package:tallyconnect_ui/core/storage/snapshot_cache.dart';
import 'package:tallyconnect_ui/core/utils/format.dart';
import 'package:tallyconnect_ui/data/accounting.dart';
import 'package:tallyconnect_ui/data/api/adapters.dart';
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/api_tally_repository.dart';
import 'package:tallyconnect_ui/data/repositories/tally_repository.dart';
import 'package:tallyconnect_ui/main.dart';

const String kGuid = 'co-1';

/// JWT with exp far in the future (payload {"exp":4102444800}).
final String kToken =
    'x.${base64Url.encode(utf8.encode('{"exp":4102444800}')).replaceAll('=', '')}.y';

/// Fake backend. Records every request.
class FakeBackend {
  final List<http.Request> calls = <http.Request>[];
  bool expire = false;

  /// Simulated network time per request (widget tests).
  Duration delay = Duration.zero;

  /// Extra `/ledger` rows for a test (none by default).
  List<Map<String, Object?>> extraLedgers = <Map<String, Object?>>[];

  /// The whole history's voucher types (V1, V2, V3, V4 — flagged
  /// is_active:false by a sync reset, still a Tally voucher — and V9).
  static const List<String> historyTypes = <String>[
    'Sales',
    'Receipt',
    'Sales Order',
    'Payment',
    'Payment',
  ];

  /// Server count of the whole history for a `type` filter.
  static int historyCount(String? type) => type == null
      ? historyTypes.length
      : historyTypes
            .where((String t) => t.toLowerCase().contains(type.toLowerCase()))
            .length;

  /// Agent's last finished sync (GET /agent-status/sync-status).
  String lastSync = '2026-10-03T04:00:00.000Z';

  /// Extra fields of GET /agent-status/sync-status (multi-company Agents:
  /// state, percent, last_error, sync_in_progress).
  Map<String, Object?> syncExtra = <String, Object?>{};

  /// `SUM(net_amount)` the server reports per type filter (null: 0).
  Map<String, num>? typeTotals;
  num totalFor(String? type) {
    final Map<String, num>? t = typeTotals;
    if (t == null) return 0;
    num s = 0;
    t.forEach((String k, num v) {
      if (type == null || k.toLowerCase().contains(type.toLowerCase())) {
        s += v;
      }
    });
    return s;
  }

  /// Extra mobile alerts (newest arrive after start).
  List<Map<String, Object?>> moreNotifs = <Map<String, Object?>>[];

  /// A brand-new account: no companies, nothing synced yet.
  bool newAccount = false;

  /// Bodies sent to POST /api/feedback; [feedbackLimited] answers 429.
  final List<Map<String, Object?>> feedback = <Map<String, Object?>>[];
  bool feedbackLimited = false;

  /// A server deployed without the feedback route (Express's own 404).
  bool feedbackMissing = false;

  /// What happens to the notification email: `sent` (Graph accepted it),
  /// `failed` (502), `skipped` (503, no recipient set) or `legacy` (the old
  /// server: 201 before trying the email, no `email_status`).
  String feedbackEmail = 'sent';

  // ------------------------------------------- /api/reminders/* (fake)
  /// The server's own pending bills of ledger L1 (it never takes amounts
  /// from the app): bill no. → (pending, due).
  Map<String, (num, String)> remBills = <String, (num, String)>{
    'S/101': (10000.50, '2026-09-20'),
    'S/102': (5000.00, '2026-10-05'),
  };

  /// L1's email in Tally (null: none saved).
  String? remEmail = 'accounts@mehta.in';

  /// Server deployed without the reminder routes (Express's own 404).
  bool remMissing = false;

  /// MICROSOFT_* variables missing on the server.
  bool remNotConfigured = false;

  /// Microsoft Graph refuses the email.
  bool remSendFail = false;

  /// Bodies of POST /api/reminders/send (one per real send attempt).
  final List<Map<String, Object?>> remSends = <Map<String, Object?>>[];
  final List<Map<String, Object?>> remLogs = <Map<String, Object?>>[];
  final List<Map<String, Object?>> remTemplates = <Map<String, Object?>>[];
  int _remId = 1;

  /// Payment reminder settings saved on the server (null: defaults).
  Map<String, Object?>? remSettings;

  /// The server has no reminder_settings table yet (SQL not run).
  bool remSettingsNoTable = false;

  /// GET /api/reminders/due rows (parties due for a reminder today).
  List<Map<String, Object?>> remDue = <Map<String, Object?>>[];

  /// Bodies of PUT /api/reminders/settings.
  final List<Map<String, Object?>> remSettingsPuts = <Map<String, Object?>>[];

  // -------------------------------------------- /api/financial/* (fake)
  /// This login may see financial statements.
  bool finAllowed = true;

  /// Agent has not synced the figures yet.
  bool finNotSynced = false;

  /// GET /api/financial/periods `message` (why no date yet), or none.
  String? finReason;

  /// Year ends whose closing stock is missing (`stock_needed`), whether
  /// this login may enter one, and what PUT /api/financial/stock-values got.
  final List<String> finStockNeeded = <String>[];
  bool finCanEnterStock = true;
  final List<Map<String, Object?>> finStockSaved = <Map<String, Object?>>[];

  /// Vouchers synced from the books' start: any From / To (`any_period`).
  bool finAnyPeriod = false;

  /// Trial Balance with crore amounts (as on a real company's phone).
  bool finBigTb = false;

  /// Cash Flow: cash / bank moved by vouchers Tally's Cash Flow leaves out.
  num finCashNotInFlow = 0;

  // ---------------------------------------- /api/attendance/* (fake)
  /// The last login's type (`ADMIN` / `USER`).
  String loginType = 'ADMIN';

  /// The server lets this (team) login check in; server without the routes.
  bool attOnTeam = true;
  bool attMissing = false;

  /// Every call (path, method, body); the logins' sessions.
  final List<Map<String, Object?>> attRequests = <Map<String, Object?>>[];
  final List<Map<String, Object?>> attSessions = <Map<String, Object?>>[];

  /// The server's clock (the same fixed "today" as the repository's).
  DateTime Function() attNow = () => DateTime(2026, 10, 3, 11);

  /// Check-in rules: positions that do not check in; each member's
  /// position / rule (user id → (position, rule)). The team login is "7".
  List<String> attExempt = <String>[];
  final Map<String, (String?, String)> attRules = <String, (String?, String)>{};

  /// The server has no check-in rules tables yet.
  bool attRulesMissing = false;

  /// Bodies of PUT /api/attendance/settings and /members/:id.
  final List<Map<String, Object?>> attRulePuts = <Map<String, Object?>>[];

  /// Must [userId] check in (as the server decides)?
  bool attRequired(String userId) {
    final (String?, String) r = attRules[userId] ?? (null, 'auto');
    if (r.$2 == 'required') return true;
    if (r.$2 == 'exempt') return false;
    final String pos = (r.$1 ?? '').toLowerCase();
    return !attExempt.any((String x) => x.toLowerCase() == pos && pos != '');
  }

  // ------------------------------------------- /api/einvoice/* (fake)
  /// Rows as the server sends them (status / alerts worked out already);
  /// server without the routes; every call.
  final List<Map<String, Object?>> einvRows = <Map<String, Object?>>[];
  bool einvMissing = false;
  final List<Map<String, Object?>> einvCalls = <Map<String, Object?>>[];

  // --------------------------------------------- /api/leave/* (fake)
  /// Server without the routes; every call (path, method, query + body).
  bool leaveMissing = false;
  final List<Map<String, Object?>> leaveCalls = <Map<String, Object?>>[];

  /// The admin's settings (as stored), leave types, holidays, requests. The
  /// member login is user 7; team members 9 "asha" and 10.
  Map<String, Object?> leaveSettings = <String, Object?>{
    'enabled': false,
    'year_start_month': 4,
    'weekly_off': <int>[0],
    'half_day': true,
    'backdate_days': 7,
    'max_request_days': 30,
  };
  final List<Map<String, Object?>> leaveTypes = <Map<String, Object?>>[];
  final List<Map<String, Object?>> leaveHolidays = <Map<String, Object?>>[];
  final List<Map<String, Object?>> leaveReqs = <Map<String, Object?>>[];

  /// Leave on, Casual 12 / Sick 6 / Unpaid (no limit), a holiday on
  /// 6 Oct 2026.
  void leaveSetUp() {
    leaveSettings['enabled'] = true;
    leaveTypes.addAll(<Map<String, Object?>>[
      <String, Object?>{
        'id': 1,
        'name': 'Casual Leave',
        'yearly_quota': 12,
        'paid': true,
        'carry_forward': false,
        'max_carry': null,
        'active': true,
      },
      <String, Object?>{
        'id': 2,
        'name': 'Sick Leave',
        'yearly_quota': 6,
        'paid': true,
        'carry_forward': false,
        'max_carry': null,
        'active': true,
      },
      <String, Object?>{
        'id': 3,
        'name': 'Unpaid Leave',
        'yearly_quota': null,
        'paid': false,
        'carry_forward': false,
        'max_carry': null,
        'active': true,
      },
    ]);
    leaveHolidays.add(<String, Object?>{
      'date': '2026-10-06',
      'name': 'Dussehra',
    });
  }

  // ----------------------------------------- /api/analytics/sales (fake)
  /// Query of every call; server deployed without the route; no sales.
  final List<Map<String, String>> salesQueries = <Map<String, String>>[];
  bool salesMissing = false;

  /// Server deployed without the Contra route (404, no JSON body).
  bool contraMissing = false;

  /// Server deployed without the edit route (404, no JSON body).
  bool editMissing = false;

  // ---------------------------------------- /api/cashflow/* (fake)
  /// Query of every call; server without the routes; no cash figures.
  final List<Map<String, String>> cashflowQueries = <Map<String, String>>[];
  bool cashflowMissing = false;
  bool cashflowNoOpening = false;

  // ---------------------------------- /api/tally-reports/* (fake)
  /// Reports "fetched by the Agent": report → [{from, to, rows}].
  final Map<String, List<Map<String, Object?>>> tallyReports =
      <String, List<Map<String, Object?>>>{};
  bool tallyReportsMissing = false;
  bool salesEmpty = false;

  /// Team members granted access; PUT bodies.
  final Set<String> finGranted = <String>{};
  final List<Map<String, Object?>> finRequests = <Map<String, Object?>>[];

  // -------------------------------------------- /api/assistant/* (fake)
  // As the backend: the server's own AI key, a token allowance per login.

  /// The free allowance and what this login has used (server-side).
  int aiLimit = 10000;
  int aiUsed = 0;

  /// Tokens one answer costs.
  int aiCost = 240;

  /// AI_API_KEY not set on the server.
  bool aiDisabled = false;

  /// `busy` (provider quota, 503) or `down` (502) or null.
  String? aiFail;

  /// Server deployed without the assistant routes.
  bool aiMissing = false;

  /// Replaces the default answer of POST /api/assistant/ask (whole body).
  Map<String, Object?>? aiReply;

  /// Bodies of POST /api/assistant/ask; headers of every assistant call.
  final List<Map<String, Object?>> aiAsks = <Map<String, Object?>>[];
  final List<Map<String, String>> aiHeadersSeen = <Map<String, String>>[];

  Map<String, Object?> get _aiUsage => <String, Object?>{
    'plan': <String, Object?>{
      'code': 'free',
      'name': 'Free',
      'period': 'lifetime',
    },
    'limit': aiLimit,
    'used': aiUsed,
    'remaining': aiUsed >= aiLimit ? 0 : aiLimit - aiUsed,
    'exhausted': aiUsed >= aiLimit,
  };

  /// Users removed with DELETE /users/:id.
  final Set<String> deletedUsers = <String>{};

  /// Logins made with POST /users (`{email, password}`).
  final List<Map<String, Object?>> createdUsers = <Map<String, Object?>>[];

  /// Request-shape violations seen by the fake server. Recorded instead of
  /// `expect` inside the handler (an `expect` there conflicts with a widget
  /// test's pump); tests assert this stays empty.
  final List<String> violations = <String>[];

  Map<String, Object?> json(String path, http.Request r) {
    throw UnimplementedError(path);
  }

  late final MockClient client = MockClient((http.Request r) async {
    calls.add(r);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final String p = r.url.path;
    if (expire && p != '/auth/login') {
      return http.Response('{"message":"Invalid token"}', 401);
    }
    Object? body;
    if (newAccount) {
      switch (p) {
        case '/company/selected' || '/company':
          return http.Response('{"success":true,"data":[]}', 200);
        case '/company/active':
          return http.Response('{"success":true,"company_guid":null}', 200);
        case '/agent-status/sync-status':
          return http.Response(
            '{"success":true,"last_sync_at":null,"sync_in_progress":false}',
            200,
          );
      }
    }
    if (p.startsWith('/api/reminders')) return _reminders(r, p);
    if (p.startsWith('/api/assistant')) return _assistant(r, p);
    if (p.startsWith('/api/financial')) return _financial(r, p);
    if (p.startsWith('/api/attendance')) return _attendance(r, p);
    if (p.startsWith('/api/leave')) return _leave(r, p);
    if (p.startsWith('/api/einvoice')) return _einvoice(r, p);
    if (p == '/api/analytics/sales') return _sales(r);
    if (p.startsWith('/api/cashflow/')) return _cashflow(r, p);
    if (p.startsWith('/api/tally-reports/')) return _tallyReports(r, p);
    if (p == '/api/feedback' && r.method == 'POST') {
      if (feedbackMissing) {
        return http.Response(
          '<!DOCTYPE html><html><body><pre>Cannot POST /api/feedback</pre>'
          '</body></html>',
          404,
          headers: <String, String>{'content-type': 'text/html'},
        );
      }
      if (feedbackLimited) {
        return http.Response(
          '{"success":false,"message":"You have sent a lot of feedback '
          'recently. Please try again later."}',
          429,
        );
      }
      feedback.add(jsonDecode(r.body) as Map<String, Object?>);
      final int id = feedback.length;
      return switch (feedbackEmail) {
        'legacy' => http.Response(
          jsonEncode(<String, Object?>{'success': true, 'id': id}),
          201,
        ),
        'failed' || 'skipped' => _json(feedbackEmail == 'failed' ? 502 : 503, <
          String,
          Object?
        >{
          'success': false,
          'stored': true,
          'id': id,
          'email_status': feedbackEmail,
          'code': feedbackEmail == 'failed'
              ? 'email_failed'
              : 'email_not_configured',
          'message': feedbackEmail == 'failed'
              ? 'Your feedback was saved (#$id), but the email to the '
                    'TallyConnect team could not be sent. Please try again later.'
              : 'Your feedback was saved (#$id), but feedback email is not '
                    'set up on the server, so the TallyConnect team was not emailed.',
        }),
        _ => _json(201, <String, Object?>{
          'success': true,
          'id': id,
          'email_status': 'sent',
        }),
      };
    }
    switch (p) {
      case '/auth/login':
        final Map<String, Object?> b =
            (jsonDecode(r.body) as Map<String, Object?>);
        if (b['loginType'] != 'ADMIN' && b['loginType'] != 'USER') {
          return http.Response('{"message":"loginType is required"}', 400);
        }
        if (b['password'] != 'secret') {
          return http.Response('{"message":"Invalid credentials"}', 401);
        }
        loginType = '${b['loginType']}';
        body = <String, Object?>{
          'token': kToken,
          'user': <String, Object?>{
            'id': 7,
            'username': 'ravi',
            'email': b['username'],
            'role': b['loginType'],
            'adminId': 7,
            if (b['loginType'] == 'ADMIN') 'plan': 'Professional',
          },
        };
      case '/company/selected':
        body = <String, Object?>{
          'success': true,
          'data': <Object?>[
            <String, Object?>{
              'company_guid': kGuid,
              'name': 'Rajlaxmi Traders',
              'starting_from': '2026-04-01',
            },
            <String, Object?>{
              'company_guid': 'co-2',
              'name': 'Other Co',
              'starting_from': null,
            },
          ],
        };
      case '/company/active':
        body = <String, Object?>{'success': true, 'company_guid': kGuid};
      // All companies of the admin, including one the agent registered but
      // has not synced yet (no row in /company/selected).
      case '/company':
        body = <String, Object?>{
          'success': true,
          'data': <Object?>[
            <String, Object?>{'company_guid': 'co-3', 'name': 'GI Apr 25-26'},
            <String, Object?>{
              'company_guid': kGuid,
              'name': 'Rajlaxmi Traders',
            },
            <String, Object?>{'company_guid': 'co-2', 'name': 'Other Co'},
          ],
        };
      case '/agent-status/sync-status':
        body = <String, Object?>{
          'success': true,
          'last_sync_at': lastSync,
          'sync_in_progress': false,
          ...syncExtra,
        };
      case '/users/me':
        body = <String, Object?>{
          'id': 7,
          'username': 'ravi',
          'email': 'ravi@x.in',
          'role': 'ADMIN',
          'company': null,
          'admin_email': 'ravi@x.in',
        };
      case '/ledger':
        body = <String, Object?>{
          'success': true,
          'data': <Object?>[
            <String, Object?>{
              'ledger_guid': 'L1',
              'name': 'Mehta Electricals',
              'parent_group': 'Sundry Debtors',
              'opening_balance': '-1200.50',
              'closing_balance': '-15000.00',
              'date': '2026-09-30T00:00:00.000Z',
            },
            <String, Object?>{
              'ledger_guid': 'L2',
              'name': 'Polycab Wires',
              'parent_group': 'Sundry Creditors',
              'opening_balance': '0',
              'closing_balance': '9000',
              'date': null,
            },
            <String, Object?>{
              'ledger_guid': 'L3',
              'name': 'HDFC Bank',
              'parent_group': 'Bank Accounts',
              'opening_balance': '0',
              'closing_balance': '-50000',
            },
            <String, Object?>{
              'ledger_guid': 'L4',
              'name': 'Rent A/c',
              'parent_group': 'Indirect Expenses',
              'opening_balance': '0',
              'closing_balance': '0',
            },
            ...extraLedgers,
          ],
        };
      case '/bill':
        body = <String, Object?>{
          'success': true,
          'data': <Object?>[
            // late by 13 days (due 20 Sep, today 3 Oct)
            <String, Object?>{
              'company_guid': kGuid,
              'bill_guid': 'B1',
              'ledger_guid': 'L1',
              'ledger_name': 'Mehta Electricals',
              'bill_name': 'S/101',
              'bill_amount': '12000.00',
              'pending_amount': '10000.50',
              'due_date': '2026-09-20T00:00:00.000Z',
              'bill_type': 'RECEIVABLE',
              'bill_date': null,
            },
            // due in 2 days
            <String, Object?>{
              'company_guid': kGuid,
              'bill_guid': 'B2',
              'ledger_guid': 'L1',
              'ledger_name': 'Mehta Electricals',
              'bill_name': 'S/102',
              'bill_amount': '5000',
              'pending_amount': '5000.00',
              'due_date': '2026-10-05T00:00:00.000Z',
              'bill_type': 'RECEIVABLE',
            },
            // payable, 45 days late
            <String, Object?>{
              'company_guid': kGuid,
              'bill_guid': 'B3',
              'ledger_guid': 'L2',
              'ledger_name': 'Polycab Wires',
              'bill_name': 'PW/9',
              'bill_amount': '9000',
              'pending_amount': '9000',
              'due_date': '2026-08-19T00:00:00.000Z',
              'bill_type': 'PAYABLE',
            },
            // settled → ignored
            <String, Object?>{
              'company_guid': kGuid,
              'bill_guid': 'B4',
              'ledger_guid': 'L1',
              'ledger_name': 'Mehta Electricals',
              'bill_name': 'S/90',
              'bill_amount': '700',
              'pending_amount': '0.00',
              'due_date': null,
              'bill_type': 'RECEIVABLE',
            },
            // other company → ignored
            <String, Object?>{
              'company_guid': 'co-2',
              'bill_guid': 'B5',
              'ledger_guid': 'X',
              'ledger_name': 'Other',
              'bill_name': 'O/1',
              'bill_amount': '99999',
              'pending_amount': '99999',
              'due_date': null,
              'bill_type': 'RECEIVABLE',
            },
          ],
        };
      case '/dashboard/summary':
        body = <String, Object?>{
          'receivables': '15000.50',
          'payables': '9000.00',
          'pending_bills': '3',
          'cleared_bills': '1',
        };
      case '/voucher-entry/paged':
        final Map<String, String> vq = r.url.queryParameters;
        final int page = int.parse(vq['page']!);
        final int limit = int.parse(vq['limit']!);
        if (limit > 200) violations.add('limit $limit > 200');
        // Month set (Home / month totals): the server filters by year +
        // month — page 1 = October rows, page 2 = one October row that
        // shifted across pages. Full history (no year/month): page 1 =
        // October rows, page 2 = September rows plus that duplicate.
        final bool monthQ = vq.containsKey('month');
        if (monthQ && (vq['year'] != '2026' || vq['month'] != '10')) {
          violations.add('month query ${r.url.query}');
        }
        body = <String, Object?>{
          'success': true,
          'data': page == 1
              ? <Object?>[
                  <String, Object?>{
                    'voucher_guid': 'V1',
                    'voucher_date': '2026-10-02T00:00:00.000Z',
                    'voucher_type': 'Sales',
                    'reference_no': 'S/101',
                    'amount': '-11800.00',
                    'is_active': true,
                    'party_name': 'Mehta Electricals',
                    'items': <Object?>[
                      <String, Object?>{
                        'item_name': 'Wire',
                        'quantity': '2',
                        'rate': '5000',
                        'amount': '10000',
                      },
                    ],
                  },
                  <String, Object?>{
                    'voucher_guid': 'V2',
                    'voucher_date': '2026-10-03T00:00:00.000Z',
                    'voucher_type': 'Receipt',
                    'reference_no': 'R/5',
                    'amount': '2500.25',
                    'is_active': true,
                    'party_name': 'Mehta Electricals',
                    'items': <Object?>[],
                  },
                  <String, Object?>{
                    'voucher_guid': 'V3',
                    'voucher_date': '2026-10-01T00:00:00.000Z',
                    'voucher_type': 'Sales Order',
                    'reference_no': 'SO/1',
                    'amount': '99999',
                    'is_active': true,
                    'party_name': 'X',
                    'items': <Object?>[],
                  },
                  <String, Object?>{
                    'voucher_guid': 'V4',
                    'voucher_date': '2026-10-01T00:00:00.000Z',
                    'voucher_type': 'Payment',
                    'reference_no': 'P/1',
                    'amount': '400',
                    'is_active': false,
                    'party_name': 'Y',
                    'items': <Object?>[],
                  },
                ]
              : <Object?>[
                  <String, Object?>{
                    'voucher_guid': 'V2',
                    'voucher_date': '2026-10-03T00:00:00.000Z',
                    'voucher_type': 'Receipt',
                    'reference_no': 'R/5',
                    'amount': '2500.25',
                    'is_active': true,
                    'party_name': 'Mehta Electricals',
                    'items': <Object?>[],
                  },
                  if (!monthQ)
                    <String, Object?>{
                      'voucher_guid': 'V9',
                      'voucher_date': '2026-09-29T00:00:00.000Z',
                      'voucher_type': 'Payment',
                      'reference_no': 'P/0',
                      'amount': '700',
                      'is_active': true,
                      'party_name': 'Polycab Wires',
                      'items': <Object?>[],
                    },
                ],
          'meta': <String, Object?>{
            // Like the server: COUNT(*) of the filter (type = ILIKE
            // '%type%'), deleted rows included.
            'total': monthQ ? 4 : historyCount(vq['type']),
            'page': page,
            'limit': limit,
            'hasMore': page == 1,
            'totalAmount': monthQ ? 0 : '${totalFor(vq['type'])}',
            'types': <Object?>['Payment', 'Receipt', 'Sales', 'Sales Order'],
            'years': <Object?>[],
          },
        };
      case '/inventory/mobile':
        body = <String, Object?>{
          'success': true,
          'items': <Object?>[
            <String, Object?>{
              'item_guid': 'I1',
              'name': 'Wire',
              'unit': 'Coil',
              // As the server returns Tally's export: stock held (a Dr
              // value) is negative; the server's rate = value ÷ qty.
              'closing_qty': 4.5,
              'closing_value': '-22500.00',
              'rate': '-5000.00',
              'opening_qty': 4,
              'opening_value': '-20000.00',
              'gst_rate': 18,
              'hsn_code': '8544',
            },
            <String, Object?>{
              'item_guid': 'I2',
              'name': 'Pipe',
              'unit': 'Nos',
              'closing_qty': 0,
              'closing_value': 0,
              'rate': 0,
              'gst_rate': null,
            },
          ],
        };
      case '/inventory':
        body = <String, Object?>{
          'success': true,
          'data': <Object?>[
            <String, Object?>{
              'id': 'I2',
              'name': 'Pipe',
              'opening': '5',
              'inward': '0',
              'outward': '0',
              'closing': '0',
            },
          ],
        };
      case '/api/mobile-sync-queue/activity':
        body = <Object?>[
          <String, Object?>{
            'id': 31,
            'entity_type': 'VOUCHER',
            'action': 'CREATE',
            'status': 'failed',
            'error': 'Tally closed',
            'created_at': '2026-10-03T05:00:00.000Z',
            'processed_at': null,
            'payload': <String, Object?>{
              'voucher_type': 'Receipt',
              'voucher_no': 'R/6',
              'party_name': 'Mehta Electricals',
              'amount_received': 1500,
              'voucher_date': '2026-10-03',
            },
          },
          <String, Object?>{
            'id': 30,
            'status': 'success',
            'created_at': '2026-10-02T05:00:00.000Z',
            'payload': <String, Object?>{
              'voucher_type': 'Journal',
              'voucher_no': 'J/1',
              'ledger_entries': <Object?>[
                <String, Object?>{
                  'ledger_name': 'Rent A/c',
                  'amount': 800,
                  'is_debit': true,
                },
                <String, Object?>{
                  'ledger_name': 'HDFC Bank',
                  'amount': 800,
                  'is_debit': false,
                },
              ],
            },
          },
        ];
      case '/api/mobile/notifications':
        body = <String, Object?>{
          'success': true,
          'notifications': <Object?>[
            <String, Object?>{
              'id': 4,
              'title': 'Entry failed',
              'message': 'R/6 failed',
              'is_read': false,
              'created_at': '2026-10-03T05:00:00.000Z',
              'type': 'entry_failed',
            },
            ...moreNotifs,
          ],
        };
      case '/api/mobile/notifications/config':
        body = <String, Object?>{
          'success': true,
          'config': <String, Object?>{
            'sync_completed': false,
            'create_entry': true,
          },
        };
      case '/users' when r.method == 'POST':
        // routes/users.js: email + password required; username = part of
        // the email before '@'; duplicate email → 400.
        final Map<String, Object?> b =
            jsonDecode(r.body) as Map<String, Object?>;
        if (b.keys.toSet().difference(<String>{
          'email',
          'password',
        }).isNotEmpty) {
          violations.add('POST /users extra fields: ${b.keys}');
        }
        final String em = '${b['email'] ?? ''}'.toLowerCase();
        if (em.isEmpty || '${b['password'] ?? ''}'.isEmpty) {
          return http.Response(
            '{"message":"Email and password required"}',
            400,
          );
        }
        if (<String>['ravi@x.in', 'asha@x.in'].contains(em) ||
            createdUsers.any((Map<String, Object?> u) => u['email'] == em)) {
          return http.Response('{"message":"User already exists"}', 400);
        }
        final Map<String, Object?> u = <String, Object?>{
          'id': 20 + createdUsers.length,
          'username': em.split('@').first,
          'email': em,
          'role': 'USER',
        };
        createdUsers.add(u);
        body = <String, Object?>{'user': u};
      case '/users':
        body = <Object?>[
          ...createdUsers,
          <String, Object?>{
            'id': 7,
            'username': 'ravi',
            'email': 'ravi@x.in',
            'role': 'ADMIN',
          },
          if (!deletedUsers.contains('9'))
            <String, Object?>{
              'id': 9,
              'username': 'asha',
              'email': 'asha@x.in',
              'role': 'USER',
              // Stored layout permissions (other keys must survive saves).
              'ledger_permissions': <String, Object?>{
                'columns': <String, Object?>{'dueDays': false},
                'note': 'web',
              },
              'vouchers_permissions': <String, Object?>{
                'columns': <String, Object?>{},
              },
              'orders_permissions': null,
              'inventory_permissions': <String, Object?>{
                'columns': <String, Object?>{'rate': false, 'legacyKey': true},
              },
            },
        ];
      case '/users/9/ledgers':
        body = <Object?>[
          <String, Object?>{'ledger_guid': 'L1'},
          // Another company's ledger: not listed here, kept on save.
          <String, Object?>{'ledger_guid': 'OTHER-CO'},
        ];
      case '/voucher-entry/user-vouchers/9':
        body = <String, Object?>{
          'vouchers': <Object?>['V1'],
        };
      case '/orders':
        body = <String, Object?>{
          'success': true,
          'data': <Object?>[
            <String, Object?>{
              'id': 'O1',
              'type': 'Sales Order',
              'date': '2026-10-01T00:00:00.000Z',
              'customer': 'Mehta Electricals',
              'amount': '5000',
              'due_date': null,
              'status': 'Pending',
            },
          ],
        };
      case '/orders/user-orders/9':
        body = <String, Object?>{'orders': <Object?>[]};
      case '/inventory/user-inventory/9':
        body = <Object?>[
          <String, Object?>{'item_name': 'Wire'},
        ];
      case '/ledger/user-ledgers':
      case '/voucher-entry/user-vouchers':
      case '/orders/user-orders':
      case '/inventory/user-inventory':
      case '/send-invite':
        body = <String, Object?>{'success': true};
      case '/api/mobile-voucher-command/contra/create' when contraMissing:
        return http.Response('Cannot POST', 404);
      case '/api/mobile-voucher-command/receipt/create':
      case '/api/mobile-voucher-command/journal/create':
      case '/api/mobile-voucher-command/contra/create':
      case '/api/mobile-voucher-command/create':
        body = <String, Object?>{
          'success': true,
          'command_id': 55,
          'voucher_guid': 'g',
          'status': 'QUEUED',
        };
      case '/api/mobile-voucher-command/edit' when editMissing:
        return http.Response('Cannot POST', 404);
      case '/api/mobile-voucher-command/edit':
        body = <String, Object?>{
          'success': true,
          'edited': true,
          'command_id': 56,
          'status': 'QUEUED',
        };
      case '/api/mobile-sync-queue/30/retry':
        // Already in Tally: refused (no second voucher).
        return http.Response(
          jsonEncode(<String, Object?>{
            'success': false,
            'code': 'done',
            'message': 'This entry is already in Tally.',
          }),
          409,
          headers: <String, String>{'content-type': 'application/json'},
        );
      case '/api/mobile-sync-queue/31/retry':
        body = <String, Object?>{
          'success': true,
          'status': 'QUEUED',
          'retry_count': 1,
        };
      default:
        if (p.startsWith('/api/mobile/notifications/') && p.endsWith('/read')) {
          body = <String, Object?>{'success': true};
        } else if (p.startsWith('/users/') &&
            p.endsWith('-permissions') &&
            r.method == 'PUT') {
          body = <String, Object?>{'success': true};
        } else if (p.startsWith('/voucher-entry/ledger/') ||
            p.startsWith('/ledger-items/ledger/') ||
            p.startsWith('/bill/ledger/')) {
          // Party detail: no entries / items / bills for this ledger.
          body = <String, Object?>{'success': true, 'data': <Object?>[]};
        } else if (p.startsWith('/users/') && r.method == 'DELETE') {
          deletedUsers.add(p.substring('/users/'.length));
          body = <String, Object?>{'success': true};
        } else if (p.startsWith('/voucher-entry/') && r.method == 'GET') {
          // One voucher's ledger lines (the invoice screen): none here.
          body = <String, Object?>{'success': true, 'data': <Object?>[]};
        } else {
          return http.Response('{"message":"Unauthorized"}', 401);
        }
    }
    return http.Response(
      jsonEncode(body),
      200,
      headers: <String, String>{'content-type': 'application/json'},
    );
  });

  http.Response _json(int status, Object body) => http.Response(
    jsonEncode(body),
    status,
    headers: <String, String>{'content-type': 'application/json'},
  );

  /// Official Tally reports, answering in the backend's shapes.
  http.Response _tallyReports(http.Request r, String p) {
    if (tallyReportsMissing) {
      return http.Response(
        '<!DOCTYPE html><html><body><pre>Cannot GET $p</pre></body></html>',
        404,
        headers: <String, String>{'content-type': 'text/html'},
      );
    }
    if (!finAllowed) {
      return _json(403, <String, Object?>{
        'success': false,
        'message': 'Ask your admin for access to financial reports.',
        'code': 'no_access',
      });
    }
    const List<String> keys = <String>[
      'trial_balance',
      'profit_loss',
      'balance_sheet',
      'cash_flow',
    ];
    List<Map<String, Object?>> of(String k) =>
        List<Map<String, Object?>>.of(
          tallyReports[k] ?? const <Map<String, Object?>>[],
        )..sort(
          (Map<String, Object?> a, Map<String, Object?> b) =>
              '${b['to']}'.compareTo('${a['to']}'),
        );
    if (p == '/api/tally-reports/periods') {
      return _json(200, <String, Object?>{
        'success': true,
        'company': 'Rajlaxmi Traders',
        'reports': <String, Object?>{
          for (final String k in keys)
            k: <Object?>[
              for (final Map<String, Object?> x in of(k))
                <String, Object?>{
                  'from': x['from'],
                  'to': x['to'],
                  'fetched_at': '2026-10-03T08:30:00.000Z',
                },
            ],
        },
      });
    }
    final String report = p.substring('/api/tally-reports/'.length);
    final String? from = r.url.queryParameters['from'];
    final String? to = r.url.queryParameters['to'];
    final Map<String, Object?>? hit = of(report)
        .where(
          (Map<String, Object?> x) =>
              from == null || (x['from'] == from && x['to'] == to),
        )
        .firstOrNull;
    if (hit == null) {
      return _json(404, <String, Object?>{
        'success': false,
        'message': 'No figures from Tally for this period yet.',
        'code': 'not_fetched',
      });
    }
    final List<Object?> rows = hit['rows']! as List<Object?>;
    Map<String, Object?> checks = <String, Object?>{};
    if (report == 'trial_balance') {
      num dr = 0, cr = 0;
      for (final Object? x in rows) {
        final num c = ((x! as Map<String, Object?>)['closing'] ?? 0) as num;
        if (c < 0) {
          dr += -c;
        } else {
          cr += c;
        }
      }
      checks = <String, Object?>{
        'debit': dr,
        'credit': cr,
        'difference': (dr - cr).abs(),
        'balanced': (dr - cr).abs() < 1,
      };
    } else if (report != 'cash_flow') {
      num pos = 0, neg = 0;
      for (final Object? x in rows) {
        final Map<String, Object?> a =
            (x! as Map<String, Object?>)['amounts']! as Map<String, Object?>;
        final num v = (a['BSMAINAMT'] ?? a['PLSUBAMT'] ?? 0) as num;
        if (v > 0) {
          pos += v;
        } else {
          neg += -v;
        }
      }
      checks = <String, Object?>{
        'credit_side': pos,
        'debit_side': neg,
        'difference': (pos - neg).abs(),
        'balanced': (pos - neg).abs() < 1,
      };
    }
    return _json(200, <String, Object?>{
      'success': true,
      'data': <String, Object?>{
        'report': report,
        'company': 'Rajlaxmi Traders',
        'period_from': hit['from'],
        'period_to': hit['to'],
        'fetched_at': '2026-10-03T08:30:00.000Z',
        'fetch_seconds': 12.4,
        'source': 'tally',
        'rows': rows,
        'checks': checks,
      },
    });
  }

  /// The cash flow forecast API, answering in the backend's shapes (two
  /// weeks with figures, the rest empty; a shortfall in week 2).
  http.Response _cashflow(http.Request r, String p) {
    if (cashflowMissing) {
      return http.Response(
        '<!DOCTYPE html><html><body><pre>Cannot GET $p</pre></body></html>',
        404,
        headers: <String, String>{'content-type': 'text/html'},
      );
    }
    if (!finAllowed) {
      return _json(403, <String, Object?>{
        'success': false,
        'message': 'Ask your admin for access to financial reports.',
        'code': 'no_access',
      });
    }
    final Map<String, String> q = Map<String, String>.of(r.url.queryParameters);
    cashflowQueries.add(<String, String>{'path': p, ...q});
    final bool adjusted = q['mode'] != 'due';
    final num? opening = cashflowNoOpening ? null : 21000;
    final DateTime w0 = DateTime(2026, 9, 28);
    final List<Map<String, Object?>> weeks = <Map<String, Object?>>[];
    num? run = opening;
    for (int i = 0; i < 13; i++) {
      final DateTime s = w0.add(Duration(days: 7 * i));
      final num inflow = i == 0 ? 750 : (i == (adjusted ? 2 : 1) ? 4000 : 0);
      final num outflow = i == 1 ? 25000 : 0;
      final num? closing = run == null ? null : run + inflow - outflow;
      weeks.add(<String, Object?>{
        'start': ymd(s),
        'end': ymd(s.add(const Duration(days: 6))),
        'opening': run,
        'inflow': inflow,
        'outflow': outflow,
        'net': inflow - outflow,
        'closing': closing,
        'inflow_bills': inflow > 0 ? 1 : 0,
        'outflow_bills': outflow > 0 ? 1 : 0,
        'overdue_inflow': i == 0 ? 750 : 0,
        'shortfall': closing != null && closing < 0,
      });
      run = closing;
    }
    if (p == '/api/cashflow/week') {
      final Map<String, Object?>? w = weeks
          .where((Map<String, Object?> x) => x['start'] == q['start'])
          .firstOrNull;
      if (w == null) {
        return _json(404, <String, Object?>{
          'success': false,
          'message': 'That week is not in the forecast.',
          'code': 'no_week',
        });
      }
      return _json(200, <String, Object?>{
        'success': true,
        'data': <String, Object?>{
          ...w,
          'inflows': <Object?>[
            if ((w['inflow']! as num) > 0)
              <String, Object?>{
                'party': 'Mehta Electricals',
                'bill': 'S/9',
                'due': '2026-10-02',
                'expected': adjusted ? '2026-10-14' : '2026-10-02',
                'amount': w['inflow'],
                'delay_days': adjusted ? 12 : 0,
                'delay_source': adjusted ? 'party' : 'due',
                'overdue': false,
              },
          ],
          'outflows': <Object?>[
            if ((w['outflow']! as num) > 0)
              <String, Object?>{
                'party': 'Polycab Wires',
                'bill': 'P/3',
                'due': '2026-10-06',
                'expected': '2026-10-06',
                'amount': w['outflow'],
                'overdue': false,
              },
          ],
        },
      });
    }
    return _json(200, <String, Object?>{
      'success': true,
      'data': <String, Object?>{
        'company': 'Rajlaxmi Traders',
        'as_on': '2026-10-03',
        'generated_at': '2026-10-03T06:00:00.000Z',
        'mode': adjusted ? 'adjusted' : 'due',
        'first_week': '2026-09-28',
        'weeks': weeks,
        'totals': <String, Object?>{
          'inflow': 4750,
          'outflow': 25000,
          'net': -20250,
        },
        'later': <String, Object?>{
          'inflow': 300,
          'outflow': 0,
          'inflow_bills': 1,
          'outflow_bills': 0,
        },
        'doubtful': <String, Object?>{
          'amount': q['doubtful'] == '1' ? 0 : 900,
          'bills': q['doubtful'] == '1' ? 0 : 1,
          'days': 90,
        },
        'no_due_date': <String, Object?>{'amount': 0, 'bills': 0},
        'shortfall_week': opening == null ? null : '2026-10-05',
        'opening': opening == null
            ? <String, Object?>{
                'amount': null,
                'reason': 'financial_not_synced',
              }
            : <String, Object?>{
                'amount': opening,
                'based_on': '2026-09-30',
                'accounts': <Object?>[
                  <String, Object?>{
                    'name': 'HDFC Bank',
                    'group': 'Bank Accounts',
                    'balance': 19500,
                  },
                  <String, Object?>{
                    'name': 'Cash',
                    'group': 'Cash-in-Hand',
                    'balance': 1500,
                  },
                ],
              },
        'advances_checked': true,
        'advances': <String, Object?>{
          'received': <String, Object?>{'amount': 600, 'bills': 1},
          'paid': <String, Object?>{'amount': 0, 'bills': 0},
        },
        'delays': <String, Object?>{
          'method': 'mixed',
          'parties_exact': 1,
          'window_days': 365,
          'company_median': 9,
          'company_bills': 41,
          'company_on_time_pct': 38,
          'parties_with_history': 12,
        },
        'top_receivables': <Object?>[
          <String, Object?>{
            'party': 'Mehta Electricals',
            'amount': 4000,
            'delay_days': 12,
            'delay_source': 'party',
            'history_bills': 18,
            'on_time_pct': 20,
            'method': 'alloc',
          },
          <String, Object?>{
            'party': 'New Customer',
            'amount': 750,
            'delay_days': 9,
            'delay_source': 'company',
            'history_bills': 0,
            'on_time_pct': null,
          },
        ],
        'counts': <String, Object?>{'receivable_bills': 3, 'payable_bills': 1},
      },
    });
  }

  /// The financial statements API, answering in the backend's shapes.
  http.Response _sales(http.Request r) {
    if (salesMissing) {
      return http.Response(
        '<!DOCTYPE html><html><body><pre>Cannot GET /api/analytics/sales</pre></body></html>',
        404,
        headers: <String, String>{'content-type': 'text/html'},
      );
    }
    salesQueries.add(Map<String, String>.of(r.url.queryParameters));
    final String from = r.url.queryParameters['from'] ?? '';
    final String to = r.url.queryParameters['to'] ?? '';
    final bool byDay =
        DateTime.parse(to).difference(DateTime.parse(from)).inDays <= 62;
    return _json(200, <String, Object?>{
      'success': true,
      'data': <String, Object?>{
        'company': 'Gupta Industries',
        'from': from,
        'to': to,
        'kpis': <String, Object?>{
          'sales': salesEmpty ? 0 : 20060,
          'invoices': salesEmpty ? 0 : 3,
          'avg_invoice': salesEmpty ? 0 : 6686.67,
          'customers': salesEmpty ? 0 : 2,
          'returns': salesEmpty ? 0 : 1180,
          'returns_count': salesEmpty ? 0 : 1,
          'net_sales': salesEmpty ? 0 : 18880,
          'prev_sales': 10000,
          'growth_pct': salesEmpty ? -100 : 100.6,
        },
        'trend': <String, Object?>{
          'unit': byDay ? 'day' : 'month',
          'points': <Object?>[
            for (int i = 1; i <= (byDay ? 30 : 12); i++)
              <String, Object?>{
                'key': byDay
                    ? '2026-09-${i.toString().padLeft(2, '0')}'
                    : '2026-${i.toString().padLeft(2, '0')}',
                'sales': salesEmpty
                    ? 0
                    : (i == 5 ? 11800 : (i == 20 ? 5900 : 0)),
                'invoices': i == 5 || i == 20 ? 1 : 0,
              },
          ],
        },
        'top_customers': salesEmpty
            ? <Object?>[]
            : <Object?>[
                <String, Object?>{
                  'party':
                      'Mehta Electricals with a long name for small phones',
                  'sales': 14160,
                  'invoices': 2,
                  'share': 70.6,
                },
                <String, Object?>{
                  'party': 'Gupta Stores',
                  'sales': 5900,
                  'invoices': 1,
                  'share': 29.4,
                },
              ],
        'top_items': salesEmpty
            ? <Object?>[]
            : <Object?>[
                <String, Object?>{
                  'item': 'Copper Wire 1.5mm',
                  'amount': 8000,
                  'qty': 10,
                  'invoices': 1,
                },
                <String, Object?>{
                  'item': 'Switch 6A',
                  'amount': 7000,
                  'qty': 70,
                  'invoices': 2,
                },
              ],
        'top_items_qty': salesEmpty
            ? <Object?>[]
            : <Object?>[
                <String, Object?>{
                  'item': 'Switch 6A',
                  'amount': 7000,
                  'qty': 70,
                  'invoices': 2,
                },
                <String, Object?>{
                  'item': 'Copper Wire 1.5mm',
                  'amount': 8000,
                  'qty': 10,
                  'invoices': 1,
                },
              ],
        'item_groups': salesEmpty
            ? <Object?>[]
            : <Object?>[
                <String, Object?>{'group': 'Switchgear', 'amount': 9000},
                <String, Object?>{'group': 'Wires', 'amount': 8000},
              ],
        'customers': <String, Object?>{
          'new': salesEmpty ? 0 : 1,
          'repeat': salesEmpty ? 0 : 1,
        },
      },
    });
  }

  /// The e-invoice API: the list (filtered by status / dates) and one
  /// invoice with its signed QR.
  http.Response _einvoice(http.Request r, String p) {
    final Map<String, String> q = r.url.queryParameters;
    einvCalls.add(<String, Object?>{'path': p, ...q});
    if (einvMissing) return http.Response('Cannot GET $p', 404);
    if (p == '/api/einvoice/list') {
      final String st = q['status'] ?? 'all';
      final String from = q['from'] ?? '0000', to = q['to'] ?? '9999';
      final List<Map<String, Object?>> inRange = <Map<String, Object?>>[
        for (final Map<String, Object?> x in einvRows)
          if ('${x['date']}'.compareTo(from) >= 0 &&
              '${x['date']}'.compareTo(to) <= 0)
            x,
      ];
      int n(String s) =>
          inRange.where((Map<String, Object?> x) => x['status'] == s).length;
      int a(String s) => inRange
          .where(
            (Map<String, Object?> x) =>
                (x['alerts']! as List<Object?>).contains(s),
          )
          .length;
      return _json(200, <String, Object?>{
        'success': true,
        'company': 'Rajlaxmi Solutions',
        'from': from,
        'to': to,
        'status': st,
        'summary': <String, Object?>{
          'total': inRange.length,
          'done': n('done'),
          'pending': n('pending'),
          'cancelled': n('cancelled'),
          'not_needed': n('not_needed'),
          'overdue': a('overdue'),
          'due_soon': a('due_soon'),
          'late_report': a('late_report'),
          'ack_before_invoice': a('ack_before_invoice'),
        },
        'rows': <Object?>[
          for (final Map<String, Object?> x in inRange)
            if (st == 'all' ||
                (st == 'alerts'
                    ? (x['alerts']! as List<Object?>).isNotEmpty
                    : x['status'] == st))
              <String, Object?>{...x}..remove('signed_qr'),
        ],
        'truncated': false,
      });
    }
    if (p.startsWith('/api/einvoice/voucher/')) {
      final String g = Uri.decodeComponent(
        p.substring('/api/einvoice/voucher/'.length),
      );
      final Map<String, Object?>? x = einvRows
          .where((Map<String, Object?> e) => e['voucher_guid'] == g)
          .firstOrNull;
      if (x == null) {
        return _json(404, <String, Object?>{
          'success': false,
          'code': 'not_found',
          'message': 'No e-invoice details for this voucher',
        });
      }
      return _json(200, <String, Object?>{'success': true, 'invoice': x});
    }
    return _json(404, <String, Object?>{
      'success': false,
      'message': 'Not found',
    });
  }

  /// The leave API as the backend implements it (one account; the login is
  /// user 7; team members 9 "asha" and 10; days skip weekly off and
  /// holidays; balances = quota − approved − pending, no carry forward).
  http.Response _leave(http.Request r, String p) {
    final Map<String, Object?> body = r.body.isEmpty
        ? <String, Object?>{}
        : jsonDecode(r.body) as Map<String, Object?>;
    final Map<String, String> q = r.url.queryParameters;
    leaveCalls.add(<String, Object?>{
      'path': p,
      'method': r.method,
      ...q,
      ...body,
    });
    if (leaveMissing) return http.Response('Cannot GET $p', 404);
    http.Response err(int status, String code, String message) => _json(
      status,
      <String, Object?>{'success': false, 'code': code, 'message': message},
    );
    String day(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    DateTime dt(String s) => DateTime.parse(s);
    final String today = day(attNow());
    final bool admin = loginType == 'ADMIN';
    final int sm = leaveSettings['year_start_month']! as int;
    final List<int> off = (leaveSettings['weekly_off']! as List<Object?>)
        .cast<int>();
    (String, String, String) yearOf(String d) {
      final DateTime x = dt(d);
      final int y = x.month >= sm ? x.year : x.year - 1;
      return (
        day(DateTime(y, sm)),
        day(DateTime(y + 1, sm, 0)),
        sm == 1 ? '$y' : '$y-${(y + 1) % 100}',
      );
    }

    bool holiday(String d) =>
        leaveHolidays.any((Map<String, Object?> h) => h['date'] == d);
    bool working(String d) => !off.contains(dt(d).weekday % 7) && !holiday(d);
    Map<String, Object?> reqOut(Map<String, Object?> x) => <String, Object?>{
      ...x,
      'type_name': leaveTypes.firstWhere(
        (Map<String, Object?> t) => t['id'] == x['type_id'],
      )['name'],
      'username': switch (x['user_id']) {
        9 => 'asha',
        10 => 'vik',
        _ => 'ravi',
      },
    };
    Map<String, Object?>? reqById(int id) =>
        leaveReqs.where((Map<String, Object?> x) => x['id'] == id).firstOrNull;
    List<Object?> holidaysIn(String a, String b) => <Object?>[
      for (final Map<String, Object?> h in leaveHolidays)
        if ('${h['date']}'.compareTo(a) >= 0 &&
            '${h['date']}'.compareTo(b) <= 0)
          h,
    ];
    Map<String, Object?> yearData(int user, String date) {
      final (String a, String b, String label) = yearOf(date);
      final List<Map<String, Object?>> mine = <Map<String, Object?>>[
        for (final Map<String, Object?> x in leaveReqs)
          if (x['user_id'] == user &&
              '${x['to']}'.compareTo(a) >= 0 &&
              '${x['from']}'.compareTo(b) <= 0)
            x,
      ];
      num sum(int type, String status) => mine
          .where(
            (Map<String, Object?> x) =>
                x['type_id'] == type && x['status'] == status,
          )
          .fold<num>(
            0,
            (num s, Map<String, Object?> x) => s + (x['days']! as num),
          );
      return <String, Object?>{
        'year': <String, Object?>{'from': a, 'to': b, 'label': label},
        'balances': <Object?>[
          for (final Map<String, Object?> t in leaveTypes)
            if (t['active'] == true)
              <String, Object?>{
                'type_id': t['id'],
                'name': t['name'],
                'paid': t['paid'],
                'active': true,
                'quota': t['yearly_quota'],
                'carried': 0,
                'entitled': t['yearly_quota'],
                'used': sum(t['id']! as int, 'approved'),
                'pending': sum(t['id']! as int, 'pending'),
                'available': t['yearly_quota'] == null
                    ? null
                    : (t['yearly_quota']! as num) -
                          sum(t['id']! as int, 'approved') -
                          sum(t['id']! as int, 'pending'),
              },
        ],
        'requests': mine.reversed.map(reqOut).toList(),
        'holidays': holidaysIn(a, b),
      };
    }

    final RegExpMatch? decide = RegExp(
      r'^/api/leave/requests/(\d+)/(approve|reject|cancel)$',
    ).firstMatch(p);
    final RegExpMatch? member = RegExp(
      r'^/api/leave/team/(\d+)$',
    ).firstMatch(p);
    final RegExpMatch? type = RegExp(r'^/api/leave/types/(\d+)$').firstMatch(p);
    final RegExpMatch? hol = RegExp(
      r'^/api/leave/holidays/([\d-]+)$',
    ).firstMatch(p);

    if (p == '/api/leave/me') {
      final bool on = leaveSettings['enabled'] == true;
      final Map<String, Object?> base = <String, Object?>{
        'success': true,
        'enabled': on,
        'is_admin': admin,
        'settings': leaveSettings,
      };
      if (!on || admin) return _json(200, base);
      final Map<String, Object?>? todayLeave = leaveReqs
          .where(
            (Map<String, Object?> x) =>
                x['user_id'] == 7 &&
                x['status'] == 'approved' &&
                '${x['from']}'.compareTo(today) <= 0 &&
                '${x['to']}'.compareTo(today) >= 0,
          )
          .firstOrNull;
      return _json(200, <String, Object?>{
        ...base,
        ...yearData(7, q['date'] ?? today),
        'today': <String, Object?>{
          'date': today,
          'kind': holiday(today)
              ? 'holiday'
              : (off.contains(dt(today).weekday % 7)
                    ? 'weekly_off'
                    : 'working'),
          'leave': todayLeave == null ? null : reqOut(todayLeave),
        },
      });
    }
    if (p == '/api/leave/requests' && r.method == 'POST') {
      if (admin) {
        return err(
          403,
          'not_on_team',
          'Leave is applied by team members; the admin approves it.',
        );
      }
      if (leaveSettings['enabled'] != true) {
        return err(
          403,
          'leave_off',
          'Leave management is off for this account.',
        );
      }
      final String? key = body['idempotency_key'] as String?;
      final Map<String, Object?>? again = key == null
          ? null
          : leaveReqs
                .where((Map<String, Object?> x) => x['key'] == key)
                .firstOrNull;
      if (again != null) {
        return _json(200, <String, Object?>{
          'success': true,
          'replayed': true,
          'request': reqOut(again),
        });
      }
      final String a = '${body['from']}', b = '${body['to'] ?? body['from']}';
      final String? half = body['half_day'] as String?;
      num days = 0;
      if (half != null) {
        days = working(a) ? .5 : 0;
      } else {
        for (
          DateTime d = dt(a);
          !d.isAfter(dt(b));
          d = DateTime(d.year, d.month, d.day + 1)
        ) {
          if (working(day(d))) days += 1;
        }
      }
      if (days == 0) {
        return err(
          400,
          'no_working_days',
          'These dates are all weekly off or holidays',
        );
      }
      final Map<String, Object?>? clash = leaveReqs
          .where(
            (Map<String, Object?> x) =>
                x['user_id'] == 7 &&
                (x['status'] == 'pending' || x['status'] == 'approved') &&
                '${x['from']}'.compareTo(b) <= 0 &&
                a.compareTo('${x['to']}') <= 0 &&
                !(half != null &&
                    x['half_day'] != null &&
                    x['half_day'] != half),
          )
          .firstOrNull;
      if (clash != null) {
        return err(
          409,
          'overlap',
          'You already have ${clash['status']} leave from ${clash['from']} to ${clash['to']}',
        );
      }
      final Map<String, Object?> bal =
          (yearData(7, a)['balances']! as List<Object?>)
              .cast<Map<String, Object?>>()
              .firstWhere(
                (Map<String, Object?> x) => x['type_id'] == body['type_id'],
              );
      if (bal['available'] != null && days > (bal['available']! as num)) {
        return err(
          409,
          'insufficient_balance',
          'Only ${bal['available']} day(s) of ${bal['name']} left in ${yearOf(a).$3}',
        );
      }
      final Map<String, Object?> x = <String, Object?>{
        'id': leaveReqs.length + 1,
        'user_id': 7,
        'type_id': body['type_id'],
        'from': a,
        'to': b,
        'half_day': half,
        'days': days,
        'reason': body['reason'],
        'status': 'pending',
        'decision_note': null,
        'created_at': attNow().toUtc().toIso8601String(),
        'key': key,
      };
      leaveReqs.add(x);
      return _json(201, <String, Object?>{
        'success': true,
        'request': reqOut(x),
      });
    }
    if (decide != null) {
      final Map<String, Object?>? x = reqById(int.parse(decide.group(1)!));
      final String action = decide.group(2)!;
      if (action != 'cancel' && !admin) {
        return err(403, 'forbidden', 'Admin access required');
      }
      if (x == null || (!admin && x['user_id'] != 7)) {
        return err(404, 'not_found', 'Leave request not found');
      }
      final List<String> allowed = action == 'cancel'
          ? (admin ? <String>['pending', 'approved'] : <String>['pending'])
          : <String>['pending'];
      if (!allowed.contains(x['status'])) {
        return err(
          409,
          'not_pending',
          'This request is already ${x['status']}',
        );
      }
      x['status'] = switch (action) {
        'approve' => 'approved',
        'reject' => 'rejected',
        _ => 'cancelled',
      };
      x['decision_note'] = body['note'] ?? x['decision_note'];
      return _json(200, <String, Object?>{
        'success': true,
        'request': reqOut(x),
      });
    }
    if (p == '/api/leave/requests') {
      if (!admin) return err(403, 'forbidden', 'Admin access required');
      final String status = q['status'] ?? 'pending';
      return _json(200, <String, Object?>{
        'success': true,
        'status': status,
        'requests': <Object?>[
          for (final Map<String, Object?> x in leaveReqs)
            if (status == 'all' || x['status'] == status) reqOut(x),
        ],
      });
    }
    if (member != null) {
      if (!admin) return err(403, 'forbidden', 'Admin access required');
      final int id = int.parse(member.group(1)!);
      if (id != 9 && id != 10) {
        return err(404, 'not_found', 'Team member not found');
      }
      return _json(200, <String, Object?>{
        'success': true,
        'member': <String, Object?>{
          'user_id': id,
          'username': id == 9 ? 'asha' : 'vik',
        },
        'settings': leaveSettings,
        ...yearData(id, q['date'] ?? today),
      });
    }
    if (p == '/api/leave/calendar') {
      final String a = q['from'] ?? today, b = q['to'] ?? today;
      return _json(200, <String, Object?>{
        'success': true,
        'from': a,
        'to': b,
        'weekly_off': off,
        'holidays': holidaysIn(a, b),
        'leaves': <Object?>[
          for (final Map<String, Object?> x in leaveReqs)
            if (x['status'] == 'approved' &&
                (admin || x['user_id'] == 7) &&
                '${x['to']}'.compareTo(a) >= 0 &&
                '${x['from']}'.compareTo(b) <= 0)
              reqOut(x),
        ],
      });
    }
    // Leave settings: the admin's.
    if (!admin) return err(403, 'forbidden', 'Admin access required');
    if (p == '/api/leave/settings' && r.method == 'GET') {
      final (String a, String b, String label) = yearOf(q['date'] ?? today);
      return _json(200, <String, Object?>{
        'success': true,
        'settings': leaveSettings,
        'year': <String, Object?>{'from': a, 'to': b, 'label': label},
        'types': leaveTypes,
        'holidays': holidaysIn(a, b),
      });
    }
    if (p == '/api/leave/settings' && r.method == 'PUT') {
      final List<Object?>? w = body['weekly_off'] as List<Object?>?;
      if (w != null && w.length > 6) {
        return err(
          400,
          'bad',
          'At least one day of the week must be a working day',
        );
      }
      leaveSettings = <String, Object?>{...leaveSettings, ...body};
      return _json(200, <String, Object?>{
        'success': true,
        'settings': leaveSettings,
      });
    }
    if (p == '/api/leave/types/defaults') {
      if (leaveTypes.isNotEmpty) {
        return err(409, 'types_exist', 'Leave types are already set up');
      }
      final bool was = leaveSettings['enabled'] == true;
      leaveSetUp();
      leaveHolidays.removeLast();
      leaveSettings['enabled'] = was;
      return _json(201, <String, Object?>{
        'success': true,
        'types': leaveTypes,
      });
    }
    if (p == '/api/leave/types' || type != null) {
      final String name = '${body['name'] ?? ''}'.trim();
      final int? id = type == null ? null : int.parse(type.group(1)!);
      if (leaveTypes.any(
        (Map<String, Object?> t) =>
            t['id'] != id && '${t['name']}'.toLowerCase() == name.toLowerCase(),
      )) {
        return err(409, 'name_taken', 'A leave type with this name exists');
      }
      if (id == null) {
        final Map<String, Object?> t = <String, Object?>{
          'id': leaveTypes.length + 1,
          'active': true,
          ...body,
        };
        leaveTypes.add(t);
        return _json(201, <String, Object?>{'success': true, 'type': t});
      }
      final Map<String, Object?> t = leaveTypes.firstWhere(
        (Map<String, Object?> x) => x['id'] == id,
      );
      t.addAll(body);
      return _json(200, <String, Object?>{'success': true, 'type': t});
    }
    if (p == '/api/leave/holidays' && r.method == 'POST') {
      leaveHolidays
        ..removeWhere((Map<String, Object?> h) => h['date'] == body['date'])
        ..add(<String, Object?>{'date': body['date'], 'name': body['name']})
        ..sort(
          (Map<String, Object?> a, Map<String, Object?> b) =>
              '${a['date']}'.compareTo('${b['date']}'),
        );
      return _json(201, <String, Object?>{'success': true});
    }
    if (hol != null && r.method == 'DELETE') {
      final int before = leaveHolidays.length;
      leaveHolidays.removeWhere(
        (Map<String, Object?> h) => h['date'] == hol.group(1),
      );
      if (leaveHolidays.length == before) {
        return err(404, 'not_found', 'Holiday not found');
      }
      return _json(200, <String, Object?>{'success': true});
    }
    return err(404, 'not_found', 'Not found');
  }

  /// The attendance API as the backend implements it (one account; the
  /// login is user 7; team member 9 "asha" has a session for the admin view).
  http.Response _attendance(http.Request r, String p) {
    final Map<String, Object?> body = r.body.isEmpty
        ? <String, Object?>{}
        : jsonDecode(r.body) as Map<String, Object?>;
    attRequests.add(<String, Object?>{
      'path': p,
      'method': r.method,
      ...r.url.queryParameters,
      ...body,
    });
    if (attMissing) {
      return http.Response('Cannot GET $p', 404);
    }
    final DateTime now = attNow();
    String day(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final String today = day(now);
    final bool admin = loginType == 'ADMIN';
    Map<String, Object?> out(Map<String, Object?> s) {
      final DateTime a = s['check_in_at']! as DateTime;
      final DateTime? b = s['check_out_at'] as DateTime?;
      return <String, Object?>{
        'id': s['id'],
        'work_date': s['work_date'],
        'check_in_at': a.toUtc().toIso8601String(),
        'check_out_at': b?.toUtc().toIso8601String(),
        'last_seen_at': (s['last_seen_at']! as DateTime)
            .toUtc()
            .toIso8601String(),
        'in_note': s['in_note'],
        'out_note': s['out_note'],
        'closed_by': s['closed_by'],
        'open': b == null,
        'minutes': (b ?? now).difference(a).inMinutes,
      };
    }

    List<Map<String, Object?>> of(
      String user, {
      String? date,
    }) => <Map<String, Object?>>[
      for (final Map<String, Object?> s in attSessions)
        if (s['user_id'] == user && (date == null || s['work_date'] == date)) s,
    ];
    Map<String, Object?>? openOf(String user) => of(
      user,
    ).where((Map<String, Object?> s) => s['check_out_at'] == null).firstOrNull;
    Map<String, Object?> dayOf(List<Map<String, Object?>> ss) {
      final Map<String, Object?>? o = ss
          .where((Map<String, Object?> s) => s['check_out_at'] == null)
          .firstOrNull;
      final String status = o != null
          ? (now.difference(o['last_seen_at']! as DateTime).inMinutes <= 15
                ? 'active'
                : 'idle')
          : (ss.isEmpty ? 'absent' : 'checked_out');
      return <String, Object?>{
        'status': status,
        'first_in': ss.isEmpty
            ? null
            : (ss.first['check_in_at']! as DateTime).toUtc().toIso8601String(),
        'last_out': o != null || ss.isEmpty
            ? null
            : (ss.last['check_out_at']! as DateTime).toUtc().toIso8601String(),
        'last_seen_at': o == null
            ? null
            : (o['last_seen_at']! as DateTime).toUtc().toIso8601String(),
        'total_minutes': ss.fold<int>(
          0,
          (int a, Map<String, Object?> s) => a + (out(s)['minutes']! as int),
        ),
        'auto_closed': ss.any(
          (Map<String, Object?> s) => s['closed_by'] == 'auto',
        ),
        'sessions': ss.map(out).toList(),
      };
    }

    List<Object?> days(List<Map<String, Object?>> ss) {
      final List<String> ds = <String>{
        for (final Map<String, Object?> s in ss) '${s['work_date']}',
      }.toList()..sort((String a, String b) => b.compareTo(a));
      return <Object?>[
        for (final String d in ds)
          <String, Object?>{
            'date': d,
            ...dayOf(
              ss
                  .where((Map<String, Object?> s) => s['work_date'] == d)
                  .toList(),
            ),
          },
      ];
    }

    http.Response err(int status, String code, String message) => _json(
      status,
      <String, Object?>{'success': false, 'code': code, 'message': message},
    );
    if (p == '/api/attendance/me') {
      final bool exempt = !admin && !attRequired('7');
      return _json(200, <String, Object?>{
        'success': true,
        'enabled': !admin && attOnTeam && !exempt,
        'is_admin': admin,
        'exempt': exempt,
        'position': attRules['7']?.$1,
        'server_time': now.toUtc().toIso8601String(),
        'date': today,
        ...dayOf(of('7', date: today)),
      });
    }
    if (p == '/api/attendance/check-in') {
      if (admin || !attOnTeam) {
        return err(
          403,
          'not_on_team',
          'Check-in is for team members; the admin sees the team.',
        );
      }
      final Object? key = body['idempotency_key'];
      final Map<String, Object?>? again = key == null
          ? null
          : attSessions
                .where((Map<String, Object?> s) => s['key'] == key)
                .firstOrNull;
      if (again != null) {
        return _json(200, <String, Object?>{
          'success': true,
          'replayed': true,
          'session': out(again),
        });
      }
      if (openOf('7') != null) {
        return err(409, 'already_checked_in', 'You are already checked in.');
      }
      final Map<String, Object?> s = <String, Object?>{
        'id': attSessions.length + 1,
        'user_id': '7',
        'work_date': today,
        'check_in_at': now,
        'last_seen_at': now,
        'check_out_at': null,
        'in_note': body['note'],
        'out_note': null,
        'closed_by': null,
        'key': key,
      };
      attSessions.add(s);
      return _json(201, <String, Object?>{'success': true, 'session': out(s)});
    }
    if (p == '/api/attendance/check-out') {
      final Map<String, Object?>? o = openOf('7');
      if (o == null) {
        return err(409, 'not_checked_in', 'You are not checked in.');
      }
      o['check_out_at'] = now;
      o['last_seen_at'] = now;
      o['out_note'] = body['note'];
      o['closed_by'] = 'user';
      return _json(200, <String, Object?>{'success': true, 'session': out(o)});
    }
    if (p == '/api/attendance/ping') {
      final Map<String, Object?>? o = openOf('7');
      if (o != null) o['last_seen_at'] = now;
      return _json(200, <String, Object?>{'success': true, 'open': o != null});
    }
    final Map<String, String> q = r.url.queryParameters;
    if (p == '/api/attendance/me/history') {
      return _json(200, <String, Object?>{
        'success': true,
        'from': q['from'],
        'to': q['to'],
        'days': days(of('7')),
      });
    }
    if (!admin) return err(403, 'forbidden', 'Admin access required');
    const List<(String, String)> team = <(String, String)>[
      ('9', 'asha'),
      ('10', 'vik'),
    ];
    Map<String, Object?> rules() => <String, Object?>{
      'success': true,
      'ready': !attRulesMissing,
      'exempt_positions': attExempt,
      'positions': <String>[
        'Sales Executive',
        'Manager',
        'Director',
        for (final (String?, String) x in attRules.values)
          if (x.$1 != null &&
              !<String>[
                'Sales Executive',
                'Manager',
                'Director',
              ].contains(x.$1))
            x.$1!,
      ],
      'members': <Object?>[
        for (final (String, String) m in team)
          <String, Object?>{
            'user_id': int.parse(m.$1),
            'username': m.$2,
            'email': '${m.$2}@x.in',
            'position': attRules[m.$1]?.$1,
            'rule': attRules[m.$1]?.$2 ?? 'auto',
            'required': attRequired(m.$1),
            'reason': (attRules[m.$1]?.$2 ?? 'auto') != 'auto'
                ? 'rule'
                : (attRequired(m.$1) ? 'default' : 'position'),
          },
      ],
    };
    if (p == '/api/attendance/settings') {
      if (r.method == 'PUT') {
        if (attRulesMissing) {
          return err(
            503,
            'not_ready',
            'Check-in settings are not available on the server yet.',
          );
        }
        attRulePuts.add(body);
        attExempt = <String>[
          for (final Object? x in body['exempt_positions']! as List<Object?>)
            '$x',
        ];
      }
      return _json(200, rules());
    }
    final RegExpMatch? mr = RegExp(
      r'^/api/attendance/members/(\d+)$',
    ).firstMatch(p);
    if (mr != null) {
      final String id = mr.group(1)!;
      if (id != '9' && id != '10') {
        return err(404, 'not_found', 'Team member not found');
      }
      attRulePuts.add(<String, Object?>{'user_id': id, ...body});
      final (String?, String) cur = attRules[id] ?? (null, 'auto');
      attRules[id] = (
        body.containsKey('position') ? body['position'] as String? : cur.$1,
        (body['rule'] as String?) ?? cur.$2,
      );
      return _json(200, rules());
    }
    if (p == '/api/attendance/summary') {
      final String from = q['from'] ?? today, to = q['to'] ?? today;
      return _json(200, <String, Object?>{
        'success': true,
        'company': 'Gupta Industries',
        'from': from,
        'to': to,
        'members': <Object?>[
          for (final (String, String) m in team)
            () {
              final List<Map<String, Object?>> ss = <Map<String, Object?>>[
                for (final Map<String, Object?> s in of(m.$1))
                  if ('${s['work_date']}'.compareTo(from) >= 0 &&
                      '${s['work_date']}'.compareTo(to) <= 0)
                    s,
              ];
              final int mins = ss.fold<int>(
                0,
                (int a, Map<String, Object?> s) =>
                    a + (out(s)['minutes']! as int),
              );
              final int present = <String>{
                for (final Map<String, Object?> s in ss) '${s['work_date']}',
              }.length;
              final bool req = attRequired(m.$1);
              return <String, Object?>{
                'user_id': int.parse(m.$1),
                'username': m.$2,
                'email': '${m.$2}@x.in',
                'position': attRules[m.$1]?.$1,
                'required': req,
                'present_days': present,
                'working_days': 3,
                'leave_days': m.$1 == '9' ? 0.5 : 0,
                'absent_days': req ? 3 - present : 0,
                'holidays': 0,
                'weekly_off': 1,
                'total_minutes': mins,
                'avg_minutes': present == 0 ? 0 : mins ~/ present,
                'avg_in': present == 0 ? null : '09:30',
                'avg_out': present == 0 ? null : '18:00',
              };
            }(),
        ],
      });
    }
    if (p == '/api/attendance/team') {
      final String date = q['date'] ?? today;
      final List<Map<String, Object?>> members = <Map<String, Object?>>[
        // Every team member of the account.
        for (final (String, String) m in team)
          () {
            final Map<String, Object?> d = dayOf(of(m.$1, date: date));
            final bool req = attRequired(m.$1);
            return <String, Object?>{
              'user_id': int.parse(m.$1),
              'username': m.$2,
              'email': '${m.$2}@x.in',
              'position': attRules[m.$1]?.$1,
              'required': req,
              ...d,
              'status': !req && d['status'] == 'absent'
                  ? 'exempt'
                  : d['status'],
            };
          }(),
      ];
      return _json(200, <String, Object?>{
        'success': true,
        'date': date,
        'company': 'Gupta Industries',
        'members': members,
      });
    }
    final RegExpMatch? h = RegExp(
      r'^/api/attendance/team/(\d+)/history$',
    ).firstMatch(p);
    if (h != null) {
      final String id = h.group(1)!;
      if (id != '9' && id != '10') {
        return err(404, 'not_found', 'Team member not found');
      }
      return _json(200, <String, Object?>{
        'success': true,
        'member': <String, Object?>{
          'user_id': int.parse(id),
          'username': id == '9' ? 'asha' : 'vik',
        },
        'from': q['from'],
        'to': q['to'],
        'days': days(of(id)),
      });
    }
    return err(404, 'not_found', 'Not found');
  }

  http.Response _financial(http.Request r, String p) {
    finRequests.add(<String, Object?>{
      'path': p,
      'method': r.method,
      ...r.url.queryParameters,
    });
    if (p == '/api/financial/me') {
      return _json(200, <String, Object?>{
        'success': true,
        'can_view': finAllowed,
      });
    }
    if (p == '/api/financial/access' && r.method == 'GET') {
      return _json(200, <String, Object?>{
        'success': true,
        'user_ids': <Object?>[for (final String x in finGranted) int.parse(x)],
      });
    }
    if (p.startsWith('/api/financial/access/') && r.method == 'PUT') {
      final String id = p.substring('/api/financial/access/'.length);
      final bool on =
          (jsonDecode(r.body) as Map<String, Object?>)['enabled'] == true;
      on ? finGranted.add(id) : finGranted.remove(id);
      return _json(200, <String, Object?>{'success': true, 'enabled': on});
    }
    if (!finAllowed) {
      return _json(403, <String, Object?>{
        'success': false,
        'code': 'no_access',
        'message': 'Ask your admin for access to financial reports.',
      });
    }
    if (p == '/api/financial/stock-values' && r.method == 'PUT') {
      final Map<String, Object?> b = jsonDecode(r.body) as Map<String, Object?>;
      finStockSaved.add(b);
      finStockNeeded.remove(b['as_on']);
      return _json(200, <String, Object?>{'success': true, ...b});
    }
    if (p == '/api/financial/periods') {
      return _json(200, <String, Object?>{
        'success': true,
        'company': 'Gupta Industries',
        'groups_synced': !finNotSynced,
        'message': ?finReason,
        'stock_needed': <Object?>[...finStockNeeded],
        'can_enter_stock': finCanEnterStock,
        if (finAnyPeriod) ...<String, Object?>{
          'any_period': true,
          'books_from': '2023-04-01',
          'stock_dates': <Object?>['2026-03-31', '2026-10-03'],
        },
        'snapshots': finNotSynced
            ? <Object?>[]
            : <Object?>[
                for (final (String, String) s in <(String, String)>[
                  ('2026-10-03', '2026-04-01'),
                  ('2026-09-30', '2026-04-01'),
                  ('2026-08-31', '2026-04-01'),
                  ('2026-03-31', '2025-04-01'),
                ])
                  <String, Object?>{
                    'as_on': s.$1,
                    'fy_from': s.$2,
                    'synced_at': '2026-10-03T05:00:00.000Z',
                  },
              ],
      });
    }
    Map<String, Object?> g(
      String name,
      num amount, [
      List<Object?> ch = const <Object?>[],
    ]) => <String, Object?>{
      'type': 'group',
      'name': name,
      'amount': amount,
      'children': ch,
    };
    Map<String, Object?> l(String name, num amount) => <String, Object?>{
      'type': 'ledger',
      'name': name,
      'guid': 'g-$name',
      'amount': amount,
    };
    final Object? data = switch (p) {
      '/api/financial/profit-loss' => <String, Object?>{
        'from': r.url.queryParameters['from'],
        'to': r.url.queryParameters['to'],
        'company': 'Gupta Industries',
        'trading': <String, Object?>{
          'income': <Object?>[
            g('Sales Accounts', 200000, <Object?>[l('Sales', 200000)]),
          ],
          'expense': <Object?>[
            g('Purchase Accounts', 120000, <Object?>[l('Purchase', 120000)]),
            g('Direct Expenses', 5000, <Object?>[l('Freight Inward', 5000)]),
          ],
          'opening_stock': 15000,
          'closing_stock': 25000,
          'total_income': 225000,
          'total_expense': 140000,
        },
        'gross_profit': 85000,
        'indirect': <String, Object?>{
          'income': <Object?>[
            g('Indirect Incomes', 2000, <Object?>[
              l('Interest Received', 2000),
            ]),
          ],
          'expense': <Object?>[
            g('Indirect Expenses', 30000, <Object?>[
              g('Office Expenses', 12000, <Object?>[l('Office Rent', 12000)]),
              l('Salary', 18000),
            ]),
          ],
          'total_income': 2000,
          'total_expense': 30000,
        },
        'net_profit': 57000,
        'total_revenue': 202000,
        'total_expenses': 155000,
      },
      '/api/financial/balance-sheet' => <String, Object?>{
        'as_on': r.url.queryParameters['as_on'],
        'company': 'Gupta Industries',
        'liabilities': <Object?>[
          g('Capital Account', 115000, <Object?>[l('Capital A/c', 115000)]),
          g('Current Liabilities', 35000, <Object?>[
            g('Sundry Creditors', 30000, <Object?>[l('Polycab Wires', 30000)]),
            g('Duties & Taxes', 5000, <Object?>[l('GST Payable', 5000)]),
          ]),
        ],
        'assets': <Object?>[
          g('Fixed Assets', 50000, <Object?>[l('Furniture', 50000)]),
          g('Current Assets', 167000, <Object?>[
            g('Stock-in-Hand', 25000),
            l('Mehta Electricals', 77000),
          ]),
        ],
        'profit_loss': <String, Object?>{
          'opening': 10000,
          'current_period': 57000,
          'total': 67000,
        },
        'total_liabilities': 217000,
        'total_assets': 217000,
        'difference': 0,
      },
      '/api/financial/trial-balance' when finBigTb => <String, Object?>{
        'as_on': r.url.queryParameters['as_on'],
        'company': 'GI Apr 25-26',
        'sections': <Object?>[
          <String, Object?>{
            ...g('Current Assets', 314552508.38, <Object?>[
              l('Real Glory Pvt Ltd', 316471156.96),
              l('Advance to Suppliers', -1918648.58),
            ]),
            'nature': 'asset',
          },
          <String, Object?>{
            ...g('Current Liabilities', -296193059.12, <Object?>[
              l('GST Payable', 6138666.06),
              l('Polycab Wires Pvt Ltd', -302331725.18),
            ]),
            'nature': 'liability',
          },
        ],
        'opening_stock': 0,
        'total_debit': 322609823.02,
        'total_credit': 304250373.76,
        'difference': 18359449.26,
        'ungrouped': <Object?>[],
      },
      '/api/financial/trial-balance' => <String, Object?>{
        'as_on': r.url.queryParameters['as_on'],
        'company': 'Gupta Industries',
        'sections': <Object?>[
          <String, Object?>{
            ...g('Current Assets', 157000, <Object?>[
              l('Mehta Electricals', 77000),
            ]),
            'nature': 'asset',
          },
          <String, Object?>{
            ...g('Capital Account', -115000, <Object?>[
              l('Capital A/c', -115000),
            ]),
            'nature': 'liability',
          },
        ],
        'opening_stock': 15000,
        'total_debit': 362000,
        'total_credit': 362000,
        'difference': 0,
        'ungrouped': <Object?>[],
      },
      '/api/financial/expenses' => <String, Object?>{
        'from': r.url.queryParameters['from'],
        'to': r.url.queryParameters['to'],
        'company': 'Gupta Industries',
        'include_purchases': r.url.queryParameters['purchases'] == '1',
        'sections': <Object?>[
          g('Indirect Expenses', 30000, <Object?>[l('Salary', 18000)]),
        ],
        'total': r.url.queryParameters['purchases'] == '1' ? 155000 : 35000,
        'top_ledgers': <Object?>[l('Salary', 18000), l('Office Rent', 12000)],
        'by_month': <Object?>[
          <String, Object?>{
            'month': '2026-08',
            'as_on': '2026-08-31',
            'amount': 29000,
          },
          <String, Object?>{
            'month': '2026-09',
            'as_on': '2026-09-30',
            'amount': 6000,
          },
        ],
      },
      '/api/financial/cash-flow' => <String, Object?>{
        'from': r.url.queryParameters['from'],
        'to': r.url.queryParameters['to'],
        'company': 'Gupta Industries',
        'opening': 45000,
        'inflow': 52000,
        'outflow': 30000,
        'net': 22000,
        'closing': 67000 + finCashNotInFlow,
        'not_in_flow': finCashNotInFlow,
        'months': <Object?>[
          <String, Object?>{
            'month': '2026-08',
            'inflow': 40000,
            'outflow': 18000,
            'net': 22000,
          },
          <String, Object?>{
            'month': '2026-09',
            'inflow': 12000,
            'outflow': 12000,
            'net': 0,
          },
        ],
        'inflow_groups': <Object?>[
          <String, Object?>{'name': 'Sundry Debtors', 'amount': 52000},
        ],
        'outflow_groups': <Object?>[
          <String, Object?>{'name': 'Indirect Expenses', 'amount': 18000},
          <String, Object?>{'name': 'Sundry Creditors', 'amount': 12000},
        ],
        'accounts': <Object?>[
          <String, Object?>{
            'name': 'HDFC Bank',
            'group': 'Bank Accounts',
            'opening': 40000,
            'closing': 60000,
          },
          <String, Object?>{
            'name': 'Cash',
            'group': 'Cash-in-Hand',
            'opening': 5000,
            'closing': 7000,
          },
        ],
        'cash_ledgers': 2,
      },
      '/api/financial/ledger-vouchers' => <String, Object?>{
        'ledger': <String, Object?>{
          'name': r.url.queryParameters['name'] ?? 'Salary',
          'guid': r.url.queryParameters['guid'],
          'group': 'Indirect Expenses',
          'nature': 'expense',
        },
        'from': r.url.queryParameters['from'],
        'to': r.url.queryParameters['to'],
        'opening': 0,
        'closing': -18000,
        'total_debit': 18000,
        'total_credit': 0,
        'rows': <Object?>[
          <String, Object?>{
            'guid': 'v-1',
            'date': '2026-08-31',
            'type': 'Payment',
            'ref': '12',
            'particulars': 'HDFC Bank',
            'debit': 10000,
            'credit': 0,
            'balance': -10000,
          },
          <String, Object?>{
            'guid': 'v-2',
            'date': '2026-09-30',
            'type': 'Payment',
            'ref': '19',
            'particulars': 'Cash',
            'debit': 8000,
            'credit': 0,
            'balance': -18000,
          },
        ],
        'truncated': false,
      },
      _ => null,
    };
    if (data == null) {
      return _json(404, <String, Object?>{
        'success': false,
        'message': 'Not found',
      });
    }
    return _json(200, <String, Object?>{'success': true, 'data': data});
  }

  /// The assistant API as the backend implements it: the server's AI key,
  /// tokens counted per login, 402 when used up, provider errors never 401.
  http.Response _assistant(http.Request r, String p) {
    if (aiMissing) {
      return http.Response(
        '<!DOCTYPE html><html><body><pre>Cannot POST $p</pre></body></html>',
        404,
        headers: <String, String>{'content-type': 'text/html'},
      );
    }
    aiHeadersSeen.add(Map<String, String>.of(r.headers));
    if (p == '/api/assistant/status') {
      return _json(200, <String, Object?>{
        'success': true,
        'enabled': !aiDisabled,
        'provider': aiDisabled
            ? null
            : <String, Object?>{'id': 'gemini', 'label': 'Google Gemini'},
        'usage': _aiUsage,
      });
    }
    final Map<String, Object?> req = r.body.isEmpty
        ? <String, Object?>{}
        : jsonDecode(r.body) as Map<String, Object?>;
    if (aiDisabled) {
      return _json(503, <String, Object?>{
        'success': false,
        'code': 'ai_not_configured',
        'message': 'The AI Assistant is not available right now.',
      });
    }
    if (aiUsed >= aiLimit) {
      return _json(402, <String, Object?>{
        'success': false,
        'code': 'ai_quota_exhausted',
        'message':
            'Your free AI access has ended. Upgrade your plan to continue.',
        'usage': _aiUsage,
      });
    }
    if (aiFail == 'busy') {
      return _json(503, <String, Object?>{
        'success': false,
        'code': 'ai_busy',
        'message':
            'The AI Assistant is busy right now. Try again in a few minutes.',
      });
    }
    if (aiFail == 'down') {
      return _json(502, <String, Object?>{
        'success': false,
        'code': 'ai_unavailable',
        'message':
            'The AI Assistant is not answering right now. Try again in a moment.',
      });
    }
    aiUsed += aiCost;
    final Map<String, Object?> b = req;
    aiAsks.add(b);
    return _json(
      200,
      aiReply ??
          <String, Object?>{
            'success': true,
            'answer':
                'Mehta Electricals owes the most: **₹15,000.50** across 2 bills.\n'
                '- **₹10,000.50** is overdue since 20-09-2026\n'
                '- Polycab Wires is a supplier (payable)',
            'blocks': <Object?>[
              <String, Object?>{
                'type': 'kpis',
                'title': 'Receivables · as on 2026-10-03',
                'items': <Object?>[
                  <String, Object?>{
                    'label': 'Total pending',
                    'value': 15000.5,
                    'format': 'money',
                    'tone': 'primary',
                  },
                  <String, Object?>{
                    'label': 'Overdue',
                    'value': 10000.5,
                    'format': 'money',
                    'tone': 'neg',
                  },
                  <String, Object?>{
                    'label': 'Bills',
                    'value': 2,
                    'format': 'count',
                  },
                  <String, Object?>{
                    'label': 'Parties',
                    'value': 1,
                    'format': 'count',
                  },
                ],
              },
              <String, Object?>{
                'type': 'table',
                'title': 'Top parties',
                'columns': <Object?>[
                  <String, Object?>{'label': 'Party', 'format': 'text'},
                  <String, Object?>{'label': 'Bills', 'format': 'count'},
                  <String, Object?>{'label': 'Pending', 'format': 'money'},
                  <String, Object?>{'label': 'Overdue', 'format': 'money'},
                ],
                'rows': <Object?>[
                  <Object?>['Mehta Electricals', 2, 15000.5, 10000.5],
                ],
                'total_rows': 1,
                'empty': 'No pending receivables.',
              },
            ],
            'tools_used': <String>['outstanding_summary'],
            'usage': _aiUsage,
          },
    );
  }

  /// The reminder API as the backend implements it (scoping, server-side
  /// amounts, honest send results).
  http.Response _reminders(http.Request r, String p) {
    if (remMissing) {
      return http.Response(
        '<!DOCTYPE html><html><body><pre>Cannot ${r.method} $p</pre></body></html>',
        404,
        headers: <String, String>{'content-type': 'text/html'},
      );
    }
    final Map<String, Object?> b = r.body.isEmpty
        ? <String, Object?>{}
        : jsonDecode(r.body) as Map<String, Object?>;
    String inrS(num v) => '₹${v.toStringAsFixed(2)}';
    Map<String, Object?> compose() {
      final List<String> names = <String>[
        for (final Object? x
            in (b['bill_names'] as List<Object?>? ?? <Object?>[]))
          '$x',
      ];
      final List<Map<String, Object?>> bills = <Map<String, Object?>>[
        for (final String n in names)
          if (remBills[n] != null)
            <String, Object?>{
              'bill_name': n,
              'bill_date': null,
              'due_date': remBills[n]!.$2,
              'pending_amount': remBills[n]!.$1,
              'overdue_days': n == 'S/101' ? 13 : 0,
            },
      ];
      final num total = bills.fold<num>(
        0,
        (num s, Map<String, Object?> x) => s + (x['pending_amount']! as num),
      );
      final List<String> to = remEmail == null
          ? <String>[]
          : <String>[remEmail!];
      final List<String> problems = <String>[
        if (bills.isEmpty) 'None of the selected bills is pending any more.',
        if (to.isEmpty)
          'No valid email address is saved for Mehta Electricals in Tally.',
        if (remNotConfigured) 'Email sending is not configured on the server.',
      ];
      return <String, Object?>{
        'ledger_guid': 'L1',
        'party': 'Mehta Electricals',
        'company': 'Gupta Industries',
        'recipients': to,
        'subject':
            'Payment reminder from Gupta Industries · ${inrS(total)} outstanding',
        'text':
            'Dear Mehta Electricals,\n${bills.map((Map<String, Object?> x) => '• ${x['bill_name']}').join('\n')}\nTotal outstanding: ${inrS(total)}',
        'bills': bills,
        'missing_bills': <String>[
          for (final String n in names)
            if (remBills[n] == null) n,
        ],
        'total': total,
        'currency': 'INR',
        'template': <String, Object?>{'id': null, 'name': 'Standard reminder'},
        'email_configured': !remNotConfigured,
        'can_send': problems.isEmpty,
        'problems': problems,
      };
    }

    Map<String, Object?> logOf(
      Map<String, Object?> c,
      String status,
      String? error,
    ) => <String, Object?>{
      'id': _remId++,
      'ledger_guid': 'L1',
      'party': 'Mehta Electricals',
      'recipients': c['recipients'],
      'subject': c['subject'],
      'bills': c['bills'],
      'total': c['total'],
      'status': status,
      'error': error,
      'attempts': 1,
      'sent_by': 'ravi@x.in',
      'created_at': '2026-10-03T05:30:00.000Z',
      'sent_at': status == 'accepted' ? '2026-10-03T05:30:01.000Z' : null,
      'key': b['idempotency_key'],
    };

    http.Response result(Map<String, Object?> log) {
      if (log['status'] == 'accepted') {
        return _json(200, <String, Object?>{
          'success': true,
          'data': log,
          'message':
              'Accepted by Microsoft 365 for delivery to ${(log['recipients']! as List<Object?>).join(', ')}. '
              'Delivery to the inbox is not confirmed.',
        });
      }
      final bool nc = remNotConfigured;
      return _json(nc ? 503 : 502, <String, Object?>{
        'success': false,
        'code': nc ? 'email_not_configured' : 'send_failed',
        'data': log,
        'message': nc
            ? 'Email sending is not configured on the server. Nothing was sent.'
            : 'The email was not sent: ${log['error']}',
      });
    }

    final Map<String, Object?> defaults = <String, Object?>{
      'mode': 'manual',
      'timing': 'before',
      'before_days': 3,
      'after_days': 1,
      'repeat_days': 0,
      'send_hour': 10,
    };
    switch ((r.method, p)) {
      case ('GET', '/api/reminders/settings'):
        return _json(200, <String, Object?>{
          'success': true,
          'data': remSettings ?? defaults,
          'stored': remSettings != null,
          'ready': !remSettingsNoTable,
          'can_edit': loginType == 'ADMIN',
          'email_configured': !remNotConfigured,
        });
      case ('PUT', '/api/reminders/settings'):
        if (loginType != 'ADMIN') {
          return _json(403, <String, Object?>{
            'success': false,
            'message': 'Only the admin can change reminder settings.',
          });
        }
        if (remSettingsNoTable) {
          return _json(503, <String, Object?>{
            'success': false,
            'code': 'not_ready',
            'message': 'Reminder settings are not available on the server yet.',
          });
        }
        remSettingsPuts.add(b);
        remSettings = <String, Object?>{...b};
        return _json(200, <String, Object?>{
          'success': true,
          'data': remSettings,
          'stored': true,
          'ready': true,
          'can_edit': true,
          'email_configured': !remNotConfigured,
        });
      case ('GET', '/api/reminders/due'):
        return _json(200, <String, Object?>{
          'success': true,
          'today': '2026-10-12',
          'settings': remSettings ?? defaults,
          'data': remDue,
        });
      case ('GET', '/api/reminders/templates'):
        return _json(200, <String, Object?>{
          'success': true,
          'data': remTemplates.isEmpty
              ? <Object?>[
                  <String, Object?>{
                    'id': null,
                    'name': 'Standard reminder',
                    'subject': 'Payment reminder from {{company}}',
                    'body': 'Dear {{party}},\n{{bills}}',
                    'is_default': true,
                  },
                ]
              : remTemplates,
          'placeholders': <String>[
            'party',
            'company',
            'bills',
            'total',
            'count',
            'sender',
          ],
          'can_edit': true,
          'email_configured': !remNotConfigured,
        });
      case ('POST', '/api/reminders/templates'):
        final Map<String, Object?> t = <String, Object?>{...b, 'id': _remId++};
        remTemplates.add(t);
        return _json(201, <String, Object?>{'success': true, 'data': t});
      case ('POST', '/api/reminders/preview'):
        if (b['ledger_guid'] != 'L1') {
          return _json(404, <String, Object?>{
            'success': false,
            'message': 'Party not found in the selected company.',
          });
        }
        return _json(200, <String, Object?>{
          'success': true,
          'data': compose(),
        });
      case ('POST', '/api/reminders/send'):
        // The app sends references only — never amounts or addresses.
        for (final String k in b.keys) {
          if (!<String>[
            'ledger_guid',
            'bill_names',
            'expected_total',
            'idempotency_key',
            'template_id',
          ].contains(k)) {
            violations.add('reminder send body has $k');
          }
        }
        final Map<String, Object?>? prev = remLogs
            .where(
              (Map<String, Object?> l) =>
                  l['key'] != null && l['key'] == b['idempotency_key'],
            )
            .firstOrNull;
        if (prev != null) {
          return _json(200, <String, Object?>{
            'success': prev['status'] == 'accepted',
            'replay': true,
            'data': prev,
          });
        }
        final Map<String, Object?> c = compose();
        if ((c['bills']! as List<Object?>).isEmpty) {
          return _json(409, <String, Object?>{
            'success': false,
            'code': 'nothing_pending',
            'message': 'None of the selected bills is pending any more.',
          });
        }
        if (((b['expected_total'] as num?) ?? 0) != c['total']) {
          return _json(409, <String, Object?>{
            'success': false,
            'code': 'changed',
            'message':
                'The bills changed in Tally since the preview. Review the reminder again.',
          });
        }
        remSends.add(b);
        final Map<String, Object?> log = logOf(
          c,
          remNotConfigured || remSendFail ? 'failed' : 'accepted',
          remNotConfigured
              ? 'Email sending is not configured on the server (MICROSOFT_* variables).'
              : remSendFail
              ? 'Microsoft Graph refused the email (HTTP 403): Access denied'
              : null,
        );
        remLogs.add(log);
        return result(log);
      case ('GET', '/api/reminders/history'):
        return _json(200, <String, Object?>{
          'success': true,
          'data': <Object?>[
            for (final Map<String, Object?> l in remLogs.reversed)
              if (l['ledger_guid'] == r.url.queryParameters['ledger_guid']) l,
          ],
        });
    }
    final RegExpMatch? m = RegExp(
      r'^/api/reminders/(\d+)/retry$',
    ).firstMatch(p);
    if (m != null && r.method == 'POST') {
      final Map<String, Object?>? l = remLogs
          .where((Map<String, Object?> x) => x['id'] == int.parse(m[1]!))
          .firstOrNull;
      if (l == null || l['status'] != 'failed') {
        return _json(409, <String, Object?>{
          'success': false,
          'code': 'not_failed',
          'message': 'Only a reminder that failed can be retried.',
        });
      }
      remSends.add(<String, Object?>{'retry': l['id']});
      l['attempts'] = (l['attempts']! as int) + 1;
      if (!remSendFail && !remNotConfigured) {
        l['status'] = 'accepted';
        l['error'] = null;
      }
      return result(l);
    }
    return _json(404, <String, Object?>{
      'success': false,
      'message': 'Not found',
    });
  }

  ApiTallyRepository repo() => ApiTallyRepository(
    client: ApiClient(client: client, baseUrl: 'https://api.test'),
    sessions: MemorySessionStore(),
    cache: MemorySnapshotCache(),
    clock: () => DateTime(2026, 10, 3, 11),
  );

  List<http.Request> to(String path) =>
      calls.where((http.Request r) => r.url.path == path).toList();
}

void main() {
  group('adapters (string numbers, UTC dates, kinds)', () {
    test('numbers and dates', () {
      expect(toNum('348690.50'), 348690.5);
      expect(toNum(''), isNull);
      expect(dateOnly('2026-09-26T00:00:00.000Z'), DateTime(2026, 9, 26));
      expect(dateOnly('2026-09-26'), DateTime(2026, 9, 26));
    });
    test('voucher types: only books, never orders / notes / returns', () {
      expect(voucherKind('Sales'), 'sales');
      expect(voucherKind('GST Sales'), 'sales');
      expect(voucherKind('Sales Order'), 'other');
      expect(voucherKind('Credit Note'), 'other');
      expect(voucherKind('Purchase Return'), 'other');
      expect(voucherKind('Receipt Note'), 'other');
      expect(voucherKind('Receipt'), 'receipt');
      expect(voucherKind('Payment'), 'payment');
      expect(voucherKind('Stock Journal'), 'other');
      expect(voucherKind('Journal'), 'journal');
      expect(voucherKind('Contra'), 'contra');
    });
    test('bill status from due date', () {
      final DateTime t = DateTime(2026, 10, 3);
      expect(billStatus(DateTime(2026, 9, 20), t).txt, '13 days late');
      expect(billStatus(DateTime(2026, 10, 3), t).st, 'soon');
      expect(billStatus(DateTime(2026, 10, 4), t).txt, 'Due tomorrow');
      expect(billStatus(DateTime(2026, 10, 30), t).st, 'ok');
      expect(billStatus(null, t).txt, 'No due date');
    });
    test('inr keeps paise, never rounds them away', () {
      expect(inr(10000.5), '₹10,000.50');
      expect(inr(-2500.25), '−₹2,500.25');
      expect(inr(348690), '₹3,48,690');
      expect(qty(4.5), '4.5');
      expect(qty(48), '48');
    });
    test('JWT expiry', () {
      expect(jwtExpired(kToken), isFalse);
      final String old =
          'x.${base64Url.encode(utf8.encode('{"exp":1000}')).replaceAll('=', '')}.y';
      expect(jwtExpired(old), isTrue);
    });
  });

  group('request bodies (exact backend field names, Dr/Cr)', () {
    test('sales: paise totals, GST split, payment', () {
      final Map<String, Object?> b = salesBody(
        const EntryDraft(
          type: 'sales',
          no: 'S/200',
          date: '2026-10-03',
          party: 'Mehta Electricals',
          due: '2026-10-18',
          amount: 1000,
          mode: 'cash',
          lines: <Line>[
            Line(
              'Wire',
              1850.5,
              3,
              'coil',
              18,
              guid: 'I1',
              hsn: '8544',
              group: 'Cables',
            ),
          ],
        ),
      );
      expect(b['voucher_type'], 'Sales');
      final Map<String, Object?> sum = b['summary']! as Map<String, Object?>;
      expect(sum['subtotal'], 5551.5);
      expect(sum['cgst'], 499.64); // 999.27 → 499.64 + 499.63
      expect(sum['sgst'], 499.63);
      expect(sum['total_amount'], 6550.77);
      final Map<String, Object?> pay = b['payment']! as Map<String, Object?>;
      expect(pay['amount_received'], 1000);
      expect(pay['balance_due'], 5550.77);
      expect(b.containsKey('ledger_entries'), isFalse);
      // Sync-agent contract (agent.cjs): item_name / quantity / rate / unit /
      // hsn_code / gst_rate / group.
      final Map<String, Object?> it =
          (b['items']! as List<Object?>).single! as Map<String, Object?>;
      expect(it['item_name'], 'Wire');
      expect(it['quantity'], 3);
      expect(it['rate'], 1850.5);
      expect(it['unit'], 'coil');
      expect(it['hsn_code'], '8544');
      expect(it['gst_rate'], 18);
      expect(it['group'], 'Cables');
      expect(it.containsKey('name'), isFalse);
      expect(it.containsKey('qty'), isFalse);
    });
    test('receipt / payment use their own field names', () {
      final Map<String, Object?> r = receiptBody(
        const EntryDraft(
          type: 'receipt',
          no: 'R/7',
          date: '2026-10-03',
          party: 'Mehta',
          amount: 2500.255,
          mode: 'upi',
          utr: 'UTR1',
          bank: 'HDFC',
          account: 'HDFC Bank',
          ref: 'Against S/101',
        ),
      );
      expect(r['amount_received'], 2500.26);
      final Map<String, Object?> rp = r['payment']! as Map<String, Object?>;
      expect(rp, <String, Object?>{
        'payment_mode': 'upi',
        'deposit_account': 'HDFC Bank',
        'bank_name': 'HDFC',
        'upi_ref': 'UTR1',
      });
      final Map<String, Object?> y = paymentBody(
        const EntryDraft(
          type: 'payment',
          no: 'P/2',
          date: '2026-10-03',
          party: 'Polycab',
          amount: 9000,
          mode: 'cheque',
          utr: '000123',
          account: 'HDFC Bank',
        ),
      );
      expect(y['amount_paid'], 9000);
      expect(y.containsKey('amount_received'), isFalse);
      expect(
        (y['payment']! as Map<String, Object?>)['transaction_instrument_no'],
        '000123',
      );
      expect(
        (y['payment']! as Map<String, Object?>)['bank_account'],
        'HDFC Bank',
      );
    });
    test('journal: Dr → is_debit true, Cr → false', () {
      final Map<String, Object?> j = journalBody(
        const EntryDraft(
          type: 'journal',
          no: 'J/2',
          date: '2026-10-03',
          party: '',
          journal: <JLine>[
            JLine('Dr', 'Rent A/c', '', 800.5),
            JLine('Cr', 'HDFC Bank', '', 800.5),
          ],
        ),
      );
      expect(j['ledger_entries'], <Object?>[
        <String, Object?>{
          'ledger_name': 'Rent A/c',
          'amount': 800.5,
          'is_debit': true,
        },
        <String, Object?>{
          'ledger_name': 'HDFC Bank',
          'amount': 800.5,
          'is_debit': false,
        },
      ]);
    });
  });

  group('ApiTallyRepository against the fake backend', () {
    test('login sends the chosen loginType and keeps the token', () async {
      final FakeBackend f = FakeBackend();
      final ApiTallyRepository r = f.repo();
      final AuthUser u = await r.login('Ravi@X.in ', 'secret', 'USER');
      expect(u.role, 'USER');
      final Map<String, Object?> sent =
          jsonDecode(f.to('/auth/login').single.body) as Map<String, Object?>;
      expect(sent, <String, Object?>{
        'username': 'ravi@x.in',
        'password': 'secret',
        'loginType': 'USER',
      });
      await r.login('ravi@x.in', 'secret', 'ADMIN');
      expect(r.user!.isAdmin, isTrue);
      expect(r.user!.plan, 'Professional');
      await expectLater(
        r.login('ravi@x.in', 'bad', 'ADMIN'),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiErrorKind.unauthorized,
          ),
        ),
      );
    });

    test(
      'refreshAll: company-scoped outstanding, month totals, parties',
      () async {
        final FakeBackend f = FakeBackend();
        final ApiTallyRepository r = f.repo();
        await r.login('ravi@x.in', 'secret', 'ADMIN');
        await r.refreshAll();
        // Startup loads only what Home needs: no ledgers / items / stock /
        // team / full voucher history for an admin until a screen asks.
        expect(f.to('/ledger'), isEmpty);
        expect(f.to('/inventory/mobile'), isEmpty);
        expect(f.to('/users'), isEmpty);
        expect(
          f
              .to('/voucher-entry/paged')
              .every(
                (http.Request q) => q.url.queryParameters['month'] == '10',
              ),
          isTrue,
        );
        await r.ensure(DataSet.ledgers);
        await r.ensure(DataSet.items);
        await r.ensure(DataSet.team);
        // Bearer token on data calls.
        expect(
          f.to('/ledger').single.headers['Authorization'],
          'Bearer $kToken',
        );
        // Outstanding: only co-1, pending > 0.
        final OutstandingSummary rs = r.outstanding(true),
            ps = r.outstanding(false);
        expect(rs.total, 15000.5);
        expect(rs.parties, 1);
        expect(rs.late, 10000.5);
        expect(rs.ageing, <num>[5000, 10000.5, 0, 0]);
        expect(rs.mismatch, isFalse); // equals /dashboard/summary
        expect(ps.total, 9000);
        expect(ps.ageing, <num>[0, 0, 9000, 0]);
        expect(r.receivables().first.txt, '13 days late');
        // Month totals: Sales Order counted as other; the Payment flagged
        // is_active:false is a real voucher; Sep row not in Oct.
        final MonthTotals m = r.monthTotals();
        expect(m.amount['sales'], 11800);
        expect(m.amount['receipt'], 2500.25);
        expect(m.amount['payment'], 400);
        expect(m.amount['other'], 99999);
        final Map<String, SumCard> cards = r.moneyCards();
        expect(cards['toGet']!.v, 15000.5);
        expect(cards['mIn']!.v, 2500.25);
        expect(cards['sales']!.v, 11800);
        expect(cards['mOut']!.v, 400);
        expect(cards['cash']!.v, isNull, reason: 'Dr/Cr not sent by server');
        // Month set: both pages, duplicate removed, every voucher kept.
        expect(r.vouchers().map((Voucher v) => v.guid), <String>[
          'V1',
          'V2',
          'V3',
          'V4',
        ]);
        expect(r.vouchersComplete, isTrue);
        // Parties: every ledger; customer / supplier only from the Tally group.
        final List<Party> ps2 = r.parties();
        expect(ps2.map((Party p) => p.name), <String>[
          'Mehta Electricals',
          'Polycab Wires',
          'HDFC Bank',
          'Rent A/c',
        ]);
        expect(ps2.map((Party p) => p.type), <String>['c', 's', 'o', 'o']);
        expect(ps2.first.bal, 15000.5);
        expect(ps2[1].bal, 9000);
        expect(r.accounts().single.t, 'HDFC Bank');
        // Items: string-free numbers, finished stock.
        // Tally's Dr-negative stock values read as stock values.
        expect(r.items().first.worth, 22500);
        expect(r.items().first.rate, 5000);
        expect(r.items().first.openingValue, 20000);
        expect(r.items().first.openingRate, 5000);
        expect(r.items().first.st, 'ok');
        expect(r.items()[1].st, 'out');
        // Activity: status + amounts per voucher type.
        expect(r.activity().first.status, 'fail');
        expect(r.activity().first.amt, 1500);
        expect(r.activity()[1].amt, 800);
        expect(r.activity()[1].kind, 'journal');
        // Notifications, team, alert config, sync.
        expect(r.notifications().single.unread, isTrue);
        expect(r.team().length, 2);
        expect(r.alertConfig()!['sync_completed'], isFalse);
        expect(r.syncInfo(kGuid)!.lastSyncAt, isNotNull);
        // Every backend company is listed, including one not synced yet;
        // the sync start month still comes from /company/selected.
        expect(
          r.companies().map((Company x) => x.name),
          containsAll(<String>['GI Apr 25-26', 'Rajlaxmi Traders', 'Other Co']),
        );
        expect(
          r.companies().firstWhere((Company x) => x.id == kGuid).sub,
          contains('from'),
        );
        expect(r.status(DataSet.vouchers).state, LoadState.ready);
        expect(f.violations, isEmpty);
      },
    );

    test('purchase posts as Purchase; receipt posts the right body', () async {
      final FakeBackend f = FakeBackend();
      final ApiTallyRepository r = f.repo();
      await r.login('ravi@x.in', 'secret', 'ADMIN');
      await r.refreshAll();
      final SubmitResult p = await r.submitEntry(
        const EntryDraft(
          type: 'purchase',
          no: '',
          date: '2026-10-03',
          party: 'Polycab Wires',
        ),
      );
      expect(p.ok, isTrue);
      final List<http.Request> pc = f.to('/api/mobile-voucher-command/create');
      expect(pc, hasLength(1));
      expect(
        (jsonDecode(pc.single.body) as Map<String, Object?>)['voucher_type'],
        'Purchase',
      );
      final SubmitResult ok = await r.submitEntry(
        const EntryDraft(
          type: 'receipt',
          no: 'R/7',
          date: '2026-10-03',
          party: 'Mehta Electricals',
          amount: 500,
          mode: 'cash',
          account: 'Cash',
        ),
      );
      expect(ok.ok, isTrue);
      expect(ok.commandId, '55');
      final Map<String, Object?> b =
          jsonDecode(
                f.to('/api/mobile-voucher-command/receipt/create').single.body,
              )
              as Map<String, Object?>;
      expect(b['amount_received'], 500);
      expect(b['party_name'], 'Mehta Electricals');
    });

    test('401 marks the session expired', () async {
      final FakeBackend f = FakeBackend();
      final ApiTallyRepository r = f.repo();
      await r.login('ravi@x.in', 'secret', 'ADMIN');
      f.expire = true;
      await r.refreshAll();
      expect(r.sessionExpired, isTrue);
      expect(r.status(DataSet.companies).failed, isTrue);
    });
  });

  group('controller with the real repository', () {
    test('login → Home; session expiry → Login', () async {
      final FakeBackend f = FakeBackend();
      final ApiTallyRepository r = f.repo();
      final AppController c = AppController(
        store: LocalStorage.memory(),
        repo: r,
      );
      expect(c.form['sParty'], '');
      expect(c.form['rDate'], '2026-10-03');
      c.loginType = 'ADMIN';
      c.setF('user', 'ravi@x.in');
      c.setF('pass', 'secret');
      c.doLogin();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.screen, 'home');
      expect(c.companyName, 'Rajlaxmi Traders');
      expect(c.acts.length, 2);
      expect(c.isAdmin, isTrue);
      // Journal must balance before it can be saved.
      c.startFlow('journal');
      c.jl = <JLine>[
        const JLine('Dr', 'Rent A/c', '', 800),
        const JLine('Cr', 'HDFC Bank', '', 700),
      ];
      expect(c.flowBlocker, 'Both sides must be equal');
      c.jl = <JLine>[
        const JLine('Dr', 'Rent A/c', '', 800),
        const JLine('Cr', 'HDFC Bank', '', 800),
      ];
      expect(c.flowBlocker, isNull);
      c.saveFlow(false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(f.to('/api/mobile-voucher-command/journal/create'), hasLength(1));
      expect(c.screen, 'home');
      // Purchase can be sent now (agent writes supplier Cr, stock in).
      c.startFlow('purchase');
      expect(c.flowBlocker ?? '', isNot(contains('cannot be sent')));
      f.expire = true;
      await r.refreshAll(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.screen, 'login');
      c.dispose();
    });
  });

  group('edit and send again (mobile entries)', () {
    test('activity rows carry what was sent; retry / edit bodies', () async {
      final FakeBackend f = FakeBackend();
      final ApiTallyRepository r = f.repo();
      await r.login('ravi@x.in', 'secret', 'ADMIN');
      await r.refreshAll();
      final QueueAct failed = r.activity().whereType<QueueAct>().firstWhere(
        (QueueAct a) => a.queueId == 31,
      );
      expect(failed.status, 'fail');
      expect(failed.canRetry, isTrue);
      expect(failed.action, 'CREATE');
      expect(failed.voucherType, 'Receipt');
      expect(failed.payload['party_name'], 'Mehta Electricals');
      // Send again: queued; an entry Tally has is refused.
      final SubmitResult again = await r.retryEntry(31);
      expect(again.ok, isTrue);
      expect(f.to('/api/mobile-sync-queue/31/retry'), hasLength(1));
      final SubmitResult done = await r.retryEntry(30);
      expect(done.ok, isFalse);
      expect(done.message, 'This entry is already in Tally.');
      // Edit: the create body plus the entry / voucher it changes.
      const EntryDraft d = EntryDraft(
        type: 'receipt',
        no: 'R/6',
        date: '2026-10-03',
        party: 'Mehta Electricals',
        amount: 1600,
        mode: 'cash',
        account: 'Cash',
      );
      final SubmitResult e1 = await r.submitEdit(d, queueId: 31);
      expect(e1.ok, isTrue);
      final Map<String, Object?> b1 =
          jsonDecode(f.to('/api/mobile-voucher-command/edit').last.body)
              as Map<String, Object?>;
      expect(b1['type'], 'receipt');
      expect(b1['queue_id'], 31);
      expect(b1.containsKey('voucher_guid'), isFalse);
      expect(b1['amount_received'], 1600);
      final SubmitResult e2 = await r.submitEdit(d, voucherGuid: 'V2');
      expect(e2.ok, isTrue);
      final Map<String, Object?> b2 =
          jsonDecode(f.to('/api/mobile-voucher-command/edit').last.body)
              as Map<String, Object?>;
      expect(b2['voucher_guid'], 'V2');
      expect(b2.containsKey('queue_id'), isFalse);
      expect((await r.submitEdit(d)).ok, isFalse); // nothing named
      // A server without the edit route.
      f.editMissing = true;
      final SubmitResult old = await r.submitEdit(d, queueId: 31);
      expect(old.ok, isFalse);
      expect(old.message, contains('not available on the server yet'));
    });

    test('controller: Edit fills the form; Save sends an edit', () async {
      final FakeBackend f = FakeBackend();
      final ApiTallyRepository r = f.repo();
      final AppController c = AppController(
        store: LocalStorage.memory(),
        repo: r,
      );
      c.loginType = 'ADMIN';
      c.setF('user', 'ravi@x.in');
      c.setF('pass', 'secret');
      c.doLogin();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final Act receipt = c.acts.firstWhere((Act a) => a.id == 'q31');
      expect(c.actEditBlocker(receipt), isNull);
      c.editAct(receipt);
      expect(c.screen, 'flow');
      expect(c.flowType, 'receipt');
      expect(c.form['rParty'], 'Mehta Electricals');
      expect(c.form['rAmt'], '1500');
      expect(c.form['rDate'], '2026-10-03');
      expect(c.form['rNo'], 'R/6');
      expect(c.editing?.queueId, 31);
      expect(c.editing?.inTally, isFalse);
      c.setF('rAcc', 'Cash');
      c.setF('rAmt', '1750');
      c.saveFlow(false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final Map<String, Object?> b =
          jsonDecode(f.to('/api/mobile-voucher-command/edit').single.body)
              as Map<String, Object?>;
      expect(b['queue_id'], 31);
      expect(b['amount_received'], 1750);
      expect(f.to('/api/mobile-voucher-command/receipt/create'), isEmpty);
      expect(c.editing, isNull);
      // A journal Tally already has: both lines, changed in Tally.
      final Act journal = c.acts.firstWhere((Act a) => a.id == 'q30');
      c.editAct(journal);
      expect(c.flowType, 'journal');
      expect(c.jl.map((JLine j) => '${j.side} ${j.name} ${j.amt}'), <String>[
        'Dr Rent A/c 800',
        'Cr HDFC Bank 800',
      ]);
      expect(c.editing?.inTally, isTrue);
      // A new entry is never an edit.
      c.startFlow('receipt');
      expect(c.editing, isNull);
      // Send again from Activity.
      c.retry('q31');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(f.to('/api/mobile-sync-queue/31/retry'), hasLength(1));
      c.dispose();
    });
  });

  group('cache, refresh, search, item detail, reminders', () {
    test('restart shows cached data; failed refresh keeps it', () async {
      final FakeBackend f = FakeBackend();
      final MemorySnapshotCache cache = MemorySnapshotCache();
      final MemorySessionStore sessions = MemorySessionStore();
      final ApiTallyRepository r = ApiTallyRepository(
        client: ApiClient(client: f.client, baseUrl: 'https://api.test'),
        sessions: sessions,
        cache: cache,
        clock: () => DateTime(2026, 10, 3, 11),
      );
      await r.login('ravi@x.in', 'secret', 'ADMIN');
      await r.refreshAll();
      await r.ensure(DataSet.ledgers);
      expect(r.outstanding(true).total, 15000.5);
      // Each data set is saved on its own, as the server sent it.
      expect(await cache.read('u7', DataSet.bills), isNotNull);
      expect(await cache.read('u7', DataSet.ledgers), isNotNull);
      expect(await cache.read('u7', DataSet.vouchers), isNotNull);
      // "Restart" with the server down.
      final ApiTallyRepository r2 = ApiTallyRepository(
        client: ApiClient(
          client: MockClient(
            (http.Request q) async => http.Response('boom', 500),
          ),
          baseUrl: 'https://api.test',
        ),
        sessions: sessions,
        cache: cache,
        clock: () => DateTime(2026, 10, 3, 11),
      );
      expect(await r2.restoreSession(), isTrue);
      // Saved data is on screen before any network answer…
      expect(r2.hasData(DataSet.bills), isTrue);
      expect(r2.outstanding(true).total, 15000.5);
      expect(r2.vouchers().length, 4);
      // …and a failed refresh keeps it (no zeros), reporting the error.
      await r2.refreshAll(force: true);
      expect(r2.outstanding(true).total, 15000.5);
      expect(r2.parties(), isNotEmpty);
      expect(r2.lastError(), isNotNull);
      // Logout removes the saved accounting data.
      await r2.logout();
      for (final String set in <String>[
        DataSet.bills,
        DataSet.ledgers,
        DataSet.vouchers,
        DataSet.activity,
      ]) {
        expect(await cache.read('u7', set), isNull);
      }
    });

    test(
      'concurrent refreshes share one load; unforced repeat is skipped',
      () async {
        final FakeBackend f = FakeBackend();
        final ApiTallyRepository r = f.repo();
        await r.login('ravi@x.in', 'secret', 'ADMIN');
        await Future.wait(<Future<void>>[r.refreshAll(), r.refreshAll()]);
        expect(f.to('/bill'), hasLength(1));
        await Future.wait(<Future<void>>[
          r.ensure(DataSet.ledgers),
          r.ensure(DataSet.ledgers),
        ]);
        expect(f.to('/ledger'), hasLength(1));
        await r.refreshAll();
        expect(f.to('/bill'), hasLength(1));
        expect(f.to('/ledger'), hasLength(1));
        // A forced refresh reloads the startup sets and every set on screen.
        await r.refreshAll(force: true);
        expect(f.to('/bill'), hasLength(2));
        expect(f.to('/ledger'), hasLength(2));
      },
    );

    test('voucher pages load on demand; history totals stream', () async {
      final FakeBackend f = FakeBackend();
      final ApiTallyRepository r = f.repo();
      await r.login('ravi@x.in', 'secret', 'ADMIN');
      await r.refreshAll();
      final int before = f.to('/voucher-entry/paged').length;
      // All-time list: page 1 only (100 rows per page), next page on scroll.
      final VoucherPager pg = r.voucherPager(
        const VoucherQuery(filter: 'all', period: 'all'),
      );
      await pg.loadMore(minNew: 1);
      final List<http.Request> calls = f
          .to('/voucher-entry/paged')
          .sublist(before);
      expect(calls, hasLength(1));
      expect(calls.single.url.queryParameters['limit'], '100');
      expect(calls.single.url.queryParameters.containsKey('month'), isFalse);
      expect(pg.rows.map((Voucher v) => v.guid), <String>[
        'V1',
        'V2',
        'V3',
        'V4',
      ]);
      expect(pg.hasMore, isTrue);
      await pg.loadMore();
      // Duplicate across pages removed; every voucher kept.
      expect(pg.rows.map((Voucher v) => v.guid), <String>[
        'V1',
        'V2',
        'V3',
        'V4',
        'V9',
      ]);
      expect(pg.complete, isTrue);
      // All-history totals: every voucher read once, rows not kept.
      expect(r.historyTotals, isNull);
      await r.scanHistory();
      final HistoryTotals h = r.historyTotals!;
      expect(h.complete, isTrue);
      expect(h.scanned, 5);
      expect(h.forFilter('sales'), (1, 11800));
      expect(h.forFilter('payment'), (2, 1100));
      expect(h.itemTrade('Wire', 'sales').qty, 2);
      // Month totals are unchanged by the scan.
      expect(r.monthTotals().amount['payment'], 400);
    });

    test('item trade summary from voucher item lines', () {
      final List<Voucher> vs = <Voucher>[
        Voucher(
          'sales',
          'A',
          'S2',
          3,
          300,
          date: DateTime(2026, 9, 3),
          items: const <VoucherItem>[VoucherItem('Wire', 2, 150, 300)],
        ),
        Voucher(
          'sales',
          'B',
          'S1',
          1,
          100,
          date: DateTime(2026, 9, 1),
          items: const <VoucherItem>[
            VoucherItem('wire ', 1, 100, 100),
            VoucherItem('Pipe', 1, 5, 5),
          ],
        ),
        Voucher(
          'purchase',
          'C',
          'P1',
          1,
          80,
          date: DateTime(2026, 9, 1),
          items: const <VoucherItem>[VoucherItem('Wire', 1, 80, 80)],
        ),
      ];
      final ItemTrade s = itemTrade(vs, 'Wire', 'sales');
      expect(s.amount, 400);
      expect(s.qty, 3);
      expect(s.vouchers, 2);
      expect(s.lastDate, DateTime(2026, 9, 3));
      expect(s.lastRate, 150);
      expect(s.minRate, 100);
      expect(s.maxRate, 150);
      expect(itemTrade(vs, 'Wire', 'purchase').amount, 80);
    });

    test('global search covers items, parties and vouchers', () async {
      final FakeBackend f = FakeBackend();
      final ApiTallyRepository r = f.repo();
      final AppController c = AppController(
        store: LocalStorage.memory(),
        repo: r,
      );
      c.setF('user', 'ravi@x.in');
      c.setF('pass', 'secret');
      c.doLogin();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // Items / ledgers are loaded when search opens (not at startup).
      c.openOverlay('search');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.searchHits('wire').first.t, 'Wire');
      expect(
        c.searchHits('polycab').map((SearchHit h) => h.t),
        contains('Polycab Wires'),
      );
      expect(c.searchHits('S/101').isNotEmpty, isTrue);
      expect(c.searchHits('zzzz'), isEmpty);
      c.dispose();
    });

    test('reminders persist locally and can be edited / removed', () {
      final LocalStorage s = LocalStorage.memory();
      final AppController a = AppController(store: s);
      final Bill b = a.repo.receivables().first;
      // Future dates (a reminder in the past is refused: it can't ring).
      final String d1 = ymd(DateTime.now().add(const Duration(days: 2)));
      final String d2 = ymd(DateTime.now().add(const Duration(days: 4)));
      a.openReminder(b);
      a.setF('remDate', d1);
      a.setF('remNote', 'Call');
      a.saveReminder();
      expect(a.reminderFor(b)!.date, d1);
      a.openReminder(b);
      a.setF('remDate', d2);
      a.saveReminder();
      expect(a.companyReminders, hasLength(1));
      a.dispose();
      final AppController b2 = AppController(store: s);
      expect(b2.reminderFor(b)!.date, d2);
      b2.deleteReminder(b2.reminderFor(b)!.id);
      expect(b2.companyReminders, isEmpty);
      b2.dispose();
    });
  });

  group('voucher list screen (real repository)', () {
    Future<(FakeBackend, AppController)> boot(WidgetTester t) async {
      // Tall screen: every fixture row is on screen (rows build lazily).
      t.view.physicalSize = const Size(390 * 3, 2400 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final FakeBackend f = FakeBackend();
      final AppController c = AppController(
        store: LocalStorage.memory(),
        repo: f.repo(),
      );
      await t.pumpWidget(
        ProviderScope(
          overrides: <Override>[appProvider.overrideWith((Ref ref) => c)],
          child: const TallyConnectApp(),
        ),
      );
      c.loginType = 'ADMIN';
      c.setF('user', 'ravi@x.in');
      c.setF('pass', 'secret');
      c.doLogin();
      for (int i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(c.screen, 'home');
      return (f, c);
    }

    Future<void> ticks(WidgetTester t, int n) async {
      for (int i = 0; i < n; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    // The list's own page requests (100 per page); the voucher-count
    // requests (`limit=1`) use the same endpoint and are not pages.
    List<Map<String, String>> pagedSince(FakeBackend f, int from) => f
        .to('/voucher-entry/paged')
        .sublist(from)
        .map((http.Request r) => r.url.queryParameters)
        .where((Map<String, String> q) => q['limit'] == '100')
        .toList();

    testWidgets('All Time: page 1 at once, real rows, next pages on demand', (
      WidgetTester t,
    ) async {
      final (FakeBackend f, AppController c) = await boot(t);
      final int before = f.to('/voucher-entry/paged').length;
      f.delay = const Duration(milliseconds: 300);
      c.go('vList', <String, Object?>{'vFilter': 'all', 'vPeriod': 'all'});
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      // Waiting for the server: a loading state, never "0" / "No entries".
      expect(find.text('All Vouchers'), findsOneWidget);
      expect(find.textContaining('No entries'), findsNothing);
      expect(find.text('0'), findsNothing);
      expect(find.text('0+'), findsNothing);
      await ticks(t, 20);
      // Page 1 of the whole history: 100 per page, newest first.
      final List<Map<String, String>> q = pagedSince(f, before);
      expect(q.first['page'], '1');
      expect(q.first['limit'], '100');
      expect(q.first['sort_by'], 'date_desc');
      expect(q.first.containsKey('month'), isFalse);
      expect(q.first.containsKey('year'), isFalse);
      expect(q.first.containsKey('type'), isFalse);
      // The rows did not fill the screen, so page 2 followed by itself;
      // the server then said hasMore=false and paging stopped.
      expect(q.map((Map<String, String> x) => x['page']), <String>['1', '2']);
      // Real rows (page 1 and the September row of page 2), duplicates
      // dropped; count and total exact for the complete list.
      expect(find.text('S/101 · 2 Oct · Sales'), findsOneWidget);
      expect(find.text('R/5 · 3 Oct · Receipt'), findsOneWidget);
      expect(find.text('P/0 · 29 Sep · Payment'), findsOneWidget);
      expect(
        find.text('P/1 · 1 Oct · Payment'),
        findsOneWidget,
      ); // reset-flagged row
      expect(find.text('5'), findsOneWidget);
      expect(find.text('₹1,15,399.25'), findsOneWidget);
      expect(find.textContaining('No entries'), findsNothing);
      expect(f.violations, isEmpty);
      await t.pump(const Duration(seconds: 6));
    });

    testWidgets('type filters page with their own query; refresh restarts', (
      WidgetTester t,
    ) async {
      final (FakeBackend f, AppController c) = await boot(t);
      c.go('vList', <String, Object?>{'vFilter': 'all', 'vPeriod': 'all'});
      await ticks(t, 10);
      int mark = f.to('/voucher-entry/paged').length;
      c.update(() => c.vFilter = 'sales');
      await ticks(t, 10);
      // Sales: server pre-filter `sale` (also matches a type named "Sale"),
      // exact kind check on the phone.
      final List<Map<String, String>> qs = pagedSince(f, mark);
      expect(qs.first['page'], '1');
      expect(qs.first['type'], 'sale');
      expect(find.text('S/101 · 2 Oct · Sales'), findsOneWidget);
      expect(find.text('R/5 · 3 Oct · Receipt'), findsNothing);
      mark = f.to('/voucher-entry/paged').length;
      c.update(() => c.vFilter = 'receipt');
      await ticks(t, 10);
      expect(pagedSince(f, mark).first['type'], 'receipt');
      expect(find.text('R/5 · 3 Oct · Receipt'), findsOneWidget);
      expect(find.text('S/101 · 2 Oct · Sales'), findsNothing);
      // Back to All: its pages are kept (no reload, no stale rows).
      mark = f.to('/voucher-entry/paged').length;
      c.update(() => c.vFilter = 'all');
      await ticks(t, 10);
      expect(pagedSince(f, mark), isEmpty);
      expect(find.text('S/101 · 2 Oct · Sales'), findsOneWidget);
      expect(find.text('R/5 · 3 Oct · Receipt'), findsOneWidget);
      // Refresh: the list restarts from page 1 and shows the rows again.
      mark = f.to('/voucher-entry/paged').length;
      c.refreshNow();
      await ticks(t, 20);
      expect(
        pagedSince(f, mark).where(
          (Map<String, String> x) =>
              !x.containsKey('month') && x['page'] == '1',
        ),
        isNotEmpty,
      );
      expect(find.text('S/101 · 2 Oct · Sales'), findsOneWidget);
      expect(find.textContaining('No entries'), findsNothing);
      expect(f.violations, isEmpty);
      await t.pump(const Duration(seconds: 6));
    });
  });
}
