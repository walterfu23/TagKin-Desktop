import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:tagkin_desktop/api/items_repository.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/prepass/face_embedder.dart';
import 'package:tagkin_desktop/prepass/onnx_face_embedder.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';

/// Insets a who box toward its center when the VLM region is still large
/// (clothing / multi-person risk) before cropping for likeness.
TagRegion refineWhoRegionForEmbed(TagRegion region) {
  final h = region.yMax - region.yMin;
  final w = region.xMax - region.xMin;
  final area = h * w;
  if (area <= 0 || !area.isFinite) return region;
  // Light inset only — SCRFD aligns inside the crop; heavy inset starved landmarks.
  final inset = area > 0.12 ? 0.10 : (area > 0.06 ? 0.05 : 0.02);
  final yMin = (region.yMin + h * inset).clamp(0.0, 1.0);
  final yMax = (region.yMax - h * inset).clamp(0.0, 1.0);
  final xMin = (region.xMin + w * inset).clamp(0.0, 1.0);
  final xMax = (region.xMax - w * inset).clamp(0.0, 1.0);
  if (yMin >= yMax || xMin >= xMax) return region;
  return TagRegion(yMin: yMin, xMin: xMin, yMax: yMax, xMax: xMax);
}

/// True when local file bytes are present for a display crop.
///
/// Allows [LocalMediaStatus.hashMismatch] (file is on disk; review surfaces the
/// mismatch separately). Skips accessDenied / missing / unsupported.
bool canCropLocalMediaForDisplay(LocalMediaResolution media) {
  if (media.file == null) return false;
  return media.status == LocalMediaStatus.available ||
      media.status == LocalMediaStatus.hashMismatch;
}

/// JPEG bytes for the refined who face crop, or null if undecodable / empty.
///
/// Uses [package:image] only — fine for JPEG/PNG. Prefer
/// [cropWhoFaceJpegAsync] for UI thumbs (HEIC via Flutter codec on macOS).
Uint8List? cropWhoFaceJpeg(Uint8List imageBytes, TagRegion region) {
  final decoded = _tryDecodeImage(imageBytes);
  if (decoded == null) return null;
  return _cropDecodedToJpeg(decoded, region);
}

/// Like [cropWhoFaceJpeg], but falls back to Flutter's platform decoder when
/// `package:image` cannot decode (e.g. HEIC on macOS).
Future<Uint8List?> cropWhoFaceJpegAsync(
  Uint8List imageBytes,
  TagRegion region,
) async {
  final sync = cropWhoFaceJpeg(imageBytes, region);
  if (sync != null) return sync;
  final decoded = await _decodeWithFlutterCodec(imageBytes);
  if (decoded == null) return null;
  return _cropDecodedToJpeg(decoded, region);
}

/// Input for [cropManyWhoFacesJpeg] — a single value so it can cross an
/// isolate boundary via `compute()`.
class FaceCropBatchRequest {
  const FaceCropBatchRequest({required this.imageBytes, required this.regions});

  final Uint8List imageBytes;
  final List<TagRegion> regions;
}

/// Decodes [request.imageBytes] **once** and crops every region — one photo
/// with N faces costs one decode, not N. `package:image`-only (safe to run
/// via `compute()`; `dart:ui` HEIC fallback needs the Flutter engine and
/// cannot run in a background isolate — see [cropManyWhoFacesJpegAsync]).
///
/// Returns a list the same length as [request.regions]; an entry is null when
/// decode failed (e.g. HEIC, truncated/corrupt bytes) or that region was too
/// small.
List<Uint8List?> cropManyWhoFacesJpeg(FaceCropBatchRequest request) {
  final decoded = _tryDecodeImage(request.imageBytes);
  if (decoded == null) {
    return List<Uint8List?>.filled(request.regions.length, null);
  }
  return [
    for (final region in request.regions) _cropDecodedToJpeg(decoded, region),
  ];
}

/// Main-isolate fallback for [cropManyWhoFacesJpeg] when `package:image`
/// cannot decode (e.g. HEIC) — decodes once via the Flutter engine codec and
/// crops every region from that single decode.
Future<List<Uint8List?>> cropManyWhoFacesJpegAsync(
  Uint8List imageBytes,
  List<TagRegion> regions,
) async {
  final sync = _tryDecodeImage(imageBytes);
  final decoded = sync ?? await _decodeWithFlutterCodec(imageBytes);
  if (decoded == null) {
    return List<Uint8List?>.filled(regions.length, null);
  }
  return [for (final region in regions) _cropDecodedToJpeg(decoded, region)];
}

/// `package:image`'s format sniffing can throw (rather than return null) on
/// truncated/corrupt/too-small byte arrays — treat that the same as "could
/// not decode" instead of surfacing an error from a batch decode.
img.Image? _tryDecodeImage(Uint8List bytes) {
  try {
    return img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
}

Uint8List? _cropDecodedToJpeg(img.Image decoded, TagRegion region) {
  final refined = refineWhoRegionForEmbed(region);
  final w = decoded.width;
  final h = decoded.height;
  if (w <= 0 || h <= 0) return null;

  var left = (refined.xMin * w).floor();
  var top = (refined.yMin * h).floor();
  var right = (refined.xMax * w).ceil();
  var bottom = (refined.yMax * h).ceil();
  left = left.clamp(0, w - 1);
  top = top.clamp(0, h - 1);
  right = right.clamp(left + 1, w);
  bottom = bottom.clamp(top + 1, h);
  final cropW = right - left;
  final cropH = bottom - top;
  if (cropW < 8 || cropH < 8) return null;

  final cropped = img.copyCrop(
    decoded,
    x: left,
    y: top,
    width: cropW,
    height: cropH,
  );
  return Uint8List.fromList(img.encodeJpg(cropped, quality: 92));
}

/// Decode via Flutter engine (HEIC/JPEG/PNG on platforms that support them).
Future<img.Image?> _decodeWithFlutterCodec(Uint8List imageBytes) async {
  ui.Codec? codec;
  ui.Image? frameImage;
  try {
    codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    frameImage = frame.image;
    final byteData = await frameImage.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (byteData == null) return null;
    final rgba = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    return img.Image.fromBytes(
      width: frameImage.width,
      height: frameImage.height,
      bytes: rgba.buffer,
      bytesOffset: rgba.offsetInBytes,
      rowStride: frameImage.width * 4,
      order: img.ChannelOrder.rgba,
    );
  } catch (_) {
    return null;
  } finally {
    frameImage?.dispose();
    codec?.dispose();
  }
}

/// After analyze: embed each who-tag face crop and POST who-appearances so the
/// API auto-runs suggested cross-item linking (R6).
///
/// Skips posting when the embedder is the content-hash stub — those vectors
/// never match across photos and would mint one Person per face.
class WhoFaceLinker {
  WhoFaceLinker({
    required this._items,
    FaceEmbedder? embedder,
    this.autoConfirmMinConfidencePercent,
  }) : _embedder = embedder ?? getFaceEmbedder();

  final ItemsRepository _items;
  final FaceEmbedder _embedder;

  /// When non-null, sent on who-appearances so high-confidence named matches
  /// may auto-confirm. Omit (null) to never auto-confirm.
  final int? autoConfirmMinConfidencePercent;

  /// Returns linked appearances, or null if nothing to post / stub skipped.
  Future<WhoAppearancesResponse?> linkWhoFacesForItem(Item item) async {
    if (item.type != ItemType.photo) return null;

    // Start security-scoped bookmark when present (macOS App Sandbox).
    final media = await resolveLocalMedia(item);
    if (media.status == LocalMediaStatus.accessDenied) {
      throw StateError(
        'macOS sandbox blocked ${media.path}. Re-open that folder once in the '
        'main TagKin app (Add from folder) so the security-scoped bookmark is '
        'saved, then re-run the loop.',
      );
    }
    if (!media.isAvailable || media.file == null) {
      return null;
    }

    final knowledge = await _items.getKnowledge(item.id);
    final whoWithRegion = knowledge.tags
        .where(
          (t) =>
              t.dimension == 'who' &&
              t.status == TagStatus.active &&
              t.region != null,
        )
        .toList();
    if (whoWithRegion.isEmpty) return null;

    final bytes = await media.file!.readAsBytes();
    final inputs = <WhoAppearanceInput>[];
    var embedder = _embedder;
    if (embedder is LazyOnnxOrStubFaceEmbedder) {
      embedder = await embedder.ensureLoaded();
    }
    final onnx = embedder is OnnxFaceEmbedder ? embedder : null;
    for (final tag in whoWithRegion) {
      final region = refineWhoRegionForEmbed(tag.region!);
      final List<FaceAppearance> faces;
      if (onnx != null) {
        faces = await onnx.embedWhoRegion(bytes, region);
      } else {
        final crop = cropWhoFaceJpeg(bytes, tag.region!);
        if (crop == null) continue;
        faces = await embedder.embed(crop);
      }
      if (faces.isEmpty) continue;
      final face = faces.first;
      if (face.embeddingModelId == StubFaceEmbedder.modelId) {
        markFaceEmbedderStubFallback();
        return null;
      }
      inputs.add(
        WhoAppearanceInput(
          tagId: tag.id,
          embedding: face.embedding,
          embeddingModelId: face.embeddingModelId,
        ),
      );
    }
    if (inputs.isEmpty) return null;

    return _items.recordWhoAppearances(
      item.id,
      WhoAppearancesRequest(
        appearances: inputs,
        autoConfirmMinConfidencePercent: autoConfirmMinConfidencePercent,
      ),
    );
  }
}
