// Theme-matched TC app icon. The icon background never changes; only the
// "T" and "c" letter colours follow the app background (wallpaper colours
// or the dominant colour of the user's photo), always with strong contrast.
//
// Android launcher icons are fixed resources, so the launcher icon switches
// between pre-made colour variants (activity-aliases in AndroidManifest.xml,
// generated with the same colour rule as [lettersFor]). The exact colour is
// available as an optional home-screen shortcut drawn here at runtime.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

/// One launcher icon variant ([alias] = `<activity-alias>` name).
class IconVariant {
  const IconVariant(this.key, this.alias, this.hue, this.label);
  final String key, alias, label;

  /// Hue in degrees; null for the neutral (graphite) variant.
  final double? hue;
}

/// Variants shipped in the APK (see android/app/src/main/res/mipmap-*).
/// `brand` is the original icon.
const List<IconVariant> kIconVariants = <IconVariant>[
  IconVariant('brand', 'IconBrand', 334, 'Original'),
  IconVariant('red', 'IconRed', 4, 'Red'),
  IconVariant('orange', 'IconOrange', 24, 'Orange'),
  IconVariant('amber', 'IconAmber', 40, 'Amber'),
  IconVariant('olive', 'IconOlive', 70, 'Olive'),
  IconVariant('green', 'IconGreen', 130, 'Green'),
  IconVariant('teal', 'IconTeal', 172, 'Teal'),
  IconVariant('cyan', 'IconCyan', 192, 'Cyan'),
  IconVariant('blue', 'IconBlue', 214, 'Blue'),
  IconVariant('indigo', 'IconIndigo', 238, 'Indigo'),
  IconVariant('purple', 'IconPurple', 272, 'Purple'),
  IconVariant('pink', 'IconPink', 305, 'Pink'),
  IconVariant('graphite', 'IconGraphite', null, 'Graphite'),
];

List<String> get kIconAliases => <String>[
  for (final IconVariant v in kIconVariants) v.alias,
];

/// The icon's own background (darker end — worst case for contrast).
const Color kIconBg = Color(0xFFEAEEF8);
const Color kIconBgTop = Color(0xFFFFFFFF);

/// Original letter colours.
const Color kBrandT = Color(0xFF1C1C1C);
const Color kBrandC = Color(0xFFD12350);

double _contrast(Color a, Color b) {
  final double x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + .05) / (math.min(x, y) + .05);
}

/// Below this saturation a colour counts as neutral (graphite icon).
const double kNeutralSat = .18;

/// Launcher variant closest to [base] (by hue; neutral → graphite).
IconVariant variantFor(Color base) {
  final HSVColor h = HSVColor.fromColor(base);
  if (h.saturation < kNeutralSat || h.value < .12) {
    return kIconVariants.last;
  }
  IconVariant best = kIconVariants.first;
  double bd = 999;
  for (final IconVariant v in kIconVariants) {
    if (v.hue == null) continue;
    final double d = (h.hue - v.hue!).abs();
    final double dd = math.min(d, 360 - d);
    if (dd < bd) {
      bd = dd;
      best = v;
    }
  }
  return best;
}

/// Letter colours for [base]: "c" in its hue, darkened until it reaches
/// 4.5:1 on the icon background; "T" a very dark shade of the same hue —
/// the original dark-T / coloured-c branding in the new colour.
(Color, Color) lettersFor(Color base, {double? fixedSat}) {
  final HSVColor h = HSVColor.fromColor(base);
  if (h.saturation < kNeutralSat || h.value < .12) {
    return (const Color(0xFF292929), const Color(0xFF6B6B6B));
  }
  final double s = fixedSat ?? h.saturation.clamp(.55, .9).toDouble();
  double v = .85;
  Color c = HSVColor.fromAHSV(1, h.hue, s, v).toColor();
  while (_contrast(c, kIconBg) < 4.5 && v > .2) {
    v -= .01;
    c = HSVColor.fromAHSV(1, h.hue, s, v).toColor();
  }
  return (HSVColor.fromAHSV(1, h.hue, .45, .16).toColor(), c);
}

/// Dominant colour of an image file: the most common saturated hue (pixels
/// weighted by saturation and brightness), averaged; the plain average when
/// the image is mostly grey.
Future<Color> dominantColor(Uint8List bytes) async {
  final ui.Codec codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: 48,
    targetHeight: 48,
  );
  final ui.Image img = (await codec.getNextFrame()).image;
  final ByteData? data = await img.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  img.dispose();
  if (data == null) return kBrandC;
  final List<double> w = List<double>.filled(24, 0);
  final List<List<double>> sum = List<List<double>>.generate(
    24,
    (_) => <double>[0, 0, 0],
  );
  double ar = 0, ag = 0, ab = 0, n = 0;
  for (int i = 0; i + 3 < data.lengthInBytes; i += 4) {
    final int r = data.getUint8(i), g = data.getUint8(i + 1);
    final int b = data.getUint8(i + 2), a = data.getUint8(i + 3);
    if (a < 128) continue;
    ar += r;
    ag += g;
    ab += b;
    n++;
    final HSVColor h = HSVColor.fromColor(Color.fromARGB(255, r, g, b));
    if (h.saturation < .2 || h.value < .15) continue;
    final int k = (h.hue / 15).floor() % 24;
    final double wt = h.saturation * h.value;
    w[k] += wt;
    sum[k][0] += r * wt;
    sum[k][1] += g * wt;
    sum[k][2] += b * wt;
  }
  if (n == 0) return kBrandC;
  int best = 0;
  for (int k = 1; k < 24; k++) {
    if (w[k] > w[best]) best = k;
  }
  // Mostly grey photo: no clear colour → its average (likely neutral).
  final double totalW = w.fold<double>(0, (double s, double x) => s + x);
  if (totalW < n * .06) {
    return Color.fromARGB(
      255,
      (ar / n).round(),
      (ag / n).round(),
      (ab / n).round(),
    );
  }
  return Color.fromARGB(
    255,
    (sum[best][0] / w[best]).round(),
    (sum[best][1] / w[best]).round(),
    (sum[best][2] / w[best]).round(),
  );
}

ui.Image? _tMask, _cMask;

Future<ui.Image> _load(String a) async {
  final ByteData d = await rootBundle.load(a);
  final ui.Codec c = await ui.instantiateImageCodec(d.buffer.asUint8List());
  return (await c.getNextFrame()).image;
}

/// The TC icon (432 px adaptive canvas: same background, letters in [t] /
/// [c]) as PNG bytes — for the exact-colour shortcut and the preview.
Future<Uint8List> renderIconPng(Color t, Color c, {int size = 432}) async {
  _tMask ??= await _load('assets/images/tc_icon_t.png');
  _cMask ??= await _load('assets/images/tc_icon_c.png');
  final double s = size.toDouble();
  final ui.PictureRecorder rec = ui.PictureRecorder();
  final Canvas cv = Canvas(rec);
  final Rect r = Rect.fromLTWH(0, 0, s, s);
  cv.drawRect(
    r,
    Paint()
      ..shader = ui.Gradient.linear(Offset.zero, Offset(0, s), <Color>[
        kIconBgTop,
        kIconBg,
      ]),
  );
  final Rect src = Rect.fromLTWH(
    0,
    0,
    _tMask!.width.toDouble(),
    _tMask!.height.toDouble(),
  );
  // Soft shadow under the letters (as in the launcher icon).
  for (final ui.Image m in <ui.Image>[_tMask!, _cMask!]) {
    cv.drawImageRect(
      m,
      src,
      r.shift(Offset(0, s * .012)),
      Paint()
        ..colorFilter = const ColorFilter.mode(
          Color(0x38281E3C),
          BlendMode.srcIn,
        )
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * .012),
    );
  }
  // Letters: mask RGB = shading / 1.6 → colour × shading.
  ColorFilter tint(Color k) => ColorFilter.matrix(<double>[
    k.r * 1.6, 0, 0, 0, 0, //
    0, k.g * 1.6, 0, 0, 0, //
    0, 0, k.b * 1.6, 0, 0, //
    0, 0, 0, 1, 0,
  ]);
  cv.drawImageRect(_tMask!, src, r, Paint()..colorFilter = tint(t));
  cv.drawImageRect(_cMask!, src, r, Paint()..colorFilter = tint(c));
  final ui.Image out = await rec.endRecording().toImage(size, size);
  final ByteData? png = await out.toByteData(format: ui.ImageByteFormat.png);
  out.dispose();
  return png!.buffer.asUint8List();
}

/// Launcher icon / shortcut operations.
abstract class AppIconService {
  /// Launcher alias enabled now (null: unknown / not supported).
  Future<String?> current();

  /// Switches the launcher icon to [alias]; false when not possible.
  Future<bool> set(String alias);
  Future<bool> pinSupported();

  /// Pins (or updates) the exact-colour shortcut: `requested`, `updated`,
  /// `none` (updateOnly, not pinned) or `unsupported`.
  Future<String> pin(Uint8List png, {bool updateOnly = false});
}

/// No launcher control (tests, iOS, desktop).
class NoAppIcon implements AppIconService {
  NoAppIcon();
  String? applied;
  int pins = 0;
  @override
  Future<String?> current() async => applied;
  @override
  Future<bool> set(String alias) async {
    applied = alias;
    return true;
  }

  @override
  Future<bool> pinSupported() async => false;
  @override
  Future<String> pin(Uint8List png, {bool updateOnly = false}) async {
    pins++;
    return 'unsupported';
  }
}

/// Android: `tallyconnect/app_icon` channel in MainActivity.kt.
class DeviceAppIcon implements AppIconService {
  DeviceAppIcon();
  static const MethodChannel _ch = MethodChannel('tallyconnect/app_icon');

  @override
  Future<String?> current() async {
    try {
      return await _ch.invokeMethod<String>('current', <String, Object>{
        'all': kIconAliases,
      });
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> set(String alias) async {
    try {
      return await _ch.invokeMethod<bool>('set', <String, Object>{
            'alias': alias,
            'all': kIconAliases,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> pinSupported() async {
    try {
      return await _ch.invokeMethod<bool>('pinSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String> pin(Uint8List png, {bool updateOnly = false}) async {
    try {
      return await _ch.invokeMethod<String>('pin', <String, Object>{
            'png': png,
            'label': 'TallyConnect',
            'updateOnly': updateOnly,
          }) ??
          'unsupported';
    } catch (_) {
      return 'unsupported';
    }
  }
}
