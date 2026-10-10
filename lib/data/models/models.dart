// Typed shapes of the prototype's data constants (Main.dc.html 1694–1867),
// extended with the identifiers and exact values the real backend returns.
// Money is `num` everywhere (rupees with paise) — never rounded for storage.
library;

import '../../core/utils/format.dart' show parseDmy;

/// A navigation target: `'screen'` or `['screen', {params}]`.
class NavTo {
  const NavTo(this.screen, [this.extra = const <String, Object?>{}]);
  final String screen;
  final Map<String, Object?> extra;
}

/// `T` shortcut (1694).
class Shortcut {
  const Shortcut(this.k, this.t, this.s, this.ic, this.c, {this.to, this.flow});
  final String k, t, s, ic;

  /// Category colour key (`navy` or a category, which resolves to accent).
  final String c;
  final String? to;
  final String? flow;
}

/// `SUMS` money card (1706). [v] is null when the server cannot provide the
/// figure (the card then shows `—` instead of a made-up number).
class SumCard {
  const SumCard(
    this.k,
    this.t,
    this.s,
    this.v,
    this.ic,
    this.c,
    this.cls,
    this.go,
  );
  final String k, t, s;
  final num? v;
  final String ic, c, cls;
  final NavTo go;

  SumCard withValue(num? value, [String? sub]) =>
      SumCard(k, t, sub ?? s, value, ic, c, cls, go);
}

/// `KIND` (1716).
class Kind {
  const Kind(this.t, this.long, this.ic, this.c, this.sign);
  final String t, long, ic, c;
  final int sign;
}

/// One stock line inside a voucher (from `/voucher-entry/paged` items).
class VoucherItem {
  const VoucherItem(this.name, this.qty, this.rate, this.amt);
  final String name;
  final num? qty, rate, amt;
}

/// `VOUCH` row (1724). Remote rows carry [guid], [date] and the raw Tally
/// voucher type in [type].
class Voucher {
  const Voucher(
    this.kind,
    this.party,
    this.no,
    this.day,
    this.amt, {
    this.guid,
    this.date,
    this.type,
    this.items = const <VoucherItem>[],
  });
  final String kind, party, no;
  final int day;
  final num amt;
  final String? guid;
  final DateTime? date;
  final String? type;
  final List<VoucherItem> items;

  /// Stable list key (number for sample data, GUID for server rows).
  String get key => guid ?? no;
}

/// One ledger line of a voucher (`/voucher-entry/:guid`).
class LedgerLine {
  const LedgerLine(this.ledger, this.amt, this.debit);
  final String ledger;
  final num amt;
  final bool debit;
}

/// `RECV` / `PAYB` bill (1747, 1755). [kind] is `recv` | `pay` once opened.
class Bill {
  const Bill(
    this.party,
    this.no,
    this.bill,
    this.due,
    this.credit,
    this.amt,
    this.st,
    this.txt,
    this.city, [
    this.kind = 'recv',
    this.id,
    this.ledgerGuid,
    this.dueDate,
    this.billAmt,
    this.lines = const <BillLine>[],
  ]);
  final String party, no, bill, due, credit;

  /// Pending (still to settle) amount.
  final num amt;
  final String st, txt, city, kind;
  final String? id, ledgerGuid;
  final DateTime? dueDate;

  /// Original bill amount (server `bill_amount`), when known.
  final num? billAmt;
  final List<BillLine> lines;

  String get key => id ?? no;

  /// The bill's date ([bill] is its `dd Mon yyyy` text); null when unknown.
  DateTime? get billDate => parseDmy(bill);

  Bill withKind(String k) => Bill(
    party,
    no,
    bill,
    due,
    credit,
    amt,
    st,
    txt,
    city,
    k,
    id,
    ledgerGuid,
    dueDate,
    billAmt,
    lines,
  );
}

/// `PARTIES` row (1762).
class Party {
  const Party(
    this.name,
    this.type,
    this.city,
    this.bal, {
    this.guid,
    this.group,
    this.email,
    this.phone,
    this.opening,
    this.closing,
    this.lastDate,
    this.search = '',
  });
  final String name;

  /// Lower-case search text built once when the list is loaded (empty for
  /// sample data → the name is used).
  final String search;

  /// `c` customer | `s` supplier | `o` any other ledger (bank, cash,
  /// expense, …) — `o` is never guessed into customer / supplier.
  final String type;

  /// Customer / Supplier / Ledger.
  String get kindLabel =>
      type == 'c' ? 'Customer' : (type == 's' ? 'Supplier' : 'Ledger');
  final String city;

  /// Outstanding (pending bills) for remote parties; prototype balance for
  /// sample data.
  final num bal;
  final String? guid, group, email, phone;

  /// Tally opening / closing balance exactly as synced (the server does not
  /// send whether it is Dr or Cr).
  final num? opening, closing;
  final DateTime? lastDate;
}

/// `ITEMS` row (1778).
class Item {
  const Item(
    this.name,
    this.stock,
    this.unit,
    this.rate,
    this.st, {
    this.guid,
    this.value,
    this.hsn,
    this.gst,
    this.group,
    this.openingQty,
    this.openingValue,
    this.search = '',
  });
  final String name;

  /// Lower-case search text built once when the list is loaded.
  final String search;

  /// Closing quantity (Tally stock summary).
  final num stock;
  final String unit;
  final num rate;

  /// ok | low | out
  final String st;
  final String? guid;

  /// Closing value from Tally (preferred over stock × rate when known).
  final num? value;
  final String? hsn;
  final num? gst;

  /// Tally stock group (parent) of the item.
  final String? group;

  /// Opening quantity / value from the Tally stock-item master.
  final num? openingQty, openingValue;

  num get worth => value ?? stock * rate;

  /// Opening rate = opening value ÷ opening quantity (null when unknown).
  num? get openingRate =>
      (openingQty == null || openingQty == 0 || openingValue == null)
      ? null
      : openingValue! / openingQty!;
}

/// Stock summary row (`/inventory`).
class StockRow {
  const StockRow(
    this.name,
    this.opening,
    this.inward,
    this.outward,
    this.closing,
  );
  final String name;
  final num? opening, inward, outward, closing;
}

/// `SALES9` line (1788).
class BillLine {
  const BillLine(this.name, this.hsn, this.qty, this.rate, this.amt);
  final String name, hsn, qty, rate;
  final num amt;
}

/// Ledger / account / pick option `{t, s}`.
class Opt {
  const Opt(this.t, this.s);
  final String t, s;
}

/// `COMPANIES` (1798).
class Company {
  const Company(this.id, this.name, this.sub);
  final String id, name, sub;

  /// `name.split(' - ')[0]`.
  String get short => name.split(' - ').first;
}

/// `FT` flow type (1803).
class FlowType {
  const FlowType({
    required this.title,
    required this.sub,
    required this.ic,
    required this.c,
    required this.steps,
    required this.p,
    required this.partyLabel,
    required this.noLabel,
    this.list,
    this.items = false,
    this.amtLabel,
    this.balLabel,
    this.accLabel,
    this.draft = false,
  });
  final String title, sub, ic, c;
  final List<String> steps;

  /// Form-key prefix: s, p, r, y, j.
  final String p;
  final String partyLabel, noLabel;
  final String? list;
  final bool items;
  final String? amtLabel, balLabel, accLabel;
  final bool draft;
}

/// `MODES` (1810).
class PayMode {
  const PayMode(this.id, this.t, this.ic);
  final String id, t, ic;
}

/// Mutable notification (`NOTIFS`, 1821).
class Notif {
  const Notif(
    this.id,
    this.t,
    this.b,
    this.time,
    this.ic,
    this.c,
    this.unread,
    this.go,
  );
  final String id, t, b, time, ic, c;
  final bool unread;
  final NavTo go;

  Notif read() => Notif(id, t, b, time, ic, c, false, go);
}

/// Activity entry (`ACTS`, 1829). status: ok | wait | fail.
class Act {
  const Act(
    this.id,
    this.kind,
    this.no,
    this.party,
    this.amt,
    this.time,
    this.status, [
    this.note = '',
    this.rows = const <(String, String)>[],
    this.items = const <(String, String, num)>[],
  ]);
  final String id, kind, no, party;
  final num amt;
  final String time, status, note;

  /// Extra detail rows / item lines taken from the queued payload.
  final List<(String, String)> rows;
  final List<(String, String, num)> items;

  Act copyWith({String? status, String? note, String? time}) => Act(
    id,
    kind,
    no,
    party,
    amt,
    time ?? this.time,
    status ?? this.status,
    note ?? this.note,
    rows,
    items,
  );
}

/// Team member (`TEAM`, 1841). st: active | pending | off.
class Member {
  const Member(this.id, this.name, this.email, this.role, this.st);
  final String id, name, email, role, st;

  Member withSt(String s) => Member(id, name, email, role, s);

  /// Same member with the name / role entered on this phone (if any).
  Member labeled(String? n, String? r) => Member(
    id,
    (n ?? '').trim().isEmpty ? name : n!.trim(),
    email,
    (r ?? '').trim().isEmpty ? role : r!.trim(),
    st,
  );
}

/// Workspace (`WS`, 1847).
class Workspace {
  const Workspace(
    this.id,
    this.name,
    this.feats,
    this.sums, {
    this.builtin = false,
  });
  final String id, name;
  final List<String> feats, sums;
  final bool builtin;
}

/// FAQ (1852).
class Faq {
  const Faq(this.q, this.a);
  final String q, a;
}

/// Report card (1858).
class Report {
  const Report(this.id, this.cat, this.t, this.s, this.ic, this.c);
  final String id, cat, t, s, ic, c;
}

/// Line item on a sales / purchase bill (`state.lines`).
class Line {
  const Line(
    this.name,
    this.rate,
    this.qty,
    this.unit,
    this.gst, {
    this.guid,
    this.hsn,
    this.group,
  });
  final String name;
  final num rate;
  final int qty;
  final String unit;
  final num gst;

  /// Tally stock group — required by the sync agent to create a new item.
  final String? guid, hsn, group;

  Line withQty(int q) =>
      Line(name, rate, q, unit, gst, guid: guid, hsn: hsn, group: group);

  /// This voucher line's own rate / GST (the item master is not changed).
  Line withRate(num r) =>
      Line(name, r, qty, unit, gst, guid: guid, hsn: hsn, group: group);
  Line withGst(num g) =>
      Line(name, rate, qty, unit, g, guid: guid, hsn: hsn, group: group);
}

/// Journal line (`state.jl`). side: Dr | Cr.
class JLine {
  const JLine(this.side, this.name, this.grp, this.amt);
  final String side, name, grp;
  final num amt;

  JLine copyWith({String? side, num? amt}) =>
      JLine(side ?? this.side, name, grp, amt ?? this.amt);
}

/// Plan (`PL`, 2675).
class Plan {
  const Plan(
    this.k,
    this.t,
    this.s,
    this.ic,
    this.c,
    this.feats, {
    this.y,
    this.m,
    this.current = false,
  });
  final String k, t, s, ic, c;
  final List<String> feats;
  final int? y, m;
  final bool current;
}

/// Search entry (`SEARCH`, 2352).
class SearchEntry {
  const SearchEntry(this.t, this.s, this.ic, this.c, {this.a, this.f});
  final String t, s, ic, c;
  final NavTo? a;
  final String? f;
}

/// What the bill PDF shows (`state.pdf`).
class PdfInfo {
  const PdfInfo({
    required this.party,
    required this.no,
    required this.date,
    required this.due,
    required this.total,
    required this.kind,
    required this.city,
    this.recv,
    this.lines = const <BillLine>[],
    this.ledger = const <LedgerLine>[],
  });
  final String party, no, date, due;
  final num total;
  final String kind, city;
  final bool? recv;

  /// Real item lines (empty when the server sent none).
  final List<BillLine> lines;

  /// Real Dr / Cr ledger lines of a voucher (empty when not known).
  final List<LedgerLine> ledger;
}

// ------------------------------------------------------------ session

/// The logged-in user (`POST /auth/login` → `user`).
class AuthUser {
  const AuthUser({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    this.adminId,
    this.plan,
  });
  final int id;
  final String username, email, role;
  final int? adminId;
  final String? plan;

  bool get isAdmin => role == 'ADMIN';

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'username': username,
    'email': email,
    'role': role,
    'adminId': adminId,
    'plan': plan,
  };

  static AuthUser? fromJson(Object? o) {
    if (o is! Map) return null;
    final Object? id = o['id'];
    final int? iid = id is num ? id.toInt() : int.tryParse('$id');
    if (iid == null) return null;
    final Object? ad = o['adminId'];
    return AuthUser(
      id: iid,
      username: '${o['username'] ?? ''}',
      email: '${o['email'] ?? ''}',
      role: '${o['role'] ?? ''}',
      adminId: ad is num ? ad.toInt() : int.tryParse('${ad ?? ''}'),
      plan: o['plan'] is String ? o['plan'] as String : null,
    );
  }
}

/// `GET /users/me`.
class Profile {
  const Profile({
    required this.username,
    required this.email,
    required this.role,
    this.company,
    this.adminEmail,
  });
  final String username, email, role;
  final String? company, adminEmail;
}

/// `GET /agent-status/sync-status`.
class SyncInfo {
  const SyncInfo(this.lastSyncAt, this.inProgress);
  final DateTime? lastSyncAt;
  final bool inProgress;
}

/// Receivable or payable outstanding, computed from the same bill list the
/// screens show (so list and totals always agree).
class OutstandingSummary {
  const OutstandingSummary({
    required this.total,
    required this.parties,
    required this.late,
    required this.lateBills,
    required this.ageing,
    this.serverTotal,
  });
  final num total, late;
  final int parties, lateBills;

  /// on time, 1–30, 31–60, > 60 days late.
  final List<num> ageing;

  /// `/dashboard/summary` value for cross-checking (ADMIN only).
  final num? serverTotal;

  bool get mismatch =>
      serverTotal != null && (serverTotal! - total).abs() > 0.009;
}

/// This-month totals by kind (sales, purchase, receipt, payment, …).
class MonthTotals {
  const MonthTotals(this.amount, this.count);
  final Map<String, num> amount;
  final Map<String, int> count;
}

/// Party detail tabs loaded on demand.
class PartyDetail {
  const PartyDetail({
    required this.entries,
    required this.items,
    required this.bills,
  });
  final List<Voucher> entries;
  final List<BillLine> items;
  final List<Bill> bills;
}

/// Result of sending an entry to the server queue.
class SubmitResult {
  const SubmitResult({
    required this.ok,
    this.message = '',
    this.commandId,
    this.duplicate = false,
  });
  final bool ok, duplicate;
  final String message;
  final String? commandId;
}

/// Loading state of one data set.
enum LoadState { idle, loading, ready, error }

class DataStatus {
  const DataStatus(this.state, [this.message]);
  final LoadState state;
  final String? message;

  static const DataStatus idle = DataStatus(LoadState.idle);
  bool get loading => state == LoadState.loading;
  bool get failed => state == LoadState.error;
}

// ------------------------------------------------------------ item detail

/// One customer or supplier of an item
/// (`/ledger-items/item/:itemName/parties`).
class ItemParty {
  const ItemParty({
    required this.name,
    required this.qty,
    required this.amount,
    required this.invoices,
    this.lastDate,
  });
  final String name;
  final num? qty, amount;
  final int? invoices;
  final DateTime? lastDate;

  /// Average rate = amount ÷ quantity (null when quantity is 0 / unknown).
  num? get avgRate =>
      (qty == null || qty == 0 || amount == null) ? null : amount! / qty!;
}

/// Customers and suppliers of an item, loaded on demand.
class ItemDetail {
  const ItemDetail({required this.customers, required this.suppliers});
  final List<ItemParty> customers, suppliers;
}

/// Sales or purchase summary of one item, summed from the item lines of
/// the loaded voucher history.
class ItemTrade {
  const ItemTrade({
    required this.amount,
    required this.qty,
    required this.vouchers,
    this.lastDate,
    this.lastRate,
    this.minRate,
    this.maxRate,
  });
  final num amount, qty;
  final int vouchers;
  final DateTime? lastDate;
  final num? lastRate, minRate, maxRate;
}

// --------------------------------------------------------------- reminders

/// A reminder on an outstanding bill. Kept only on this phone (the backend
/// has no reminder endpoint).
class Reminder {
  const Reminder({
    required this.id,
    required this.company,
    required this.billKey,
    required this.party,
    required this.billNo,
    required this.kind,
    required this.amount,
    required this.date,
    this.time = '',
    this.note = '',
    this.done = false,
  });
  final String id, company, billKey, party, billNo;

  /// Marked done (from the list or the notification): no longer rings.
  final bool done;

  /// `recv` | `pay`
  final String kind;
  final num amount;

  /// `YYYY-MM-DD`
  final String date;

  /// `HH:mm` (24 h); empty for reminders saved before times existed.
  final String time;
  final String note;

  DateTime? get day => DateTime.tryParse(date);

  /// Date + time of the reminder (start of day when no time was set).
  DateTime? get at {
    final DateTime? d = day;
    if (d == null) return null;
    final List<String> p = time.split(':');
    final int h = p.length == 2 ? (int.tryParse(p[0]) ?? 0) : 0;
    final int m = p.length == 2 ? (int.tryParse(p[1]) ?? 0) : 0;
    return DateTime(d.year, d.month, d.day, h, m);
  }

  Reminder copyWith({String? date, String? time, bool? done}) => Reminder(
    id: id,
    company: company,
    billKey: billKey,
    party: party,
    billNo: billNo,
    kind: kind,
    amount: amount,
    date: date ?? this.date,
    time: time ?? this.time,
    note: note,
    done: done ?? this.done,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'company': company,
    'billKey': billKey,
    'party': party,
    'billNo': billNo,
    'kind': kind,
    'amount': amount,
    'date': date,
    'time': time,
    'note': note,
    'done': done,
  };

  static Reminder? fromJson(Object? o) {
    if (o is! Map || o['id'] is! String || o['date'] is! String) return null;
    return Reminder(
      id: o['id'] as String,
      company: '${o['company'] ?? ''}',
      billKey: '${o['billKey'] ?? ''}',
      party: '${o['party'] ?? ''}',
      billNo: '${o['billNo'] ?? ''}',
      kind: o['kind'] == 'pay' ? 'pay' : 'recv',
      amount: o['amount'] is num ? o['amount'] as num : 0,
      date: o['date'] as String,
      time: o['time'] is String ? o['time'] as String : '',
      note: '${o['note'] ?? ''}',
      done: o['done'] == true,
    );
  }
}
