// `.i` icons: the prototype's `IC` SVG paths parsed once into Flutter Paths
// and stroked with round caps/joins in a 24×24 viewBox.
library;

import 'package:flutter/widgets.dart';

import 'tc_icon_paths.dart';

/// `.i` sizes (lines 49–51): size and stroke width.
enum IcSize {
  /// `.i` 22 / 1.9
  m(22, 1.9),

  /// `.i.s` 18 / 1.9
  s(18, 1.9),

  /// `.i.xs` 15 / 2.2
  xs(15, 2.2),

  /// `.i.l` 28 / 1.8
  l(28, 1.8),

  /// `.i.xl` 34 / 1.7
  xl(34, 1.7);

  const IcSize(this.px, this.stroke);
  final double px;
  final double stroke;
}

final Map<String, Path> _cache = <String, Path>{};

Path icPath(String key) =>
    _cache.putIfAbsent(key, () => parseSvgPath(tcIconPaths[key] ?? ''));

class Ic extends StatelessWidget {
  const Ic(
    this.k, {
    super.key,
    this.size = IcSize.m,
    this.color,
    this.px,
    this.stroke,
  });

  final String k;
  final IcSize size;
  final Color? color;

  /// Explicit pixel size (overrides [size]).
  final double? px;
  final double? stroke;

  @override
  Widget build(BuildContext context) {
    final double s = px ?? size.px;
    final Color c =
        color ??
        DefaultTextStyle.of(context).style.color ??
        const Color(0xFF0E1B33);
    return SizedBox(
      width: s,
      height: s,
      child: CustomPaint(
        painter: _IcPainter(icPath(k), c, stroke ?? size.stroke),
      ),
    );
  }
}

class _IcPainter extends CustomPainter {
  _IcPainter(this.path, this.color, this.stroke);
  final Path path;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final double sc = size.width / 24;
    canvas.save();
    canvas.scale(sc);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IcPainter old) =>
      old.path != path || old.color != color || old.stroke != stroke;
}

// ---------------------------------------------------------------------------
// Minimal SVG path-data parser (M L H V C S Q T A Z, absolute + relative).

Path parseSvgPath(String d) {
  final Path p = Path();
  final List<String> tokens = RegExp(
    r'[MmLlHhVvCcSsQqTtAaZz]|-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?',
  ).allMatches(d).map((Match m) => m.group(0)!).toList();
  int i = 0;
  String cmd = 'M';
  double x = 0, y = 0, sx = 0, sy = 0;
  double? lcx, lcy; // last control point for S/T
  bool isCmd(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  double n() => double.parse(tokens[i++]);

  // Arc flags may be packed ("0 0 1" or "001"); the regex already splits
  // numbers, but flags like "01" would read as one number — handle that.
  final List<double> flagBuf = <double>[];
  double flag() {
    if (flagBuf.isNotEmpty) return flagBuf.removeAt(0);
    final String t = tokens[i++];
    if (t.length > 1 &&
        !t.contains('.') &&
        (t.startsWith('0') || t.startsWith('1'))) {
      for (int k = 1; k < t.length; k++) {
        flagBuf.add(double.parse(t[k]));
      }
      return double.parse(t[0]);
    }
    return double.parse(t);
  }

  while (i < tokens.length) {
    if (isCmd(tokens[i])) cmd = tokens[i++];
    final bool rel = cmd == cmd.toLowerCase();
    switch (cmd.toUpperCase()) {
      case 'M':
        final double nx = n() + (rel ? x : 0), ny = n() + (rel ? y : 0);
        p.moveTo(nx, ny);
        x = sx = nx;
        y = sy = ny;
        cmd = rel ? 'l' : 'L';
        lcx = lcy = null;
      case 'L':
        x = n() + (rel ? x : 0);
        y = n() + (rel ? y : 0);
        p.lineTo(x, y);
        lcx = lcy = null;
      case 'H':
        x = n() + (rel ? x : 0);
        p.lineTo(x, y);
        lcx = lcy = null;
      case 'V':
        y = n() + (rel ? y : 0);
        p.lineTo(x, y);
        lcx = lcy = null;
      case 'C':
        final double x1 = n() + (rel ? x : 0), y1 = n() + (rel ? y : 0);
        final double x2 = n() + (rel ? x : 0), y2 = n() + (rel ? y : 0);
        final double ex = n() + (rel ? x : 0), ey = n() + (rel ? y : 0);
        p.cubicTo(x1, y1, x2, y2, ex, ey);
        lcx = x2;
        lcy = y2;
        x = ex;
        y = ey;
      case 'S':
        final double x1 = lcx != null ? 2 * x - lcx : x;
        final double y1 = lcy != null ? 2 * y - lcy : y;
        final double x2 = n() + (rel ? x : 0), y2 = n() + (rel ? y : 0);
        final double ex = n() + (rel ? x : 0), ey = n() + (rel ? y : 0);
        p.cubicTo(x1, y1, x2, y2, ex, ey);
        lcx = x2;
        lcy = y2;
        x = ex;
        y = ey;
      case 'Q':
        final double x1 = n() + (rel ? x : 0), y1 = n() + (rel ? y : 0);
        final double ex = n() + (rel ? x : 0), ey = n() + (rel ? y : 0);
        p.quadraticBezierTo(x1, y1, ex, ey);
        lcx = x1;
        lcy = y1;
        x = ex;
        y = ey;
      case 'T':
        final double x1 = lcx != null ? 2 * x - lcx : x;
        final double y1 = lcy != null ? 2 * y - lcy : y;
        final double ex = n() + (rel ? x : 0), ey = n() + (rel ? y : 0);
        p.quadraticBezierTo(x1, y1, ex, ey);
        lcx = x1;
        lcy = y1;
        x = ex;
        y = ey;
      case 'A':
        final double rx = n(), ry = n(), rot = n();
        final bool large = flag() != 0;
        final bool sweep = flag() != 0;
        final double ex =
            (flagBuf.isNotEmpty ? flagBuf.removeAt(0) : n()) + (rel ? x : 0);
        final double ey = n() + (rel ? y : 0);
        if (rx == 0 || ry == 0) {
          p.lineTo(ex, ey);
        } else if ((ex - x).abs() < 1e-9 && (ey - y).abs() < 1e-9) {
          // zero-length arc: SVG draws nothing
        } else {
          p.arcToPoint(
            Offset(ex, ey),
            radius: Radius.elliptical(rx, ry),
            rotation: rot,
            largeArc: large,
            clockwise: sweep,
          );
        }
        x = ex;
        y = ey;
        lcx = lcy = null;
      case 'Z':
        p.close();
        x = sx;
        y = sy;
        lcx = lcy = null;
        // Z takes no args; stop a stray number loop.
        if (i < tokens.length && !isCmd(tokens[i])) cmd = 'L';
      default:
        i++;
    }
  }
  return p;
}
