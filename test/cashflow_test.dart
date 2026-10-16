// Cash flow forecast: the server's answer read into the app, the controller
// (modes, doubtful bills, a week's bills, errors, Demo Company), the Reports
// tile (same access as financial reports), the screens at 320 px and the
// PDF.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/share/share_doc.dart' show ShareDoc;
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/demo_repository.dart';
import 'package:tallyconnect_ui/main.dart';
import 'package:tallyconnect_ui/presentation/screens/cashflow_screens.dart'
    show cashflowDoc, cfWeekLabel;

import 'api_integration_test.dart' show FakeBackend;
import 'screens_test.dart' show loadFigtree;

Future<AppController> _start(FakeBackend f, {String screen = 'home'}) async {
  final DemoAwareRepository r = DemoAwareRepository(live: f.repo());
  await r.login('ravi@x.in', 'secret', 'ADMIN');
  await r.refreshAll();
  final AppController c = AppController(
    store: LocalStorage.memory(),
    repo: r,
    startScreen: screen,
  );
  c.afterRefresh(quietOk: true);
  return c;
}

void main() {
  group('controller', () {
    test('opens with payment habits; figures from the server', () async {
      final FakeBackend f = FakeBackend();
      final AppController c = await _start(f);
      await c.openCashflow();
      expect(c.screen, 'cashflow');
      expect(f.cashflowQueries.single, <String, String>{
        'path': '/api/cashflow/forecast',
        'mode': 'adjusted',
        'doubtful': '0',
      });
      final CashForecast d = c.cfData!;
      expect(d.company, 'Rajlaxmi Traders');
      expect(d.adjusted, isTrue);
      expect(d.opening, 21000);
      expect(d.openingBasedOn, DateTime(2026, 9, 30));
      expect(d.accounts.map((CashAccount a) => a.name), <String>[
        'HDFC Bank',
        'Cash',
      ]);
      expect(d.weeks, hasLength(13));
      expect(d.weeks.first.start, DateTime(2026, 9, 28));
      expect(d.weeks.first.closing, 21750);
      expect(d.weeks[1].shortfall, isTrue);
      expect(d.shortfallWeek, DateTime(2026, 10, 5));
      expect(d.endBalance, 21000 + 4750 - 25000);
      expect((d.totalIn, d.totalOut), (4750, 25000));
      expect((d.doubtfulBills, d.doubtfulAmount, d.doubtfulDays), (1, 900, 90));
      expect(d.top.first.party, 'Mehta Electricals');
      expect(d.top.first.delayDays, 12);
      expect(d.top[1].delaySource, 'company');
      expect(d.companyDelay, 9);
      // Phase 2: exact delays where Tally has bill-wise receipts; advances.
      expect(d.top.first.exact, isTrue);
      expect(d.top[1].method, isNull);
      expect((d.delayMethod, d.partiesExact), ('mixed', 1));
      expect(d.advancesChecked, isTrue);
      expect(
        (d.advancesIn, d.advancesInBills, d.advancesOutBills),
        (600, 1, 0),
      );
      c.dispose();
    });

    test('due dates, doubtful bills, refresh; a week\'s bills', () async {
      final FakeBackend f = FakeBackend();
      final AppController c = await _start(f);
      await c.openCashflow();
      await c.setCfMode('due');
      expect(f.cashflowQueries.last['mode'], 'due');
      expect(c.cfData!.adjusted, isFalse);
      await c.setCfDoubtful(true);
      expect(f.cashflowQueries.last['doubtful'], '1');
      expect(c.cfData!.doubtfulBills, 0);
      await c.loadCashflow(refresh: true);
      expect(f.cashflowQueries.last['refresh'], '1');

      await c.openCfWeek(c.cfData!.weeks[1]);
      expect(c.screen, 'cfWeek');
      expect(f.cashflowQueries.last, <String, String>{
        'path': '/api/cashflow/week',
        'start': '2026-10-05',
        'mode': 'due',
        'doubtful': '1',
      });
      final CashWeekDetail w = c.cfWeekData!;
      expect(w.week.outflow, 25000);
      expect(w.outflows.single.party, 'Polycab Wires');
      expect(w.inflows.single.bill, 'S/9'); // due 2 Oct, due-date mode
      c.dispose();
    });

    test('older server / no access / Demo Company: clear messages', () async {
      final FakeBackend f = FakeBackend()..cashflowMissing = true;
      final AppController c = await _start(f);
      await c.openCashflow();
      expect(
        c.cfError,
        'The cash flow forecast is not available on the server yet.',
      );
      expect(c.cfData, isNull);
      c.dispose();

      final FakeBackend g = FakeBackend()..finAllowed = false;
      final AppController d = await _start(g);
      await d.openCashflow();
      expect(d.cfError, 'Ask your admin for access to financial reports.');
      d.dispose();

      final FakeBackend h = FakeBackend()..newAccount = true;
      final AppController e = await _start(h);
      expect(e.demo, isTrue);
      await e.openCashflow();
      expect(e.screen, isNot('cashflow'));
      expect(h.cashflowQueries, isEmpty);
      e.dispose();

      // Sample data (no account): nothing is asked.
      final AppController s = AppController(store: LocalStorage.memory());
      await s.openCashflow();
      expect(s.screen, isNot('cashflow'));
      expect(s.toast, contains('TallyConnect account'));
      s.dispose();
    });

    test('PDF: headline figures and one row per week', () async {
      final FakeBackend f = FakeBackend();
      final AppController c = await _start(f);
      await c.openCashflow();
      final ShareDoc doc = cashflowDoc(c, c.cfData!);
      expect(doc.title, 'Cash flow forecast');
      expect(doc.fileName, 'TallyConnect_Cash_flow_forecast.pdf');
      expect(doc.facts.first, ('Cash + bank today', '₹21,000'));
      expect(doc.table!.rows, hasLength(13));
      expect(doc.table!.rows.first, <String>[
        '28 Sep – 4 Oct',
        '₹21,000',
        '₹750',
        '₹0',
        '₹21,750',
      ]);
      expect(doc.totals.last, ('Balance after 13 weeks', '₹750'));
      c.dispose();
    });

    test('week labels', () {
      expect(
        cfWeekLabel(DateTime(2026, 10, 12), DateTime(2026, 10, 18)),
        '12–18 Oct',
      );
      expect(
        cfWeekLabel(DateTime(2026, 9, 28), DateTime(2026, 10, 4)),
        '28 Sep – 4 Oct',
      );
    });
  });

  group('screens (320 px)', () {
    setUpAll(loadFigtree);

    Future<AppController> open(WidgetTester t, FakeBackend f) async {
      t.view.physicalSize = const Size(320 * 3, 720 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final AppController c = await _start(f);
      await t.pumpWidget(
        ProviderScope(
          overrides: <Override>[appProvider.overrideWith((Ref ref) => c)],
          child: const TallyConnectApp(),
        ),
      );
      return c;
    }

    Future<void> settle(WidgetTester t) async {
      for (int i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('Reports tile → forecast → a week; no overflow', (
      WidgetTester t,
    ) async {
      final FakeBackend f = FakeBackend();
      final AppController c = await open(t, f);
      await c.checkFinancialAccess(force: true);
      c.go('reports');
      await settle(t);
      await t.ensureVisible(find.byKey(const ValueKey<String>('cashflowTile')));
      await settle(t);
      await t.tap(find.byKey(const ValueKey<String>('cashflowTile')));
      await settle(t);
      expect(c.screen, 'cashflow');
      expect(find.text('₹21,000'), findsWidgets);
      expect(find.byKey(const ValueKey<String>('cfChart')), findsOneWidget);
      expect(find.textContaining('Cash may run short'), findsOneWidget);
      expect(t.takeException(), isNull);
      // Week list and customers' habits further down.
      await t.scrollUntilVisible(
        find.byKey(const ValueKey<String>('cfWeek-1')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.byKey(const ValueKey<String>('cfWeek-1')));
      await settle(t);
      expect(c.screen, 'cfWeek');
      expect(find.text('Polycab Wires'), findsOneWidget);
      expect(t.takeException(), isNull);
      c.back();
      await settle(t);
      await t.scrollUntilVisible(
        find.text('Mehta Electricals'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Pays ~12 days late'), findsOneWidget);
      expect(find.textContaining('18 bills (exact)'), findsOneWidget);
      // Notes: which delays are exact, and the advances left out.
      await t.scrollUntilVisible(
        find.textContaining('Advances received'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.textContaining('Delays are exact for 1 customer'),
        findsOneWidget,
      );
      expect(find.textContaining('₹600 in 1 bill'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 6));
    });

    testWidgets('no cash figures: still shown, without balances', (
      WidgetTester t,
    ) async {
      final FakeBackend f = FakeBackend()..cashflowNoOpening = true;
      final AppController c = await open(t, f);
      await c.openCashflow();
      await settle(t);
      expect(find.text('Not available'), findsOneWidget);
      expect(find.text('Net change over 13 weeks'), findsOneWidget);
      expect(find.textContaining('Cash may run short'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 6));
    });

    testWidgets('tile hidden without financial-report access', (
      WidgetTester t,
    ) async {
      final FakeBackend f = FakeBackend()..finAllowed = false;
      final AppController c = await open(t, f);
      await c.checkFinancialAccess(force: true);
      c.go('reports');
      await settle(t);
      expect(find.byKey(const ValueKey<String>('cashflowTile')), findsNothing);
      await t.pump(const Duration(seconds: 6));
    });
  });
}
