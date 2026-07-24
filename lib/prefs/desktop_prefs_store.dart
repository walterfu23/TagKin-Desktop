import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/prefs/desktop_prefs.dart';

/// Application Support (macOS) / APPDATA (Windows) directory for desktop prefs.
Future<Directory> tagkinAppSupportDir({Directory? override}) async {
  if (override != null) {
    if (!override.existsSync()) {
      await override.create(recursive: true);
    }
    return override;
  }
  if (!kIsWeb && Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) {
      throw StateError('APPDATA not set');
    }
    final dir = Directory(p.join(appData, 'tagkin_desktop'));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    throw StateError('HOME not set');
  }
  final dir = Directory(
    p.join(home, 'Library', 'Application Support', 'tagkin_desktop'),
  );
  if (!dir.existsSync()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// Loads/saves [DesktopPrefs] as JSON under Application Support.
class DesktopPrefsStore {
  DesktopPrefsStore({Directory? supportDir}) : _supportDirOverride = supportDir;

  final Directory? _supportDirOverride;

  Future<File> _file() async {
    final dir = await tagkinAppSupportDir(override: _supportDirOverride);
    return File(p.join(dir.path, 'desktop_prefs.json'));
  }

  Future<DesktopPrefs> load() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return DesktopPrefs.defaults;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return DesktopPrefs.defaults;
      return DesktopPrefs.fromJson(
        decoded.map((k, v) => MapEntry(k.toString(), v)),
      );
    } catch (_) {
      return DesktopPrefs.defaults;
    }
  }

  Future<void> save(DesktopPrefs prefs) async {
    final file = await _file();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(prefs.toJson()),
    );
  }
}
