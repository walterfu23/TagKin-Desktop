import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tagkin_desktop/prepass/onnx_face_embedder.dart';

void main() {
  group('letterboxToSquare', () {
    test('leaves square images unchanged in size', () {
      final src = img.Image(width: 40, height: 40);
      img.fill(src, color: img.ColorRgb8(200, 10, 10));
      final out = letterboxToSquare(src);
      expect(out.width, 40);
      expect(out.height, 40);
    });

    test('pads a wide crop to square without stretching content width', () {
      final src = img.Image(width: 60, height: 30);
      img.fill(src, color: img.ColorRgb8(10, 200, 10));
      final out = letterboxToSquare(src, padValue: 127);
      expect(out.width, 60);
      expect(out.height, 60);
      // Content centered vertically: row 15 of src → row 15+15=30 of out.
      expect(out.getPixel(0, 30).g, greaterThan(100));
      // Top pad band is mid-gray.
      expect(out.getPixel(30, 0).r, 127);
      expect(out.getPixel(30, 0).g, 127);
      expect(out.getPixel(30, 0).b, 127);
    });

    test('pads a tall crop to square without stretching content height', () {
      final src = img.Image(width: 20, height: 50);
      img.fill(src, color: img.ColorRgb8(10, 10, 200));
      final out = letterboxToSquare(src, padValue: 127);
      expect(out.width, 50);
      expect(out.height, 50);
      expect(out.getPixel(0, 0).r, 127);
      // Content starts at dx=15.
      expect(out.getPixel(15, 0).b, greaterThan(100));
    });
  });
}
