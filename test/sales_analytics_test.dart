// Sales analytics: the dashboard data from the server, periods (presets and
// a custom range that leaves other pages alone), errors, Demo Company, the
// screen at 320 px and the PDF.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/share/share_doc.dart' show ShareDoc;
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/core/utils/format.dart';
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/demo_repository.dart';
import 'package:tallyconnect_ui/main.dart';
import 'package:tallyconnect_ui/presentation/screens/sales_screens.dart'
    show salesDoc;

import 'api_integration_test.dart' show FakeBackend;
import 'screens_test.dart' show loadFigtree;

Future<AppController> _start(FakeBackend f) async {
  final DemoAwareRepository r = DemoAwareRepository(live: f.repo());
  await r.login('ravi@x.in', 'secret', 'ADMIN');
  await r.refreshAll();
  final AppController c = AppController(
    store: LocalStorage.memory(),
    repo: r,
    startScreen: 'home',
  );
  c.afterRefresh(quietOk: true);
  return c;
}

void main() {
  group('controller', () {
    test('opens with this month; figures from the server', () async {
      final FakeBackend f = FakeBackend();
      final AppController c = await _start(f);
      await c.openSalesAnalytics();
      expect(c.screen, 'salesDash');
      final DateTime t = c.today;
      expect(f.salesQueries.single, <String, String>{
        'from': ymd(DateTime(t.year, t.month)),
        'to': ymd(DateTime(t.year, t.month, t.day)),
      });
      final SalesDash d = c.salesData!;
      expect(d.sales, 20060);
      expect(d.netSales, 18880);
      expect(d.growthPct, 100.6);
      expect(d.byDay, isTrue);
      expect(d.points, hasLength(30));
      expect(d.topCustomers.first.share, 70.6);
      expect(d.topItemsQty.first.item, 'Switch 6A');
      expect(d.groups.first, ('Switchgear', 9000));
      expect((d.newCustomers, d.repeatCustomers), (1, 1));
      c.dispose();
    });

    test('presets and a custom range (other pages keep theirs)', () async {
      final FakeBackend f = FakeBackend();
      final AppController c = await _start(f);
      await c.openSalesAnalytics();
      await c.setSalesPreset('fy');
      final DateTime t = c.today;
      final int fy = t.month >= 4 ? t.year : t.year - 1;
      expect(f.salesQueries.last['from'], '$fy-04-01');
      expect(c.salesData!.byDay, isFalse);
      await c.setSalesPreset('lastMonth');
      expect(f.salesQueries.last, <String, String>{
        'from': ymd(DateTime(t.year, t.month - 1)),
        'to': ymd(DateTime(t.year, t.month, 0)),
      });
      final Object? before = c.range;
      await c.setSalesPreset('custom');
      expect(c.overlay, 'dateRange');
      c.setF('drFrom', '2026-01-01');
      c.setF('drTo', '2026-03-31');
      c.applyRange();
      await pumpEventQueue();
      expect(c.salesPreset, 'custom');
      expect(f.salesQueries.last, <String, String>{'from': '2026-01-01', 'to': '2026-03-31'});
      expect(c.salesPeriodLabel, '01 Jan 2026 – 31 Mar 2026');
      expect(c.range, before); // Vouchers / Reports range untouched
      c.dispose();
    });

    test('older server / Demo Company: clear messages', () async {
      final FakeBackend f = FakeBackend()..salesMissing = true;
      final AppController c = await _start(f);
      await c.openSalesAnalytics();
      expect(c.salesError, 'Sales analytics are not available on the server yet.');
      expect(c.salesData, isNull);
      c.dispose();

      final FakeBackend g = FakeBackend()..newAccount = true;
      final AppController d = await _start(g);
      expect(d.demo, isTrue);
      await d.openSalesAnalytics();
      expect(d.screen, isNot('salesDash'));
      expect(d.toast, contains('not Demo Company'));
      expect(g.salesQueries, isEmpty);
      d.dispose();
    });

    test('PDF: headline numbers, customers, items', () async {
      final FakeBackend f = FakeBackend();
      final AppController c = await _start(f);
      await c.openSalesAnalytics();
      final ShareDoc doc = salesDoc(c, c.salesData!);
      expect(doc.title, 'Sales analytics');
      expect(doc.fileName, 'TallyConnect_Sales_analytics.pdf');
      expect(doc.totals.first, ('Sales (incl. GST)', '₹20,060'));
      final String rows = doc.table!.rows.map((List<String> r) => r.join(' ')).join('\n');
      expect(rows, contains('Gupta Stores'));
      expect(rows, contains('Switch 6A'));
      c.dispose();
    });
  });

  group('screen (320 px)', () {
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

    testWidgets('Reports tile → dashboard; every section; no overflow', (
      WidgetTester t,
    ) async {
      final FakeBackend f = FakeBackend();
      final AppController c = await open(t, f);
      c.go('reports');
      await settle(t);
      await t.tap(find.byKey(const ValueKey<String>('salesTile')));
      await settle(t);
      expect(c.screen, 'salesDash');
      expect(find.byKey(const ValueKey<String>('salesTotal')), findsOneWidget);
      expect(find.text('₹20,060'), findsOneWidget);
      expect(find.textContaining('+100.6% vs previous period'), findsOneWidget);
      expect(t.takeException(), isNull);
      // Lower sections exist (built lazily as the page scrolls).
      await t.scrollUntilVisible(
        find.byKey(const ValueKey<String>('salesItems')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const ValueKey<String>('salesTrend')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('salesCustomers')), findsWidgets);
      await t.ensureVisible(find.text('By quantity'));
      await settle(t);
      await t.tap(find.text('By quantity'));
      await settle(t);
      expect(c.salesItemsBy, 'qty');
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 6));
    });

    testWidgets('no sales in the period: a plain message', (WidgetTester t) async {
      final FakeBackend f = FakeBackend()..salesEmpty = true;
      final AppController c = await open(t, f);
      await c.openSalesAnalytics();
      await settle(t);
      expect(find.text('No sales in this period.'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 6));
    });
  });
}
