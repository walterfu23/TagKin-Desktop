import 'dart:typed_data';

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

/// JPEG bytes for the refined who face crop, or null if undecodable / empty.
Uint8List? cropWhoFaceJpeg(Uint8List imageBytes, TagRegion region) {
  final decoded = img.decodeImage(imageBytes);
  if (decoded == null) return null;
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

/// After analyze: embed each who-tag face crop and POST who-appearances so the
/// API auto-runs suggested cross-item linking (R6).
///
/// Skips posting when the embedder is the content-hash stub — those vectors
/// never match across photos and would mint one Person per face.
class WhoFaceLinker {
  WhoFaceLinker({
    required ItemsRepository items,
    FaceEmbedder? embedder,
  })  : _items = items,
        _embedder = embedder ?? getFaceEmbedder();

  final ItemsRepository _items;
  final FaceEmbedder _embedder;

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
      WhoAppearancesRequest(appearances: inputs),
    );
  }
}
