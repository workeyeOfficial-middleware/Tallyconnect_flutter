// Typed shapes of the prototype's data constants (Main.dc.html 1694–1867).
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

/// `SUMS` money card (1706).
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
  final int v;
  final String ic, c, cls;
  final NavTo go;
}

/// `KIND` (1716).
class Kind {
  const Kind(this.t, this.long, this.ic, this.c, this.sign);
  final String t, long, ic, c;
  final int sign;
}

/// `VOUCH` row (1724).
class Voucher {
  const Voucher(this.kind, this.party, this.no, this.day, this.amt);
  final String kind, party, no;
  final int day;
  final int amt;
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
  ]);
  final String party, no, bill, due, credit;
  final int amt;
  final String st, txt, city, kind;

  Bill withKind(String k) =>
      Bill(party, no, bill, due, credit, amt, st, txt, city, k);
}

/// `PARTIES` row (1762).
class Party {
  const Party(this.name, this.type, this.city, this.bal);
  final String name;

  /// `c` customer | `s` supplier.
  final String type;
  final String city;
  final int bal;
}

/// `ITEMS` row (1778).
class Item {
  const Item(this.name, this.stock, this.unit, this.rate, this.st);
  final String name;
  final int stock;
  final String unit;
  final int rate;

  /// ok | low | out
  final String st;
}

/// `SALES9` line (1788).
class BillLine {
  const BillLine(this.name, this.hsn, this.qty, this.rate, this.amt);
  final String name, hsn, qty, rate;
  final int amt;
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
  ]);
  final String id, kind, no, party;
  final int amt;
  final String time, status, note;

  Act copyWith({String? status, String? note, String? time}) => Act(
    id,
    kind,
    no,
    party,
    amt,
    time ?? this.time,
    status ?? this.status,
    note ?? this.note,
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
  const Line(this.name, this.rate, this.qty, this.unit, this.gst);
  final String name;
  final num rate;
  final int qty;
  final String unit;
  final int gst;

  Line withQty(int q) => Line(name, rate, q, unit, gst);
}

/// Journal line (`state.jl`). side: Dr | Cr.
class JLine {
  const JLine(this.side, this.name, this.grp, this.amt);
  final String side, name, grp;
  final int amt;

  JLine copyWith({String? side, int? amt}) =>
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
  });
  final String party, no, date, due;
  final int total;
  final String kind, city;
  final bool? recv;
}
