import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geocoding/geocoding.dart' as geo;
import 'package:http/http.dart' as http;
import 'package:tagkin_desktop/where/where_place_label.dart';

/// Reverse-geocodes GPS coords to [PlaceParts] (city / region / country).
abstract class ReverseGeocoder {
  Future<PlaceParts?> reverse(double lat, double lng);
}

/// OS geocoder on Darwin/Android; Nominatim fallback elsewhere (Windows).
class DefaultReverseGeocoder implements ReverseGeocoder {
  DefaultReverseGeocoder({
    http.Client? httpClient,
    this._geocoding,
    this.userAgent = 'TagKinDesktop/1.0 (where reverse-geocode)',
  }) : _http = httpClient ?? http.Client();

  final http.Client _http;
  final geo.Geocoding? _geocoding;
  final String userAgent;

  @override
  Future<PlaceParts?> reverse(double lat, double lng) async {
    if (_supportsPlatformGeocoder) {
      try {
        final parts = await _platformReverse(lat, lng);
        if (parts != null) return parts;
      } catch (_) {
        // Fall through to Nominatim.
      }
    }
    return _nominatimReverse(lat, lng);
  }

  bool get _supportsPlatformGeocoder {
    if (kIsWeb) return false;
    return Platform.isMacOS || Platform.isIOS || Platform.isAndroid;
  }

  Future<PlaceParts?> _platformReverse(double lat, double lng) async {
    final client = _geocoding ?? geo.Geocoding();
    final marks = await client.placemarkFromCoordinates(lat, lng);
    if (marks.isEmpty) return null;
    final p = marks.first;
    return PlaceParts(
      locality: p.locality?.isNotEmpty == true
          ? p.locality
          : (p.subLocality?.isNotEmpty == true ? p.subLocality : null),
      administrativeArea: p.administrativeArea,
      country: p.country,
      isoCountryCode: p.isoCountryCode,
    );
  }

  Future<PlaceParts?> _nominatimReverse(double lat, double lng) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'lat': lat.toString(),
      'lon': lng.toString(),
      'format': 'json',
      'addressdetails': '1',
    });
    final response = await _http.get(
      uri,
      headers: {
        'User-Agent': userAgent,
        'Accept': 'application/json',
      },
    );
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    final address = decoded['address'];
    if (address is! Map<String, dynamic>) return null;

    String? pick(List<String> keys) {
      for (final key in keys) {
        final v = address[key];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return null;
    }

    return PlaceParts(
      locality: pick(const [
        'city',
        'town',
        'village',
        'municipality',
        'hamlet',
        'suburb',
      ]),
      administrativeArea: pick(const [
        'state',
        'province',
        'region',
        'state_district',
      ]),
      country: pick(const ['country']),
      isoCountryCode: pick(const ['country_code'])?.toUpperCase(),
    );
  }
}

/// Test double — maps `"lat,lng"` keys to canned [PlaceParts].
class FakeReverseGeocoder implements ReverseGeocoder {
  FakeReverseGeocoder(this.byCoordKey);

  final Map<String, PlaceParts> byCoordKey;

  static String key(double lat, double lng) => '$lat,$lng';

  @override
  Future<PlaceParts?> reverse(double lat, double lng) async {
    return byCoordKey[key(lat, lng)];
  }
}
