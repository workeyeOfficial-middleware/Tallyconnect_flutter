// TAB BAR (Main.dc.html 1401–1410; selectTab 1985, tDown 2188, hb 2697):
// see-through glass bar, stretching/settling pill, hover bubble that follows
// the finger, and long-press-to-lift tab reordering.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/design/tc_icons.dart';
import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';
import '../../data/mock/mock_data.dart';
import 'common.dart';

const Color kTabInk = Color(0xFF3C4763);

class TcTabBar extends ConsumerWidget {
  const TcTabBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final double width = MediaQuery.sizeOf(context).width - 28;
    final double slot = (width - 12) / 5;
    c.setBarGeometry(slot, 14);

    final (Duration, Curve, Duration, Curve) tr = switch (c.pillT) {
      PillTr.none => (
        Duration.zero,
        Curves.linear,
        Duration.zero,
        Curves.linear,
      ),
      PillTr.stretch => (
        const Duration(milliseconds: 200),
        const Cubic(.4, 0, .2, 1),
        const Duration(milliseconds: 200),
        Curves.easeOut,
      ),
      PillTr.settle => (
        const Duration(milliseconds: 620),
        const Cubic(.26, 1.55, .44, 1),
        const Duration(milliseconds: 620),
        const Cubic(.26, 1.8, .44, 1),
      ),
      PillTr.reorder => (
        const Duration(milliseconds: 550),
        const Cubic(.28, 1.5, .45, 1),
        const Duration(milliseconds: 300),
        Curves.ease,
      ),
    };
    const BorderRadius br = BorderRadius.all(Radius.circular(34));

    final List<Widget> tabs = <Widget>[];
    for (int i = 0; i < kTabs.length; i++) {
      final int pos = c.tabOrder.indexOf(i);
      final bool dragging = c.tdrag != null && c.tdrag!.i == i;
      final bool on = c.tab == i;
      final bool hov = c.hovOn && pos == c.hovPos;
      final Color col = on ? p.acc : (hov ? p.ink : kTabInk);
      tabs.add(
        AnimatedPositioned(
          key: ValueKey<int>(i),
          duration: dragging
              ? Duration.zero
              : const Duration(milliseconds: 550),
          curve: const Cubic(.28, 1.5, .45, 1),
          left: dragging ? c.tdrag!.x : 6 + pos * slot,
          top: 6,
          width: slot,
          height: 56,
          child: Listener(
            onPointerDown: (PointerDownEvent e) => c.tDown(e, i),
            child: Tap(
              onTap: () => c.tapTab(i),
              radius: 28,
              scale: .86,
              highlight: false,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: const Cubic(.3, 1.5, .5, 1),
                transform: dragging
                    ? (Matrix4.identity()
                        ..translateByDouble(0, -8, 0, 1)
                        ..scaleByDouble(1.14, 1.14, 1, 1))
                    : Matrix4.identity(),
                transformAlignment: Alignment.center,
                decoration: dragging
                    ? BoxDecoration(
                        color: whiteA(.5),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: <BoxShadow>[css(0, 14, 24, -10, navyA(.45))],
                      )
                    : BoxDecoration(borderRadius: BorderRadius.circular(22)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    AnimatedSlide(
                      duration: const Duration(milliseconds: 420),
                      curve: const Cubic(.3, 1.6, .5, 1),
                      offset: Offset(0, hov ? -3 / 22 : 0),
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 420),
                        curve: const Cubic(.3, 1.6, .5, 1),
                        scale: hov ? 1.2 : 1,
                        child: Ic(kTabs[i].ic, color: col),
                      ),
                    ),
                    const SizedBox(height: 3),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 300),
                      style: ts(11.5, w: w700, c: col).copyWith(
                        shadows: const <Shadow>[
                          Shadow(
                            color: Color.fromRGBO(255, 255, 255, .9),
                            offset: Offset(0, 1),
                            blurRadius: 1,
                          ),
                          Shadow(
                            color: Color.fromRGBO(255, 255, 255, .7),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Text(kTabs[i].t),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    // Lifted tab paints on top.
    if (c.tdrag != null) {
      final int di = c.tdrag!.i;
      final Widget d = tabs.removeAt(di);
      tabs.add(d);
    }

    return Positioned(
      left: 14,
      right: 14,
      bottom: barBottom(context),
      height: 68,
      child: Rise(
        curve: const Cubic(.2, .8, .2, 1),
        child: MouseRegion(
          onHover: (PointerHoverEvent e) => c.hbMove(e, e.localPosition.dx),
          onExit: (_) => c.hbLeave(),
          child: Listener(
            onPointerDown: (PointerDownEvent e) =>
                c.hbDown(e, e.localPosition.dx),
            onPointerMove: (PointerMoveEvent e) =>
                c.hbMove(e, e.localPosition.dx),
            onPointerUp: (PointerUpEvent e) => c.hbUp(e, e.localPosition.dx),
            child: Glass(
              borderRadius: br,
              blur: true,
              filter: backdrop(6, 2.1, 1.06),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[whiteA(.18), whiteA(.04)],
              ),
              border: Border.all(color: whiteA(.58)),
              sheenGradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[whiteA(.4), whiteA(0)],
                stops: const <double>[0, .42],
              ),
              shadows: <BoxShadow>[css(0, 16, 30, -18, navyA(.35))],
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  // ---- pill
                  AnimatedPositioned(
                    duration: tr.$1,
                    curve: tr.$2,
                    left: 6 + c.pillPos * slot,
                    width: c.pillSpan * slot,
                    top: 6,
                    height: 56,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(end: c.pillS),
                      duration: tr.$3,
                      curve: tr.$4,
                      builder: (BuildContext context, double s, Widget? ch) =>
                          Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.diagonal3Values(1, s, 1),
                            child: ch,
                          ),
                      child: const LiquidPill(),
                    ),
                  ),
                  // ---- hover bubble
                  AnimatedPositioned(
                    duration: c.hovOn
                        ? const Duration(milliseconds: 480)
                        : Duration.zero,
                    curve: const Cubic(.3, 1.45, .45, 1),
                    left: 6 + c.hovPos * slot + (slot - 50) / 2,
                    top: 0,
                    width: 50,
                    height: 50,
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 220),
                        opacity: c.hovOn ? 1 : 0,
                        child: AnimatedScale(
                          duration: Duration(milliseconds: c.hovOn ? 400 : 300),
                          curve: c.hovOn
                              ? const Cubic(.3, 1.6, .5, 1)
                              : Curves.ease,
                          scale: c.hovOn ? 1 : .55,
                          child: _Bubble(dwell: c.dwell),
                        ),
                      ),
                    ),
                  ),
                  ...tabs,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.pill`: liquid glass lens with an inner accent glow and gloss strip.
/// Also used as the active marker of [PillFilter].
class LiquidPill extends StatelessWidget {
  const LiquidPill({super.key});

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    const BorderRadius br = BorderRadius.all(Radius.circular(28));
    return CustomPaint(
      painter: OuterShadow(br, <BoxShadow>[
        BoxShadow(color: mix(p.acc, .14), spreadRadius: .5),
        css(0, 8, 18, -8, navyA(.3)),
      ]),
      child: ClipRRect(
        borderRadius: br,
        child: BackdropFilter(
          filter: backdrop(10, 2.1),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: br,
              border: Border.all(color: whiteA(.95)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[whiteA(.46), whiteA(.12), whiteA(.22)],
                stops: const <double>[0, .6, 1],
              ),
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: br,
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: <Color>[mix(p.acc, .16), mix(p.acc, 0)],
                stops: const <double>[0, .3],
              ),
            ),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) => Stack(
                children: <Widget>[
                  Positioned(
                    left: box.maxWidth * .14,
                    right: box.maxWidth * .14,
                    top: 3,
                    height: box.maxHeight * .4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[whiteA(.9), whiteA(0)],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.hbub` hover bubble, with the `spinR` dwell ring.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.dwell});
  final bool dwell;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned.fill(
          child: CustomPaint(
            painter: OuterShadow(BorderRadius.circular(25), <BoxShadow>[
              css(0, 10, 18, -8, mix(p.navy, .4)),
            ]),
            child: ClipOval(
              child: BackdropFilter(
                filter: backdrop(1.5, 2.4, 1.12),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: whiteA(.75)),
                    gradient: RadialGradient(
                      center: const Alignment(-.36, -.48),
                      radius: .75,
                      colors: <Color>[
                        whiteA(.75),
                        whiteA(.14),
                        whiteA(.04),
                        whiteA(.2),
                      ],
                      stops: const <double>[0, .42, .66, 1],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (dwell)
          Positioned.fill(
            left: -3,
            top: -3,
            right: -3,
            bottom: -3,
            child: Enter(
              ms: 600,
              curve: Curves.linear,
              builder: (double t, Widget ch) => Opacity(
                opacity: .2 + .8 * t,
                child: Transform.rotate(
                  angle: t * 300 * 3.14159 / 180,
                  child: ch,
                ),
              ),
              child: CustomPaint(painter: _Ring(p.acc)),
            ),
          ),
      ],
    );
  }
}

class _Ring extends CustomPainter {
  _Ring(this.c);
  final Color c;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect r = (Offset.zero & size).deflate(1);
    canvas.drawArc(
      r,
      -2.36,
      1.57,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = mix(c, .7),
    );
    canvas.drawArc(
      r,
      -.79,
      1.57,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = mix(c, .4),
    );
  }

  @override
  bool shouldRepaint(_Ring old) => old.c != c;
}

/// Filter bar in the tab bar's liquid-glass style: a glass track whose
/// selected option sits on the same [LiquidPill] lens as the active tab,
/// with the same press-scale. Options share the width equally when every
/// label fits; otherwise the track scrolls sideways (no wrapping, no
/// clipping) and keeps the selected option in view.
class PillFilter extends StatefulWidget {
  const PillFilter({
    super.key,
    required this.items,
    required this.selected,
    required this.onPick,
    this.margin = const EdgeInsets.only(top: 4, bottom: 14),
  });

  /// (key, label)
  final List<(String, String)> items;
  final String selected;
  final ValueChanged<String> onPick;
  final EdgeInsets margin;

  @override
  State<PillFilter> createState() => _PillFilterState();
}

class _PillFilterState extends State<PillFilter> {
  final ScrollController _sc = ScrollController();
  List<double> _widths = const <double>[];
  bool _scrolls = false;

  static const double _h = 52, _pad = 5, _gap = 4;

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  /// Centres the selected option inside the track (scroll mode only).
  void _reveal() {
    if (!_scrolls || !_sc.hasClients) return;
    final int i = widget.items.indexWhere(
      ((String, String) e) => e.$1 == widget.selected,
    );
    if (i < 0) return;
    double x = 0;
    for (int k = 0; k < i; k++) {
      x += _widths[k] + _gap;
    }
    final ScrollPosition ps = _sc.position;
    final double target = (x - (ps.viewportDimension - _widths[i]) / 2).clamp(
      ps.minScrollExtent,
      ps.maxScrollExtent,
    );
    _sc.animateTo(
      target,
      duration: const Duration(milliseconds: 380),
      curve: const Cubic(.3, 1.2, .5, 1),
    );
  }

  @override
  void didUpdateWidget(PillFilter old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final TextScaler sc = MediaQuery.textScalerOf(context);
    TextStyle style(bool on) =>
        ts(14, w: on ? w800 : w700, c: on ? p.acc : kTabInk);
    return Padding(
      padding: widget.margin,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final double inner = box.maxWidth - _pad * 2;
          _widths = <double>[
            for (final (String, String) e in widget.items)
              (TextPainter(
                    text: TextSpan(text: e.$2, style: style(true)),
                    textDirection: TextDirection.ltr,
                    textScaler: sc,
                    maxLines: 1,
                  )..layout()).width +
                  30,
          ];
          final int n = widget.items.length;
          final double equal = n == 0 ? inner : (inner - _gap * (n - 1)) / n;
          _scrolls = _widths.any((double w) => w > equal);
          Widget option(int i) {
            final (String, String) e = widget.items[i];
            final bool on = e.$1 == widget.selected;
            return Tap(
              onTap: () => widget.onPick(e.$1),
              radius: 22,
              scale: .9,
              highlight: false,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 260),
                    opacity: on ? 1 : 0,
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 520),
                      curve: const Cubic(.26, 1.55, .44, 1),
                      scale: on ? 1 : .82,
                      child: const LiquidPill(),
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 260),
                        style: style(on),
                        child: Text(
                          e.$2,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.fade,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          final Widget row = _scrolls
              ? SingleChildScrollView(
                  controller: _sc,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: <Widget>[
                      for (int i = 0; i < n; i++) ...<Widget>[
                        if (i > 0) const SizedBox(width: _gap),
                        SizedBox(width: _widths[i], child: option(i)),
                      ],
                    ],
                  ),
                )
              : Row(
                  children: <Widget>[
                    for (int i = 0; i < n; i++) ...<Widget>[
                      if (i > 0) const SizedBox(width: _gap),
                      Expanded(child: option(i)),
                    ],
                  ],
                );
          if (_scrolls) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_sc.hasClients && _sc.offset == 0) _reveal();
            });
          }
          return Glass(
            radius: _h / 2,
            height: _h,
            blur: true,
            padding: const EdgeInsets.all(_pad),
            child: row,
          );
        },
      ),
    );
  }
}
