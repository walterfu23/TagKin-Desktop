import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/prefs/desktop_prefs_store.dart';

/// Persists in-progress folder ingest roots so a crash can auto-resume.
///
/// JSON map of accountId → folder paths, under Application Support
/// (`active_folder_ingests.json`). Cleared when a job reaches a terminal
/// phase; a kill mid-job leaves the entry for the next signed-in session.
class ActiveFolderIngestStore {
  ActiveFolderIngestStore({Directory? supportDir})
      : _supportDirOverride = supportDir;

  final Directory? _supportDirOverride;

  Map<String, List<String>> _cache = {};
  bool _loaded = false;

  Future<File> _file() async {
    final dir = await tagkinAppSupportDir(override: _supportDirOverride);
    return File(p.join(dir.path, 'active_folder_ingests.json'));
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _file();
      if (!file.existsSync()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      final next = <String, List<String>>{};
      for (final e in decoded.entries) {
        if (e.key is! String || e.value is! List) continue;
        next[e.key as String] = [
          for (final v in e.value as List)
            if (v is String && v.isNotEmpty) p.normalize(v),
        ];
      }
      _cache = next;
    } catch (_) {
      _cache = {};
    }
  }

  Future<void> _persist() async {
    final file = await _file();
    await file.writeAsString(jsonEncode(_cache));
  }

  Future<List<String>> listForAccount(String accountId) async {
    await _ensureLoaded();
    return List<String>.from(_cache[accountId] ?? const []);
  }

  Future<void> add(String accountId, String folderPath) async {
    await _ensureLoaded();
    final normalized = p.normalize(folderPath);
    final current = List<String>.from(_cache[accountId] ?? const []);
    if (current.contains(normalized)) return;
    current.add(normalized);
    _cache[accountId] = current;
    await _persist();
  }

  Future<void> remove(String accountId, String folderPath) async {
    await _ensureLoaded();
    final normalized = p.normalize(folderPath);
    final current = List<String>.from(_cache[accountId] ?? const []);
    if (!current.contains(normalized)) return;
    current.remove(normalized);
    if (current.isEmpty) {
      _cache.remove(accountId);
    } else {
      _cache[accountId] = current;
    }
    await _persist();
  }
}

/// Process-wide store used by [FolderIngestQueue].
final activeFolderIngestStore = ActiveFolderIngestStore();
