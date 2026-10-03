// ITEMS (1027–1052), PARTY (1054–1081), PARTY DETAIL (1083–1108);
// view models 2563–2596.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/design/tc_fields.dart';
import '../../core/design/tc_icons.dart';
import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';
import '../../core/share/share_doc.dart';
import '../../core/utils/format.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import '../../data/repositories/api_tally_repository.dart' show DataSet;
import '../widgets/common.dart';

/// `.tot.stat` (centred column) / `.glass.stat` (left).
class StatBox extends StatelessWidget {
  const StatBox(
    this.value,
    this.label, {
    super.key,
    this.kind,
    this.bg,
    this.glass = false,
    this.top,
  });
  final String value, label;
  final String? kind;
  final Color? bg;
  final bool glass;
  final Widget? top;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    // The prototype runtime wraps bound values in `<span class=sc-interp>`, so
    // `.stat span` (13 px / 600 / ink3) also styles the number inside `<b>`.
    final TextStyle st = ts(13, w: w600, c: p.ink3);
    final Widget col = Column(
      crossAxisAlignment: glass
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        ?top,
        // …while the `<b>` keeps its 24 px / 800 line box.
        Text(
          value,
          style: st,
          strutStyle: const StrutStyle(
            fontFamily: kFont,
            fontSize: 24,
            fontWeight: w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: glass ? TextAlign.start : TextAlign.center,
          style: st,
        ),
      ],
    );
    if (glass) return Glass(padding: const EdgeInsets.all(12), child: col);
    return Tot(
      kind: kind ?? 'a',
      bg: bg,
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(12),
      child: col,
    );
  }
}

/// Search input + square glass action (`.iw.grow` + `.cbtn` 56).
class SearchRow extends StatelessWidget {
  const SearchRow({
    super.key,
    required this.value,
    required this.onChanged,
    required this.placeholder,
    required this.icon,
    this.onAction,
  });
  final String value;
  final ValueChanged<String> onChanged;
  final String placeholder, icon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Inp(
            value: value,
            onChanged: onChanged,
            placeholder: placeholder,
            icon: 'search',
          ),
        ),
        const SizedBox(width: 10),
        CBtn(
          icon,
          size: 56,
          radius: 16,
          color: Tc.of(context).navy,
          onTap: onAction,
        ),
      ],
    ),
  );
}

class ItemsScreen extends ConsumerWidget {
  const ItemsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final List<Item> all = c.repo.items();
    final String q = c.f('itemQ').toLowerCase();
    final List<Item> rows = all
        .where(
          (Item x) =>
              (c.itemsFilter == 'all' || x.st == c.itemsFilter) &&
              (q.isEmpty || x.name.toLowerCase().contains(q)),
        )
        .toList();
    final ({List<Item> rows, int hidden, VoidCallback unhide}) v = c
        .listView<Item>('items', rows, (Item x) => x.name);
    final List<(String, String)> segs = <(String, String)>[
      ('all', 'All (${all.length})'),
      ('low', 'Low (${all.where((Item x) => x.st == 'low').length})'),
      ('out', 'Finished (${all.where((Item x) => x.st == 'out').length})'),
    ];
    return Scr(
      children: <Widget>[
        BackNav(
          actions: <Widget>[
            CBtn(
              'file',
              onTap: () => c.previewDoc(docItems(rows, c.companyName)),
            ),
            CBtn(
              'share',
              onTap: () => c.shareDoc(docItems(rows, c.companyName)),
            ),
            CBtn('sync', onTap: c.refreshNow),
          ],
        ),
        const TitleBadge('Items'),
        const Sub('Your stock from Tally'),
        Glass(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Ico('box', size: IcoSize.sm, color: p.cat('items')),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('Total stock value', style: rsStyle(context)),
                        Text(
                          inr(
                            all.fold<num>(0, (num s, Item x) => s + x.worth),
                          ),
                          style: amtStyle(context, size: 26),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Grid(
                cols: 3,
                gap: 10,
                children: <Widget>[
                  StatBox('${all.length}', 'Items'),
                  StatBox(
                    '${all.where((Item x) => x.st == 'low').length}',
                    'Running low',
                    kind: 'b',
                  ),
                  StatBox(
                    '${all.where((Item x) => x.st == 'out').length}',
                    'Finished',
                    kind: 'n',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Seg(
          items: segs.map(((String, String) e) => e.$2).toList(),
          selected: segs.indexWhere(
            ((String, String) e) => e.$1 == c.itemsFilter,
          ),
          onPick: (int i) => c.update(() => c.itemsFilter = segs[i].$1),
        ),
        SearchRow(
          value: c.f('itemQ'),
          onChanged: (String s) => c.setF('itemQ', s),
          placeholder: 'Search item name',
          icon: 'scan',
          onAction: () => c.say(
            c.repo.isRemote
                ? 'Barcode search is not available yet on the server'
                : 'Point the camera at a barcode',
          ),
        ),
        GlassList(
          children: <Widget>[
            for (final Item x in v.rows)
              LRow(
                list: 'items',
                lk: x.name,
                child: RowX(
                  children: <Widget>[
                    Ico(
                      'box',
                      size: IcoSize.xs,
                      color: p.cat('items'),
                      icon: IcSize.s,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            x.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: rtStyle(context),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: <Widget>[
                              Bdg(
                                x.stock > 0
                                    ? '${qty(x.stock)} ${x.unit}'
                                    : 'Finished',
                                kind: x.st == 'ok'
                                    ? BadgeKind.ok
                                    : (x.st == 'low'
                                          ? BadgeKind.warn
                                          : BadgeKind.bad),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  ' ${inr(x.rate)} / ${x.unit}',
                                  maxLines: 1,
                                  style: rsStyle(context),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Text(inr(x.worth), style: amtStyle(context)),
                  ],
                ),
              ),
            if (v.hidden > 0)
              HidRow('${v.hidden} hidden · Unhide', onTap: v.unhide),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  c.emptyText(DataSet.items, 'No item found.'),
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

class PartyScreen extends ConsumerWidget {
  const PartyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final List<Party> pool = c.partyPool();
    final String q = c.f('partyQ').toLowerCase();
    final List<Party> rows = pool
        .where(
          (Party x) =>
              (c.partyFilter == 'all' || x.type == c.partyFilter) &&
              (q.isEmpty || x.name.toLowerCase().contains(q)),
        )
        .toList();
    if (c.partySort == 'amt') {
      rows.sort((Party a, Party b) => b.bal.abs().compareTo(a.bal.abs()));
    } else {
      rows.sort(
        (Party a, Party b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    }
    final ({List<Party> rows, int hidden, VoidCallback unhide}) v = c
        .listView<Party>('party', rows, (Party x) => x.name);
    const List<(String, String)> segs = <(String, String)>[
      ('all', 'All'),
      ('c', 'Customers'),
      ('s', 'Suppliers'),
    ];
    final String sortLabel = c.partySort == 'amt'
        ? 'Sorted by balance · tap ⇅ for A–Z'
        : 'Sorted A–Z · tap ⇅ for balance';
    return Scr(
      children: <Widget>[
        BackNav(
          actions: <Widget>[
            CBtn(
              'file',
              onTap: () => c.previewDoc(docParties(v.rows, c.companyName)),
            ),
            CBtn('sync', onTap: c.refreshNow),
            CBtn('userPlus', onTap: () => c.openNewParty()),
          ],
        ),
        const TitleBadge('Party'),
        const Sub('Customers and suppliers'),
        Grid(
          cols: 3,
          gap: 10,
          children: <Widget>[
            StatBox('${pool.length}', 'All', glass: true),
            StatBox(
              '${pool.where((Party x) => x.type == 'c').length}',
              'Customers',
              glass: true,
            ),
            StatBox(
              '${pool.where((Party x) => x.type == 's').length}',
              'Suppliers',
              glass: true,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Seg(
          items: segs.map(((String, String) e) => e.$2).toList(),
          selected: segs.indexWhere(
            ((String, String) e) => e.$1 == c.partyFilter,
          ),
          onPick: (int i) => c.update(() => c.partyFilter = segs[i].$1),
        ),
        SearchRow(
          value: c.f('partyQ'),
          onChanged: (String s) => c.setF('partyQ', s),
          placeholder: 'Search party name',
          icon: 'sort',
          onAction: () =>
              c.update(() => c.partySort = c.partySort == 'amt' ? 'az' : 'amt'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
          child: Text(sortLabel, style: rsStyle(context)),
        ),
        GlassList(
          children: <Widget>[
            for (final Party x in v.rows)
              LRow(
                list: 'party',
                lk: x.name,
                child: RowX(
                  onTap: () {
                    if (c.guardTap('party', x.name)) {
                      c.go('partyDetail', <String, Object?>{
                        'party': x.name,
                        'partyTab': 'summary',
                      });
                    }
                  },
                  children: <Widget>[
                    Av(initials(x.name)),
                    Expanded(
                      child: RTx(
                        x.name,
                        '${x.kindLabel} · ${x.city.isNotEmpty ? x.city : (x.group ?? '')}',
                        ell: true,
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Text(
                          inr(x.bal.abs()),
                          style: amtStyle(
                            context,
                            cls: x.bal == 0
                                ? ''
                                : (x.type == 'c' || (x.type == 'o' && x.bal > 0)
                                      ? 'in'
                                      : 'out'),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          x.bal == 0
                              ? (c.repo.isRemote ? 'No pending bills' : 'Settled')
                              : (x.type == 'c' || (x.type == 'o' && x.bal > 0)
                                    ? 'They owe you'
                                    : 'You owe'),
                          style: rsStyle(context, 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (v.hidden > 0)
              HidRow('${v.hidden} hidden · Unhide', onTap: v.unhide),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  c.emptyText(DataSet.ledgers, 'No party found.'),
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

class PartyDetailScreen extends ConsumerWidget {
  const PartyDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final List<Party> pool = c.partyPool();
    final Party? pf =
        pool.where((Party x) => x.name == c.party).firstOrNull ??
        c.repo.parties().firstOrNull;
    if (pf == null) {
      return const Scr(
        children: <Widget>[BackNav(), EmptyBox('No party selected.')],
      );
    }
    final Party p0 = pf;
    final bool pc = p0.type == 'c';
    final bool other = p0.type == 'o';
    // Other ledgers: positive pending balance = they owe you.
    final bool owesYou = pc || (other && p0.bal > 0);
    final bool remote = c.repo.isRemote;
    final PartyDetail? det = p0.guid == null
        ? null
        : c.repo.partyDetail(p0.guid!);
    final List<Voucher> pv = remote
        ? (det?.entries ?? const <Voucher>[])
        : c.repo.vouchers().where((Voucher v) => v.party == p0.name).toList();
    // Tally balances arrive without Dr/Cr; the size is shown as synced.
    String tallyBal(num? v) => v == null ? '—' : '${inr(v.abs())} (Dr/Cr not sent)';
    const List<(String, String)> tabs = <(String, String)>[
      ('summary', 'Summary'),
      ('items', 'Items'),
      ('vouchers', 'Entries'),
    ];
    final bool sbt = p0.name == 'Shree Balaji Traders';
    final List<(String, String, bool)> rows = remote
        ? <(String, String, bool)>[
            ('Group', p0.group ?? '—', false),
            if (p0.email != null) ('Email', p0.email!, false),
            if (p0.phone != null) ('Phone', p0.phone!, false),
            ('Opening balance (Tally)', tallyBal(p0.opening), false),
            ('Closing balance (Tally)', tallyBal(p0.closing), false),
            ('Last entry', dmy(p0.lastDate), false),
            ('Pending bills', '${det?.bills.length ?? '—'}', false),
          ]
        : sbt
        ? const <(String, String, bool)>[
            ('Group', 'Customers (Sundry Debtors)', false),
            ('City', 'Mumbai', false),
            ('GSTIN', '27AAKFS2291M1Z8', false),
            (
              'Address',
              'Shop No. 12, Market Road, Kurla, Mumbai – 400070',
              false,
            ),
            ('Contact person', 'Rakesh Agarwal', false),
            ('Phone', '+91 98298 48278', false),
            ('Email', 'accounts@shreebalaji.in', false),
            ('Credit time', '30 days', false),
            ('Opening balance (1 Apr 2026)', '₹12,540 Dr', false),
          ]
        : <(String, String, bool)>[
            (
              'Group',
              pc
                  ? 'Customers (Sundry Debtors)'
                  : 'Suppliers (Sundry Creditors)',
              false,
            ),
            ('City', p0.city, false),
            ('Entries this month', '${pv.length}', false),
          ];
    final List<BillLine> items = remote
        ? (det?.items ?? const <BillLine>[])
        : (sbt ? c.repo.billLines('Sales 9') : const <BillLine>[]);
    final String loadingText = c.emptyText(DataSet.party, '');
    Widget empty(String t) => Padding(
      padding: const EdgeInsets.all(18),
      child: Text(t, textAlign: TextAlign.center, style: rsStyle(context, 15)),
    );
    return FlowScr(
      foot: <Widget>[
        Expanded(
          flex: 10,
          child: Btn(
            label: 'Remind',
            icon: 'bell',
            kind: BtnKind.g,
            color: p.acc,
            onTap: () => c.say(
              remote
                  ? 'WhatsApp reminders are not available yet on the server'
                  : 'Reminder sent on WhatsApp to ${p0.name}',
            ),
          ),
        ),
        Expanded(
          flex: 17,
          child: Btn(
            label: other ? 'New Entry' : (pc ? 'New Sale' : 'New Purchase'),
            icon: 'plus',
            kind: BtnKind.a,
            onTap: () => other
                ? c.go('newEntry')
                : (pc
                      ? c.startFlow('sales', <String, String>{'sParty': p0.name})
                      : c.startFlow('purchase', <String, String>{
                          'pParty': p0.name,
                        })),
          ),
        ),
      ],
      children: <Widget>[
        BackNav(
          actions: <Widget>[
            CBtn(
              'sync',
              onTap: remote ? () => c.repo.loadPartyDetail(p0) : c.refreshNow,
            ),
            CBtn(
              'file',
              onTap: () => c.previewDoc(
                docParty(p0, c.companyName, rows, pv, c.today, remote: remote),
              ),
            ),
            CBtn(
              'share',
              onTap: () => c.shareDoc(
                docParty(p0, c.companyName, rows, pv, c.today, remote: remote),
              ),
            ),
          ],
        ),
        Seg(
          margin: const EdgeInsets.only(top: 2, bottom: 14),
          items: tabs.map(((String, String) e) => e.$2).toList(),
          selected: tabs.indexWhere(((String, String) e) => e.$1 == c.partyTab),
          onPick: (int i) => c.update(() => c.partyTab = tabs[i].$1),
        ),
        Glass(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Av(initials(p0.name), size: Av.lg),
                  const SizedBox(width: 12),
                  Expanded(
                    child: RTx(
                      p0.name,
                      '${p0.kindLabel} · ${p0.city.isNotEmpty ? p0.city : (p0.group ?? '')}',
                      titleSize: 19,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Bdg('Active', kind: BadgeKind.ok, dot: true),
                ],
              ),
              Tot(
                bg: owesYou ? mix(p.pos, .10) : mix(p.warn, .09),
                margin: const EdgeInsets.only(top: 12, bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${remote ? 'Outstanding (pending bills)' : 'Balance'} · as on ${dmy(c.today)}',
                      style: rsStyle(context),
                    ),
                    Text(
                      remote
                          ? inr(p0.bal.abs())
                          : '${inr(p0.bal)}${p0.bal != 0 ? (pc ? ' Dr' : ' Cr') : ''}',
                      style: amtStyle(
                        context,
                        cls: owesYou ? 'big in' : 'big out',
                      ),
                    ),
                    Text(
                      p0.bal == 0
                          ? (remote ? 'No pending bills' : 'All settled')
                          : (owesYou ? 'They owe you' : 'You owe them'),
                      style: ts(13.5, w: w700, c: p.ink3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (c.partyTab == 'summary')
          KvList(rows, margin: const EdgeInsets.only(top: 12)),
        if (c.partyTab == 'items')
          GlassList(
            margin: const EdgeInsets.only(top: 12),
            children: <Widget>[
              for (final BillLine l in items)
                RowX(
                  children: <Widget>[
                    Ico(
                      'box',
                      size: IcoSize.xs,
                      color: p.cat('items'),
                      icon: IcSize.s,
                    ),
                    Expanded(
                      child: RTx(
                        l.name,
                        <String>[l.qty, l.rate]
                            .where((String x) => x.isNotEmpty)
                            .join(' · '),
                      ),
                    ),
                    Text(inr(l.amt), style: amtStyle(context)),
                  ],
                ),
              if (items.isEmpty)
                empty(
                  loadingText.isNotEmpty
                      ? loadingText
                      : (remote
                            ? 'No items bought or sold by this party.'
                            : 'No item details in sample data.'),
                ),
            ],
          ),
        if (c.partyTab == 'vouchers')
          GlassList(
            margin: const EdgeInsets.only(top: 12),
            children: <Widget>[
              for (final Voucher v in pv)
                RowX(
                  onTap: () =>
                      c.go('entryDetail', <String, Object?>{
                        'entry':
                            c.repo
                                .vouchers()
                                .where((Voucher x) => x.guid != null && x.guid == v.guid)
                                .firstOrNull ??
                            v,
                      }),
                  children: <Widget>[
                    Ico(
                      kKinds[v.kind]!.ic,
                      size: IcoSize.xs,
                      color: p.cat(kKinds[v.kind]!.c),
                      icon: IcSize.s,
                    ),
                    Expanded(
                      child: RTx(
                        '${v.type ?? kKinds[v.kind]!.t} · ${v.no}',
                        vDate(v),
                      ),
                    ),
                    Text(inr(v.amt), style: amtStyle(context)),
                  ],
                ),
              if (pv.isEmpty)
                empty(
                  loadingText.isNotEmpty
                      ? loadingText
                      : (remote ? 'No entries for this party.' : 'No entries this month.'),
                ),
            ],
          ),
      ],
    );
  }
}
