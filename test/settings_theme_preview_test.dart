import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/persons/collections_store.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_store.dart';
import 'package:tagkin_desktop/prefs/settings_page.dart';
import 'package:tagkin_desktop/theme/theme_palettes.dart';
import 'package:tagkin_desktop/update/client_identity.dart';
import 'package:tagkin_desktop/update/client_support_providers.dart';

import 'fake_credits_repository.dart';
import 'fake_usage_repository.dart';

void main() {
  testWidgets('Settings intro follows the theme before Save', (tester) async {
    final prefs = DesktopPrefsController(store: MemoryDesktopPrefsStore());
    await prefs.load();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          desktopPrefsControllerProvider.overrideWith((ref) => prefs),
          usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
          creditsRepositoryProvider.overrideWithValue(FakeCreditsRepository()),
          collectionsStoreProvider.overrideWithValue(MemoryCollectionsStore()),
          clientIdentityProvider.overrideWithValue(
            const ClientIdentity(version: '1.0.0+1', platform: 'test'),
          ),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    final cream = paletteFor('cream').primary.withValues(alpha: 0.07);
    expect(
      tester.widget<Card>(find.byKey(const Key('settings-intro'))).color,
      cream,
    );

    await tester.tap(find.byKey(const Key('settings-theme')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mint').last);
    await tester.pumpAndSettle();

    final mint = paletteFor('mint');
    expect(
      tester.widget<Card>(find.byKey(const Key('settings-intro'))).color,
      mint.primary.withValues(alpha: 0.07),
    );
    final groupCards = tester
        .widgetList<Card>(find.byType(Card))
        .where((card) => card.key != const Key('settings-intro'));
    expect(groupCards, isNotEmpty);
    for (final card in groupCards) {
      expect(card.color, mint.surface);
    }
    expect(prefs.prefs.themeId, 'cream');

    RadioListTile<ThemeScope> scopeTile(Key key) =>
        tester.widget<RadioListTile<ThemeScope>>(find.byKey(key));

    expect(scopeTile(const Key('settings-theme-scope-all')).selected, isTrue);
    expect(
      scopeTile(const Key('settings-theme-scope-all')).selectedTileColor,
      mint.primary.withValues(alpha: 0.14),
    );

    await tester.tap(find.byKey(const Key('settings-theme')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blush').last);
    await tester.pumpAndSettle();

    expect(
      scopeTile(const Key('settings-theme-scope-all')).selectedTileColor,
      paletteFor('blush').primary.withValues(alpha: 0.14),
    );
  });
}

class MemoryDesktopPrefsStore extends DesktopPrefsStore {
  MemoryDesktopPrefsStore() : super(supportDir: null);

  DesktopPrefs saved = DesktopPrefs.defaults;

  @override
  Future<DesktopPrefs> load() async => saved;

  @override
  Future<void> save(DesktopPrefs prefs) async {
    saved = prefs;
  }
}
