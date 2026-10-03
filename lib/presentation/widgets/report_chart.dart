// Report chart (NEW feature — not in the prototype): Bar / Pie / Line views
// of the same rows the report list shows, drawn with the theme colours.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';
import '../../core/share/report_data.dart';
import '../../core/utils/format.dart';

/// ₹ with K / L / Cr suffixes for axis labels.
String compactInr(num v) {
  final double a = v.abs().toDouble();
  String f(double x) => x >= 100
      ? x.round().toString()
      : x.toStringAsFixed(x >= 10 ? 0 : 1).replaceAll(RegExp(r'\.0$'), '');
  if (a >= 1e7) return '₹${f(a / 1e7)}Cr';
  if (a >= 1e5) return '₹${f(a / 1e5)}L';
  if (a >= 1e3) return '₹${f(a / 1e3)}K';
  return inr(a);
}

List<Color> chartColors(TcPalette p) => <Color>[
  p.acc,
  p.navy2,
  p.acc2,
  p.navy,
  p.pos,
  p.warn,
  p.acc3,
  p.ink3,
];

class ReportChart extends StatelessWidget {
  const ReportChart({
    super.key,
    required this.data,
    required this.type,
    required this.onType,
  });
  final ReportData data;

  /// bar | pie | line
  final String type;
  final ValueChanged<String> onType;

  static const List<(String, String)> kTypes = <(String, String)>[
    ('bar', 'Bar'),
    ('pie', 'Pie'),
    ('line', 'Line'),
  ];

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final List<ChartPoint> pts = data.points;
    Widget body;
    switch (type) {
      case 'pie':
        body = _Pie(points: pts, total: data.total);
      case 'line':
        body = SizedBox(
          height: 210,
          child: _Animated(
            builder: (double t) => CustomPaint(
              painter: _LinePainter(pts, p, t),
              size: Size.infinite,
            ),
          ),
        );
      default:
        body = pts.length <= 8
            ? _HBars(points: pts)
            : SizedBox(
                height: 210,
                child: _Animated(
                  builder: (double t) => CustomPaint(
                    painter: _VBarPainter(pts, p, t),
                    size: Size.infinite,
                  ),
                ),
              );
    }
    return Glass(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Seg(
            items: kTypes.map(((String, String) e) => e.$2).toList(),
            selected: kTypes.indexWhere(((String, String) e) => e.$1 == type),
            onPick: (int i) => onType(kTypes[i].$1),
          ),
          KeyedSubtree(key: ValueKey<String>(type), child: body),
        ],
      ),
    );
  }
}

/// Grows the chart in from 0 → 1 on mount (.6 s).
class _Animated extends StatelessWidget {
  const _Animated({required this.builder});
  final Widget Function(double t) builder;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween<double>(begin: 0, end: 1),
    duration: const Duration(milliseconds: 600),
    curve: const Cubic(.2, .85, .2, 1),
    builder: (BuildContext context, double t, _) => builder(t),
  );
}

/// Horizontal bars with label + value (few, long-named rows).
class _HBars extends StatelessWidget {
  const _HBars({required this.points});
  final List<ChartPoint> points;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final num mx = points.fold<num>(
      0,
      (num m, ChartPoint x) => math.max(m, x.value),
    );
    return _Animated(
      builder: (double t) => Column(
        children: <Widget>[
          for (int i = 0; i < points.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          points[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ts(14.5, h: 1.3, c: p.ink2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        inr(points[i].value),
                        style: amtStyle(context, size: 14.5),
                      ),
                    ],
                  ),
                  Container(
                    height: 10,
                    margin: const EdgeInsets.only(top: 6),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: navyA(.08),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: FractionallySizedBox(
                      widthFactor: mx == 0
                          ? 0
                          : (points[i].value / mx * t).clamp(0, 1).toDouble(),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          gradient: LinearGradient(
                            colors: <Color>[p.acc2, p.acc3],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

TextPainter _tp(String s, TextStyle st) => TextPainter(
  text: TextSpan(text: s, style: st),
  textDirection: TextDirection.ltr,
)..layout();

/// Shared plot frame: y grid with compact ₹ labels, returns the plot rect.
Rect _frame(Canvas canvas, Size size, num mx, TcPalette p) {
  final TextStyle ls = ts(10.5, w: w600, c: p.ink3);
  const int ticks = 4;
  final double labelW = _tp(compactInr(mx), ls).width + 8;
  final Rect r = Rect.fromLTRB(labelW, 6, size.width, size.height - 22);
  final Paint grid = Paint()
    ..color = navyA(.08)
    ..strokeWidth = 1;
  for (int i = 0; i <= ticks; i++) {
    final double y = r.bottom - r.height * i / ticks;
    canvas.drawLine(Offset(r.left, y), Offset(r.right, y), grid);
    final TextPainter tp = _tp(compactInr(mx * i / ticks), ls);
    tp.paint(canvas, Offset(r.left - tp.width - 6, y - tp.height / 2));
  }
  return r;
}

/// X labels: first, middle and last only (keeps mobile charts readable).
void _xLabels(
  Canvas canvas,
  Rect r,
  List<ChartPoint> pts,
  double Function(int) xOf,
  TcPalette p,
) {
  final TextStyle ls = ts(10.5, w: w600, c: p.ink3);
  final Set<int> show = <int>{0, pts.length ~/ 2, pts.length - 1};
  for (final int i in show) {
    final String s = pts[i].label.length > 12
        ? '${pts[i].label.substring(0, 11)}…'
        : pts[i].label;
    final TextPainter tp = _tp(s, ls);
    final double x = (xOf(i) - tp.width / 2).clamp(r.left, r.right - tp.width);
    tp.paint(canvas, Offset(x, r.bottom + 6));
  }
}

class _VBarPainter extends CustomPainter {
  _VBarPainter(this.pts, this.p, this.t);
  final List<ChartPoint> pts;
  final TcPalette p;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.isEmpty) return;
    final num mx = pts.fold<num>(
      0,
      (num m, ChartPoint x) => math.max(m, x.value),
    );
    final Rect r = _frame(canvas, size, mx == 0 ? 1 : mx, p);
    final double slot = r.width / pts.length;
    final double bw = math.max(3, slot * .62);
    double xOf(int i) => r.left + slot * i + slot / 2;
    for (int i = 0; i < pts.length; i++) {
      final double h = mx == 0 ? 0 : r.height * pts[i].value / mx * t;
      final Rect b = Rect.fromLTWH(xOf(i) - bw / 2, r.bottom - h, bw, h);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          b,
          topLeft: Radius.circular(math.min(4, bw / 2)),
          topRight: Radius.circular(math.min(4, bw / 2)),
        ),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[p.acc2, p.acc3],
          ).createShader(b),
      );
    }
    _xLabels(canvas, r, pts, xOf, p);
  }

  @override
  bool shouldRepaint(_VBarPainter o) => o.t != t || o.pts != pts || o.p != p;
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.pts, this.p, this.t);
  final List<ChartPoint> pts;
  final TcPalette p;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.isEmpty) return;
    final num mx = pts.fold<num>(
      0,
      (num m, ChartPoint x) => math.max(m, x.value),
    );
    final Rect r = _frame(canvas, size, mx == 0 ? 1 : mx, p);
    final int n = pts.length;
    double xOf(int i) =>
        n == 1 ? r.center.dx : r.left + 8 + (r.width - 16) * i / (n - 1);
    double yOf(int i) =>
        r.bottom - (mx == 0 ? 0 : r.height * pts[i].value / mx * t);
    final Path line = Path()..moveTo(xOf(0), yOf(0));
    for (int i = 1; i < n; i++) {
      final double cx = (xOf(i - 1) + xOf(i)) / 2;
      line.cubicTo(cx, yOf(i - 1), cx, yOf(i), xOf(i), yOf(i));
    }
    final Path area = Path.from(line)
      ..lineTo(xOf(n - 1), r.bottom)
      ..lineTo(xOf(0), r.bottom)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[mix(p.acc, .22), mix(p.acc, 0)],
        ).createShader(r),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = p.acc,
    );
    for (int i = 0; i < n; i++) {
      final Offset o = Offset(xOf(i), yOf(i));
      canvas.drawCircle(o, 4.2, Paint()..color = Colors.white);
      canvas.drawCircle(
        o,
        4.2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = p.acc,
      );
    }
    _xLabels(canvas, r, pts, xOf, p);
  }

  @override
  bool shouldRepaint(_LinePainter o) => o.t != t || o.pts != pts || o.p != p;
}

/// Donut with the report total in the middle and a legend underneath.
class _Pie extends StatelessWidget {
  const _Pie({required this.points, required this.total});
  final List<ChartPoint> points;
  final String total;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final List<Color> cols = chartColors(p);
    final num sum = points.fold<num>(0, (num s, ChartPoint x) => s + x.value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: 190,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              _Animated(
                builder: (double t) => CustomPaint(
                  size: const Size(190, 190),
                  painter: _PiePainter(points, cols, t),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text('Total', style: rsStyle(context)),
                  Text(
                    sum == 0 ? total : compactInr(sum),
                    style: amtStyle(context, size: 18),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (int i = 0; i < points.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: <Widget>[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: cols[i % cols.length],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    points[i].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ts(14, h: 1.3, c: p.ink2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  sum == 0
                      ? '0%'
                      : '${(points[i].value / sum * 100).toStringAsFixed(1)}%',
                  style: ts(14, w: w800, c: p.ink, tab: true),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PiePainter extends CustomPainter {
  _PiePainter(this.pts, this.cols, this.t);
  final List<ChartPoint> pts;
  final List<Color> cols;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final num sum = pts.fold<num>(0, (num s, ChartPoint x) => s + x.value);
    if (sum == 0) return;
    final Rect r = Offset.zero & size;
    const double stroke = 30;
    final Rect ring = r.deflate(stroke / 2);
    double a = -math.pi / 2;
    for (int i = 0; i < pts.length; i++) {
      final double sweep = 2 * math.pi * pts[i].value / sum * t;
      canvas.drawArc(
        ring,
        a,
        math.max(0, sweep - .025),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = cols[i % cols.length],
      );
      a += sweep;
    }
  }

  @override
  bool shouldRepaint(_PiePainter o) =>
      o.t != t || o.pts != pts || o.cols != cols;
}
