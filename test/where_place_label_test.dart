import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_store.dart';
import 'package:tagkin_desktop/where/reverse_geocoder.dart';
import 'package:tagkin_desktop/where/where_label_resolver.dart';
import 'package:tagkin_desktop/where/where_place_label.dart';

void main() {
  group('parseLatLngTag', () {
    test('parses pre-pass GPS tags', () {
      final c = parseLatLngTag('37.7749,-122.4194');
      expect(c?.lat, closeTo(37.7749, 1e-6));
      expect(c?.lng, closeTo(-122.4194, 1e-6));
    });

    test('rejects place labels and out-of-range', () {
      expect(parseLatLngTag('restaurant'), isNull);
      expect(parseLatLngTag('91,0'), isNull);
      expect(parseLatLngTag('0,181'), isNull);
    });
  });

  group('formatWherePlaceLabel', () {
    const sf = PlaceParts(
      locality: 'San Francisco',
      administrativeArea: 'CA',
      country: 'United States',
      isoCountryCode: 'US',
    );

    test('same country omits country by default', () {
      expect(
        formatWherePlaceLabel(sf, deviceCountryCode: 'US', homeState: 'CA'),
        'San Francisco',
      );
    });

    test('showCountryWhenSameCountry keeps country', () {
      expect(
        formatWherePlaceLabel(
          sf,
          deviceCountryCode: 'US',
          homeState: 'CA',
          showCountryWhenSameCountry: true,
        ),
        'San Francisco, United States',
      );
    });

    test('showStateWhenSameState keeps state when home matches', () {
      expect(
        formatWherePlaceLabel(
          sf,
          deviceCountryCode: 'US',
          homeState: 'CA',
          showStateWhenSameState: true,
        ),
        'San Francisco, CA',
      );
    });

    test('empty homeState always shows state', () {
      expect(
        formatWherePlaceLabel(sf, deviceCountryCode: 'US'),
        'San Francisco, CA',
      );
    });

    test('different country includes country name', () {
      expect(
        formatWherePlaceLabel(
          const PlaceParts(
            locality: 'Paris',
            administrativeArea: 'Île-de-France',
            country: 'France',
            isoCountryCode: 'FR',
          ),
          deviceCountryCode: 'US',
        ),
        'Paris, Île-de-France, France',
      );
    });

    test('missing city still shows region', () {
      expect(
        formatWherePlaceLabel(
          const PlaceParts(
            administrativeArea: 'California',
            country: 'United States',
            isoCountryCode: 'US',
          ),
          deviceCountryCode: 'US',
        ),
        'California',
      );
    });
  });

  group('DesktopPrefs', () {
    test('defaults are all false / empty home', () {
      expect(DesktopPrefs.defaults.showCountryWhenSameCountry, isFalse);
      expect(DesktopPrefs.defaults.showStateWhenSameState, isFalse);
      expect(DesktopPrefs.defaults.multiColumnSort, isFalse);
      expect(DesktopPrefs.defaults.homeState, '');
    });

    test('round-trips through JSON', () async {
      final dir = await Directory.systemTemp.createTemp('tagkin_prefs_');
      addTearDown(() => dir.delete(recursive: true));
      final store = DesktopPrefsStore(supportDir: dir);
      const prefs = DesktopPrefs(
        showCountryWhenSameCountry: true,
        showStateWhenSameState: true,
        multiColumnSort: true,
        homeState: 'CA',
      );
      await store.save(prefs);
      expect(await store.load(), prefs);
    });
  });

  group('WhereLabelResolver', () {
    test('maps GPS tags via geocoder; passes scene labels through', () async {
      final resolver = WhereLabelResolver(
        geocoder: FakeReverseGeocoder({
          FakeReverseGeocoder.key(37.77, -122.42): const PlaceParts(
            locality: 'San Francisco',
            administrativeArea: 'CA',
            country: 'United States',
            isoCountryCode: 'US',
          ),
        }),
        deviceCountryCodeProvider: () => 'US',
        prefsProvider: () => const DesktopPrefs(homeState: 'NY'),
      );

      expect(await resolver.resolve('restaurant'), 'restaurant');
      expect(
        await resolver.resolve('37.77,-122.42'),
        'San Francisco, CA',
      );
    });

    test('keeps raw coords when geocode returns nothing', () async {
      final resolver = WhereLabelResolver(
        geocoder: FakeReverseGeocoder({}),
        deviceCountryCodeProvider: () => 'US',
      );
      expect(await resolver.resolve('10.0,20.0'), '10.0,20.0');
    });
  });
}
