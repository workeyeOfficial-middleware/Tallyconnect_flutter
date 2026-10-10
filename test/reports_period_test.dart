// Reports: This month / All time period; no barcode scanning anywhere;
// exact all-time totals (₹28,56,94,078.63 + a synced ₹87 receipt).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/design/tc_icon_paths.dart';
import 'package:tallyconnect_ui/core/design/tc_kit.dart';
import 'package:tallyconnect_ui/core/share/report_data.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/core/utils/format.dart';
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/api_tally_repository.dart';
import 'package:tallyconnect_ui/data/repositories/tally_repository.dart';
import 'package:tallyconnect_ui/main.dart';

import 'api_integration_test.dart' show FakeBackend;
import 'screens_test.dart' show loadFigtree;

Future<AppController> _boot(WidgetTester t, String start) async {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final AppController c = AppController(
    store: LocalStorage.memory(),
    startScreen: start,
  );
  await t.pumpWidget(
    ProviderScope(
      overrides: <Override>[appProvider.overrideWith((Ref ref) => c)],
      child: const TallyConnectApp(),
    ),
  );
  await t.pump(const Duration(milliseconds: 600));
  return c;
}

Future<void> _settle(WidgetTester t) async {
  for (int i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('no barcode scanning', () {
    setUpAll(loadFigtree);

    testWidgets('Items search has no scan button', (WidgetTester t) async {
      final AppController c = await _boot(t, 'home');
      c.jump('items');
      await _settle(t);
      expect(
        find.byWidgetPredicate((Widget w) => w is CBtn && w.icon == 'scan'),
        findsNothing,
      );
      expect(find.textContaining('arcode'), findsNothing);
      expect(tcIconPaths.containsKey('scan'), isFalse);
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 6));
    });
  });

  group('report period', () {
    test('chosen period is kept on the phone', () {
      final LocalStorage s = LocalStorage.memory();
      final AppController c = AppController(store: s);
      expect(c.repPeriod, 'month');
      c.setRepPeriod('all');
      c.dispose();
      final AppController c2 = AppController(store: s);
      expect(c2.repPeriod, 'all');
      c2.setRepPeriod('bogus'); // ignored
      expect(c2.repPeriod, 'all');
      c2.dispose();
    });

    test('demo data: All time covers every month, This month one', () {
      final TallyRepository r = MockTallyRepository();
      for (final String id in <String>['day', 'sreg', 'preg']) {
        final ReportData m = reportData(r, id);
        final ReportData a = reportData(r, id, period: 'all');
        expect(a.rows.length, greaterThanOrEqualTo(m.rows.length), reason: id);
        expect(a.period, 'All time');
        expect(a.partial, isFalse);
      }
      final ReportData all = reportData(r, 'day', period: 'all');
      expect(all.total, inr(sumRupees(r.vouchers().map((Voucher v) => v.amt))));
    });

    test(
      'server, All time: exact totals while only a few pages are read',
      () async {
        final FakeBackend f = FakeBackend()
          ..typeTotals = <String, num>{
            'Receipt': 285694078.63,
            'Sales': 1250.75,
            'Payment': 400,
            'Sales Order': 0,
          };
        final ApiTallyRepository r = f.repo();
        await r.login('ravi@x.in', 'secret', 'ADMIN');
        await r.refreshAll();
        final AppController c = AppController(
          store: LocalStorage.memory(),
          repo: r,
          startScreen: 'home',
        )..setRepPeriod('all');
        // Being counted: never a stale or partial figure.
        expect(c.periodAmountText('all', 'receipt'), '…');
        await r.loadVoucherCounts('all');
        expect(c.periodAmountText('all', 'receipt'), '₹28,56,94,078.63');

        // Sales list with no page read yet: the server's exact total.
        final ReportData d = reportData(
          r,
          'sreg',
          period: 'all',
          loaded: const <Voucher>[],
        );
        expect(d.total, '₹1,250.75');
        expect(d.totalLabel, '1 bills');
        expect(d.partial, isTrue);
        expect(d.hasChart, isFalse); // never a chart of part of the history
        expect(d.period, startsWith('All time'));

        // Agent syncs a new ₹87 receipt.
        f.typeTotals!['Receipt'] = 285694165.63;
        f.lastSync = '2026-10-03T05:00:00.000Z';
        await c.liveCheck();
        expect(c.periodAmountText('all', 'receipt'), '…');
        await r.loadVoucherCounts('all');
        expect(c.periodAmountText('all', 'receipt'), '₹28,56,94,165.63');
        c.dispose();
      },
    );

    testWidgets('Reports and every report render for both periods', (
      WidgetTester t,
    ) async {
      final AppController c = await _boot(t, 'home');
      c.jump('reports');
      await _settle(t);
      expect(find.text(c.periodLabel('month')), findsOneWidget);
      await t.tap(find.text('All time'));
      await _settle(t);
      expect(c.repPeriod, 'all');
      expect(find.text('All time'), findsWidgets);
      for (final String period in <String>['all', 'month']) {
        c.setRepPeriod(period);
        for (final Report r in c.repo.reports()) {
          c.go('report', <String, Object?>{'report': r.id});
          await _settle(t);
          expect(t.takeException(), isNull, reason: '${r.id} $period');
          c.back();
          await _settle(t);
        }
      }
      // Period switch on a voucher report.
      c.go('report', <String, Object?>{'report': 'sreg'});
      await _settle(t);
      await t.tap(find.text('All time').first);
      await _settle(t);
      expect(c.repPeriod, 'all');
      expect(find.textContaining('All time'), findsWidgets);
      await t.pump(const Duration(seconds: 6));
    });
  });
}
