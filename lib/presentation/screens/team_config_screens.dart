// SALES TEAM → Configure User: layout permissions (which columns a user
// sees) and selection permissions (which ledgers / vouchers / orders /
// items a user may see), saved for that one user on the existing server
// routes (see team_admin.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../core/design/tc_fields.dart';
import '../../core/design/tc_icons.dart';
import '../../core/design/tc_kit.dart';
import '../../core/design/tc_palette.dart';
import '../../core/network/api_client.dart';
import '../../core/share/share_doc.dart' show stockLabel;
import '../../core/utils/format.dart';
import '../../data/models/models.dart';
import '../../data/repositories/api_tally_repository.dart' show DataSet;
import '../../data/repositories/team_admin.dart';
import '../widgets/common.dart';
import 'insight_screens.dart' show kTS;

String _err(Object e) => e is ApiException ? e.userMessage : '$e';

/// Shown when no user is being configured (e.g. opened directly).
class _NoUser extends StatelessWidget {
  const _NoUser();

  @override
  Widget build(BuildContext context) => const Scr(
    children: <Widget>[BackNav(), EmptyBox('No team member selected.')],
  );
}

/// Loading / error row used by the three screens.
class _State extends StatelessWidget {
  const _State({this.loading = false, this.error, this.onRetry});
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final TcPalette p = Tc.of(context);
    if (loading) {
      return Glass(
        padding: const EdgeInsets.all(22),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: p.acc),
          ),
        ),
      );
    }
    return GlassRow(
      onTap: onRetry,
      children: <Widget>[
        Ico('sync', size: IcoSize.xs, color: p.neg, icon: IcSize.s),
        Expanded(child: RTx('Could not load', error ?? '')),
        if (onRetry != null)
          Text(
            'Retry',
            style: ts(14, w: w700, c: p.acc),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------ user hub

class TeamUserScreen extends ConsumerWidget {
  const TeamUserScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController c = ref.watch(appProvider);
    final TeamConfig? cfg = c.teamCfg;
    if (cfg == null) return const _NoUser();
    return ListenableBuilder(
      listenable: cfg,
      builder: (BuildContext context, _) {
        final TcPalette p = Tc.of(context);
        final Member m = cfg.member;
        final bool ready = !cfg.loading && cfg.error == null;
        Widget row(PermArea a, String title, String sub, String to) => RowX(
          onTap: ready
              ? () => c.go(to, <String, Object?>{'teamKind': a.kind})
              : null,
          children: <Widget>[
            Ico(a.icon, size: IcoSize.xs, color: p.cat(a.cat), icon: IcSize.s),
            Expanded(child: RTx(title, sub, ell: true)),
            chevR(),
          ],
        );
        return Scr(
          children: <Widget>[
            const BackNav(),
            const H1('Configure User', afterNav: true),
            const Sub('What this person can see'),
            Glass(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  Av(initials(m.name)),
                  const SizedBox(width: 12),
                  Expanded(child: RTx(m.name, m.email, ell: true)),
                  const SizedBox(width: 10),
                  // Status is shown as it is; configuring never changes it.
                  Bdg(
                    kTS[m.st]?.$1 ?? m.st,
                    kind: kTS[m.st]?.$2 ?? BadgeKind.info,
                    dot: true,
                  ),
                ],
              ),
            ),
            if (cfg.loading)
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: _State(loading: true),
              )
            else if (cfg.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: _State(error: cfg.error, onRetry: cfg.load),
              )
            else ...<Widget>[
              const Sec('Layout Permissions'),
              GlassList(
                children: <Widget>[
                  for (final PermArea a in kPermAreas)
                    row(a, a.layoutTitle, () {
                      final Map<String, bool> on = cfg.columns(a);
                      final int n = on.values.where((bool v) => v).length;
                      return '$n of ${on.length} fields shown';
                    }(), 'teamLayout'),
                ],
              ),
              const Sec('Selection Permissions'),
              GlassList(
                children: <Widget>[
                  for (final PermArea a in kPermAreas)
                    row(
                      a,
                      a.selectTitle,
                      cfg.selError[a.kind] != null
                          ? 'Could not load · tap to retry'
                          : '${cfg.selected[a.kind]?.length ?? 0} selected',
                      'teamSelect',
                    ),
                ],
              ),
              InfoBox(
                'Changes are saved only for ${m.name}. Admins always see everything.',
                icon: 'info',
                margin: const EdgeInsets.only(top: 18, bottom: 14),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------- layouts

class TeamLayoutScreen extends ConsumerStatefulWidget {
  const TeamLayoutScreen({super.key});

  @override
  ConsumerState<TeamLayoutScreen> createState() => _TeamLayoutState();
}

class _TeamLayoutState extends ConsumerState<TeamLayoutScreen> {
  Map<String, bool>? _draft;
  String? _kind;

  @override
  Widget build(BuildContext context) {
    final AppController c = ref.watch(appProvider);
    final TeamConfig? cfg = c.teamCfg;
    if (cfg == null) return const _NoUser();
    final PermArea a = permArea(c.teamKind);
    if (_kind != a.kind) {
      _kind = a.kind;
      _draft = null;
    }
    return ListenableBuilder(
      listenable: cfg,
      builder: (BuildContext context, _) {
        final TcPalette p = Tc.of(context);
        final Map<String, bool> saved = cfg.columns(a);
        final Map<String, bool> d = _draft ??= Map<String, bool>.of(saved);
        final bool changed = a.fields.any(
          (LayoutField f) => d[f.key] != saved[f.key],
        );
        final int on = d.values.where((bool v) => v).length;
        Future<void> save() async {
          try {
            await cfg.saveLayout(a, Map<String, bool>.of(d));
            if (!mounted) return;
            setState(() => _draft = null);
            c.say('${a.layoutTitle} saved for ${cfg.member.name}');
          } catch (e) {
            c.say('Could not save: ${_err(e)}');
          }
        }

        return FlowScr(
          foot: <Widget>[
            Expanded(
              child: Btn(
                label: cfg.saving ? 'Saving…' : 'Save',
                icon: 'check',
                enabled: changed && !cfg.saving,
                onTap: save,
              ),
            ),
          ],
          children: <Widget>[
            const BackNav(),
            H1(a.layoutTitle, afterNav: true),
            Sub('${cfg.member.name} · $on of ${a.fields.length} fields shown'),
            Chips(
              margin: const EdgeInsets.only(bottom: 14),
              children: <Widget>[
                ChipBtn(
                  'All on',
                  on: on == a.fields.length,
                  onTap: () => setState(() {
                    for (final LayoutField f in a.fields) {
                      d[f.key] = true;
                    }
                  }),
                ),
                ChipBtn(
                  'All off',
                  on: on == 0,
                  onTap: () => setState(() {
                    for (final LayoutField f in a.fields) {
                      d[f.key] = false;
                    }
                  }),
                ),
              ],
            ),
            GlassList(
              children: <Widget>[
                for (final LayoutField f in a.fields)
                  RowX(
                    onTap: () => setState(() => d[f.key] = !(d[f.key] ?? true)),
                    children: <Widget>[
                      Ico(
                        d[f.key]! ? 'eye' : 'eyeOff',
                        size: IcoSize.xs,
                        color: d[f.key]! ? p.cat(a.cat) : p.ink3,
                        icon: IcSize.s,
                      ),
                      Expanded(
                        child: RTx(
                          f.label,
                          d[f.key]! ? 'Shown' : 'Hidden',
                          ell: true,
                        ),
                      ),
                      Sw(d[f.key]!),
                    ],
                  ),
              ],
            ),
            const InfoBox(
              'Turned-off fields are hidden from this user. Tap Save to apply.',
              icon: 'info',
              margin: EdgeInsets.only(top: 14, bottom: 14),
            ),
          ],
        );
      },
    );
  }
}

// ----------------------------------------------------------- selection

class TeamSelectScreen extends ConsumerStatefulWidget {
  const TeamSelectScreen({super.key});

  @override
  ConsumerState<TeamSelectScreen> createState() => _TeamSelectState();
}

class _TeamSelectState extends ConsumerState<TeamSelectScreen> {
  static const int _pageSize = 50;

  String? _kind;

  /// The selection being edited (starts as the user's saved selection; keys
  /// not listed here — e.g. another company's — are kept on save).
  Set<String>? _draft;
  int _page = 0;

  /// Search the local page index belongs to (a new search starts at page 1).
  String _pageQ = '';

  // Orders (GET /orders) — loaded once per screen.
  List<SelOpt>? _orders;
  String? _ordersErr;

  // Vouchers — server pages (search on the server).
  SelPage? _vPage;
  bool _vLoading = false;
  String? _vErr;
  String _vQuery = '';
  int _vSeq = 0;

  void _reset(String kind) {
    _kind = kind;
    _draft = null;
    _page = 0;
    _orders = null;
    _ordersErr = null;
    _vPage = null;
    _vErr = null;
    _vQuery = '';
  }

  Future<void> _loadOrders(TeamAdmin admin) async {
    setState(() => _ordersErr = null);
    try {
      final List<SelOpt> o = await admin.orders();
      if (mounted) setState(() => _orders = o);
    } catch (e) {
      if (mounted) setState(() => _ordersErr = _err(e));
    }
  }

  Future<void> _loadVouchers(TeamAdmin admin, int page, String q) async {
    final int seq = ++_vSeq;
    setState(() {
      _vLoading = true;
      _vErr = null;
      _vQuery = q;
      _page = page;
    });
    try {
      final SelPage r = await admin.vouchers(page + 1, q);
      if (!mounted || seq != _vSeq) return; // a newer page / search won
      setState(() {
        _vPage = r;
        _vLoading = false;
      });
    } catch (e) {
      if (!mounted || seq != _vSeq) return;
      setState(() {
        _vErr = _err(e);
        _vLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppController c = ref.watch(appProvider);
    final TeamConfig? cfg = c.teamCfg;
    if (cfg == null) return const _NoUser();
    final PermArea a = permArea(c.teamKind);
    if (_kind != a.kind) _reset(a.kind);
    final bool voucher = a.kind == 'voucher';
    final String q = c.q('tsQ').trim().toLowerCase();
    if (!voucher && q != _pageQ) {
      _pageQ = q;
      _page = 0;
    }

    // Source rows (vouchers come page by page from the server).
    List<SelOpt> all = const <SelOpt>[];
    bool srcLoading = false;
    String? srcErr;
    String emptyText = 'Nothing to select.';
    switch (a.kind) {
      case 'ledger':
        srcLoading =
            c.repo.status(DataSet.ledgers).loading &&
            !c.repo.hasData(DataSet.ledgers);
        all = c.memo<List<SelOpt>>(
          'ts-ledgers',
          '${c.repo.version}',
          () => <SelOpt>[
            for (final Party x in c.repo.parties())
              if ((x.guid ?? '').isNotEmpty)
                SelOpt(
                  x.guid!,
                  x.name,
                  '${x.kindLabel}${(x.group ?? '').isEmpty ? '' : ' · ${x.group}'}',
                ),
          ],
        );
        emptyText = c.emptyText(DataSet.ledgers, 'No ledgers found.');
      case 'inventory':
        srcLoading =
            c.repo.status(DataSet.items).loading &&
            !c.repo.hasData(DataSet.items);
        all = c.memo<List<SelOpt>>(
          'ts-items',
          '${c.repo.version}',
          () => <SelOpt>[
            for (final Item x in c.repo.items())
              SelOpt(
                x.name,
                x.name,
                <String>[
                  if ((x.group ?? '').isNotEmpty) x.group!,
                  stockLabel(x),
                ].join(' · '),
              ),
          ],
        );
        emptyText = c.emptyText(DataSet.items, 'No items found.');
      case 'order':
        if (_orders == null && _ordersErr == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _orders == null && _ordersErr == null) {
              _loadOrders(cfg.admin);
            }
          });
        }
        srcLoading = _orders == null && _ordersErr == null;
        srcErr = _ordersErr;
        all = _orders ?? const <SelOpt>[];
        emptyText = 'No orders in this company.';
      case 'voucher':
        if (!_vLoading && (_vPage == null || _vQuery != q) && _vErr == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_vLoading) _loadVouchers(cfg.admin, 0, q);
          });
        }
        srcLoading = _vLoading;
        srcErr = _vErr;
        all = _vPage?.rows ?? const <SelOpt>[];
        emptyText = q.isEmpty ? 'No vouchers.' : 'No voucher matches “$q”.';
    }

    return ListenableBuilder(
      listenable: cfg,
      builder: (BuildContext context, _) {
        final TcPalette p = Tc.of(context);
        final String? loadErr = cfg.selError[a.kind];
        final Set<String> saved = cfg.selected[a.kind] ?? <String>{};
        final Set<String> d = _draft ??= Set<String>.of(saved);
        final bool changed = d.length != saved.length || !d.containsAll(saved);
        // Local lists: filtered here, then paged; vouchers: one server page.
        final List<SelOpt> rows = voucher
            ? all
            : (q.isEmpty
                  ? all
                  : all
                        .where(
                          (SelOpt o) =>
                              '${o.title} ${o.sub}'.toLowerCase().contains(q),
                        )
                        .toList());
        final int pages = voucher
            ? (((_vPage?.total ?? 0) + TeamAdmin.voucherPageSize - 1) ~/
                      TeamAdmin.voucherPageSize)
                  .clamp(1, 1 << 30)
            : ((rows.length + _pageSize - 1) ~/ _pageSize).clamp(1, 1 << 30);
        final int page = _page.clamp(0, pages - 1);
        final List<SelOpt> shown = voucher
            ? rows
            : rows.skip(page * _pageSize).take(_pageSize).toList();
        final bool allOn =
            rows.isNotEmpty && rows.every((SelOpt o) => d.contains(o.key));
        final bool hasPrev = page > 0;
        final bool hasNext = voucher
            ? (_vPage?.hasMore ?? false)
            : page < pages - 1;
        void go(int to) {
          if (voucher) {
            _loadVouchers(cfg.admin, to, q);
          } else {
            setState(() => _page = to);
          }
        }

        Future<void> save() async {
          try {
            await cfg.saveSelection(a.kind, Set<String>.of(d));
            if (!mounted) return;
            setState(() => _draft = null);
            c.say('${a.selectTitle} saved for ${cfg.member.name}');
          } catch (e) {
            c.say('Could not save: ${_err(e)}');
          }
        }

        return FlowScr(
          foot: <Widget>[
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Selected', style: rsStyle(context)),
                  Text('${d.length}', style: rtStyle(context, 20)),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 140),
              child: Btn(
                label: cfg.saving ? 'Saving…' : 'Save',
                icon: 'check',
                expand: false,
                enabled: changed && !cfg.saving && loadErr == null,
                onTap: save,
              ),
            ),
          ],
          children: <Widget>[
            const BackNav(),
            H1(a.selectTitle, afterNav: true),
            Sub('${cfg.member.name} · ${d.length} selected'),
            if (loadErr != null)
              // The saved selection could not be read: saving now would
              // replace it, so Save stays off until it loads.
              _State(
                error: loadErr,
                onRetry: () {
                  setState(() => _draft = null);
                  cfg.load();
                },
              )
            else ...<Widget>[
              Inp(
                value: c.f('tsQ'),
                onChanged: (String s) => c.setQuery('tsQ', s),
                placeholder: voucher
                    ? 'Search party, number, type or date'
                    : 'Search',
                icon: 'search',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 12, 6, 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        voucher
                            ? '${_vPage?.total ?? 0} vouchers'
                            : '${rows.length} ${rows.length == 1 ? 'match' : 'matches'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: rsStyle(context),
                      ),
                    ),
                    ChipBtn(
                      allOn ? 'Unselect All' : 'Select All',
                      icon: allOn ? 'close' : 'check',
                      on: allOn,
                      onTap: rows.isEmpty
                          ? null
                          : () => setState(() {
                              if (allOn) {
                                d.removeAll(rows.map((SelOpt o) => o.key));
                              } else {
                                d.addAll(rows.map((SelOpt o) => o.key));
                              }
                            }),
                    ),
                  ],
                ),
              ),
              if (voucher)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                  child: Text(
                    'Select All applies to the vouchers on this page.',
                    style: rsStyle(context, 12.5),
                  ),
                ),
              if (srcLoading && shown.isEmpty)
                const _State(loading: true)
              else if (srcErr != null)
                _State(
                  error: srcErr,
                  onRetry: () => voucher
                      ? _loadVouchers(cfg.admin, page, q)
                      : _loadOrders(cfg.admin),
                )
              else
                lazyList<SelOpt>(
                  rows: shown,
                  empty: emptyText,
                  row: (BuildContext context, SelOpt o) {
                    final bool on = d.contains(o.key);
                    return RowX(
                      onTap: () => setState(() {
                        if (!d.remove(o.key)) d.add(o.key);
                      }),
                      children: <Widget>[
                        Tk(on),
                        Expanded(child: RTx(o.title, o.sub, ell: true)),
                        if (o.amount != null)
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.sizeOf(context).width * .3,
                            ),
                            child: AmtText(
                              inr(o.amount),
                              style: amtStyle(context, size: 14.5),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              if (pages > 1 || hasNext)
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 14),
                  child: Row(
                    children: <Widget>[
                      CBtn('chevL', onTap: hasPrev ? () => go(page - 1) : null),
                      Expanded(
                        child: Text(
                          'Page ${page + 1} of $pages',
                          textAlign: TextAlign.center,
                          style: ts(14.5, w: w700, c: p.ink2),
                        ),
                      ),
                      CBtn('chevR', onTap: hasNext ? () => go(page + 1) : null),
                    ],
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}
