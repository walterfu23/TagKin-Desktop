import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/folder_bookmark_store.dart';
import 'package:tagkin_desktop/prepass/auto_fix_blurry.dart';
import 'package:tagkin_desktop/prepass/ffmpeg_resolve.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';

/// Long edge for cached photo/video poster thumbs (library table).
const int kLibraryThumbLongEdge = 128;

/// Result of resolving a library-table thumbnail (local disk only — R1/R5).
class LocalThumbResult {
  const LocalThumbResult({
    required this.status,
    this.path,
  });

  final LocalMediaStatus status;
  final String? path;

  bool get hasImage =>
      status == LocalMediaStatus.available && path != null && path!.isNotEmpty;
}

/// Caches downscaled photo JPEGs, video poster frames, and key-period stills.
///
/// Uses security-scoped bookmarks on macOS (same as D8) so sandboxed paths
/// are readable. Never uploads bytes.
class LocalThumbCache {
  LocalThumbCache({
    this.cacheRoot,
    this.runFfmpeg,
    this.bookmarks,
    this.startAccess,
  });

  /// Optional durable cache directory (defaults to a system temp folder).
  Directory? cacheRoot;

  /// Optional ffmpeg runner for tests; when set, skips PATH/bundle lookup.
  final Future<List<int>> Function(String ffmpeg, List<String> args)? runFfmpeg;

  final FolderBookmarkStore? bookmarks;
  final Future<void> Function(String bookmark)? startAccess;

  Directory? _resolvedCacheRoot;

  final Map<String, LocalThumbResult> _memory = {};

  String _key(Item item) =>
      '${item.id}:${item.contentHash ?? ''}:${item.type.wire}';

  String _periodKey(Item item, String keyPeriodId, int timestampMs) =>
      '${_key(item)}:kp:$keyPeriodId:$timestampMs';

  /// Clears in-memory entries (e.g. after library reload).
  void clear() => _memory.clear();

  /// Resolves a displayable local thumb path for [item].
  Future<LocalThumbResult> resolve(Item item) async {
    final memKey = _key(item);
    final cached = _memory[memKey];
    if (cached != null) return cached;

    final opened = await _openSource(item);
    if (opened.result != null) return _storeKey(memKey, opened.result!);
    final sourcePath = opened.path!;

    if (item.type == ItemType.photo) {
      return _storeKey(memKey, await _downscaledPhoto(item, sourcePath));
    }

    final hash = item.contentHash ?? 'nohash';
    final root = await _ensureCacheRoot();
    final outPath = p.join(root.path, '${item.id}_$hash.jpg');
    return _storeKey(
      memKey,
      await _extractVideoJpeg(
        videoPath: sourcePath,
        outPath: outPath,
        ssSeconds: 0,
      ),
    );
  }

  /// Still at [timestampMs] for a video key period (local ffmpeg only — R1).
  Future<LocalThumbResult> resolveKeyPeriod(
    Item item, {
    required String keyPeriodId,
    required int timestampMs,
  }) async {
    final memKey = _periodKey(item, keyPeriodId, timestampMs);
    final cached = _memory[memKey];
    if (cached != null) return cached;

    if (item.type != ItemType.video) {
      return _storeKey(
        memKey,
        const LocalThumbResult(status: LocalMediaStatus.unsupported),
      );
    }

    final opened = await _openSource(item);
    if (opened.result != null) return _storeKey(memKey, opened.result!);
    final sourcePath = opened.path!;

    final hash = item.contentHash ?? 'nohash';
    final root = await _ensureCacheRoot();
    final safeKp = keyPeriodId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final outPath = p.join(
      root.path,
      '${item.id}_${hash}_kp_${safeKp}_$timestampMs.jpg',
    );
    final ss = (timestampMs < 0 ? 0 : timestampMs) / 1000.0;
    return _storeKey(
      memKey,
      await _extractVideoJpeg(
        videoPath: sourcePath,
        outPath: outPath,
        ssSeconds: ss,
      ),
    );
  }

  Future<({String? path, LocalThumbResult? result})> _openSource(
    Item item,
  ) async {
    var sourcePath = localPathFromSourceRef(item.sourceRef);
    if (sourcePath == null) {
      return (
        path: null,
        result: const LocalThumbResult(status: LocalMediaStatus.unsupported),
      );
    }

    await _ensureBookmarkAccess(sourcePath);

    try {
      if (!await File(sourcePath).exists()) {
        return (
          path: null,
          result: const LocalThumbResult(status: LocalMediaStatus.missing),
        );
      }
    } on PathAccessException {
      return (
        path: null,
        result: const LocalThumbResult(status: LocalMediaStatus.accessDenied),
      );
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode == 1) {
        return (
          path: null,
          result: const LocalThumbResult(status: LocalMediaStatus.accessDenied),
        );
      }
      return (
        path: null,
        result: const LocalThumbResult(status: LocalMediaStatus.missing),
      );
    }

    if (item.type == ItemType.photo) {
      sourcePath = await preferSharpenedStillPath(
        sourcePath: sourcePath,
        contentHash: item.contentHash,
      );
      await _ensureBookmarkAccess(sourcePath);
    }

    return (path: sourcePath, result: null);
  }

  Future<void> _ensureBookmarkAccess(String sourcePath) async {
    if (!SecurityScopedBookmarks.isSupported) return;
    final store = bookmarks ?? folderBookmarkStore;
    final start = startAccess ?? SecurityScopedBookmarks.startAccess;
    final bookmark = await store.bookmarkForFile(sourcePath);
    if (bookmark == null) return;
    try {
      await start(bookmark);
    } catch (_) {
      // Fall through; exists()/read may still fail with accessDenied.
    }
  }

  Future<LocalThumbResult> _downscaledPhoto(Item item, String sourcePath) async {
    final root = await _ensureCacheRoot();
    final hash = item.contentHash ?? 'nohash';
    final outPath = p.join(root.path, '${item.id}_${hash}_thumb.jpg');
    final outFile = File(outPath);
    if (await outFile.exists()) {
      return LocalThumbResult(
        status: LocalMediaStatus.available,
        path: outPath,
      );
    }

    try {
      final bytes = await File(sourcePath).readAsBytes();
      final decoded = img.decodeImage(Uint8List.fromList(bytes));
      if (decoded == null) {
        // Undecodable (e.g. HEIC) — fall back to original path for Image.file.
        return LocalThumbResult(
          status: LocalMediaStatus.available,
          path: sourcePath,
        );
      }
      final resized = _fitLongEdge(decoded, kLibraryThumbLongEdge);
      final jpeg = img.encodeJpg(resized, quality: 85);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(jpeg, flush: true);
      return LocalThumbResult(
        status: LocalMediaStatus.available,
        path: outPath,
      );
    } on PathAccessException {
      return const LocalThumbResult(status: LocalMediaStatus.accessDenied);
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode == 1) {
        return const LocalThumbResult(status: LocalMediaStatus.accessDenied);
      }
      return const LocalThumbResult(status: LocalMediaStatus.unsupported);
    } catch (_) {
      return const LocalThumbResult(status: LocalMediaStatus.unsupported);
    }
  }

  static img.Image _fitLongEdge(img.Image source, int longEdge) {
    final w = source.width;
    final h = source.height;
    if (w <= longEdge && h <= longEdge) return source;
    if (w >= h) {
      return img.copyResize(
        source,
        width: longEdge,
        interpolation: img.Interpolation.average,
      );
    }
    return img.copyResize(
      source,
      height: longEdge,
      interpolation: img.Interpolation.average,
    );
  }

  Future<LocalThumbResult> _extractVideoJpeg({
    required String videoPath,
    required String outPath,
    required double ssSeconds,
  }) async {
    final outFile = File(outPath);
    if (await outFile.exists()) {
      return LocalThumbResult(
        status: LocalMediaStatus.available,
        path: outPath,
      );
    }

    final tools = runFfmpeg != null ? null : resolveFfmpegTools();
    if (runFfmpeg == null && tools == null) {
      return const LocalThumbResult(status: LocalMediaStatus.unsupported);
    }

    try {
      final args = <String>[
        '-y',
        '-ss',
        ssSeconds.toStringAsFixed(3),
        '-i',
        videoPath,
        '-frames:v',
        '1',
        outPath,
      ];
      if (runFfmpeg != null) {
        await runFfmpeg!('ffmpeg', args);
      } else {
        final result = await Process.run(
          tools!.ffmpeg,
          args,
          runInShell: false,
        );
        if (result.exitCode != 0) {
          return const LocalThumbResult(status: LocalMediaStatus.unsupported);
        }
      }
      if (!await outFile.exists()) {
        return const LocalThumbResult(status: LocalMediaStatus.unsupported);
      }
      return LocalThumbResult(
        status: LocalMediaStatus.available,
        path: outPath,
      );
    } catch (_) {
      return const LocalThumbResult(status: LocalMediaStatus.unsupported);
    }
  }

  Future<Directory> _ensureCacheRoot() async {
    if (cacheRoot != null) {
      if (!await cacheRoot!.exists()) {
        await cacheRoot!.create(recursive: true);
      }
      return cacheRoot!;
    }
    if (_resolvedCacheRoot != null) return _resolvedCacheRoot!;
    final dir = await Directory.systemTemp.createTemp('tagkin_thumbs_');
    _resolvedCacheRoot = dir;
    return dir;
  }

  LocalThumbResult _storeKey(String key, LocalThumbResult result) {
    _memory[key] = result;
    return result;
  }
}
