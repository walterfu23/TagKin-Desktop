import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// macOS security-scoped bookmark helpers (no-ops elsewhere).
///
/// Channel implemented in `macos/Runner/SecurityScopedBookmarksPlugin.swift`.
class SecurityScopedBookmarks {
  SecurityScopedBookmarks._();

  static const MethodChannel _channel = MethodChannel(
    'tagkin_desktop/security_scoped_bookmarks',
  );

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  /// Native folder picker that returns path + bookmark in one step.
  static Future<({String path, String bookmarkBase64})?> pickFolder() async {
    if (!isSupported) return null;
    final raw = await _channel.invokeMethod<dynamic>('pickFolder');
    if (raw is! Map) return null;
    final path = raw['path'];
    final bookmark = raw['bookmarkBase64'];
    if (path is! String || bookmark is! String) return null;
    if (path.isEmpty || bookmark.isEmpty) return null;
    return (path: path, bookmarkBase64: bookmark);
  }

  static Future<String> startAccess(String bookmarkBase64) async {
    final path = await _channel.invokeMethod<String>(
      'startAccess',
      bookmarkBase64,
    );
    if (path == null || path.isEmpty) {
      throw StateError('startAccess returned empty path');
    }
    return path;
  }

  static Future<void> stopAccess(String bookmarkBase64) async {
    await _channel.invokeMethod<void>('stopAccess', bookmarkBase64);
  }
}

/// Persists folder bookmarks under Application Support so local media remains
/// readable after hot restart / relaunch (App Sandbox).
class FolderBookmarkStore {
  FolderBookmarkStore({Directory? supportDir}) : _supportDirOverride = supportDir;

  final Directory? _supportDirOverride;

  /// folderPath → bookmarkBase64
  Map<String, String> _cache = {};
  bool _loaded = false;

  Future<Directory> _dir() async {
    final override = _supportDirOverride;
    if (override != null) return override;
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

  Future<File> _file() async {
    final dir = await _dir();
    return File(p.join(dir.path, 'folder_bookmarks.json'));
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _file();
      if (!file.existsSync()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        _cache = {
          for (final e in decoded.entries)
            if (e.key is String && e.value is String) e.key as String: e.value as String,
        };
      }
    } catch (_) {
      _cache = {};
    }
  }

  Future<void> _persist() async {
    final file = await _file();
    await file.writeAsString(jsonEncode(_cache));
  }

  Future<void> save(String folderPath, String bookmarkBase64) async {
    await _ensureLoaded();
    final normalized = p.normalize(folderPath);
    _cache[normalized] = bookmarkBase64;
    await _persist();
  }

  /// Longest bookmarked folder prefix of [filePath], if any.
  Future<String?> bookmarkForFile(String filePath) async {
    await _ensureLoaded();
    final normalized = p.normalize(filePath);
    String? best;
    for (final folder in _cache.keys) {
      final prefix = folder.endsWith(p.separator) ? folder : '$folder${p.separator}';
      if (normalized == folder || normalized.startsWith(prefix)) {
        if (best == null || folder.length > best.length) {
          best = folder;
        }
      }
    }
    return best == null ? null : _cache[best];
  }
}

/// Process-wide store used by folder pick + local media resolve.
final folderBookmarkStore = FolderBookmarkStore();
