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
import '../../data/accounting.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import '../../data/repositories/api_tally_repository.dart' show DataSet;
import '../../data/repositories/tally_repository.dart' show HistoryTotals;
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
    // Debounced search over the search text built once per item; filtered
    // and ordered once per data / filter / search change.
    final String q = c.q('itemQ').toLowerCase();
    final String mk =
        '${c.repo.version}|${all.length}|${c.itemsFilter}|$q|${c.prefsVersion}';
    final List<Item> rows = c.memo<List<Item>>(
      'items-rows',
      mk,
      () => all
          .where(
            (Item x) =>
                (c.itemsFilter == 'all' || x.st == c.itemsFilter) &&
                (q.isEmpty ||
                    (x.search.isNotEmpty ? x.search : x.name.toLowerCase())
                        .contains(q)),
          )
          .toList(),
    );
    final ({List<Item> rows, int hidden, VoidCallback unhide}) v = c
        .memo<({List<Item> rows, int hidden, VoidCallback unhide})>(
          'items-view',
          mk,
          () => c.listView<Item>('items', rows, (Item x) => x.name),
        );
    final (num, int, int) stats = c.memo<(num, int, int)>(
      'items-stats',
      '${c.repo.version}|${all.length}',
      () => (
        all.fold<num>(0, (num s, Item x) => s + x.worth),
        all.where((Item x) => x.st == 'low').length,
        all.where((Item x) => x.st == 'out').length,
      ),
    );
    final List<(String, String)> segs = <(String, String)>[
      ('all', 'All (${all.length})'),
      ('low', 'Low (${stats.$2})'),
      ('out', 'Finished (${stats.$3})'),
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
                        AmtText(
                          inr(stats.$1),
                          align: Alignment.centerLeft,
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
                  StatBox('${stats.$2}', 'Running low', kind: 'b'),
                  StatBox('${stats.$3}', 'Finished', kind: 'n'),
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
          onChanged: (String s) => c.setQuery('itemQ', s),
          placeholder: 'Search item name',
          icon: 'scan',
          onAction: () => c.say(
            c.repo.isRemote
                ? 'Barcode search is not available yet on the server'
                : 'Point the camera at a barcode',
          ),
        ),
        lazyList<Item>(
          rows: v.rows,
          row: (BuildContext context, Item x) => LRow(
            list: 'items',
            lk: x.name,
            child: RowX(
              onTap: () {
                if (c.guardTap('items', x.name)) c.openItem(x.name);
              },
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
                            stockLabel(x),
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
                              ' ${rateLabel(x)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
          hidden: v.hidden,
          unhide: v.unhide,
          empty: rows.isEmpty
              ? c.emptyText(DataSet.items, 'No item found.')
              : null,
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
    // 16K+ parties: debounced search over the text built once per party;
    // filtered, sorted and ordered once per data / filter / search change.
    final String q = c.q('partyQ').toLowerCase();
    final String mk =
        '${c.repo.version}|${pool.length}|${c.partyFilter}|${c.partySort}|$q|${c.prefsVersion}';
    final List<Party> rows = c.memo<List<Party>>('party-rows', mk, () {
      final List<Party> r = pool
          .where(
            (Party x) =>
                (c.partyFilter == 'all' || x.type == c.partyFilter) &&
                (q.isEmpty ||
                    (x.search.isNotEmpty ? x.search : x.name.toLowerCase())
                        .contains(q)),
          )
          .toList();
      if (c.partySort == 'amt') {
        r.sort((Party a, Party b) => b.bal.abs().compareTo(a.bal.abs()));
      } else {
        r.sort(
          (Party a, Party b) =>
              a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      }
      return r;
    });
    final ({List<Party> rows, int hidden, VoidCallback unhide}) v = c
        .memo<({List<Party> rows, int hidden, VoidCallback unhide})>(
          'party-view',
          mk,
          () => c.listView<Party>('party', rows, (Party x) => x.name),
        );
    final (int, int) pc = c.memo<(int, int)>(
      'party-counts',
      '${c.repo.version}|${pool.length}',
      () => (
        pool.where((Party x) => x.type == 'c').length,
        pool.where((Party x) => x.type == 's').length,
      ),
    );
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
            StatBox('${pc.$1}', 'Customers', glass: true),
            StatBox('${pc.$2}', 'Suppliers', glass: true),
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
          onChanged: (String s) => c.setQuery('partyQ', s),
          placeholder: 'Search party name',
          icon: 'sort',
          onAction: () =>
              c.update(() => c.partySort = c.partySort == 'amt' ? 'az' : 'amt'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
          child: Text(sortLabel, style: rsStyle(context)),
        ),
        lazyList<Party>(
          rows: v.rows,
          row: (BuildContext context, Party x) => LRow(
            list: 'party',
            lk: x.name,
            // The pin is part of the row layout (beside the amount), so it
            // stays inside the card and never covers name or balance.
            pinOverlay: false,
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
                if (c.isPinned('party', x.name)) ...<Widget>[
                  const PinBadge(),
                  const SizedBox(width: 8),
                ],
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * .38,
                  ),
                  child: x.bal == 0 && c.repo.isRemote
                      // No pending bills: the ledger's Tally opening balance
                      // (`/ledger` opening_balance; size only — the server
                      // sends no Dr/Cr).
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: <Widget>[
                            Text(
                              'Opening Balance',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: rsStyle(context, 12),
                            ),
                            const SizedBox(height: 4),
                            AmtText(
                              x.opening == null ? '—' : inr(x.opening!.abs()),
                              style: amtStyle(context),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: <Widget>[
                            AmtText(
                              inr(x.bal.abs()),
                              style: amtStyle(
                                context,
                                cls: x.bal == 0
                                    ? ''
                                    : (x.type == 'c' ||
                                              (x.type == 'o' && x.bal > 0)
                                          ? 'in'
                                          : 'out'),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              x.bal == 0
                                  ? 'Settled'
                                  : (x.type == 'c' ||
                                            (x.type == 'o' && x.bal > 0)
                                        ? 'They owe you'
                                        : 'You owe'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: rsStyle(context, 12),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          hidden: v.hidden,
          unhide: v.unhide,
          empty: rows.isEmpty
              ? c.emptyText(DataSet.ledgers, 'No party found.')
              : null,
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
    String tallyBal(num? v) =>
        v == null ? '—' : '${inr(v.abs())} (Dr/Cr not sent)';
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
    return FlowScr(
      foot: <Widget>[
        // No WhatsApp backend: bill reminders live in Outstanding.
        Expanded(
          child: Btn(
            label: other ? 'New Entry' : (pc ? 'New Sale' : 'New Purchase'),
            icon: 'plus',
            kind: BtnKind.a,
            onTap: () => other
                ? c.go('newEntry')
                : (pc
                      ? c.startFlow('sales', <String, String>{
                          'sParty': p0.name,
                        })
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
              onTap: remote
                  ? () => c.repo.loadPartyDetail(p0, force: true)
                  : c.refreshNow,
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
                    AmtText(
                      remote
                          ? inr(p0.bal.abs())
                          : '${inr(p0.bal)}${p0.bal != 0 ? (pc ? ' Dr' : ' Cr') : ''}',
                      align: Alignment.centerLeft,
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
          lazyList<BillLine>(
            margin: const EdgeInsets.only(top: 12),
            rows: items,
            row: (BuildContext context, BillLine l) => RowX(
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
                    <String>[
                      l.qty,
                      l.rate,
                    ].where((String x) => x.isNotEmpty).join(' · '),
                  ),
                ),
                Text(inr(l.amt), style: amtStyle(context)),
              ],
            ),
            empty: loadingText.isNotEmpty
                ? loadingText
                : (remote
                      ? 'No items bought or sold by this party.'
                      : 'No item details in sample data.'),
          ),
        if (c.partyTab == 'vouchers')
          lazyList<Voucher>(
            margin: const EdgeInsets.only(top: 12),
            rows: pv,
            row: (BuildContext context, Voucher v) => RowX(
              onTap: () => c.go('entryDetail', <String, Object?>{
                'entry':
                    (v.guid == null ? null : c.repo.voucherByKey(v.key)) ?? v,
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
            empty: loadingText.isNotEmpty
                ? loadingText
                : (remote
                      ? 'No entries for this party.'
                      : 'No entries this month.'),
          ),
      ],
    );
  }
}

/// ITEM DETAIL (new): stock from Tally, sales / purchase summary from the
/// item lines of the loaded voucher history, and the item's customers /
/// suppliers from `/ledger-items/item/:itemName/parties`.
class ItemDetailScreen extends ConsumerWidget {
  const ItemDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TcPalette p = Tc.of(context);
    final Item? it = c.repo
        .items()
        .where((Item x) => x.name == c.itemSel)
        .firstOrNull;
    if (it == null) {
      return Scr(
        children: <Widget>[
          const BackNav(),
          EmptyBox(c.emptyText(DataSet.items, 'No item selected.')),
        ],
      );
    }
    // Sales / purchase summary from the whole voucher history, streamed on
    // opening this screen (never at startup); figures show once read.
    final HistoryTotals? h = c.repo.historyTotals;
    final bool scanned = h != null && h.done;
    final ItemTrade sales = h?.itemTrade(it.name, 'sales') ?? ItemAcc().trade;
    final ItemTrade purch =
        h?.itemTrade(it.name, 'purchase') ?? ItemAcc().trade;
    final ItemDetail? det = c.repo.itemDetail(it.name);
    final bool complete = h != null && h.complete;
    String rate(num? v) => v == null ? '—' : inr(v);
    String q(num v) => it.unit.isEmpty ? qty(v) : '${qty(v)} ${it.unit}';
    List<(String, String, bool)> trade(
      ItemTrade t,
      bool sale,
    ) => <(String, String, bool)>[
      (
        sale ? 'Total sales value' : 'Total purchase value',
        inr(t.amount),
        true,
      ),
      (sale ? 'Quantity sold' : 'Quantity bought', q(t.qty), false),
      (sale ? 'Last sale date' : 'Last purchase date', dmy(t.lastDate), false),
      ('Last rate', rate(t.lastRate), false),
      ('Lowest rate', rate(t.minRate), false),
      ('Highest rate', rate(t.maxRate), false),
      (sale ? 'Sales vouchers' : 'Purchase vouchers', '${t.vouchers}', false),
    ];
    const List<(String, String)> tabs = <(String, String)>[
      ('summary', 'Summary'),
      ('customers', 'Customers'),
      ('suppliers', 'Suppliers'),
    ];
    Widget parties(List<ItemParty>? list, bool sale) {
      if (list == null) {
        return EmptyBox(
          c.repo.isRemote
              ? c.emptyText(DataSet.item, 'Loading…')
              : 'No party details in sample data.',
        );
      }
      if (list.isEmpty) {
        return EmptyBox(
          sale
              ? 'No customer has bought this item yet.'
              : 'No supplier has sold this item to you yet.',
        );
      }
      return lazyList<ItemParty>(
        rows: list,
        row: (BuildContext context, ItemParty x) => RowX(
          cross: CrossAxisAlignment.start,
          children: <Widget>[
            Av(initials(x.name), size: Av.sm),
            Expanded(
              child: RTx(
                x.name,
                <String>[
                  if (x.lastDate != null)
                    '${sale ? 'Last sold' : 'Last bought'}: ${dmy(x.lastDate)}',
                  if (x.avgRate != null) 'Avg rate ${inr(paise(x.avgRate!))}',
                  if (x.invoices != null)
                    '${x.invoices} ${x.invoices == 1 ? 'voucher' : 'vouchers'}',
                ].join(' · '),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text('Total qty', style: rsStyle(context, 12)),
                Text(
                  x.qty == null ? '—' : q(x.qty!),
                  style: rtStyle(context, 15),
                ),
                const SizedBox(height: 2),
                Text(
                  x.amount == null ? '—' : inr(x.amount),
                  style: amtStyle(context, size: 14.5),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Scr(
      children: <Widget>[
        BackNav(
          actions: <Widget>[
            CBtn(
              'sync',
              onTap: () => c.repo.isRemote
                  ? c.repo.loadItemDetail(it, force: true)
                  : c.refreshNow(),
            ),
            CBtn('share', onTap: () => c.shareDoc(docItem(it, c.companyName))),
          ],
        ),
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
                    child: RTx(
                      it.name,
                      <String>[
                        if ((it.group ?? '').isNotEmpty) it.group!,
                        'Unit: ${it.unit.isEmpty ? 'not set' : it.unit}',
                      ].join(' · '),
                      titleSize: 19,
                    ),
                  ),
                ],
              ),
              Tot(
                bg: mix(p.cat('items'), .08),
                margin: const EdgeInsets.only(top: 12),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('Closing stock', style: rsStyle(context)),
                          AmtText(
                            stockLabel(it),
                            align: Alignment.centerLeft,
                            style: amtStyle(context, size: 20),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * .45,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Text('Stock value', style: rsStyle(context)),
                          AmtText(
                            inr(it.worth),
                            style: amtStyle(context, size: 20),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Seg(
          margin: const EdgeInsets.only(top: 14, bottom: 14),
          items: tabs.map(((String, String) e) => e.$2).toList(),
          selected: tabs.indexWhere(((String, String) e) => e.$1 == c.itemTab),
          onPick: (int i) => c.update(() => c.itemTab = tabs[i].$1),
        ),
        if (c.itemTab == 'summary') ...<Widget>[
          const Sec('Item', margin: EdgeInsets.fromLTRB(8, 0, 8, 8)),
          KvList(<(String, String, bool)>[
            ('Item name', it.name, false),
            ('Stock group', (it.group ?? '').isEmpty ? '—' : it.group!, false),
            ('HSN / SAC', it.hsn ?? 'Not set in Tally', false),
            (
              'GST rate',
              it.gst == null ? 'Not set in Tally' : '${qty(it.gst!)}%',
              false,
            ),
            ('Stock rate (Tally)', rateLabel(it), false),
            (
              'Opening stock',
              it.openingQty == null ? '—' : q(it.openingQty!),
              false,
            ),
            (
              'Opening value',
              it.openingValue == null ? '—' : inr(it.openingValue),
              false,
            ),
            ('Closing stock', stockLabel(it), false),
            ('Closing value', it.value == null ? '—' : inr(it.value), false),
          ]),
          // Sales / purchase summary: read from the voucher history when
          // this item opens (with progress).
          if (!scanned)
            InfoBox(
              h == null || h.running
                  ? 'Reading sales and purchases'
                        '${h == null ? '' : ' · ${h.scanned}${h.total == null ? '' : ' of ${h.total}'} vouchers'}…'
                  : (h.error ?? 'Reading sales and purchases…'),
              icon: 'info',
              margin: const EdgeInsets.only(top: 14),
            ),
          if (scanned && !complete)
            const InfoBox(
              'The voucher history could not be read in full, so these totals may be incomplete.',
              icon: 'info',
              margin: EdgeInsets.only(top: 14),
            ),
          if (scanned) ...<Widget>[
            const Sec('Sales summary'),
            KvList(trade(sales, true)),
            const Sec('Purchase summary'),
            KvList(trade(purch, false)),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
            child: Text(
              'Summed from the item lines of your synced Tally vouchers.',
              style: rsStyle(context, 12.5),
            ),
          ),
        ],
        if (c.itemTab == 'customers') parties(det?.customers, true),
        if (c.itemTab == 'suppliers') parties(det?.suppliers, false),
      ],
    );
  }
}
