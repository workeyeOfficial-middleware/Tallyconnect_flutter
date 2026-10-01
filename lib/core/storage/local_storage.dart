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
