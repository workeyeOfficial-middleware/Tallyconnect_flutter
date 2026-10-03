// HOME (Main.dc.html 545–625; view model 2321–2350): top bar, company box,
// the swipeable dashboard pages with long-press menu / drag / pin / hide,
// page dots, edge-flip indicators and the drag ghost.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/design/tc_icons.dart';
import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';
import '../../core/utils/format.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import '../widgets/common.dart';

double homePagerTop(BuildContext c) => topIn(c) + 148;
double homePagerBottom(BuildContext c) => barBottom(c) + 102;

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final PageController _pc;
  late final AppController _c;

  @override
  void initState() {
    super.initState();
    final AppController c = _c = ref.read(appProvider);
    final int n = c.curPages().length;
    final int i = c.page.clamp(0, n - 1);
    _pc = PageController(initialPage: i);
    c.pager = _pc;
    if (i != c.page) {
      WidgetsBinding.instance.addPostFrameCallback((_) => c.onPageChanged(i));
    }
  }

  @override
  void dispose() {
    if (_c.pager == _pc) _c.pager = null;
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final List<List<String>> pages =
        c.pagesByWs[c.curWs.id] ?? c.defaultPages(c.curWs);
    final List<HiddenCard> hid = c.hidList();
    final double top = topIn(context);
    final DragPt? drag = c.drag;
    return Stack(
      children: <Widget>[
        // ---- pager
        Positioned(
          top: homePagerTop(context),
          bottom: homePagerBottom(context),
          left: 0,
          right: 0,
          child: PageView.builder(
            controller: _pc,
            physics: c.scrollLock
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(parent: ClampingScrollPhysics()),
            onPageChanged: c.onPageChanged,
            itemCount: pages.length,
            itemBuilder: (BuildContext context, int i) => _Page(
              index: i,
              ids: pages[i],
              hasHidden: hid.any((HiddenCard h) => h.page == i),
            ),
          ),
        ),
        // ---- top bar + company box
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, top, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                NavRow(
                  children: <Widget>[
                    CBtn('menu', onTap: () => c.openOverlay('menu')),
                    const Expanded(child: Brand()),
                    CBtn('search', onTap: () => c.openOverlay('search')),
                    CBtn(
                      'bell',
                      onTap: () => c.go('notifs'),
                      dot: c.unread > 0,
                    ),
                  ],
                ),
                Tap(
                  onTap: () => c.openOverlay('company'),
                  radius: 24,
                  child: Glass(
                    radius: 24,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 78),
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: <Widget>[
                          const _CoIc(),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  c.companyName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: ts(
                                    18,
                                    w: w800,
                                    ls: -.18,
                                    h: 1.2,
                                    c: p.ink,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 2,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: <Widget>[
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        const LiveDot(),
                                        const SizedBox(width: 7),
                                        Ic(
                                          'laptop',
                                          size: IcSize.xs,
                                          color: p.ink,
                                        ),
                                        const SizedBox(width: 5),
                                        Flexible(
                                          child: Text(
                                            'Tally Connected',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: ts(
                                              12.5,
                                              w: w700,
                                              h: 1.25,
                                              c: p.ink,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      '· Synced 2 min ago',
                                      style: ts(12.5, h: 1.25, c: p.ink3),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Container(
                            width: 34,
                            height: 34,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: navyA(.06),
                            ),
                            child: Ic('chevD', size: IcSize.s, color: p.ink2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // ---- page dots
        // `.dots`: the glass capsule is always there; dots only with 2+ pages.
        Positioned(
          left: 0,
          right: 0,
          bottom: barBottom(context) + 76,
          height: 24,
          child: Center(
            child: Glass(
              radius: 12,
              blur: true,
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (
                    int i = 0;
                    i < (pages.length < 2 ? 0 : pages.length);
                    i++
                  ) ...<Widget>[
                    if (i > 0) const SizedBox(width: 2),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => c.scrollToPage(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 450),
                        curve: const Cubic(.3, 1.5, .5, 1),
                        width: i == c.page ? 32 : 22,
                        height: 24,
                        alignment: Alignment.center,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 450),
                          curve: const Cubic(.3, 1.5, .5, 1),
                          width: i == c.page ? 20 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: i == c.page ? p.acc : navyA(.25),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        // ---- drag: edges + ghost
        if (drag != null) ...<Widget>[
          _Edge(left: true, on: c.edge == 'l'),
          _Edge(left: false, on: c.edge == 'r'),
          _Ghost(drag: drag),
        ],
      ],
    );
  }
}

class _CoIc extends StatelessWidget {
  const _CoIc();

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final BorderRadius br = BorderRadius.circular(16);
    return CustomPaint(
      painter: OuterShadow(br, <BoxShadow>[css(0, 8, 16, -8, mix(p.acc3, .7))]),
      child: Container(
        width: 50,
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: br,
          gradient: LinearGradient(
            begin: const Alignment(-.45, -1),
            end: const Alignment(.45, 1),
            colors: <Color>[p.acc2, p.acc3],
          ),
        ),
        foregroundDecoration: insetTop(br, whiteA(.35)),
        child: const Ic('building', color: Colors.white),
      ),
    );
  }
}

class _Edge extends StatelessWidget {
  const _Edge({required this.left, required this.on});
  final bool left, on;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Positioned(
      top: homePagerTop(context),
      bottom: homePagerBottom(context),
      left: left ? 0 : null,
      right: left ? null : 0,
      width: 34,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: on ? 1 : .35,
          duration: const Duration(milliseconds: 250),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: left ? Alignment.centerLeft : Alignment.centerRight,
                end: left ? Alignment.centerRight : Alignment.centerLeft,
                colors: <Color>[mix(p.acc, .22), mix(p.acc, 0)],
              ),
            ),
            child: Center(child: Ic(left ? 'chevL' : 'chevR', color: p.acc)),
          ),
        ),
      ),
    );
  }
}

class _Ghost extends ConsumerWidget {
  const _Ghost({required this.drag});
  final DragPt drag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final ({String label, String ic, String c})? m = c.widgetMeta(drag.id);
    if (m == null) return const SizedBox.shrink();
    return Positioned(
      left: drag.x,
      top: drag.y,
      child: IgnorePointer(
        child: FractionalTranslation(
          translation: const Offset(-.5, -.5),
          child: Transform.rotate(
            angle: 2.5 * math.pi / 180,
            child: Transform.scale(
              scale: 1.06,
              child: Glass(
                radius: 22,
                blur: true,
                shadows: <BoxShadow>[css(0, 30, 50, -18, navyA(.55))],
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 116),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Ico(m.ic, size: IcoSize.sm, color: p.cat(m.c)),
                        const SizedBox(height: 8),
                        Text(
                          m.label,
                          style: ts(15, w: w800, c: p.ink),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One `.page`: title, `.wgrid` (3 columns, wide cards span all), drop zone
/// and the "Hidden cards · Unhide" row.
class _Page extends ConsumerWidget {
  const _Page({
    required this.index,
    required this.ids,
    required this.hasHidden,
  });
  final int index;
  final List<String> ids;
  final bool hasHidden;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final bool dragging = c.drag != null;
    // CSS grid auto-placement: wide cards take a full row; tiles fill rows of 3.
    final List<Widget> rows = <Widget>[];
    List<String> run = <String>[];
    void flush() {
      if (run.isEmpty) return;
      final List<String> r = run;
      run = <String>[];
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 12));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int j = 0; j < 3; j++) ...<Widget>[
                if (j > 0) const SizedBox(width: 12),
                Expanded(
                  child: j < r.length
                      ? _Card(id: r[j])
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    }

    for (final String id in ids) {
      if (c.widgetMeta(id) == null) continue;
      if (id == 'newEntry' || id == 'money') {
        flush();
        if (rows.isNotEmpty) rows.add(const SizedBox(height: 12));
        rows.add(_Card(id: id));
      } else {
        run.add(id);
        if (run.length == 3) flush();
      }
    }
    flush();

    return fadeMask(
      top: 10,
      bottom: 18,
      SingleChildScrollView(
        physics: scrollPhysics(c),
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 12),
              child: Text(
                index == 0 ? 'What would you like to do?' : 'Page ${index + 1}',
                style: ts(19, w: w800, ls: -.19, c: p.ink),
              ),
            ),
            ...rows,
            Container(
              key: c.reg.end(index),
              margin: const EdgeInsets.only(top: 12),
              child: dragging
                  ? CustomPaint(
                      painter: DashedRRect(
                        BorderRadius.circular(20),
                        navyA(.2),
                        2,
                        fill: whiteA(.28),
                      ),
                      child: Container(
                        height: 74,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Drop here',
                          textAlign: TextAlign.center,
                          style: ts(13, w: w700, c: p.ink3),
                        ),
                      ),
                    )
                  : const SizedBox(height: 0, width: double.infinity),
            ),
            if (hasHidden)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: HidRow(
                  'Hidden cards · Unhide',
                  glass: true,
                  onTap: () => c.showHiddenPanel(index),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// `.wg` card shell with all interaction states.
class _Card extends ConsumerWidget {
  const _Card({required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final bool wide = id == 'newEntry' || id == 'money';
    final bool armed = c.armed?.matches('home', id) ?? false;
    final bool ghosted = c.drag?.id == id;
    final bool lifted =
        c.cmenu != null && c.cmenu!.list == 'home' && c.cmenu!.id == id;
    final bool dim = c.cmenu != null && !lifted;
    final bool pinned = c.pinned.contains(id);
    final GlobalKey gk = c.reg.card(id);

    void open(VoidCallback f) {
      if (!c.guardTap('home', id)) return;
      f();
    }

    Widget body;
    if (id == 'newEntry') {
      body = _EntryHero(open: open);
    } else if (id == 'money') {
      body = _MoneyCard(open: open);
    } else {
      final Shortcut t = kShortcuts[id]!;
      body = Tap(
        onTap: () => open(() => c.openShortcut(t)),
        child: Glass(
          child: Container(
            constraints: const BoxConstraints(minHeight: 136),
            padding: const EdgeInsets.fromLTRB(6, 16, 6, 14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Ico(t.ic, color: p.cat(t.c), icon: IcSize.l),
                const SizedBox(height: 9),
                Text(
                  t.t,
                  textAlign: TextAlign.center,
                  style: ts(16, w: w800, h: 1.1, c: p.ink),
                ),
                const SizedBox(height: 4),
                Text(
                  t.s,
                  textAlign: TextAlign.center,
                  style: ts(12.5, c: p.ink3),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget w = Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: <Widget>[
        body,
        if (pinned)
          const Positioned(top: 8, right: 8, child: PinBadge(mini: false)),
        if (armed) ...<Widget>[
          Positioned.fill(
            child: AbsorbPointer(
              child: Container(color: const Color(0x00000000)),
            ),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: p.navy,
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  css(0, 4, 10, -4, Colors.black.withValues(alpha: .4)),
                ],
              ),
              child: const Ic('move', size: IcSize.xs, color: Colors.white),
            ),
          ),
        ],
      ],
    );

    if (ghosted) {
      w = CustomPaint(
        foregroundPainter: DashedRRect(
          BorderRadius.circular(22),
          navyA(.45),
          2,
        ),
        child: Opacity(opacity: .3, child: w),
      );
    } else {
      w = AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: dim ? .55 : 1,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 350),
          curve: const Cubic(.3, 1.5, .5, 1),
          scale: lifted ? 1.035 : 1,
          child: Wiggle(on: armed, deg: wide ? .35 : 1.4, child: w),
        ),
      );
    }
    if (c.flash.contains(id)) w = _Flash(child: w);
    return KeyedSubtree(
      key: gk,
      child: Listener(
        onPointerDown: (PointerDownEvent e) => c.pDown(e, 'home', id, gk),
        child: w,
      ),
    );
  }
}

/// `flashIn` (1.3 s) + fading accent glow on an unhidden card.
class _Flash extends StatelessWidget {
  const _Flash({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Enter(
      ms: 1300,
      builder: (double t, Widget ch) {
        const Cubic seg = Cubic(.3, 1.5, .5, 1);
        final double sc = t < .6
            ? .85 + (1.04 - .85) * seg.transform(t / .6)
            : 1.04 - .04 * seg.transform((t - .6) / .4);
        final double op = (t / .6).clamp(0, 1);
        final double glow = 1 - Curves.ease.transform(t);
        return Opacity(
          opacity: op,
          child: Transform.scale(
            scale: sc,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: <BoxShadow>[
                  BoxShadow(color: mix(p.acc, .55 * glow), spreadRadius: 3),
                  BoxShadow(color: mix(p.acc, .4 * glow), blurRadius: 18),
                ],
              ),
              child: ch,
            ),
          ),
        );
      },
      child: child,
    );
  }
}

/// New Entry hero card (lines 570–581).
class _EntryHero extends ConsumerWidget {
  const _EntryHero({required this.open});
  final void Function(VoidCallback) open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    const List<(String, String, String)> quick = <(String, String, String)>[
      ('Sale', 'bag', 'sales'),
      ('Purchase', 'cart', 'purchase'),
      ('Money In', 'in', 'receipt'),
      ('Money Out', 'out', 'payment'),
    ];
    return HeroBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Tap(
            onTap: () => open(() => c.go('newEntry')),
            radius: 18,
            subtleHighlight: true,
            child: Row(
              children: <Widget>[
                const PlusTile(),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'New Entry',
                        style: ts(21, w: w800, c: p.acc3),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Record a sale, purchase, money in or out',
                        style: ts(14, c: p.ink2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Ic('chevR', color: p.ink),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              for (int i = 0; i < quick.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Tap(
                    onTap: () => open(() => c.startFlow(quick[i].$3)),
                    radius: 16,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(2, 10, 2, 9),
                      decoration: BoxDecoration(
                        color: whiteA(.42),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: whiteA(.78)),
                      ),
                      child: Column(
                        children: <Widget>[
                          Container(
                            width: 40,
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: whiteA(.92),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: <BoxShadow>[
                                css(0, 6, 12, -6, mix(p.acc3, .45)),
                              ],
                            ),
                            child: Ic(quick[i].$2, color: p.acc),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            quick[i].$1,
                            maxLines: 1,
                            overflow: TextOverflow.visible,
                            softWrap: false,
                            style: ts(12.5, w: w700, c: p.ink),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Money summary card (lines 583–596).
class _MoneyCard extends ConsumerWidget {
  const _MoneyCard({required this.open});
  final void Function(VoidCallback) open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    Color bg(String k) => switch (k) {
      'toGet' => mix(p.pos, .09),
      'toGive' => mix(p.warn, .08),
      'mIn' => mix(p.pos, .06),
      'mOut' => mix(p.warn, .06),
      'sales' => mix(p.acc, .08),
      'purch' => mix(p.navy2, .07),
      _ => navyA(.06),
    };
    final Map<String, SumCard> sums = c.repo.moneyCards();
    return Glass(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LtBadge(Text('Money summary', style: rtStyle(context, 18))),
          Grid(
            cols: 2,
            children: <Widget>[
              for (final String k in c.curWs.sums)
                if (sums[k] != null)
                  Tap(
                    onTap: () => open(() => c.run(sums[k]!.go)),
                    radius: 16,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: bg(k),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Ico(
                            sums[k]!.ic,
                            size: IcoSize.xs,
                            color: p.cat(sums[k]!.c),
                            icon: IcSize.s,
                          ),
                          const SizedBox(height: 8),
                          Text(sums[k]!.t, style: rtStyle(context, 15)),
                          Text(sums[k]!.s, style: rsStyle(context, 12.5)),
                          const SizedBox(height: 6),
                          Text(
                            inr(sums[k]!.v),
                            style: amtStyle(
                              context,
                              size: 19,
                              cls: sums[k]!.cls,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}
