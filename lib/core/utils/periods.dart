// The standard report periods, the same on every report and list: All time,
// Today, Yesterday, Last 7 days, This month, Next month, Current financial
// year, Previous financial year, and a custom date range. Indian financial
// year: 1 April – 31 March.
library;

/// The standard periods (key, label), in display order. A custom date
/// range (`range`, "Custom date range") comes after them.
const List<(String, String)> kStdPeriods = <(String, String)>[
  ('all', 'All time'),
  ('today', 'Today'),
  ('yesterday', 'Yesterday'),
  ('week', 'Last 7 days'),
  ('month', 'This month'),
  ('next', 'Next month'),
  ('fy', 'Current financial year'),
  ('pfy', 'Previous financial year'),
];

/// Label of the custom date range option.
const String kCustomRange = 'Custom date range';

/// 1 April of the financial year holding [d].
DateTime fyStartOf(DateTime d) =>
    DateTime(d.month >= 4 ? d.year : d.year - 1, 4);

/// From–To (both days included) of standard period [k] on [today]; null
/// for All time or an unknown key. This month and the current financial
/// year run to today; Next month and the previous year are whole.
(DateTime, DateTime)? stdPeriodRange(String k, DateTime today) {
  final DateTime t = DateTime(today.year, today.month, today.day);
  final DateTime fy = fyStartOf(t);
  return switch (k) {
    'today' => (t, t),
    'yesterday' => (
      DateTime(t.year, t.month, t.day - 1),
      DateTime(t.year, t.month, t.day - 1),
    ),
    'week' => (DateTime(t.year, t.month, t.day - 6), t),
    'month' => (DateTime(t.year, t.month), t),
    'next' => (DateTime(t.year, t.month + 1), DateTime(t.year, t.month + 2, 0)),
    'fy' => (fy, t),
    'pfy' => (DateTime(fy.year - 1, 4), DateTime(fy.year, 4, 0)),
    _ => null,
  };
}
