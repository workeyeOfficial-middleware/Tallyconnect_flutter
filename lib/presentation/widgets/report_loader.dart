// The one loading state of every report: a small ledger page with columns
// rising and a ₹ coin, and a plain line ("Preparing your report…"). Used
// instead of a bare "Loading…" wherever figures are worked out.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';

class ReportLoader extends StatefulWidget {
  const ReportLoader({
    super.key,
    this.text = 'Preparing your report…',
    this.margin = const EdgeInsets.symmetric(vertical: 8),
  });
  final String text;
  final EdgeInsets margin;

  @override
  State<ReportLoader> createState() => _ReportLoaderState();
}

class _ReportLoaderState extends State<ReportLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    // Reduced motion: the figure stands still.
    final bool still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Padding(
      padding: widget.margin,
      child: Glass(
        key: const ValueKey<String>('reportLoader'),
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 20),
        child: Column(
          children: <Widget>[
            SizedBox(
              width: 120,
              height: 84,
              child: AnimatedBuilder(
                animation: _a,
                builder: (BuildContext context, _) => CustomPaint(
                  painter: _LedgerPainter(
                    t: still ? .35 : _a.value,
                    ink: p.ink3,
                    bar: p.acc,
                    bar2: p.navy2,
                    coin: p.pos,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                widget.text,
                textAlign: TextAlign.center,
                style: ts(14.5, w: w700, c: p.ink2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A ledger page (ruled lines), four columns rising one after another,
/// and a ₹ coin that bobs.
class _LedgerPainter extends CustomPainter {
  _LedgerPainter({
    required this.t,
    required this.ink,
    required this.bar,
    required this.bar2,
    required this.coin,
  });
  final double t;
  final Color ink, bar, bar2, coin;

  @override
  void paint(Canvas canvas, Size s) {
    final RRect page = RRect.fromRectAndRadius(
      Rect.fromLTWH(4, 6, s.width - 30, s.height - 8),
      const Radius.circular(8),
    );
    canvas.drawRRect(page, Paint()..color = ink.withValues(alpha: .10));
    canvas.drawRRect(
      page,
      Paint()
        ..color = ink.withValues(alpha: .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    // Ruled lines.
    final Paint rule = Paint()
      ..color = ink.withValues(alpha: .22)
      ..strokeWidth = 1;
    for (int i = 1; i <= 4; i++) {
      final double y = page.top + i * (page.height / 5);
      canvas.drawLine(
        Offset(page.left + 8, y),
        Offset(page.right - 8, y),
        rule,
      );
    }
    // Columns rising in turn.
    const int n = 4;
    final double w = (page.width - 16) / (n * 2 - 1);
    for (int i = 0; i < n; i++) {
      final double phase = (t - i * .14) % 1;
      final double h =
          (.25 + .65 * (.5 - .5 * math.cos(phase * 2 * math.pi))) *
          (page.height - 14);
      final Rect r = Rect.fromLTWH(
        page.left + 8 + i * 2 * w,
        page.bottom - 6 - h,
        w,
        h,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(3)),
        Paint()..color = (i.isEven ? bar : bar2).withValues(alpha: .85),
      );
    }
    // ₹ coin.
    final double bob = math.sin(t * 2 * math.pi) * 3;
    final Offset c = Offset(s.width - 16, 18 + bob);
    canvas.drawCircle(c, 14, Paint()..color = coin);
    final TextPainter tp = TextPainter(
      text: const TextSpan(
        text: '₹',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
  }

  @override
  bool shouldRepaint(_LedgerPainter o) =>
      o.t != t || o.ink != ink || o.bar != bar;
}
