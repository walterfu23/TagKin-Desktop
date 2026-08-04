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

  /// State / province / region (geocoder `administrativeArea`).
  final String? administrativeArea;

  /// Country display name.
  final String? country;

  /// ISO 3166-1 alpha-2 (e.g. `US`, `CA`).
  final String? isoCountryCode;
}

/// Formatted where label with optional segments for Folders UI.
class WhereDisplay {
  const WhereDisplay({
    required this.label,
    this.locality,
    this.region,
    this.regionName,
    this.country,
  });

  /// Joined display string (sort / filter / plain Text).
  final String label;

  final String? locality;

  /// State/province included in [label] (null when omitted as familiar).
  final String? region;

  /// Geocoder administrative area when known (for “add to familiar”), even if
  /// omitted from [label].
  final String? regionName;

  final String? country;

  /// Non-GPS / failed geocode passthrough.
  factory WhereDisplay.plain(String value) => WhereDisplay(label: value);
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

bool sameRegionName(String? a, String? b) {
  final left = _clean(a)?.toLowerCase();
  final right = _clean(b)?.toLowerCase();
  if (left == null || right == null) return false;
  return left == right;
}

final _unicodeLetter = RegExp(r'\p{L}', unicode: true);

/// True when [token] (trimmed) contains at least one Unicode letter.
/// Rejects `-`, `123`, empty; allows `CA`, `zzz`, `Île-de-France`.
bool isValidFamiliarRegionToken(String token) {
  final trimmed = token.trim();
  if (trimmed.isEmpty) return false;
  return _unicodeLetter.hasMatch(trimmed);
}

/// Splits familiar-regions CSV into trimmed non-empty entries.
List<String> parseFamiliarRegions(String csv) {
  return [
    for (final part in csv.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];
}

/// Trimmed tokens from [csv] that fail [isValidFamiliarRegionToken].
List<String> invalidFamiliarRegionTokens(String csv) {
  return [
    for (final part in parseFamiliarRegions(csv))
      if (!isValidFamiliarRegionToken(part)) part,
  ];
}

/// Joins familiar region names for prefs storage.
String encodeFamiliarRegions(Iterable<String> regions) {
  return [
    for (final r in regions)
      if (r.trim().isNotEmpty) r.trim(),
  ].join(', ');
}

/// Trim, drop empties/invalids, case-insensitive dedupe (keeps first spelling).
String normalizeFamiliarRegionsCsv(String csv) {
  final seen = <String>{};
  final out = <String>[];
  for (final part in parseFamiliarRegions(csv)) {
    if (!isValidFamiliarRegionToken(part)) continue;
    final key = part.toLowerCase();
    if (!seen.add(key)) continue;
    out.add(part);
  }
  return encodeFamiliarRegions(out);
}

bool isFamiliarRegion(String region, String familiarRegionsCsv) {
  return parseFamiliarRegions(familiarRegionsCsv)
      .any((r) => sameRegionName(r, region));
}

/// Formats city / state[/province][, country] using display prefs.
///
/// [familiarRegions] is a CSV of familiar region names. Empty → never omit
/// state/province as familiar.
WhereDisplay formatWhereDisplay(
  PlaceParts place, {
  String? deviceCountryCode,
  String familiarRegions = '',
  bool showCountryWhenSameCountry = false,
  bool showStateWhenSameState = false,
}) {
  final city = _clean(place.locality);
  final regionName = _clean(place.administrativeArea);
  final country = _clean(place.country);
  final placeCountry = _normalizeCountryCode(place.isoCountryCode);
  final device = _normalizeCountryCode(deviceCountryCode);

  final sameCountry = device != null &&
      placeCountry != null &&
      device == placeCountry;
  final includeCountry = country != null &&
      (!sameCountry || showCountryWhenSameCountry);

  final familiar = isFamiliarRegion(regionName ?? '', familiarRegions);
  final includeRegion = regionName != null &&
      regionName != city &&
      (!familiar || showStateWhenSameState);

  final parts = <String>[
    ?city,
    if (includeRegion) regionName,
    if (includeCountry) country,
  ];
  if (parts.isEmpty) {
    return WhereDisplay(
      label: regionName ?? country ?? '',
      locality: city,
      region: includeRegion ? regionName : null,
      regionName: regionName,
      country: includeCountry ? country : null,
    );
  }
  return WhereDisplay(
    label: parts.join(', '),
    locality: city,
    region: includeRegion ? regionName : null,
    regionName: regionName,
    country: includeCountry ? country : null,
  );
}

/// Convenience: joined label only (tests / simple callers).
String? formatWherePlaceLabel(
  PlaceParts place, {
  String? deviceCountryCode,
  String familiarRegions = '',
  @Deprecated('Use familiarRegions') String homeState = '',
  bool showCountryWhenSameCountry = false,
  bool showStateWhenSameState = false,
}) {
  final csv =
      familiarRegions.isNotEmpty ? familiarRegions : homeState;
  final display = formatWhereDisplay(
    place,
    deviceCountryCode: deviceCountryCode,
    familiarRegions: csv,
    showCountryWhenSameCountry: showCountryWhenSameCountry,
    showStateWhenSameState: showStateWhenSameState,
  );
  if (display.label.isEmpty) return null;
  return display.label;
}
