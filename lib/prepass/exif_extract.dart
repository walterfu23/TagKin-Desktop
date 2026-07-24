import 'dart:io';
import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:tagkin_desktop/contract/contract.dart';

/// EXIF-derived when/where from local media bytes (D4).
///
/// Never throws — missing/unparseable EXIF returns null fields.
class ExifExtract {
  const ExifExtract({this.capturedAt, this.where});

  /// ISO-8601 capture time when EXIF DateTimeOriginal / CreateDate / DateTime
  /// is present and parseable; otherwise null.
  final String? capturedAt;

  /// GPS lat/lng when present; otherwise null.
  ///
  /// Place names (city/state) are derived at display time from these coords.
  final PrePassWhere? where;
}

/// Extract EXIF when/where from [bytes]. Reads metadata only (R1/R5).
Future<ExifExtract> extractExif(Uint8List bytes) async {
  Map<String, IfdTag> data;
  try {
    data = await readExifFromBytes(bytes);
  } catch (_) {
    return const ExifExtract();
  }
  if (data.isEmpty) return const ExifExtract();

  return ExifExtract(
    capturedAt: _parseCapturedAt(data),
    where: _parseWhere(data),
  );
}

/// Reads [path] from local disk only, then [extractExif].
Future<ExifExtract> extractExifFromFile(String path) async {
  final bytes = await File(path).readAsBytes();
  return extractExif(bytes);
}

String? _parseCapturedAt(Map<String, IfdTag> data) {
  final raw = data['EXIF DateTimeOriginal']?.toString() ??
      data['EXIF DateTimeDigitized']?.toString() ??
      data['Image DateTime']?.toString();
  if (raw == null || raw.isEmpty) return null;
  return _exifDateTimeToIso(raw);
}

/// EXIF dates are typically `YYYY:MM:DD HH:MM:SS` (colons in the date).
String? _exifDateTimeToIso(String raw) {
  final trimmed = raw.trim();
  // Convert "2020:05:15 12:30:00" → "2020-05-15T12:30:00"
  final match = RegExp(
    r'^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})',
  ).firstMatch(trimmed);
  if (match != null) {
    final iso =
        '${match[1]}-${match[2]}-${match[3]}T${match[4]}:${match[5]}:${match[6]}';
    final parsed = DateTime.tryParse(iso);
    if (parsed != null) return parsed.toUtc().toIso8601String();
  }
  final fallback = DateTime.tryParse(trimmed);
  if (fallback != null) return fallback.toUtc().toIso8601String();
  return null;
}

PrePassWhere? _parseWhere(Map<String, IfdTag> data) {
  final latRef = data['GPS GPSLatitudeRef']?.toString();
  final lngRef = data['GPS GPSLongitudeRef']?.toString();
  final latVal = _gpsValuesToFloat(data['GPS GPSLatitude']?.values);
  final lngVal = _gpsValuesToFloat(data['GPS GPSLongitude']?.values);
  if (latRef == null ||
      lngRef == null ||
      latVal == null ||
      lngVal == null ||
      !latVal.isFinite ||
      !lngVal.isFinite) {
    return null;
  }
  var lat = latVal;
  var lng = lngVal;
  if (latRef == 'S') lat = -lat;
  if (lngRef == 'W') lng = -lng;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
  return PrePassWhere(lat: lat, lng: lng);
}

/// DMS (degrees/minutes/seconds) Ratio list → decimal degrees.
double? _gpsValuesToFloat(IfdValues? values) {
  if (values == null || values is! IfdRatios) return null;
  var sum = 0.0;
  var unit = 1.0;
  for (final v in values.ratios) {
    sum += v.toDouble() * unit;
    unit /= 60.0;
  }
  return sum;
}
