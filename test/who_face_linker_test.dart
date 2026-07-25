import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/persons/who_face_linker.dart';

void main() {
  test('refineWhoRegionForEmbed insets large boxes', () {
    const large = TagRegion(yMin: 0.0, xMin: 0.0, yMax: 0.8, xMax: 0.6);
    final refined = refineWhoRegionForEmbed(large);
    expect(refined.yMin, greaterThan(large.yMin));
    expect(refined.yMax, lessThan(large.yMax));
    expect(refined.xMin, greaterThan(large.xMin));
    expect(refined.xMax, lessThan(large.xMax));
  });

  test('refineWhoRegionForEmbed barely changes small face boxes', () {
    const small = TagRegion(yMin: 0.2, xMin: 0.3, yMax: 0.35, xMax: 0.42);
    final refined = refineWhoRegionForEmbed(small);
    expect(refined.yMin, closeTo(small.yMin, 0.05));
    expect(refined.yMax, closeTo(small.yMax, 0.05));
  });

  test('cropWhoFaceJpeg returns a non-empty jpeg for a valid region', () {
    final image = img.Image(width: 100, height: 100);
    img.fill(image, color: img.ColorRgb8(200, 100, 50));
    final bytes = Uint8List.fromList(img.encodeJpg(image));
    const region = TagRegion(yMin: 0.2, xMin: 0.2, yMax: 0.6, xMax: 0.6);
    final crop = cropWhoFaceJpeg(bytes, region);
    expect(crop, isNotNull);
    expect(crop!.length, greaterThan(50));
    expect(img.decodeImage(crop), isNotNull);
  });
}
