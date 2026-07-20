import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/contract/contract.dart';

/// Photo extensions D3 recognizes (lowercase, no dot).
const Set<String> kPhotoExtensions = {
  'jpg',
  'jpeg',
  'png',
  'heic',
  'heif',
  'webp',
  'bmp',
  'tiff',
  'tif',
};

/// Video extensions D3 recognizes (lowercase, no dot).
const Set<String> kVideoExtensions = {
  'mp4',
  'mov',
  'm4v',
  'avi',
  'mkv',
  'webm',
};

/// System/hidden basenames D3 always skips regardless of extension.
const Set<String> kIgnoredBasenames = {'Thumbs.db', 'desktop.ini'};

/// True when [basename] is a dotfile or a known OS-generated file
/// (`.DS_Store`, `Thumbs.db`, …) that must never be enumerated as media.
bool isIgnoredName(String basename) {
  if (basename.startsWith('.')) return true;
  return kIgnoredBasenames.contains(basename);
}

/// Classifies [path] into [ItemType.photo] / [ItemType.video] by extension;
/// `null` when unsupported. Takes an explicit [context] (rather than the
/// top-level `path` functions) so the same logic is provably correct for
/// both Windows- and macOS-style paths regardless of the host OS running
/// the test (D3 cross-OS regression bullet).
ItemType? classifyByExtension(String path, {p.Context? context}) {
  final ext = (context ?? p.context)
      .extension(path)
      .replaceFirst('.', '')
      .toLowerCase();
  if (ext.isEmpty) return null;
  if (kPhotoExtensions.contains(ext)) return ItemType.photo;
  if (kVideoExtensions.contains(ext)) return ItemType.video;
  return null;
}

/// One enumerated candidate file before hashing/dedup.
class MediaCandidate {
  const MediaCandidate({
    required this.path,
    required this.type,
    required this.size,
    required this.modifiedAt,
  });

  /// Absolute local filesystem path (never sent to `tagkin-api`; only a
  /// derived `sourceRef` is, via [BatchIngestController]).
  final String path;
  final ItemType type;
  final int size;
  final DateTime modifiedAt;
}

/// Recursively enumerates supported media under a root folder.
///
/// Uses `dart:io` + `package:path` only — never a hard-coded `/` or `\`
/// separator. Skips unsupported extensions, hidden/system files, and guards
/// against symlink loops via a resolved-path visited-set.
class MediaEnumerator {
  MediaEnumerator({p.Context? pathContext}) : _p = pathContext ?? p.context;

  final p.Context _p;

  Future<List<MediaCandidate>> enumerate(String rootPath) async {
    final root = Directory(rootPath);
    if (!await root.exists()) {
      throw ArgumentError('Folder does not exist: $rootPath');
    }
    final results = <MediaCandidate>[];
    final visitedDirs = <String>{};
    await _walk(root, results, visitedDirs);
    return results;
  }

  Future<void> _walk(
    Directory dir,
    List<MediaCandidate> results,
    Set<String> visitedDirs,
  ) async {
    String resolvedPath;
    try {
      resolvedPath = await dir.resolveSymbolicLinks();
    } on FileSystemException {
      return;
    }
    if (!visitedDirs.add(resolvedPath)) return;

    List<FileSystemEntity> entries;
    try {
      entries = await dir.list(followLinks: false).toList();
    } on FileSystemException {
      return;
    }

    for (final entity in entries) {
      final basename = _p.basename(entity.path);
      if (isIgnoredName(basename)) continue;

      if (entity is Directory) {
        await _walk(entity, results, visitedDirs);
        continue;
      }
      if (entity is File) {
        final type = classifyByExtension(entity.path, context: _p);
        if (type == null) continue;
        FileStat stat;
        try {
          stat = await entity.stat();
        } on FileSystemException {
          continue;
        }
        results.add(
          MediaCandidate(
            path: entity.path,
            type: type,
            size: stat.size,
            modifiedAt: stat.modified,
          ),
        );
      }
    }
  }
}

/// Top-level tear-off used as `BatchIngestController`'s default
/// `enumerateFolder` dependency — a plain function type is easier to
/// override in tests than a class instance.
Future<List<MediaCandidate>> enumerateMedia(String rootPath) =>
    MediaEnumerator().enumerate(rootPath);
