// NOTIFICATIONS (627–649), CREATE WORKSPACE (651–675), MANAGE WORKSPACES
// (677–700) and NEW ENTRY (702–716).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/design/tc_fields.dart';
import '../../core/design/tc_icons.dart';
import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import '../widgets/common.dart';

class NotifsScreen extends ConsumerWidget {
  const NotifsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final List<Notif> base = c.notifs
        .where((Notif n) => c.nFilter == 'all' || n.unread)
        .toList();
    final ({List<Notif> rows, int hidden, VoidCallback unhide}) v = c
        .listView<Notif>('notifs', base, (Notif n) => n.id);
    return Scr(
      children: <Widget>[
        BackNav(actions: <Widget>[CBtn('sync', onTap: c.refreshNow)]),
        const H1('Alerts', afterNav: true),
        Sub(c.unread > 0 ? '${c.unread} unread' : 'All read'),
        Row(
          children: <Widget>[
            Expanded(
              child: Seg(
                items: const <String>['All', 'Unread'],
                selected: c.nFilter == 'all' ? 0 : 1,
                onPick: (int i) =>
                    c.update(() => c.nFilter = i == 0 ? 'all' : 'unread'),
                margin: EdgeInsets.zero,
              ),
            ),
            const SizedBox(width: 10),
            ChipBtn(
              'Mark all read',
              icon: 'check',
              color: p.navy,
              height: 50,
              onTap: c.markAll,
            ),
          ],
        ),
        GlassList(
          margin: const EdgeInsets.only(top: 18),
          children: <Widget>[
            for (final Notif n in v.rows)
              LRow(
                list: 'notifs',
                lk: n.id,
                child: RowX(
                  onTap: () {
                    if (c.guardTap('notifs', n.id)) c.openNotif(n);
                  },
                  cross: CrossAxisAlignment.start,
                  children: <Widget>[
                    Ico(
                      n.ic,
                      size: IcoSize.xs,
                      color: p.cat(n.c),
                      icon: IcSize.s,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                child: Text(n.t, style: rtStyle(context)),
                              ),
                              const SizedBox(width: 10),
                              Text(n.time, style: rsStyle(context)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(n.b, style: ts(14.5, h: 1.3, c: p.ink2)),
                        ],
                      ),
                    ),
                    if (n.unread)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: p.neg,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (v.hidden > 0)
              HidRow('${v.hidden} hidden · Unhide', onTap: v.unhide),
            if (v.rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  'You have read everything.',
                  textAlign: TextAlign.center,
                  style: rsStyle(context, 15),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// `.wsfeat` chooser tile.
class _WsFeat extends StatelessWidget {
  const _WsFeat({
    required this.t,
    required this.ic,
    required this.c,
    required this.sel,
    required this.onTap,
  });
  final String t, ic, c;
  final bool sel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Tap(
      onTap: onTap,
      child: Glass(
        child: Stack(
          fit: StackFit.passthrough,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
              child: Column(
                children: <Widget>[
                  Ico(ic, size: IcoSize.xs, color: p.cat(c), icon: IcSize.s),
                  const SizedBox(height: 6),
                  Text(
                    t,
                    textAlign: TextAlign.center,
                    style: ts(12.5, w: w700, c: p.ink),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sel ? p.neg : p.acc,
                  shape: BoxShape.circle,
                ),
                child: Ic(
                  sel ? 'minus' : 'plus',
                  size: IcSize.xs,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CreateWsScreen extends ConsumerWidget {
  const CreateWsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final bool isF = c.wsTab == 'f';
    final List<String> chosen = isF ? c.wsSel : c.wsSums;
    final List<String> all = isF
        ? kShortcuts.keys.toList()
        : kSums.keys.toList();
    ({String t, String ic, String c}) meta(String k) {
      if (isF) {
        final Shortcut s = kShortcuts[k]!;
        return (t: s.t, ic: s.ic, c: s.c);
      }
      final SumCard s = kSums[k]!;
      return (t: s.t, ic: s.ic, c: s.c);
    }

    Widget tile(String k, bool sel) {
      final ({String t, String ic, String c}) m = meta(k);
      return _WsFeat(
        t: m.t,
        ic: m.ic,
        c: m.c,
        sel: sel,
        onTap: () => c.toggleWsKey(k),
      );
    }

    final bool cannot = c.f('wsName').trim().isEmpty || c.wsSel.isEmpty;
    return FlowScr(
      foot: <Widget>[
        Expanded(
          flex: 10,
          child: Btn(label: 'Cancel', kind: BtnKind.g, onTap: c.back),
        ),
        Expanded(
          flex: 17,
          child: Btn(
            label: 'Save workspace',
            icon: 'check',
            enabled: !cannot,
            onTap: c.saveWs,
          ),
        ),
      ],
      children: <Widget>[
        NavRow(
          children: <Widget>[
            CBtn('chevL', onTap: c.back),
            Expanded(
              child: Text('Make a workspace', style: rtStyle(context, 19)),
            ),
            ChipBtn(
              'Reset',
              color: p.acc,
              onTap: () => c.update(() {
                c.wsSel = <String>[];
                c.wsSums = <String>[];
                c.form['wsName'] = '';
              }),
            ),
          ],
        ),
        const Sub(
          'A workspace is your own Home screen. Pick the shortcuts and money cards you want.',
          margin: EdgeInsets.fromLTRB(4, 0, 4, 16),
        ),
        Fld(
          label: 'Workspace name',
          child: Inp(
            value: c.f('wsName'),
            onChanged: (String v) => c.setF('wsName', v),
            placeholder: 'e.g. Sales Desk',
            icon: 'grid',
          ),
        ),
        Seg(
          items: <String>[
            'Shortcuts (${c.wsSel.length})',
            'Money cards (${c.wsSums.length})',
          ],
          selected: isF ? 0 : 1,
          onPick: (int i) => c.update(() => c.wsTab = i == 0 ? 'f' : 'm'),
        ),
        const Sec('Chosen', margin: EdgeInsets.fromLTRB(8, 0, 8, 8)),
        if (chosen.isEmpty) const EmptyBox('Nothing yet. Tap below to add.'),
        if (chosen.isNotEmpty)
          Grid(
            cols: 4,
            gap: 10,
            children: <Widget>[for (final String k in chosen) tile(k, true)],
          ),
        const Sec('Tap to add'),
        Grid(
          cols: 4,
          gap: 10,
          children: <Widget>[
            for (final String k in all.where((String k) => !chosen.contains(k)))
              tile(k, false),
          ],
        ),
      ],
    );
  }
}

class ManageWsScreen extends ConsumerWidget {
  const ManageWsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    return FlowScr(
      foot: <Widget>[
        Expanded(
          child: Btn(
            label: 'Make a new workspace',
            icon: 'plus',
            onTap: c.goCreateWs,
          ),
        ),
      ],
      children: <Widget>[
        NavRow(
          children: <Widget>[
            CBtn('chevL', onTap: c.back),
            Expanded(child: Text('Workspaces', style: rtStyle(context, 19))),
          ],
        ),
        const Sub(
          'Workspaces are your own Home screens. Switching one never changes your accounts data.',
          margin: EdgeInsets.fromLTRB(4, 0, 4, 16),
        ),
        for (final Workspace w in c.wsList)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Glass(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Ico('grid', size: IcoSize.sm, color: p.navy),
                      const SizedBox(width: 12),
                      Expanded(
                        child: RTx(
                          w.name,
                          '${w.feats.length} shortcuts · ${w.sums.length} money cards${w.builtin ? ' · built-in' : ''}',
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (w.id == c.activeWs)
                        const Bdg('In use', kind: BadgeKind.ok, dot: true)
                      else
                        ChipBtn(
                          'Use',
                          color: p.navy,
                          height: 40,
                          onTap: () => c.useWs(w),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _BoldLine(
                    'Shortcuts:',
                    w.feats.map((String k) => kShortcuts[k]?.t ?? k).join(', '),
                  ),
                  _BoldLine(
                    'Money cards:',
                    w.sums.map((String k) => kSums[k]?.t ?? k).join(', '),
                  ),
                  if (!w.builtin)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Btn(
                              label: 'Edit',
                              icon: 'edit',
                              iconSize: IcSize.s,
                              kind: BtnKind.g,
                              height: 46,
                              fontSize: 15,
                              onTap: () => c.editWs(w),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Btn(
                              label: 'Delete',
                              icon: 'trash',
                              iconSize: IcSize.s,
                              kind: BtnKind.plain,
                              bg: mix(p.neg, .10),
                              color: p.neg,
                              height: 46,
                              fontSize: 15,
                              onTap: () => c.delWs(w),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _BoldLine extends StatelessWidget {
  const _BoldLine(this.b, this.rest);
  final String b, rest;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text: b,
            style: const TextStyle(fontWeight: w700),
          ),
          TextSpan(text: ' $rest'),
        ],
      ),
      style: ts(14, h: 1.3, c: Tc.of(context).ink3),
    ),
  );
}

class NewEntryScreen extends ConsumerWidget {
  const NewEntryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    const List<(String, String, String, String, String)> tiles =
        <(String, String, String, String, String)>[
          ('Sale', 'You sold goods', 'bag', 'sales', 'sales'),
          ('Purchase', 'You bought goods', 'cart', 'purchase', 'purchase'),
          ('Money In', 'Money came to you', 'in', 'receipt', 'receipt'),
          ('Money Out', 'Money went out', 'out', 'payment', 'payment'),
        ];
    return Scr(
      children: <Widget>[
        const BackNav(),
        const H1('New Entry', afterNav: true),
        const Sub('What do you want to write down?'),
        Grid(
          cols: 2,
          children: <Widget>[
            for (final (String, String, String, String, String) e in tiles)
              Tap(
                onTap: () => c.startFlow(e.$5),
                child: Glass(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 168),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 18,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Ico(
                          e.$3,
                          color: p.cat(e.$4),
                          box: 66,
                          radius: 22,
                          icon: IcSize.xl,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          e.$1,
                          textAlign: TextAlign.center,
                          style: ts(19, w: w800, h: 1.1, c: p.ink),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          e.$2,
                          textAlign: TextAlign.center,
                          style: ts(14, c: p.ink3),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        GlassRow(
          margin: const EdgeInsets.only(top: 12),
          onTap: () => c.startFlow('journal'),
          children: <Widget>[
            Ico('book', size: IcoSize.sm, color: p.cat('journal')),
            const Expanded(
              child: RTx(
                'Adjustment',
                'Journal entry · move money between accounts',
              ),
            ),
            chevR(),
          ],
        ),
        const InfoBox(
          'Tap a picture to start. You can go back at any step — nothing is sent until you tap Save.',
          margin: EdgeInsets.only(top: 18, bottom: 14),
        ),
      ],
    );
  }
}
