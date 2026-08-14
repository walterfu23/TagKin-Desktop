import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_store.dart';
import 'package:tagkin_desktop/ui/format_local_datetime.dart';
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
        formatWherePlaceLabel(sf, deviceCountryCode: 'US', familiarRegions: 'CA'),
        'San Francisco',
      );
    });

    test('showCountryWhenSameCountry keeps country', () {
      expect(
        formatWherePlaceLabel(
          sf,
          deviceCountryCode: 'US',
          familiarRegions: 'CA',
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
          familiarRegions: 'CA',
          showStateWhenSameState: true,
        ),
        'San Francisco, CA',
      );
    });

    test('empty familiarRegions always shows state', () {
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
    test('defaults: where flags off; face overlays on; recents 20', () {
      expect(DesktopPrefs.defaults.showCountryWhenSameCountry, isFalse);
      expect(DesktopPrefs.defaults.showStateWhenSameState, isFalse);
      expect(DesktopPrefs.defaults.multiColumnSort, isFalse);
      expect(DesktopPrefs.defaults.showFaceOverlays, isTrue);
      expect(DesktopPrefs.defaults.familiarRegions, '');
      expect(DesktopPrefs.defaults.libraryPageSize, 50);
      expect(DesktopPrefs.defaults.recentCollectionsLimit, 20);
      expect(DesktopPrefs.defaults.nearDuplicateThreshold, 4);
      expect(DesktopPrefs.defaults.sampleMinIntervalMs, 1000);
      expect(DesktopPrefs.defaults.sampleMaxIntervalMs, 15000);
      expect(DesktopPrefs.defaults.softMaxFramesPerItem, 500);
      expect(DesktopPrefs.defaults.sceneCutThreshold, 0.3);
      expect(DesktopPrefs.defaults.facesDetectScoreThreshold, 0.2);
      expect(DesktopPrefs.defaults.facesTrayPageLimit, 500);
      expect(DesktopPrefs.defaults.autoConfirmHighConfidencePersonMatches, isTrue);
      expect(DesktopPrefs.defaults.autoConfirmMinConfidencePercent, 95);
      expect(DesktopPrefs.defaults.jobsPollIntervalSeconds, 2);
      expect(
        DesktopPrefs.defaults.dateTimeFormat,
        DateTimeDisplayFormat.local,
      );
    });

    test('round-trips through JSON including new prefs', () async {
      final dir = await Directory.systemTemp.createTemp('tagkin_prefs_');
      addTearDown(() => dir.delete(recursive: true));
      final store = DesktopPrefsStore(supportDir: dir);
      const prefs = DesktopPrefs(
        showCountryWhenSameCountry: true,
        showStateWhenSameState: true,
        multiColumnSort: true,
        showFaceOverlays: false,
        familiarRegions: 'CA',
        libraryPageSize: 25,
        recentCollectionsLimit: 10,
        nearDuplicateThreshold: 6,
        sampleMinIntervalMs: 800,
        sampleMaxIntervalMs: 12000,
        softMaxFramesPerItem: 200,
        sceneCutThreshold: 0.4,
        facesDetectScoreThreshold: 0.35,
        facesTrayPageLimit: 200,
        autoConfirmHighConfidencePersonMatches: false,
        autoConfirmMinConfidencePercent: 75,
        jobsPollIntervalSeconds: 5,
        dateTimeFormat: DateTimeDisplayFormat.iso24,
      );
      await store.save(prefs);
      expect(await store.load(), prefs);
    });

    test('fromJson defaults showFaceOverlays to true when missing', () {
      final prefs = DesktopPrefs.fromJson({
        'where.showCountryWhenSameCountry': false,
        'ui.multiColumnSort': false,
      });
      expect(prefs.showFaceOverlays, isTrue);
      expect(prefs.recentCollectionsLimit, 20);
      expect(prefs.libraryPageSize, 50);
      expect(prefs.dateTimeFormat, DateTimeDisplayFormat.local);
      expect(prefs.dateTimeFormatOrLocal, DateTimeDisplayFormat.local);
    });

    test('fromJson migrates where.homeState to familiarRegions', () {
      final prefs = DesktopPrefs.fromJson({
        'where.homeState': 'California',
      });
      expect(prefs.familiarRegions, 'California');
    });

    test('normalizeFamiliarRegionsCsv trims dedupes and drops empties', () {
      expect(
        normalizeFamiliarRegionsCsv(' California, , nevada, California '),
        'California, nevada',
      );
      expect(normalizeFamiliarRegionsCsv(', ,'), '');
      expect(normalizeFamiliarRegionsCsv(''), '');
    });

    test('invalidFamiliarRegionTokens lists letter-less tokens', () {
      expect(invalidFamiliarRegionTokens('CA, -, NV'), ['-']);
      expect(invalidFamiliarRegionTokens('123, --'), ['123', '--']);
      expect(invalidFamiliarRegionTokens('CA, Nevada'), isEmpty);
    });

    test('isValidFamiliarRegionToken letter rule', () {
      expect(isValidFamiliarRegionToken('CA'), isTrue);
      expect(isValidFamiliarRegionToken('zzz'), isTrue);
      expect(isValidFamiliarRegionToken('Île-de-France'), isTrue);
      expect(isValidFamiliarRegionToken('-'), isFalse);
      expect(isValidFamiliarRegionToken('123'), isFalse);
      expect(isValidFamiliarRegionToken(''), isFalse);
    });

    test('normalizeFamiliarRegionsCsv drops invalid tokens', () {
      expect(
        normalizeFamiliarRegionsCsv('CA, -, NV, wa'),
        'CA, NV, wa',
      );
      expect(normalizeFamiliarRegionsCsv('zzz'), 'zzz');
      expect(normalizeFamiliarRegionsCsv('-'), '');
    });

    test('fromJson normalizes messy familiarRegions CSV', () {
      final prefs = DesktopPrefs.fromJson({
        'where.familiarRegions': ' CA, , ca, Nevada ',
      });
      expect(prefs.familiarRegions, 'CA, Nevada');
    });

    test('addFamiliarRegion appends and dedupes', () async {
      final dir = await Directory.systemTemp.createTemp('tagkin_prefs_fam_');
      addTearDown(() => dir.delete(recursive: true));
      final controller = DesktopPrefsController(
        store: DesktopPrefsStore(supportDir: dir),
      );
      expect(await controller.addFamiliarRegion('California'), isTrue);
      expect(controller.prefs.familiarRegions, 'California');
      expect(await controller.addFamiliarRegion('california'), isFalse);
      expect(await controller.addFamiliarRegion('Nevada'), isTrue);
      expect(controller.prefs.familiarRegions, 'California, Nevada');
    });

    test('CSV familiarRegions matches any entry', () {
      expect(
        formatWherePlaceLabel(
          const PlaceParts(
            locality: 'Reno',
            administrativeArea: 'Nevada',
            country: 'United States',
            isoCountryCode: 'US',
          ),
          deviceCountryCode: 'US',
          familiarRegions: 'California, Nevada',
        ),
        'Reno',
      );
    });

    test('restoreDefaults writes factory prefs', () async {
      final dir = await Directory.systemTemp.createTemp('tagkin_prefs_restore_');
      addTearDown(() => dir.delete(recursive: true));
      final controller = DesktopPrefsController(
        store: DesktopPrefsStore(supportDir: dir),
      );
      await controller.update(
        const DesktopPrefs(libraryPageSize: 12, recentCollectionsLimit: 3),
      );
      await controller.restoreDefaults();
      expect(controller.prefs, DesktopPrefs.defaults);
      expect(await DesktopPrefsStore(supportDir: dir).load(), DesktopPrefs.defaults);
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
        prefsProvider: () => const DesktopPrefs(familiarRegions: 'NY'),
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
