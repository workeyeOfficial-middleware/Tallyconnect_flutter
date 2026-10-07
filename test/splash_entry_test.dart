// Launch splash (shown once, hands over to the app) and the New Entry
// cards (Journal / Contra).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/main.dart';
import 'package:tallyconnect_ui/presentation/splash.dart';

void size(WidgetTester t, double w, double h) {
  t.view.physicalSize = Size(w * 3, h * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

void main() {
  group('launch splash', () {
    Finder asset(String name) => find.byWidgetPredicate(
      (Widget w) =>
          w is Image &&
          w.image is AssetImage &&
          (w.image as AssetImage).assetName == name,
    );

    for (final (double, double) s in <(double, double)>[
      (320, 568), // small phone
      (390, 844), // phone
      (1024, 1366), // tablet
    ]) {
      testWidgets('Earth at once, logo in, app after ~1 s (${s.$1}x${s.$2})', (
        WidgetTester t,
      ) async {
        size(t, s.$1, s.$2);
        await t.pumpWidget(
          SplashBoot(
            appOverlay: kAppOverlay,
            boot: () async =>
                const MaterialApp(home: Scaffold(body: Text('APP HOME'))),
          ),
        );
        // First frame: the Earth is already there (no fade from black).
        expect(asset(kSplashImage), findsOneWidget);
        final Opacity earthFade = t.widget<Opacity>(
          find
              .ancestor(of: asset(kSplashImage), matching: find.byType(Opacity))
              .first,
        );
        expect(earthFade.opacity, 1, reason: 'only the exit fades the splash');
        // Shown whole (fits the shorter side): never stretched or cropped.
        final Size sz = t.getSize(asset(kSplashImage));
        expect(sz.width, sz.height);
        expect(sz.width, lessThanOrEqualTo(s.$1));
        // The transparent logo comes in over it; no text / spinner / UI
        // of its own and no layout overflow.
        for (int i = 0; i < 9; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(asset(kSplashLogo), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (Widget w) => w is Text && w.data != 'APP HOME',
          ),
          findsNothing,
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);
        // ~1 s intro + 0.35 s cross-fade (after the 250 ms asset fallback
        // used here; the app pre-decodes the art and starts at frame one).
        for (int i = 0; i < 11; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('APP HOME'), findsOneWidget);
        expect(find.byType(SplashBoot), findsOneWidget);
        expect(find.byType(Image), findsNothing);
      });
    }

    testWidgets('waits for a slow start-up (no extra fixed delay)', (
      WidgetTester t,
    ) async {
      size(t, 390, 844);
      await t.pumpWidget(
        SplashBoot(
          appOverlay: kAppOverlay,
          boot: () => Future<Widget>.delayed(
            const Duration(seconds: 3),
            () => const MaterialApp(home: Scaffold(body: Text('APP HOME'))),
          ),
        ),
      );
      for (int i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      // Intro done, app not ready: the splash (Earth + logo) stays.
      expect(find.text('APP HOME'), findsNothing);
      expect(asset(kSplashImage), findsOneWidget);
      expect(asset(kSplashLogo), findsOneWidget);
      for (int i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      // Ready at 3 s; gone ~0.35 s later.
      expect(find.text('APP HOME'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byType(Image), findsNothing);
    });
  });

  group('new entry cards', () {
    Future<AppController> open(WidgetTester t) async {
      size(t, 390, 844);
      final AppController c = AppController(
        store: LocalStorage.memory(),
        startScreen: 'newEntry',
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

    testWidgets('six cards: Journal replaces Adjustment, Contra added', (
      WidgetTester t,
    ) async {
      await open(t);
      for (final String s in <String>[
        'Sale',
        'Purchase',
        'Receipt',
        'Payment',
        'Journal',
        'Contra',
      ]) {
        expect(find.text(s), findsOneWidget, reason: s);
      }
      expect(find.text('Adjustment'), findsNothing);
      await t.pump(const Duration(seconds: 6));
    });

    testWidgets('Journal opens the journal flow', (WidgetTester t) async {
      final AppController c = await open(t);
      await t.tap(find.text('Journal'));
      await t.pump(const Duration(milliseconds: 600));
      expect(c.screen, 'flow');
      expect(c.flowType, 'journal');
      await t.pump(const Duration(seconds: 6));
    });

    testWidgets('Contra is not posted as another voucher type', (
      WidgetTester t,
    ) async {
      final AppController c = await open(t);
      await t.tap(find.text('Contra'));
      await t.pump(const Duration(milliseconds: 300));
      expect(c.screen, 'newEntry');
      expect(c.toast, contains('Contra'));
      await t.pump(const Duration(seconds: 6));
    });
  });
}
