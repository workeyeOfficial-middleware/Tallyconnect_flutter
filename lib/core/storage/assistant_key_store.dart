// The user's own AI provider keys for the AI assistant: kept only in the
// platform keystore (Android Keystore / iOS Keychain), one per provider per
// TallyConnect login, never in SharedPreferences or the data cache. A key
// leaves the phone only inside the HTTPS request to the TallyConnect
// backend, which uses it for that one request and does not store it.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class AssistantKeyStore {
  Future<String?> read(String account, {String provider = 'gemini'});
  Future<void> write(String account, String key, {String provider = 'gemini'});
  Future<void> delete(String account, {String provider = 'gemini'});
}

/// Storage name of a key. Gemini keeps its original name, so keys saved
/// before other providers existed are still found.
String assistantKeyName(String account, String provider) {
  final String a = account.trim().toLowerCase();
  return provider == 'gemini' ? 'tc-gemini-key-$a' : 'tc-ai-key-$provider-$a';
}

class SecureAssistantKeyStore implements AssistantKeyStore {
  SecureAssistantKeyStore([FlutterSecureStorage? s])
    : _s = s ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String account, {String provider = 'gemini'}) async {
    try {
      return await _s.read(key: assistantKeyName(account, provider));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(
    String account,
    String key, {
    String provider = 'gemini',
  }) async {
    try {
      await _s.write(key: assistantKeyName(account, provider), value: key);
    } catch (_) {}
  }

  @override
  Future<void> delete(String account, {String provider = 'gemini'}) async {
    try {
      await _s.delete(key: assistantKeyName(account, provider));
    } catch (_) {}
  }
}

/// In-memory store (tests and platforms without a keystore). Gemini keys
/// are stored under the account alone, other providers as
/// `provider:account`.
class MemoryAssistantKeyStore implements AssistantKeyStore {
  final Map<String, String> keys = <String, String>{};
  static String _k(String account, String provider) =>
      provider == 'gemini' ? account : '$provider:$account';
  @override
  Future<String?> read(String account, {String provider = 'gemini'}) async =>
      keys[_k(account, provider)];
  @override
  Future<void> write(
    String account,
    String key, {
    String provider = 'gemini',
  }) async => keys[_k(account, provider)] = key;
  @override
  Future<void> delete(String account, {String provider = 'gemini'}) async =>
      keys.remove(_k(account, provider));
}
