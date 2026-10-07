// Formatting helpers ported 1:1 from Main.dc.html (inr 1683, inr2 1684,
// fdate 1686, initials 1687), plus date helpers for real server dates.
library;

/// Indian digit grouping with U+2212 minus: `inr(348690)` → `₹3,48,690`.
/// Whole rupees print without decimals; amounts with paise keep them
/// (`inr(1234.5)` → `₹1,234.50`) so accounting values are never rounded away.
String inr(num? value) {
  num n = value ?? 0;
  if (n.isNaN || n.isInfinite) n = 0;
  final num paise = (n * 100).round();
  if (paise % 100 != 0) return inr2(n);
  final bool neg = paise < 0;
  final String s = (paise.abs() ~/ 100).toString();
  return '${neg ? '−' : ''}₹${_group(s)}';
}

String _group(String s) {
  String rest = s.length > 3 ? s.substring(0, s.length - 3) : '';
  final String last3 = s.length > 3 ? s.substring(s.length - 3) : s;
  if (rest.isNotEmpty) {
    rest = rest.replaceAllMapped(
      RegExp(r'\B(?=(\d{2})+(?!\d))'),
      (Match m) => ',',
    );
  }
  return rest.isNotEmpty ? '$rest,$last3' : last3;
}

/// A count with Indian digit grouping: `grouped(46438)` → `46,438`.
String grouped(int n) => n < 0 ? '−${_group('${-n}')}' : _group('$n');

/// Two decimals with Indian grouping: `inr2(1234.5)` → `₹1,234.50`.
String inr2(num? value) {
  num n = value ?? 0;
  if (n.isNaN || n.isInfinite) n = 0;
  final int paise = (n * 100).round();
  final bool neg = paise < 0;
  final int a = paise.abs();
  return '${neg ? '−' : ''}₹${_group('${a ~/ 100}')}.${(a % 100).toString().padLeft(2, '0')}';
}

/// Rounds to paise (2 decimals) — the precision Tally keeps.
num paise(num v) => (v * 100).round() / 100;

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

const List<String> kMonthsLong = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// `yyyy-mm-dd` → `dd Mon yyyy`; empty → `—`.
String fdate(String? s) {
  if (s == null || s.isEmpty) return '—';
  final List<String> p = s.split('-');
  if (p.length < 3) return s;
  final int m = int.tryParse(p[1]) ?? 1;
  return '${p[2]} ${kMonths[(m - 1).clamp(0, 11)]} ${p[0]}';
}

/// `26 Sep 2026`.
String dmy(DateTime? d) => d == null
    ? '—'
    : '${d.day.toString().padLeft(2, '0')} ${kMonths[d.month - 1]} ${d.year}';

/// `26 Sep`.
String dm(DateTime d) => '${d.day} ${kMonths[d.month - 1]}';

/// `September 2026`.
String monthYear(DateTime d) => '${kMonthsLong[d.month - 1]} ${d.year}';

/// `2026-09-26`.
String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// `10:58 AM`.
String clock(DateTime t) {
  final int h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// Activity / alert time: `10:58 AM` today, `Yesterday`, else `24 Sep`.
String stamp(DateTime t, DateTime now) {
  final DateTime a = DateTime(t.year, t.month, t.day);
  final DateTime b = DateTime(now.year, now.month, now.day);
  final int d = b.difference(a).inDays;
  if (d == 0) return clock(t);
  if (d == 1) return 'Yesterday';
  return t.year == now.year ? dm(t) : dmy(t);
}

/// `2 min ago`, `3 hr ago`, else a date.
String ago(DateTime t, DateTime now) {
  final Duration d = now.difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} hr ago';
  return stamp(t, now);
}

/// Parses `26 Sep 2026` (sample data) into a date.
DateTime? parseDmy(String s) {
  final List<String> p = s.trim().split(RegExp(r'\s+'));
  if (p.length != 3) return null;
  final int? d = int.tryParse(p[0]), y = int.tryParse(p[2]);
  final int m = kMonths.indexOf(p[1]) + 1;
  if (d == null || y == null || m == 0) return null;
  return DateTime(y, m, d);
}

/// Whole calendar days from [from] to [to] (date parts only).
int dayDiff(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// First letter, upper-cased; `?` for empty.
String initials(String? n) {
  final String t = (n ?? '?').trim();
  return t.isEmpty ? '' : t[0].toUpperCase();
}

/// `Number(x)||0` for form strings.
num numOf(String? s) => num.tryParse((s ?? '').trim()) ?? 0;

/// Stock quantity: whole numbers without decimals, else up to 3 places.
String qty(num q) => q == q.roundToDouble()
    ? q.toInt().toString()
    : q.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
