import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs.dart';
import 'package:tagkin_desktop/theme/app_theme.dart';
import 'package:tagkin_desktop/theme/theme_choice.dart';
import 'package:tagkin_desktop/theme/theme_palettes.dart';

void main() {
  test('unknown theme id falls back to Cream', () {
    expect(canonicalThemeId('nope'), kDefaultThemeId);
    expect(paletteFor('nope').id, kDefaultThemeId);
    expect(DesktopPrefs.defaults.themeId, kDefaultThemeId);
    expect(DesktopPrefs.defaults.themeScope, ThemeScope.all);
  });

  test('prefs round-trip theme id and scope', () {
    const prefs = DesktopPrefs(
      themeId: 'plum',
      themeScope: ThemeScope.collection,
    );
    final again = DesktopPrefs.fromJson(prefs.toJson());
    expect(again.themeId, 'plum');
    expect(again.themeScope, ThemeScope.collection);
    expect(
      DesktopPrefs.fromJson(<String, dynamic>{}).themeScope,
      ThemeScope.all,
    );
  });

  test('effective theme is global unless the collection has its own', () {
    expect(
      effectiveThemeId(
        collectionScope: false,
        globalThemeId: 'mint',
        collectionThemeId: 'plum',
      ),
      'mint',
    );
    expect(
      effectiveThemeId(
        collectionScope: true,
        globalThemeId: 'mint',
        collectionThemeId: 'plum',
      ),
      'plum',
    );
    expect(
      effectiveThemeId(
        collectionScope: true,
        globalThemeId: 'mint',
        collectionThemeId: null,
      ),
      'mint',
    );
  });

  test(
    'switching to this collection keeps a saved theme and fills a missing one',
    () {
      final assigned = assignCollectionThemes(
        collections: const [
          CollectionThemeSlot(id: 'a', themeId: 'plum'),
          CollectionThemeSlot(id: 'b'),
        ],
        globalThemeId: 'mint',
        stampMissing: true,
        openCollectionId: 'b',
        openThemeId: 'mint',
      );
      expect(assigned[0].themeId, 'plum');
      expect(assigned[1].themeId, 'mint');
    },
  );

  test('switching back to all collections leaves the saved theme stored', () {
    expect(
      effectiveThemeId(
        collectionScope: false,
        globalThemeId: 'cream',
        collectionThemeId: 'plum',
      ),
      'cream',
    );
    final kept = assignCollectionThemes(
      collections: const [CollectionThemeSlot(id: 'a', themeId: 'plum')],
      globalThemeId: 'cream',
      stampMissing: false,
    );
    expect(kept.single.themeId, 'plum');
  });

  test('every theme keeps its palette colors and drops the default tint', () {
    for (final palette in kPalettes) {
      final theme = buildAppTheme(themeId: palette.id);
      expect(
        theme.scaffoldBackgroundColor,
        palette.background,
        reason: palette.id,
      );
      expect(theme.colorScheme.primary, palette.primary, reason: palette.id);
      expect(theme.colorScheme.surface, palette.surface, reason: palette.id);
      expect(
        theme.colorScheme.onSurface,
        palette.onBackground,
        reason: palette.id,
      );
      expect(
        theme.colorScheme.primaryContainer,
        palette.primary,
        reason: palette.id,
      );
      expect(
        theme.colorScheme.surfaceContainerLow,
        palette.surface,
        reason: palette.id,
      );
      expect(
        theme.colorScheme.surfaceContainerHighest,
        palette.surface,
        reason: palette.id,
      );
      expect(
        theme.colorScheme.surfaceTint,
        palette.primary,
        reason: palette.id,
      );
      expect(
        theme.colorScheme.brightness,
        palette.isDark ? Brightness.dark : Brightness.light,
        reason: palette.id,
      );
      expect(
        theme.hoverColor,
        palette.primary.withValues(alpha: 0.10),
        reason: palette.id,
      );
      expect(
        theme.focusColor,
        palette.primary.withValues(alpha: 0.16),
        reason: palette.id,
      );
      expect(
        theme.highlightColor,
        palette.primary.withValues(alpha: 0.14),
        reason: palette.id,
      );
      expect(
        theme.splashColor,
        palette.primary.withValues(alpha: 0.20),
        reason: palette.id,
      );
      expect(theme.canvasColor, palette.surface, reason: palette.id);
    }
  });
}
