// The financial statements' graph: the same figures the statement lists
// (Balance Sheet assets / liabilities, Trial Balance debit / credit, P&L
// summary / income / expenses), every chart type, the choice kept on the
// phone, and the statement itself unchanged; the screens at phone widths.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/share/report_data.dart' show ChartPoint;
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/data/repositories/demo_repository.dart';
import 'package:tallyconnect_ui/main.dart';
import 'package:tallyconnect_ui/presentation/screens/fin_charts.dart';

import 'api_integration_test.dart' show FakeBackend;
import 'screens_test.dart' show loadFigtree;

Future<AppController> _start(FakeBackend f, {LocalStorage? store}) async {
  final DemoAwareRepository r = DemoAwareRepository(live: f.repo());
  await r.login('ravi@x.in', 'secret', 'ADMIN');
  await r.refreshAll();
  final AppController c = AppController(
    store: store ?? LocalStorage.memory(),
    repo: r,
    startScreen: 'home',
  );
  c.afterRefresh(quietOk: true);
  return c;
}

num _sum(FinChartSet s) =>
    s.points.fold<num>(0, (num a, ChartPoint p) => a + p.value);
FinChartSet _set(List<FinChartSet> l, String k) =>
    l.firstWhere((FinChartSet s) => s.key == k);

void main() {
  group('figures', () {
    test('Balance Sheet: assets = liabilities = the statement total', () async {
      final FakeBackend f = FakeBackend()..finAnyPeriod = true;
      final AppController c = await _start(f);
      await c.openStatement('bs');
      final List<FinChartSet> sets = finChartSets(c.finData!, 'bs');
      expect(sets.map((FinChartSet s) => s.key), <String>[
        'assets',
        'liabilities',
        'compare',
      ]);
      expect(_sum(_set(sets, 'assets')), 217000);
      expect(_sum(_set(sets, 'liabilities')), 217000);
      expect(
        _set(sets, 'liabilities').points.map((ChartPoint p) => p.label),
        contains('Profit & Loss A/c'),
      );
      expect(_set(sets, 'compare').adds, isFalse);
      c.dispose();
    });

    test(
      'Trial Balance: debit / credit = the Grand Total columns (crores)',
      () async {
        final FakeBackend f = FakeBackend()
          ..finAnyPeriod = true
          ..finBigTb = true;
        final AppController c = await _start(f);
        await c.openStatement('tb');
        final List<FinChartSet> sets = finChartSets(c.finData!, 'tb');
        expect(
          _sum(_set(sets, 'debit')),
          closeTo(c.finData!.n('total_debit'), .01),
        );
        expect(
          _sum(_set(sets, 'credit')),
          closeTo(c.finData!.n('total_credit'), .01),
        );
        expect(
          _set(sets, 'debit').points.every((ChartPoint p) => p.value > 0),
          isTrue,
        );
        c.dispose();
      },
    );

    test('Profit & Loss: the summary is the figures on top', () async {
      final FakeBackend f = FakeBackend()..finAnyPeriod = true;
      final AppController c = await _start(f);
      await c.openStatement('pl');
      final FinChartSet s = _set(finChartSets(c.finData!, 'pl'), 'summary');
      expect(
        s.points.map((ChartPoint p) => (p.label, p.value)),
        <(String, num)>[
          ('Revenue', c.finData!.n('total_revenue')),
          ('Expenses', c.finData!.n('total_expenses')),
          ('Gross profit', c.finData!.n('gross_profit')),
          ('Net profit', c.finData!.n('net_profit')),
        ],
      );
      expect(s.adds, isFalse); // no made-up total
      c.dispose();
    });

    test(
      'chart type and each statement\x27s series are kept on the phone',
      () async {
        final FakeBackend f = FakeBackend()..finAnyPeriod = true;
        final LocalStorage store = LocalStorage.memory();
        final AppController c = await _start(f, store: store);
        expect(c.finChartType, 'bar');
        expect(c.finChartOpen, isFalse); // closed until opened
        c.toggleFinChart();
        c.setFinChartType('scatter');
        c.setFinChartSet('bs', 'liabilities');
        c.setFinChartSet('tb', 'credit');
        c.dispose();
        final AppController d = await _start(f, store: store);
        expect(d.finChartType, 'scatter');
        expect(d.finChartOpen, isTrue);
        expect(d.finChartSets, <String, String>{
          'bs': 'liabilities',
          'tb': 'credit',
        });
        d.dispose();
      },
    );
  });

  group('screens', () {
    setUpAll(loadFigtree);

    for (final double w in <double>[320, 412]) {
      testWidgets(
        'every chart type and series on the three statements at ${w.toInt()} px',
        (WidgetTester t) async {
          t.view.physicalSize = Size(w * 3, 760 * 3);
          t.view.devicePixelRatio = 3;
          addTearDown(t.view.reset);
          final FakeBackend f = FakeBackend()
            ..finAnyPeriod = true
            ..finBigTb = true;
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

          Future<void> tap(String k) async {
            final Finder x = find.byKey(ValueKey<String>(k));
            await t.ensureVisible(x);
            await t.pump();
            await t.tap(x);
            await settle();
          }

          for (final String kind in <String>['bs', 'tb', 'pl']) {
            await c.openStatement(kind);
            await settle();
            expect(
              find.byKey(const ValueKey<String>('finChart')),
              findsOneWidget,
              reason: kind,
            );
            // Closed at first: opened once, it stays open on the others.
            if (!c.finChartOpen) await tap('finChartToggle');
            expect(c.finChartOpen, isTrue);
            for (final FinChartSet s in finChartSets(c.finData!, kind)) {
              await tap('finChartSet-${s.key}');
              expect(c.finChartSets[kind], s.key);
              for (final String ty in <String>[
                'bar',
                'column',
                'line',
                'scatter',
                'pie',
              ]) {
                c.setFinChartType(ty);
                await settle();
                expect(t.takeException(), isNull, reason: '$kind/${s.key}/$ty');
              }
            }
          }
          // The statement itself is unchanged by the graph.
          await c.openStatement('bs');
          await settle();
          expect(find.text('2,17,000.00'), findsWidgets);
          await t.pump(const Duration(seconds: 6));
        },
      );
    }
  });
}
