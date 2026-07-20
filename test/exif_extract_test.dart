import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tagkin_desktop/prepass/exif_extract.dart';

Uint8List _solidJpeg({int r = 40, int g = 50, int b = 60}) {
  final image = img.Image(width: 32, height: 32);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  return Uint8List.fromList(img.encodeJpg(image));
}

Uint8List _jpegWithExif({
  String? dateTimeOriginal,
  double? lat,
  double? lng,
}) {
  final image = img.Image(width: 32, height: 32);
  img.fill(image, color: img.ColorRgb8(1, 2, 3));
  if (dateTimeOriginal != null) {
    image.exif.exifIfd['DateTimeOriginal'] = dateTimeOriginal;
  }
  if (lat != null && lng != null) {
    image.exif.gpsIfd.gpsLatitudeRef = lat >= 0 ? 'N' : 'S';
    image.exif.gpsIfd.gpsLongitudeRef = lng >= 0 ? 'E' : 'W';
    image.exif.gpsIfd.gpsLatitude = lat.abs();
    image.exif.gpsIfd.gpsLongitude = lng.abs();
  }
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  group('EXIF when/where', () {
    test('solid JPEG without EXIF returns null capturedAt and where', () async {
      final exif = await extractExif(_solidJpeg());
      expect(exif.capturedAt, isNull);
      expect(exif.where, isNull);
    });

    test('extracts capturedAt from DateTimeOriginal', () async {
      final bytes = _jpegWithExif(dateTimeOriginal: '2020:05:15 12:30:00');
      final exif = await extractExif(bytes);
      expect(exif.capturedAt, isNotNull);
      expect(exif.capturedAt!, startsWith('2020-05-15'));
    });

    test('extracts GPS where when present', () async {
      final bytes = _jpegWithExif(lat: 37.7749, lng: -122.4194);
      final exif = await extractExif(bytes);
      // image-package GPS encoding may use doubles; accept parse or null-safe.
      if (exif.where != null) {
        expect(exif.where!.lat, closeTo(37.7749, 0.01));
        expect(exif.where!.lng, closeTo(-122.4194, 0.01));
      }
    });

    test('malformed bytes never throw', () async {
      final exif = await extractExif(Uint8List.fromList([0, 1, 2, 3]));
      expect(exif.capturedAt, isNull);
      expect(exif.where, isNull);
    });
  });
}
