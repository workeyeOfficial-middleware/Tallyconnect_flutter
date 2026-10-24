// Ledgers by location, from what Tally saves on each ledger: its state, PIN
// code and address lines (Tally has no separate city field — the city is
// written in the address). A filter is a state (exact) and / or a city /
// area / PIN typed by the user ("Mumbai", "Andheri", "4000"), matched in
// the address and PIN. Only ledgers whose Tally address says so match.
library;

import 'models/models.dart';

/// The location chosen on the ledger list (empty: no filter).
class LocFilter {
  const LocFilter({this.state, this.area = ''});
  final String? state;

  /// City, area or PIN (start of it), as typed.
  final String area;

  static const LocFilter none = LocFilter();

  bool get on => (state ?? '').isNotEmpty || area.trim().isNotEmpty;

  /// "Mumbai · Maharashtra" / "Maharashtra" / "Mumbai".
  String get label => <String>[
    if (area.trim().isNotEmpty) area.trim(),
    if ((state ?? '').isNotEmpty) state!,
  ].join(' · ');

  /// Key for memoised lists.
  String get key => '${state ?? ''}|${area.trim().toLowerCase()}';
}

String _norm(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// Does [p]'s Tally location match [f]?
bool matchesLocation(Party p, LocFilter f) {
  if (!f.on) return true;
  final String? st = f.state;
  if (st != null && st.isNotEmpty) {
    if (_norm(p.state ?? '') != _norm(st)) return false;
  }
  final String a = _norm(f.area);
  if (a.isEmpty) return true;
  final String pin = (p.pincode ?? '').replaceAll(' ', '');
  // Digits: a PIN or the start of one ("400" = Mumbai PINs), or in the address.
  if (RegExp(r'^\d+$').hasMatch(a.replaceAll(' ', ''))) {
    final String d = a.replaceAll(' ', '');
    return pin.startsWith(d) || _norm(p.address ?? '').contains(d);
  }
  return _norm(p.address ?? '').contains(a) || _norm(p.state ?? '') == a;
}

/// States saved on [rows] with how many ledgers each, most first.
List<(String, int)> statesOf(Iterable<Party> rows) {
  final Map<String, (String, int)> by = <String, (String, int)>{};
  for (final Party p in rows) {
    final String s = (p.state ?? '').trim();
    if (s.isEmpty) continue;
    final (String, int)? x = by[_norm(s)];
    by[_norm(s)] = (x?.$1 ?? s, (x?.$2 ?? 0) + 1);
  }
  return by.values.toList()..sort(
    ((String, int) a, (String, int) b) =>
        b.$2 != a.$2 ? b.$2.compareTo(a.$2) : a.$1.compareTo(b.$1),
  );
}

/// How many of [rows] have any location saved in Tally.
int withLocation(Iterable<Party> rows) => rows
    .where(
      (Party p) =>
          (p.state ?? '').isNotEmpty ||
          (p.address ?? '').isNotEmpty ||
          (p.pincode ?? '').isNotEmpty,
    )
    .length;

/// A short place for a row: "401208 · Maharashtra" (empty: none).
String placeOf(Party p) => <String>[
  if ((p.pincode ?? '').isNotEmpty) p.pincode!,
  if ((p.state ?? '').isNotEmpty) p.state!,
].join(' · ');
