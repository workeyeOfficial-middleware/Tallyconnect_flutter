// Email addresses from a Tally email field, which is free text: one or more
// addresses separated by commas, semicolons, slashes, spaces or new lines,
// sometimes with labels or a `mailto:` prefix.
library;

final RegExp _email = RegExp(
  r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}',
);

/// Every valid address in [raw], in order, without duplicates (compared
/// without case). Nothing valid → empty.
List<String> emailAddresses(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const <String>[];
  final List<String> out = <String>[];
  for (final RegExpMatch m in _email.allMatches(raw)) {
    final String e = m[0]!.replaceAll(RegExp(r'\.+$'), '');
    if (!out.any((String x) => x.toLowerCase() == e.toLowerCase())) out.add(e);
  }
  return out;
}

/// `mailto:` link that opens the email app with [address] as the recipient
/// (nothing is sent until the user sends it there).
Uri mailUri(String address) => Uri(scheme: 'mailto', path: address);
