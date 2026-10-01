// Formatting helpers ported 1:1 from Main.dc.html (inr 1683, inr2 1684,
// fdate 1686, initials 1687).
library;

/// Indian digit grouping, rounded, U+2212 minus: `inr(348690)` → `₹3,48,690`.
String inr(num? value) {
  num n = value ?? 0;
  if (n.isNaN) n = 0;
  final bool neg = n < 0;
  final String s = n.abs().round().toString();
  String rest = s.length > 3 ? s.substring(0, s.length - 3) : '';
  final String last3 = s.length > 3 ? s.substring(s.length - 3) : s;
  if (rest.isNotEmpty) {
    rest = rest.replaceAllMapped(
      RegExp(r'\B(?=(\d{2})+(?!\d))'),
      (Match m) => ',',
    );
  }
  return '${neg ? '−' : ''}₹${rest.isNotEmpty ? '$rest,$last3' : last3}';
}

/// Two decimals with Indian grouping: `inr2(1234.5)` → `₹1,234.50`.
String inr2(num? value) {
  final num n = value ?? 0;
  final String f = n.toStringAsFixed(2);
  final List<String> p = f.split('.');
  return '${inr(num.parse(p[0]))}.${p[1]}';
}

const List<String> kMonths = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `yyyy-mm-dd` → `dd Mon yyyy`; empty → `—`.
String fdate(String? s) {
  if (s == null || s.isEmpty) return '—';
  final List<String> p = s.split('-');
  if (p.length < 3) return s;
  final int m = int.tryParse(p[1]) ?? 1;
  return '${p[2]} ${kMonths[(m - 1).clamp(0, 11)]} ${p[0]}';
}

/// First letter, upper-cased; `?` for empty.
String initials(String? n) {
  final String t = (n ?? '?').trim();
  return t.isEmpty ? '' : t[0].toUpperCase();
}

/// `Number(x)||0` for form strings.
num numOf(String? s) => num.tryParse((s ?? '').trim()) ?? 0;
