import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/persons/collection.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_store.dart';

/// Loads/saves [CollectionsFile] as JSON under Application Support.
class CollectionsStore {
  CollectionsStore({Directory? supportDir, this.accountKey})
    : _supportDirOverride = supportDir;

  final Directory? _supportDirOverride;

  /// Firebase user id for this catalog. Null keeps the shared file, used by
  /// Clerk and by tests that do not switch accounts.
  String? accountKey;

  Future<File> _file() async {
    final dir = await tagkinAppSupportDir(override: _supportDirOverride);
    final key = accountKey;
    final name = (key == null || key.isEmpty)
        ? 'collections.json'
        : 'collections.${key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.json';
    return File(p.join(dir.path, name));
  }

  Future<CollectionsFile> load() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return CollectionsFile.empty;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return CollectionsFile.empty;
      return CollectionsFile.fromJson(
        decoded.map((k, v) => MapEntry(k.toString(), v)),
      );
    } catch (_) {
      return CollectionsFile.empty;
    }
  }

  Future<void> save(CollectionsFile catalog) async {
    final file = await _file();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(catalog.toJson()),
    );
  }
}

/// In-memory [CollectionsStore] for widget tests (avoids fake-async IO hangs).
class MemoryCollectionsStore extends CollectionsStore {
  MemoryCollectionsStore([CollectionsFile initial = CollectionsFile.empty])
    : _slots = {'': initial};

  final Map<String, CollectionsFile> _slots;

  String get _slot => accountKey ?? '';

  @override
  Future<CollectionsFile> load() async =>
      _slots[_slot] ?? CollectionsFile.empty;

  @override
  Future<void> save(CollectionsFile catalog) async {
    _slots[_slot] = catalog;
  }
}
