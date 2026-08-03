import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/persons/collection.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_store.dart';

/// Loads/saves [CollectionsFile] as JSON under Application Support.
class CollectionsStore {
  CollectionsStore({Directory? supportDir}) : _supportDirOverride = supportDir;

  final Directory? _supportDirOverride;

  Future<File> _file() async {
    final dir = await tagkinAppSupportDir(override: _supportDirOverride);
    return File(p.join(dir.path, 'collections.json'));
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
      : _data = initial;

  CollectionsFile _data;

  @override
  Future<CollectionsFile> load() async => _data;

  @override
  Future<void> save(CollectionsFile catalog) async {
    _data = catalog;
  }
}
