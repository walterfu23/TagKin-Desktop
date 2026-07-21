import 'dart:io';

import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/content_hash.dart';

/// Outcome of resolving an item's authorized local media path (D8).
enum LocalMediaStatus { available, missing, hashMismatch, unsupported }

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

/// Resolves [item] to an authorized local file and optionally verifies
/// [Item.contentHash] against a fresh SHA-256 of the on-disk bytes.
///
/// Never uploads or sends bytes anywhere — local disk only (R1/R5/R7).
Future<LocalMediaResolution> resolveLocalMedia(
  Item item, {
  Future<String> Function(String path) contentHasher = computeContentHash,
  bool Function(String path)? fileExists,
}) async {
  if (item.sourceType != SourceType.local) {
    return const LocalMediaResolution(status: LocalMediaStatus.unsupported);
  }

  final path = localPathFromSourceRef(item.sourceRef);
  if (path == null) {
    return const LocalMediaResolution(status: LocalMediaStatus.missing);
  }

  final exists = fileExists ?? (p) => File(p).existsSync();
  if (!exists(path)) {
    return LocalMediaResolution(status: LocalMediaStatus.missing, path: path);
  }

  final expected = item.contentHash;
  if (expected != null && expected.isNotEmpty) {
    final actual = await contentHasher(path);
    if (actual != expected) {
      return LocalMediaResolution(
        status: LocalMediaStatus.hashMismatch,
        path: path,
        file: File(path),
      );
    }
  }

  return LocalMediaResolution(
    status: LocalMediaStatus.available,
    path: path,
    file: File(path),
  );
}
