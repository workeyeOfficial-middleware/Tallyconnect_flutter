// Settings → Background → Text colour: every text shade lighter / darker,
// never past readable (4.5:1 on its surface), saved, live preview.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/app/providers.dart';
import 'package:tallyconnect_ui/core/design/tc_palette.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/main.dart';

import 'screens_test.dart' show loadFigtree;

double _ratio(Color c, double bgLum) {
  final double l = c.computeLuminance();
  return (math.max(l, bgLum) + .05) / (math.min(l, bgLum) + .05);
}

List<Color> _inks(TcPalette p) => <Color>[
  p.ink,
  p.ink2,
  p.ink3,
  p.pageInk,
  p.pageInk2,
  p.pageInk3,
  p.tabInk,
  p.filterInk,
];

void main() {
  group('palette', () {
    test('Auto (0) leaves every colour exactly as before', () {
      for (final double shade in <double>[-1, 0, 1]) {
        final TcPalette a = resolvePalette(preset: 'aurora', shade: shade);
        final TcPalette b = resolvePalette(
          preset: 'aurora',
          shade: shade,
          textTone: 0,
        );
        expect(_inks(b), _inks(a));
        expect(b, a);
      }
    });

    test('darker / lighter move text, never below 4.5:1', () {
      for (final String look in kLookDefs.keys) {
        for (final double shade in <double>[-1, 0, 1]) {
          final TcPalette auto = resolvePalette(preset: look, shade: shade);
          final double bg = backdropLum(
            wall: auto.wall,
            photo: false,
            photoLum: 1,
            shade: shade,
          );
          final double card =
              bg + (auto.gt.computeLuminance() - bg) * auto.glassA;
          for (final double tone in <double>[-1, -.5, .5, 1]) {
            final TcPalette p = resolvePalette(
              preset: look,
              shade: shade,
              textTone: tone,
            );
            final String at = '$look shade $shade tone $tone';
            final List<(Color, Color, double)> pairs = <(Color, Color, double)>[
              (p.ink, auto.ink, card),
              (p.ink2, auto.ink2, card),
              (p.ink3, auto.ink3, card),
              (p.filterInk, auto.filterInk, card),
              (p.pageInk, auto.pageInk, bg),
              (p.pageInk2, auto.pageInk2, bg),
              (p.pageInk3, auto.pageInk3, bg),
              (p.tabInk, auto.tabInk, bg),
            ];
            for (final (Color now, Color was, double surf) in pairs) {
              // Readable, or left exactly as the automatic colour.
              if (now != was) {
                expect(_ratio(now, surf), greaterThanOrEqualTo(4.5), reason: at);
              }
              // Direction: darker never lighter, lighter never darker.
              if (tone > 0) {
                expect(
                  now.computeLuminance(),
                  lessThanOrEqualTo(was.computeLuminance() + 1e-9),
                  reason: at,
                );
              } else {
                expect(
                  now.computeLuminance(),
                  greaterThanOrEqualTo(was.computeLuminance() - 1e-9),
                  reason: at,
                );
              }
            }
          }
        }
      }
    });

    test('a visible change both ways on the default look', () {
      final TcPalette auto = resolvePalette(preset: 'aurora');
      final TcPalette dark = resolvePalette(preset: 'aurora', textTone: 1);
      final TcPalette light = resolvePalette(preset: 'aurora', textTone: -1);
      expect(dark.ink2.computeLuminance(), lessThan(auto.ink2.computeLuminance()));
      expect(
        light.ink2.computeLuminance(),
        greaterThan(auto.ink2.computeLuminance()),
      );
    });
  });

  group('setting', () {
    test('saved, applied to the palette, reset with the background', () {
      final LocalStorage s = LocalStorage.memory();
      final AppController c = AppController(store: s);
      expect(c.textTone, 0);
      final Color auto = c.palette.ink2;
      c.setTextTone(70);
      expect(c.palette.ink2, isNot(auto));
      c.setTextTone(400); // clamped
      expect(c.textTone, 100);
      c.setTextTone(-40);
      c.dispose();
      final AppController c2 = AppController(store: s);
      expect(c2.textTone, -40);
      c2.resetLook();
      expect(c2.textTone, 0);
      c2.dispose();
    });
  });

  group('screen', () {
    setUpAll(loadFigtree);

    testWidgets('Background tab: slider and live preview follow the value', (
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

      c.go('settings', <String, Object?>{'setTab': 'look'});
      c.update(() => c.lookTab = 'background');
      await settle();
      await t.scrollUntilVisible(find.text('Card text'), 200);
      await settle();
      expect(find.text('Text colour'), findsOneWidget);
      expect(find.text('Auto'), findsOneWidget);
      for (final double v in <double>[-100, 50, 100]) {
        c.setTextTone(v);
        await settle();
        final Text card = t.widget<Text>(find.text('Card text'));
        expect(card.style!.color, c.palette.ink);
        final Text page = t.widget<Text>(find.text('Page title'));
        expect(page.style!.color, c.palette.pageInk);
        expect(t.takeException(), isNull);
      }
      // Background shade (default +100) and Text colour both read +100.
      expect(find.text('+100'), findsNWidgets(2));
      // Every screen still renders with the strongest settings.
      for (final double v in <double>[-100, 100]) {
        c.setTextTone(v);
        for (final String s in <String>[
          'home',
          'vouchers',
          'outstanding',
          'reports',
          'items',
        ]) {
          c.jump(s);
          await settle();
          expect(t.takeException(), isNull, reason: '$s $v');
        }
        c.openOverlay('menu');
        await settle();
        expect(t.takeException(), isNull);
        c.closeOv();
        await settle();
      }
      await t.pump(const Duration(seconds: 6));
    });
  });
}
