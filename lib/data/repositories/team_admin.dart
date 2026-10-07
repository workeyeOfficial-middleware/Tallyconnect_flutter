// Sales Team user configuration on the existing backend: layout (column)
// permissions stored on the user (`GET /users`, `PUT /users/:id/*-
// permissions`) and selection permissions (which ledgers / vouchers / orders
// / items the user may see), plus invite and delete. Only routes the server
// already has are used.
library;

import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/format.dart';
import '../api/adapters.dart';
import '../api/set_parsers.dart';
import '../api/tally_api.dart';
import '../models/models.dart';

/// One switchable column of a layout. [key] is the backend's `columns` key
/// (camelCase, as the server's inventory route reads them: `false` hides the
/// column, a missing key means visible).
class LayoutField {
  const LayoutField(this.key, this.label);
  final String key, label;
}

/// One permission area (Ledgers, Vouchers, Orders, Inventory).
class PermArea {
  const PermArea({
    required this.kind,
    required this.layoutTitle,
    required this.selectTitle,
    required this.userField,
    required this.route,
    required this.fields,
    required this.icon,
    required this.cat,
  });
  final String kind, layoutTitle, selectTitle, icon, cat;

  /// Field of the `GET /users` row holding this layout permission.
  final String userField;

  /// `PUT /users/:id/<route>`.
  final String route;
  final List<LayoutField> fields;
}

const List<PermArea> kPermAreas = <PermArea>[
  PermArea(
    kind: 'ledger',
    layoutTitle: 'Ledgers Layout',
    selectTitle: 'Ledger Selection',
    userField: 'ledger_permissions',
    route: 'ledger-permissions',
    icon: 'person',
    cat: 'party',
    fields: <LayoutField>[
      LayoutField('partyName', 'Party Name'),
      LayoutField('type', 'Type'),
      LayoutField('openingBalance', 'Opening Balance'),
      LayoutField('outstanding', 'Outstanding'),
      LayoutField('dueDays', 'Due Days'),
      LayoutField('actions', 'Actions'),
    ],
  ),
  PermArea(
    kind: 'voucher',
    layoutTitle: 'Vouchers Layout',
    selectTitle: 'Voucher Selection',
    userField: 'vouchers_permissions',
    route: 'voucher-permissions',
    icon: 'receipt',
    cat: 'vouchers',
    fields: <LayoutField>[
      LayoutField('date', 'Date'),
      LayoutField('voucherType', 'Voucher Type'),
      LayoutField('referenceNo', 'Reference No.'),
      LayoutField('party', 'Party'),
      LayoutField('amount', 'Amount'),
      LayoutField('status', 'Status'),
      LayoutField('actions', 'Actions'),
    ],
  ),
  PermArea(
    kind: 'order',
    layoutTitle: 'Orders Layout',
    selectTitle: 'Order Selection',
    userField: 'orders_permissions',
    route: 'orders-permissions',
    icon: 'note',
    cat: 'sales',
    fields: <LayoutField>[
      LayoutField('orderNo', 'Order No.'),
      LayoutField('partyName', 'Party Name'),
      LayoutField('type', 'Type'),
      LayoutField('dueDate', 'Due Date'),
      LayoutField('date', 'Date'),
      LayoutField('amount', 'Amount'),
      LayoutField('status', 'Status'),
      LayoutField('actions', 'Actions'),
    ],
  ),
  PermArea(
    kind: 'inventory',
    layoutTitle: 'Inventory Layout',
    selectTitle: 'Inventory Selection',
    userField: 'inventory_permissions',
    route: 'inventory-permissions',
    icon: 'box',
    cat: 'items',
    fields: <LayoutField>[
      LayoutField('itemCode', 'Item Code'),
      LayoutField('itemName', 'Item Name'),
      LayoutField('opening', 'Opening'),
      LayoutField('inward', 'Inward'),
      LayoutField('outward', 'Outward'),
      LayoutField('closingStock', 'Closing Stock'),
      LayoutField('rate', 'Rate'),
      LayoutField('value', 'Value'),
      LayoutField('actions', 'Actions'),
    ],
  ),
];

PermArea permArea(String kind) =>
    kPermAreas.firstWhere((PermArea a) => a.kind == kind);

/// A row the admin can select for a user.
class SelOpt {
  const SelOpt(this.key, this.title, this.sub, [this.amount]);

  /// What the server stores (ledger GUID, voucher GUID, order GUID or item
  /// name).
  final String key;
  final String title, sub;
  final num? amount;
}

/// One page of the server's voucher list (selection of vouchers).
class SelPage {
  const SelPage(this.rows, this.total, this.hasMore);
  final List<SelOpt> rows;
  final int? total;
  final bool hasMore;
}

/// Team admin calls on the existing routes.
class TeamAdmin {
  TeamAdmin(this._api, this._reloadTeam);
  final TallyApi _api;
  final Future<void> Function() _reloadTeam;

  /// Voucher selection page size (server list, newest first).
  static const int voucherPageSize = 50;

  int _uid(Member m) {
    final int? id = int.tryParse(m.id);
    if (id == null) {
      throw const ApiException(ApiErrorKind.badRequest, 'Unknown user id');
    }
    return id;
  }

  /// The user's stored layout permission objects, read fresh.
  Future<Map<String, Map<String, Object?>>> layouts(Member m) async {
    final Object? body = await _api.users();
    final Map<String, Object?>? row = rows(
      body,
    ).where((Map<String, Object?> r) => str(r['id']) == m.id).firstOrNull;
    if (row == null) {
      throw const ApiException(ApiErrorKind.notFound, 'User not found');
    }
    return <String, Map<String, Object?>>{
      for (final PermArea a in kPermAreas) a.kind: _obj(row[a.userField]),
    };
  }

  static Map<String, Object?> _obj(Object? v) =>
      v is Map ? v.cast<String, Object?>() : <String, Object?>{};

  Future<void> saveLayout(
    Member m,
    PermArea a,
    Map<String, Object?> perm,
  ) async {
    await _api.saveLayoutPermissions(m.id, a.route, perm);
  }

  /// Keys the user is allowed to see for [kind].
  Future<Set<String>> selection(Member m, String kind) async {
    switch (kind) {
      case 'ledger':
        return <String>{
          for (final Map<String, Object?> r in rows(
            await _api.userLedgers(m.id),
          ))
            if (str(r['ledger_guid']).isNotEmpty) str(r['ledger_guid']),
        };
      case 'voucher':
        return _list(await _api.userVouchers(m.id), 'vouchers');
      case 'order':
        return _list(await _api.userOrders(m.id), 'orders');
      case 'inventory':
        return <String>{
          for (final Map<String, Object?> r in rows(
            await _api.userInventory(m.id),
          ))
            if (str(r['item_name']).isNotEmpty) str(r['item_name']),
        };
    }
    throw ArgumentError(kind);
  }

  static Set<String> _list(Object? body, String key) {
    final Object? l = body is Map ? body[key] : null;
    return <String>{
      if (l is List)
        for (final Object? e in l)
          if (e != null && '$e'.isNotEmpty) '$e',
    };
  }

  /// Replaces the user's selection for [kind] with [keys].
  Future<void> saveSelection(Member m, String kind, Set<String> keys) async {
    final int id = _uid(m);
    final List<String> l = keys.toList()..sort();
    switch (kind) {
      case 'ledger':
        await _api.saveUserLedgers(id, l);
      case 'voucher':
        await _api.saveUserVouchers(id, l);
      case 'order':
        await _api.saveUserOrders(id, l);
      case 'inventory':
        await _api.saveUserInventory(id, l);
      default:
        throw ArgumentError(kind);
    }
  }

  /// The active company's orders (`GET /orders`).
  Future<List<SelOpt>> orders() async => <SelOpt>[
    for (final Map<String, Object?> r in rows(await _api.orders()))
      if (str(r['id']).isNotEmpty)
        SelOpt(
          str(r['id']),
          str(r['customer']).isEmpty ? '—' : str(r['customer']),
          <String>[
            if (str(r['type']).isNotEmpty) str(r['type']),
            if (dateOnly(r['date']) != null) dmy(dateOnly(r['date'])),
            if (str(r['status']).isNotEmpty) str(r['status']),
          ].join(' · '),
          toNum(r['amount']),
        ),
  ];

  /// One page of all vouchers (server search on party, number, type, date).
  Future<SelPage> vouchers(int page, String search) async {
    final VoucherPageParsed p = await parseVoucherPage(
      await _api.vouchersPagedText(
        page: page,
        limit: voucherPageSize,
        search: search.trim().isEmpty ? null : search.trim(),
      ),
    );
    return SelPage(
      <SelOpt>[
        for (final Voucher v in p.rows)
          if ((v.guid ?? '').isNotEmpty)
            SelOpt(
              v.guid!,
              '${v.type ?? 'Voucher'} · ${v.no}',
              '${v.party} · ${dmy(v.date)}',
              v.amt,
            ),
      ],
      p.total,
      p.hasMore,
    );
  }

  Future<void> sendInvite(Member m) => _api.sendInvite(m.email, m.name);

  Future<void> deleteUser(Member m) async {
    await _api.deleteUser(m.id);
    await _reloadTeam();
  }
}

/// Configure User state for one member: the stored layout permissions and
/// selections, loaded when the screen opens and updated on each save.
class TeamConfig extends ChangeNotifier {
  TeamConfig(this.admin, this.member);
  final TeamAdmin admin;
  final Member member;

  bool loading = false, saving = false;
  String? error;
  Map<String, Map<String, Object?>> layouts = <String, Map<String, Object?>>{};
  final Map<String, Set<String>> selected = <String, Set<String>>{};
  final Map<String, String> selError = <String, String>{};
  bool _disposed = false;

  static String _msg(Object e) =>
      e is ApiException ? e.userMessage : 'Could not load: $e';

  Future<void> load() async {
    loading = true;
    error = null;
    _notify();
    try {
      final List<Object?> r = await Future.wait(<Future<Object?>>[
        admin.layouts(member),
        for (final PermArea a in kPermAreas)
          admin
              .selection(member, a.kind)
              .then<Object?>((Set<String> s) => s, onError: (Object e) => e),
      ]);
      layouts = r[0]! as Map<String, Map<String, Object?>>;
      for (int i = 0; i < kPermAreas.length; i++) {
        final Object? v = r[i + 1];
        final String k = kPermAreas[i].kind;
        if (v is Set<String>) {
          selected[k] = v;
          selError.remove(k);
        } else {
          selError[k] = _msg(v!);
        }
      }
    } catch (e) {
      error = _msg(e);
    }
    loading = false;
    _notify();
  }

  /// Field on/off as stored (a missing key means on).
  Map<String, bool> columns(PermArea a) {
    final Object? c = layouts[a.kind]?['columns'];
    final Map<Object?, Object?> m = c is Map ? c : const <Object?, Object?>{};
    return <String, bool>{
      for (final LayoutField f in a.fields) f.key: m[f.key] != false,
    };
  }

  /// Saves [cols] into the user's stored object; every other key there
  /// (other columns, other settings) is kept as it was.
  Future<void> saveLayout(PermArea a, Map<String, bool> cols) async {
    final Map<String, Object?> cur = Map<String, Object?>.of(
      layouts[a.kind] ?? <String, Object?>{},
    );
    final Object? c = cur['columns'];
    cur['columns'] = <String, Object?>{
      if (c is Map) ...c.cast<String, Object?>(),
      ...cols,
    };
    saving = true;
    _notify();
    try {
      await admin.saveLayout(member, a, cur);
      layouts = <String, Map<String, Object?>>{...layouts, a.kind: cur};
    } finally {
      saving = false;
      _notify();
    }
  }

  Future<void> saveSelection(String kind, Set<String> keys) async {
    saving = true;
    _notify();
    try {
      await admin.saveSelection(member, kind, keys);
      selected[kind] = Set<String>.of(keys);
      selError.remove(kind);
    } finally {
      saving = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
