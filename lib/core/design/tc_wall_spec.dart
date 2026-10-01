// CSS `--wall` backgrounds as data + a painter that reproduces them.
// radial-gradient(W% H% at X% Y%) → scaled unit circle; linear-gradient(Ndeg)
// → CSS gradient line; repeating-linear-gradient → TileMode.repeated;
// conic-gradient(from A at X% Y%) → sweep rotated by A−90°.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

class GStop {
  const GStop(this.color, this.at);
  final Color color;

  /// 0..1 for normal gradients, pixels for [RepeatingLinearLayer].
  final double at;
}

sealed class WallLayer {
  const WallLayer();
}

class RadialLayer extends WallLayer {
  const RadialLayer(this.rx, this.ry, this.cx, this.cy, this.stops);

  /// `radial-gradient(rx ry at cx cy, c 0%, c00 end)` — the common fade.
  RadialLayer.fade(
    this.rx,
    this.ry,
    this.cx,
    this.cy,
    Color c, [
    double end = .7,
  ]) : stops = <GStop>[GStop(c, 0), GStop(c.withValues(alpha: 0), end)];

  final double rx, ry, cx, cy;
  final List<GStop> stops;
}

class LinearLayer extends WallLayer {
  const LinearLayer(this.angle, this.stops);
  final double angle;
  final List<GStop> stops;
}

class RepeatingLinearLayer extends WallLayer {
  const RepeatingLinearLayer(this.angle, this.stops);
  final double angle;
  final List<GStop> stops;
}

class ConicLayer extends WallLayer {
  const ConicLayer(this.from, this.cx, this.cy, this.colors);
  final double from, cx, cy;
  final List<Color> colors;
}

/// Layers in CSS order: the first one is painted on top.
class WallSpec {
  const WallSpec(this.layers);
  final List<WallLayer> layers;
}

class WallPainter extends CustomPainter {
  const WallPainter(this.spec);
  final WallSpec spec;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect r = Offset.zero & size;
    canvas.save();
    canvas.clipRect(r);
    for (final WallLayer l in spec.layers.reversed) {
      switch (l) {
        case LinearLayer():
          _linear(canvas, size, l.angle, l.stops, false);
        case RepeatingLinearLayer():
          _linear(canvas, size, l.angle, l.stops, true);
        case RadialLayer():
          final Offset c = Offset(size.width * l.cx, size.height * l.cy);
          final double rx = math.max(size.width * l.rx, .001);
          final double ry = math.max(size.height * l.ry, .001);
          canvas.save();
          canvas.translate(c.dx, c.dy);
          canvas.scale(rx, ry);
          final double last = l.stops.last.at;
          final Paint p = Paint()
            ..shader = ui.Gradient.radial(
              Offset.zero,
              1,
              l.stops.map((GStop s) => s.color).toList(),
              l.stops.map((GStop s) => s.at).toList(),
            );
          // Beyond the last stop the layer is transparent, except dunes
          // whose solid core extends — draw a covering rect in local space.
          if (l.stops.last.color.a == 0) {
            canvas.drawCircle(Offset.zero, last, p);
          } else {
            canvas.drawRect(
              Rect.fromLTRB(
                -c.dx / rx,
                -c.dy / ry,
                (size.width - c.dx) / rx,
                (size.height - c.dy) / ry,
              ),
              p,
            );
          }
          canvas.restore();
        case ConicLayer():
          final Offset c = Offset(size.width * l.cx, size.height * l.cy);
          final int n = l.colors.length;
          canvas.save();
          canvas.translate(c.dx, c.dy);
          canvas.rotate((l.from - 90) * math.pi / 180);
          final double big = size.longestSide * 3;
          canvas.drawRect(
            Rect.fromCenter(center: Offset.zero, width: big, height: big),
            Paint()
              ..shader = ui.Gradient.sweep(
                Offset.zero,
                l.colors,
                List<double>.generate(n, (int i) => i / (n - 1)),
              ),
          );
          canvas.restore();
      }
    }
    canvas.restore();
  }

  void _linear(
    Canvas canvas,
    Size size,
    double angle,
    List<GStop> stops,
    bool repeat,
  ) {
    final double a = angle * math.pi / 180;
    final Offset dir = Offset(math.sin(a), -math.cos(a));
    final Offset center = size.center(Offset.zero);
    final Paint p = Paint();
    if (repeat) {
      final double period = stops.last.at;
      final Offset start = center - dir * (period / 2);
      p.shader = ui.Gradient.linear(
        start,
        start + dir * period,
        stops.map((GStop s) => s.color).toList(),
        stops.map((GStop s) => s.at / period).toList(),
        TileMode.repeated,
      );
    } else {
      final double len =
          (size.width * math.sin(a)).abs() + (size.height * math.cos(a)).abs();
      p.shader = ui.Gradient.linear(
        center - dir * (len / 2),
        center + dir * (len / 2),
        stops.map((GStop s) => s.color).toList(),
        stops.map((GStop s) => s.at).toList(),
      );
    }
    canvas.drawRect(Offset.zero & size, p);
  }

  @override
  bool shouldRepaint(WallPainter old) => !identical(old.spec, spec);
}
