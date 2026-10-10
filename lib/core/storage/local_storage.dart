// localStorage → SharedPreferences with the prototype's exact keys
// (`loadJ` / `saveJ`, Main.dc.html 1869–1873). Values are JSON strings.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalStorage {
  LocalStorage(this._p);

  /// In-memory store for tests and platforms without prefs.
  LocalStorage.memory() : _p = null;

  final SharedPreferences? _p;
  final Map<String, String> _mem = <String, String>{};

  static Future<LocalStorage> open() async {
    try {
      return LocalStorage(await SharedPreferences.getInstance());
    } catch (_) {
      return LocalStorage.memory();
    }
  }

  static const String kPages = 'tc-liquid-pages-v2';
  static const String kHidden = 'tc-liquid-hidden-v2';
  static const String kPinned = 'tc-liquid-pinned';
  static const String kPage = 'tc-liquid-page-v2';
  static const String kTabs = 'tc-liquid-tabs';
  static const String kLists = 'tc-liquid-lists';
  static const String kPreset = 'tc-liquid-preset';
  static const String kAccent = 'tc-liquid-accent';
  static const String kMode = 'tc-liquid-mode';
  static const String kCustom = 'tc-liquid-custom';
  static const String kWall = 'tc-liquid-wall';
  static const String kPhoto = 'tc-liquid-photo';
  static const String kBgOpacity = 'tc-liquid-bg-opacity';
  static const String kBgShade = 'tc-liquid-bg-shade';
  static const String kReminders = 'tc-outstanding-reminders';

  /// Due-bill alerts switch (3 days before due) and the notification ids
  /// armed for it.
  static const String kAutoRemind = 'tc-due-alerts-on';
  static const String kDueAlertIds = 'tc-due-alert-ids';

  /// Name / company-role / mobile entered in Add person, by email (the
  /// server's create-user endpoint stores only email + password).
  static const String kMemberInfo = 'tc-team-member-info';

  /// Bottom-bar tabs the user hid (tab keys), the whole bar hidden, and the
  /// glass level (Settings → Look → Glass).
  static const String kHiddenTabs = 'tc-hidden-tabs';
  static const String kNavHidden = 'tc-nav-hidden';
  static const String kGlass = 'tc-liquid-glass';

  /// Glass see-through 20–100 % (higher = clearer). Replaces [kGlass],
  /// whose scale ran the other way.
  static const String kGlassClear = 'tc-glass-clear';

  /// Text colour −100 (lighter) … 0 (automatic) … +100 (darker).
  static const String kTextTone = 'tc-text-tone';

  /// Date range picked for the filters: {from, to} (`yyyy-mm-dd`).
  static const String kDateRange = 'tc-date-range';

  /// Reports period: `month` | `all` | `range`.
  static const String kRepPeriod = 'tc-report-period';

  /// Theme-matched app icon: switch on/off, launcher variant last applied,
  /// exact-colour shortcut pinned + its last colours.
  static const String kIconMatch = 'tc-icon-match';

  /// Server alert ids already shown as phone notifications; notification
  /// permission asked once.
  static const String kSeenAlerts = 'tc-seen-alerts';
  static const String kNotifAsked = 'tc-notif-asked';
  static const String kIconApplied = 'tc-icon-applied';
  static const String kIconShortcut = 'tc-icon-shortcut';

  /// Low-stock alerts switch, and per company the items last seen out of
  /// stock (so only items that newly run out raise an alert).
  static const String kLowStockOn = 'tc-low-stock-alerts-on';
  static const String kOutStock = 'tc-out-of-stock-items';

  /// `loadJ(k, d)`.
  T load<T>(String k, T d) {
    try {
      final String? raw = _p != null ? _p.getString(k) : _mem[k];
      if (raw == null) return d;
      final Object? v = jsonDecode(raw);
      if (v == null) return d;
      if (v is T) return v as T;
      return d;
    } catch (_) {
      return d;
    }
  }

  /// `saveJ(k, v)`.
  void save(String k, Object? v) {
    try {
      final String s = jsonEncode(v);
      if (_p != null) {
        _p.setString(k, s);
      } else {
        _mem[k] = s;
      }
    } catch (_) {}
  }

  /// `loadOrder()`: a permutation of 0..4, else the default.
  List<int> loadTabOrder() {
    final Object? v = load<Object?>(kTabs, null);
    if (v is List && v.length == 5) {
      final List<int> o = v.whereType<num>().map((num e) => e.toInt()).toList();
      if (o.length == 5 && <int>[0, 1, 2, 3, 4].every(o.contains)) return o;
    }
    return <int>[0, 1, 2, 3, 4];
  }
}
