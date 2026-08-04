import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';
import 'package:tagkin_desktop/where/reverse_geocoder.dart';
import 'package:tagkin_desktop/where/where_place_label.dart';

/// Shared reverse-geocode cache for library + review where labels.
final whereLabelResolverProvider = Provider<WhereLabelResolver>((ref) {
  return WhereLabelResolver(
    prefsProvider: () => ref.read(desktopPrefsProvider),
  );
});

/// Turns raw where-tag values into display labels (GPS → city/state).
///
/// Non-GPS tags (e.g. model `"restaurant"`) pass through unchanged.
/// Failed reverse-geocode keeps the original `"lat,lng"` string.
class WhereLabelResolver {
  WhereLabelResolver({
    ReverseGeocoder? geocoder,
    String? Function()? deviceCountryCodeProvider,
    DesktopPrefs Function()? prefsProvider,
  })  : _geocoder = geocoder ?? DefaultReverseGeocoder(),
        _deviceCountryCode =
            deviceCountryCodeProvider ?? deviceCountryCode,
        _prefs = prefsProvider ?? (() => DesktopPrefs.defaults);

  final ReverseGeocoder _geocoder;
  final String? Function() _deviceCountryCode;
  final DesktopPrefs Function() _prefs;
  final Map<String, WhereDisplay> _cache = {};
  final Map<String, Future<WhereDisplay>> _inflight = {};

  void clearCache() {
    _cache.clear();
    _inflight.clear();
  }

  Future<WhereDisplay> resolveDisplay(String rawValue) {
    final cached = _cache[rawValue];
    if (cached != null) return Future.value(cached);

    final pending = _inflight[rawValue];
    if (pending != null) return pending;

    final future = _resolveUncached(rawValue);
    _inflight[rawValue] = future;
    return future.whenComplete(() => _inflight.remove(rawValue));
  }

  Future<String> resolve(String rawValue) async {
    return (await resolveDisplay(rawValue)).label;
  }

  Future<List<WhereDisplay>> resolveAllDisplays(Iterable<String> values) async {
    final out = <WhereDisplay>[];
    for (final value in values) {
      out.add(await resolveDisplay(value));
    }
    return out;
  }

  Future<List<String>> resolveAll(Iterable<String> values) async {
    return [
      for (final d in await resolveAllDisplays(values)) d.label,
    ];
  }

  Future<WhereDisplay> _resolveUncached(String rawValue) async {
    final coords = parseLatLngTag(rawValue);
    if (coords == null) {
      final plain = WhereDisplay.plain(rawValue);
      _cache[rawValue] = plain;
      return plain;
    }
    try {
      final place = await _geocoder.reverse(coords.lat, coords.lng);
      if (place != null) {
        final prefs = _prefs();
        final display = formatWhereDisplay(
          place,
          deviceCountryCode: _deviceCountryCode(),
          familiarRegions: prefs.familiarRegions,
          showCountryWhenSameCountry: prefs.showCountryWhenSameCountry,
          showStateWhenSameState: prefs.showStateWhenSameState,
        );
        if (display.label.isNotEmpty) {
          _cache[rawValue] = display;
          return display;
        }
      }
    } catch (_) {
      // Keep raw coords on failure.
    }
    final fallback = WhereDisplay.plain(rawValue);
    _cache[rawValue] = fallback;
    return fallback;
  }
}
