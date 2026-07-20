import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tagkin_desktop/prepass/face_embedder.dart';

Uint8List _solidJpeg() {
  final image = img.Image(width: 16, height: 16);
  img.fill(image, color: img.ColorRgb8(200, 10, 10));
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  group('StubFaceEmbedder', () {
    test('returns contract vector dimension 512', () async {
      final faces = await StubFaceEmbedder().embed(_solidJpeg());
      expect(faces, hasLength(1));
      expect(faces.single.embedding, hasLength(kFaceEmbeddingDim));
      expect(faces.single.embeddingModelId, StubFaceEmbedder.modelId);
    });

    test('is deterministic for identical bytes', () async {
      final bytes = _solidJpeg();
      final a = await StubFaceEmbedder().embed(bytes);
      final b = await StubFaceEmbedder().embed(bytes);
      expect(a.single.embedding, b.single.embedding);
    });

    test('L2-normalizes the vector', () async {
      final faces = await StubFaceEmbedder().embed(_solidJpeg());
      var sumSq = 0.0;
      for (final v in faces.single.embedding) {
        sumSq += v * v;
      }
      expect(sumSq, closeTo(1.0, 1e-6));
    });
  });

  // Keep analyzer happy on platforms where dart:io is unused above.
  test('model id is stable', () {
    expect(StubFaceEmbedder.modelId, 'stub-face-embed-v1');
    expect(Platform.isMacOS || Platform.isWindows || Platform.isLinux, isTrue);
  });
}
