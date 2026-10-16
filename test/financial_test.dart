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
          expect(t.takeException(), isNull);

          await c.openFinancial('tb');
          await settle();
          expect(find.textContaining(' Dr'), findsWidgets);
          expect(find.textContaining(' Cr'), findsWidgets);
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
