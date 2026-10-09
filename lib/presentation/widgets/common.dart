// Screen scaffolding shared by every screen: `.scr`, `.scr.wt`, `.flowscr`
// + `.fbody` + `.foot`, the inF/inB entry animation, `rise`, sheets, list
// rows with long-press, and the wiggle used by armed cards.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/design/tc_icons.dart';
import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';

// ----------------------------------------------------------- device insets
// The prototype is a fixed 390×844 frame with no status bar; on devices the
// top/bottom offsets are pushed past the safe areas.

double topIn(BuildContext c) =>
    math.max(28.0, MediaQuery.paddingOf(c).top + 10);
double barBottom(BuildContext c) =>
    math.max(20.0, MediaQuery.paddingOf(c).bottom + 6);

/// Where tab-screen content stops (`.scr.wt { bottom: 100px }`).
double wtBottom(BuildContext c) => barBottom(c) + 80;

// ------------------------------------------------------------- animations

const Cubic kEaseScr = Cubic(.2, .85, .2, 1);

/// `inF` / `inB`: ±30 px slide + fade, 420 ms, played once on mount.
class EnterAnim extends StatefulWidget {
  const EnterAnim({super.key, required this.back, required this.child});
  final bool back;
  final Widget child;

  @override
  State<EnterAnim> createState() => _EnterAnimState();
}

class _EnterAnimState extends State<EnterAnim>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..forward();
  late final Animation<double> _a = CurvedAnimation(
    parent: _c,
    curve: kEaseScr,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _a,
    child: widget.child,
    builder: (BuildContext context, Widget? child) => Opacity(
      opacity: _a.value.clamp(0, 1),
      child: Transform.translate(
        offset: Offset((1 - _a.value) * (widget.back ? -30 : 30), 0),
        child: child,
      ),
    ),
  );
}

/// `rise`: y 10 → 0 + fade (.35 s by default).
class Rise extends StatefulWidget {
  const Rise({
    super.key,
    required this.child,
    this.ms = 350,
    this.curve = Curves.ease,
  });
  final Widget child;
  final int ms;
  final Curve curve;

  @override
  State<Rise> createState() => _RiseState();
}

class _RiseState extends State<Rise> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.ms),
  )..forward();
  late final Animation<double> _a = CurvedAnimation(
    parent: _c,
    curve: widget.curve,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _a,
    child: widget.child,
    builder: (BuildContext context, Widget? child) => Opacity(
      opacity: _a.value.clamp(0, 1),
      child: Transform.translate(
        offset: Offset(0, (1 - _a.value) * 10),
        child: child,
      ),
    ),
  );
}

/// Generic one-shot entrance (fade / slide-up / slide-left / pop).
class Enter extends StatefulWidget {
  const Enter({
    super.key,
    required this.child,
    required this.ms,
    this.curve = Curves.ease,
    required this.builder,
  });
  final Widget child;
  final int ms;
  final Curve curve;
  final Widget Function(double t, Widget child) builder;

  @override
  State<Enter> createState() => _EnterState();
}

class _EnterState extends State<Enter> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.ms),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (BuildContext context, Widget? child) =>
        widget.builder(widget.curve.transform(_c.value), child!),
  );
}

Widget fadeIn(Widget child, {int ms = 250}) => Enter(
  ms: ms,
  builder: (double t, Widget c) => Opacity(opacity: t.clamp(0, 1), child: c),
  child: child,
);

/// Infinite ±deg wiggle (`wig` / `wigw`, .34 s).
class Wiggle extends StatefulWidget {
  const Wiggle({
    super.key,
    required this.on,
    required this.child,
    this.deg = 1.4,
    this.phase = 0,
  });
  final bool on;
  final Widget child;
  final double deg;
  final double phase;

  @override
  State<Wiggle> createState() => _WiggleState();
}

class _WiggleState extends State<Wiggle> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    if (widget.on) _c.repeat();
  }

  @override
  void didUpdateWidget(Wiggle old) {
    super.didUpdateWidget(old);
    if (widget.on && !_c.isAnimating) _c.repeat();
    if (!widget.on && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.on) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        final double t = (_c.value + widget.phase) % 1;
        final double k = -math.cos(t * 2 * math.pi); // -1 → 1 → -1
        return Transform.rotate(
          angle: k * widget.deg * math.pi / 180,
          child: child,
        );
      },
    );
  }
}

// ---------------------------------------------------------------- screens

ScrollPhysics scrollPhysics(AppController c) => c.scrollLock
    ? const NeverScrollableScrollPhysics()
    : const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

/// `.scr` (padding 28 16 36) or `.scr.wt` on tab-bar screens (stops 100 px
/// above the bottom with an 18 px fade).
class Scr extends ConsumerStatefulWidget {
  const Scr({super.key, required this.children, this.onNearEnd});

  /// Plain widgets lay out as before; [ScrSliver]s (e.g. [SliverGlassList])
  /// build their rows lazily, only while on screen.
  final List<Widget> children;

  /// Called when the user scrolls near the end (load the next page).
  final VoidCallback? onNearEnd;

  @override
  ConsumerState<Scr> createState() => _ScrState();
}

class _ScrState extends ConsumerState<Scr> {
  final ScrollController _sc = ScrollController();
  final GlobalKey _vp = GlobalKey();
  late final AppController _ctl = ref.read(appProvider);

  @override
  void initState() {
    super.initState();
    _ctl;
  }

  @override
  void dispose() {
    final AppController c = _ctl;
    if (c.reg.screenScroll == _sc) {
      c.reg.screenScroll = null;
      c.reg.screenViewport = null;
    }
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppController c = ref.watch(appProvider);
    c.reg.screenScroll = _sc;
    c.reg.screenViewport = _vp;
    final bool wt = c.showTabs;
    // There is no Scaffold, so the keyboard must be made room for here:
    // fields near the bottom stay reachable above it.
    final double kb = MediaQuery.viewInsetsOf(context).bottom;
    Widget scroll = CustomScrollView(
      key: _vp,
      controller: _sc,
      physics: scrollPhysics(c),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: <Widget>[
        SliverPadding(
          // The scroll view runs to the bottom of the screen (under the
          // glass tab bar, like Home), so cards are never cut at a line above
          // the bar; this padding lets the last card rest fully above it.
          padding: EdgeInsets.fromLTRB(
            16,
            topIn(context),
            16,
            (wt
                    ? wtBottom(context) + 20
                    : 36 + MediaQuery.paddingOf(context).bottom) +
                kb,
          ),
          sliver: SliverMainAxisGroup(slivers: toSlivers(widget.children)),
        ),
      ],
    );
    if (widget.onNearEnd != null) {
      // Also after each build: rows that do not fill the screen, or a page
      // that arrives while the user is already at the end, load the next
      // page without waiting for another scroll.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_sc.hasClients) return;
        final ScrollPosition pos = _sc.position;
        if (pos.hasContentDimensions && pos.extentAfter < 900) {
          widget.onNearEnd?.call();
        }
      });
      scroll = NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification n) {
          if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 900) {
            widget.onNearEnd!();
          }
          return false;
        },
        child: scroll,
      );
    }
    if (c.repo.isRemote && c.loggedIn) {
      // Pull down to reload; the current data stays until fresh data arrives.
      scroll = RefreshIndicator(
        edgeOffset: topIn(context),
        color: Tc.of(context).acc,
        onRefresh: c.pullRefresh,
        child: scroll,
      );
    }
    // No bottom cut-off or fade: the wallpaper and the content continue
    // behind the translucent tab bar.
    return scroll;
  }
}

/// Reports its child's laid-out height (after the frame) when it changes.
class _MeasureHeight extends SingleChildRenderObjectWidget {
  const _MeasureHeight({required this.onHeight, required super.child});
  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureHeight(onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasureHeight r) =>
      r.onHeight = onHeight;
}

class _RenderMeasureHeight extends RenderProxyBox {
  _RenderMeasureHeight(this.onHeight);
  ValueChanged<double> onHeight;
  double? _last;

  @override
  void performLayout() {
    super.performLayout();
    final double h = size.height;
    if (h == _last) return;
    _last = h;
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(h));
  }
}

/// `mask-image` fade at the top and/or bottom edge.
Widget fadeMask(Widget child, {double top = 0, double bottom = 0}) =>
    ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (Rect r) {
        final double h = r.height <= 0 ? 1 : r.height;
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            if (top > 0) const Color(0x00000000),
            const Color(0xFF000000),
            const Color(0xFF000000),
            if (bottom > 0) const Color(0x00000000),
          ],
          stops: <double>[
            if (top > 0) 0,
            (top / h).clamp(0, 1),
            (1 - bottom / h).clamp(0, 1),
            if (bottom > 0) 1,
          ],
        ).createShader(r);
      },
      child: child,
    );

/// `.scr.flowscr`: scrolling `.fbody` + fixed `.foot`.
class FlowScr extends ConsumerStatefulWidget {
  const FlowScr({super.key, required this.children, this.foot});

  /// Plain widgets and lazily built [ScrSliver]s (see [Scr]).
  final List<Widget> children;
  final List<Widget>? foot;

  @override
  ConsumerState<FlowScr> createState() => _FlowScrState();
}

class _FlowScrState extends ConsumerState<FlowScr> {
  /// The footer's measured height (room left under the content).
  final ValueNotifier<double> _footH = ValueNotifier<double>(0);

  @override
  void dispose() {
    _footH.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppController c = ref.watch(appProvider);
    final List<Widget> children = widget.children;
    final List<Widget>? foot = widget.foot;
    // No Scaffold resizes this screen for the keyboard: the body shrinks by
    // the keyboard height so the form scrolls and the footer buttons sit
    // above the keyboard instead of under it.
    final double kb = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: Stack(
        children: <Widget>[
          // The content runs under the see-through glass footer (it blurs
          // what scrolls behind it) instead of stopping at its edge.
          Positioned.fill(
            child: CustomScrollView(
              physics: scrollPhysics(c),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: <Widget>[
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, topIn(context), 16, 24),
                  sliver: SliverMainAxisGroup(slivers: toSlivers(children)),
                ),
                // Room for the footer at the end: exactly its measured
                // height, so the last content rests fully above it.
                if (foot != null)
                  SliverToBoxAdapter(
                    child: ValueListenableBuilder<double>(
                      valueListenable: _footH,
                      builder: (BuildContext context, double h, _) =>
                          SizedBox(height: h),
                    ),
                  ),
              ],
            ),
          ),
          if (foot != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _MeasureHeight(
                onHeight: (double h) => _footH.value = h,
                // With the keyboard up the system-bar inset is already
                // covered.
                child: Foot(compact: kb > 0, children: foot),
              ),
            ),
        ],
      ),
    );
  }
}

/// Wraps plain widgets for a sliver scroll view; [ScrSliver]s pass through.
List<Widget> toSlivers(List<Widget> children) => <Widget>[
  for (final Widget w in children)
    w is ScrSliver ? w : SliverToBoxAdapter(child: w),
];

/// A child of [Scr] / [FlowScr] that is itself a sliver (built lazily).
abstract class ScrSliver extends StatelessWidget {
  const ScrSliver({super.key});
}

/// [GlassList]'s look (one glass card, 1 px dividers, rounded ends) for a
/// long list whose rows are built only while they are on screen — the
/// screen never builds thousands of rows at once.
class SliverGlassList extends ScrSliver {
  const SliverGlassList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.margin = EdgeInsets.zero,
    this.divider = true,
    this.radius = 22,
  });
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsets margin;
  final bool divider;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (itemCount == 0) return const SliverToBoxAdapter(child: SizedBox());
    final TcPalette p = Tc.of(context);
    return SliverPadding(
      padding: margin,
      sliver: DecoratedSliver(
        decoration: GlassDecoration(
          fill: p.glassFill,
          radius: radius,
          shadows: glassShadows(),
        ),
        sliver: SliverPadding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          sliver: SliverList.builder(
            itemCount: itemCount,
            itemBuilder: (BuildContext context, int i) {
              final Widget raw = itemBuilder(context, i);
              Widget w = OnSurface(child: raw);
              if (i > 0 && divider && raw is! HidRow) {
                w = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[listDivider(), w],
                );
              }
              // Same rounded clipping as [GlassList] at both ends.
              if (i == 0 || i == itemCount - 1) {
                w = ClipRRect(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(i == 0 ? radius : 0),
                    bottom: Radius.circular(i == itemCount - 1 ? radius : 0),
                  ),
                  child: w,
                );
              }
              return w;
            },
          ),
        ),
      ),
    );
  }
}

/// [GlassList] replacement for long lists: [rows] built lazily with the
/// same look, then the "N hidden · Unhide" row and the empty text.
SliverGlassList lazyList<T>({
  required List<T> rows,
  required Widget Function(BuildContext context, T row) row,
  int hidden = 0,
  VoidCallback? unhide,
  String? empty,
  EdgeInsets margin = EdgeInsets.zero,
}) {
  final bool showEmpty = rows.isEmpty && empty != null;
  return SliverGlassList(
    margin: margin,
    itemCount: rows.length + (hidden > 0 ? 1 : 0) + (showEmpty ? 1 : 0),
    itemBuilder: (BuildContext context, int i) {
      if (i < rows.length) return row(context, rows[i]);
      if (hidden > 0 && i == rows.length) {
        return HidRow('$hidden hidden · Unhide', onTap: unhide);
      }
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Text(
          empty ?? '',
          textAlign: TextAlign.center,
          style: rsStyle(context, 15),
        ),
      );
    },
  );
}

/// Last row of a paged list: loading / retry / end text.
class PageFooterRow extends StatelessWidget {
  const PageFooterRow({
    super.key,
    required this.loading,
    this.error,
    this.onRetry,
    this.text = '',
  });
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final String text;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    if (loading) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: p.acc),
          ),
        ),
      );
    }
    if (error != null) {
      return RowX(
        onTap: onRetry,
        children: <Widget>[
          Ico('sync', size: IcoSize.xs, color: p.neg, icon: IcSize.s),
          Expanded(child: RTx('Could not load more', error!)),
          Text(
            'Retry',
            style: ts(14, w: w700, c: p.acc),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: ts(15, c: p.ink3),
      ),
    );
  }
}

/// One-line amount that shrinks to fit instead of wrapping or pushing its
/// neighbours (large rupee values, long totals).
class AmtText extends StatelessWidget {
  const AmtText(
    this.text, {
    super.key,
    required this.style,
    this.align = Alignment.centerRight,
  });
  final String text;
  final TextStyle style;
  final AlignmentGeometry align;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: align,
    child: Text(text, maxLines: 1, softWrap: false, style: style),
  );
}

/// `.foot`: see-through glass bar with the action buttons.
class Foot extends StatelessWidget {
  const Foot({
    super.key,
    required this.children,
    this.inSheet = false,
    this.compact = false,
  });
  final List<Widget> children;
  final bool inSheet;

  /// Keyboard open: no system-bar padding below the buttons.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return ClipRect(
      child: BackdropFilter(
        filter: backdrop(22, 1.7),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            compact
                ? 12
                : 26 +
                      (inSheet ? 0 : MediaQuery.paddingOf(context).bottom * .6),
          ),
          decoration: BoxDecoration(
            color: p.gt.withValues(alpha: .5),
            border: Border(top: BorderSide(color: whiteA(.85))),
          ),
          child: Row(
            children: <Widget>[
              for (int i = 0; i < children.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: 12),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// `.nav` row: min-height 48, gap 10, margin-bottom 10.
class NavRow extends StatelessWidget {
  const NavRow({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.only(bottom: 10),
  });
  final List<Widget> children;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    // Narrow phones (≈320 px): tighter gaps so the buttons fit one row.
    final double gap = MediaQuery.sizeOf(context).width < 360 ? 6 : 10;
    return Padding(
      padding: margin,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: <Widget>[
            for (int i = 0; i < children.length; i++) ...<Widget>[
              if (i > 0 && children[i] is! Spacer && children[i - 1] is! Spacer)
                SizedBox(width: gap),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// Standard back pill row: `[pbtn backLabel] [grow] [...actions]`.
class BackNav extends ConsumerWidget {
  const BackNav({super.key, this.actions = const <Widget>[], this.label});
  final List<Widget> actions;
  final String? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    return NavRow(
      children: <Widget>[
        // Takes all room left by the actions; shrinks only when that room
        // is smaller than the pill (very narrow phones).
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: PBtn(label ?? c.backLabel, onTap: c.back),
            ),
          ),
        ),
        ...actions,
      ],
    );
  }
}

/// Title row with an optional right-side badge (`.lt` + `.h1` + badge).
class TitleBadge extends ConsumerWidget {
  const TitleBadge(this.title, {super.key, this.badge});
  final String title;

  /// Default: "From Tally" for server data, "Sample data" for the demo.
  final String? badge;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: <Widget>[
      Expanded(child: H1(title)),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Bdg(
          badge ??
              (ref.watch(appProvider).repo.isRemote
                  ? 'From Tally'
                  : 'Sample data'),
          kind: BadgeKind.acc,
        ),
      ),
    ],
  );
}

// ------------------------------------------------------------------ lists

/// `.glass.list` container with 1 px dividers between children.
class GlassList extends StatelessWidget {
  const GlassList({
    super.key,
    required this.children,
    this.margin = EdgeInsets.zero,
    this.divider = true,
    this.radius = 22,
  });
  final List<Widget> children;
  final EdgeInsets margin;
  final bool divider;
  final double radius;

  @override
  Widget build(BuildContext context) => Padding(
    padding: margin,
    child: Glass(
      radius: radius,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < children.length; i++) ...<Widget>[
              if (i > 0 && divider && children[i] is! HidRow) listDivider(),
              children[i],
            ],
          ],
        ),
      ),
    ),
  );
}

/// `.row`: 12 14 padding, min-height 66, gap 12.
class RowX extends StatelessWidget {
  const RowX({
    super.key,
    required this.children,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    this.minHeight = 66,
    this.cross = CrossAxisAlignment.center,
    this.radius = 16,
  });
  final List<Widget> children;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double minHeight;
  final CrossAxisAlignment cross;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final Widget r = Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: padding,
      child: Row(
        crossAxisAlignment: cross,
        children: <Widget>[
          for (int i = 0; i < children.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 12),
            children[i],
          ],
        ],
      ),
    );
    return onTap == null ? r : Tap(onTap: onTap, radius: radius, child: r);
  }
}

/// A glass `.row` card (e.g. "Need help logging in?").
class GlassRow extends StatelessWidget {
  const GlassRow({
    super.key,
    required this.children,
    this.onTap,
    this.minHeight = 66,
    this.radius = 22,
    this.border,
    this.margin = EdgeInsets.zero,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  });
  final List<Widget> children;
  final VoidCallback? onTap;
  final double minHeight;
  final double radius;
  final Border? border;
  final EdgeInsets margin, padding;

  @override
  Widget build(BuildContext context) {
    final Widget g = Glass(
      radius: radius,
      border: border,
      child: Container(
        constraints: BoxConstraints(minHeight: minHeight),
        padding: padding,
        child: Row(
          children: <Widget>[
            for (int i = 0; i < children.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 12),
              children[i],
            ],
          ],
        ),
      ),
    );
    return Padding(
      padding: margin,
      child: onTap == null ? g : Tap(onTap: onTap, radius: radius, child: g),
    );
  }
}

const Color kChev = Color(0xFF8A94AC);
Widget chevR([IcSize s = IcSize.s]) => Ic('chevR', size: s, color: kChev);

/// A customisable list row (`L()` rows with `data-lk`): long-press menu,
/// drag reorder, pin badge and the armed / ghost / lifted states.
class LRow extends ConsumerStatefulWidget {
  const LRow({
    super.key,
    required this.list,
    required this.lk,
    required this.child,
    this.radius = 16,
    this.pinOverlay = true,
    this.pinCorner = false,
  });
  final String list, lk;
  final Widget child;
  final double radius;

  /// Grid cards: the pin sits in the card's (empty) top-right corner.
  /// List rows (default): the row keeps a narrow lane on the right for the
  /// pin, so it never covers amounts, badges or buttons.
  final bool pinCorner;

  /// Draws the pin badge over the row's top-right corner. Rows that lay the
  /// badge out themselves (so it never covers their text) pass false.
  final bool pinOverlay;

  @override
  ConsumerState<LRow> createState() => _LRowState();
}

/// Each row owns its drag / long-press key only while it is on screen and
/// removes it when scrolled away, so long lists never hold thousands of
/// [GlobalKey]s.
class _LRowState extends ConsumerState<LRow> {
  final GlobalKey _gk = GlobalKey();
  late final AppController _ctl = ref.read(appProvider);
  String? _slot;

  void _register() {
    final String slot = '${widget.list}|${widget.lk}';
    if (_slot != null && _slot != slot && _ctl.reg.rows[_slot] == _gk) {
      _ctl.reg.rows.remove(_slot);
    }
    _slot = slot;
    _ctl.reg.rows[slot] = _gk;
  }

  @override
  void dispose() {
    if (_slot != null && _ctl.reg.rows[_slot] == _gk) {
      _ctl.reg.rows.remove(_slot);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppController c = ref.watch(appProvider);
    _register();
    final String list = widget.list, lk = widget.lk;
    final Widget child = widget.child;
    final double radius = widget.radius;
    final GlobalKey gk = _gk;
    final bool armed = c.armed?.matches(list, lk) ?? false;
    final bool ghost =
        c.ldrag != null && c.ldrag!.list == list && c.ldrag!.id == lk;
    final bool lift =
        c.cmenu != null && c.cmenu!.list == list && c.cmenu!.id == lk;
    final bool dim = c.cmenu != null && !lift;
    final bool pinned = c.isPinned(list, lk);
    final bool lane = pinned && widget.pinOverlay && !widget.pinCorner;
    Widget w = Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: <Widget>[
        lane
            ? Padding(padding: const EdgeInsets.only(right: 18), child: child)
            : child,
        if (pinned && widget.pinOverlay)
          widget.pinCorner
              ? const Positioned(top: 6, right: 8, child: PinBadge())
              : const Positioned(
                  top: 0,
                  bottom: 0,
                  right: 4,
                  child: Center(child: PinBadge()),
                ),
      ],
    );
    if (lift) {
      w = DecoratedBox(
        decoration: BoxDecoration(
          color: whiteA(.35),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: w,
      );
    }
    if (armed) {
      w = CustomPaint(
        foregroundPainter: DashedRRect(
          BorderRadius.circular(radius),
          mix(Tc.of(context).navy, .45),
          2,
        ),
        child: w,
      );
    }
    return KeyedSubtree(
      key: gk,
      child: Listener(
        onPointerDown: (PointerDownEvent e) => c.pDown(e, list, lk, gk),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: ghost ? .3 : (dim ? .6 : 1),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 350),
            curve: const Cubic(.3, 1.5, .5, 1),
            scale: lift ? 1.02 : 1,
            child: Wiggle(on: armed && !ghost, child: w),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- sheets

/// `.scrim` + `.sheet` (slides up .46 s cubic-bezier(.2,.95,.25,1)).
class Sheet extends ConsumerWidget {
  const Sheet({
    super.key,
    required this.child,
    this.top,
    this.flex = false,
    this.onClose,
    this.label,
  });
  final Widget child;

  /// Fixed `top:` (search 60, pickers 40); otherwise max-height 90 %.
  final double? top;

  /// `.sheetf`: column layout with its own scrolling body and footer.
  final bool flex;
  final VoidCallback? onClose;
  final String? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final MediaQueryData mq = MediaQuery.of(context);
    final double kb = mq.viewInsets.bottom;
    final double topPos = top != null ? math.max(top!, mq.padding.top + 8) : 0;
    final Widget body = ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: backdrop(26, 1.85),
        child: Glass(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          fill: p.sheetFill,
          shadows: const <BoxShadow>[],
          child: Padding(
            padding: flex
                ? const EdgeInsets.only(top: 10)
                : EdgeInsets.fromLTRB(16, 10, 16, 30 + mq.padding.bottom * .5),
            child: flex
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Grab(),
                      Expanded(child: child),
                    ],
                  )
                : SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[const Grab(), child],
                    ),
                  ),
          ),
        ),
      ),
    );
    return Stack(
      children: <Widget>[
        Positioned.fill(child: Scrim(onTap: onClose ?? c.closeOv)),
        Positioned(
          left: 0,
          right: 0,
          bottom: kb,
          top: top != null ? topPos : null,
          child: Enter(
            ms: 460,
            curve: const Cubic(.2, .95, .25, 1),
            builder: (double t, Widget ch) => FractionalTranslation(
              translation: Offset(0, (1 - t) * 1.05),
              child: ch,
            ),
            child: top != null
                ? body
                : ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: (mq.size.height - kb) * .9,
                    ),
                    child: body,
                  ),
          ),
        ),
      ],
    );
  }
}

class Grab extends StatelessWidget {
  const Grab({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 42,
      height: 5,
      margin: const EdgeInsets.fromLTRB(0, 2, 0, 12),
      decoration: BoxDecoration(
        color: navyA(.22),
        borderRadius: BorderRadius.circular(3),
      ),
    ),
  );
}

/// `.scrim`: rgba(14,27,51,.3) fading in over .25 s.
class Scrim extends StatelessWidget {
  const Scrim({super.key, this.onTap, this.alpha = .3, this.ms = 250});
  final VoidCallback? onTap;
  final double alpha;
  final int ms;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: fadeIn(ColoredBox(color: Color.fromRGBO(14, 27, 51, alpha)), ms: ms),
  );
}

/// `.shd` sheet header: title/sub + close button.
class SheetHead extends ConsumerWidget {
  const SheetHead(
    this.title, {
    super.key,
    this.sub,
    this.size = 22,
    this.onClose,
    this.closeFirst = false,
  });
  final String title;
  final String? sub;
  final double size;
  final VoidCallback? onClose;
  final bool closeFirst;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final Widget close = CBtn(
      'close',
      small: true,
      onTap: onClose ?? c.closeOv,
    );
    final Widget text = Expanded(child: RTx(title, sub, titleSize: size));
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: closeFirst
            ? <Widget>[close, const SizedBox(width: 12), text]
            : <Widget>[text, const SizedBox(width: 12), close],
      ),
    );
  }
}

/// `.grid2` / `.two` / `.grid3` / `.grid4` with equal-height rows.
class Grid extends StatelessWidget {
  const Grid({
    super.key,
    required this.cols,
    required this.children,
    this.gap = 12,
    this.stretch = true,
  });
  final int cols;
  final List<Widget> children;
  final double gap;
  final bool stretch;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < children.length; i += cols) {
      final List<Widget> cells = <Widget>[];
      for (int j = 0; j < cols; j++) {
        if (j > 0) cells.add(SizedBox(width: gap));
        cells.add(
          Expanded(
            child: i + j < children.length
                ? children[i + j]
                : const SizedBox.shrink(),
          ),
        );
      }
      if (rows.isNotEmpty) rows.add(SizedBox(height: gap));
      rows.add(
        stretch
            ? IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: cells,
                ),
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: cells,
              ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

/// `.stat` tile text (24/800 value over 13/600 label).
class Stat extends StatelessWidget {
  const Stat(this.value, this.label, {super.key, this.color, this.top});
  final String value, label;
  final Color? color;
  final Widget? top;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ?top,
        Text(
          value,
          style: ts(24, w: w800, c: color ?? p.ink),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: ts(13, w: w600, c: p.ink3),
        ),
      ],
    );
  }
}

/// "Sample data" / summary header line (`.lt` with badge).
class LtBadge extends ConsumerWidget {
  const LtBadge(
    this.left, {
    super.key,
    this.badge,
    this.margin = const EdgeInsets.only(bottom: 12),
  });
  final Widget left;

  /// Default: "From Tally" for server data, "Sample data" for the demo.
  final String? badge;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: margin,
    child: Row(
      children: <Widget>[
        Expanded(child: left),
        const SizedBox(width: 8),
        Bdg(
          badge ??
              (ref.watch(appProvider).repo.isRemote
                  ? 'From Tally'
                  : 'Sample data'),
          kind: BadgeKind.acc,
        ),
      ],
    ),
  );
}
