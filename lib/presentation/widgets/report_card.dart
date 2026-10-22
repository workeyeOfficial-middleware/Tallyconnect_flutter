// The square report card of the Reports dashboard: one design for the
// financial statements, the Cash Flow Forecast and the analytics cards —
// the P&L card's look (icon, title, one-line hint). At least as tall as it
// is wide; taller only when large text needs the room, so nothing is cut.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';

class ReportCard extends StatelessWidget {
  const ReportCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String icon, title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Tap(
      onTap: onTap,
      child: Glass(
        child: _AtLeastSquare(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Ico(icon, size: IcoSize.sm, color: p.acc),
                const SizedBox(height: 12),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: rtStyle(context),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: rsStyle(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Its child at least as tall as it is wide (and so in intrinsic sizing too,
/// which the dashboard's equal-height grid rows use).
class _AtLeastSquare extends SingleChildRenderObjectWidget {
  const _AtLeastSquare({required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSquare();
}

class _RenderSquare extends RenderProxyBox {
  double _floor(double width) => width.isFinite ? width : 0;

  @override
  double computeMinIntrinsicHeight(double width) =>
      math.max(_floor(width), child?.getMinIntrinsicHeight(width) ?? 0);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      math.max(_floor(width), child?.getMaxIntrinsicHeight(width) ?? 0);

  @override
  void performLayout() {
    final double minH = math.min(
      math.max(constraints.minHeight, _floor(constraints.maxWidth)),
      constraints.maxHeight,
    );
    final BoxConstraints inner = constraints.copyWith(minHeight: minH);
    if (child == null) {
      size = inner.constrain(Size(constraints.maxWidth, minH));
      return;
    }
    child!.layout(inner, parentUsesSize: true);
    size = child!.size;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final double minH = math.min(
      math.max(constraints.minHeight, _floor(constraints.maxWidth)),
      constraints.maxHeight,
    );
    final BoxConstraints inner = constraints.copyWith(minHeight: minH);
    return child?.getDryLayout(inner) ?? inner.smallest;
  }
}
