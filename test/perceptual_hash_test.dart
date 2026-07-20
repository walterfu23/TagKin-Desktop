import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/ingest/perceptual_hash.dart';

import 'fixtures/synthetic_images.dart';

void main() {
  group('computePerceptualHash', () {
    test('identical image bytes produce identical hash', () {
      final bytes = gradientImagePng();
      expect(computePerceptualHash(bytes), computePerceptualHash(bytes));
    });

    test('hash is 16 lowercase hex characters (64-bit dHash)', () {
      final hash = computePerceptualHash(solidImagePng());
      expect(hash, isNotNull);
      expect(hash, matches(RegExp(r'^[0-9a-f]{16}$')));
    });

    test('undecodable bytes return null (falls back to contentHash only)',
        () {
      final hash = computePerceptualHash(Uint8List.fromList([1, 2, 3, 4]));
      expect(hash, isNull);
    });

    test(
        'a slightly perturbed re-save is near-duplicate; a different image is not',
        () {
      final original = computePerceptualHash(gradientImagePng())!;
      final resaved = computePerceptualHash(
        gradientImagePng(noiseAmplitude: 2),
      )!;
      final different = computePerceptualHash(
        gradientImagePng(descending: true),
      )!;

      expect(hammingDistance(original, resaved), lessThanOrEqualTo(4));
      expect(hammingDistance(original, different), greaterThan(4));
    });
  });

  group('hammingDistance', () {
    test('distance to self is zero', () {
      const hash = '00ff00ff00ff00ff';
      expect(hammingDistance(hash, hash), 0);
    });

    test('fully-inverted hash has maximum distance', () {
      expect(
        hammingDistance('0000000000000000', 'ffffffffffffffff'),
        64,
      );
    });
  });
}
