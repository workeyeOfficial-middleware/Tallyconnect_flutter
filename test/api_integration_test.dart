// Backend integration tests — no network: a fake HTTP client answers with
// the exact JSON shapes documented in BACKEND_API_REFERENCE.md (numbers as
// strings, DATE columns as midnight-UTC ISO strings).
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/core/network/api_client.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/core/storage/session_store.dart';
import 'package:tallyconnect_ui/core/utils/format.dart';
import 'package:tallyconnect_ui/data/accounting.dart';
import 'package:tallyconnect_ui/data/api/adapters.dart';
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/api_tally_repository.dart';
import 'package:tallyconnect_ui/data/repositories/tally_repository.dart';

const String kGuid = 'co-1';

/// JWT with exp far in the future (payload {"exp":4102444800}).
final String kToken =
    'x.${base64Url.encode(utf8.encode('{"exp":4102444800}')).replaceAll('=', '')}.y';

/// Fake backend. Records every request.
class FakeBackend {
  final List<http.Request> calls = <http.Request>[];
  bool expire = false;

  Map<String, Object?> json(String path, http.Request r) {
    throw UnimplementedError(path);
  }

  late final MockClient client = MockClient((http.Request r) async {
    calls.add(r);
    final String p = r.url.path;
    if (expire && p != '/auth/login') {
      return http.Response('{"message":"Invalid token"}', 401);
    }
    Object? body;
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
            <String, Object?>{'company_guid': kGuid, 'name': 'Rajlaxmi Traders', 'starting_from': '2026-04-01'},
            <String, Object?>{'company_guid': 'co-2', 'name': 'Other Co', 'starting_from': null},
          ],
        };
      case '/company/active':
        body = <String, Object?>{'success': true, 'company_guid': kGuid};
      case '/agent-status/sync-status':
        body = <String, Object?>{'success': true, 'last_sync_at': '2026-10-03T04:00:00.000Z', 'sync_in_progress': false};
      case '/users/me':
        body = <String, Object?>{'id': 7, 'username': 'ravi', 'email': 'ravi@x.in', 'role': 'ADMIN', 'company': null, 'admin_email': 'ravi@x.in'};
      case '/ledger':
        body = <String, Object?>{
          'success': true,
          'data': <Object?>[
            <String, Object?>{'ledger_guid': 'L1', 'name': 'Mehta Electricals', 'parent_group': 'Sundry Debtors', 'opening_balance': '-1200.50', 'closing_balance': '-15000.00', 'date': '2026-09-30T00:00:00.000Z'},
            <String, Object?>{'ledger_guid': 'L2', 'name': 'Polycab Wires', 'parent_group': 'Sundry Creditors', 'opening_balance': '0', 'closing_balance': '9000', 'date': null},
            <String, Object?>{'ledger_guid': 'L3', 'name': 'HDFC Bank', 'parent_group': 'Bank Accounts', 'opening_balance': '0', 'closing_balance': '-50000'},
            <String, Object?>{'ledger_guid': 'L4', 'name': 'Rent A/c', 'parent_group': 'Indirect Expenses', 'opening_balance': '0', 'closing_balance': '0'},
          ],
        };
      case '/bill':
        body = <String, Object?>{
          'success': true,
          'data': <Object?>[
            // late by 13 days (due 20 Sep, today 3 Oct)
            <String, Object?>{'company_guid': kGuid, 'bill_guid': 'B1', 'ledger_guid': 'L1', 'ledger_name': 'Mehta Electricals', 'bill_name': 'S/101', 'bill_amount': '12000.00', 'pending_amount': '10000.50', 'due_date': '2026-09-20T00:00:00.000Z', 'bill_type': 'RECEIVABLE', 'bill_date': null},
            // due in 2 days
            <String, Object?>{'company_guid': kGuid, 'bill_guid': 'B2', 'ledger_guid': 'L1', 'ledger_name': 'Mehta Electricals', 'bill_name': 'S/102', 'bill_amount': '5000', 'pending_amount': '5000.00', 'due_date': '2026-10-05T00:00:00.000Z', 'bill_type': 'RECEIVABLE'},
            // payable, 45 days late
            <String, Object?>{'company_guid': kGuid, 'bill_guid': 'B3', 'ledger_guid': 'L2', 'ledger_name': 'Polycab Wires', 'bill_name': 'PW/9', 'bill_amount': '9000', 'pending_amount': '9000', 'due_date': '2026-08-19T00:00:00.000Z', 'bill_type': 'PAYABLE'},
            // settled → ignored
            <String, Object?>{'company_guid': kGuid, 'bill_guid': 'B4', 'ledger_guid': 'L1', 'ledger_name': 'Mehta Electricals', 'bill_name': 'S/90', 'bill_amount': '700', 'pending_amount': '0.00', 'due_date': null, 'bill_type': 'RECEIVABLE'},
            // other company → ignored
            <String, Object?>{'company_guid': 'co-2', 'bill_guid': 'B5', 'ledger_guid': 'X', 'ledger_name': 'Other', 'bill_name': 'O/1', 'bill_amount': '99999', 'pending_amount': '99999', 'due_date': null, 'bill_type': 'RECEIVABLE'},
          ],
        };
      case '/dashboard/summary':
        body = <String, Object?>{'receivables': '15000.50', 'payables': '9000.00', 'pending_bills': '3', 'cleared_bills': '1'};
      case '/voucher-entry/paged':
        // Full history (no year/month): page 1 = October rows, page 2 =
        // September rows plus one duplicate that shifted across pages.
        expect(r.url.queryParameters.containsKey('month'), isFalse);
        final int page = int.parse(r.url.queryParameters['page']!);
        body = <String, Object?>{
          'success': true,
          'data': page == 1
              ? <Object?>[
                  <String, Object?>{'voucher_guid': 'V1', 'voucher_date': '2026-10-02T00:00:00.000Z', 'voucher_type': 'Sales', 'reference_no': 'S/101', 'amount': '-11800.00', 'is_active': true, 'party_name': 'Mehta Electricals', 'items': <Object?>[<String, Object?>{'item_name': 'Wire', 'quantity': '2', 'rate': '5000', 'amount': '10000'}]},
                  <String, Object?>{'voucher_guid': 'V2', 'voucher_date': '2026-10-03T00:00:00.000Z', 'voucher_type': 'Receipt', 'reference_no': 'R/5', 'amount': '2500.25', 'is_active': true, 'party_name': 'Mehta Electricals', 'items': <Object?>[]},
                  <String, Object?>{'voucher_guid': 'V3', 'voucher_date': '2026-10-01T00:00:00.000Z', 'voucher_type': 'Sales Order', 'reference_no': 'SO/1', 'amount': '99999', 'is_active': true, 'party_name': 'X', 'items': <Object?>[]},
                  <String, Object?>{'voucher_guid': 'V4', 'voucher_date': '2026-10-01T00:00:00.000Z', 'voucher_type': 'Payment', 'reference_no': 'P/1', 'amount': '400', 'is_active': false, 'party_name': 'Y', 'items': <Object?>[]},
                ]
              : <Object?>[
                  <String, Object?>{'voucher_guid': 'V2', 'voucher_date': '2026-10-03T00:00:00.000Z', 'voucher_type': 'Receipt', 'reference_no': 'R/5', 'amount': '2500.25', 'is_active': true, 'party_name': 'Mehta Electricals', 'items': <Object?>[]},
                  <String, Object?>{'voucher_guid': 'V9', 'voucher_date': '2026-09-29T00:00:00.000Z', 'voucher_type': 'Payment', 'reference_no': 'P/0', 'amount': '700', 'is_active': true, 'party_name': 'Polycab Wires', 'items': <Object?>[]},
                ],
          'meta': <String, Object?>{'total': 5, 'page': page, 'limit': 200, 'hasMore': page == 1, 'totalAmount': 0, 'types': <Object?>[], 'years': <Object?>[]},
        };
      case '/inventory/mobile':
        body = <String, Object?>{
          'success': true,
          'items': <Object?>[
            <String, Object?>{'item_guid': 'I1', 'name': 'Wire', 'unit': 'Coil', 'closing_qty': 4.5, 'closing_value': 22500, 'rate': 5000, 'gst_rate': 18, 'hsn_code': '8544'},
            <String, Object?>{'item_guid': 'I2', 'name': 'Pipe', 'unit': 'Nos', 'closing_qty': 0, 'closing_value': 0, 'rate': 0, 'gst_rate': null},
          ],
        };
      case '/inventory':
        body = <String, Object?>{'success': true, 'data': <Object?>[<String, Object?>{'id': 'I2', 'name': 'Pipe', 'opening': '5', 'inward': '0', 'outward': '0', 'closing': '0'}]};
      case '/api/mobile-sync-queue/activity':
        body = <Object?>[
          <String, Object?>{'id': 31, 'entity_type': 'VOUCHER', 'action': 'CREATE', 'status': 'failed', 'error': 'Tally closed', 'created_at': '2026-10-03T05:00:00.000Z', 'processed_at': null, 'payload': <String, Object?>{'voucher_type': 'Receipt', 'voucher_no': 'R/6', 'party_name': 'Mehta Electricals', 'amount_received': 1500, 'voucher_date': '2026-10-03'}},
          <String, Object?>{'id': 30, 'status': 'success', 'created_at': '2026-10-02T05:00:00.000Z', 'payload': <String, Object?>{'voucher_type': 'Journal', 'voucher_no': 'J/1', 'ledger_entries': <Object?>[<String, Object?>{'ledger_name': 'Rent A/c', 'amount': 800, 'is_debit': true}, <String, Object?>{'ledger_name': 'HDFC Bank', 'amount': 800, 'is_debit': false}]}},
        ];
      case '/api/mobile/notifications':
        body = <String, Object?>{'success': true, 'notifications': <Object?>[<String, Object?>{'id': 4, 'title': 'Entry failed', 'message': 'R/6 failed', 'is_read': false, 'created_at': '2026-10-03T05:00:00.000Z', 'type': 'entry_failed'}]};
      case '/api/mobile/notifications/config':
        body = <String, Object?>{'success': true, 'config': <String, Object?>{'sync_completed': false, 'create_entry': true}};
      case '/users':
        body = <Object?>[<String, Object?>{'id': 7, 'username': 'ravi', 'email': 'ravi@x.in', 'role': 'ADMIN'}, <String, Object?>{'id': 9, 'username': 'asha', 'email': 'asha@x.in', 'role': 'USER'}];
      case '/api/mobile-voucher-command/receipt/create':
      case '/api/mobile-voucher-command/journal/create':
      case '/api/mobile-voucher-command/create':
        body = <String, Object?>{'success': true, 'command_id': 55, 'voucher_guid': 'g', 'status': 'QUEUED'};
      default:
        if (p.startsWith('/api/mobile/notifications/') && p.endsWith('/read')) {
          body = <String, Object?>{'success': true};
        } else {
          return http.Response('{"message":"Unauthorized"}', 401);
        }
    }
    return http.Response(jsonEncode(body), 200, headers: <String, String>{'content-type': 'application/json'});
  });

  ApiTallyRepository repo() => ApiTallyRepository(
    client: ApiClient(client: client, baseUrl: 'https://api.test'),
    sessions: MemorySessionStore(),
    clock: () => DateTime(2026, 10, 3, 11),
  );

  List<http.Request> to(String path) => calls.where((http.Request r) => r.url.path == path).toList();
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
      final String old = 'x.${base64Url.encode(utf8.encode('{"exp":1000}')).replaceAll('=', '')}.y';
      expect(jwtExpired(old), isTrue);
    });
  });

  group('request bodies (exact backend field names, Dr/Cr)', () {
    test('sales: paise totals, GST split, payment', () {
      final Map<String, Object?> b = salesBody(const EntryDraft(
        type: 'sales', no: 'S/200', date: '2026-10-03', party: 'Mehta Electricals',
        due: '2026-10-18', amount: 1000, mode: 'cash',
        lines: <Line>[Line('Wire', 1850.5, 3, 'coil', 18, guid: 'I1', hsn: '8544')],
      ));
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
    });
    test('receipt / payment use their own field names', () {
      final Map<String, Object?> r = receiptBody(const EntryDraft(
        type: 'receipt', no: 'R/7', date: '2026-10-03', party: 'Mehta', amount: 2500.255,
        mode: 'upi', utr: 'UTR1', bank: 'HDFC', account: 'HDFC Bank', ref: 'Against S/101',
      ));
      expect(r['amount_received'], 2500.26);
      final Map<String, Object?> rp = r['payment']! as Map<String, Object?>;
      expect(rp, <String, Object?>{'payment_mode': 'upi', 'deposit_account': 'HDFC Bank', 'bank_name': 'HDFC', 'upi_ref': 'UTR1'});
      final Map<String, Object?> y = paymentBody(const EntryDraft(
        type: 'payment', no: 'P/2', date: '2026-10-03', party: 'Polycab', amount: 9000,
        mode: 'cheque', utr: '000123', account: 'HDFC Bank',
      ));
      expect(y['amount_paid'], 9000);
      expect(y.containsKey('amount_received'), isFalse);
      expect((y['payment']! as Map<String, Object?>)['transaction_instrument_no'], '000123');
      expect((y['payment']! as Map<String, Object?>)['bank_account'], 'HDFC Bank');
    });
    test('journal: Dr → is_debit true, Cr → false', () {
      final Map<String, Object?> j = journalBody(const EntryDraft(
        type: 'journal', no: 'J/2', date: '2026-10-03', party: '',
        journal: <JLine>[JLine('Dr', 'Rent A/c', '', 800.5), JLine('Cr', 'HDFC Bank', '', 800.5)],
      ));
      expect(j['ledger_entries'], <Object?>[
        <String, Object?>{'ledger_name': 'Rent A/c', 'amount': 800.5, 'is_debit': true},
        <String, Object?>{'ledger_name': 'HDFC Bank', 'amount': 800.5, 'is_debit': false},
      ]);
    });
  });

  group('ApiTallyRepository against the fake backend', () {
    test('login sends the chosen loginType and keeps the token', () async {
      final FakeBackend f = FakeBackend();
      final ApiTallyRepository r = f.repo();
      final AuthUser u = await r.login('Ravi@X.in ', 'secret', 'USER');
      expect(u.role, 'USER');
      final Map<String, Object?> sent = jsonDecode(f.to('/auth/login').single.body) as Map<String, Object?>;
      expect(sent, <String, Object?>{'username': 'ravi@x.in', 'password': 'secret', 'loginType': 'USER'});
      await r.login('ravi@x.in', 'secret', 'ADMIN');
      expect(r.user!.isAdmin, isTrue);
      expect(r.user!.plan, 'Professional');
      await expectLater(r.login('ravi@x.in', 'bad', 'ADMIN'), throwsA(isA<ApiException>().having((ApiException e) => e.kind, 'kind', ApiErrorKind.unauthorized)));
    });

    test('refreshAll: company-scoped outstanding, month totals, parties', () async {
      final FakeBackend f = FakeBackend();
      final ApiTallyRepository r = f.repo();
      await r.login('ravi@x.in', 'secret', 'ADMIN');
      await r.refreshAll();
      // Bearer token on data calls.
      expect(f.to('/ledger').single.headers['Authorization'], 'Bearer $kToken');
      // Outstanding: only co-1, pending > 0.
      final OutstandingSummary rs = r.outstanding(true), ps = r.outstanding(false);
      expect(rs.total, 15000.5);
      expect(rs.parties, 1);
      expect(rs.late, 10000.5);
      expect(rs.ageing, <num>[5000, 10000.5, 0, 0]);
      expect(rs.mismatch, isFalse); // equals /dashboard/summary
      expect(ps.total, 9000);
      expect(ps.ageing, <num>[0, 0, 9000, 0]);
      expect(r.receivables().first.txt, '13 days late');
      // Month totals: Sales Order and inactive Payment excluded; Sep row not in Oct.
      final MonthTotals m = r.monthTotals();
      expect(m.amount['sales'], 11800);
      expect(m.amount['receipt'], 2500.25);
      expect(m.amount['payment'], isNull);
      expect(m.amount['other'], 99999);
      final Map<String, SumCard> cards = r.moneyCards();
      expect(cards['toGet']!.v, 15000.5);
      expect(cards['mIn']!.v, 2500.25);
      expect(cards['sales']!.v, 11800);
      expect(cards['mOut']!.v, 0);
      expect(cards['cash']!.v, isNull, reason: 'Dr/Cr not sent by server');
      // Full history: both pages, duplicate removed, inactive dropped.
      expect(r.vouchers().map((Voucher v) => v.guid), <String>['V1', 'V2', 'V3', 'V9']);
      expect(r.vouchersComplete, isTrue);
      // Parties: every ledger; customer / supplier only from the Tally group.
      final List<Party> ps2 = r.parties();
      expect(ps2.map((Party p) => p.name), <String>['Mehta Electricals', 'Polycab Wires', 'HDFC Bank', 'Rent A/c']);
      expect(ps2.map((Party p) => p.type), <String>['c', 's', 'o', 'o']);
      expect(ps2.first.bal, 15000.5);
      expect(ps2[1].bal, 9000);
      expect(r.accounts().single.t, 'HDFC Bank');
      // Items: string-free numbers, finished stock.
      expect(r.items().first.worth, 22500);
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
      expect(r.status(DataSet.vouchers).state, LoadState.ready);
    });

    test('purchase is blocked; receipt posts the right body', () async {
      final FakeBackend f = FakeBackend();
      final ApiTallyRepository r = f.repo();
      await r.login('ravi@x.in', 'secret', 'ADMIN');
      await r.refreshAll();
      final SubmitResult p = await r.submitEntry(const EntryDraft(type: 'purchase', no: '', date: '2026-10-03', party: 'Polycab Wires'));
      expect(p.ok, isFalse);
      expect(f.to('/api/mobile-voucher-command/create'), isEmpty);
      final SubmitResult ok = await r.submitEntry(const EntryDraft(type: 'receipt', no: 'R/7', date: '2026-10-03', party: 'Mehta Electricals', amount: 500, mode: 'cash', account: 'Cash'));
      expect(ok.ok, isTrue);
      expect(ok.commandId, '55');
      final Map<String, Object?> b = jsonDecode(f.to('/api/mobile-voucher-command/receipt/create').single.body) as Map<String, Object?>;
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
      final AppController c = AppController(store: LocalStorage.memory(), repo: r);
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
      c.jl = <JLine>[const JLine('Dr', 'Rent A/c', '', 800), const JLine('Cr', 'HDFC Bank', '', 700)];
      expect(c.flowBlocker, 'Both sides must be equal');
      c.jl = <JLine>[const JLine('Dr', 'Rent A/c', '', 800), const JLine('Cr', 'HDFC Bank', '', 800)];
      expect(c.flowBlocker, isNull);
      c.saveFlow(false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(f.to('/api/mobile-voucher-command/journal/create'), hasLength(1));
      expect(c.screen, 'home');
      // Purchase shows the blocker on the check step.
      c.startFlow('purchase');
      expect(c.flowBlocker, contains('Purchase cannot be sent'));
      f.expire = true;
      await r.refreshAll();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.screen, 'login');
      c.dispose();
    });
  });
}
