// AI assistant on the server's AI key: the usage the server reports, the
// tokens-left meter, the "free AI access ended" popup and banner at 320 px.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/data/models/models.dart';
import 'package:tallyconnect_ui/data/repositories/demo_repository.dart';
import 'package:tallyconnect_ui/main.dart';

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
  group('usage from the server', () {
    test('status and answers carry the usage; older servers none', () {
      final AiStatus s = AiStatus.fromJson(<String, Object?>{
        'success': true,
        'enabled': true,
        'usage': <String, Object?>{
          'plan': <String, Object?>{'code': 'free', 'name': 'Free'},
          'limit': 10000,
          'used': 10240,
        },
      });
      expect(s.enabled, isTrue);
      expect(s.usage!.remaining, 0); // never negative
      expect(s.usage!.exhausted, isTrue);
      expect(s.usage!.fraction, 1.0);
      expect(AiStatus.fromJson(<String, Object?>{'enabled': false}).enabled, isFalse);
      expect(AiStatus.fromJson(null).usage, isNull);
      final AssistantReply r = AssistantReply.fromJson(<String, Object?>{
        'answer': 'x',
        'usage': <String, Object?>{
          'plan': <String, Object?>{'code': 'pro', 'name': 'Pro'},
          'limit': 500000,
          'used': 1200,
        },
      });
      expect(r.usage!.planName, 'Pro');
      expect(r.usage!.remaining, 498800);
      expect(AssistantReply.fromJson(<String, Object?>{'answer': 'x'}).usage, isNull);
      expect(AiUsage.spent.exhausted, isTrue);
    });
  });

  group('screens (320 px)', () {
    setUpAll(loadFigtree);

    Future<AppController> open(WidgetTester t, FakeBackend f) async {
      t.view.physicalSize = const Size(320 * 3, 640 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final AppController c = await _start(f);
      await t.pumpWidget(
        ProviderScope(
          overrides: <Override>[appProvider.overrideWith((Ref ref) => c)],
          child: const TallyConnectApp(),
        ),
      );
      await c.openAssistant();
      for (int i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      return c;
    }

    testWidgets('meter: tokens left, then nearly used up', (WidgetTester t) async {
      final FakeBackend f = FakeBackend()..aiUsed = 8500;
      final AppController c = await open(t, f);
      expect(find.byKey(const ValueKey<String>('aiUsage')), findsOneWidget);
      expect(find.text('Free plan · 1,500 of 10,000 AI tokens left'), findsOneWidget);
      // No key field, provider chips or model picker any more.
      expect(find.byKey(const ValueKey<String>('aiKeyField')), findsNothing);
      expect(find.byKey(const ValueKey<String>('aiConnect')), findsNothing);
      expect(find.byKey(const ValueKey<String>('aiModelChip')), findsNothing);
      expect(t.takeException(), isNull);
      c.closeOv();
      await t.pump(const Duration(seconds: 6));
    });

    testWidgets('used up on opening: popup first, banner after Not now', (
      WidgetTester t,
    ) async {
      final FakeBackend f = FakeBackend()..aiUsed = 10000;
      final AppController c = await open(t, f);
      expect(c.overlay, 'aiLimit');
      expect(find.byKey(const ValueKey<String>('aiLimitSheet')), findsOneWidget);
      expect(find.text('Free AI access ended'), findsOneWidget);
      expect(
        find.text('Your free AI access has ended. Upgrade your plan to continue.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey<String>('aiViewPlans')), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const ValueKey<String>('aiLimitClose')));
      for (int i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(c.overlay, 'assistant');
      expect(find.text('Free plan · AI tokens used up'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('aiLimitBanner')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('aiSend')), findsNothing);
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const ValueKey<String>('aiBannerPlans')));
      for (int i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(c.screen, 'billing');
      expect(f.aiAsks, isEmpty); // nothing was ever sent
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 6));
    });

    testWidgets('assistant off at the server: a plain message', (
      WidgetTester t,
    ) async {
      final FakeBackend f = FakeBackend()..aiDisabled = true;
      final AppController c = await open(t, f);
      expect(find.byKey(const ValueKey<String>('aiOff')), findsOneWidget);
      expect(find.text('The AI Assistant is not available right now.'), findsOneWidget);
      expect(t.takeException(), isNull);
      c.closeOv();
      await t.pump(const Duration(seconds: 6));
    });
  });
}
