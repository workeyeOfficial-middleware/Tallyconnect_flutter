// Dialable numbers from a Tally phone field, which is free text: one or
// more numbers, separated by commas, slashes, "or", new lines…, with
// spaces, dashes, brackets, extensions or labels mixed in.
library;

/// Digits a dialable number may have (international numbers are at most
/// 15; local landlines without the area code are at least 6).
const int kMinPhoneDigits = 6;
const int kMaxPhoneDigits = 15;

/// Every dialable number in [raw], in order, without duplicates. Each is
/// digits only, with a leading `+` when the number had one (`00` country
/// prefixes become `+`). Nothing dialable → empty.
List<String> dialableNumbers(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const <String>[];
  final List<String> out = <String>[];
  void add(String n) {
    if (!out.contains(n)) out.add(n);
  }

  // Extensions are not dialled ("x 12", "ext. 12", "extn 12").
  final String noExt = raw.replaceAll(
    RegExp(r'\b(?:ext|extn|x)\.?\s*\d+', caseSensitive: false),
    ' ',
  );
  for (final String part in noExt.split(
    RegExp(r'[,;/|\n\r]+|\s+(?:or|and)\s+|&', caseSensitive: false),
  )) {
    final String digits = part.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) continue;
    if (digits.length <= kMaxPhoneDigits) {
      final String? n = _number(part);
      if (n != null) add(n);
      continue;
    }
    // Too many digits for one number: several numbers separated only by
    // spaces ("98200 12345 98201 54321"). Group the space-separated pieces
    // into numbers of at least 10 digits.
    final StringBuffer cur = StringBuffer();
    for (final String piece in part.trim().split(RegExp(r'\s+'))) {
      cur.write(piece);
      if (cur.toString().replaceAll(RegExp(r'\D'), '').length >= 10) {
        final String? n = _number(cur.toString());
        if (n != null) add(n);
        cur.clear();
      }
    }
  }
  return out;
}

String? _number(String part) {
  final String t = part.trim();
  String digits = t.replaceAll(RegExp(r'\D'), '');
  bool plus = RegExp(r'^\s*\+').hasMatch(t);
  if (!plus && digits.startsWith('00') && digits.length > 10) {
    digits = digits.substring(2);
    plus = true;
  }
  if (digits.length < kMinPhoneDigits || digits.length > kMaxPhoneDigits) {
    return null;
  }
  return plus ? '+$digits' : digits;
}

/// `tel:` link that opens the dialer with [number] (does not call).
Uri telUri(String number) => Uri(scheme: 'tel', path: number);

/// A dialable number for display: "+91 98200 12345" / "98200 12345".
String phoneLabel(String n) {
  final bool plus = n.startsWith('+');
  final String d = plus ? n.substring(1) : n;
  if (plus && d.startsWith('91') && d.length == 12) {
    return '+91 ${d.substring(2, 7)} ${d.substring(7)}';
  }
  if (!plus && d.length == 10) return '${d.substring(0, 5)} ${d.substring(5)}';
  return n;
}
