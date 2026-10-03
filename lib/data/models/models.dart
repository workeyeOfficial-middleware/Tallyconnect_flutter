// Typed shapes of the prototype's data constants (Main.dc.html 1694–1867),
// extended with the identifiers and exact values the real backend returns.
// Money is `num` everywhere (rupees with paise) — never rounded for storage.
library;

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
  });
  final String name;

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
  });
  final String name;
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
  final String? group;

  num get worth => value ?? stock * rate;
}

/// Stock summary row (`/inventory`).
class StockRow {
  const StockRow(this.name, this.opening, this.inward, this.outward, this.closing);
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
  });
  final String name;
  final num rate;
  final int qty;
  final String unit;
  final num gst;
  final String? guid, hsn;

  Line withQty(int q) => Line(name, rate, q, unit, gst, guid: guid, hsn: hsn);
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
  });
  final String party, no, date, due;
  final num total;
  final String kind, city;
  final bool? recv;

  /// Real item lines (empty when the server sent none).
  final List<BillLine> lines;
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
