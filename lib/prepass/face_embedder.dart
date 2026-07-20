import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Contract face embedding dimension (`PrePassAppearanceInput.embedding`
/// minItems/maxItems = 512).
const int kFaceEmbeddingDim = 512;

/// One face/person appearance from the classic-CV pre-pass (vector only).
class FaceAppearance {
  const FaceAppearance({
    required this.embedding,
    required this.embeddingModelId,
  });

  final List<double> embedding;
  final String embeddingModelId;
}

/// Pluggable face detect + embed. Real adapters (MediaPipe / InsightFace)
/// can swap in later; CI and v1 use [StubFaceEmbedder].
abstract class FaceEmbedder {
  Future<List<FaceAppearance>> embed(Uint8List bytes);
}

/// Deterministic 512-d L2-normalized vector from content — no model download.
///
/// Mirrors `@tagkin/prepass` `StubFaceEmbedder` (`stub-face-embed-v1`) so
/// desktop and web stay conceptually aligned for contract shape tests.
class StubFaceEmbedder implements FaceEmbedder {
  static const modelId = 'stub-face-embed-v1';

  @override
  Future<List<FaceAppearance>> embed(Uint8List bytes) async {
    final digest = sha256.convert(bytes).bytes;
    final embedding = List<double>.filled(kFaceEmbeddingDim, 0);
    for (var i = 0; i < kFaceEmbeddingDim; i++) {
      final b = digest[i % digest.length];
      embedding[i] = (b / 255) * 2 - 1;
    }
    var norm = 0.0;
    for (final v in embedding) {
      norm += v * v;
    }
    norm = math.sqrt(norm);
    if (norm == 0) norm = 1;
    for (var i = 0; i < embedding.length; i++) {
      embedding[i] = embedding[i] / norm;
    }
    return [
      FaceAppearance(embedding: embedding, embeddingModelId: modelId),
    ];
  }
}

FaceEmbedder getFaceEmbedder() => StubFaceEmbedder();
