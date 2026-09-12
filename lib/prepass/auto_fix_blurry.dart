import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tagkin_desktop/ingest/model_upload_image.dart';
import 'package:tagkin_desktop/ingest/tagkin_fixed_sidecar.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs.dart';
import 'package:tagkin_desktop/prepass/unsharp.dart';

/// Result of a local (0-credit) unsharp pass at ingest.
class AutoFixBlurryResult {
  const AutoFixBlurryResult({
    required this.jpegBytes,
    required this.cachePath,
    this.sidecarPath,
  });

  final Uint8List jpegBytes;
  final String cachePath;
  final String? sidecarPath;
}

String deblurCacheFileName(String contentHash) => '${contentHash}_fixed.jpg';

/// App-support cache for sharpened JPEGs (not the album unless sidecar-on).
Future<Directory> defaultDeblurCacheDir() async {
  final support = await getApplicationSupportDirectory();
  final dir = Directory(p.join(support.path, 'deblur'));
  await dir.create(recursive: true);
  return dir;
}

/// Decode [bytes] from [path], unsharp, and encode JPEG. Null if undecodable.
Future<Uint8List?> unsharpJpegBytes(String path, Uint8List bytes) async {
  var decoded = img.decodeImage(bytes);
  if (decoded == null) {
    final jpeg = await convertHeicLikeToJpeg(bytes);
    if (jpeg == null) return null;
    decoded = img.decodeImage(jpeg);
    if (decoded == null) return null;
  }
  final sharpened = unsharpMask(decoded);
  return Uint8List.fromList(img.encodeJpg(sharpened, quality: 92));
}

/// Local unsharp when auto-fix is on and [sharpness] is below the Settings bar.
///
/// Does not overwrite [originalPath]. Writes a cache JPEG always; writes
/// `*.tagkin-fixed.jpg` only when [DesktopPrefs.saveFixedPhotoInFolder] is on.
/// Already-fixed sidecars and unknown (null) scores are skipped.
Future<AutoFixBlurryResult?> autoFixBlurryPhoto({
  required String originalPath,
  required Uint8List originalBytes,
  required double? sharpness,
  required String contentHash,
  required DesktopPrefs prefs,
  required Directory cacheDir,
}) async {
  if (!prefs.autoFixBlurryPhotos) return null;
  if (sharpness == null) return null;
  if (isTagkinFixedSidecar(originalPath)) return null;
  if (sharpness >= prefs.itemListBlurrySharpnessThreshold) return null;

  final jpeg = await unsharpJpegBytes(originalPath, originalBytes);
  if (jpeg == null) return null;

  await cacheDir.create(recursive: true);
  final cachePath = p.join(cacheDir.path, deblurCacheFileName(contentHash));
  await File(cachePath).writeAsBytes(jpeg, flush: true);

  String? sidecarPath;
  if (prefs.saveFixedPhotoInFolder) {
    sidecarPath = tagkinFixedSidecarPath(originalPath);
    await File(sidecarPath).writeAsBytes(jpeg, flush: true);
  }

  return AutoFixBlurryResult(
    jpegBytes: jpeg,
    cachePath: cachePath,
    sidecarPath: sidecarPath,
  );
}

/// Prefer album sidecar, then deblur cache, else [sourcePath].
Future<String> preferSharpenedStillPath({
  required String sourcePath,
  String? contentHash,
  Directory? cacheDir,
}) async {
  if (isTagkinFixedSidecar(sourcePath)) return sourcePath;
  final sidecar = tagkinFixedSidecarPath(sourcePath);
  if (await File(sidecar).exists()) return sidecar;
  if (contentHash != null && contentHash.isNotEmpty) {
    Directory? dir = cacheDir;
    if (dir == null) {
      try {
        dir = await defaultDeblurCacheDir();
      } catch (_) {
        dir = null;
      }
    }
    if (dir != null) {
      final cached = File(p.join(dir.path, deblurCacheFileName(contentHash)));
      if (await cached.exists()) return cached.path;
    }
  }
  return sourcePath;
}
