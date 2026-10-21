// Reports UI: Trial Balance columns with crore amounts never overlap, clip
// or shrink (phones 320–412 px, larger text: amounts under the name); the
// From–To on every statement; the Reports screen's category tabs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/design/tc_kit.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/data/repositories/api_tally_repository.dart'
    show DataSet;
import 'package:tallyconnect_ui/data/repositories/demo_repository.dart';
import 'package:tallyconnect_ui/main.dart';

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

/// The Trial Balance amounts on screen (Indian grouping, two decimals).
final RegExp _amt = RegExp(r'^\(?[−]?\)? ?[\d,]+\.\d\d$');

void main() {
  setUpAll(loadFigtree);

  Future<AppController> open(
    WidgetTester t,
    FakeBackend f,
    double w, {
    double text = 1,
  }) async {
    t.view.physicalSize = Size(w * 3, 800 * 3);
    t.view.devicePixelRatio = 3;
    t.platformDispatcher.textScaleFactorTestValue = text;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
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

  /// Every amount: full size (not scaled down), inside the card, and no
  /// two amounts overlap.
  void checkAmounts(WidgetTester t, {required int atLeast}) {
    final List<Element> els = find
        .byWidgetPredicate(
          (Widget w) => w is Text && _amt.hasMatch(w.data ?? ''),
        )
        .evaluate()
        .toList();
    expect(els.length, greaterThanOrEqualTo(atLeast));
    final Rect card = t.getRect(
      find
          .ancestor(of: find.text('PARTICULARS'), matching: find.byType(Glass))
          .first,
    );
    // One size for every amount of the table (rows, groups and totals).
    final Set<double?> sizes = <double?>{
      for (final Element e in els) (e.widget as Text).style?.fontSize,
    };
    expect(sizes, hasLength(1), reason: 'amount font sizes: $sizes');
    final List<Rect> rects = <Rect>[];
    for (final Element e in els) {
      final RenderBox b = e.renderObject! as RenderBox;
      final Rect r = b.localToGlobal(Offset.zero) & b.size;
      // Painted size = laid-out size: the amount was not shrunk to fit.
      final Offset far = b.localToGlobal(b.size.bottomRight(Offset.zero));
      expect(
        far.dx - r.left,
        closeTo(b.size.width, .5),
        reason: '${(e.widget as Text).data}',
      );
      expect(r.left, greaterThanOrEqualTo(card.left - .5));
      expect(r.right, lessThanOrEqualTo(card.right + .5));
      rects.add(r);
    }
    for (int i = 0; i < rects.length; i++) {
      for (int j = i + 1; j < rects.length; j++) {
        final Rect o = rects[i].intersect(rects[j]);
        final bool overlap = o.width > .5 && o.height > .5;
        expect(
          overlap,
          isFalse,
          reason:
              '${(els[i].widget as Text).data} / ${(els[j].widget as Text).data}',
        );
        // Same row: at least the column gap between them.
        if ((rects[i].center.dy - rects[j].center.dy).abs() < 4) {
          final double gap = rects[i].left < rects[j].left
              ? rects[j].left - rects[i].right
              : rects[i].left - rects[j].right;
          expect(gap, greaterThanOrEqualTo(8));
        }
      }
    }
  }

  for (final (double, double) s in <(double, double)>[
    (320, 1),
    (360, 1),
    (412, 1),
    (360, 1.3),
  ]) {
    testWidgets('Trial Balance crore amounts: no overlap / clip / shrink at '
        '${s.$1.toInt()} px, text ×${s.$2}', (WidgetTester t) async {
      final FakeBackend f = FakeBackend()..finBigTb = true;
      final AppController c = await open(t, f, s.$1, text: s.$2);
      await c.openFinancial('tb');
      await settle(t);
      // Grand Total: Dr 32,26,09,823.02 = Cr 30,42,50,373.76 + the
      // difference in opening balances (1,83,59,449.26).
      expect(find.text('32,26,09,823.02'), findsNWidgets(2));
      expect(find.text('1,83,59,449.26'), findsOneWidget);
      await t.ensureVisible(find.text('Current Assets'));
      await t.tap(find.text('Current Assets'));
      await settle(t);
      expect(find.text('31,64,71,156.96'), findsWidgets);
      expect(find.text('19,18,648.58'), findsWidgets);
      checkAmounts(t, atLeast: 6);
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 6));
    });
  }

  testWidgets('From–To on every statement; checked against synced dates', (
    WidgetTester t,
  ) async {
    final FakeBackend f = FakeBackend(); // no any_period: month ends only
    final AppController c = await open(t, f, 360);
    for (final String k in <String>['bs', 'pl', 'tb', 'exp']) {
      await c.openFinancial(k);
      await settle(t);
      expect(
        find.byKey(const ValueKey<String>('periodFrom')),
        findsOneWidget,
        reason: k,
      );
    }
    // P&L: a synced month (Sep) is fine and loads it.
    await c.openFinancial('pl');
    c.openFinRange();
    c.setF('drFrom', '2026-09-01');
    c.setF('drTo', '2026-09-30');
    expect(c.rangeError, isNull);
    c.applyRange();
    await settle(t);
    expect(_last(f, 'profit-loss')['from'], '2026-09-01');
    expect(_last(f, 'profit-loss')['to'], '2026-09-30');
    // A To date the server has no figures for: said in the sheet.
    c.openFinRange();
    c.setF('drFrom', '2026-09-01');
    c.setF('drTo', '2026-09-15');
    expect(c.rangeError, contains('not synced'));
    expect(c.rangeError, contains('Synced: 03 Oct 2026'));
    c.closeOv();
    // Balance Sheet: as at a synced month end.
    await c.openFinancial('bs');
    c.openFinRange();
    c.setF('drTo', '2026-08-31');
    expect(c.rangeError, isNull);
    c.applyRange();
    await settle(t);
    expect(_last(f, 'balance-sheet')['as_on'], '2026-08-31');
    await t.pump(const Duration(seconds: 6));
  });

  test('a server that takes any period: any From–To', () async {
    final FakeBackend g = FakeBackend()..finAnyPeriod = true;
    final AppController d = await _start(g);
    for (final (String, String) k in <(String, String)>[
      ('pl', 'profit-loss'),
      ('tb', 'trial-balance'),
      ('bs', 'balance-sheet'),
      ('cf', 'cash-flow'),
      ('exp', 'expenses'),
    ]) {
      await d.openFinancial(k.$1);
      d.openFinRange();
      d.setF('drFrom', '2024-04-07');
      d.setF('drTo', '2026-09-15');
      expect(d.rangeError, isNull, reason: k.$1);
      d.applyRange();
      await pumpEventQueue();
      expect(_last(g, k.$2)['from'], '2024-04-07', reason: k.$1);
      expect(_last(g, k.$2)['to'], '2026-09-15', reason: k.$1);
    }
    d.dispose();
  });

  for (final double w in <double>[320, 412]) {
    testWidgets('Reports: category tabs under the summary at ${w.toInt()} px', (
      WidgetTester t,
    ) async {
      final FakeBackend f = FakeBackend();
      final AppController c = await open(t, f, w);
      await c.checkFinancialAccess(force: true);
      c.go('reports');
      await settle(t);
      await settle(t);
      expect(c.repTabs.map(((String, String) x) => x.$1), <String>[
        'fin',
        'analytics',
        'sales',
        'party',
        'stock',
        'accounts',
      ]);
      // Tabs right below the summary card.
      final double tabsY = t
          .getTopLeft(find.byKey(const ValueKey<String>('repTab-fin')))
          .dy;
      expect(tabsY, greaterThan(t.getTopLeft(find.text('This month')).dy));
      // Financial Statements first: its six cards at once.
      expect(c.repTab, 'fin');
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
      expect(find.byKey(const ValueKey<String>('salesTile')), findsNothing);
      expect(find.text('Top customers'), findsNothing);
      expect(t.takeException(), isNull);

      Future<void> tab(String k) async {
        final Finder x = find.byKey(ValueKey<String>('repTab-$k'));
        await t.scrollUntilVisible(
          x,
          120,
          scrollable: find.byType(Scrollable).last,
        );
        await t.tap(x);
        await settle(t);
        expect(c.repTab, k);
      }

      await tab('analytics');
      expect(find.byKey(const ValueKey<String>('salesTile')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('fin-bs')), findsNothing);
      await tab('sales');
      expect(find.text('Top customers'), findsOneWidget);
      expect(find.text('Sales list'), findsOneWidget);
      expect(find.text('Stock summary'), findsNothing);
      await tab('stock');
      expect(find.text('Stock summary'), findsOneWidget);
      expect(find.text('Items not moving'), findsOneWidget);
      await tab('accounts');
      expect(find.text('Day Book'), findsOneWidget);
      // The old Expenses card opens the dated Expenses statement.
      expect(find.text('Any period'), findsOneWidget);
      await t.tap(find.text('Expenses'));
      await settle(t);
      expect(c.screen, 'finReport');
      expect(c.finKind, 'exp');
      expect(t.takeException(), isNull);
      // The tab is kept when coming back.
      c.back();
      await settle(t);
      expect(c.repTab, 'accounts');
      await t.pump(const Duration(seconds: 6));
    });
  }
}
