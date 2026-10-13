// The user's own Gemini API key for the AI assistant: kept only in the
// platform keystore (Android Keystore / iOS Keychain), one per TallyConnect
// login, never in SharedPreferences or the data cache. It leaves the phone
// only inside the HTTPS request to the TallyConnect backend, which uses it
// for that one request and does not store it.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class AssistantKeyStore {
  Future<String?> read(String account);
  Future<void> write(String account, String key);
  Future<void> delete(String account);
}

class SecureAssistantKeyStore implements AssistantKeyStore {
  SecureAssistantKeyStore([FlutterSecureStorage? s])
    : _s = s ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;

  static String _k(String account) =>
      'tc-gemini-key-${account.trim().toLowerCase()}';

  @override
  Future<String?> read(String account) async {
    try {
      return await _s.read(key: _k(account));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String account, String key) async {
    try {
      await _s.write(key: _k(account), value: key);
    } catch (_) {}
  }

  @override
  Future<void> delete(String account) async {
    try {
      await _s.delete(key: _k(account));
    } catch (_) {}
  }
}

/// In-memory store (tests and platforms without a keystore).
class MemoryAssistantKeyStore implements AssistantKeyStore {
  final Map<String, String> keys = <String, String>{};
  @override
  Future<String?> read(String account) async => keys[account];
  @override
  Future<void> write(String account, String key) async => keys[account] = key;
  @override
  Future<void> delete(String account) async => keys.remove(account);
}
