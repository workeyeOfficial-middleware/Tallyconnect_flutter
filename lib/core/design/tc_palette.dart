// Looks (.ps-*), accents (.ac-*), wallpapers (.wp-*) and the resolver that
// reproduces the root-class cascade of Main.dc.html (lines 341–446, 1875–1913,
// rootCls 2752, applyTheme 1958).
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'tc_color_math.dart';
import 'tc_wall_spec.dart';

Color _h(String hex, [double a = 1]) => hexColor(hex, a);

RadialLayer _rf(double rx, double ry, double cx, double cy, String hex) =>
    RadialLayer.fade(rx, ry, cx, cy, _h(hex));

LinearLayer _lin(double angle, List<String> hex) => LinearLayer(angle, <GStop>[
  for (int i = 0; i < hex.length; i++) GStop(_h(hex[i]), i / (hex.length - 1)),
]);

/// A wallpaper: `--wall` plus the three orb colours.
class Wall {
  const Wall(this.spec, this.o1, this.o2, this.o3);
  final WallSpec spec;
  final Color o1, o2, o3;
}

final Wall _aurora = Wall(
  WallSpec(<WallLayer>[
    _rf(.60, .38, .12, .06, '#C9DCFA'),
    _rf(.55, .34, .95, .22, '#E2D8F7'),
    _rf(.70, .40, .80, .96, '#D3E4F8'),
    _rf(.45, .30, .04, .70, '#F1DFE8'),
    _lin(180, <String>['#EEF2FB', '#E7EBF6']),
  ]),
  _h('#BCD3F8'),
  _h('#DCCCF5'),
  _h('#F0D3DF'),
);

final Wall _ocean = Wall(
  WallSpec(<WallLayer>[
    _rf(.60, .40, .10, .05, '#BDE3F3'),
    _rf(.55, .35, .95, .25, '#C7D6F8'),
    _rf(.70, .45, .70, .98, '#CDEFEA'),
    _lin(180, <String>['#EDF6FA', '#E3EEF6']),
  ]),
  _h('#A9D6EF'),
  _h('#BFD0F6'),
  _h('#BFE8E1'),
);

final Wall _lavender = Wall(
  WallSpec(<WallLayer>[
    _rf(.60, .40, .12, .06, '#DACDF6'),
    _rf(.55, .35, .92, .30, '#F2D3E6'),
    _rf(.70, .45, .60, .98, '#CBD4F6'),
    _lin(180, <String>['#F3F0FB', '#EAE5F6']),
  ]),
  _h('#CDBBF2'),
  _h('#EEC5DC'),
  _h('#C0CBF3'),
);

final Wall _sunrise = Wall(
  WallSpec(<WallLayer>[
    _rf(.60, .40, .10, .06, '#FBD6C3'),
    _rf(.55, .35, .95, .28, '#F6CFDA'),
    _rf(.70, .45, .65, .98, '#FBE6C2'),
    _lin(180, <String>['#FCF4EE', '#F6EBE7']),
  ]),
  _h('#F7C6AE'),
  _h('#F2C0CF'),
  _h('#F7DDB0'),
);

final Wall _mint = Wall(
  WallSpec(<WallLayer>[
    _rf(.60, .40, .10, .06, '#C9EADB'),
    _rf(.55, .35, .95, .26, '#CFE5F2'),
    _rf(.70, .45, .65, .98, '#E2F0CE'),
    _lin(180, <String>['#EFF8F3', '#E6F1EC']),
  ]),
  _h('#B5E0CB'),
  _h('#BCD9EC'),
  _h('#D7EBB9'),
);

final Wall _pearl = Wall(
  WallSpec(<WallLayer>[
    _rf(.60, .40, .12, .06, '#E4E7F0'),
    _rf(.55, .35, .92, .28, '#F1ECE4'),
    _rf(.70, .45, .60, .98, '#E0E7F2'),
    _lin(180, <String>['#F7F7F9', '#EDEEF2']),
  ]),
  _h('#DADFEA'),
  _h('#EAE3D8'),
  _h('#D8E0EC'),
);

final Wall _silk = Wall(
  WallSpec(<WallLayer>[
    RepeatingLinearLayer(118, <GStop>[
      GStop(_h('#FFFFFF', 0), 0),
      GStop(_h('#FFFFFF', 0), 30),
      GStop(_h('#FFFFFF', .4), 36),
      GStop(_h('#FFFFFF', 0), 42),
      GStop(_h('#FFFFFF', 0), 72),
    ]),
    _rf(.90, .60, 0, 0, '#D3E1FB').withEnd(.65),
    _rf(.80, .60, 1, 1, '#F2D8E6').withEnd(.65),
    LinearLayer(160, <GStop>[
      GStop(_h('#E6EBFA'), 0),
      GStop(_h('#EEE6F6'), .55),
      GStop(_h('#F6E8EE'), 1),
    ]),
  ]),
  _h('#CAD8F8'),
  _h('#E2D2F3'),
  _h('#F1D2E0'),
);

final Wall _prism = Wall(
  WallSpec(<WallLayer>[
    RadialLayer.fade(.70, .55, .50, .45, _h('#FFFFFF', .72)),
    ConicLayer(200, .65, .35, <Color>[
      _h('#D6E4FB'),
      _h('#E6D8F6'),
      _h('#F5DCE5'),
      _h('#FAE9D6'),
      _h('#D9EFE6'),
      _h('#D6E4FB'),
    ]),
  ]),
  _h('#CFE0FA'),
  _h('#EBD3F1'),
  _h('#F7E0CB'),
);

final Wall _dunes = Wall(
  WallSpec(<WallLayer>[
    RadialLayer(1.60, .55, .20, 1.18, <GStop>[
      GStop(_h('#E8CDB9'), 0),
      GStop(_h('#E8CDB9'), .45),
      GStop(_h('#E8CDB9', 0), .62),
    ]),
    RadialLayer(1.50, .50, .90, 1.25, <GStop>[
      GStop(_h('#EBD9C6'), 0),
      GStop(_h('#EBD9C6'), .45),
      GStop(_h('#EBD9C6', 0), .60),
    ]),
    LinearLayer(180, <GStop>[
      GStop(_h('#DCE7F7'), 0),
      GStop(_h('#EEF0F6'), .55),
      GStop(_h('#F5EDE6'), 1),
    ]),
  ]),
  _h('#CFDDF6'),
  _h('#F1DCCB'),
  _h('#E8D3C2'),
);

extension on RadialLayer {
  RadialLayer withEnd(double end) => RadialLayer(rx, ry, cx, cy, <GStop>[
    stops.first,
    GStop(stops.last.color, end),
  ]);
}

/// `.wp-*` (lines 342–350).
final Map<String, Wall> kWalls = <String, Wall>{
  'aurora': _aurora,
  'ocean': _ocean,
  'lavender': _lavender,
  'sunrise': _sunrise,
  'mint': _mint,
  'pearl': _pearl,
  'silk': _silk,
  'prism': _prism,
  'dunes': _dunes,
};

class KT {
  const KT(this.k, this.t, [this.s = '']);
  final String k, t, s;
}

/// WALLS (1913).
const List<KT> kWallList = <KT>[
  KT('aurora', 'Aurora mist'),
  KT('ocean', 'Ocean haze'),
  KT('lavender', 'Lavender'),
  KT('sunrise', 'Sunrise'),
  KT('mint', 'Mint garden'),
  KT('pearl', 'Pearl'),
  KT('silk', 'Silk waves'),
  KT('prism', 'Prism'),
  KT('dunes', 'Dunes'),
];

/// LOOKS (1875).
const List<KT> kLooks = <KT>[
  KT('aurora', 'Aurora', 'Maroon & navy · misty blue'),
  KT('ocean', 'Ocean Breeze', 'Calm blues'),
  KT('royal', 'Royal Silk', 'Violet on silk waves'),
  KT('sunrise', 'Sunrise Clay', 'Warm terracotta'),
  KT('mint', 'Mint Ledger', 'Fresh greens'),
  KT('pearl', 'Pearl Graphite', 'Quiet neutrals'),
  KT('prism', 'Prism Indigo', 'Soft rainbow glass'),
  KT('rose', 'Rose Quartz', 'Rose on lavender'),
];

/// One `.ps-*` look (lines 353–360, pos/neg/warn 442–446).
class Look {
  const Look({
    required this.acc,
    required this.navy,
    required this.ink,
    required this.gt,
    required this.wall,
    this.pnw = const <String>['#0F7B55', '#B4233F', '#A5470E'],
  });

  /// acc, acc2, acc3
  final List<String> acc;

  /// navy, navy2, navy3
  final List<String> navy;

  /// ink, ink2, ink3
  final List<String> ink;
  final Color gt;
  final Wall wall;

  /// pos, neg, warn
  final List<String> pnw;
}

final Map<String, Look> kLookDefs = <String, Look>{
  'aurora': Look(
    acc: const <String>['#8C1D3F', '#A42A52', '#6E1531'],
    navy: const <String>['#1B2D5B', '#2A4584', '#172A55'],
    ink: const <String>['#0E1B33', '#3F4B68', '#58647F'],
    gt: const Color(0xFFFFFFFF),
    wall: _aurora,
  ),
  'ocean': Look(
    acc: const <String>['#0B6A8F', '#1486B0', '#07506D'],
    navy: const <String>['#133A63', '#1F5690', '#0E2B4B'],
    ink: const <String>['#0B2340', '#34506B', '#4D677F'],
    gt: const Color.fromRGBO(244, 250, 255, 1),
    wall: _ocean,
    pnw: const <String>['#0F7B62', '#B4364A', '#A5530E'],
  ),
  'royal': Look(
    acc: const <String>['#5A3DBF', '#7457D9', '#43299A'],
    navy: const <String>['#26235F', '#3A3790', '#1B1946'],
    ink: const <String>['#1C1640', '#453F6B', '#5D5782'],
    gt: const Color.fromRGBO(250, 247, 255, 1),
    wall: _silk,
  ),
  'sunrise': Look(
    acc: const <String>['#A2462A', '#BF5E3E', '#7E331C'],
    navy: const <String>['#3A2C4A', '#574370', '#2A1F36'],
    ink: const <String>['#2A1A14', '#5A443A', '#6E574D'],
    gt: const Color.fromRGBO(255, 250, 246, 1),
    wall: _sunrise,
    pnw: const <String>['#3E7B3A', '#A93A22', '#9A5B04'],
  ),
  'mint': Look(
    acc: const <String>['#0E7159', '#169174', '#0A5443'],
    navy: const <String>['#16423C', '#22625A', '#0F302B'],
    ink: const <String>['#0F2A24', '#36514A', '#4B665E'],
    gt: const Color.fromRGBO(246, 253, 250, 1),
    wall: _mint,
    pnw: const <String>['#0E7159', '#B0364A', '#9A5B04'],
  ),
  'pearl': Look(
    acc: const <String>['#3E4C63', '#56657F', '#2B3647'],
    navy: const <String>['#1E2635', '#33405A', '#141A25'],
    ink: const <String>['#141A25', '#3F4758', '#565E6E'],
    gt: const Color(0xFFFFFFFF),
    wall: _pearl,
  ),
  'prism': Look(
    acc: const <String>['#4338CA', '#5B51E0', '#312A9E'],
    navy: const <String>['#1E1B4B', '#2E2A75', '#151238'],
    ink: const <String>['#15133A', '#413E66', '#58557C'],
    gt: const Color(0xFFFFFFFF),
    wall: _prism,
  ),
  'rose': Look(
    acc: const <String>['#A0306A', '#B8487F', '#7C2352'],
    navy: const <String>['#3B2350', '#57346F', '#2A1839'],
    ink: const <String>['#24152E', '#4E3F5A', '#63556F'],
    gt: const Color.fromRGBO(252, 248, 255, 1),
    wall: _lavender,
    pnw: const <String>['#1F7A5C', '#A8324A', '#A5470E'],
  ),
};

/// ACCENTS (1876–1877) with the `.ac-*` class values (401–411, 436–441).
class Accent {
  const Accent(this.k, this.t, this.a, this.b, this.acc, this.navy);
  final String k, t;

  /// Swatch gradient ends.
  final String a, b;

  /// acc, acc2, acc3 / navy, navy2, navy3 from the CSS class.
  final List<String> acc, navy;
}

const List<Accent> kAccents = <Accent>[
  Accent(
    'maroon',
    'Maroon',
    '#8C1D3F',
    '#6E1531',
    <String>['#8C1D3F', '#A42A52', '#6E1531'],
    <String>['#4A1428', '#6B2240', '#360E1D'],
  ),
  Accent(
    'berry',
    'Berry',
    '#A0306A',
    '#7C2352',
    <String>['#A0306A', '#B8487F', '#7C2352'],
    <String>['#4E1838', '#6E2A52', '#3A1129'],
  ),
  Accent(
    'violet',
    'Violet',
    '#6D3FC4',
    '#5530A0',
    <String>['#6D3FC4', '#8558DB', '#5530A0'],
    <String>['#2E1F5E', '#43308A', '#211646'],
  ),
  Accent(
    'indigo',
    'Indigo',
    '#4338CA',
    '#312A9E',
    <String>['#4338CA', '#5B51E0', '#312A9E'],
    <String>['#1E1B4B', '#2E2A75', '#151238'],
  ),
  Accent(
    'blue',
    'Royal Blue',
    '#1D4ED8',
    '#1A3FAE',
    <String>['#1D4ED8', '#3B6BEA', '#1A3FAE'],
    <String>['#172554', '#1E3A8A', '#0F1B40'],
  ),
  Accent(
    'ocean',
    'Ocean',
    '#0B6A8F',
    '#07506D',
    <String>['#0B6A8F', '#1486B0', '#07506D'],
    <String>['#133A63', '#1F5690', '#0E2B4B'],
  ),
  Accent(
    'teal',
    'Teal',
    '#0F766E',
    '#0B5953',
    <String>['#0F766E', '#14958A', '#0B5953'],
    <String>['#133F3C', '#1E5E58', '#0D2E2B'],
  ),
  Accent(
    'emerald',
    'Emerald',
    '#0E7159',
    '#0A5443',
    <String>['#0E7159', '#169174', '#0A5443'],
    <String>['#16423C', '#22625A', '#0F302B'],
  ),
  Accent(
    'bronze',
    'Bronze',
    '#9A5B04',
    '#7A4703',
    <String>['#9A5B04', '#B8730F', '#7A4703'],
    <String>['#3D2A12', '#5C3F1B', '#2B1E0C'],
  ),
  Accent(
    'terracotta',
    'Terracotta',
    '#A2462A',
    '#7E331C',
    <String>['#A2462A', '#BF5E3E', '#7E331C'],
    <String>['#4A2418', '#6A3522', '#361A11'],
  ),
  Accent(
    'graphite',
    'Graphite',
    '#3E4C63',
    '#2B3647',
    <String>['#3E4C63', '#56657F', '#2B3647'],
    <String>['#1E2635', '#33405A', '#141A25'],
  ),
  Accent(
    'slate',
    'Slate',
    '#334E68',
    '#243B53',
    <String>['#334E68', '#486581', '#243B53'],
    <String>['#102A43', '#243B53', '#0B1D30'],
  ),
  Accent(
    'plum',
    'Plum',
    '#7A2E7A',
    '#5E215E',
    <String>['#7A2E7A', '#934493', '#5E215E'],
    <String>['#3A1638', '#55224F', '#2A0F28'],
  ),
  Accent(
    'clayrose',
    'Clay Rose',
    '#A0405A',
    '#7E2E44',
    <String>['#A0405A', '#B85A72', '#7E2E44'],
    <String>['#4A1E2A', '#6A2C3C', '#36151E'],
  ),
  Accent(
    'cocoa',
    'Cocoa',
    '#6B4A3A',
    '#52372A',
    <String>['#6B4A3A', '#85604E', '#52372A'],
    <String>['#2F2019', '#4A3327', '#211611'],
  ),
  Accent(
    'olive',
    'Olive',
    '#5F6B2E',
    '#4A5423',
    <String>['#5F6B2E', '#77853C', '#4A5423'],
    <String>['#2A3014', '#3F4820', '#1E220E'],
  ),
  Accent(
    'forest',
    'Forest',
    '#2F6B3A',
    '#22522B',
    <String>['#2F6B3A', '#3F874B', '#22522B'],
    <String>['#173320', '#244B2F', '#102416'],
  ),
];

Accent? accentOf(String k) {
  for (final Accent a in kAccents) {
    if (a.k == k) return a;
  }
  return null;
}

/// LOOKACC (1878).
const Map<String, List<String>> kLookAcc = <String, List<String>>{
  'aurora': <String>['berry', 'indigo', 'blue', 'graphite'],
  'ocean': <String>['blue', 'teal', 'slate', 'indigo'],
  'royal': <String>['indigo', 'berry', 'plum', 'graphite'],
  'sunrise': <String>['bronze', 'clayrose', 'cocoa', 'olive'],
  'mint': <String>['teal', 'forest', 'ocean', 'graphite'],
  'pearl': <String>['slate', 'blue', 'maroon', 'emerald'],
  'prism': <String>['violet', 'blue', 'berry', 'teal'],
  'rose': <String>['plum', 'maroon', 'violet', 'clayrose'],
};

/// LOOKSIG (1879): [name, from, to].
const Map<String, List<String>> kLookSig = <String, List<String>>{
  'aurora': <String>['Maroon', '#8C1D3F', '#6E1531'],
  'ocean': <String>['Ocean', '#0B6A8F', '#07506D'],
  'royal': <String>['Royal Violet', '#5A3DBF', '#43299A'],
  'sunrise': <String>['Terracotta', '#A2462A', '#7E331C'],
  'mint': <String>['Emerald', '#0E7159', '#0A5443'],
  'pearl': <String>['Graphite', '#3E4C63', '#2B3647'],
  'prism': <String>['Indigo', '#4338CA', '#312A9E'],
  'rose': <String>['Rose', '#A0306A', '#7C2352'],
};

/// `okAccent` (1912).
bool okAccent(String look, String a) =>
    a == 'look' || (kLookAcc[look] ?? const <String>[]).contains(a);

/// Resolved custom properties for one root (or one thumbnail).
class TcPalette {
  const TcPalette({
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
    required this.pos,
    required this.neg,
    required this.warn,
    required this.wall,
    required this.o1,
    required this.o2,
    required this.o3,
    this.g = .6,
    this.gb = 0,
    this.photoPath,
    this.photoDark = false,
    Color? pageInk,
    Color? pageInk2,
    Color? pageInk3,
    this.fillFloor = 0,
    this.tabInk = kTabInk0,
    this.filterInk = kTabInk0,
  }) : pageInk = pageInk ?? ink,
       pageInk2 = pageInk2 ?? ink2,
       pageInk3 = pageInk3 ?? ink3;

  final Color acc, acc2, acc3, navy, navy2, navy3, ink, ink2, ink3, gt;

  /// Text drawn straight on the background (titles, sub-titles, section
  /// labels, tab labels, empty notes): dark on a light background, light on
  /// a dark one — always readable (see [resolvePalette]).
  final Color pageInk, pageInk2, pageInk3;

  /// Unselected bottom-bar tab labels (on the see-through bar).
  final Color tabInk;

  /// Unselected labels of glass filter rows (on the glass).
  final Color filterInk;

  /// Least glass / sheet opacity so dark text inside cards stays readable
  /// over a dark or busy background.
  final double fillFloor;

  /// The background behind the screens is dark (light page text).
  bool get pageDark => pageInk.computeLuminance() > .5;
  final Color pos, neg, warn;
  final WallSpec wall;
  final Color o1, o2, o3;

  /// `--g` glass level, `--gb` photo boost.
  final double g, gb;

  /// Photo wallpaper (`.photo`); orbs hide when set.
  final String? photoPath;
  final bool photoDark;

  bool get hasPhoto => photoPath != null;

  /// How see-through the glass is, 0 … 1, from the Glass setting (20–100 %):
  /// a higher setting is clearer glass (less tint, softer sheen), never a
  /// whiter one.
  double get clarity => glassClarity(g);

  /// `.glass` tint opacity (cards, lists, sidebar): 74 % at 20 → 12 % at
  /// 100, never below the readability floor.
  double get glassA =>
      math.max(glassTint(g) + gb, fillFloor).clamp(0, 1).toDouble();

  Color get glassFill => gt.withValues(alpha: glassA);

  /// `.sheet` fill (bottom sheets, forms): a little denser than cards.
  Color get sheetFill => gt.withValues(
    alpha: math.max(.92 - .44 * clarity, fillFloor).clamp(0, 1).toDouble(),
  );

  /// Bars on top of content (sheet / screen footers).
  Color get barFill => gt.withValues(
    alpha: math.max(.66 - .4 * clarity, fillFloor * .8).clamp(0, 1).toDouble(),
  );

  /// Strength of the glass sheen (top-left highlight): subtler on clearer
  /// glass so it does not whiten the card.
  double get sheen => 1 - .5 * clarity;

  /// `C.*` with `.icmatch` always on: every category colour is the accent.
  Color cat(String k) => k == 'navy' ? navy : acc;

  TcPalette copyWith({double? g, double? gb}) => TcPalette(
    acc: acc,
    acc2: acc2,
    acc3: acc3,
    navy: navy,
    navy2: navy2,
    navy3: navy3,
    ink: ink,
    ink2: ink2,
    ink3: ink3,
    gt: gt,
    pos: pos,
    neg: neg,
    warn: warn,
    wall: wall,
    o1: o1,
    o2: o2,
    o3: o3,
    g: g ?? this.g,
    gb: gb ?? this.gb,
    photoPath: photoPath,
    photoDark: photoDark,
    pageInk: pageInk,
    pageInk2: pageInk2,
    pageInk3: pageInk3,
    fillFloor: fillFloor,
    tabInk: tabInk,
    filterInk: filterInk,
  );

  @override
  bool operator ==(Object other) =>
      other is TcPalette &&
      other.acc == acc &&
      other.navy == navy &&
      other.ink == ink &&
      other.gt == gt &&
      identical(other.wall, wall) &&
      other.g == g &&
      other.gb == gb &&
      other.photoPath == photoPath &&
      other.pos == pos &&
      other.pageInk == pageInk &&
      other.pageInk2 == pageInk2 &&
      other.pageInk3 == pageInk3 &&
      other.ink2 == ink2 &&
      other.ink3 == ink3 &&
      other.tabInk == tabInk &&
      other.filterInk == filterInk &&
      other.fillFloor == fillFloor;

  @override
  int get hashCode => Object.hash(
    acc,
    navy,
    ink,
    gt,
    wall,
    g,
    gb,
    photoPath,
    pos,
    pageInk,
    ink2,
    ink3,
    tabInk,
    filterInk,
    fillFloor,
  );
}

/// Default unselected tab label colour (light background).
const Color kTabInk0 = Color(0xFF3C4763);

/// [c] moved toward black ([tone] > 0, darker) or white ([tone] < 0,
/// lighter) by |tone| (0 … 1) — but only as far as it still reads at
/// 4.5:1 on a surface of luminance [bgLum]; never less readable than that.
Color toneInk(Color c, double tone, double bgLum) {
  final double t = tone.clamp(-1, 1).toDouble();
  if (t == 0) return c;
  final Color to = t > 0 ? const Color(0xFF05070D) : const Color(0xFFFFFFFF);
  for (int i = 10; i > 0; i--) {
    final Color x = Color.lerp(c, to, t.abs() * i / 10)!;
    if (_contrast(x.computeLuminance(), bgLum) >= 4.5) return x;
  }
  return c;
}

/// Glass level [g] (.2 … 1 from the 20–100 % setting) → clarity 0 … 1.
double glassClarity(double g) => ((g - .2) / .8).clamp(0, 1).toDouble();

/// Glass tint opacity before the photo boost / readability floor.
double glassTint(double g) => .74 - .62 * glassClarity(g);

/// The root-class cascade: `g{n} ps-{preset} [ac-{accent}] icmatch [photo]`
/// plus applyTheme's inline overrides (custom mode, wallpaper key, photo).
// ---------------------------------------------------- readable text

/// The screen's base colour under the wallpaper (see [TcWallpaper]).
const Color kBaseBg = Color(0xFFE9EDF7);

Color _over(Color under, Color c, double a) => Color.from(
  alpha: 1,
  red: under.r + (c.r - under.r) * a,
  green: under.g + (c.g - under.g) * a,
  blue: under.b + (c.b - under.b) * a,
);

/// Average colour of a wallpaper, painted over [kBaseBg]: full-cover layers
/// count by their stops' average alpha; soft radial glows by about a third.
Color wallAverage(WallSpec spec) {
  Color acc = kBaseBg;
  for (final WallLayer l in spec.layers.reversed) {
    final List<Color> cs = switch (l) {
      LinearLayer() => l.stops.map((GStop s) => s.color).toList(),
      RepeatingLinearLayer() => l.stops.map((GStop s) => s.color).toList(),
      RadialLayer() => l.stops.map((GStop s) => s.color).toList(),
      ConicLayer() => l.colors,
    };
    if (cs.isEmpty) continue;
    double a = 0, r = 0, g = 0, b = 0;
    for (final Color c in cs) {
      a += c.a;
      r += c.r * c.a;
      g += c.g * c.a;
      b += c.b * c.a;
    }
    if (a <= 0) continue;
    final Color avg = Color.from(
      alpha: 1,
      red: r / a,
      green: g / a,
      blue: b / a,
    );
    final double cover = (a / cs.length) * (l is RadialLayer ? .35 : 1);
    acc = _over(acc, avg, cover.clamp(0, 1));
  }
  return acc;
}

double _contrast(double l1, double l2) {
  final double hi = math.max(l1, l2), lo = math.min(l1, l2);
  return (hi + .05) / (lo + .05);
}

/// [c] moved toward [to] just enough to reach [ratio] against a
/// background of luminance [bgLum] (at most fully [to]).
Color _readable(Color c, Color to, double bgLum, double ratio) {
  for (int i = 0; i <= 10; i++) {
    final Color x = Color.lerp(c, to, i / 10)!;
    if (_contrast(x.computeLuminance(), bgLum) >= ratio) return x;
  }
  return to;
}

/// Luminance of the background behind the screens: wallpaper (or photo)
/// at [opacity] over the base colour, then the Background shade veil.
double backdropLum({
  required WallSpec wall,
  required bool photo,
  required double photoLum,
  double opacity = 1,
  double shade = 0,
}) {
  final double op = opacity.clamp(0, 1).toDouble();
  final double sh = shade.clamp(-1, 1).toDouble();
  final double base = kBaseBg.computeLuminance();
  final double w = photo ? photoLum : wallAverage(wall).computeLuminance();
  double l = w * op + base * (1 - op);
  if (sh > 0) l *= 1 - .45 * sh;
  if (sh < 0) l += (1 - l) * .6 * -sh;
  return l.clamp(0, 1).toDouble();
}

TcPalette resolvePalette({
  required String preset,
  String accent = 'look',
  String mode = 'look',
  String customBase = '#8C1D3F',
  int customCombo = 0,
  String wallK = 'theme',
  String? photoPath,
  double photoLum = 1,
  double glass = 60,
  double opacity = 1,
  double shade = 0,
  double textTone = 0,
}) {
  final Look look = kLookDefs[preset] ?? kLookDefs['aurora']!;
  List<String> acc = look.acc;
  List<String> navy = look.navy;
  final Accent? ac = accent != 'look' ? accentOf(accent) : null;
  if (ac != null) {
    acc = ac.acc;
    navy = ac.navy;
  }
  Color cAcc = _h(acc[0]), cAcc2 = _h(acc[1]), cAcc3 = _h(acc[2]);
  Color cNavy = _h(navy[0]), cNavy2 = _h(navy[1]), cNavy3 = _h(navy[2]);
  Color ink = _h(look.ink[0]), ink2 = _h(look.ink[1]), ink3 = _h(look.ink[2]);
  Color gt = look.gt;
  WallSpec wall = look.wall.spec;
  Color o1 = look.wall.o1, o2 = look.wall.o2, o3 = look.wall.o3;
  if (mode == 'custom') {
    final GeneratedTheme v = makeTheme(customBase, customCombo);
    cAcc = v.acc;
    cAcc2 = v.acc2;
    cAcc3 = v.acc3;
    cNavy = v.navy;
    cNavy2 = v.navy2;
    cNavy3 = v.navy3;
    ink = v.ink;
    ink2 = v.ink2;
    ink3 = v.ink3;
    gt = v.gt;
    wall = v.wall;
    o1 = v.o1;
    o2 = v.o2;
    o3 = v.o3;
  }
  final bool photo = wallK == 'photo' && photoPath != null;
  if (!photo && wallK != 'theme' && kWalls.containsKey(wallK)) {
    final Wall w = kWalls[wallK]!;
    wall = w.spec;
    o1 = w.o1;
    o2 = w.o2;
    o3 = w.o3;
  }
  final bool dark = photo && photoLum < .35;
  final double gl = (glass / 10).round() * 10 / 100;
  final double gbv = photo ? (dark ? .2 : .12) : 0;

  // ---- Readable text on any background.
  // Page text (on the background itself): dark or light, whichever reads
  // better (WCAG contrast), then each shade nudged to at least 4.5:1.
  final double bg = backdropLum(
    wall: wall,
    photo: photo,
    photoLum: photoLum,
    opacity: opacity,
    shade: shade,
  );
  const Color light = Color(0xFFF5F7FC);
  final bool lightText =
      _contrast(light.computeLuminance(), bg) >
      _contrast(ink.computeLuminance(), bg);
  final Color pInk = lightText ? light : ink;
  final Color pInk2 = lightText
      ? _readable(const Color(0xFFDCE2EE), light, bg, 4.5)
      : _readable(ink2, ink, bg, 4.5);
  final Color pInk3 = lightText
      ? _readable(const Color(0xFFBFC7D8), light, bg, 4.5)
      : _readable(ink3, ink, bg, 4.5);
  // Card text stays dark: the glass keeps just enough tint that the card
  // reads as light over a dark / busy background (luminance ≥ .6 on the
  // least clear setting, ≥ .28 — still 4.5:1 for the card ink — on the
  // clearest), and the lighter text shades are nudged to 4.5:1 on it. So a
  // clearer setting always shows more of the background, never a whiter
  // card.
  final double gtl = gt.computeLuminance();
  final double a0 = (glassTint(gl) + gbv).clamp(0, 1).toDouble();
  final double need = .6 - .32 * glassClarity(gl);
  double floor = 0;
  if (gtl > bg && bg + (gtl - bg) * a0 < need) {
    floor = ((need - bg) / (gtl - bg)).clamp(0, .96).toDouble();
  }
  final double cardLum = bg + (gtl - bg) * math.max(a0, floor);
  ink2 = _readable(ink2, ink, cardLum, 4.5);
  ink3 = _readable(ink3, ink, cardLum, 4.5);

  // ---- Text colour (Settings → Background): every text shade moved
  // lighter / darker, each only as far as it stays readable on its surface
  // (page text on the background, card text on the glass).
  final double tt = textTone.clamp(-1, 1).toDouble();
  final Color tInk = lightText ? pInk2 : kTabInk0;

  return TcPalette(
    acc: cAcc,
    acc2: cAcc2,
    acc3: cAcc3,
    navy: cNavy,
    navy2: cNavy2,
    navy3: cNavy3,
    ink: toneInk(ink, tt, cardLum),
    ink2: toneInk(ink2, tt, cardLum),
    ink3: toneInk(ink3, tt, cardLum),
    gt: gt,
    pos: _h(look.pnw[0]),
    neg: _h(look.pnw[1]),
    warn: _h(look.pnw[2]),
    wall: wall,
    o1: o1,
    o2: o2,
    o3: o3,
    g: gl,
    gb: gbv,
    photoPath: photo ? photoPath : null,
    photoDark: dark,
    pageInk: toneInk(pInk, tt, bg),
    pageInk2: toneInk(pInk2, tt, bg),
    pageInk3: toneInk(pInk3, tt, bg),
    fillFloor: floor,
    tabInk: toneInk(tInk, tt, bg),
    filterInk: toneInk(kTabInk0, tt, cardLum),
  );
}

/// Palette for one look thumbnail (`lthumb ps-{k} [ac-{a}]`).
TcPalette lookThumbPalette(String look, String accent) => resolvePalette(
  preset: look,
  accent: accent != 'look' && okAccent(look, accent) ? accent : 'look',
);

/// Inherited palette.
class Tc extends InheritedWidget {
  const Tc({super.key, required this.p, required super.child});
  final TcPalette p;

  static TcPalette of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Tc>()!.p;

  @override
  bool updateShouldNotify(Tc old) => old.p != p;
}
