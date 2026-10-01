// Colour maths and the custom-colour theme generator, ported from
// Main.dc.html lines 1880–1912 (hsl2rgb … makeTheme, COMBOS, okAccent).
library;

import 'dart:math' as math;
import 'dart:ui';

import 'tc_wall_spec.dart';

double clampN(double x, double a, double b) => math.max(a, math.min(b, x));

List<double> hsl2rgb(double h, double s, double l) {
  h = ((h % 360) + 360) % 360;
  s /= 100;
  l /= 100;
  final double c = (1 - (2 * l - 1).abs()) * s;
  final double x = c * (1 - ((h / 60) % 2 - 1).abs());
  final double m = l - c / 2;
  double r = 0, g = 0, b = 0;
  if (h < 60) {
    r = c;
    g = x;
  } else if (h < 120) {
    r = x;
    g = c;
  } else if (h < 180) {
    g = c;
    b = x;
  } else if (h < 240) {
    g = x;
    b = c;
  } else if (h < 300) {
    r = x;
    b = c;
  } else {
    r = c;
    b = x;
  }
  return <double>[(r + m) * 255, (g + m) * 255, (b + m) * 255];
}

String rgb2hex(List<double> a) =>
    '#${a.map((double v) => clampN(v, 0, 255).round().toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';

String hslx(double h, double s, double l) => rgb2hex(hsl2rgb(h, s, l));

List<int> hex2rgb(String? hex) {
  String h = (hex ?? '').replaceAll('#', '');
  if (h.length == 3) h = h.split('').map((String c) => '$c$c').join();
  final int n = int.tryParse(h, radix: 16) ?? 0;
  return <int>[(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

Color hexColor(String hex, [double alpha = 1]) {
  final List<int> c = hex2rgb(hex);
  return Color.fromRGBO(c[0], c[1], c[2], alpha);
}

String colorHex(Color c) => rgb2hex(<double>[c.r * 255, c.g * 255, c.b * 255]);

List<double> rgb2hsl(List<int> a) {
  final double r = a[0] / 255, g = a[1] / 255, b = a[2] / 255;
  final double mx = math.max(r, math.max(g, b)),
      mn = math.min(r, math.min(g, b));
  final double l = (mx + mn) / 2;
  double h = 0, s = 0;
  final double d = mx - mn;
  if (d != 0) {
    s = l > .5 ? d / (2 - mx - mn) : d / (mx + mn);
    if (mx == r) {
      h = (g - b) / d + (g < b ? 6 : 0);
    } else if (mx == g) {
      h = (b - r) / d + 2;
    } else {
      h = (r - g) / d + 4;
    }
    h *= 60;
  }
  return <double>[h, s * 100, l * 100];
}

String hsv2hex(double h, double s, double v) {
  s /= 100;
  v /= 100;
  double f(int n) {
    final double k = (n + h / 60) % 6;
    return v - v * s * math.max(0, math.min(k, math.min(4 - k, 1)));
  }

  return rgb2hex(<double>[f(5) * 255, f(3) * 255, f(1) * 255]);
}

List<int> hex2hsv(String hex) {
  final List<int> a = hex2rgb(hex);
  final double r = a[0] / 255, g = a[1] / 255, b = a[2] / 255;
  final double mx = math.max(r, math.max(g, b)),
      mn = math.min(r, math.min(g, b));
  final double d = mx - mn;
  double h = 0;
  if (d != 0) {
    if (mx == r) {
      // JS `%` keeps the sign of the dividend.
      final double q = (g - b) / d;
      h = q - 6 * (q / 6).truncateToDouble();
    } else if (mx == g) {
      h = (b - r) / d + 2;
    } else {
      h = (r - g) / d + 4;
    }
    h *= 60;
    if (h < 0) h += 360;
  }
  return <int>[
    h.round(),
    (mx != 0 ? d / mx * 100 : 0).round(),
    (mx * 100).round(),
  ];
}

double lumOf(List<num> a) {
  final List<double> c = a.map((num v) {
    final double x = v / 255;
    return x <= .03928
        ? x / 12.92
        : math.pow((x + .055) / 1.055, 2.4).toDouble();
  }).toList();
  return .2126 * c[0] + .7152 * c[1] + .0722 * c[2];
}

double contrastOf(String h1, String h2) {
  final double a = lumOf(hex2rgb(h1)), b = lumOf(hex2rgb(h2));
  return (math.max(a, b) + .05) / (math.min(a, b) + .05);
}

class Combo {
  const Combo(this.t, this.s, this.sh, this.cap);
  final String t;
  final String s;
  final double sh;
  final double cap;
}

const List<Combo> kCombos = <Combo>[
  Combo('Tonal', 'One calm colour family', 0, 42),
  Combo('Harmony', 'Neighbour shades', 32, 40),
  Combo('Contrast', 'Opposite colour accents', 180, 34),
  Combo('Balanced', 'Three-way colour mix', 120, 30),
  Combo('Business', 'Quiet neutral greys', 0, 8),
];

({String c, double l}) readable(
  double h,
  double s,
  double l,
  String bg,
  double min,
) {
  String c = hslx(h, s, l);
  while (contrastOf(c, bg) < min && l > 6) {
    l -= 2;
    c = hslx(h, s, l);
  }
  return (c: c, l: l);
}

/// Output of [makeTheme]: the 14 THEME_KEYS.
class GeneratedTheme {
  const GeneratedTheme({
    required this.acc,
    required this.acc2,
    required this.acc3,
    required this.navy,
    required this.navy2,
    required this.navy3,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.gt,
    required this.wall,
    required this.o1,
    required this.o2,
    required this.o3,
  });
  final Color acc, acc2, acc3, navy, navy2, navy3, ink, ink2, ink3, gt;
  final WallSpec wall;
  final Color o1, o2, o3;
}

final Map<String, GeneratedTheme> _themeCache = <String, GeneratedTheme>{};

/// `makeTheme(hex, ci)` (1898–1910).
GeneratedTheme makeTheme(String hex, int ci) =>
    _themeCache.putIfAbsent('$hex|$ci', () => _makeTheme(hex, ci));

GeneratedTheme _makeTheme(String hex, int ci) {
  final List<double> hs = rgb2hsl(hex2rgb(hex));
  final double h = hs[0];
  final bool grey = hs[1] < 10;
  final double sa = grey ? hs[1] : clampN(hs[1], 38, 82);
  final Combo cb = (ci >= 0 && ci < kCombos.length) ? kCombos[ci] : kCombos[0];
  const String bg = '#F2F4FA';
  final ({String c, double l}) a = readable(h, sa, 46, bg, 4.8);
  final String acc = a.c;
  final String acc2 = hslx(h, sa, math.min(a.l + 11, 62));
  final String acc3 = hslx(h, sa, math.max(a.l - 10, 8));
  final double h2 = h + cb.sh;
  final double ss = grey ? hs[1] : math.min(sa, cb.cap);
  final String ink3 = readable(h2, math.min(ss, 18), 42, bg, 4.8).c;
  final List<double> gtr = hsl2rgb(h, grey ? 0 : 55, 98.4);
  final double t2 = cb.sh == 0 ? h + 18 : h2;
  final double t3 = cb.sh == 0
      ? h - 18
      : (h + h2) / 2 + (cb.sh == 180 ? 90 : 0);
  final Color b1 = hexColor(hslx(h, grey ? 6 : 66, 87));
  final Color b2 = hexColor(hslx(t2, grey ? 6 : 56, 89));
  final Color b3 = hexColor(hslx(t3, grey ? 4 : 46, 91));
  final Color top = hexColor(hslx(h, grey ? 5 : 40, 96.6));
  final Color bot = hexColor(hslx(h2, grey ? 5 : 30, 93.6));
  final WallSpec wall = WallSpec(<WallLayer>[
    RadialLayer.fade(.60, .38, .12, .06, b1),
    RadialLayer.fade(.55, .34, .95, .24, b2),
    RadialLayer.fade(.70, .40, .80, .96, b3),
    LinearLayer(180, <GStop>[GStop(top, 0), GStop(bot, 1)]),
  ]);
  return GeneratedTheme(
    acc: hexColor(acc),
    acc2: hexColor(acc2),
    acc3: hexColor(acc3),
    navy: hexColor(hslx(h2, ss, 20)),
    navy2: hexColor(hslx(h2, ss, 32)),
    navy3: hexColor(hslx(h2, ss, 14)),
    ink: hexColor(hslx(h2, math.min(ss, 28), 12)),
    ink2: hexColor(hslx(h2, math.min(ss, 22), 30)),
    ink3: hexColor(ink3),
    gt: Color.fromRGBO(gtr[0].round(), gtr[1].round(), gtr[2].round(), 1),
    wall: wall,
    o1: hexColor(hslx(h, grey ? 6 : 60, 82)),
    o2: hexColor(hslx(t2, grey ? 6 : 50, 85)),
    o3: hexColor(hslx(t3, grey ? 4 : 44, 87)),
  );
}
