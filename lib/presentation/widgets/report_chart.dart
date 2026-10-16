// Charts: Bar / Pie / Line views of the same rows a report lists, drawn with
// the theme colours. [TcChart] is the shared, interactive chart (tap a bar,
// point, slice or legend row to read its value); [ReportChart] is the
// Reports-screen card around it. Real report data only — nothing estimated.
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

/// Series colours: the theme accent and navy first, then distinct hues that
/// read well on the light glass and on dark themes — the same order in every
/// chart, so a colour means the same slice / bar position everywhere.
List<Color> chartColors(TcPalette p) => <Color>[
  p.acc,
  p.navy2,
  const Color(0xFF14B8A6), // teal
  const Color(0xFFF59E0B), // amber
  const Color(0xFF8B5CF6), // violet
  const Color(0xFF0EA5E9), // sky
  p.pos,
  const Color(0xFFEC4899), // pink
];

/// Pie slices: the largest [keep] rows, the rest summed as "Others".
List<ChartPoint> pieSlices(List<ChartPoint> pts, {int keep = 6}) {
  final List<ChartPoint> pos = pts.where((ChartPoint x) => x.value > 0).toList()
    ..sort((ChartPoint a, ChartPoint b) => b.value.compareTo(a.value));
  if (pos.length <= keep + 1) return pos;
  final num rest = pos
      .skip(keep)
      .fold<num>(0, (num s, ChartPoint x) => s + x.value);
  return <ChartPoint>[
    ...pos.take(keep),
    ChartPoint('Others (${pos.length - keep})', rest),
  ];
}

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
  Widget build(BuildContext context) => Glass(
    padding: const EdgeInsets.all(18),
    child: TcChart(
      points: data.points,
      type: type,
      onType: onType,
      total: data.total,
    ),
  );
}

/// The interactive chart with its type switch. [types] limits the choices
/// (e.g. trends: line / bar / pie; shares: bar / pie).
class TcChart extends StatefulWidget {
  const TcChart({
    super.key,
    required this.points,
    required this.type,
    required this.onType,
    this.total = '',
    this.types = ReportChart.kTypes,
    this.height = 210,
    this.hBarsUpTo = 8,
  });
  final List<ChartPoint> points;
  final String type;
  final ValueChanged<String> onType;

  /// Shown inside the donut when the slices add up to nothing.
  final String total;
  final List<(String, String)> types;
  final double height;

  /// Bar view: horizontal labelled bars up to this many rows, else columns.
  final int hBarsUpTo;

  @override
  State<TcChart> createState() => _TcChartState();
}

class _TcChartState extends State<TcChart> {
  int? _sel;

  @override
  void didUpdateWidget(TcChart old) {
    super.didUpdateWidget(old);
    if (old.type != widget.type || old.points != widget.points) _sel = null;
  }

  void _pick(int? i) => setState(() => _sel = i == _sel ? null : i);

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final List<ChartPoint> pts = widget.points;
    final String type =
        widget.types.any(((String, String) e) => e.$1 == widget.type)
        ? widget.type
        : widget.types.first.$1;
    final List<ChartPoint> shown = type == 'pie' ? pieSlices(pts) : pts;
    final num sum = shown.fold<num>(
      0,
      (num s, ChartPoint x) => s + math.max(0, x.value),
    );
    final int? sel = _sel != null && _sel! < shown.length ? _sel : null;
    // The colour a point is drawn in (many bars share the accent).
    Color colorOf(int i) =>
        type == 'pie' || shown.length <= 12 ? chartColors(p)[i % 8] : p.acc;

    Widget body;
    switch (type) {
      case 'pie':
        body = _Pie(
          points: shown,
          total: widget.total,
          sel: sel,
          onPick: _pick,
        );
      case 'line':
        body = _Plot(
          points: pts,
          kind: 'line',
          height: widget.height,
          sel: sel,
          onPick: _pick,
        );
      default:
        body = pts.length <= widget.hBarsUpTo
            ? _HBars(points: pts, sel: sel, onPick: _pick)
            : _Plot(
                points: pts,
                kind: 'bar',
                height: widget.height,
                sel: sel,
                onPick: _pick,
              );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.types.length > 1)
          Seg(
            items: widget.types.map(((String, String) e) => e.$2).toList(),
            selected: widget.types.indexWhere(
              ((String, String) e) => e.$1 == type,
            ),
            onPick: (int i) => widget.onType(widget.types[i].$1),
          ),
        // What the finger is on (or how to read the chart).
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Container(
            key: ValueKey<int?>(sel),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: sel == null
                  ? navyA(.04)
                  : mix(colorOf(sel), .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: sel == null
                ? Text(
                    'Tap a ${type == 'pie' ? 'slice' : (type == 'line' ? 'point' : 'bar')} to see its value',
                    key: const ValueKey<String>('chartHint'),
                    style: ts(12.5, w: w600, c: p.ink3),
                  )
                : Row(
                    key: const ValueKey<String>('chartReadout'),
                    children: <Widget>[
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: colorOf(sel),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          shown[sel].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ts(13.5, w: w700, c: p.ink),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        inr(shown[sel].value),
                        style: amtStyle(context, size: 14),
                      ),
                      if (sum > 0) ...<Widget>[
                        const SizedBox(width: 6),
                        Text(
                          '${(math.max(0, shown[sel].value) / sum * 100).toStringAsFixed(1)}%',
                          style: ts(12.5, w: w700, c: p.ink3, tab: true),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
        KeyedSubtree(key: ValueKey<String>(type), child: body),
      ],
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

/// Horizontal bars with label + value (few, long-named rows); tap a row.
class _HBars extends StatelessWidget {
  const _HBars({required this.points, required this.sel, required this.onPick});
  final List<ChartPoint> points;
  final int? sel;
  final ValueChanged<int?> onPick;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final List<Color> cols = chartColors(p);
    final num mx = points.fold<num>(
      0,
      (num m, ChartPoint x) => math.max(m, x.value),
    );
    return _Animated(
      builder: (double t) => Column(
        children: <Widget>[
          for (int i = 0; i < points.length; i++)
            GestureDetector(
              key: ValueKey<String>('chartBar-$i'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onPick(i),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: sel == null || sel == i ? 1 : .45,
                child: Padding(
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
                          widthFactor: mx <= 0
                              ? 0
                              : (math.max(0, points[i].value) / mx * t)
                                    .clamp(0, 1)
                                    .toDouble(),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(5),
                              gradient: LinearGradient(
                                colors: <Color>[
                                  mix(cols[i % 8], .75),
                                  cols[i % 8],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
  maxLines: 1,
)..layout();

/// Where the plot sits in [size] and where point [i] is — shared by the
/// painter and the tap handler so a tap hits exactly what is drawn.
class _Geom {
  _Geom(Size size, this.n, num maxV, this.line) {
    final TextStyle ls = _axisStyle;
    labelW = _tp(compactInr(maxV), ls).width + 10;
    // Room for the top tick label (never clipped) and the x labels.
    rect = Rect.fromLTRB(labelW, 10, size.width - 4, size.height - 24);
    slot = n == 0 ? rect.width : rect.width / n;
  }
  static final TextStyle _axisStyle = ts(
    10.5,
    w: w600,
    c: const Color(0xFF8A93A6),
  );
  final int n;
  final bool line;
  late final double labelW, slot;
  late final Rect rect;

  double xOf(int i) {
    if (!line) return rect.left + slot * i + slot / 2;
    return n == 1
        ? rect.center.dx
        : rect.left + 8 + (rect.width - 16) * i / (n - 1);
  }

  /// The point nearest to a tap at [x].
  int indexAt(double x) {
    if (n == 0) return 0;
    if (!line) return ((x - rect.left) / slot).floor().clamp(0, n - 1);
    if (n == 1) return 0;
    return ((x - rect.left - 8) / (rect.width - 16) * (n - 1)).round().clamp(
      0,
      n - 1,
    );
  }
}

/// Columns or a line over a y grid with ₹ labels; tap or drag to read.
class _Plot extends StatelessWidget {
  const _Plot({
    required this.points,
    required this.kind,
    required this.height,
    required this.sel,
    required this.onPick,
  });
  final List<ChartPoint> points;
  final String kind;
  final double height;
  final int? sel;
  final ValueChanged<int?> onPick;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final num mx = points.fold<num>(
      0,
      (num m, ChartPoint x) => math.max(m, x.value),
    );
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final _Geom g = _Geom(
            Size(box.maxWidth, height),
            points.length,
            mx <= 0 ? 1 : mx,
            kind == 'line',
          );
          return GestureDetector(
            key: ValueKey<String>('chartPlot-$kind'),
            behavior: HitTestBehavior.opaque,
            onTapDown: (TapDownDetails d) =>
                onPick(g.indexAt(d.localPosition.dx)),
            onHorizontalDragUpdate: (DragUpdateDetails d) {
              final int i = g.indexAt(d.localPosition.dx);
              if (i != sel) onPick(i);
            },
            child: _Animated(
              builder: (double t) => CustomPaint(
                size: Size(box.maxWidth, height),
                painter: _PlotPainter(
                  points,
                  p,
                  t,
                  g,
                  mx <= 0 ? 1 : mx,
                  kind,
                  sel,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PlotPainter extends CustomPainter {
  _PlotPainter(this.pts, this.p, this.t, this.g, this.mx, this.kind, this.sel);
  final List<ChartPoint> pts;
  final TcPalette p;
  final double t;
  final _Geom g;
  final num mx;
  final String kind;
  final int? sel;

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.isEmpty) return;
    final Rect r = g.rect;
    final TextStyle ls = ts(10.5, w: w600, c: p.ink3);
    // y grid + labels
    const int ticks = 4;
    final Paint grid = Paint()
      ..color = navyA(.08)
      ..strokeWidth = 1;
    for (int i = 0; i <= ticks; i++) {
      final double y = r.bottom - r.height * i / ticks;
      canvas.drawLine(Offset(r.left, y), Offset(r.right, y), grid);
      final TextPainter tp = _tp(compactInr(mx * i / ticks), ls);
      tp.paint(canvas, Offset(r.left - tp.width - 6, y - tp.height / 2));
    }
    double yOf(int i) =>
        r.bottom - r.height * (math.max(0, pts[i].value) / mx) * t;
    final List<Color> cols = chartColors(p);
    final int n = pts.length;

    if (kind == 'bar') {
      final double bw = math.max(1.5, math.min(g.slot * .64, 34));
      for (int i = 0; i < n; i++) {
        final double top = yOf(i);
        final Rect b = Rect.fromLTRB(
          g.xOf(i) - bw / 2,
          top,
          g.xOf(i) + bw / 2,
          r.bottom,
        );
        if (b.height <= 0) continue;
        final Color c = n <= 12 ? cols[i % 8] : p.acc;
        final bool dim = sel != null && sel != i;
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            b,
            topLeft: Radius.circular(math.min(5, bw / 2)),
            topRight: Radius.circular(math.min(5, bw / 2)),
          ),
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[c, mix(c, dim ? .25 : .6)],
            ).createShader(b),
        );
      }
    } else {
      final Path line = Path()..moveTo(g.xOf(0), yOf(0));
      for (int i = 1; i < n; i++) {
        final double cx = (g.xOf(i - 1) + g.xOf(i)) / 2;
        line.cubicTo(cx, yOf(i - 1), cx, yOf(i), g.xOf(i), yOf(i));
      }
      final Path area = Path.from(line)
        ..lineTo(g.xOf(n - 1), r.bottom)
        ..lineTo(g.xOf(0), r.bottom)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[mix(p.acc, .28), mix(p.acc, 0)],
          ).createShader(r),
      );
      canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..shader = LinearGradient(
            colors: <Color>[p.navy2, p.acc],
          ).createShader(r),
      );
      // Dots only while they stay apart.
      if (n <= 31) {
        for (int i = 0; i < n; i++) {
          final Offset o = Offset(g.xOf(i), yOf(i));
          canvas.drawCircle(o, 3.6, Paint()..color = Colors.white);
          canvas.drawCircle(
            o,
            3.6,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = p.acc,
          );
        }
      }
    }

    // The selected point: a guide line and a ring.
    final int? s = sel;
    if (s != null && s < n) {
      final double x = g.xOf(s);
      canvas.drawLine(
        Offset(x, r.top),
        Offset(x, r.bottom),
        Paint()
          ..color = navyA(.25)
          ..strokeWidth = 1,
      );
      if (kind == 'line') {
        final Offset o = Offset(x, yOf(s));
        canvas.drawCircle(o, 7, Paint()..color = mix(p.acc, .25));
        canvas.drawCircle(o, 4.5, Paint()..color = p.acc);
      }
    }

    // x labels: first, last, and the middle only where it does not collide.
    final List<int> order = <int>[0, if (n > 1) n - 1, if (n > 2) n ~/ 2];
    final List<Rect> placed = <Rect>[];
    for (final int i in order) {
      final String txt = pts[i].label.length > 12
          ? '${pts[i].label.substring(0, 11)}…'
          : pts[i].label;
      final TextPainter tp = _tp(txt, ls);
      final double x = (g.xOf(i) - tp.width / 2)
          .clamp(0, size.width - tp.width)
          .toDouble();
      final Rect box = Rect.fromLTWH(
        x - 4,
        r.bottom + 6,
        tp.width + 8,
        tp.height,
      );
      if (placed.any((Rect o) => o.overlaps(box))) continue;
      placed.add(box);
      tp.paint(canvas, Offset(x, r.bottom + 6));
    }
  }

  @override
  bool shouldRepaint(_PlotPainter o) =>
      o.t != t ||
      o.pts != pts ||
      o.p != p ||
      o.sel != sel ||
      o.kind != kind ||
      o.g.rect != g.rect;
}

/// Donut with the total (or the tapped slice) in the middle and a legend.
class _Pie extends StatelessWidget {
  const _Pie({
    required this.points,
    required this.total,
    required this.sel,
    required this.onPick,
  });
  final List<ChartPoint> points;
  final String total;
  final int? sel;
  final ValueChanged<int?> onPick;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final List<Color> cols = chartColors(p);
    final num sum = points.fold<num>(0, (num s, ChartPoint x) => s + x.value);
    const double d = 190;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: SizedBox(
            width: d,
            height: d,
            child: GestureDetector(
              key: const ValueKey<String>('chartPie'),
              behavior: HitTestBehavior.opaque,
              onTapDown: (TapDownDetails e) {
                final Offset v = e.localPosition - const Offset(d / 2, d / 2);
                if (v.distance < d / 2 - 34 || v.distance > d / 2 || sum <= 0) {
                  return;
                }
                // Angle from 12 o'clock, clockwise.
                double a = math.atan2(v.dy, v.dx) + math.pi / 2;
                if (a < 0) a += 2 * math.pi;
                double acc = 0;
                for (int i = 0; i < points.length; i++) {
                  acc += 2 * math.pi * points[i].value / sum;
                  if (a <= acc) return onPick(i);
                }
              },
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  _Animated(
                    builder: (double t) => CustomPaint(
                      size: const Size(d, d),
                      painter: _PiePainter(points, cols, t, sel),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          sel == null
                              ? 'Total'
                              : '${(points[sel!].value / (sum == 0 ? 1 : sum) * 100).toStringAsFixed(1)}%',
                          style: rsStyle(context),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            sel == null
                                ? (sum == 0 ? total : compactInr(sum))
                                : compactInr(points[sel!].value),
                            style: amtStyle(context, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (int i = 0; i < points.length; i++)
          GestureDetector(
            key: ValueKey<String>('chartLegend-$i'),
            behavior: HitTestBehavior.opaque,
            onTap: () => onPick(i),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: sel == null || sel == i ? 1 : .5,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: cols[i % cols.length],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 10),
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
            ),
          ),
      ],
    );
  }
}

class _PiePainter extends CustomPainter {
  _PiePainter(this.pts, this.cols, this.t, this.sel);
  final List<ChartPoint> pts;
  final List<Color> cols;
  final double t;
  final int? sel;

  @override
  void paint(Canvas canvas, Size size) {
    final num sum = pts.fold<num>(0, (num s, ChartPoint x) => s + x.value);
    if (sum <= 0) return;
    final Rect r = Offset.zero & size;
    const double stroke = 30;
    final Rect ring = r.deflate(stroke / 2 + 4);
    double a = -math.pi / 2;
    for (int i = 0; i < pts.length; i++) {
      final double sweep = 2 * math.pi * pts[i].value / sum * t;
      final bool on = sel == i;
      canvas.drawArc(
        on ? ring.inflate(3) : ring,
        a,
        math.max(0, sweep - .025),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = on ? stroke + 6 : stroke
          ..color = sel == null || on
              ? cols[i % cols.length]
              : cols[i % cols.length].withValues(alpha: .4),
      );
      a += sweep;
    }
  }

  @override
  bool shouldRepaint(_PiePainter o) =>
      o.t != t || o.pts != pts || o.cols != cols || o.sel != sel;
}
