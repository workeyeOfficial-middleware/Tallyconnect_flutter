// Component kit reproducing the prototype's CSS classes (Main.dc.html 38–486):
// .glass, .tap, .ico, .btn, .chip, .seg, .inp, .badge, .sw, .av, .kv, .row …
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tc_icons.dart';
import 'tc_palette.dart';

// --------------------------------------------------------------- primitives

/// CSS `box-shadow: x y blur spread color` → Flutter (blur b ≈ σ·2).
BoxShadow css(double x, double y, double blur, double spread, Color c) =>
    BoxShadow(
      offset: Offset(x, y),
      blurRadius: math.max(0, (blur / 2 - .5) / .57735),
      spreadRadius: spread,
      color: c,
    );

const Color kNavyA = Color(0xFF1B2D5B); // rgba(27,45,91,·)
Color navyA(double a) => kNavyA.withValues(alpha: a);
Color whiteA(double a) => Colors.white.withValues(alpha: a);

/// `color-mix(in srgb, X p%, transparent)`.
Color mix(Color c, double p) => c.withValues(alpha: c.a * p);

/// `color-mix(in srgb, A p%, B)` — premultiplied, as CSS specifies.
Color mixWith(Color a, double p, Color b) {
  final double al = a.a * p + b.a * (1 - p);
  if (al <= 0) return const Color(0x00000000);
  double ch(double x, double y) => (x * a.a * p + y * b.a * (1 - p)) / al;
  return Color.from(
    alpha: al,
    red: ch(a.r, b.r),
    green: ch(a.g, b.g),
    blue: ch(a.b, b.b),
  );
}

const String kFont = 'Figtree';

TextStyle ts(
  double size, {
  FontWeight w = FontWeight.w400,
  Color? c,
  double? h,
  double ls = 0,
  bool tab = false,
}) => TextStyle(
  fontFamily: kFont,
  fontSize: size,
  fontWeight: w,
  color: c,
  height: h,
  letterSpacing: ls,
  fontFeatures: tab ? const <FontFeature>[FontFeature.tabularFigures()] : null,
);

const FontWeight w400 = FontWeight.w400;
const FontWeight w600 = FontWeight.w600;
const FontWeight w700 = FontWeight.w700;
const FontWeight w800 = FontWeight.w800;

// ------------------------------------------------------------------- glass

final ui.ImageFilter _glassFilter = ui.ImageFilter.compose(
  outer: ColorFilter.matrix(_saturate(1.85)),
  inner: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26, tileMode: TileMode.clamp),
);

List<double> _saturate(double s, [double brightness = 1, double contrast = 1]) {
  const double lr = .2126, lg = .7152, lb = .0722;
  final double sr = (1 - s) * lr, sg = (1 - s) * lg, sb = (1 - s) * lb;
  final double b = brightness * contrast;
  final double t = 128 * (1 - contrast) * brightness;
  return <double>[
    (sr + s) * b,
    sg * b,
    sb * b,
    0,
    t,
    sr * b,
    (sg + s) * b,
    sb * b,
    0,
    t,
    sr * b,
    sg * b,
    (sb + s) * b,
    0,
    t,
    0,
    0,
    0,
    1,
    0,
  ];
}

/// backdrop-filter: blur(b) saturate(s) brightness(br) contrast(c).
ui.ImageFilter backdrop(
  double blur,
  double sat, [
  double br = 1,
  double ct = 1,
]) => ui.ImageFilter.compose(
  outer: ColorFilter.matrix(_saturate(sat, br, ct)),
  inner: ui.ImageFilter.blur(
    sigmaX: blur,
    sigmaY: blur,
    tileMode: TileMode.clamp,
  ),
);

const List<BoxShadow> kGlassShadow = <BoxShadow>[];

List<BoxShadow> glassShadows() => <BoxShadow>[
  css(0, 14, 34, -16, navyA(.24)),
  css(0, 2, 6, 0, navyA(.05)),
];

/// `.glass`: translucent tint, white hairline, sheen, inner highlight and soft
/// navy shadow. [blur] adds the real backdrop blur (used for floating chrome).
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    this.child,
    this.radius = 22,
    this.padding,
    this.fill,
    this.gradient,
    this.border,
    this.shadows,
    this.blur = false,
    this.filter,
    this.sheen = true,
    this.width,
    this.height,
    this.borderRadius,
    this.sheenGradient,
  });

  final Widget? child;
  final double radius;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? fill;
  final Gradient? gradient;
  final Border? border;
  final List<BoxShadow>? shadows;
  final bool blur;
  final ui.ImageFilter? filter;
  final bool sheen;
  final Gradient? sheenGradient;
  final double? width, height;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final BorderRadius br = borderRadius ?? BorderRadius.circular(radius);
    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        color: gradient == null ? (fill ?? p.glassFill) : null,
        gradient: gradient,
        borderRadius: br,
      ),
      child: CustomPaint(
        foregroundPainter: _GlassEdge(br, border),
        painter: sheen ? _Sheen(br, sheenGradient) : null,
        child: OnSurface(
          child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ),
      ),
    );
    if (blur) {
      body = ClipRRect(
        borderRadius: br,
        child: BackdropFilter(filter: filter ?? _glassFilter, child: body),
      );
    }
    final List<BoxShadow> sh = shadows ?? glassShadows();
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: sh.isEmpty ? null : OuterShadow(br, sh),
        child: body,
      ),
    );
  }
}

/// [Glass]'s look as a [Decoration] (outer shadow, fill, sheen, edge), for
/// surfaces that are slivers — e.g. a lazily built list inside one glass
/// card ([DecoratedSliver]) — so they look exactly like [Glass].
class GlassDecoration extends Decoration {
  const GlassDecoration({
    required this.fill,
    this.radius = 22,
    this.shadows = const <BoxShadow>[],
  });
  final Color fill;
  final double radius;
  final List<BoxShadow> shadows;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _GlassBoxPainter(this);

  @override
  bool operator ==(Object other) =>
      other is GlassDecoration &&
      other.fill == fill &&
      other.radius == radius &&
      listEquals(other.shadows, shadows);

  @override
  int get hashCode => Object.hash(fill, radius, Object.hashAll(shadows));
}

class _GlassBoxPainter extends BoxPainter {
  _GlassBoxPainter(this.d);
  final GlassDecoration d;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration cfg) {
    final Size? size = cfg.size;
    if (size == null || size.isEmpty) return;
    final BorderRadius br = BorderRadius.circular(d.radius);
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    if (d.shadows.isNotEmpty) OuterShadow(br, d.shadows).paint(canvas, size);
    canvas.drawRRect(br.toRRect(Offset.zero & size), Paint()..color = d.fill);
    // The sheen is a card-sized highlight. A long lazy list is one very tall
    // box (1,000+ rows → 100,000 px); stretched over that, the visible rows
    // all fell in the sheen's white start and looked solid white. Keep it
    // at card height at the top, so every row shows the same glass.
    final double sh = math.min(size.height, kSheenMaxH);
    canvas.save();
    canvas.clipRRect(br.toRRect(Offset.zero & size));
    _Sheen(br, null).paint(canvas, Size(size.width, sh));
    canvas.restore();
    _GlassEdge(br, null).paint(canvas, size);
    canvas.restore();
  }
}

/// Tallest box the glass sheen spans (see [GlassDecoration]).
const double kSheenMaxH = 1200;

/// Paints box shadows only outside the rounded box (CSS semantics), so a
/// translucent surface is not darkened by its own shadow.
class OuterShadow extends CustomPainter {
  OuterShadow(this.br, this.shadows);
  final BorderRadius br;
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect rr = br.toRRect(Offset.zero & size);
    canvas.save();
    final Path outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromLTWH(-200, -200, size.width + 400, size.height + 400))
      ..addRRect(rr);
    canvas.clipPath(outside);
    for (final BoxShadow s in shadows) {
      final RRect r = rr.shift(s.offset).inflate(s.spreadRadius);
      canvas.drawRRect(r, s.toPaint());
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(OuterShadow old) => old.br != br || old.shadows != shadows;
}

class _Sheen extends CustomPainter {
  _Sheen(this.br, this.g);
  final BorderRadius br;
  final Gradient? g;

  static const LinearGradient _def = LinearGradient(
    begin: Alignment(-.42, -.9),
    end: Alignment(.42, .9),
    colors: <Color>[
      Color.fromRGBO(255, 255, 255, .65),
      Color.fromRGBO(255, 255, 255, 0),
      Color.fromRGBO(255, 255, 255, 0),
      Color.fromRGBO(196, 208, 246, .22),
    ],
    stops: <double>[0, .36, .72, 1],
  );

  @override
  void paint(Canvas canvas, Size size) {
    final Rect r = Offset.zero & size;
    canvas.drawRRect(
      br.toRRect(r),
      Paint()..shader = (g ?? _def).createShader(r),
    );
  }

  @override
  bool shouldRepaint(_Sheen old) => old.br != br || old.g != g;
}

class _GlassEdge extends CustomPainter {
  _GlassEdge(this.br, this.border);
  final BorderRadius br;
  final Border? border;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect rr = br.toRRect(Offset.zero & size);
    canvas.save();
    canvas.clipRRect(rr);
    // The 1 px inner rims are worked out on a corner-high strip at the top
    // and at the bottom (same shapes): on a very tall box (a long lazy list,
    // 80,000 px) subtracting two full-height shapes lost float precision and
    // filled the whole list with the white rim colour.
    final double h0 = math.min(
      size.height,
      math.max(
                math.max(br.topLeft.y, br.topRight.y),
                math.max(br.bottomLeft.y, br.bottomRight.y),
              ) *
              2 +
          4,
    );
    final RRect top = br.toRRect(Rect.fromLTWH(0, 0, size.width, h0));
    final RRect bot = br.toRRect(
      Rect.fromLTWH(0, size.height - h0, size.width, h0),
    );
    // inset 0 1px 0 rgba(255,255,255,.95)
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRRect(top),
        Path()..addRRect(top.shift(const Offset(0, 1))),
      ),
      Paint()..color = whiteA(.95),
    );
    // inset 0 -1px 0 rgba(27,45,91,.05)
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRRect(bot),
        Path()..addRRect(bot.shift(const Offset(0, -1))),
      ),
      Paint()..color = navyA(.05),
    );
    canvas.restore();
    final BorderSide side = border?.top ?? BorderSide(color: whiteA(.8));
    if (side.style != BorderStyle.none && side.width > 0) {
      canvas.drawRRect(
        rr.deflate(side.width / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = side.width
          ..color = side.color,
      );
    }
  }

  @override
  bool shouldRepaint(_GlassEdge old) => old.br != br || old.border != border;
}

// --------------------------------------------------------------------- tap

/// `.tap`: press scale .955 (120 ms), springy release (.38 s
/// cubic-bezier(.3,1.45,.5,1)) and the `::after` highlight.
class Tap extends StatefulWidget {
  const Tap({
    super.key,
    required this.child,
    this.onTap,
    this.radius = 22,
    this.borderRadius,
    this.scale = .955,
    this.highlight = true,
    this.enabled = true,
    this.subtleHighlight = false,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final BorderRadius? borderRadius;
  final double scale;
  final bool highlight;
  final bool enabled;

  /// `.hero .tap::after` / `.pdfv .tap::after` variant.
  final bool subtleHighlight;
  final HitTestBehavior behavior;

  @override
  State<Tap> createState() => _TapState();
}

class _TapState extends State<Tap> {
  bool _down = false;
  Offset? _start;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final bool on = widget.enabled && widget.onTap != null;
    final BorderRadius br =
        widget.borderRadius ?? BorderRadius.circular(widget.radius);
    return Listener(
      onPointerDown: on
          ? (PointerDownEvent e) {
              _start = e.position;
              _set(true);
            }
          : null,
      onPointerMove: on
          ? (PointerMoveEvent e) {
              if (_start != null && (e.position - _start!).distance > 12) {
                _set(false);
              }
            }
          : null,
      onPointerUp: on ? (_) => _set(false) : null,
      onPointerCancel: on ? (_) => _set(false) : null,
      child: GestureDetector(
        behavior: widget.behavior,
        onTap: on ? widget.onTap : null,
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: Duration(milliseconds: _down ? 120 : 380),
          curve: _down ? Curves.ease : const Cubic(.3, 1.45, .5, 1),
          child: widget.highlight
              ? Stack(
                  fit: StackFit.passthrough,
                  children: <Widget>[
                    widget.child,
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: _down ? 1 : 0,
                          duration: const Duration(milliseconds: 280),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: br,
                              border: Border.all(
                                color: whiteA(
                                  widget.subtleHighlight ? .55 : .85,
                                ),
                              ),
                              gradient: LinearGradient(
                                begin: const Alignment(-.35, -1),
                                end: const Alignment(.35, 1),
                                colors: widget.subtleHighlight
                                    ? <Color>[
                                        whiteA(.34),
                                        whiteA(.06),
                                        whiteA(.16),
                                      ]
                                    : <Color>[
                                        whiteA(.55),
                                        whiteA(.12),
                                        whiteA(.26),
                                      ],
                                stops: const <double>[0, .45, 1],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : widget.child,
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- icon tile

enum IcoSize { lg, sm, xs }

/// `.ico`: white tile with a 10 % tint square of the icon colour.
class Ico extends StatelessWidget {
  const Ico(
    this.k, {
    super.key,
    this.size = IcoSize.lg,
    this.color,
    this.icon = IcSize.m,
    this.box,
    this.radius,
  });

  final String k;
  final IcoSize size;
  final Color? color;
  final IcSize icon;

  /// Explicit box size (e.g. 66 / 72) and radius.
  final double? box;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final double d =
        box ??
        switch (size) {
          IcoSize.lg => 56,
          IcoSize.sm => 44,
          IcoSize.xs => 38,
        };
    final double r =
        radius ??
        switch (size) {
          IcoSize.lg => 18,
          IcoSize.sm => 14,
          IcoSize.xs => 12,
        };
    final double inset = switch (size) {
      IcoSize.lg => 7,
      IcoSize.sm => 5,
      IcoSize.xs => 4,
    };
    final double ir = switch (size) {
      IcoSize.lg => 13,
      IcoSize.sm => 10,
      IcoSize.xs => 9,
    };
    final Color c = color ?? Tc.of(context).acc;
    final BorderRadius br = BorderRadius.circular(r);
    return CustomPaint(
      painter: OuterShadow(br, <BoxShadow>[css(0, 8, 18, -9, navyA(.32))]),
      child: Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          borderRadius: br,
          border: Border.all(color: whiteA(.95)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[whiteA(.98), whiteA(.66)],
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Positioned.fill(
              left: inset - 1,
              top: inset - 1,
              right: inset - 1,
              bottom: inset - 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(ir),
                ),
              ),
            ),
            Ic(k, size: icon, color: c),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ buttons

enum BtnKind { p, a, g, plain }

/// `.btn` (56 high, radius 18, 16.5/700) in navy (`btn-p`), accent (`btn-a`),
/// glass (`btn glass btn-g`) or a custom fill.
class Btn extends StatelessWidget {
  const Btn({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.kind = BtnKind.p,
    this.enabled = true,
    this.height = 56,
    this.radius = 18,
    this.fontSize = 16.5,
    this.color,
    this.bg,
    this.padding = const EdgeInsets.symmetric(horizontal: 18),
    this.iconAfter = false,
    this.iconSize = IcSize.m,
    this.expand = true,
  });

  final String label;
  final String? icon;
  final VoidCallback? onTap;
  final BtnKind kind;
  final bool enabled;
  final double height, radius, fontSize;
  final Color? color, bg;
  final EdgeInsets padding;
  final bool iconAfter;
  final IcSize iconSize;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final Color fg =
        color ??
        switch (kind) {
          BtnKind.p || BtnKind.a => Colors.white,
          _ => p.ink,
        };
    final List<Widget> parts = <Widget>[
      if (icon != null && !iconAfter) Ic(icon!, size: iconSize, color: fg),
      Flexible(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ts(fontSize, w: w700, c: fg),
        ),
      ),
      if (icon != null && iconAfter) Ic(icon!, size: iconSize, color: fg),
    ];
    final Widget content = Padding(
      padding: padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < parts.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 8),
            parts[i],
          ],
        ],
      ),
    );
    final BorderRadius br = BorderRadius.circular(radius);
    Widget box;
    switch (kind) {
      case BtnKind.g:
        box = Glass(radius: radius, height: height, child: content);
      case BtnKind.p:
      case BtnKind.a:
        final bool a = kind == BtnKind.a;
        box = CustomPaint(
          painter: OuterShadow(br, <BoxShadow>[
            css(0, 14, 26, -12, mix(a ? p.acc3 : p.navy3, a ? .65 : .7)),
          ]),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              borderRadius: br,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: a ? <Color>[p.acc2, p.acc3] : <Color>[p.navy2, p.navy3],
              ),
            ),
            foregroundDecoration: _InsetTop(br, whiteA(.28)),
            child: content,
          ),
        );
      case BtnKind.plain:
        box = Container(
          height: height,
          decoration: BoxDecoration(borderRadius: br, color: bg),
          child: content,
        );
    }
    return Opacity(
      opacity: enabled ? 1 : .42,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Tap(onTap: onTap, radius: radius, child: box),
      ),
    );
  }
}

/// Decoration painting `inset 0 1px 0 color` along the top edge.
class _InsetTop extends Decoration {
  const _InsetTop(this.br, this.color);
  final BorderRadius br;
  final Color color;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _InsetTopPainter(br, color);
}

class _InsetTopPainter extends BoxPainter {
  _InsetTopPainter(this.br, this.color);
  final BorderRadius br;
  final Color color;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration cfg) {
    final RRect rr = br.toRRect(offset & cfg.size!);
    canvas.save();
    canvas.clipRRect(rr);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRRect(rr),
        Path()..addRRect(rr.shift(const Offset(0, 1))),
      ),
      Paint()..color = color,
    );
    canvas.restore();
  }
}

Decoration insetTop(BorderRadius br, Color c) => _InsetTop(br, c);

/// `.cbtn`: 46 round glass icon button (`.sm` 40).
class CBtn extends StatelessWidget {
  const CBtn(
    this.icon, {
    super.key,
    this.onTap,
    this.small = false,
    this.size,
    this.radius,
    this.color,
    this.iconSize,
    this.dot = false,
    this.glass = true,
    this.bg,
  });

  final String icon;
  final VoidCallback? onTap;
  final bool small;
  final double? size, radius;
  final Color? color;
  final IcSize? iconSize;

  /// `.rdot` unread dot.
  final bool dot;
  final bool glass;
  final Color? bg;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final double d = size ?? (small ? 40 : 46);
    final double r = radius ?? d / 2;
    final Widget icn = Ic(
      icon,
      size: iconSize ?? (small ? IcSize.s : IcSize.m),
      color: color ?? p.ink,
    );
    final Widget box = glass
        ? Glass(
            radius: r,
            width: d,
            height: d,
            child: Center(child: icn),
          )
        : Container(
            width: d,
            height: d,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(r),
            ),
            child: Center(child: icn),
          );
    return Tap(
      onTap: onTap,
      radius: r,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          box,
          if (dot)
            Positioned(
              top: 9,
              right: 10,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: p.neg,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// `.pbtn`: glass back pill with chevron + label in accent.
class PBtn extends StatelessWidget {
  const PBtn(this.label, {super.key, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Tap(
      onTap: onTap,
      radius: 23,
      child: Glass(
        radius: 23,
        height: 46,
        padding: const EdgeInsets.only(left: 10, right: 18),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Ic('chevL', size: IcSize.s, color: p.acc),
            const SizedBox(width: 2),
            Text(
              label,
              style: ts(16, w: w700, c: p.acc),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.chip` (glass, 42 high) — `on` turns navy.
class ChipBtn extends StatelessWidget {
  const ChipBtn(
    this.label, {
    super.key,
    this.on = false,
    this.onTap,
    this.icon,
    this.color,
    this.height = 42,
    this.fontSize = 15,
    this.iconSize = IcSize.s,
  });

  final String label;
  final bool on;
  final VoidCallback? onTap;
  final String? icon;
  final Color? color;
  final double height, fontSize;
  final IcSize iconSize;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final Color fg = on ? Colors.white : (color ?? p.ink2);
    // Never wider than the screen: very long labels end with "…" instead of
    // overflowing or overlapping the next chip.
    final double maxW = MediaQuery.sizeOf(context).width - 32;
    final Widget inner = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW > 80 ? maxW : 80),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Ic(icon!, size: iconSize, color: fg),
              const SizedBox(width: 7),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: ts(fontSize, w: w700, c: fg),
              ),
            ),
          ],
        ),
      ),
    );
    return Tap(
      onTap: onTap,
      radius: height / 2,
      child: on
          ? CustomPaint(
              painter: OuterShadow(
                BorderRadius.circular(height / 2),
                <BoxShadow>[css(0, 10, 20, -10, navyA(.7))],
              ),
              child: Container(
                height: height,
                decoration: BoxDecoration(
                  color: p.navy,
                  borderRadius: BorderRadius.circular(height / 2),
                  border: Border.all(color: navyA(.9)),
                ),
                child: inner,
              ),
            )
          : Glass(radius: height / 2, height: height, child: inner),
    );
  }
}

/// Row of chips: `.chips` gap 8, margin 4 0 14 — always ONE line that
/// scrolls sideways ([wrapMax] is no longer used; kept for callers).
class Chips extends StatelessWidget {
  const Chips({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.only(top: 4, bottom: 14),
    this.wrapMax = 8,
  });
  final List<Widget> children;
  final EdgeInsets margin;
  final int wrapMax;

  /// Filter / type chips on ONE horizontal line that swipes sideways when
  /// the chips are wider than the screen — never wrapped into more rows
  /// (same pattern as the voucher-type row).
  @override
  Widget build(BuildContext context) => Padding(
    padding: margin,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < children.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 8),
            children[i],
          ],
        ],
      ),
    ),
  );
}

/// `.seg`: glass segmented control.
class Seg extends StatelessWidget {
  const Seg({
    super.key,
    required this.items,
    required this.selected,
    required this.onPick,
    this.fontSize = 15,
    this.margin = const EdgeInsets.only(bottom: 14),
    this.hoverSelect = false,
  });

  final List<String> items;
  final int selected;
  final ValueChanged<int> onPick;
  final double fontSize;
  final EdgeInsets margin;

  /// With a mouse / trackpad, resting on an option selects it (taps work
  /// as before; touch screens have no hover).
  final bool hoverSelect;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Padding(
      padding: margin,
      child: Glass(
        radius: 17,
        padding: const EdgeInsets.all(4),
        child: Row(
          children: <Widget>[
            for (int i = 0; i < items.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: HoverDwell(
                  enabled: hoverSelect && i != selected,
                  onDwell: () => onPick(i),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onPick(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: i == selected
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0),
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: i == selected
                            ? <BoxShadow>[css(0, 3, 10, 0, navyA(.14))]
                            : const <BoxShadow>[],
                      ),
                      child: Text(
                        items[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ts(
                          fontSize,
                          w: w700,
                          c: i == selected ? p.ink : p.ink2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ badges

enum BadgeKind { ok, warn, bad, info, acc }

class Bdg extends StatelessWidget {
  const Bdg(
    this.text, {
    super.key,
    this.kind = BadgeKind.info,
    this.dot = false,
    this.padding,
    this.fontSize = 12,
    this.bg,
    this.fg,
  });
  final String text;
  final BadgeKind kind;
  final bool dot;
  final EdgeInsets? padding;
  final double fontSize;
  final Color? bg, fg;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final (Color b, Color f) = switch (kind) {
      BadgeKind.ok => (mix(p.pos, .12), p.pos),
      BadgeKind.warn => (mix(p.warn, .12), p.warn),
      BadgeKind.bad => (mix(p.neg, .12), p.neg),
      BadgeKind.info => (navyA(.08), p.navy),
      BadgeKind.acc => (mix(p.acc, .10), p.acc),
    };
    final Color fc = fg ?? f;
    return Container(
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg ?? b,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (dot) ...<Widget>[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: fc, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ts(fontSize, w: w700, c: fc),
            ),
          ),
        ],
      ),
    );
  }
}

/// Status kind helper: 'late' → bad, 'soon' → warn, else info.
BadgeKind billKind(String st) => st == 'late'
    ? BadgeKind.bad
    : (st == 'soon' ? BadgeKind.warn : BadgeKind.info);

// ------------------------------------------------------------------ switch

/// `.sw` toggle.
class Sw extends StatelessWidget {
  const Sw(this.on, {super.key});
  final bool on;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 54,
      height: 32,
      decoration: BoxDecoration(
        color: on ? p.acc : navyA(.2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: <Widget>[
          AnimatedPositioned(
            duration: const Duration(milliseconds: 350),
            curve: const Cubic(.3, 1.5, .5, 1),
            top: 3,
            left: on ? 25 : 3,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  css(0, 2, 6, 0, Colors.black.withValues(alpha: .2)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ avatar

/// `.av` (40, `.sm` 34, `.lg` 58).
class Av extends StatelessWidget {
  const Av(
    this.text, {
    super.key,
    this.size = 40,
    this.fontSize,
    this.gradient,
    this.accent = false,
  });
  final String text;
  final double size;
  final double? fontSize;
  final Gradient? gradient;

  /// Accent gradient (acc2 → acc3) as on the profile avatar.
  final bool accent;

  static const double sm = 34, lg = 58;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final double fs = fontSize ?? (size <= 34 ? 14 : (size >= 58 ? 22 : 16));
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient:
            gradient ??
            LinearGradient(
              begin: const Alignment(-.35, -1),
              end: const Alignment(.35, 1),
              colors: accent
                  ? <Color>[p.acc2, p.acc3]
                  : <Color>[p.navy2, p.navy],
            ),
      ),
      foregroundDecoration: insetTop(
        BorderRadius.circular(size / 2),
        whiteA(.3),
      ),
      child: Text(
        text,
        style: ts(fs, w: w800, c: Colors.white),
      ),
    );
  }
}

// -------------------------------------------------------------- tick/radio

/// `.tk` round check (`.tk-off` empty ring).
class Tk extends StatelessWidget {
  const Tk(this.on, {super.key, this.size = 30, this.iconSize = IcSize.xs});
  final bool on;
  final double size;
  final IcSize iconSize;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? p.acc : whiteA(.7),
        border: on ? null : Border.all(color: navyA(.22), width: 2),
      ),
      child: on ? Ic('check', size: iconSize, color: Colors.white) : null,
    );
  }
}

/// `.thck`: small check badge on selected cards.
class Thck extends StatelessWidget {
  const Thck({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Tc.of(context).acc,
      shape: BoxShape.circle,
      boxShadow: <BoxShadow>[
        css(0, 3, 8, -2, Colors.black.withValues(alpha: .3)),
      ],
    ),
    child: const Ic('check', size: IcSize.xs, color: Colors.white),
  );
}

// -------------------------------------------------------------- typography

/// Marks content drawn on a glass card / sheet (a light surface) — text
/// there keeps the card ink; outside it, text sits on the background and
/// uses the page ink ([TcPalette.pageInk]).
class OnSurface extends InheritedWidget {
  const OnSurface({super.key, required super.child});

  static bool of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<OnSurface>() != null;

  @override
  bool updateShouldNotify(OnSurface old) => false;
}

/// Readable text colour for [level] 1 (ink) / 2 (ink2) / 3 (ink3): the card
/// ink on a glass surface, else the page ink chosen for the background.
Color inkFor(BuildContext c, [int level = 1]) {
  final TcPalette p = Tc.of(c);
  final bool card = OnSurface.of(c);
  return switch (level) {
    1 => card ? p.ink : p.pageInk,
    2 => card ? p.ink2 : p.pageInk2,
    _ => card ? p.ink3 : p.pageInk3,
  };
}

class H1 extends StatelessWidget {
  const H1(
    this.text, {
    super.key,
    this.center = false,
    this.margin = const EdgeInsets.fromLTRB(4, 10, 4, 4),
    this.size = 34,
    this.afterNav = false,
  });

  /// Directly under the `.nav` row in a block `.scr`: CSS collapses the
  /// nav's 10 px bottom margin with the title's 10 px top margin.
  final bool afterNav;
  final String text;
  final bool center;
  final EdgeInsets margin;
  final double size;

  @override
  Widget build(BuildContext context) => Padding(
    padding: afterNav ? margin.copyWith(top: 0) : margin,
    child: Text(
      text,
      textAlign: center ? TextAlign.center : TextAlign.start,
      style: ts(size, w: w800, h: 1.08, ls: -.025 * size, c: inkFor(context)),
    ),
  );
}

class Sub extends StatelessWidget {
  const Sub(
    this.text, {
    super.key,
    this.center = false,
    this.margin = const EdgeInsets.fromLTRB(4, 0, 4, 16),
  });
  final String text;
  final bool center;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) => Padding(
    padding: margin,
    child: Text(
      text,
      textAlign: center ? TextAlign.center : TextAlign.start,
      style: ts(15.5, h: 1.4, c: inkFor(context, 2)),
    ),
  );
}

/// `.sec` uppercase section label.
class Sec extends StatelessWidget {
  const Sec(
    this.text, {
    super.key,
    this.margin = const EdgeInsets.fromLTRB(8, 22, 8, 8),
  });
  final String text;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) => Padding(
    padding: margin,
    child: Text(
      text.toUpperCase(),
      style: ts(12.5, w: w800, ls: .07 * 12.5, c: inkFor(context, 3)),
    ),
  );
}

/// `.h2` inside `.hrow`.
class H2Row extends StatelessWidget {
  const H2Row(this.text, {super.key, this.top = 22});
  final String text;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(4, top, 4, 12),
    child: Text(
      text,
      style: ts(20, w: w800, ls: -.2, c: inkFor(context)),
    ),
  );
}

/// `.rt` / `.rs` text pair.
class RTx extends StatelessWidget {
  const RTx(
    this.title,
    this.sub, {
    super.key,
    this.titleSize = 16,
    this.ell = false,
    this.subEll = false,
    this.subStyle,
    this.titleStyle,
    this.crossEnd = false,
  });
  final String title;
  final String? sub;
  final double titleSize;
  final bool ell, subEll;
  final TextStyle? subStyle, titleStyle;
  final bool crossEnd;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Column(
      crossAxisAlignment: crossEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          title,
          maxLines: ell ? 1 : null,
          overflow: ell ? TextOverflow.ellipsis : null,
          style: titleStyle ?? ts(titleSize, w: w700, h: 1.25, c: p.ink),
        ),
        if (sub != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              sub!,
              maxLines: subEll ? 1 : null,
              overflow: subEll ? TextOverflow.ellipsis : null,
              style: subStyle ?? ts(13.5, h: 1.3, c: p.ink3),
            ),
          ),
      ],
    );
  }
}

TextStyle rtStyle(BuildContext c, [double size = 16]) =>
    ts(size, w: w700, h: 1.25, c: Tc.of(c).ink);
TextStyle rsStyle(BuildContext c, [double size = 13.5]) =>
    ts(size, h: 1.3, c: Tc.of(c).ink3);

/// `.amt`.
TextStyle amtStyle(
  BuildContext c, {
  double size = 16,
  String cls = '',
  double ls = 0,
}) {
  final TcPalette p = Tc.of(c);
  final Color col = cls.contains('in')
      ? p.pos
      : (cls.contains('out') ? p.neg : p.ink);
  final bool big = cls.contains('big');
  return ts(
    big && size == 16 ? 32 : size,
    w: w800,
    c: col,
    tab: true,
    ls: big ? -.64 : ls,
  );
}

/// `.kv` key/value row.
class Kv extends StatelessWidget {
  const Kv(
    this.k,
    this.v, {
    super.key,
    this.strong = false,
    this.divider = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
  });
  final String k, v;
  final bool strong;
  final bool divider;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        border: divider ? Border(top: BorderSide(color: navyA(.06))) : null,
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final TextStyle ks = strong
              ? ts(17, w: w800, c: p.ink)
              : ts(15, c: p.ink3);
          final TextStyle vs = ts(
            strong ? 17 : 15,
            w: strong ? w800 : w700,
            c: p.ink,
          );
          final TextScaler sc = MediaQuery.textScalerOf(context);
          double natural(String t, TextStyle st) =>
              (TextPainter(
                text: TextSpan(text: t, style: st),
                textDirection: TextDirection.ltr,
                textScaler: sc,
              )..layout()).width +
              1;
          // CSS flex: both items shrink in proportion to their natural width
          // (`justify-content: space-between`, value right-aligned).
          // min-width:auto — an item never shrinks below its longest word.
          double minContent(String t, TextStyle st) => t
              .split(RegExp(r'\s+'))
              .map((String w) => natural(w, st))
              .fold<double>(0, (double a, double b) => a > b ? a : b);
          final double nk = natural(k, ks), nv = natural(v, vs);
          final double room = box.maxWidth - 14;
          // Unbreakable words that cannot share one line (long references,
          // big numbers on narrow phones): value goes under the key instead
          // of overflowing.
          if (minContent(k, ks) + minContent(v, vs) > room) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(k, style: ks),
                const SizedBox(height: 2),
                Text(v, textAlign: TextAlign.right, style: vs),
              ],
            );
          }
          double kw = nk, vw = nv;
          if (nk + nv > room) {
            final double over = nk + nv - room;
            kw = nk - over * nk / (nk + nv);
            vw = nv - over * nv / (nk + nv);
            final double mk = minContent(k, ks), mv = minContent(v, vs);
            if (kw < mk) {
              kw = mk;
              vw = room - kw;
            } else if (vw < mv) {
              vw = mv;
              kw = room - vw;
            }
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: kw,
                child: Text(k, style: ks),
              ),
              const Spacer(),
              SizedBox(
                width: vw,
                child: Text(v, textAlign: TextAlign.right, style: vs),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Glass list of `.kv` rows with 1px dividers.
class KvList extends StatelessWidget {
  const KvList(this.rows, {super.key, this.margin = EdgeInsets.zero});
  final List<(String, String, bool)> rows;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) => Padding(
    padding: margin,
    child: Glass(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < rows.length; i++)
            Kv(rows[i].$1, rows[i].$2, strong: rows[i].$3, divider: i > 0),
        ],
      ),
    ),
  );
}

/// `.list` divider between rows.
Widget listDivider([double a = .07]) => Container(height: 1, color: navyA(a));

/// `.tot` money box (`a` navy 6 %, `b` warn 9 %, `c` pos 10 %).
class Tot extends StatelessWidget {
  const Tot({
    super.key,
    required this.child,
    this.kind = 'a',
    this.bg,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    this.margin = const EdgeInsets.only(bottom: 10),
    this.radius = 16,
  });
  final Widget child;
  final String kind;
  final Color? bg;
  final EdgeInsets padding, margin;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final Color c =
        bg ??
        switch (kind) {
          'b' => mix(p.warn, .09),
          'c' => mix(p.pos, .10),
          'n' => mix(p.neg, .08),
          _ => navyA(.06),
        };
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: DefaultTextStyle.merge(
        style: ts(16, w: w700, c: p.ink),
        child: child,
      ),
    );
  }
}

/// `.info` box.
class InfoBox extends StatelessWidget {
  const InfoBox(
    this.text, {
    super.key,
    this.icon = 'help',
    this.margin = const EdgeInsets.only(bottom: 14),
  });
  final String text;
  final String icon;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: navyA(.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Ic(icon, size: IcSize.s, color: p.ink2),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: ts(14, h: 1.4, c: p.ink2)),
          ),
        ],
      ),
    );
  }
}

/// `.warn` / `.okb` banners.
class Banner2 extends StatelessWidget {
  const Banner2(
    this.text, {
    super.key,
    required this.ok,
    this.icon,
    this.margin = const EdgeInsets.symmetric(vertical: 12),
  });
  final String text;
  final bool ok;
  final String? icon;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final Color c = ok ? p.pos : p.warn;
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: mix(c, .10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          Ic(icon ?? (ok ? 'check' : 'info'), size: IcSize.s, color: c),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: ts(14.5, w: w700, c: c),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.empty` dashed box.
class EmptyBox extends StatelessWidget {
  const EmptyBox(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: DashedRRect(BorderRadius.circular(20), navyA(.18), 2),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: ts(15, c: inkFor(context, 2)),
      ),
    ),
  );
}

/// Dashed rounded border (CSS `border: 2px dashed`).
class DashedRRect extends CustomPainter {
  DashedRRect(
    this.br,
    this.color,
    this.width, {
    this.dash = 6,
    this.gap = 5,
    this.fill,
  });
  final BorderRadius br;
  final Color color;
  final double width, dash, gap;
  final Color? fill;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect rr = br.toRRect(Offset.zero & size).deflate(width / 2);
    if (fill != null) canvas.drawRRect(rr, Paint()..color = fill!);
    final Path path = Path()..addRRect(rr);
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;
    for (final ui.PathMetric m in path.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(DashedRRect old) =>
      old.color != color || old.br != br || old.fill != fill;
}

/// `.dash` add button (dashed, 56 high).
class DashBtn extends StatelessWidget {
  const DashBtn({
    super.key,
    required this.child,
    this.onTap,
    this.color,
    this.align = MainAxisAlignment.center,
    this.padding = EdgeInsets.zero,
  });
  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  final MainAxisAlignment align;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Tap(
    onTap: onTap,
    radius: 18,
    child: CustomPaint(
      painter: DashedRRect(
        BorderRadius.circular(18),
        color ?? navyA(.22),
        2,
        fill: whiteA(.35),
      ),
      child: Container(
        height: 56,
        padding: padding,
        child: Row(
          mainAxisAlignment: align,
          children: <Widget>[Flexible(child: child)],
        ),
      ),
    ),
  );
}

/// `.del` trash button.
class DelBtn extends StatelessWidget {
  const DelBtn({super.key, this.onTap, this.size = 44});
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Tap(
      onTap: onTap,
      radius: 14,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: mix(p.neg, .08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Ic('trash', size: IcSize.s, color: p.neg),
      ),
    );
  }
}

/// `.stepper` (−  qty  +).
class Stepper2 extends StatelessWidget {
  const Stepper2({super.key, required this.label, this.onDec, this.onInc});
  final String label;
  final VoidCallback? onDec, onInc;

  @override
  Widget build(BuildContext context) {
    Widget b(String ic, VoidCallback? f) => GestureDetector(
      onTap: f,
      child: Container(
        width: 40,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(11),
          boxShadow: <BoxShadow>[css(0, 1, 3, 0, navyA(.14))],
        ),
        child: Ic(ic, size: IcSize.s, color: Tc.of(context).ink),
      ),
    );
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: navyA(.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          b('minus', onDec),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 74),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: ts(15, w: w800, c: Tc.of(context).ink),
            ),
          ),
          b('plus', onInc),
        ],
      ),
    );
  }
}

/// `.hidrow` "N hidden · Unhide".
class HidRow extends StatelessWidget {
  const HidRow(
    this.text, {
    super.key,
    this.onTap,
    this.inGrid = false,
    this.glass = false,
  });
  final String text;
  final VoidCallback? onTap;
  final bool inGrid;
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final Widget row = Container(
      constraints: const BoxConstraints(minHeight: 48),
      decoration: inGrid || glass
          ? null
          : BoxDecoration(
              border: Border(top: BorderSide(color: navyA(.07))),
            ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Ic('eye', size: IcSize.s, color: p.navy),
          const SizedBox(width: 8),
          Text(
            text,
            style: ts(14, w: w700, c: p.navy),
          ),
        ],
      ),
    );
    return Tap(
      onTap: onTap,
      radius: 18,
      child: inGrid
          ? CustomPaint(
              painter: DashedRRect(BorderRadius.circular(18), navyA(.18), 2),
              child: row,
            )
          : (glass
                ? Glass(radius: 18, border: const Border(), child: row)
                : row),
    );
  }
}

/// `.pinmini` / `.pinb` pin badge.
class PinBadge extends StatelessWidget {
  const PinBadge({super.key, this.mini = true});
  final bool mini;

  @override
  Widget build(BuildContext context) {
    final double d = mini ? 20 : 24;
    return Container(
      width: d,
      height: d,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Tc.of(context).acc,
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          mini
              ? css(0, 3, 8, -3, Colors.black.withValues(alpha: .4))
              : css(0, 4, 10, -4, Colors.black.withValues(alpha: .4)),
        ],
      ),
      child: Ic('pin', px: mini ? 12 : 15, stroke: 2.2, color: Colors.white),
    );
  }
}

/// `.live` dot.
class LiveDot extends StatelessWidget {
  const LiveDot({super.key});

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: p.acc2,
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(color: mix(p.pos, .18), spreadRadius: 3),
        ],
      ),
    );
  }
}

/// `.brand`: Tally (ink) + Connect (accent).
class Brand extends StatelessWidget {
  const Brand({super.key, this.size = 22, this.align = TextAlign.center});
  final double size;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text: 'Tally',
            style: TextStyle(color: p.ink),
          ),
          TextSpan(
            text: 'Connect',
            style: TextStyle(color: p.acc),
          ),
        ],
      ),
      textAlign: align,
      style: ts(size, w: w800, ls: -.02 * size),
    );
  }
}

/// `.lmark` gradient logo tile.
class LMark extends StatelessWidget {
  const LMark({
    super.key,
    this.size = 78,
    this.radius = 26,
    this.icon = IcSize.xl,
  });
  final double size, radius;
  final IcSize icon;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final BorderRadius br = BorderRadius.circular(radius);
    return CustomPaint(
      painter: OuterShadow(br, <BoxShadow>[
        css(0, 18, 30, -12, mix(p.acc3, .7)),
      ]),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: br,
          gradient: LinearGradient(
            begin: const Alignment(-.5, -1),
            end: const Alignment(.5, 1),
            colors: <Color>[p.acc2, p.acc3],
          ),
        ),
        foregroundDecoration: insetTop(br, whiteA(.35)),
        child: Ic('rupeeC', size: icon, color: Colors.white),
      ),
    );
  }
}

/// `.plus` gradient tile (hero, acth).
class PlusTile extends StatelessWidget {
  const PlusTile({
    super.key,
    this.icon = 'plus',
    this.size = 54,
    this.radius = 18,
    this.icSize = IcSize.l,
  });
  final String icon;
  final double size, radius;
  final IcSize icSize;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final BorderRadius br = BorderRadius.circular(radius);
    return CustomPaint(
      painter: OuterShadow(br, <BoxShadow>[
        css(0, 10, 18, -8, mix(p.acc3, .6)),
      ]),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: br,
          border: Border.all(color: whiteA(.65)),
          gradient: LinearGradient(
            begin: const Alignment(-.35, -1),
            end: const Alignment(.35, 1),
            colors: <Color>[p.acc2, p.acc3],
          ),
        ),
        foregroundDecoration: insetTop(br, whiteA(.45)),
        child: Ic(icon, size: icSize, color: Colors.white),
      ),
    );
  }
}

/// `.hero` light accent surface (lines 128, 451–459).
class HeroBox extends StatelessWidget {
  const HeroBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 26,
  });
  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Glass(
      radius: radius,
      padding: padding,
      gradient: LinearGradient(
        begin: const Alignment(-.65, -1),
        end: const Alignment(.65, 1),
        colors: <Color>[
          mixWith(p.acc, .2, whiteA(.6)),
          mixWith(p.acc2, .11, whiteA(.38)),
        ],
      ),
      border: Border.all(color: whiteA(.82)),
      sheenGradient: LinearGradient(
        begin: const Alignment(-.35, -1),
        end: const Alignment(.35, 1),
        colors: <Color>[whiteA(.6), whiteA(0)],
        stops: const <double>[0, .42],
      ),
      shadows: <BoxShadow>[css(0, 20, 38, -20, mix(p.acc3, .42))],
      child: child,
    );
  }
}

/// Haptic tick (`navigator.vibrate`).
void buzz() => HapticFeedback.selectionClick();

/// With a mouse / trackpad, resting on [child] for a moment runs [onDwell]
/// (e.g. opens the tab or selects the filter under the pointer). Touch
/// screens have no hover, so on phones only taps act.
class HoverDwell extends StatefulWidget {
  const HoverDwell({
    super.key,
    required this.child,
    required this.onDwell,
    this.enabled = true,
    this.delay = const Duration(milliseconds: 650),
  });
  final Widget child;
  final VoidCallback onDwell;
  final bool enabled;
  final Duration delay;

  @override
  State<HoverDwell> createState() => _HoverDwellState();
}

class _HoverDwellState extends State<HoverDwell> {
  Timer? _t;

  void _cancel() {
    _t?.cancel();
    _t = null;
  }

  @override
  void didUpdateWidget(HoverDwell old) {
    super.didUpdateWidget(old);
    if (!widget.enabled) _cancel();
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (PointerEnterEvent e) {
      if (!widget.enabled || e.kind == PointerDeviceKind.touch) return;
      _cancel();
      _t = Timer(widget.delay, () {
        if (mounted && widget.enabled) widget.onDwell();
      });
    },
    onExit: (_) => _cancel(),
    child: widget.child,
  );
}
