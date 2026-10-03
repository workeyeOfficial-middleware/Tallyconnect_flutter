// Overlays (Main.dc.html 1412–1608): side menu, search / company / pick /
// new-party / item-picker / add-item / team sheets, PDF viewer, hidden-cards
// panel, card menu, list drag ghost and the toast.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/design/tc_fields.dart';
import '../../core/design/tc_icons.dart';
import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';
import '../../core/utils/format.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import '../screens/account_screens.dart' show CompanyRow;
import '../screens/insight_screens.dart' show kTS;
import '../widgets/common.dart';
import 'doc_viewer.dart';

/// Builds the active overlay (`state.overlay`).
class OverlayLayer extends ConsumerWidget {
  const OverlayLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    return switch (c.overlay) {
      'menu' => const SideMenu(),
      'search' => const SearchSheet(),
      'company' => const CompanySheet(),
      'pick' => const PickSheetView(),
      'newParty' => const NewPartySheet(),
      'picker' => const ItemPickerSheet(),
      'addItem' => const AddItemSheet(),
      'invite' => const InviteSheet(),
      'newUser' => const NewUserSheet(),
      'member' => const MemberSheet(),
      'pdf' => const PdfViewer(),
      'doc' => const DocViewer(),
      _ => const SizedBox.shrink(),
    };
  }
}

// ------------------------------------------------------------------- menu

/// `.mrow` menu row.
class MRow extends StatelessWidget {
  const MRow({
    super.key,
    required this.ic,
    required this.icColor,
    required this.t,
    this.onTap,
    this.trailing,
    this.textColor,
    this.chev = true,
  });
  final String ic, t;
  final Color icColor;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? textColor;
  final bool chev;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    final Widget r = Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: <Widget>[
          Ico(ic, size: IcoSize.xs, color: icColor, icon: IcSize.s),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              t,
              style: ts(16, w: w700, c: textColor ?? p.ink),
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 12),
            trailing!,
          ],
          if (chev && onTap != null && trailing == null) ...<Widget>[
            const SizedBox(width: 12),
            const Ic('chevR', size: IcSize.xs, color: kChev),
          ],
        ],
      ),
    );
    return onTap == null ? r : Tap(onTap: onTap, radius: 16, child: r);
  }
}

class _MenuList extends StatelessWidget {
  const _MenuList(this.children);
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Glass(
    radius: 20,
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Column(
      children: <Widget>[
        for (int i = 0; i < children.length; i++) ...<Widget>[
          if (i > 0) listDivider(.06),
          children[i],
        ],
      ],
    ),
  );
}

class SideMenu extends ConsumerWidget {
  const SideMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final MediaQueryData mq = MediaQuery.of(context);
    final int unread = c.unread;
    final List<(String, String, String, String, int)> acct =
        <(String, String, String, String, int)>[
          ('Companies', 'building', 'navy', 'companies', 0),
          ('Sales Team', 'team', 'team', 'team', 0),
          ('Reports', 'chart', 'reports', 'reports', 0),
          ('Settings', 'gear', 'settings', 'settings', 0),
          ('Alerts', 'bell', 'acc', 'notifs', unread),
          ('Workspaces', 'grid', 'navy', 'manageWs', 0),
          ('Refer a friend', 'gift', 'sales', 'refer', 0),
        ];
    const BorderRadius br = BorderRadius.horizontal(right: Radius.circular(32));
    return Stack(
      children: <Widget>[
        Positioned.fill(child: Scrim(onTap: c.closeOv)),
        Positioned(
          top: 0,
          bottom: 0,
          left: 0,
          width: math.min(320, mq.size.width - 40),
          child: Enter(
            ms: 420,
            curve: const Cubic(.2, .95, .25, 1),
            builder: (double t, Widget ch) => FractionalTranslation(
              translation: Offset(-(1 - t) * 1.05, 0),
              child: ch,
            ),
            child: ClipRRect(
              borderRadius: br,
              child: BackdropFilter(
                filter: backdrop(26, 1.85),
                child: Glass(
                  borderRadius: br,
                  fill: p.sheetFill,
                  shadows: const <BoxShadow>[],
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      14,
                      math.max(30, mq.padding.top + 12),
                      14,
                      30 + mq.padding.bottom,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Row(
                            children: <Widget>[
                              const LMark(size: 38, radius: 12, icon: IcSize.s),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Brand(size: 19, align: TextAlign.left),
                              ),
                              CBtn('close', small: true, onTap: c.closeOv),
                            ],
                          ),
                        ),
                        GlassRow(
                          radius: 20,
                          onTap: () => c.go('settings', <String, Object?>{
                            'setTab': 'profile',
                          }),
                          children: <Widget>[
                            const Av('W', size: 50, accent: true),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    'workk72002',
                                    style: rtStyle(context, 17),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'workk72002@gmail.com',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: rsStyle(context),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      'See profile ›',
                                      style: ts(14, w: w700, c: p.acc),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Sec('My account'),
                        _MenuList(<Widget>[
                          for (final (String, String, String, String, int) m
                              in acct)
                            MRow(
                              ic: m.$2,
                              icColor: p.cat(m.$3),
                              t: m.$1,
                              onTap: () => c.go(m.$4),
                              trailing: m.$5 > 0
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        Container(
                                          constraints: const BoxConstraints(
                                            minWidth: 24,
                                          ),
                                          height: 24,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                          ),
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: p.neg,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Text(
                                            '${m.$5}',
                                            style: ts(
                                              12.5,
                                              w: w800,
                                              c: Colors.white,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        const Ic(
                                          'chevR',
                                          size: IcSize.xs,
                                          color: kChev,
                                        ),
                                      ],
                                    )
                                  : null,
                            ),
                        ]),
                        const Sec('Plan'),
                        _MenuList(<Widget>[
                          MRow(
                            ic: 'card',
                            icColor: p.acc,
                            t: 'Plans & billing',
                            onTap: () => c.go('billing'),
                            trailing: const Bdg(
                              'Enterprise',
                              kind: BadgeKind.acc,
                            ),
                          ),
                          MRow(
                            ic: 'lock',
                            icColor: p.cat('settings'),
                            t: 'Change password',
                            onTap: c.goForgot,
                          ),
                        ]),
                        const Sec('Support'),
                        _MenuList(<Widget>[
                          MRow(
                            ic: 'help',
                            icColor: p.cat('sales'),
                            t: 'Help',
                            onTap: () => c.go('help'),
                          ),
                          MRow(
                            ic: 'info',
                            icColor: p.cat('settings'),
                            t: 'Version',
                            trailing: Text('19.6.2', style: rsStyle(context)),
                          ),
                          MRow(
                            ic: 'logout',
                            icColor: p.neg,
                            t: 'Log out',
                            textColor: p.neg,
                            chev: false,
                            onTap: c.logout,
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- sheets

class SearchSheet extends ConsumerWidget {
  const SearchSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final String q = c.f('q').toLowerCase().trim();
    final List<SearchEntry> results = kSearch
        .where(
          (SearchEntry r) =>
              q.isEmpty || '${r.t} ${r.s}'.toLowerCase().contains(q),
        )
        .toList();
    return Sheet(
      top: 60,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SheetHead('Search'),
          Inp(
            value: c.f('q'),
            onChanged: (String v) => c.setF('q', v),
            placeholder: 'Type a screen, e.g. Party or Sales',
            icon: 'search',
          ),
          GlassList(
            margin: const EdgeInsets.only(top: 12),
            children: <Widget>[
              for (final SearchEntry r in results)
                RowX(
                  onTap: () {
                    c.setF('q', '');
                    if (r.f != null) {
                      c.startFlow(r.f!);
                    } else {
                      c.run(r.a!);
                    }
                  },
                  children: <Widget>[
                    Ico(
                      r.ic,
                      size: IcoSize.xs,
                      color: p.cat(r.c),
                      icon: IcSize.s,
                    ),
                    Expanded(child: RTx(r.t, r.s)),
                    chevR(),
                  ],
                ),
              if (results.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    'Nothing found. Try “sale” or “party”.',
                    textAlign: TextAlign.center,
                    style: rsStyle(context, 15),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class CompanySheet extends ConsumerWidget {
  const CompanySheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    return Sheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SheetHead(
            'Choose company',
            sub: 'Reports, bills and stock switch to the company you pick.',
          ),
          for (final Company co in c.repo.companies())
            CompanyRow(co, sub: 'Tally company'),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Btn(
                    label: 'Refresh',
                    icon: 'sync',
                    iconSize: IcSize.s,
                    kind: BtnKind.g,
                    onTap: () => c.say('Company list refreshed from Tally'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Btn(label: 'Manage', onTap: () => c.go('companies')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PickSheetView extends ConsumerWidget {
  const PickSheetView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final PickSheet? pk = c.pick;
    if (pk == null) return const SizedBox.shrink();
    final String q = c.f('pq').toLowerCase();
    final String cur = c.f(pk.key);
    return Sheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SheetHead(pk.title),
          Inp(
            value: c.f('pq'),
            onChanged: (String v) => c.setF('pq', v),
            placeholder: 'Search',
            icon: 'search',
          ),
          GlassList(
            margin: const EdgeInsets.only(top: 12),
            children: <Widget>[
              for (final Opt o in pk.opts.where(
                (Opt o) => q.isEmpty || o.t.toLowerCase().contains(q),
              ))
                RowX(
                  onTap: () => c.choosePick(o.t, o.s),
                  children: <Widget>[
                    Av(initials(o.t), size: Av.sm),
                    Expanded(child: RTx(o.t, o.s)),
                    if (o.t == cur) Ic('check', color: p.cat('receipt')),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class NewPartySheet extends ConsumerWidget {
  const NewPartySheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    return Sheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SheetHead(
            'Add new party',
            sub: c.npType == 's'
                ? 'A supplier you buy from'
                : 'A customer you sell to',
          ),
          Fld(
            label: 'Name',
            req: true,
            child: Inp(
              value: c.f('npName'),
              onChanged: (String v) => c.setF('npName', v),
              placeholder: 'e.g. Shree Ganesh Traders',
            ),
          ),
          Fld(
            label: 'Mobile number',
            child: Inp(
              value: c.f('npPhone'),
              onChanged: (String v) => c.setF('npPhone', v),
              placeholder: '+91',
              keyboard: TextInputType.phone,
            ),
          ),
          Fld(
            label: 'City',
            child: Inp(
              value: c.f('npCity'),
              onChanged: (String v) => c.setF('npCity', v),
              placeholder: 'e.g. Mumbai',
            ),
          ),
          Btn(
            label: 'Save party',
            icon: 'check',
            enabled: c.f('npName').trim().isNotEmpty,
            onTap: c.saveParty,
          ),
        ],
      ),
    );
  }
}

class ItemPickerSheet extends ConsumerWidget {
  const ItemPickerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final List<Line> cl = c.lines[c.flowType] ?? <Line>[];
    final String q = c.f('pickQ').toLowerCase();
    return Sheet(
      top: 40,
      flex: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SheetHead(
              'Add items',
              sub: 'Tap to pick · use − and + for quantity',
              size: 20,
              closeFirst: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Inp(
              value: c.f('pickQ'),
              onChanged: (String v) => c.setF('pickQ', v),
              placeholder: 'Search item name',
              icon: 'search',
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: DashBtn(
              onTap: () => c.openOverlay('addItem'),
              color: mix(p.acc, .35),
              align: MainAxisAlignment.start,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: <Widget>[
                  Ic('plus', color: p.acc),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Add new item',
                          style: ts(15, w: w800, c: p.acc),
                        ),
                        Text(
                          'Item not in Tally? Make it here',
                          style: ts(12.5, w: w600, c: p.ink3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Sec('Items from Tally'),
                  for (final Item it in c.repo.items().where(
                    (Item it) => q.isEmpty || it.name.toLowerCase().contains(q),
                  ))
                    Builder(
                      builder: (BuildContext context) {
                        final int idx = cl.indexWhere(
                          (Line l) => l.name == it.name,
                        );
                        final bool sel = idx >= 0;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Glass(
                            border: sel
                                ? Border.all(color: p.navy, width: 2)
                                : null,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                RowX(
                                  onTap: () => c.togglePickItem(it),
                                  children: <Widget>[
                                    Av(
                                      initials(it.name),
                                      size: Av.sm,
                                      gradient: LinearGradient(
                                        begin: const Alignment(-.35, -1),
                                        end: const Alignment(.35, 1),
                                        colors: sel
                                            ? <Color>[p.acc2, p.acc3]
                                            : <Color>[p.navy2, p.navy],
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(
                                            it.name,
                                            style: rtStyle(context),
                                          ),
                                          const SizedBox(height: 2),
                                          Text.rich(
                                            TextSpan(
                                              text:
                                                  '${it.stock > 0 ? '${it.stock} ${it.unit} in stock' : 'Out of stock'} · ',
                                              children: <InlineSpan>[
                                                TextSpan(
                                                  text:
                                                      '${inr(it.rate)} / ${it.unit}',
                                                  style: const TextStyle(
                                                    fontWeight: w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            style: rsStyle(context),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Tk(sel),
                                  ],
                                ),
                                if (sel)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      14,
                                      0,
                                      14,
                                      12,
                                    ),
                                    child: Row(
                                      children: <Widget>[
                                        Expanded(
                                          child: Text(
                                            'Quantity',
                                            style: ts(13.5, w: w700, c: p.ink3),
                                          ),
                                        ),
                                        Stepper2(
                                          label: '${cl[idx].qty} ${it.unit}',
                                          onDec: () => c.stepPickItem(it, -1),
                                          onInc: () => c.stepPickItem(it, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          _SheetFoot(
            children: <Widget>[
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('${cl.length} items picked', style: rsStyle(context)),
                    Text(inr(c.totals(cl).total), style: rtStyle(context, 20)),
                  ],
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 140),
                child: Btn(
                  label: 'Done',
                  icon: 'check',
                  expand: false,
                  onTap: c.closeOv,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// `.sheet .foot` — flex sheets have no side padding, so the footer spans
/// the full sheet width.
class _SheetFoot extends StatelessWidget {
  const _SheetFoot({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Foot(inSheet: true, children: children);
}

class _CatChips extends StatelessWidget {
  const _CatChips({
    required this.items,
    required this.selected,
    required this.onPick,
  });
  final List<String> items;
  final String selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final String v in items)
          GestureDetector(
            onTap: () => onPick(v),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: v == selected ? p.navy : whiteA(.85),
                borderRadius: BorderRadius.circular(19),
                border: Border.all(color: v == selected ? p.navy : navyA(.12)),
              ),
              child: Center(
                widthFactor: 1,
                child: Text(
                  v,
                  style: ts(
                    14,
                    w: w700,
                    c: v == selected ? Colors.white : p.ink2,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class AddItemSheet extends ConsumerWidget {
  const AddItemSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final num nq = numOf(c.f('niQty')),
        nr = numOf(c.f('niRate')),
        nd = numOf(c.f('niDisc'));
    final num nsub = nq * nr * (1 - nd / 100), ngst = nsub * c.niGst / 100;
    final bool off = c.f('niName').trim().isEmpty || nq == 0 || nr == 0;
    void back() => c.openOverlay('picker');
    return Sheet(
      top: 40,
      flex: true,
      onClose: c.closeOv,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SheetHead(
              'Add new item',
              sub: 'Makes the item and adds it to this bill',
              onClose: back,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Fld(
                    label: 'Item type',
                    req: true,
                    child: _CatChips(
                      items: const <String>[
                        'General',
                        'Wires & Cables',
                        'Lighting',
                        'Switches',
                        'Switchgear',
                        'Fans',
                      ],
                      selected: c.niCat,
                      onPick: (String v) => c.update(() => c.niCat = v),
                    ),
                  ),
                  Fld(
                    label: 'Item name',
                    req: true,
                    child: Inp(
                      value: c.f('niName'),
                      onChanged: (String v) => c.setF('niName', v),
                      placeholder: 'e.g. Supreme PVC Pipe 1 inch',
                    ),
                  ),
                  Fld(
                    label: 'Unit',
                    req: true,
                    child: _CatChips(
                      items: const <String>['PCS', 'NOS', 'COIL', 'BOX', 'MTR'],
                      selected: c.niUnit,
                      onPick: (String v) => c.update(() => c.niUnit = v),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Fld(
                          label: 'Quantity',
                          req: true,
                          child: Inp(
                            value: c.f('niQty'),
                            onChanged: (String v) => c.setF('niQty', v),
                            keyboard: TextInputType.number,
                            formatters: kDigits,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Fld(
                          label: 'Rate (₹)',
                          req: true,
                          child: Inp(
                            value: c.f('niRate'),
                            onChanged: (String v) => c.setF('niRate', v),
                            placeholder: '0.00',
                            keyboard: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            formatters: kDecimal,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Fld(
                          label: 'HSN / SAC',
                          child: Inp(
                            value: c.f('niHsn'),
                            onChanged: (String v) => c.setF('niHsn', v),
                            placeholder: 'e.g. 9405',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Fld(
                          label: 'Discount (%)',
                          child: Inp(
                            value: c.f('niDisc'),
                            onChanged: (String v) => c.setF('niDisc', v),
                            keyboard: TextInputType.number,
                            formatters: kDecimal,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Fld(
                    label: 'GST rate',
                    child: _CatChips(
                      items: const <String>['0%', '5%', '12%', '18%', '28%'],
                      selected: '${c.niGst}%',
                      onPick: (String v) => c.update(
                        () => c.niGst = int.parse(v.replaceAll('%', '')),
                      ),
                    ),
                  ),
                  Tot(
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text('Amount'),
                              Text(
                                'Before GST ${inr2(nsub)} + GST ${inr2(ngst)}',
                                style: ts(
                                  13.5,
                                  w: w600,
                                  h: 1.3,
                                  c: Tc.of(context).ink3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          inr2(nsub + ngst),
                          style: amtStyle(context, size: 22),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          _SheetFoot(
            children: <Widget>[
              Expanded(
                flex: 10,
                child: Btn(label: 'Cancel', kind: BtnKind.g, onTap: back),
              ),
              Expanded(
                flex: 17,
                child: Btn(
                  label: 'Add item',
                  icon: 'plus',
                  enabled: !off,
                  onTap: c.addNewItem,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class InviteSheet extends ConsumerWidget {
  const InviteSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    return Sheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SheetHead(
            'Invite by email',
            sub: 'They get a link to join your team as Sales Rep.',
          ),
          Fld(
            label: 'Email address',
            child: Inp(
              value: c.f('iEmail'),
              onChanged: (String v) => c.setF('iEmail', v),
              placeholder: 'name@example.com',
              icon: 'mail',
              keyboard: TextInputType.emailAddress,
            ),
          ),
          Btn(
            label: 'Send invite',
            icon: 'send',
            enabled: RegExp(r'.+@.+\..+').hasMatch(c.f('iEmail')),
            onTap: c.sendInvite,
          ),
        ],
      ),
    );
  }
}

class NewUserSheet extends ConsumerWidget {
  const NewUserSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    return Sheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SheetHead(
            'Add person',
            sub: 'Make a login for someone in your team.',
          ),
          Fld(
            label: 'Full name',
            req: true,
            child: Inp(
              value: c.f('nuName'),
              onChanged: (String v) => c.setF('nuName', v),
              placeholder: 'e.g. Rohit Kumar',
              icon: 'person',
            ),
          ),
          Fld(
            label: 'Mobile number',
            child: Inp(
              value: c.f('nuPhone'),
              onChanged: (String v) => c.setF('nuPhone', v),
              placeholder: '+91',
              icon: 'phone',
              keyboard: TextInputType.phone,
            ),
          ),
          Btn(
            label: 'Add to team',
            icon: 'check',
            enabled: c.f('nuName').trim().isNotEmpty,
            onTap: c.saveUser,
          ),
        ],
      ),
    );
  }
}

class MemberSheet extends ConsumerWidget {
  const MemberSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final Member m =
        c.team.where((Member x) => x.id == c.member).firstOrNull ??
        c.team.first;
    final List<(String, String, Color, VoidCallback)> actions = m.st == 'active'
        ? <(String, String, Color, VoidCallback)>[
            (
              'Turn off access',
              'lock',
              p.neg,
              () => c.setMemberSt(m, 'off', '${m.name} turned off'),
            ),
          ]
        : m.st == 'off'
        ? <(String, String, Color, VoidCallback)>[
            (
              'Turn on access',
              'check',
              p.pos,
              () => c.setMemberSt(m, 'active', '${m.name} turned on'),
            ),
          ]
        : <(String, String, Color, VoidCallback)>[
            (
              'Send invite again',
              'send',
              p.navy,
              () {
                c.closeOv();
                c.say('Invite sent again');
              },
            ),
            ('Cancel invite', 'close', p.neg, () => c.cancelInvite(m)),
          ];
    return Sheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: <Widget>[
                Av(initials(m.name), size: Av.lg),
                const SizedBox(width: 12),
                Expanded(child: RTx(m.name, m.email, titleSize: 20)),
                const SizedBox(width: 12),
                Bdg(kTS[m.st]!.$1, kind: kTS[m.st]!.$2, dot: true),
              ],
            ),
          ),
          _MenuList(<Widget>[
            for (final (String, String, Color, VoidCallback) a in actions)
              MRow(
                ic: a.$2,
                icColor: a.$3,
                t: a.$1,
                textColor: a.$3,
                chev: false,
                onTap: a.$4,
              ),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Btn(label: 'Close', kind: BtnKind.g, onTap: c.closeOv),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------- pdf

class PdfViewer extends ConsumerWidget {
  const PdfViewer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final MediaQueryData mq = MediaQuery.of(context);
    final PdfInfo pd =
        c.pdf ??
        const PdfInfo(
          party: 'Shree Balaji Traders',
          no: 'Sales 9',
          date: '21 Sep 2026',
          due: '06 Oct 2026',
          total: 112100,
          kind: 'Sales bill',
          city: 'Mumbai',
          recv: true,
        );
    final bool s9 = pd.no == 'Sales 9';
    final int taxable = s9 ? 95000 : (pd.total / 1.18).round();
    final int cg = s9 ? 8550 : ((pd.total - taxable) / 2).round();
    final bool purchase =
        pd.recv == false || RegExp('PI|Purchase').hasMatch(pd.kind);
    final String city = '${pd.city}${s9 ? ' · GSTIN: 27AAKFS2291M1Z8' : ''}';
    final List<(String, String, String, String, String, String)> lines = s9
        ? <(String, String, String, String, String, String)>[
            for (int i = 0; i < kSales9.length; i++)
              (
                '${i + 1}',
                kSales9[i].name,
                kSales9[i].hsn,
                kSales9[i].qty,
                kSales9[i].rate,
                inr(kSales9[i].amt),
              ),
          ]
        : <(String, String, String, String, String, String)>[
            ('1', 'Goods as per Tally entry', '—', '—', '—', inr(taxable)),
          ];
    const Color ink = Color(0xFF16203A), mute = Color(0xFF6B7690);
    TextStyle t9([FontWeight w = w400, Color col = ink, double sz = 9]) =>
        ts(sz, w: w, c: col, h: 1.45);
    Widget lt(Widget a, Widget b) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Flexible(child: a),
        const SizedBox(width: 8),
        b,
      ],
    );
    Widget cell(String s, {bool r = false, bool head = false, int flex = 1}) =>
        Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
            child: Text(
              s,
              textAlign: r ? TextAlign.right : TextAlign.left,
              style: head ? t9(w700, ink, 8) : t9(),
            ),
          ),
        );
    final Widget paper = Container(
      width: 300,
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: <BoxShadow>[
          css(0, 20, 40, 0, Colors.black.withValues(alpha: .4)),
        ],
      ),
      child: DefaultTextStyle(
        style: t9(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            lt(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    c.companyName,
                    style: ts(12, w: w800, c: p.acc),
                  ),
                  const Text(
                    'Unit 4, Laxmi Industrial Estate, Andheri (E), Mumbai – 400093',
                  ),
                  const Text('GSTIN: 27AAGFG4417K1Z5'),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    purchase ? 'PURCHASE BILL' : 'TAX INVOICE',
                    style: t9(w800, ink, 11),
                  ),
                  Text.rich(
                    TextSpan(
                      text: 'No: ',
                      children: <InlineSpan>[
                        TextSpan(
                          text: pd.no,
                          style: const TextStyle(fontWeight: w700),
                        ),
                      ],
                    ),
                  ),
                  Text.rich(
                    TextSpan(
                      text: 'Date: ',
                      children: <InlineSpan>[
                        TextSpan(
                          text: pd.date,
                          style: const TextStyle(fontWeight: w700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 1,
              color: p.acc,
              margin: const EdgeInsets.symmetric(vertical: 8),
            ),
            lt(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    purchase ? 'BILL FROM' : 'BILLED TO',
                    style: t9(w400, mute, 7.5),
                  ),
                  Text(pd.party, style: t9(w800)),
                  Text(city),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text('DUE DATE', style: t9(w400, mute, 7.5)),
                  Text(pd.due, style: t9(w800)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              color: const Color(0xFFEEF1F8),
              child: Row(
                children: <Widget>[
                  cell('#', head: true),
                  cell('Item', head: true, flex: 5),
                  cell('HSN', head: true, flex: 2),
                  cell('Qty', head: true, r: true, flex: 2),
                  cell('Rate', head: true, r: true, flex: 2),
                  cell('Amount', head: true, r: true, flex: 3),
                ],
              ),
            ),
            for (final (String, String, String, String, String, String) l
                in lines)
              Container(
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFFE6E9F1))),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    cell(l.$1),
                    cell(l.$2, flex: 5),
                    cell(l.$3, flex: 2),
                    cell(l.$4, r: true, flex: 2),
                    cell(l.$5, r: true, flex: 2),
                    cell(l.$6, r: true, flex: 3),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 300 * .45 - 16),
              child: Column(
                children: <Widget>[
                  lt(const Text('Subtotal'), Text(inr(taxable))),
                  lt(const Text('CGST @ 9%'), Text(inr(cg))),
                  lt(const Text('SGST @ 9%'), Text(inr(cg))),
                  Container(
                    margin: const EdgeInsets.only(top: 3),
                    padding: const EdgeInsets.only(top: 3),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: ink)),
                    ),
                    child: lt(
                      Text('Total', style: t9(w800)),
                      Text(inr(pd.total), style: t9(w800)),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(5),
              color: const Color(0xFFEEF1F8),
              child: Text.rich(
                TextSpan(
                  text: 'Amount: ',
                  children: <InlineSpan>[
                    TextSpan(
                      text: inr(pd.total),
                      style: const TextStyle(fontWeight: w700),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            lt(
              Text(
                'Made with TallyConnect · prototype preview',
                style: t9(w400, mute, 7.5),
              ),
              Container(
                padding: const EdgeInsets.only(top: 2),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: ink)),
                ),
                child: Text('Authorised signatory', style: t9(w400, ink, 7.5)),
              ),
            ),
          ],
        ),
      ),
    );
    Widget ctl(String ic, VoidCallback f) => Tap(
      onTap: f,
      radius: 23,
      subtleHighlight: true,
      child: Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: whiteA(.14), shape: BoxShape.circle),
        child: Ic(ic, color: Colors.white),
      ),
    );
    return fadeIn(
      ColoredBox(
        color: const Color(0xFF1D2231),
        child: Column(
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                math.max(28, mq.padding.top + 8),
                16,
                12,
              ),
              child: Row(
                children: <Widget>[
                  CBtn(
                    'close',
                    glass: false,
                    bg: whiteA(.12),
                    color: Colors.white,
                    onTap: c.closeOv,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${pd.no.replaceFirst(' ', '_')}.pdf',
                          style: ts(16, w: w700, c: Colors.white),
                        ),
                        Opacity(
                          opacity: .7,
                          child: Text(
                            '1 page · A4 · ${pd.kind}',
                            style: ts(13, c: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  CBtn(
                    'share',
                    glass: false,
                    bg: whiteA(.12),
                    color: Colors.white,
                    onTap: () => c.shareDoc(c.pdfDoc),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: 10),
                child: Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: c.zoom / 100),
                    duration: const Duration(milliseconds: 350),
                    curve: const Cubic(.3, 1.4, .5, 1),
                    builder: (BuildContext context, double s, Widget? ch) =>
                        Transform.scale(
                          scale: s,
                          alignment: Alignment.topCenter,
                          child: ch,
                        ),
                    child: paper,
                  ),
                ),
              ),
            ),
            Container(
              margin: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                22 + mq.padding.bottom * .6,
              ),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: whiteA(.12),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                children: <Widget>[
                  ctl('minus', () => c.zoomBy(-20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${c.zoom}%',
                      textAlign: TextAlign.center,
                      style: ts(16, w: w800, c: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ctl('plus', () => c.zoomBy(20)),
                  const SizedBox(width: 10),
                  ctl('download', () => c.downloadDoc(c.pdfDoc)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------- floating glass layers

/// Water-glass surface used by the card menu and the hidden-cards panel.
class WaterGlass extends StatelessWidget {
  const WaterGlass({
    super.key,
    required this.child,
    required this.radius,
    this.padding = EdgeInsets.zero,
    this.blurPx = 7,
    this.sat = 2.3,
    this.bright = 1.08,
    this.contrast = 1.03,
    this.g0 = .3,
    this.g1 = .06,
    this.g2 = .14,
  });
  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final double blurPx, sat, bright, contrast, g0, g1, g2;

  @override
  Widget build(BuildContext context) {
    final BorderRadius br = BorderRadius.circular(radius);
    return Glass(
      borderRadius: br,
      blur: true,
      filter: backdrop(blurPx, sat, bright, contrast),
      gradient: LinearGradient(
        begin: const Alignment(-.35, -1),
        end: const Alignment(.35, 1),
        colors: <Color>[whiteA(g0), whiteA(g1), whiteA(g2)],
        stops: const <double>[0, .45, 1],
      ),
      border: Border.all(color: whiteA(.62)),
      sheenGradient: RadialGradient(
        center: const Alignment(-.64, -1),
        radius: .9,
        colors: <Color>[whiteA(.6), whiteA(0)],
        stops: const <double>[0, .62],
      ),
      shadows: <BoxShadow>[css(0, 24, 44, -18, navyA(.45))],
      padding: padding,
      child: child,
    );
  }
}

const List<Shadow> kMilk = <Shadow>[
  Shadow(
    color: Color.fromRGBO(255, 255, 255, .95),
    offset: Offset(0, 1),
    blurRadius: 1,
  ),
  Shadow(color: Color.fromRGBO(255, 255, 255, .75), blurRadius: 10),
];

class CardMenu extends ConsumerWidget {
  const CardMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final CMenu? m = c.cmenu;
    if (m == null) return const SizedBox.shrink();
    final CardInfo? info = c.infoFor(m.list, m.id);
    if (info == null) return const SizedBox.shrink();
    final bool pinned = c.isPinned(m.list, m.id);
    final List<(String, String, VoidCallback)> items =
        <(String, String, VoidCallback)>[
          (pinned ? 'Unpin' : 'Pin', 'pin', c.cmPin),
          ('Open', 'open', c.cmOpen),
          ('Drag', 'move', c.cmDrag),
          ('Hide', 'eyeOff', c.cmHide),
          ('Share', 'share', c.cmShare),
        ];
    return Stack(
      children: <Widget>[
        Positioned.fill(child: Scrim(onTap: c.closeCMenu, alpha: .06, ms: 200)),
        Positioned(
          left: m.x,
          top: m.y,
          width: 214,
          child: Enter(
            ms: 380,
            builder: (double t, Widget ch) {
              final double k = const Cubic(.3, 1.5, .5, 1).transform(t);
              return Opacity(
                opacity: t.clamp(0, 1),
                child: Transform.scale(scale: .84 + .16 * k, child: ch),
              );
            },
            child: WaterGlass(
              radius: 24,
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: whiteA(.55))),
                    ),
                    child: Row(
                      children: <Widget>[
                        Ico(
                          info.ic,
                          size: IcoSize.xs,
                          color: p.cat(info.c),
                          icon: IcSize.s,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            info.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ts(
                              16,
                              w: w700,
                              c: p.ink,
                            ).copyWith(shadows: kMilk),
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final (String, String, VoidCallback) it in items)
                    Tap(
                      onTap: it.$3,
                      radius: 14,
                      child: SizedBox(
                        height: 48,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: <Widget>[
                              Ic(it.$2, color: p.navy),
                              const SizedBox(width: 12),
                              Text(
                                it.$1,
                                style: ts(
                                  16,
                                  w: w700,
                                  c: p.ink,
                                ).copyWith(shadows: kMilk),
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
        ),
      ],
    );
  }
}

/// `.ghost.lghost`: the row following the finger during a list drag.
class ListGhost extends ConsumerWidget {
  const ListGhost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final DragPt? d = c.ldrag;
    if (d == null) return const SizedBox.shrink();
    final CardInfo? info = c.infoFor(d.list, d.id);
    if (info == null) return const SizedBox.shrink();
    return Positioned(
      left: d.x,
      top: d.y,
      child: IgnorePointer(
        child: FractionalTranslation(
          translation: const Offset(-.5, -.5),
          child: Transform.rotate(
            angle: 2.5 * math.pi / 180,
            child: Transform.scale(
              scale: 1.06,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Glass(
                  blur: true,
                  gradient: LinearGradient(
                    begin: const Alignment(-.35, -1),
                    end: const Alignment(.35, 1),
                    colors: <Color>[whiteA(.55), whiteA(.25)],
                  ),
                  shadows: <BoxShadow>[css(0, 30, 50, -18, navyA(.55))],
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Ico(
                        info.ic,
                        size: IcoSize.xs,
                        color: p.cat(info.c),
                        icon: IcSize.s,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          info.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ts(15, w: w800, c: p.ink),
                        ),
                      ),
                    ],
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

/// Floating "Hidden on Page N" panel (`.sheet.hpanel`).
class HiddenPanel extends ConsumerWidget {
  const HiddenPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final List<HiddenCard> list = c
        .hidList()
        .where((HiddenCard h) => h.page == c.hidPage)
        .toList();
    return Stack(
      children: <Widget>[
        Positioned.fill(child: Scrim(onTap: c.closeOv, alpha: .06, ms: 200)),
        Positioned(
          left: 12,
          right: 12,
          bottom: barBottom(context) + 80,
          child: Enter(
            ms: 460,
            curve: const Cubic(.2, .95, .25, 1),
            builder: (double t, Widget ch) => Transform.translate(
              offset: Offset(0, (1 - t) * 400),
              child: ch,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .7,
              ),
              child: WaterGlass(
                radius: 30,
                blurPx: 10,
                sat: 2.2,
                bright: 1.06,
                contrast: 1,
                g0: .34,
                g1: .1,
                g2: .2,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Grab(),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: RTx(
                                c.hidPage == 0
                                    ? 'Hidden on Page 1'
                                    : 'Hidden on Page ${c.hidPage + 1}',
                                'Tap Unhide to put a card back exactly where it was.',
                                titleSize: 20,
                                titleStyle: ts(
                                  20,
                                  w: w700,
                                  h: 1.25,
                                  c: p.ink,
                                ).copyWith(shadows: kMilk),
                                subStyle: ts(
                                  13.5,
                                  h: 1.3,
                                  c: p.ink3,
                                ).copyWith(shadows: kMilk),
                              ),
                            ),
                            const SizedBox(width: 12),
                            CBtn('close', small: true, onTap: c.closeOv),
                          ],
                        ),
                      ),
                      for (int i = 0; i < list.length; i++)
                        Builder(
                          builder: (BuildContext context) {
                            final ({String label, String ic, String c})? w = c
                                .widgetMeta(list[i].id);
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                border: i > 0
                                    ? Border(top: BorderSide(color: whiteA(.5)))
                                    : null,
                              ),
                              child: Row(
                                children: <Widget>[
                                  Ico(
                                    w?.ic ?? 'grid',
                                    size: IcoSize.xs,
                                    color: p.cat(w?.c ?? 'navy'),
                                    icon: IcSize.s,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      w?.label ?? list[i].id,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: ts(
                                        16,
                                        w: w700,
                                        c: p.ink,
                                      ).copyWith(shadows: kMilk),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  ChipBtn(
                                    'Unhide',
                                    icon: 'eye',
                                    height: 40,
                                    color: p.navy,
                                    onTap: () =>
                                        c.restoreHidden(<String>[list[i].id]),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      if (list.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Btn(
                            label: 'Unhide all',
                            onTap: () => c.restoreHidden(
                              list.map((HiddenCard h) => h.id).toList(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// `.toast`: pops in at the top for 2600 ms.
class ToastView extends ConsumerWidget {
  const ToastView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final String? t = c.toast;
    if (t == null) return const SizedBox.shrink();
    final double w = MediaQuery.sizeOf(context).width;
    return Positioned(
      top: math.max(18, MediaQuery.paddingOf(context).top + 6),
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Enter(
            ms: 420,
            builder: (double v, Widget ch) {
              final double k = const Cubic(.3, 1.5, .5, 1).transform(v);
              return Opacity(
                opacity: v.clamp(0, 1),
                child: Transform.translate(
                  offset: Offset(0, -16 * (1 - k)),
                  child: Transform.scale(scale: .94 + .06 * k, child: ch),
                ),
              );
            },
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: math.min(356, w - 34)),
              child: Glass(
                radius: 26,
                blur: true,
                padding: const EdgeInsets.fromLTRB(12, 12, 18, 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: p.acc,
                        shape: BoxShape.circle,
                      ),
                      child: const Ic(
                        'check',
                        size: IcSize.s,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        t,
                        style: ts(15, w: w700, c: p.ink),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
