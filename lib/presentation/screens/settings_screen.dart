// SETTINGS (Main.dc.html 1228–1321; view models 2657–2672, 2712–2749):
// Profile, Alerts, Plan and Look — looks, palette, colour picker, matching
// combinations, wallpapers with preview/apply and the glass level.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/design/tc_color_math.dart';
import '../../core/design/tc_fields.dart';
import '../../core/design/tc_icons.dart';
import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';
import '../../core/design/tc_wall_spec.dart';
import '../../core/utils/format.dart';
import '../../data/mock/mock_data.dart';
import '../../data/repositories/api_tally_repository.dart' show DataSet;
import '../widgets/common.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    const List<(String, String)> tabs = <(String, String)>[
      ('profile', 'Profile'),
      ('alerts', 'Alerts'),
      ('plan', 'Plan'),
      ('look', 'Look'),
      ('layout', 'Layout'),
    ];
    return Scr(
      children: <Widget>[
        const BackNav(),
        const H1('Settings', afterNav: true),
        const Sub('Your profile, alerts, plan and look'),
        Seg(
          fontSize: 14,
          items: tabs.map(((String, String) e) => e.$2).toList(),
          selected: tabs.indexWhere(((String, String) e) => e.$1 == c.setTab),
          onPick: (int i) => c.update(() => c.setTab = tabs[i].$1),
        ),
        KeyedSubtree(
          key: ValueKey<String>(c.setTab),
          child: switch (c.setTab) {
            'alerts' => const _Alerts(),
            'plan' => const _Plan(),
            'look' => const _Look(),
            'layout' => const _Layout(),
            _ => const _Profile(),
          },
        ),
      ],
    );
  }
}

class _Profile extends ConsumerWidget {
  const _Profile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final bool remote = c.repo.isRemote;
    final String name = remote
        ? (c.repo.profile?.username ?? c.repo.user?.username ?? '—')
        : 'workk72002';
    final String role = remote
        ? (c.isAdmin ? 'Admin' : 'Team member')
        : 'Admin';
    final List<(String, String, String)> rows = <(String, String, String)>[
      ('Username', name, 'person'),
      (
        'Email',
        remote
            ? (c.repo.profile?.email ?? c.repo.user?.email ?? '—')
            : 'workk72002@gmail.com',
        'mail',
      ),
      // The server stores no mobile number for users.
      ('Mobile', remote ? '—' : '+91 98200 45127', 'phone'),
      ('Company', c.companyName, 'building'),
      ('Role', role, 'shield'),
      if (remote && !c.isAdmin && c.repo.profile?.adminEmail != null)
        ('Admin', c.repo.profile!.adminEmail!, 'shield'),
      ('Plan', remote ? (c.repo.user?.plan ?? '—') : 'Enterprise', 'star'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Rise(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              children: <Widget>[
                Av(initials(name), size: 86, fontSize: 34, accent: true),
                const SizedBox(height: 12),
                Text(name, style: rtStyle(context, 21)),
                const SizedBox(height: 4),
                Text('$role · ${c.companyName}', style: rsStyle(context)),
              ],
            ),
          ),
        ),
        GlassList(
          children: <Widget>[
            for (final (String, String, String) r in rows)
              RowX(
                minHeight: 60,
                children: <Widget>[
                  Ico(r.$3, size: IcoSize.xs, color: p.navy, icon: IcSize.s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(r.$1, style: rsStyle(context)),
                        Text(r.$2, style: rtStyle(context)),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Btn(
            label: 'Log out',
            icon: 'logout',
            kind: BtnKind.g,
            color: p.neg,
            onTap: c.logout,
          ),
        ),
      ],
    );
  }
}

/// Notification preferences: one switch per alert type, grouped. Changes
/// are kept as a draft until "Save preferences"; server types are saved to
/// this user's account (the server then shows only enabled types), phone
/// types (due reminders, out-of-stock) on this phone.
class _Alerts extends ConsumerWidget {
  const _Alerts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    if (!c.alertsReady) {
      return Rise(
        child: EmptyBox(
          c.emptyText(DataSet.alerts, 'Loading your notification settings…'),
        ),
      );
    }
    final List<String> groups = <String>[];
    for (final NotifPref x in c.notifPrefs) {
      if (!groups.contains(x.group)) groups.add(x.group);
    }
    return Rise(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: RTx(
              'Notification preferences',
              'Choose exactly which alerts you get. Only switched-on types '
                  'appear in Alerts.',
              titleSize: 17,
            ),
          ),
          for (final String g in groups) ...<Widget>[
            Sec(g),
            GlassList(
              children: <Widget>[
                for (final NotifPref x in c.notifPrefs)
                  if (x.group == g)
                    RowX(
                      key: ValueKey<String>('pref-${x.key}'),
                      onTap: () => c.toggleAlert(x.key),
                      children: <Widget>[
                        Ico(
                          x.ic,
                          size: IcoSize.xs,
                          color: p.cat(x.c),
                          icon: IcSize.s,
                        ),
                        Expanded(child: RTx(x.t, x.s)),
                        Sw(c.alertOn(x.key)),
                      ],
                    ),
              ],
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Btn(
              label: c.alertSaving ? 'Saving…' : 'Save preferences',
              icon: 'check',
              enabled: c.alertDirty && !c.alertSaving,
              onTap: c.saveAlertPrefs,
            ),
          ),
          if (c.alertDirty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'You have unsaved changes',
                textAlign: TextAlign.center,
                style: rsStyle(context, 12.5),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bottom bar and Home cards the user hid (long-press), with Restore.
class _Layout extends ConsumerWidget {
  const _Layout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final List<({String k, String t, String ic})> tabs =
        <({String k, String t, String ic})>[
          for (final ({String k, String t, String ic}) t in kTabs)
            if (c.hiddenTabs.contains(t.k) && c.canOpen(t.k)) t,
        ];
    final List<HiddenCard> cards = c.hidList();
    Widget restore(VoidCallback f) =>
        ChipBtn('Restore', icon: 'eye', height: 36, fontSize: 13.5, onTap: f);
    return Rise(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          GlassRow(
            key: const ValueKey<String>('navBarSwitch'),
            onTap: () => c.setNavBarHidden(!c.navBarHidden),
            children: <Widget>[
              Ico('grid', size: IcoSize.xs, color: p.navy, icon: IcSize.s),
              Expanded(
                child: RTx(
                  'Bottom navigation bar',
                  c.navBarHidden
                      ? 'Hidden · open screens from the menu'
                      : 'Shown at the bottom of main screens',
                ),
              ),
              Sw(!c.navBarHidden),
            ],
          ),
          const Sec('Hidden tabs'),
          GlassList(
            children: <Widget>[
              if (tabs.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No hidden tabs. Long-press a tab in the bar, let go '
                    'without moving it, then choose Hide.',
                    style: rsStyle(context, 14),
                  ),
                ),
              for (final ({String k, String t, String ic}) t in tabs)
                RowX(
                  children: <Widget>[
                    Ico(t.ic, size: IcoSize.xs, color: p.acc, icon: IcSize.s),
                    Expanded(child: RTx(t.t, 'Hidden from the bottom bar')),
                    restore(() => c.restoreTab(t.k)),
                  ],
                ),
            ],
          ),
          Sec('Hidden Home cards · ${c.curWs.name}'),
          GlassList(
            children: <Widget>[
              if (cards.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No hidden cards. Long-press a card on Home and choose '
                    'Hide.',
                    style: rsStyle(context, 14),
                  ),
                ),
              for (final HiddenCard h in cards)
                Builder(
                  builder: (BuildContext context) {
                    final CardInfo? info = c.infoFor('home', h.id);
                    return RowX(
                      children: <Widget>[
                        Ico(
                          info?.ic ?? 'grid',
                          size: IcoSize.xs,
                          color: p.cat(info?.c ?? 'acc'),
                          icon: IcSize.s,
                        ),
                        Expanded(
                          child: RTx(info?.label ?? h.id, 'Page ${h.page + 1}'),
                        ),
                        restore(() => c.restoreHidden(<String>[h.id])),
                      ],
                    );
                  },
                ),
            ],
          ),
          if (tabs.isNotEmpty || cards.isNotEmpty || c.navBarHidden)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Btn(
                label: 'Restore everything',
                icon: 'eye',
                kind: BtnKind.g,
                onTap: () {
                  if (c.navBarHidden) c.setNavBarHidden(false);
                  if (tabs.isNotEmpty) c.restoreTab();
                  if (cards.isNotEmpty) {
                    c.restoreHidden(<String>[
                      for (final HiddenCard h in cards) h.id,
                    ]);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _Plan extends ConsumerWidget {
  const _Plan();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    return Rise(
      child: Glass(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Ico('star', size: IcoSize.sm, color: p.acc),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Your plan', style: rsStyle(context)),
                      Text(
                        c.repo.isRemote
                            ? (c.repo.user?.plan ?? 'Not sent by server')
                            : 'Enterprise',
                        style: rtStyle(context, 20),
                      ),
                    ],
                  ),
                ),
                const Bdg('Active', kind: BadgeKind.ok, dot: true),
              ],
            ),
            Kv(
              'Renews on',
              c.repo.isRemote ? 'Not available from server' : '31 Mar 2027',
              padding: const EdgeInsets.fromLTRB(0, 14, 0, 4),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Btn(label: 'See all plans', onTap: () => c.go('billing')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section heading used throughout the Look tab.
class _Hd extends StatelessWidget {
  const _Hd(this.t, this.s, {this.top = 22});
  final String t, s;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(4, top, 4, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(t, style: rtStyle(context, 17)),
        const SizedBox(height: 4),
        Text(s, style: rsStyle(context)),
      ],
    ),
  );
}

/// Selectable glass card with a 2 px navy border when on (`.lookbtn.on`,
/// `.wbtn.on`, `.palb.on`).
class _SelCard extends StatelessWidget {
  const _SelCard({
    required this.on,
    required this.onTap,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(8, 8, 8, 10),
  });
  final bool on;
  final VoidCallback onTap;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Tap(
    onTap: onTap,
    child: Glass(
      border: Border.all(
        color: on ? Tc.of(context).navy : const Color(0x00000000),
        width: 2,
      ),
      child: Padding(padding: padding, child: child),
    ),
  );
}

/// `.pvcard` mini glass card inside thumbnails.
class _PvCard extends StatelessWidget {
  const _PvCard(this.p, {this.cardAlpha = .5});
  final TcPalette p;
  final double cardAlpha;

  @override
  Widget build(BuildContext context) => Positioned(
    left: 10,
    right: 10,
    bottom: 10,
    height: 46,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: backdrop(8, 1.8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: p.gt.withValues(alpha: cardAlpha),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: whiteA(.85)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(
                    begin: const Alignment(-.35, -1),
                    end: const Alignment(.35, 1),
                    colors: <Color>[p.acc2, p.acc3],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Aa ₹',
                  style: ts(15, w: w800, c: p.ink),
                ),
              ),
              Container(
                width: 30,
                height: 16,
                decoration: BoxDecoration(
                  color: p.navy,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// `.lthumb` / `.cthumb`: wallpaper + orb + preview card.
class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.p,
    required this.on,
    this.orb = true,
    this.cardAlpha = .5,
  });
  final TcPalette p;
  final bool on, orb;
  final double cardAlpha;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 112,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: <Widget>[
          Positioned.fill(child: CustomPaint(painter: WallPainter(p.wall))),
          if (orb)
            Positioned(
              top: -16,
              right: -10,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: 10,
                  sigmaY: 10,
                  tileMode: TileMode.decal,
                ),
                child: Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    color: p.o2.withValues(alpha: .9),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: whiteA(.9)),
              ),
            ),
          ),
          _PvCard(p, cardAlpha: cardAlpha),
          if (on) const Positioned(top: 8, right: 8, child: Thck()),
        ],
      ),
    ),
  );
}

class _Look extends ConsumerWidget {
  const _Look();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final List<String> sig = kLookSig[c.preset] ?? kLookSig['aurora']!;
    final List<(String, String, String, String)> accents =
        <(String, String, String, String)>[
          ('look', sig[0], sig[1], sig[2]),
          for (final String k in kLookAcc[c.preset] ?? const <String>[])
            (k, accentOf(k)!.t, accentOf(k)!.a, accentOf(k)!.b),
        ];
    const List<(String, String)> tabs = <(String, String)>[
      ('theme', 'Looks'),
      ('colour', 'Colour'),
      ('background', 'Background'),
      ('glass', 'Glass'),
    ];
    final String tab = c.lookTab;
    return Rise(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Sub-sections so each kind of setting has its own place.
          Seg(
            fontSize: 13.5,
            items: tabs.map(((String, String) e) => e.$2).toList(),
            selected: tabs.indexWhere(((String, String) e) => e.$1 == tab),
            onPick: (int i) => c.update(() => c.lookTab = tabs[i].$1),
          ),
          if (tab == 'theme') ...<Widget>[
            const _Hd(
              'Look',
              'Each look sets the wallpaper, glass, colours and text together.',
              top: 0,
            ),
            Grid(
              cols: 2,
              children: <Widget>[
                for (final KT l in kLooks)
                  _SelCard(
                    on: c.mode == 'look' && c.preset == l.k,
                    onTap: () => c.pickLook(l.k),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _Thumb(
                          p: lookThumbPalette(l.k, c.accent),
                          on: c.mode == 'look' && c.preset == l.k,
                        ),
                        const SizedBox(height: 9),
                        RTx(
                          l.t,
                          l.s,
                          titleSize: 15,
                          subStyle: ts(13.5, h: 1.3, c: p.ink3),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (c.mode == 'custom')
              const InfoBox(
                'Using your own colour. Pick a ready-made look above to switch back.',
                icon: 'drop',
                margin: EdgeInsets.only(top: 18, bottom: 14),
              ),
            const _ResetLook(),
          ],
          if (tab == 'colour') ...<Widget>[
            if (c.mode == 'look') ...<Widget>[
              const _Hd(
                'Colour palette',
                'Colours picked to suit this look. Used for buttons, tabs, icons and highlights on every screen.',
              ),
              Grid(
                cols: 5,
                gap: 8,
                children: <Widget>[
                  for (final (String, String, String, String) a in accents)
                    _SelCard(
                      on: c.accent == a.$1,
                      onTap: () => c.pickAccent(a.$1),
                      padding: const EdgeInsets.fromLTRB(2, 12, 2, 10),
                      child: Stack(
                        fit: StackFit.passthrough,
                        clipBehavior: Clip.none,
                        children: <Widget>[
                          Column(
                            children: <Widget>[
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                  gradient: LinearGradient(
                                    begin: const Alignment(-.5, -1),
                                    end: const Alignment(.5, 1),
                                    colors: <Color>[
                                      hexColor(a.$3),
                                      hexColor(a.$4),
                                    ],
                                  ),
                                  boxShadow: <BoxShadow>[
                                    css(
                                      0,
                                      6,
                                      14,
                                      -6,
                                      Colors.black.withValues(alpha: .35),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                a.$2,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ts(11.5, w: w700, c: p.ink),
                              ),
                            ],
                          ),
                          if (c.accent == a.$1)
                            const Positioned(top: -6, right: -2, child: Thck()),
                        ],
                      ),
                    ),
                ],
              ),
            ],
            const _Hd(
              'Your own colour',
              'Pick any colour. We make matching looks for you.',
            ),
            const _ColourPicker(),
            const _Hd(
              'Matching combinations',
              'Tap one to use it on every screen.',
            ),
            Grid(
              cols: 2,
              children: <Widget>[
                for (int i = 0; i < kCombos.length; i++)
                  Builder(
                    builder: (BuildContext context) {
                      final String hex = c.cpHex;
                      final bool on =
                          c.mode == 'custom' &&
                          c.customBase == hex &&
                          c.customCombo == i;
                      final TcPalette tp = resolvePalette(
                        preset: c.preset,
                        mode: 'custom',
                        customBase: hex,
                        customCombo: i,
                      );
                      return _SelCard(
                        on: on,
                        onTap: () => c.pickCombo(i),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _Thumb(p: tp, on: on, orb: false, cardAlpha: .55),
                            const SizedBox(height: 9),
                            RTx(kCombos[i].t, kCombos[i].s, titleSize: 15),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ],
          if (tab == 'background') ...<Widget>[
            const _Hd(
              'Wallpaper',
              'Choose a background or use your own photo. You will see a preview first.',
              top: 0,
            ),
            const _Walls(),
            if (c.pendWall != null) const _WallPreview(),
            const _BackgroundLevels(),
          ],
          if (tab == 'glass')
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Glass(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Expanded(
                          child: RTx(
                            'Glass see-through',
                            'How clear the glass looks',
                            titleSize: 17,
                          ),
                        ),
                        Text(
                          '${c.glass.round()}%',
                          style: amtStyle(context, size: 20),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 30,
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 4,
                          activeTrackColor: p.acc,
                          inactiveTrackColor: navyA(.15),
                          thumbColor: p.acc,
                          overlayShape: SliderComponentShape.noOverlay,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 9,
                          ),
                          showValueIndicator: ShowValueIndicator.never,
                          tickMarkShape: SliderTickMarkShape.noTickMark,
                        ),
                        child: Slider(
                          value: c.glass.clamp(20, 100),
                          min: 20,
                          max: 100,
                          divisions: 8,
                          onChanged: c.setGlass,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 8, 0, 14),
                      child: Row(
                        children: <Widget>[
                          for (final int v in const <int>[
                            20,
                            40,
                            60,
                            80,
                            100,
                          ]) ...<Widget>[
                            if (v != 20) const SizedBox(width: 8),
                            Expanded(
                              child: Tap(
                                onTap: () => c.setGlass(v.toDouble()),
                                radius: 13,
                                child: c.glass == v
                                    ? Container(
                                        height: 42,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: p.navy,
                                          borderRadius: BorderRadius.circular(
                                            13,
                                          ),
                                        ),
                                        child: Text(
                                          '$v%',
                                          style: ts(
                                            14,
                                            w: w700,
                                            c: Colors.white,
                                          ),
                                        ),
                                      )
                                    : Glass(
                                        radius: 13,
                                        height: 42,
                                        child: Center(
                                          child: Text(
                                            '$v%',
                                            style: ts(14, w: w700, c: p.ink),
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('Live preview', style: rtStyle(context, 15)),
                    ),
                    _GlassPreview(glassTxt: '${c.glass.round()}%'),
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        'Changes cards, top bars, sheets and the bottom bar on every screen. Text and icons always stay clear.',
                        style: rsStyle(context),
                      ),
                    ),
                    const _ResetLook(),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ResetLook extends ConsumerWidget {
  const _ResetLook();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Btn(
        label: 'Reset to default',
        icon: 'sync',
        kind: BtnKind.g,
        onTap: c.resetLook,
      ),
    );
  }
}

/// Glass-style slider used by the background controls.
class _LevelSlider extends StatelessWidget {
  const _LevelSlider({
    required this.title,
    required this.sub,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.ends = const ('', ''),
  });
  final String title, sub, valueText;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  final (String, String) ends;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: RTx(title, sub, titleSize: 17)),
            const SizedBox(width: 10),
            Text(valueText, style: amtStyle(context, size: 20)),
          ],
        ),
        SizedBox(
          height: 30,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              activeTrackColor: p.acc,
              inactiveTrackColor: navyA(.15),
              thumbColor: p.acc,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
              showValueIndicator: ShowValueIndicator.never,
              tickMarkShape: SliderTickMarkShape.noTickMark,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: ((max - min) / 5).round(),
              onChanged: onChanged,
            ),
          ),
        ),
        if (ends.$1.isNotEmpty)
          Row(
            children: <Widget>[
              Text(ends.$1, style: rsStyle(context, 12.5)),
              const Spacer(),
              Text(ends.$2, style: rsStyle(context, 12.5)),
            ],
          ),
      ],
    );
  }
}

/// Background (wallpaper) opacity and shade — separate from the glass level.
class _BackgroundLevels extends ConsumerWidget {
  const _BackgroundLevels();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final int sh = c.bgShade.round();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Glass(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _LevelSlider(
              title: 'Background opacity',
              sub: 'How strongly the wallpaper shows',
              valueText: c.bgOpacity.round() == 0
                  ? 'Hidden'
                  : '${c.bgOpacity.round()}%',
              value: c.bgOpacity,
              min: 0,
              max: 100,
              onChanged: c.setBgOpacity,
              ends: const ('Hidden', 'Full'),
            ),
            const SizedBox(height: 18),
            _LevelSlider(
              title: 'Background shade',
              sub: 'Make the background lighter or darker',
              valueText: sh == 0 ? 'Normal' : (sh > 0 ? '+$sh' : '$sh'),
              value: c.bgShade,
              min: -100,
              max: 100,
              onChanged: c.setBgShade,
              ends: const ('Lighter', 'Darker'),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Only the background changes. Cards keep their own glass level (Glass tab).',
                style: rsStyle(context),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Btn(
                label: 'Background back to default',
                icon: 'sync',
                kind: BtnKind.g,
                onTap: () {
                  c.setBgOpacity(100);
                  c.setBgShade(AppController.kDefaultShade);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Five tab labels in a glass bar (preview mock-ups).
Widget _tabLabels(TcPalette p) => Row(
  mainAxisAlignment: MainAxisAlignment.spaceAround,
  children: <Widget>[
    for (final String t in const <String>[
      'Home',
      'Dues',
      'Team',
      'Activity',
      'Reports',
    ])
      Flexible(
        child: Text(
          t,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          style: ts(11, w: w700, c: t == 'Home' ? p.acc : p.ink),
        ),
      ),
  ],
);

class _GlassPreview extends StatelessWidget {
  const _GlassPreview({required this.glassTxt});
  final String glassTxt;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return SizedBox(
      height: 150,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: CustomPaint(painter: WallPainter(p.wall))),
            Positioned(
              top: -20,
              right: 10,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: 8,
                  sigmaY: 8,
                  tileMode: TileMode.decal,
                ),
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: p.acc.withValues(alpha: .55),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -30,
              left: 20,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: 6,
                  sigmaY: 6,
                  tileMode: TileMode.decal,
                ),
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: p.navy2.withValues(alpha: .5),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Glass(
                    radius: 16,
                    blur: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Text(
                      'Glass card · $glassTxt',
                      style: ts(14, w: w700, c: p.ink),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Glass(
                    radius: 26,
                    height: 52,
                    blur: true,
                    child: _tabLabels(p),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColourPicker extends ConsumerWidget {
  const _ColourPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final String hex = c.cpHex;
    final Color hue = hexColor(hslx(c.cpH.toDouble(), 100, 50));
    return Glass(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ---- saturation / value pad
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              void set(Offset l) => c.cpPad(l.dx / box.maxWidth, l.dy / 164);
              return GestureDetector(
                onPanDown: (DragDownDetails d) => set(d.localPosition),
                onPanUpdate: (DragUpdateDetails d) => set(d.localPosition),
                child: Container(
                  height: 164,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: <BoxShadow>[
                      css(0, 8, 18, -10, Colors.black.withValues(alpha: .3)),
                    ],
                    gradient: LinearGradient(
                      colors: <Color>[Colors.white, hue],
                    ),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: const LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: <Color>[Colors.black, Color(0x00000000)],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: (box.maxWidth - 4) * c.cpS / 100 - 14,
                        top: 160 * (100 - c.cpV) / 100 - 14,
                        child: IgnorePointer(
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: hexColor(hex),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: <BoxShadow>[
                                css(
                                  0,
                                  2,
                                  10,
                                  0,
                                  Colors.black.withValues(alpha: .4),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          // ---- hue range
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) {
                void set(double x) => c.cpHue(
                  ((x - 14) / (box.maxWidth - 28) * 359).clamp(0, 359),
                );
                return GestureDetector(
                  onPanDown: (DragDownDetails d) => set(d.localPosition.dx),
                  onPanUpdate: (DragUpdateDetails d) => set(d.localPosition.dx),
                  child: Container(
                    height: 30,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.white, width: 2),
                      gradient: const LinearGradient(
                        colors: <Color>[
                          Color(0xFFFF0000),
                          Color(0xFFFFFF00),
                          Color(0xFF00FF00),
                          Color(0xFF00FFFF),
                          Color(0xFF0000FF),
                          Color(0xFFFF00FF),
                          Color(0xFFFF0000),
                        ],
                        stops: <double>[0, .17, .33, .5, .67, .83, 1],
                      ),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        Positioned(
                          left: (box.maxWidth - 32) * c.cpH / 359,
                          top: -1,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: whiteA(.15),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: <BoxShadow>[
                                css(
                                  0,
                                  2,
                                  8,
                                  0,
                                  Colors.black.withValues(alpha: .4),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // ---- swatch + hex + more colours
          Row(
            children: <Widget>[
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: hexColor(hex),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: <BoxShadow>[
                    css(0, 6, 14, -6, Colors.black.withValues(alpha: .35)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Inp(
                  value: c.cpHexTyping ?? hex.substring(1),
                  onChanged: c.cpHexInput,
                  maxLength: 7,
                  leftPad: 32,
                  fontWeight: w800,
                  letterSpacing: .68,
                  capitalization: TextCapitalization.characters,
                  prefix: Transform.translate(
                    offset: const Offset(-1, 0),
                    child: Text(
                      '#',
                      style: ts(18, w: w800, c: p.ink3),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              CBtn(
                'drop',
                size: 56,
                radius: 16,
                color: p.acc,
                onTap: () => _moreColours(context, c),
              ),
            ],
          ),
          // ---- quick swatches
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Grid(
              cols: 8,
              gap: 9,
              stretch: false,
              children: <Widget>[
                for (final String h in kQuickSwatches)
                  Tap(
                    onTap: () => c.cpPickHex(h),
                    radius: 99,
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          color: hexColor(h),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: <BoxShadow>[
                            if (h == hex)
                              BoxShadow(color: p.ink, spreadRadius: 3),
                            css(
                              0,
                              3,
                              8,
                              -3,
                              Colors.black.withValues(alpha: .35),
                            ),
                          ],
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

  /// `<input type=color>` ("More colours"): mobile has no native colour
  /// dialog, so it opens the same full-spectrum picker in a bottom sheet.
  void _moreColours(BuildContext context, AppController c) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0x00000000),
      isScrollControlled: true,
      builder: (BuildContext ctx) => ListenableBuilder(
        listenable: c,
        builder: (BuildContext context, _) => Tc(
          p: c.palette,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Material(
              type: MaterialType.transparency,
              child: SafeArea(
                child: Glass(
                  blur: true,
                  fill: c.palette.sheetFill,
                  padding: const EdgeInsets.all(8),
                  child: const _ColourPicker(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Walls extends ConsumerWidget {
  const _Walls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final WallSpec themeWall = c.mode == 'custom'
        ? makeTheme(c.customBase, c.customCombo).wall
        : kLookDefs[c.preset]!.wall.spec;
    final List<(String, String)> items = <(String, String)>[
      ('theme', 'Match theme'),
      for (final KT w in kWallList) (w.k, w.t),
      if (c.photo != null) ('photo', 'My photo'),
    ];
    Widget thumb(String k, bool on) {
      Widget bg;
      if (k == 'photo') {
        bg = Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Image.file(File(c.photo!.path), fit: BoxFit.cover),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[whiteA(.3), whiteA(.2)],
                ),
              ),
            ),
          ],
        );
      } else {
        bg = CustomPaint(
          painter: WallPainter(k == 'theme' ? themeWall : kWalls[k]!.spec),
        );
      }
      return SizedBox(
        height: 96,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Stack(
            children: <Widget>[
              Positioned.fill(child: bg),
              Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: FractionallySizedBox(
                  widthFactor: .76,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                      child: Container(
                        height: 18,
                        decoration: BoxDecoration(
                          color: whiteA(.4),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: whiteA(.8)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: whiteA(.9)),
                  ),
                ),
              ),
              if (on) const Positioned(top: 8, right: 8, child: Thck()),
            ],
          ),
        ),
      );
    }

    return Grid(
      cols: 3,
      children: <Widget>[
        for (final (String, String) w in items)
          _SelCard(
            on: (c.wallK == w.$1 && c.pendWall == null) || c.pendWall == w.$1,
            onTap: () => c.pickWall(w.$1),
            padding: const EdgeInsets.fromLTRB(7, 7, 7, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                thumb(w.$1, c.wallK == w.$1 && c.pendWall == null),
                const SizedBox(height: 7),
                Text(
                  w.$2,
                  textAlign: TextAlign.center,
                  style: rtStyle(context, 13),
                ),
              ],
            ),
          ),
        _SelCard(
          on: false,
          onTap: c.uploadPhoto,
          padding: const EdgeInsets.fromLTRB(7, 7, 7, 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              CustomPaint(
                painter: DashedRRect(
                  BorderRadius.circular(15),
                  mix(p.acc, .4),
                  2,
                  fill: whiteA(.35),
                ),
                child: SizedBox(
                  height: 96,
                  child: Center(
                    child: Ic('upload', size: IcSize.l, color: p.acc),
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'Upload photo',
                textAlign: TextAlign.center,
                style: rtStyle(context, 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WallPreview extends ConsumerWidget {
  const _WallPreview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final String pend = c.pendWall!;
    final String name = pend == 'photo'
        ? 'Your photo'
        : pend == 'theme'
        ? 'Match theme'
        : kWallList.where((KT x) => x.k == pend).firstOrNull?.t ?? '';
    Widget bg;
    if (pend == 'photo' && c.pendPhoto != null) {
      bg = Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.file(File(c.pendPhoto!.path), fit: BoxFit.cover),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[whiteA(.3), whiteA(.2)],
              ),
            ),
          ),
        ],
      );
    } else {
      final WallSpec spec = pend == 'theme'
          ? (c.mode == 'custom'
                ? makeTheme(c.customBase, c.customCombo).wall
                : kLookDefs[c.preset]!.wall.spec)
          : (kWalls[pend]?.spec ?? p.wall);
      bg = CustomPaint(painter: WallPainter(spec));
    }
    final TcPalette gp = p.copyWith(g: .6);
    return Rise(
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Glass(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('Preview · $name', style: rtStyle(context, 16)),
              ),
              SizedBox(
                height: 236,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(child: bg),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: whiteA(.9)),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Tc(
                          p: gp,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Glass(
                                radius: 18,
                                blur: true,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: <Widget>[
                                    Container(
                                      width: 38,
                                      height: 38,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        gradient: LinearGradient(
                                          begin: const Alignment(-.45, -1),
                                          end: const Alignment(.45, 1),
                                          colors: <Color>[p.acc2, p.acc3],
                                        ),
                                      ),
                                      child: const Ic(
                                        'building',
                                        size: IcSize.s,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: RTx(
                                        c.companyName,
                                        'Tally Connected',
                                        titleSize: 15,
                                        subStyle: ts(12, c: p.ink3),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              Glass(
                                radius: 25,
                                height: 50,
                                blur: true,
                                fill: whiteA(.2),
                                child: _tabLabels(p),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Btn(
                        label: 'Cancel',
                        kind: BtnKind.g,
                        onTap: c.cancelWall,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Btn(
                        label: 'Apply',
                        icon: 'check',
                        onTap: c.applyWall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
