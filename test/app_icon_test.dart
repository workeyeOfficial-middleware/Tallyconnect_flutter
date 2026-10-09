// Theme-matched TC app icon: variant choice, letter contrast, dominant
// colour of a photo, applying the launcher icon, and the rendered shortcut.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/core/app_icon/app_icon.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';

double ratio(Color a, Color b) {
  final double x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
}

Future<Uint8List> solidPng(Color c) async {
  final ui.PictureRecorder r = ui.PictureRecorder();
  ui.Canvas(
    r,
  ).drawRect(const ui.Rect.fromLTWH(0, 0, 64, 64), ui.Paint()..color = c);
  final ui.Image img = await r.endRecording().toImage(64, 64);
  final ByteData? b = await img.toByteData(format: ui.ImageByteFormat.png);
  return b!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('variant by hue; neutral → graphite; brand for crimson', () {
    expect(variantFor(const Color(0xFF2A6BBF)).key, 'blue');
    expect(variantFor(const Color(0xFF1B7D2C)).key, 'green');
    expect(variantFor(const Color(0xFF8C1D3F)).key, 'brand');
    expect(variantFor(const Color(0xFF808080)).key, 'graphite');
    expect(variantFor(const Color(0xFF050505)).key, 'graphite');
  });

  test('letters keep strong contrast on the icon background', () {
    for (final Color base in <Color>[
      const Color(0xFFFFE600), // bright yellow
      const Color(0xFF00FFFF), // cyan
      const Color(0xFFFF00FF),
      const Color(0xFF8C1D3F),
      const Color(0xFFB0B0B0),
    ]) {
      final (Color t, Color c) = lettersFor(base);
      expect(ratio(c, kIconBg), greaterThanOrEqualTo(4.5), reason: '$base');
      expect(ratio(t, kIconBg), greaterThanOrEqualTo(10), reason: '$base');
    }
  });

  test('dominant colour of a photo', () async {
    final Color d = await dominantColor(
      await solidPng(const Color(0xFF1E8C3A)),
    );
    expect(variantFor(d).key, 'green');
    final Color g = await dominantColor(
      await solidPng(const Color(0xFF777777)),
    );
    expect(variantFor(g).key, 'graphite');
  });

  test('icon applied on pause only when changed; off → original', () async {
    final LocalStorage s = LocalStorage.memory();
    final NoAppIcon dev = NoAppIcon();
    final AppController c = AppController(store: s, appIcon: dev);
    await c.applyAppIcon();
    final String first = dev.applied ?? 'IconBrand';
    expect(kIconAliases, contains(first));
    dev.applied = null;
    await c.applyAppIcon(); // same background: no switch
    expect(dev.applied, isNull);
    c.setIconMatch(false);
    await c.applyAppIcon();
    expect(dev.applied ?? 'IconBrand', 'IconBrand');
    c.dispose();
  });

  testWidgets('shortcut icon renders (letters on the same background)', (
    WidgetTester t,
  ) async {
    final Uint8List? png = await t.runAsync(
      () => renderIconPng(const Color(0xFF1C1C1C), const Color(0xFF1B7D2C)),
    );
    expect(png, isNotNull);
    expect(png!.length, greaterThan(1000));
    expect(png.sublist(1, 4), <int>[0x50, 0x4E, 0x47]); // "PNG"
  });
}
