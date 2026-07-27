import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:tagkin_desktop/prepass/onnx_face_embedder.dart';

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

/// Pluggable face detect + embed. Real adapters (ONNX ArcFace) swap in via
/// [getFaceEmbedder]; CI uses [StubFaceEmbedder].
abstract class FaceEmbedder {
  Future<List<FaceAppearance>> embed(Uint8List bytes);
}

/// Deterministic 512-d L2-normalized vector from content — no model download.
///
/// Mirrors `@tagkin/prepass` `StubFaceEmbedder` (`stub-face-embed-v1`) so
/// desktop and web stay conceptually aligned for contract shape tests.
/// Does **not** match the same person across different photos.
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

/// Test/CI override. When set, [getFaceEmbedder] returns this instance.
FaceEmbedder? debugFaceEmbedderOverride;

/// Set when production falls back to [StubFaceEmbedder] (missing ONNX weights).
bool _faceEmbedderStubNoticePending = false;

@visibleForTesting
void debugResetFaceEmbedderStubNotice() {
  _faceEmbedderStubNoticePending = false;
}

/// Marks that the user should be told matching will be weak (stub in use).
void markFaceEmbedderStubFallback() {
  _faceEmbedderStubNoticePending = true;
}

/// Returns true once after stub fallback was marked (clears the flag).
bool consumeFaceEmbedderStubNotice() {
  if (!_faceEmbedderStubNoticePending) return false;
  _faceEmbedderStubNoticePending = false;
  return true;
}

/// Tiny helper so tests don't need to import foundation internals.
class PlatformEnvironment {
  /// True under `flutter test` (process env and/or `--dart-define=FLUTTER_TEST`).
  static bool get isFlutterTest {
    if (const bool.fromEnvironment('FLUTTER_TEST')) return true;
    if (kIsWeb) return false;
    return Platform.environment['FLUTTER_TEST'] == 'true';
  }
}

/// Production: ONNX when models are on disk; stub otherwise (tests inject stub).
FaceEmbedder getFaceEmbedder() {
  if (debugFaceEmbedderOverride != null) {
    return debugFaceEmbedderOverride!;
  }
  // Unit tests must not load native ORT / missing weights.
  if (PlatformEnvironment.isFlutterTest) {
    return StubFaceEmbedder();
  }
  return LazyOnnxOrStubFaceEmbedder();
}
