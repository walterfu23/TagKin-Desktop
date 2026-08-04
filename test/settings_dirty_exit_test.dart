import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_store.dart';
import 'package:tagkin_desktop/prefs/settings_page.dart';

void main() {
  testWidgets('dirty Settings exit shows Discard/Cancel/Save', (tester) async {
    final store = MemoryDesktopPrefsStore();
    final prefsController = DesktopPrefsController(store: store);
    await prefsController.load();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          desktopPrefsControllerProvider.overrideWith((ref) => prefsController),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const Key('open-settings'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsPage(),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pref-multi-column-sort')));
    await tester.pump();

    // Back via AppBar.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-dirty-dialog')), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-dirty-discard')));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsNothing);
    expect(prefsController.prefs.multiColumnSort, isFalse);
  });

  testWidgets('dirty Settings Save from exit dialog persists', (tester) async {
    final store = MemoryDesktopPrefsStore();
    final prefsController = DesktopPrefsController(store: store);
    await prefsController.load();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          desktopPrefsControllerProvider.overrideWith((ref) => prefsController),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const Key('open-settings'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsPage(),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pref-multi-column-sort')));
    await tester.pump();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-dirty-save')));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsNothing);
    expect(prefsController.prefs.multiColumnSort, isTrue);
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
