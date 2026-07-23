import 'dart:io';

import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/content_hash.dart';
import 'package:tagkin_desktop/ingest/folder_bookmark_store.dart';

/// Outcome of resolving an item's authorized local media path (D8).
enum LocalMediaStatus {
  available,
  missing,
  hashMismatch,
  unsupported,
  /// macOS App Sandbox denied the path (bookmark missing / expired).
  accessDenied,
}

/// Result of [resolveLocalMedia] — bytes stay on local disk only (R1/R5/R7).
class LocalMediaResolution {
  const LocalMediaResolution({
    required this.status,
    this.file,
    this.path,
  });

  final LocalMediaStatus status;
  final File? file;
  final String? path;

  bool get isAvailable => status == LocalMediaStatus.available && file != null;
}

/// Parses a `file://` [Item.sourceRef] into a local filesystem path.
///
/// Returns null when the ref is missing or not a file URI.
String? localPathFromSourceRef(String? sourceRef) {
  if (sourceRef == null || sourceRef.isEmpty) return null;
  final uri = Uri.tryParse(sourceRef);
  if (uri == null) return null;
  if (uri.scheme == 'file') return uri.toFilePath();
  // Bare absolute paths (rare) — accept only when they look absolute.
  if (sourceRef.startsWith('/') ||
      (sourceRef.length > 2 && sourceRef[1] == ':')) {
    return sourceRef;
  }
  return null;
}

bool _isAccessDenied(Object e) {
  if (e is PathAccessException) return true;
  if (e is FileSystemException) {
    // errno 1 = EPERM (Operation not permitted) on macOS sandbox denial.
    return e.osError?.errorCode == 1;
  }
  return false;
}

/// Resolves [item] to an authorized local file and optionally verifies
/// [Item.contentHash] against a fresh SHA-256 of the on-disk bytes.
///
/// Never uploads or sends bytes anywhere — local disk only (R1/R5/R7).
/// On macOS, starts a stored security-scoped bookmark when present.
Future<LocalMediaResolution> resolveLocalMedia(
  Item item, {
  Future<String> Function(String path) contentHasher = computeContentHash,
  bool Function(String path)? fileExists,
  FolderBookmarkStore? bookmarks,
  Future<void> Function(String bookmark)? startAccess,
}) async {
  if (item.sourceType != SourceType.local) {
    return const LocalMediaResolution(status: LocalMediaStatus.unsupported);
  }

  final path = localPathFromSourceRef(item.sourceRef);
  if (path == null) {
    return const LocalMediaResolution(status: LocalMediaStatus.missing);
  }

  final store = bookmarks ?? folderBookmarkStore;
  final start = startAccess ??
      (SecurityScopedBookmarks.isSupported
          ? SecurityScopedBookmarks.startAccess
          : null);

  String? activeBookmark;
  try {
    if (start != null) {
      final bookmark = await store.bookmarkForFile(path);
      if (bookmark != null) {
        await start(bookmark);
        activeBookmark = bookmark;
      }
    }

    final exists = fileExists ??
        (p) {
          try {
            return File(p).existsSync();
          } catch (e) {
            if (_isAccessDenied(e)) rethrow;
            return false;
          }
        };

    try {
      if (!exists(path)) {
        return LocalMediaResolution(status: LocalMediaStatus.missing, path: path);
      }
    } catch (e) {
      if (_isAccessDenied(e)) {
        return LocalMediaResolution(
          status: LocalMediaStatus.accessDenied,
          path: path,
        );
      }
      rethrow;
    }

    final expected = item.contentHash;
    if (expected != null && expected.isNotEmpty) {
      try {
        final actual = await contentHasher(path);
        if (actual != expected) {
          return LocalMediaResolution(
            status: LocalMediaStatus.hashMismatch,
            path: path,
            file: File(path),
          );
        }
      } catch (e) {
        if (_isAccessDenied(e)) {
          return LocalMediaResolution(
            status: LocalMediaStatus.accessDenied,
            path: path,
          );
        }
        rethrow;
      }
    }

    return LocalMediaResolution(
      status: LocalMediaStatus.available,
      path: path,
      file: File(path),
    );
  } catch (e) {
    if (_isAccessDenied(e)) {
      return LocalMediaResolution(
        status: LocalMediaStatus.accessDenied,
        path: path,
      );
    }
    rethrow;
  } finally {
    // Keep bookmark access alive for the process after first startAccess in
    // pickFolder; stopAccess is only needed if we want to release early.
    // Intentionally leave started scopes open for subsequent Image.file / hash.
    assert(activeBookmark == null || activeBookmark.isNotEmpty);
  }
}
