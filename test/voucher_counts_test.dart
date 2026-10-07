// Exact voucher counts per date period and type: all history counted by the
// server (no history download), periods with the lists' own rules.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/data/repositories/api_tally_repository.dart';
import 'package:tallyconnect_ui/data/repositories/tally_repository.dart';
import 'package:tallyconnect_ui/data/repositories/voucher_pager.dart'
    show exactTypeCounts;
import 'package:tallyconnect_ui/main.dart';

import 'api_integration_test.dart' show FakeBackend;

/// Real Figtree metrics (the test font draws every glyph as a wide square).
Future<void> loadFigtree() async {
  final FontLoader l = FontLoader('Figtree');
  for (final String w in <String>[
    'Regular',
    'Medium',
    'SemiBold',
    'Bold',
    'ExtraBold',
  ]) {
    final List<int> b = File('assets/fonts/Figtree-$w.ttf').readAsBytesSync();
    l.addFont(
      Future<ByteData>.value(ByteData.sublistView(Uint8List.fromList(b))),
    );
  }
  await l.load();
}

void main() {
  setUpAll(loadFigtree);
  group('exact type counts from the server\'s ILIKE counts', () {
    test('nested names are separated', () {
      // ILIKE '%Sales%' also counts "Sales Order" and "Sales Order Cancel".
      expect(
        exactTypeCounts(<String, int>{
          'Sales': 9,
          'Sales Order': 3,
          'Sales Order Cancel': 1,
          'Receipt': 4,
        }),
        <String, int>{
          'sales': 6,
          'sales order': 2,
          'sales order cancel': 1,
          'receipt': 4,
        },
      );
    });

    test('case variants are one type', () {
      expect(
        exactTypeCounts(<String, int>{'Sales': 4, 'SALES': 4}),
        <String, int>{'sales': 4},
      );
    });
  });

  group('repository counts', () {
    Future<(FakeBackend, ApiTallyRepository)> login() async {
      final FakeBackend f = FakeBackend();
      final ApiTallyRepository r = f.repo();
      await r.login('ravi@x.in', 'secret', 'ADMIN');
      await r.refreshAll();
      return (f, r);
    }

    test('all time: server counts only, one row per call', () async {
      final (FakeBackend f, ApiTallyRepository r) = await login();
      final int before = f.to('/voucher-entry/paged').length;
      await r.loadVoucherCounts('all');
      final VoucherCounts c = r.voucherCounts('all')!;
      expect(c.complete, isTrue);
      expect(c.forFilter('all'), 5);
      expect(c.forFilter('sales'), 1); // "Sales Order" is not a sale
      expect(c.forFilter('type:Sales Order'), 1);
      expect(c.forFilter('other'), 1);
      expect(c.forFilter('receipt'), 1);
      expect(c.forFilter('payment'), 2); // V4 and V9
      expect(c.forFilter('journal'), 0);
      expect(c.otherTypes, <String>['Sales Order']);
      // 1 total + 4 types, each limit=1: nothing else is downloaded.
      final List<http.Request> calls = f
          .to('/voucher-entry/paged')
          .sublist(before);
      expect(calls, hasLength(5));
      expect(
        calls.every((http.Request q) => q.url.queryParameters['limit'] == '1'),
        isTrue,
      );
      // Cached: no second count while fresh.
      await r.loadVoucherCounts('all');
      expect(f.to('/voucher-entry/paged').length, before + 5);
    });

    test('this month, last 7 days, today: same rules as the lists', () async {
      final (FakeBackend _, ApiTallyRepository r) = await login();
      // This month: the complete month set (V1–V4).
      final VoucherCounts m = r.voucherCounts('month')!;
      expect(m.forFilter('all'), 4);
      expect(m.forFilter('sales'), 1);
      expect(m.forFilter('receipt'), 1);
      expect(m.forFilter('payment'), 1);
      // Last 7 days (27 Sep – 3 Oct): V1, V2, V3, V4 and V9.
      await r.loadVoucherCounts('week');
      final VoucherCounts w = r.voucherCounts('week')!;
      expect(w.forFilter('all'), 5);
      expect(w.forFilter('payment'), 2);
      // Today (3 Oct): V2 only.
      await r.loadVoucherCounts('today');
      expect(r.voucherCounts('today')!.forFilter('all'), 1);
      expect(r.voucherCounts('today')!.forFilter('receipt'), 1);
      expect(r.voucherCounts('today')!.forFilter('sales'), 0);
    });
  });

  testWidgets('hub: All time shows totals; counts follow the period', (
    WidgetTester t,
  ) async {
    t.view.physicalSize = const Size(390 * 3, 1600 * 3);
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
    c.go('vHub');
    for (int i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(c.vPeriod, 'all');
    expect(find.text('5 total'), findsOneWidget); // All
    expect(find.text('1 total'), findsWidgets); // Sales, Receipt, …
    expect(find.text('2 total'), findsOneWidget); // Payment
    // No tile says "N this month" while All time is selected.
    expect(find.textContaining(RegExp(r'^\d+ this month$')), findsNothing);
    // This month: the month's counts.
    c.update(() => c.vPeriod = 'month');
    for (int i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('4 this month'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^\d+ total$')), findsNothing);
    // A tile opens the list with the same period.
    await t.tap(find.text('4 this month'));
    for (int i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(c.screen, 'vList');
    expect(c.vPeriod, 'month');
    await t.pump(const Duration(seconds: 6));
  });
}
