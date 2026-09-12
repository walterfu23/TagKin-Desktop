import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tagkin_desktop/prepass/sharpness.dart';

Uint8List _jpeg(img.Image image) =>
    Uint8List.fromList(img.encodeJpg(image, quality: 95));

void main() {
  test('uniform still scores near zero; checkerboard is above the blurry bar',
      () {
    final flat = img.Image(width: 64, height: 64);
    img.fill(flat, color: img.ColorRgb8(120, 120, 120));
    final flatScore = sharpnessFromJpeg(_jpeg(flat));
    expect(flatScore, isNotNull);
    expect(flatScore!, lessThan(5));

    final checker = img.Image(width: 64, height: 64);
    for (var y = 0; y < 64; y++) {
      for (var x = 0; x < 64; x++) {
        final on = ((x ~/ 4) + (y ~/ 4)).isEven;
        checker.setPixelRgb(x, y, on ? 255 : 0, on ? 255 : 0, on ? 255 : 0);
      }
    }
    final sharpScore = sharpnessFromJpeg(_jpeg(checker));
    expect(sharpScore, isNotNull);
    expect(sharpScore!, greaterThan(kBlurrySharpnessThreshold));
    expect(sharpScore, greaterThan(flatScore));
  });

  test('undecodable bytes return null (unknown, fail closed)', () {
    expect(sharpnessFromJpeg(Uint8List.fromList([0, 1, 2, 3])), isNull);
  });
}
