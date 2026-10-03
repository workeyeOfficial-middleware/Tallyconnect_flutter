// Keeps the login token and user in the platform keystore (Android
// Keystore / iOS Keychain) — never in plain SharedPreferences.
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/models/models.dart';

abstract interface class SessionStore {
  Future<({String token, AuthUser user})?> read();
  Future<void> write(String token, AuthUser user);
  Future<void> clear();
}

class SecureSessionStore implements SessionStore {
  SecureSessionStore([FlutterSecureStorage? s])
    : _s = s ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;

  static const String _kToken = 'tc-session-token';
  static const String _kUser = 'tc-session-user';

  @override
  Future<({String token, AuthUser user})?> read() async {
    try {
      final String? t = await _s.read(key: _kToken);
      final String? u = await _s.read(key: _kUser);
      if (t == null || u == null) return null;
      final AuthUser? user = AuthUser.fromJson(jsonDecode(u));
      if (user == null || jwtExpired(t)) return null;
      return (token: t, user: user);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String token, AuthUser user) async {
    try {
      await _s.write(key: _kToken, value: token);
      await _s.write(key: _kUser, value: jsonEncode(user.toJson()));
    } catch (_) {}
  }

  @override
  Future<void> clear() async {
    try {
      await _s.delete(key: _kToken);
      await _s.delete(key: _kUser);
    } catch (_) {}
  }
}

/// In-memory store (tests).
class MemorySessionStore implements SessionStore {
  ({String token, AuthUser user})? _v;
  @override
  Future<({String token, AuthUser user})?> read() async => _v;
  @override
  Future<void> write(String token, AuthUser user) async =>
      _v = (token: token, user: user);
  @override
  Future<void> clear() async => _v = null;
}

/// True when the JWT `exp` claim is in the past (or unreadable). The backend
/// issues 1-day tokens and has no refresh endpoint.
bool jwtExpired(String token, {DateTime? now}) {
  try {
    final List<String> parts = token.split('.');
    if (parts.length != 3) return true;
    final String norm = base64Url.normalize(parts[1]);
    final Object? claims = jsonDecode(utf8.decode(base64Url.decode(norm)));
    if (claims is! Map) return true;
    final Object? exp = claims['exp'];
    if (exp is! num) return false;
    final DateTime at = DateTime.fromMillisecondsSinceEpoch(
      exp.toInt() * 1000,
      isUtc: true,
    );
    return !(now ?? DateTime.now()).toUtc().isBefore(
      at.subtract(const Duration(minutes: 1)),
    );
  } catch (_) {
    return true;
  }
}
