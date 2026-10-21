// Liquid glass "see-through" setting: a higher value is clearer glass (less
// tint, softer sheen) on every surface — cards, lists, sheets, footers, the
// sidebar and the bottom bar — and card text stays readable at every level.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/design/tc_fields.dart';
import 'package:tallyconnect_ui/core/design/tc_kit.dart';
import 'package:tallyconnect_ui/core/design/tc_palette.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/main.dart';
import 'package:tallyconnect_ui/presentation/shell.dart';
import 'package:tallyconnect_ui/presentation/widgets/tab_bar.dart';

import 'screens_test.dart' show loadFigtree;

double _ratio(double a, double b) =>
    (math.max(a, b) + .05) / (math.min(a, b) + .05);

const List<double> kLevels = <double>[20, 40, 60, 80, 100];

void main() {
  group('palette', () {
    test('higher setting → clearer glass on every look / background', () {
      for (final String look in kLookDefs.keys) {
        for (final String wall in <String>['theme', ...kWalls.keys]) {
          for (final double shade in <double>[-1, 0, 1]) {
            TcPalette? prev;
            for (final double lv in kLevels) {
              final TcPalette p = resolvePalette(
                preset: look,
                wallK: wall,
                glass: lv,
                shade: shade,
              );
              final String at = '$look/$wall/shade $shade/$lv %';
              if (prev != null) {
                expect(p.glassA, lessThanOrEqualTo(prev.glassA), reason: at);
                expect(
                  p.sheetFill.a,
                  lessThanOrEqualTo(prev.sheetFill.a),
                  reason: at,
                );
                expect(
                  p.barFill.a,
                  lessThanOrEqualTo(prev.barFill.a),
                  reason: at,
                );
                expect(p.sheen, lessThan(prev.sheen), reason: at);
                // Fields and raised controls follow the setting too.
                expect(
                  p.fieldFill.a,
                  lessThanOrEqualTo(prev.fieldFill.a),
                  reason: at,
                );
                expect(
                  p.raisedFill.a,
                  lessThanOrEqualTo(prev.raisedFill.a),
                  reason: at,
                );
              }
              // Card ink readable on the glass over this background.
              final double bg = backdropLum(
                wall: p.wall,
                photo: false,
                photoLum: 1,
                shade: shade,
              );
              final double gl = p.gt.computeLuminance();
              final double card = bg + (gl - bg) * p.glassA;
              expect(
                _ratio(card, p.ink.computeLuminance()),
                greaterThanOrEqualTo(4.5),
                reason: at,
              );
              // Typed text stays readable on a field over this background.
              final double field = bg + (gl - bg) * p.fieldFill.a;
              expect(
                _ratio(field, p.ink.computeLuminance()),
                greaterThanOrEqualTo(4.5),
                reason: 'field $at',
              );
              prev = p;
            }
          }
        }
      }
    });

    test('light background: 20 % → 74 % tint, 100 % → 8 %', () {
      final TcPalette lo = resolvePalette(preset: 'aurora', glass: 20);
      final TcPalette hi = resolvePalette(preset: 'aurora', glass: 100);
      expect(lo.glassA, closeTo(.74, 1e-9));
      expect(hi.glassA, closeTo(.08, 1e-9));
      expect(hi.sheen, .5);
    });

    test('dark background: still clearer at 100 % than at 20 %', () {
      final TcPalette lo = resolvePalette(
        preset: 'aurora',
        glass: 20,
        shade: 1,
      );
      final TcPalette hi = resolvePalette(
        preset: 'aurora',
        glass: 100,
        shade: 1,
      );
      expect(hi.glassA, lessThan(lo.glassA - .2));
    });
  });

  group('fields and frosted cards', () {
    setUpAll(loadFigtree);

    testWidgets(
      'a text field follows the setting; Frosted cards blur every card',
      (WidgetTester t) async {
        t.view.physicalSize = const Size(390 * 3, 844 * 3);
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        final LocalStorage store = LocalStorage.memory();
        final AppController c = AppController(
          store: store,
          startScreen: 'login',
        );
        await t.pumpWidget(
          ProviderScope(
            overrides: <Override>[appProvider.overrideWith((Ref ref) => c)],
            child: const TallyConnectApp(),
          ),
        );
        Future<void> settle() async {
          for (int i = 0; i < 6; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
        }

        await settle();
        double fieldAlpha() {
          final AnimatedContainer box = t.widget<AnimatedContainer>(
            find
                .descendant(
                  of: find.byType(Inp).first,
                  matching: find.byType(AnimatedContainer),
                )
                .first,
          );
          return (box.decoration! as BoxDecoration).color!.a;
        }

        c.setGlass(20);
        await settle();
        final double dense = fieldAlpha();
        c.setGlass(100);
        await settle();
        expect(fieldAlpha(), lessThan(dense - .2)); // clearer, not fixed white
        expect(fieldAlpha(), closeTo(c.palette.fieldFill.a, 1e-9));

        // Frosted cards: off by default; on → cards blur; kept on the phone.
        c.jump('home');
        await settle();
        final int before = t.widgetList(find.byType(BackdropFilter)).length;
        expect(c.cardBlur, isFalse);
        c.toggleCardBlur();
        await settle();
        expect(
          t.widgetList(find.byType(BackdropFilter)).length,
          greaterThan(before + 3),
        );
        expect(AppController(store: store).cardBlur, isTrue);
        c.resetLook();
        expect(c.cardBlur, isFalse);
        await t.pump(const Duration(seconds: 6));
      },
    );
  });

  group('saved setting', () {
    test('old scale is turned round once; new value kept', () {
      for (final (num old, double now) in <(num, double)>[
        (20, 100),
        (60, 60),
        (100, 20),
      ]) {
        final LocalStorage s = LocalStorage.memory()
          ..save(LocalStorage.kGlass, old);
        final AppController c = AppController(store: s);
        expect(c.glass, now);
        c.dispose();
        // Read again: not turned round a second time.
        final AppController c2 = AppController(store: s);
        expect(c2.glass, now);
        c2.dispose();
      }
      final LocalStorage s = LocalStorage.memory();
      final AppController c = AppController(store: s)..setGlass(40);
      c.dispose();
      expect(AppController(store: s).glass, 40);
    });
  });

  group('every surface follows the setting', () {
    setUpAll(loadFigtree);

    testWidgets('screens, sidebar and bar at 20 / 60 / 100 %', (
      WidgetTester t,
    ) async {
      t.view.physicalSize = const Size(390 * 3, 844 * 3);
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
      Future<void> settle() async {
        for (int i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
      }

      double? sidebarA, barTop;
      for (final double lv in <double>[20, 60, 100]) {
        c.setGlass(lv);
        for (final String s in kScreens) {
          c.jump(s);
          await settle();
          expect(t.takeException(), isNull, reason: '$s @ $lv %');
        }
        c.jump('home');
        await settle();
        // Bottom bar tint.
        final Glass bar = t.widget<Glass>(
          find
              .descendant(
                of: find.byType(TcTabBar),
                matching: find.byType(Glass),
              )
              .first,
        );
        final double top = (bar.gradient! as LinearGradient).colors.first.a;
        if (barTop != null) expect(top, lessThan(barTop));
        barTop = top;
        // Sidebar.
        c.openOverlay('menu');
        await settle();
        final Iterable<Glass> withFill = t
            .widgetList<Glass>(find.byType(Glass))
            .where((Glass g) => g.fill == c.palette.glassFill);
        expect(withFill, isNotEmpty, reason: 'sidebar @ $lv %');
        final double a = c.palette.glassA;
        if (sidebarA != null) expect(a, lessThan(sidebarA));
        sidebarA = a;
        c.closeOv();
        await settle();
        expect(t.takeException(), isNull);
      }
      await t.pump(const Duration(seconds: 6));
    });
  });
}
