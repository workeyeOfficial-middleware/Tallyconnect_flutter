// Last successfully loaded backend responses, kept on the device so screens
// show the previous real data immediately after a restart while a fresh
// load runs in the background (stale-while-refresh).
//
// One file per user and data set, holding the server's JSON text exactly as
// received: nothing large is encoded or decoded on the UI thread to save it,
// and one big set never forces rewriting the others. The complete voucher
// history is never cached (only the current month). Cleared on logout and
// company switch.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract interface class SnapshotCache {
  Future<String?> read(String user, String set);
  Future<void> write(String user, String set, String json);

  /// Removes every saved set of [user].
  Future<void> clear(String user);
}

String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

class FileSnapshotCache implements SnapshotCache {
  Future<Directory?> _dir() async {
    try {
      final Directory d = Directory(
        p.join((await getApplicationSupportDirectory()).path, 'tc_snapshots'),
      );
      if (!d.existsSync()) await d.create(recursive: true);
      return d;
    } catch (_) {
      return null; // no platform storage (tests) — cache simply off
    }
  }

  Future<File?> _file(String user, String set) async {
    final Directory? d = await _dir();
    return d == null
        ? null
        : File(p.join(d.path, '${_safe(user)}__${_safe(set)}.json'));
  }

  @override
  Future<String?> read(String user, String set) async {
    try {
      final File? f = await _file(user, set);
      if (f == null || !f.existsSync()) return null;
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String user, String set, String json) async {
    try {
      final File? f = await _file(user, set);
      if (f == null) return;
      final File tmp = File('${f.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(f.path);
    } catch (_) {}
  }

  @override
  Future<void> clear(String user) async {
    try {
      final Directory? d = await _dir();
      if (d == null) return;
      final String prefix = '${_safe(user)}__';
      await for (final FileSystemEntity e in d.list()) {
        if (p.basename(e.path).startsWith(prefix)) await e.delete();
      }
    } catch (_) {}
  }
}

/// In-memory cache (tests).
class MemorySnapshotCache implements SnapshotCache {
  final Map<String, String> _m = <String, String>{};
  @override
  Future<String?> read(String user, String set) async => _m['$user|$set'];
  @override
  Future<void> write(String user, String set, String json) async =>
      _m['$user|$set'] = json;
  @override
  Future<void> clear(String user) async =>
      _m.removeWhere((String k, _) => k.startsWith('$user|'));
}
