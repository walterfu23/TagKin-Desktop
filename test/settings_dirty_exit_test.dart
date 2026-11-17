import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/item_lists/item_list_nle.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_store.dart';
import 'package:tagkin_desktop/prefs/settings_page.dart';
import 'package:tagkin_desktop/ui/format_local_datetime.dart';

import 'fake_credits_repository.dart';
import 'fake_usage_repository.dart';

List<Override> _overrides(DesktopPrefsController prefsController) {
  return [
    desktopPrefsControllerProvider.overrideWith((ref) => prefsController),
    usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
    creditsRepositoryProvider.overrideWithValue(FakeCreditsRepository()),
  ];
}

Future<void> _openSettings(WidgetTester tester) async {
  // Settings is a lazy list; a tall window builds every group.
  tester.view.physicalSize = const Size(1000, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.tap(find.byKey(const Key('open-settings')));
  await tester.pumpAndSettle();
}

Widget _host() {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          key: const Key('open-settings'),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
            );
          },
          child: const Text('Open'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('dirty Settings exit shows Discard/Cancel/Save', (tester) async {
    final store = MemoryDesktopPrefsStore();
    final prefsController = DesktopPrefsController(store: store);
    await prefsController.load();

    await tester.pumpWidget(
      ProviderScope(overrides: _overrides(prefsController), child: _host()),
    );
    await _openSettings(tester);

    expect(find.byKey(const Key('pref-date-time-format')), findsOneWidget);
    expect(find.text('Local (this computer)'), findsOneWidget);

    final country = find.byKey(const Key('pref-show-country-same'));
    await tester.ensureVisible(country);
    await tester.pumpAndSettle();
    await tester.tap(country);
    await tester.pump();

    // Back via AppBar.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-dirty-dialog')), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-dirty-discard')));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsNothing);
    expect(prefsController.prefs.showCountryWhenSameCountry, isFalse);
  });

  testWidgets('familiar regions undo restores the previous text', (
    tester,
  ) async {
    final store = MemoryDesktopPrefsStore();
    final prefsController = DesktopPrefsController(store: store);
    await prefsController.load();

    await tester.pumpWidget(
      ProviderScope(overrides: _overrides(prefsController), child: _host()),
    );
    await _openSettings(tester);

    final field = find.byKey(const Key('pref-familiar-regions'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'California');
    await tester.pump();
    expect(find.byKey(const Key('undo-depth')), findsOneWidget);

    final scope = tester.element(find.byKey(const Key('pref-show-country-same')));
    Focus.of(scope).requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pump();

    expect(tester.widget<TextField>(field).controller?.text, isEmpty);
  });

  testWidgets('dirty Settings Save from exit dialog persists', (tester) async {
    final store = MemoryDesktopPrefsStore();
    final prefsController = DesktopPrefsController(store: store);
    await prefsController.load();

    await tester.pumpWidget(
      ProviderScope(overrides: _overrides(prefsController), child: _host()),
    );
    await _openSettings(tester);

    final country = find.byKey(const Key('pref-show-country-same'));
    await tester.ensureVisible(country);
    await tester.pumpAndSettle();
    await tester.tap(country);
    await tester.pump();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-dirty-save')));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsNothing);
    expect(prefsController.prefs.showCountryWhenSameCountry, isTrue);
  });

  testWidgets('Settings slider Save persists library page size', (
    tester,
  ) async {
    final store = MemoryDesktopPrefsStore();
    final prefsController = DesktopPrefsController(store: store);
    await prefsController.load();

    await tester.pumpWidget(
      ProviderScope(overrides: _overrides(prefsController), child: _host()),
    );
    await _openSettings(tester);

    // Library is below the intro + Where card; ListView builds lazily.
    final pageSizeKey = find.byKey(const Key('pref-library-page-size'));
    await tester.dragUntilVisible(
      pageSizeKey,
      find.byType(ListView),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();

    final slider = tester.widget<Slider>(pageSizeKey);
    slider.onChanged!(25);
    await tester.pump();

    await tester.tap(find.byKey(const Key('settings-save')));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsNothing);
    expect(prefsController.prefs.libraryPageSize, 25);
  });

  testWidgets('Date and time format Save persists iso24', (tester) async {
    final store = MemoryDesktopPrefsStore();
    final prefsController = DesktopPrefsController(store: store);
    await prefsController.load();

    await tester.pumpWidget(
      ProviderScope(overrides: _overrides(prefsController), child: _host()),
    );
    await _openSettings(tester);

    await tester.tap(find.byKey(const Key('pref-date-time-format')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('yyyy-MM-dd HH:mm:ss').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-save')));
    await tester.pumpAndSettle();

    expect(prefsController.prefs.dateTimeFormat, DateTimeDisplayFormat.iso24);
  });

  testWidgets(
    'Settings has no export timeline controls and Save keeps their values',
    (tester) async {
      final store = MemoryDesktopPrefsStore();
      final prefsController = DesktopPrefsController(store: store);
      await prefsController.load();
      await prefsController.update(
        prefsController.prefs.copyWith(
          exportPhotoStillDurationSeconds: 6.0,
          exportPhotoTransition: ExportPhotoTransition.dipToBlack,
          exportPhotoTransitionSeconds: 0.5,
          exportSequenceSize: ExportSequenceSize.p4k,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(overrides: _overrides(prefsController), child: _host()),
      );
      await _openSettings(tester);

      final loopCount = find.byKey(const Key('pref-export-music-loop-count'));
      await tester.dragUntilVisible(
        loopCount,
        find.byType(ListView),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      expect(loopCount, findsOneWidget);
      for (final key in const [
        'pref-export-photo-still-duration',
        'pref-export-photo-transition',
        'pref-export-photo-transition-duration',
        'pref-export-sequence-size',
      ]) {
        expect(find.byKey(Key(key)), findsNothing, reason: key);
      }

      tester.widget<Slider>(loopCount).onChanged!(3);
      await tester.pump();
      await tester.tap(find.byKey(const Key('settings-save')));
      await tester.pumpAndSettle();

      final saved = prefsController.prefs;
      expect(saved.exportMusicLoopCount, 3);
      expect(saved.exportPhotoStillDurationSeconds, 6.0);
      expect(saved.exportPhotoTransition, ExportPhotoTransition.dipToBlack);
      expect(saved.exportPhotoTransitionSeconds, 0.5);
      expect(saved.exportSequenceSize, ExportSequenceSize.p4k);
    },
  );

  testWidgets('Settings Credits group shows remaining from /usage', (
    tester,
  ) async {
    final store = MemoryDesktopPrefsStore();
    final prefsController = DesktopPrefsController(store: store);
    await prefsController.load();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          desktopPrefsControllerProvider.overrideWith((ref) => prefsController),
          usageRepositoryProvider.overrideWithValue(
            FakeUsageRepository(
              summary: fixtureUsageSummary(remainingCredits: 1234),
            ),
          ),
          creditsRepositoryProvider.overrideWithValue(FakeCreditsRepository()),
        ],
        child: _host(),
      ),
    );
    await _openSettings(tester);

    final tile = find.byKey(const Key('settings-credits-remaining'));
    await tester.dragUntilVisible(
      tile,
      find.byType(ListView),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();

    expect(tile, findsOneWidget);
    expect(find.text('Credits remaining'), findsOneWidget);
    expect(
      find.byKey(const Key('settings-credits-remaining-value')),
      findsOneWidget,
    );
    expect(find.text('1,234'), findsOneWidget);
    expect(find.byKey(const Key('settings-buy-credits')), findsOneWidget);
  });
}

/// In-memory prefs store for Settings widget tests.
class MemoryDesktopPrefsStore extends DesktopPrefsStore {
  MemoryDesktopPrefsStore() : super(supportDir: null);

  DesktopPrefs _prefs = DesktopPrefs.defaults;

  @override
  Future<DesktopPrefs> load() async => _prefs;

  @override
  Future<void> save(DesktopPrefs prefs) async {
    _prefs = prefs;
  }
}
