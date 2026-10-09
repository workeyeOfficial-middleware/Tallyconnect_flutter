// Hide / restore bottom-bar tabs and the whole bar, appearance defaults,
// readable text on light and dark backgrounds, and the voucher-type row.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/design/tc_palette.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/main.dart';

import 'screens_test.dart' show loadFigtree;

double _ratio(Color a, Color b) {
  final double x = a.computeLuminance(), y = b.computeLuminance();
  final double hi = x > y ? x : y, lo = x > y ? y : x;
  return (hi + .05) / (lo + .05);
}

void main() {
  group('appearance defaults', () {
    test('fresh install: background 100 %, glass 20 %; both saved', () {
      final LocalStorage s = LocalStorage.memory();
      final AppController c = AppController(store: s);
      expect(c.bgOpacity, 100);
      expect(c.glass, 20);
      expect(c.wallK, 'theme'); // Match theme
      expect(c.bgShade, 100);
      c.setBgShade(-20);
      c.setGlass(50);
      c.dispose();
      final AppController c2 = AppController(store: s);
      expect(c2.glass, 50); // user's choice kept
      expect(c2.bgShade, -20);
      c2.resetLook();
      expect(c2.glass, 20);
      c2.dispose();
    });
  });

  group('readable text', () {
    test('light background: dark page text; dark background: light', () {
      final TcPalette light = resolvePalette(preset: 'aurora');
      expect(light.pageDark, isFalse);
      expect(light.pageInk, light.ink);
      // Darkest shade over the wallpaper.
      final TcPalette dark = resolvePalette(preset: 'aurora', shade: 1);
      final double bg = backdropLum(
        wall: dark.wall,
        photo: false,
        photoLum: 1,
        shade: 1,
      );
      final Color bgc = Color.from(
        alpha: 1,
        red: bg,
        green: bg,
        blue: bg,
      ); // grey of the same luminance (linear ≈ for the check)
      expect(bgc.computeLuminance(), lessThan(.5));
      for (final Color t in <Color>[
        light.pageInk,
        light.pageInk2,
        light.pageInk3,
      ]) {
        final double l = backdropLum(
          wall: light.wall,
          photo: false,
          photoLum: 1,
        );
        expect(
          (l + .05) / (t.computeLuminance() + .05),
          greaterThanOrEqualTo(4.5),
        );
      }
      // Dark photo wallpaper: page text turns light, cards get opaque
      // enough for their dark text.
      final TcPalette ph = resolvePalette(
        preset: 'aurora',
        wallK: 'photo',
        photoPath: 'x.jpg',
        photoLum: .05,
        glass: 0,
      );
      expect(ph.pageDark, isTrue);
      expect(_ratio(ph.pageInk3, const Color(0xFF3A3A3A)), greaterThan(3));
      expect(ph.glassFill.a, greaterThan(.5));
    });
  });

  group('hide / restore tabs and bar', () {
    test('hide a tab, open it from links, restore; Home never hides', () {
      final LocalStorage s = LocalStorage.memory();
      final AppController c = AppController(store: s, startScreen: 'home');
      expect(c.barCount, 5);
      final int act = c.barOrder.firstWhere(
        (int i) => c.tabHidden(i) == false && i == 3,
      );
      c.hideTab(act); // Activity
      expect(c.barCount, 4);
      expect(c.tabHidden(act), isTrue);
      c.hideTab(0); // Home: ignored
      expect(c.tabHidden(0), isFalse);
      // Still reachable as a normal screen.
      c.go('activity');
      expect(c.screen, 'activity');
      expect(c.history, isNotEmpty);
      c.dispose();
      // Saved.
      final AppController c2 = AppController(store: s, startScreen: 'home');
      expect(c2.barCount, 4);
      c2.restoreTab('activity');
      expect(c2.barCount, 5);
      // Whole bar.
      c2.setNavBarHidden(true);
      expect(c2.showTabs, isFalse);
      c2.dispose();
      final AppController c3 = AppController(store: s, startScreen: 'home');
      expect(c3.navBarHidden, isTrue);
      c3.setNavBarHidden(false);
      expect(c3.showTabs, isTrue);
      c3.dispose();
    });
  });

  group('items by stock group; item customers open their party', () {
    setUpAll(loadFigtree);
    testWidgets('group list → group items; tab menu pop-up', (
      WidgetTester t,
    ) async {
      t.view.physicalSize = const Size(360 * 3, 800 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final AppController c = AppController(
        store: LocalStorage.memory(),
        startScreen: 'home',
      );
      await t.pumpWidget(
        ProviderScope(
          overrides: <Override>[appProvider.overrideWith((Ref ref) => c)],
          child: const TallyConnectApp(),
        ),
      );
      c.go('items');
      c.update(() => c.itemsView = 'groups');
      for (int i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final String g = c.repo.items().first.group ?? 'Not in a group';
      expect(find.text(g), findsWidgets);
      expect(t.takeException(), isNull);
      c.openItemGroup(g);
      for (int i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text(c.repo.items().first.name), findsOneWidget);
      // Tab long-press menu (glass pop-up): hide the tab.
      c.update(() {
        c.tabMenu = 3;
        c.overlay = 'tabMenu';
      });
      for (int i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Hide from bar'), findsOneWidget);
      expect(find.text('Hide whole bar'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('hideTabBtn')));
      await t.pump(const Duration(milliseconds: 300));
      expect(c.tabHidden(3), isTrue);
      expect(c.overlay, isNull);
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 6));
    });
  });

  group('screens at several widths', () {
    setUpAll(loadFigtree);
    for (final double w in <double>[320, 360, 412]) {
      testWidgets('Settings → Layout and voucher list at ${w.toInt()}', (
        WidgetTester t,
      ) async {
        t.view.physicalSize = Size(w * 3, 800 * 3);
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        final AppController c = AppController(
          store: LocalStorage.memory(),
          startScreen: 'home',
        );
        c.hideTab(3);
        await t.pumpWidget(
          ProviderScope(
            overrides: <Override>[appProvider.overrideWith((Ref ref) => c)],
            child: const TallyConnectApp(),
          ),
        );
        c.go('settings');
        c.update(() => c.setTab = 'layout');
        for (int i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('Hidden tabs'.toUpperCase()), findsOneWidget);
        expect(find.text('Activity'), findsWidgets);
        expect(t.takeException(), isNull);
        c.go('vList', <String, Object?>{'vFilter': 'purchase'});
        for (int i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(t.takeException(), isNull);
        await t.pump(const Duration(seconds: 6));
      });
    }
  });
}
