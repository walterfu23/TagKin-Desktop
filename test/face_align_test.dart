import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tagkin_desktop/prepass/face_align.dart';
import 'package:tagkin_desktop/prepass/scrfd.dart';

void main() {
  group('estimateNormSimilarity + warpAffine', () {
    test('identity landmarks near template warp to 112 canvas', () {
      final src = img.Image(width: 200, height: 200);
      img.fill(src, color: img.ColorRgb8(40, 40, 40));
      final lm = [
        for (final p in kArcFaceTemplate112) [p[0], p[1]],
      ];
      for (final p in lm) {
        final x = p[0].round().clamp(0, 199);
        final y = p[1].round().clamp(0, 199);
        src.setPixelRgb(x, y, 255, 0, 0);
      }
      final out = normCropArcFace(src, lm);
      expect(out.width, 112);
      expect(out.height, 112);
      final eye = out.getPixel(38, 52);
      expect(eye.r, greaterThan(100));
    });

    test('estimateSimilarity maps origin toward dst', () {
      final src = [
        [0.0, 0.0],
        [10.0, 0.0],
        [0.0, 10.0],
      ];
      final dst = [
        [100.0, 100.0],
        [120.0, 100.0],
        [100.0, 120.0],
      ];
      final m = estimateSimilarityTransform(src, dst);
      final x = m[0] * 0 + m[1] * 0 + m[2];
      final y = m[3] * 0 + m[4] * 0 + m[5];
      expect(x, closeTo(100, 1e-6));
      expect(y, closeTo(100, 1e-6));
    });

    test('matches InsightFace-style matrix on sample landmarks', () {
      final src = [
        [10.0, 20.0],
        [40.0, 18.0],
        [25.0, 50.0],
        [12.0, 70.0],
        [38.0, 72.0],
      ];
      final m = estimateNormSimilarity(src, imageSize: 112);
      expect(m[0], closeTo(0.8597235, 1e-4));
      expect(m[1], closeTo(0.0030526, 1e-4));
      expect(m[2], closeTo(34.39265, 0.5));
      expect(m[3], closeTo(-0.0030526, 1e-4));
      expect(m[4], closeTo(0.8597235, 1e-4));
      expect(m[5], closeTo(32.4298, 0.5));
    });
  });

  group('letterboxForScrfd', () {
    test('pads wide image into square det canvas', () {
      final src = img.Image(width: 100, height: 50);
      img.fill(src, color: img.ColorRgb8(10, 20, 30));
      final packed = letterboxForScrfd(src, detSize: 64);
      expect(packed.detImg.width, 64);
      expect(packed.detImg.height, 64);
      expect(packed.newW, 64);
      expect(packed.newH, 32);
      expect(packed.detScale, closeTo(32 / 50, 1e-6));
    });
  });

  group('orderScrfdOutputsByShape', () {
    test('reorders interleaved alphabetical name order into score/bbox/kps', () {
      // Simulated alphabetical: s8,b8,k8,s16,b16,k16,s32,b32,k32
      Float32List fill(int n, int c, double v) =>
          Float32List.fromList(List.filled(n * c, v));
      final interleaved = [
        (data: fill(12800, 1, 0.1), shape: [12800, 1]),
        (data: fill(12800, 4, 0.2), shape: [12800, 4]),
        (data: fill(12800, 10, 0.3), shape: [12800, 10]),
        (data: fill(3200, 1, 0.4), shape: [3200, 1]),
        (data: fill(3200, 4, 0.5), shape: [3200, 4]),
        (data: fill(3200, 10, 0.6), shape: [3200, 10]),
        (data: fill(800, 1, 0.7), shape: [800, 1]),
        (data: fill(800, 4, 0.8), shape: [800, 4]),
        (data: fill(800, 10, 0.9), shape: [800, 10]),
      ];
      final ordered = orderScrfdOutputsByShape(interleaved);
      expect(ordered, isNotNull);
      expect(ordered![0][0], closeTo(0.1, 1e-6)); // score8
      expect(ordered[1][0], closeTo(0.4, 1e-6)); // score16
      expect(ordered[2][0], closeTo(0.7, 1e-6)); // score32
      expect(ordered[3][0], closeTo(0.2, 1e-6)); // bbox8
      expect(ordered[6][0], closeTo(0.3, 1e-6)); // kps8
    });
  });
}
