// Financial statements in the app: who sees them, periods built only from
// the dates the Agent synced, the four reports, team access, errors, demo,
// and the screens at phone widths.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/core/utils/format.dart' show ymd;
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/api_tally_repository.dart'
    show DataSet;
import 'package:tallyconnect_ui/data/repositories/demo_repository.dart';
import 'package:tallyconnect_ui/core/share/share_doc.dart' show ShareDoc;
import 'package:tallyconnect_ui/main.dart';
import 'package:tallyconnect_ui/presentation/screens/financial_screens.dart'
    show finDoc;

import 'api_integration_test.dart' show FakeBackend;
import 'screens_test.dart' show loadFigtree;

Future<AppController> _start(FakeBackend f) async {
  final DemoAwareRepository r = DemoAwareRepository(live: f.repo());
  await r.login('ravi@x.in', 'secret', 'ADMIN');
  await r.refreshAll();
  await r.ensure(DataSet.ledgers);
  final AppController c = AppController(
    store: LocalStorage.memory(),
    repo: r,
    startScreen: 'home',
  );
  c.afterRefresh(quietOk: true);
  return c;
}

Map<String, Object?> _last(FakeBackend f, String path) => f.finRequests
    .lastWhere((Map<String, Object?> x) => x['path'] == '/api/financial/$path');

void main() {
  group('controller', () {
    test('who sees them: allowed login yes; not allowed / demo no', () async {
      final FakeBackend f = FakeBackend();
      final AppController c = await _start(f);
      await c.checkFinancialAccess();
      expect(c.finCanView, isTrue);
      c.dispose();

      final FakeBackend g = FakeBackend()..finAllowed = false;
      final AppController d = await _start(g);
      await d.checkFinancialAccess();
      expect(d.finCanView, isFalse);
      d.dispose();

      final FakeBackend h = FakeBackend()..newAccount = true;
      final AppController e = await _start(h);
      expect(e.demo, isTrue);
      await e.checkFinancialAccess();
      expect(e.finCanView, isFalse);
      expect(h.finRequests, isEmpty); // demo never asks the server
      e.dispose();
    });

    test(
      'P&L: this year by default; only periods with Tally figures',
      () async {
        final FakeBackend f = FakeBackend();
        final AppController c = await _start(f);
        await c.openFinancial('pl');
        expect(c.screen, 'finReport');
        expect(_last(f, 'profit-loss')['from'], '2026-04-01');
        expect(_last(f, 'profit-loss')['to'], '2026-10-03');
        expect(c.finData!.n('net_profit'), 57000);
        expect(c.finPresets.map(((String, String) x) => x.$1), <String>[
          'fy',
          'month',
          'lastMonth',
          'lastFy',
          'pick',
        ]);
        expect(c.finPresets[2].$2, 'Sep 2026');
        await c.setFinPreset('lastMonth');
        expect(_last(f, 'profit-loss')['from'], '2026-09-01');
        expect(_last(f, 'profit-loss')['to'], '2026-09-30');
        expect(c.finPeriodLabel, 'September 2026');
        await c.setFinPreset('lastFy');
        expect(_last(f, 'profit-loss')['from'], '2025-04-01');
        expect(_last(f, 'profit-loss')['to'], '2026-03-31');
        // A month whose previous month-end is not synced cannot be a period.
        final int before = f.finRequests.length;
        await c.pickFinMonth(DateTime(2026, 8, 31));
        expect(
          c.toast,
          contains('No Tally figures for the month before Aug 2026'),
        );
        expect(f.finRequests.length, before);
        await c.pickFinMonth(DateTime(2026, 9, 30));
        expect(_last(f, 'profit-loss')['from'], '2026-09-01');
        c.dispose();
      },
    );

    test('Balance Sheet / Trial Balance: as on dates', () async {
      final FakeBackend f = FakeBackend();
      final AppController c = await _start(f);
      await c.openFinancial('bs');
      expect(_last(f, 'balance-sheet')['as_on'], '2026-10-03');
      expect(c.finPresets.map(((String, String) x) => x.$2).take(3), <String>[
        'As on 3 Oct',
        'End of Sep 2026',
        'Last year end',
      ]);
      await c.setFinPreset('lastFy');
      expect(_last(f, 'balance-sheet')['as_on'], '2026-03-31');
      await c.pickFinMonth(DateTime(2026, 8, 31)); // any month end is fine here
      expect(_last(f, 'balance-sheet')['as_on'], '2026-08-31');
      await c.openFinancial('tb');
      expect(_last(f, 'trial-balance')['as_on'], '2026-10-03');
      expect(c.finData!.n('total_debit'), c.finData!.n('total_credit'));
      c.dispose();
    });

    test('Expenses: purchases switch asks the server again', () async {
      final FakeBackend f = FakeBackend();
      final AppController c = await _start(f);
      await c.openFinancial('exp');
      expect(c.finData!.n('total'), 35000);
      expect(c.finData!.byMonth.length, 2);
      c.toggleFinPurchases();
      await pumpEventQueue();
      expect(_last(f, 'expenses')['purchases'], '1');
      expect(c.finData!.n('total'), 155000);
      c.dispose();
    });

    test('not synced yet / no access: clear messages', () async {
      final FakeBackend f = FakeBackend()..finNotSynced = true;
      final AppController c = await _start(f);
      await c.openFinancial('pl');
      expect(c.finError, contains('Update the TallyConnect Agent'));
      expect(c.finData, isNull);
      c.dispose();

      // The server says why (e.g. closing stock values not synced yet).
      final FakeBackend h = FakeBackend()
        ..finNotSynced = true
        ..finReason = 'Closing stock values are not synced yet.';
      final AppController e = await _start(h);
      await e.openFinancial('bs');
      expect(e.finError, 'Closing stock values are not synced yet.');
      e.dispose();

      final FakeBackend g = FakeBackend()..finAllowed = false;
      final AppController d = await _start(g);
      await d.openFinancial('bs');
      expect(d.finError, 'Ask your admin for access to financial reports.');
      d.dispose();
    });

    test(
      'missing year-end closing stock: the admin enters it, reports reload',
      () async {
        final FakeBackend f = FakeBackend()..finStockNeeded.add('2026-03-31');
        final AppController c = await _start(f);
        await c.openFinancial('pl');
        expect(c.finPeriods!.stockNeeded, <DateTime>[DateTime(2026, 3, 31)]);
        expect(c.finPeriods!.canEnterStock, isTrue);
        c.openFinStock(DateTime(2026, 3, 31));
        expect(c.overlay, 'finStock');
        // Checked before sending.
        c.setF('fsValue', '-5');
        await c.saveFinStock();
        expect(c.finStockError, isNotNull);
        c.setF('fsValue', '');
        await c.saveFinStock();
        expect(c.finStockError, isNotNull);
        expect(f.finStockSaved, isEmpty);
        // Indian grouping accepted.
        c.setF('fsValue', '2,50,000.50');
        await c.saveFinStock();
        expect(f.finStockSaved.single, <String, Object?>{
          'as_on': '2026-03-31',
          'value': 250000.5,
        });
        expect(c.overlay, isNull);
        expect(c.finStockError, isNull);
        expect(c.finPeriods!.stockNeeded, isEmpty);
        expect(c.toast, contains('Closing stock saved'));
        c.dispose();
      },
    );

    test('admin gives and removes a team member\'s access', () async {
      final FakeBackend f = FakeBackend();
      final AppController c = await _start(f);
      await c.loadFinancialAccess();
      expect(c.finAccessIds, isEmpty);
      const Member m = Member('9', 'Asha', 'asha@x.in', 'Sales', 'active');
      await c.setMemberFinancialAccess(m, true);
      expect(f.finGranted, <String>{'9'});
      expect(c.finAccessIds, <String>{'9'});
      expect(c.toast, contains('Asha can now see financial reports'));
      await c.setMemberFinancialAccess(m, false);
      expect(f.finGranted, isEmpty);
      c.dispose();
    });

    test(
      'any period: Cash Flow, From / To, ledger vouchers keep the dates',
      () async {
        final FakeBackend f = FakeBackend()..finAnyPeriod = true;
        final AppController c = await _start(f);
        // The Cash Flow tile: the statement from cash / bank vouchers (not
        // the stored Tally figures, which may be empty).
        await c.openStatement('cf');
        expect(c.screen, 'finReport');
        expect(c.finKind, 'cf');
        final DateTime t = c.today;
        final DateTime fy = DateTime(t.month >= 4 ? t.year : t.year - 1, 4);
        expect(_last(f, 'cash-flow')['from'], ymd(fy));
        expect(_last(f, 'cash-flow')['to'], ymd(t));
        expect(c.finData!.n('closing'), 67000);
        expect(c.finData!.cashMonths, hasLength(2));
        expect(c.finData!.pairs('outflow_groups').first, (
          'Indirect Expenses',
          18000,
        ));
        expect(c.finData!.cashAccounts.first, ('HDFC Bank', 40000, 60000));
        // A month row: just that month.
        await c.pickCashMonth(DateTime(2026, 8));
        expect(_last(f, 'cash-flow')['from'], '2026-08-01');
        expect(_last(f, 'cash-flow')['to'], '2026-08-31');

        // From / To on a statement: any dates — also a To after today.
        await c.openFinancial('pl');
        c.openFinRange();
        expect(c.overlay, 'dateRange');
        expect(c.rangePresets, AppController.kRangePresets);
        c.setF('drFrom', '2024-04-01');
        final String future = ymd(t.add(const Duration(days: 40)));
        c.setF('drTo', future);
        expect(c.rangeError, isNull);
        c.applyRange();
        await pumpEventQueue();
        expect(_last(f, 'profit-loss')['to'], future);
        c.openFinRange();
        c.setF('drFrom', '2024-04-01');
        c.setF('drTo', '2026-09-15');
        expect(c.rangeError, isNull);
        c.applyRange();
        await pumpEventQueue();
        expect(c.overlay, isNull);
        expect(c.finPreset, 'range');
        expect(_last(f, 'profit-loss')['from'], '2024-04-01');
        expect(_last(f, 'profit-loss')['to'], '2026-09-15');

        // A ledger → its vouchers in the same period → a voucher.
        final FinNode salary = c.finData!
            .subNodes('indirect', 'expense')
            .first
            .children
            .firstWhere((FinNode n) => n.name == 'Salary');
        await c.openFinLedger(salary);
        expect(c.screen, 'finLedger');
        expect(_last(f, 'ledger-vouchers')['guid'], 'g-Salary');
        expect(_last(f, 'ledger-vouchers')['from'], '2024-04-01');
        expect(_last(f, 'ledger-vouchers')['to'], '2026-09-15');
        expect(c.finLed!.rows, hasLength(2));
        expect(c.finLed!.totalDebit, 18000);
        expect(c.finLed!.closing, -18000);
        // New dates on the ledger reload it with them.
        c.openFinRange();
        c.setF('drFrom', '2026-09-01');
        c.setF('drTo', '2026-09-30');
        c.applyRange();
        await pumpEventQueue();
        expect(_last(f, 'ledger-vouchers')['from'], '2026-09-01');
        expect(c.screen, 'finLedger');
        c.openFinVoucher(c.finLed!.rows.first);
        expect(c.screen, 'entryDetail');
        c.dispose();
      },
    );

    test(
      'each report keeps its From / To: Back, reopening, restarting',
      () async {
        final FakeBackend f = FakeBackend()..finAnyPeriod = true;
        final LocalStorage store = LocalStorage.memory();
        Future<AppController> start() async {
          final DemoAwareRepository r = DemoAwareRepository(live: f.repo());
          await r.login('ravi@x.in', 'secret', 'ADMIN');
          await r.refreshAll();
          final AppController c = AppController(
            store: store,
            repo: r,
            startScreen: 'home',
          );
          c.afterRefresh(quietOk: true);
          return c;
        }

        final AppController c = await start();
        // P&L: a picked From / To.
        await c.openFinancial('pl');
        c.openFinRange();
        c.setF('drFrom', '2026-04-15');
        c.setF('drTo', '2026-08-31');
        c.applyRange();
        await pumpEventQueue();
        expect(_last(f, 'profit-loss')['from'], '2026-04-15');
        // Another statement keeps its own default …
        await c.openFinancial('cf');
        final DateTime t = c.today;
        expect(_last(f, 'cash-flow')['to'], ymd(t));
        // … Cash Flow: one month picked.
        await c.pickCashMonth(DateTime(2026, 8));
        // Back to the P&L: still the picked dates (not "This FY").
        c.back();
        await c.openFinancial('pl');
        expect(c.finPreset, 'range');
        expect(_last(f, 'profit-loss')['from'], '2026-04-15');
        expect(_last(f, 'profit-loss')['to'], '2026-08-31');
        // A refresh asks for the same dates.
        await c.loadFinancial();
        expect(_last(f, 'profit-loss')['from'], '2026-04-15');
        // Sales analytics: 12 months.
        await c.setSalesPreset('last12');
        // The forecast: 8 weeks.
        c.openCfRange();
        c.rangePreset('w8');
        c.applyRange();
        expect(c.cfWeeks, 8);
        c.dispose();

        // The app opened again: every report as it was left.
        final AppController d = await start();
        expect(d.salesPreset, 'last12');
        expect(d.cfWeeks, 8);
        await d.openFinancial('pl');
        expect(_last(f, 'profit-loss')['from'], '2026-04-15');
        expect(_last(f, 'profit-loss')['to'], '2026-08-31');
        await d.openFinancial('cf');
        expect(_last(f, 'cash-flow')['from'], '2026-08-01');
        expect(_last(f, 'cash-flow')['to'], '2026-08-31');
        // A preset chip changes it — and that is kept instead.
        await d.openFinancial('pl');
        await d.setFinPreset('fy');
        final DateTime fy = DateTime(t.month >= 4 ? t.year : t.year - 1, 4);
        expect(_last(f, 'profit-loss')['from'], ymd(fy));
        d.dispose();
        final AppController e = await start();
        await e.openFinancial('pl');
        expect(e.finPreset, 'fy');
        expect(_last(f, 'profit-loss')['from'], ymd(fy));
        e.dispose();
      },
    );

    test('forecast From / To: this week, 4–26 weeks', () async {
      final FakeBackend f = FakeBackend();
      final AppController c = await _start(f);
      c.openCfRange();
      expect(c.overlay, 'dateRange');
      expect(c.rangePresets, AppController.kForecastPresets);
      expect(c.f('drFrom'), ymd(c.cfStart));
      c.rangePreset('w8');
      expect(c.f('drTo'), ymd(c.cfStart.add(const Duration(days: 55))));
      expect(c.rangeError, isNull);
      c.applyRange();
      await pumpEventQueue();
      expect(c.cfWeeks, 8);
      expect(f.cashflowQueries.last['weeks'], '8');
      // Starts this week; at most 26 weeks.
      c.openCfRange();
      c.setF('drFrom', ymd(c.cfStart.add(const Duration(days: 7))));
      expect(c.rangeError, contains('starts with this week'));
      c.setF('drFrom', ymd(c.cfStart));
      c.setF('drTo', ymd(c.cfStart.add(const Duration(days: 7 * 27))));
      expect(c.rangeError, contains('at most 26 weeks'));
      c.dispose();
    });
  });

  group('screens', () {
    setUpAll(loadFigtree);

    for (final double w in <double>[320, 412]) {
      testWidgets(
        'Reports tiles → P&L, Balance Sheet, Trial Balance, Expenses at ${w.toInt()} px',
        (WidgetTester t) async {
          t.view.physicalSize = Size(w * 3, 800 * 3);
          t.view.devicePixelRatio = 3;
          addTearDown(t.view.reset);
          final FakeBackend f = FakeBackend();
          final AppController c = await _start(f);
          await t.pumpWidget(
            ProviderScope(
              overrides: <Override>[appProvider.overrideWith((Ref ref) => c)],
              child: const TallyConnectApp(),
            ),
          );
          Future<void> settle() async {
            for (int i = 0; i < 8; i++) {
              await t.pump(const Duration(milliseconds: 100));
            }
          }

          Future<void> tapKey(String k) async {
            final Finder x = find.byKey(ValueKey<String>(k));
            // Rows far above are not built while scrolled down: back to top.
            if (x.evaluate().isEmpty) {
              c.reg.screenScroll?.jumpTo(0);
              await settle();
            }
            // Rows below the fold are built as the page scrolls.
            if (x.evaluate().isEmpty) {
              await t.scrollUntilVisible(
                x,
                200,
                scrollable: find.byType(Scrollable).first,
              );
            }
            await t.ensureVisible(x);
            await t.pump();
            await t.tap(x);
            await settle();
          }

          c.go('reports');
          await settle();
          await settle();
          expect(find.byKey(const ValueKey<String>('fin-pl')), findsOneWidget);
          expect(t.takeException(), isNull);
          await tapKey('fin-pl');
          expect(c.screen, 'finReport');
          expect(find.text('₹57,000'), findsWidgets);
          expect(find.text('Trading account'), findsOneWidget);
          // Groups open to show their ledgers.
          expect(find.text('Salary'), findsNothing);
          await tapKey('finNode-ie/Indirect Expenses');
          expect(find.text('Salary'), findsOneWidget);
          expect(t.takeException(), isNull);
          // Period chip.
          await tapKey('finPreset-lastMonth');
          expect(_last(f, 'profit-loss')['to'], '2026-09-30');
          // Share: the PDF document holds every group / ledger and totals
          // (the PDF viewer itself cannot render inside widget tests).
          c.reg.screenScroll?.jumpTo(0);
          await settle();
          expect(
            find.byKey(const ValueKey<String>('finShare')),
            findsOneWidget,
          );
          final ShareDoc doc = finDoc(c, c.finData!);
          expect(doc.title, 'Profit & Loss');
          expect(doc.subtitle, 'September 2026');
          expect(
            doc.table!.rows.any((List<String> r) => r[0].trim() == 'Salary'),
            isTrue,
          );
          expect(doc.totals.last, ('Net profit', '₹57,000'));

          await c.openFinancial('bs');
          await settle();
          expect(find.text('Liabilities'), findsOneWidget);
          expect(find.text('Profit & Loss A/c'), findsOneWidget);
          expect(find.text('Opening Balance'), findsOneWidget);
          expect(find.text('Current Period'), findsOneWidget);
          // Both sides total alike, Tally's way (no ₹ sign, two decimals).
          expect(find.text('2,17,000.00'), findsNWidgets(2));
          expect(t.takeException(), isNull);

          await c.openFinancial('tb');
          await settle();
          expect(find.text('PARTICULARS'), findsOneWidget);
          expect(find.text('DEBIT'), findsOneWidget);
          expect(find.text('CREDIT'), findsOneWidget);
          expect(find.text('Grand Total'), findsOneWidget);
          expect(find.text('3,62,000.00'), findsNWidgets(2));
          // A group opens to its ledgers, each in its column.
          expect(find.text('Capital A/c'), findsNothing);
          await tapKey('finNode-tb/Capital Account');
          expect(find.text('Capital A/c'), findsOneWidget);
          expect(find.text('1,15,000.00'), findsNWidgets(2));
          expect(t.takeException(), isNull);

          await c.openFinancial('exp');
          await settle();
          expect(find.text('Month-wise'), findsOneWidget);
          await tapKey('finPurchases');
          expect(_last(f, 'expenses')['purchases'], '1');
          expect(t.takeException(), isNull);

          // Pick month sheet.
          await c.openFinancial('bs');
          await settle();
          await tapKey('finPreset-pick');
          expect(c.overlay, 'finPick');
          await tapKey('finMonth-2026-8');
          expect(_last(f, 'balance-sheet')['as_on'], '2026-08-31');
          expect(t.takeException(), isNull);
          await t.pump(const Duration(seconds: 6));
        },
      );
    }

    for (final bool admin in <bool>[true, false]) {
      testWidgets(
        'missing year-end closing stock: ${admin ? 'admin enters it' : 'team member is told to ask'} (320 px)',
        (WidgetTester t) async {
          t.view.physicalSize = const Size(320 * 3, 800 * 3);
          t.view.devicePixelRatio = 3;
          addTearDown(t.view.reset);
          final FakeBackend f = FakeBackend()
            ..finStockNeeded.add('2026-03-31')
            ..finCanEnterStock = admin;
          final AppController c = await _start(f);
          await t.pumpWidget(
            ProviderScope(
              overrides: <Override>[appProvider.overrideWith((Ref ref) => c)],
              child: const TallyConnectApp(),
            ),
          );
          Future<void> settle() async {
            for (int i = 0; i < 8; i++) {
              await t.pump(const Duration(milliseconds: 100));
            }
          }

          await c.openFinancial('pl');
          await settle();
          const ValueKey<String> btn = ValueKey<String>('finStock-2026-3-31');
          expect(find.textContaining('Closing stock as on'), findsOneWidget);
          if (!admin) {
            expect(find.byKey(btn), findsNothing);
            expect(find.textContaining('Ask your admin'), findsOneWidget);
            expect(t.takeException(), isNull);
            await t.pump(const Duration(seconds: 6));
            return;
          }
          await t.ensureVisible(find.byKey(btn));
          await t.pump();
          await t.tap(find.byKey(btn));
          await settle();
          expect(c.overlay, 'finStock');
          expect(t.takeException(), isNull);
          await t.enterText(
            find.descendant(
              of: find.byKey(const ValueKey<String>('finStockValue')),
              matching: find.byType(TextField),
            ),
            '125000',
          );
          await t.pump();
          await t.tap(find.byKey(const ValueKey<String>('finStockSave')));
          await settle();
          expect(f.finStockSaved.single['value'], 125000);
          expect(c.overlay, isNull);
          expect(find.byKey(btn), findsNothing);
          expect(t.takeException(), isNull);
          await t.pump(const Duration(seconds: 6));
        },
      );
    }

    testWidgets(
      'dashboard sections; Cash Flow; From / To; ledger vouchers at 320 px',
      (WidgetTester t) async {
        t.view.physicalSize = const Size(320 * 3, 800 * 3);
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        final FakeBackend f = FakeBackend()..finAnyPeriod = true;
        final AppController c = await _start(f);
        await t.pumpWidget(
          ProviderScope(
            overrides: <Override>[appProvider.overrideWith((Ref ref) => c)],
            child: const TallyConnectApp(),
          ),
        );
        Future<void> settle() async {
          for (int i = 0; i < 8; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
        }

        Future<void> tapKey(String k) async {
          final Finder x = find.byKey(ValueKey<String>(k));
          if (x.evaluate().isEmpty) {
            c.reg.screenScroll?.jumpTo(0);
            await settle();
          }
          await t.ensureVisible(x);
          await t.pump();
          await t.tap(x);
          await settle();
        }

        c.go('reports');
        await settle();
        await settle();
        // Financial statements, then Business analytics.
        for (final String k in <String>[
          'fin-bs',
          'fin-pl',
          'fin-tb',
          'fin-cf',
          'cashflowTile',
          'fin-exp',
        ]) {
          expect(find.byKey(ValueKey<String>(k)), findsOneWidget, reason: k);
        }
        expect(
          find.textContaining(
            RegExp('Financial statements', caseSensitive: false),
          ),
          findsOneWidget,
        );
        // Square cards: each at least as tall as it is wide.
        final Size bs = t.getSize(find.byKey(const ValueKey<String>('fin-bs')));
        expect(bs.height, greaterThanOrEqualTo(bs.width - 0.5));
        final Finder analytics = find.textContaining(
          RegExp('Business analytics', caseSensitive: false),
        );
        await t.scrollUntilVisible(
          analytics,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(analytics, findsOneWidget);
        expect(t.takeException(), isNull);

        await tapKey('fin-cf');
        expect(c.finKind, 'cf');
        expect(
          find.byKey(const ValueKey<String>('periodFrom')),
          findsOneWidget,
        );
        expect(find.text('₹67,000'), findsWidgets);
        expect(find.text('Month-wise'), findsOneWidget);
        await t.scrollUntilVisible(
          find.text('Cash and bank accounts'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Cash and bank accounts'), findsOneWidget);
        // Nothing left out of Cash Flow: no note.
        expect(find.byKey(const ValueKey<String>('cfNotInFlow')), findsNothing);
        expect(t.takeException(), isNull);
        // Cash moved by vouchers Tally's Cash Flow leaves out: the note.
        f.finCashNotInFlow = -3000;
        await c.loadFinancial();
        await settle();
        await t.scrollUntilVisible(
          find.byKey(const ValueKey<String>('cfNotInFlow')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.textContaining('of cash / bank movement is not in Cash Flow'),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
        await tapKey('cfMonth-2026-8');
        expect(_last(f, 'cash-flow')['from'], '2026-08-01');
        expect(t.takeException(), isNull);

        // The From / To sheet from the header.
        await tapKey('periodFrom');
        expect(c.overlay, 'dateRange');
        await settle();
        expect(
          find.byKey(const ValueKey<String>('rangePreset-fy')),
          findsOneWidget,
        );
        c.closeOv();
        await settle();

        // P&L → a group → a ledger → its vouchers.
        await c.openFinancial('pl');
        await settle();
        await tapKey('finNode-ie/Indirect Expenses');
        await tapKey('finNode-ie/Indirect Expenses/Salary');
        expect(c.screen, 'finLedger');
        await settle();
        expect(find.text('Opening Balance'), findsOneWidget);
        expect(find.text('Closing Balance'), findsOneWidget);
        expect(find.text('HDFC Bank'), findsOneWidget);
        expect(find.text('18,000.00'), findsWidgets);
        expect(t.takeException(), isNull);
        // A voucher row opens the voucher (its detail call is not part of
        // this fake server, so only the navigation is checked here).
        await t.ensureVisible(
          find.byKey(const ValueKey<String>('finLedRow-v-1')),
        );
        await t.pump();
        await t.tap(find.byKey(const ValueKey<String>('finLedRow-v-1')));
        expect(c.screen, 'entryDetail');
        await t.pump(const Duration(seconds: 6));
      },
    );

    testWidgets('team member without access: no tiles', (WidgetTester t) async {
      t.view.physicalSize = const Size(390 * 3, 800 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final FakeBackend f = FakeBackend()..finAllowed = false;
      final AppController c = await _start(f);
      await t.pumpWidget(
        ProviderScope(
          overrides: <Override>[appProvider.overrideWith((Ref ref) => c)],
          child: const TallyConnectApp(),
        ),
      );
      c.go('reports');
      for (int i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(c.finCanView, isFalse);
      expect(find.byKey(const ValueKey<String>('fin-pl')), findsNothing);
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 6));
    });
  });
}
