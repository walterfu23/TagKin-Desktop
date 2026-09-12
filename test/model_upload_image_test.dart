import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/model_upload_image.dart';

Uint8List _jpeg({
  required int orientation,
  required img.ColorRgb8 topLeft,
  required img.ColorRgb8 bottomRight,
}) {
  final image = img.Image(width: 32, height: 32);
  img.fill(image, color: img.ColorRgb8(40, 40, 40));
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      image.setPixel(x, y, topLeft);
      image.setPixel(24 + x, 24 + y, bottomRight);
    }
  }
  image.exif.imageIfd.orientation = orientation;
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

img.Color _sample(img.Image decoded, int x, int y) => decoded.getPixel(x, y);

void main() {
  test('jpegExifOrientation reads IFD0 Orientation', () {
    final bytes = _jpeg(
      orientation: 3,
      topLeft: img.ColorRgb8(255, 0, 0),
      bottomRight: img.ColorRgb8(0, 0, 255),
    );
    expect(jpegExifOrientation(bytes), 3);
  });

  test('Orientation 1 JPEG is uploaded unchanged', () async {
    final bytes = _jpeg(
      orientation: 1,
      topLeft: img.ColorRgb8(255, 0, 0),
      bottomRight: img.ColorRgb8(0, 0, 255),
    );
    final prepared = await prepareModelUploadBytes(
      path: '/albums/upright.jpg',
      type: ItemType.photo,
      rawBytes: bytes,
    );
    expect(prepared.mimeType, 'image/jpeg');
    expect(prepared.bytes, same(bytes));
  });

  test('JPEG without Orientation is uploaded unchanged', () async {
    final image = img.Image(width: 16, height: 16);
    img.fill(image, color: img.ColorRgb8(10, 20, 30));
    final bytes = Uint8List.fromList(img.encodeJpg(image));
    expect(jpegExifOrientation(bytes), isNull);

    final prepared = await prepareModelUploadBytes(
      path: '/albums/plain.jpg',
      type: ItemType.photo,
      rawBytes: bytes,
    );
    expect(prepared.bytes, same(bytes));
  });

  test('Orientation 3 JPEG is baked upright for analyze', () async {
    final red = img.ColorRgb8(255, 0, 0);
    final blue = img.ColorRgb8(0, 0, 255);
    final bytes = _jpeg(
      orientation: 3,
      topLeft: red,
      bottomRight: blue,
    );
    expect(jpegExifOrientation(bytes), 3);

    final prepared = await prepareModelUploadBytes(
      path: '/albums/rotated.jpg',
      type: ItemType.photo,
      rawBytes: bytes,
    );
    expect(prepared.mimeType, 'image/jpeg');
    expect(identical(prepared.bytes, bytes), isFalse);
    final out = prepared.bytes is Uint8List
        ? prepared.bytes as Uint8List
        : Uint8List.fromList(prepared.bytes);
    expect(jpegExifOrientation(out), anyOf(isNull, 1));

    final decoded = img.decodeImage(out);
    expect(decoded, isNotNull);
    // Storage top-left red is displayed bottom-right after 180° bake.
    final br = _sample(decoded!, 28, 28);
    final tl = _sample(decoded, 4, 4);
    expect(br.r, greaterThan(200));
    expect(br.b, lessThan(40));
    expect(tl.b, greaterThan(200));
    expect(tl.r, lessThan(40));
  });

  test('PNG bytes are uploaded unchanged', () async {
    final image = img.Image(width: 8, height: 8);
    img.fill(image, color: img.ColorRgb8(1, 2, 3));
    final bytes = Uint8List.fromList(img.encodePng(image));
    final prepared = await prepareModelUploadBytes(
      path: '/albums/still.png',
      type: ItemType.photo,
      rawBytes: bytes,
    );
    expect(prepared.mimeType, 'image/png');
    expect(prepared.bytes, same(bytes));
  });
}
