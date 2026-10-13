// Layout at phone widths: no overflow on the main screens; balanced header
// (back pill never shrunk, compact action icons); period choices + Date
// range on ONE row; Home's assistant button clear of the tab bar; the
// assistant's mic + send beside the question field.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/storage/assistant_key_store.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/data/repositories/api_tally_repository.dart'
    show DataSet;
import 'package:tallyconnect_ui/data/repositories/demo_repository.dart';
import 'package:tallyconnect_ui/main.dart';
import 'package:tallyconnect_ui/presentation/widgets/tab_bar.dart';

import 'api_integration_test.dart' show FakeBackend;
import 'screens_test.dart' show loadFigtree;

void main() {
  setUpAll(loadFigtree);

  for (final double w in <double>[320, 360, 390, 412]) {
    testWidgets('main screens at ${w.toInt()} px', (WidgetTester t) async {
      t.view.physicalSize = Size(w * 3, 780 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final FakeBackend f = FakeBackend();
      final DemoAwareRepository r = DemoAwareRepository(live: f.repo());
      await r.login('ravi@x.in', 'secret', 'ADMIN');
      await r.refreshAll();
      await r.ensure(DataSet.ledgers);
      final AppController c = AppController(
        store: LocalStorage.memory(),
        repo: r,
        startScreen: 'home',
        assistantKeys: MemoryAssistantKeyStore()
          ..keys['ravi@x.in'] = 'AIzaGOODKEY_1234567890abcdef',
      );
      c.afterRefresh(quietOk: true);
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

      Future<void> visit(String s, [Map<String, Object?>? extra]) async {
        c.go(s, extra);
        await settle();
        expect(t.takeException(), isNull, reason: '$s at $w');
      }

      // Home: the assistant button sits above the tab bar.
      await settle();
      expect(t.takeException(), isNull);
      final Rect fab = t.getRect(
        find.byKey(const ValueKey<String>('assistantFab')),
      );
      final Rect bar = t.getRect(find.byType(TcTabBar));
      expect(fab.bottom, lessThanOrEqualTo(bar.top + 1));
      expect(fab.right, lessThanOrEqualTo(w));

      // Outstanding list: balanced header — compact actions, a full-height
      // back button (never scaled down), all on one line.
      await visit('outList', <String, Object?>{'outKind': 'recv'});
      final Rect back = t.getRect(
        find.byKey(const ValueKey<String>('backBtn')),
      );
      expect(back.height, 44);
      expect(back.width, greaterThanOrEqualTo(44));
      for (final String k in <String>['outRangeBtn', 'outSearchBtn']) {
        final Finder b = find.byKey(ValueKey<String>(k));
        if (b.evaluate().isNotEmpty) expect(t.getSize(b).height, 40, reason: k);
      }
      // Period options and Date range on one row.
      Rect at(String k) => t.getRect(find.byKey(ValueKey<String>(k)));
      final double y = at('period-out-all').center.dy;
      for (final String k in <String>[
        'period-out-month',
        'period-out-week',
        'period-out-today',
        'range-out',
      ]) {
        expect(at(k).center.dy, moreOrLessEquals(y, epsilon: .5), reason: k);
      }
      // A quick period filters by its date range; All time clears it.
      await t.tap(find.byKey(const ValueKey<String>('period-out-all')));
      c.pickPeriod('out', 'week');
      await settle();
      expect(c.outRange, isTrue);
      expect(c.periodSel('out'), 'week');
      expect(t.takeException(), isNull);
      c.pickPeriod('out', 'all');
      await settle();
      expect(c.outRange, isFalse);

      await visit('outHub');
      await visit('outList', <String, Object?>{'outKind': 'pay'});
      await visit('vHub');
      await visit('vList', <String, Object?>{'vFilter': 'all'});
      final double vy = at('period-v-all').center.dy;
      expect(at('range-v').center.dy, moreOrLessEquals(vy, epsilon: .5));
      await visit('reports');
      await visit('report', <String, Object?>{'report': 'sreg'});
      final double ry = at('period-rep-all').center.dy;
      expect(at('range-rep').center.dy, moreOrLessEquals(ry, epsilon: .5));
      c.pickPeriod('rep', 'today');
      await settle();
      expect(c.repPeriod, 'range');
      expect(c.periodSel('rep'), 'today');
      expect(t.takeException(), isNull);
      c.pickPeriod('rep', 'month');
      await settle();
      expect(c.repPeriod, 'month');
      await visit('party');
      await visit('partyDetail', <String, Object?>{
        'party': 'Mehta Electricals',
        'partyTab': 'summary',
      });
      await visit('items');
      await visit('notifs');
      await visit('activity');
      await visit('settings');
      await visit('companies');
      await visit('help');

      // Assistant: mic inside the field, send beside it, on one row.
      await visit('home');
      await c.openAssistant();
      await settle();
      final Rect mic = t.getRect(find.byKey(const ValueKey<String>('aiMic')));
      final Rect send = t.getRect(find.byKey(const ValueKey<String>('aiSend')));
      expect(mic.center.dy, moreOrLessEquals(send.center.dy, epsilon: 2));
      expect(mic.right, lessThan(send.left));
      expect(send.right, lessThanOrEqualTo(w));
      expect(t.takeException(), isNull);
      c.closeOv();
      await t.pump(const Duration(seconds: 6));
    });
  }
}
