// Last successfully loaded backend responses, kept on the device so screens
// show the previous real data immediately after a restart while a fresh
// load runs in the background (stale-while-refresh). Stored as JSON in the
// app's private support directory; cleared on logout and company switch.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract interface class SnapshotCache {
  Future<Map<String, Object?>?> read(String key);
  Future<void> write(String key, Map<String, Object?> value);
  Future<void> clear(String key);
}

class FileSnapshotCache implements SnapshotCache {
  Future<File?> _file(String key) async {
    try {
      final Directory d = await getApplicationSupportDirectory();
      final String safe = key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      return File(p.join(d.path, 'tc_snapshot_$safe.json'));
    } catch (_) {
      return null; // no platform storage (tests) — cache simply off
    }
  }

  @override
  Future<Map<String, Object?>?> read(String key) async {
    try {
      final File? f = await _file(key);
      if (f == null || !f.existsSync()) return null;
      final Object? v = jsonDecode(await f.readAsString());
      return v is Map ? v.cast<String, Object?>() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, Map<String, Object?> value) async {
    try {
      final File? f = await _file(key);
      if (f == null) return;
      final File tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(value), flush: true);
      await tmp.rename(f.path);
    } catch (_) {}
  }

  @override
  Future<void> clear(String key) async {
    try {
      final File? f = await _file(key);
      if (f != null && f.existsSync()) await f.delete();
    } catch (_) {}
  }
}

/// In-memory cache (tests).
class MemorySnapshotCache implements SnapshotCache {
  final Map<String, Map<String, Object?>> _m = <String, Map<String, Object?>>{};
  @override
  Future<Map<String, Object?>?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, Map<String, Object?> value) async =>
      _m[key] = value;
  @override
  Future<void> clear(String key) async => _m.remove(key);
}
