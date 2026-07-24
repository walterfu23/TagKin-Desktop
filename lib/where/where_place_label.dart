import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Parsed GPS where-tag (`"lat,lng"` as stored by pre-pass).
class LatLng {
  const LatLng(this.lat, this.lng);

  final double lat;
  final double lng;
}

/// Human place parts from reverse geocode (city / region / country).
class PlaceParts {
  const PlaceParts({
    this.locality,
    this.administrativeArea,
    this.country,
    this.isoCountryCode,
  });

  /// City / town / village.
  final String? locality;

  /// State / province / region.
  final String? administrativeArea;

  /// Country display name.
  final String? country;

  /// ISO 3166-1 alpha-2 (e.g. `US`, `CA`).
  final String? isoCountryCode;
}

final _latLngTag = RegExp(
  r'^(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)$',
);

/// Returns coords when [value] is a pre-pass GPS tag; otherwise null.
LatLng? parseLatLngTag(String value) {
  final match = _latLngTag.firstMatch(value.trim());
  if (match == null) return null;
  final lat = double.tryParse(match[1]!);
  final lng = double.tryParse(match[2]!);
  if (lat == null ||
      lng == null ||
      !lat.isFinite ||
      !lng.isFinite ||
      lat < -90 ||
      lat > 90 ||
      lng < -180 ||
      lng > 180) {
    return null;
  }
  return LatLng(lat, lng);
}

/// Device country for same-country checks (ISO alpha-2 upper).
String? deviceCountryCode() {
  if (kIsWeb) {
    return _normalizeCountryCode(
      PlatformDispatcher.instance.locale.countryCode,
    );
  }
  try {
    final fromLocaleName = _countryFromLocaleName(Platform.localeName);
    if (fromLocaleName != null) return fromLocaleName;
  } catch (_) {}
  return _normalizeCountryCode(
    PlatformDispatcher.instance.locale.countryCode,
  );
}

String? _countryFromLocaleName(String localeName) {
  // e.g. en_US, en-US, en_US.UTF-8
  final match = RegExp(r'[_-]([A-Za-z]{2})\b').firstMatch(localeName);
  return _normalizeCountryCode(match?.group(1));
}

String? _normalizeCountryCode(String? raw) {
  if (raw == null) return null;
  final code = raw.trim().toUpperCase();
  if (code.length != 2) return null;
  return code;
}

String? _clean(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed == 'null') return null;
  return trimmed;
}

bool _sameRegion(String? a, String? b) {
  final left = _clean(a)?.toLowerCase();
  final right = _clean(b)?.toLowerCase();
  if (left == null || right == null) return false;
  return left == right;
}

/// Formats city / state[/province][, country] using display prefs.
///
/// [showCountryWhenSameCountry] / [showStateWhenSameState] default false.
/// [homeState] empty → same-state never matches (region always shown when set).
String? formatWherePlaceLabel(
  PlaceParts place, {
  String? deviceCountryCode,
  String homeState = '',
  bool showCountryWhenSameCountry = false,
  bool showStateWhenSameState = false,
}) {
  final city = _clean(place.locality);
  final region = _clean(place.administrativeArea);
  final country = _clean(place.country);
  final placeCountry = _normalizeCountryCode(place.isoCountryCode);
  final device = _normalizeCountryCode(deviceCountryCode);

  final sameCountry = device != null &&
      placeCountry != null &&
      device == placeCountry;
  final includeCountry = country != null &&
      (!sameCountry || showCountryWhenSameCountry);

  final sameState = _sameRegion(region, homeState);
  final includeRegion = region != null &&
      region != city &&
      (!sameState || showStateWhenSameState);

  final parts = <String>[
    ?city,
    if (includeRegion) region,
    if (includeCountry) country,
  ];
  if (parts.isEmpty) return null;
  return parts.join(', ');
}
