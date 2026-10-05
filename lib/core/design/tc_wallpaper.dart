// `.wall` (lines 489–493): the `--wall` background plus three `.orb`s
// (blur 36px, opacity .7, `drift` 16s alternate, delays 0 / −6s / −11s).
// With a photo wallpaper the orbs hide and a white veil sits on top
// (`.photo .wall::after`, lines 462–466).
library;

import 'dart:io';

import 'package:flutter/widgets.dart';

import 'tc_palette.dart';
import 'tc_wall_spec.dart';

/// [opacity] (0.2–1) fades the wallpaper towards the plain base colour;
/// [shade] (−1 lighter … +1 darker) veils it with white or black. Both are
/// independent of the glass / card level.
class TcWallpaper extends StatefulWidget {
  const TcWallpaper({super.key, this.opacity = 1, this.shade = 0});
  final double opacity, shade;

  @override
  State<TcWallpaper> createState() => _TcWallpaperState();
}

class _TcWallpaperState extends State<TcWallpaper>
    with SingleTickerProviderStateMixin {
  // One 32 s loop = one full `alternate` cycle of the 16 s drift.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 32),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final double op = widget.opacity.clamp(.2, 1);
    final double sh = widget.shade.clamp(-1, 1);
    final Widget wall = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (p.hasPhoto)
          Image.file(
            File(p.photoPath!),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                CustomPaint(painter: WallPainter(p.wall)),
          )
        else
          RepaintBoundary(child: CustomPaint(painter: WallPainter(p.wall))),
        if (!p.hasPhoto)
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (BuildContext context, _) =>
                  CustomPaint(painter: _OrbPainter(_c.value, p.o1, p.o2, p.o3)),
            ),
          ),
        if (p.hasPhoto)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: p.photoDark
                    ? const <Color>[
                        Color.fromRGBO(255, 255, 255, .58),
                        Color.fromRGBO(255, 255, 255, .46),
                      ]
                    : const <Color>[
                        Color.fromRGBO(255, 255, 255, .34),
                        Color.fromRGBO(255, 255, 255, .2),
                      ],
              ),
            ),
          ),
      ],
    );
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const ColoredBox(color: Color(0xFFE9EDF7)),
        if (op >= .999) wall else Opacity(opacity: op, child: wall),
        // Darker: black veil up to 45 % (text stays readable on the glass);
        // lighter: white veil up to 60 %.
        if (sh > 0)
          ColoredBox(color: Color.fromRGBO(0, 0, 0, .45 * sh))
        else if (sh < 0)
          ColoredBox(color: Color.fromRGBO(255, 255, 255, .6 * -sh)),
      ],
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter(this.t, this.o1, this.o2, this.o3);
  final double t;
  final Color o1, o2, o3;

  static const Cubic _ease = Cubic(.42, 0, .58, 1);

  double _phase(double offsetSec) {
    final double s = (t * 32 + offsetSec) % 32;
    final double x = s < 16 ? s / 16 : (32 - s) / 16;
    return _ease.transform(x);
  }

  void _orb(
    Canvas canvas,
    Color c,
    double d,
    double left,
    double top,
    double phase,
  ) {
    final double k = _phase(phase);
    final double scale = 1 + .14 * k;
    final Offset center = Offset(left + d / 2 + 26 * k, top + d / 2 + 38 * k);
    canvas.drawCircle(
      center,
      d / 2 * scale,
      Paint()
        ..color = c.withValues(alpha: c.a * .7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 36),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    _orb(canvas, o1, 220, -60, -40, 0);
    _orb(canvas, o2, 200, size.width + 80 - 200, 260, 6);
    _orb(canvas, o3, 180, -50, size.height - 60 - 180, 11);
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.t != t || old.o1 != o1 || old.o2 != o2 || old.o3 != o3;
}

/// Any box painted with a palette's `--wall` (thumbnails, previews).
class WallBox extends StatelessWidget {
  const WallBox({super.key, required this.spec, this.child, this.borderRadius});
  final WallSpec spec;
  final Widget? child;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: borderRadius ?? BorderRadius.zero,
    child: CustomPaint(painter: WallPainter(spec), child: child),
  );
}
