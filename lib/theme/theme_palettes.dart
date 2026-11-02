import 'package:flutter/material.dart';

class ThemePalette {
  const ThemePalette({
    required this.id,
    required this.label,
    required this.group,
    required this.isDark,
    required this.background,
    required this.surface,
    required this.primary,
    required this.onBackground,
  });

  final String id;
  final String label;
  final String group;
  final bool isDark;
  final Color background;
  final Color surface;
  final Color primary;
  final Color onBackground;
}

class ThemeGroup {
  const ThemeGroup({required this.label, required this.ids});

  final String label;
  final List<String> ids;
}

const kDefaultThemeId = 'cream';

/// Where a chosen theme is stored.
enum ThemeScope { all, collection }

ThemeScope themeScopeFromWire(Object? raw) =>
    raw == 'collection' ? ThemeScope.collection : ThemeScope.all;

/// Light, then Dark, then Colorful. Order within each group is fixed.
const kThemeGroups = <ThemeGroup>[
  ThemeGroup(
    label: 'Light',
    ids: ['paper', 'cream', 'blush', 'mint'],
  ),
  ThemeGroup(
    label: 'Dark',
    ids: ['high-contrast', 'sunset', 'forest', 'slate'],
  ),
  ThemeGroup(
    label: 'Colorful',
    ids: ['plum', 'terracotta', 'amber', 'meadow', 'lagoon', 'denim'],
  ),
];

const _paletteById = <String, ThemePalette>{
  'paper': ThemePalette(
    id: 'paper',
    label: 'Paper',
    group: 'Light',
    isDark: false,
    background: Color(0xFFF8F9FC),
    surface: Color(0xFFFFFFFF),
    primary: Color(0xFF3D5A80),
    onBackground: Color(0xFF1A1A2E),
  ),
  'cream': ThemePalette(
    id: 'cream',
    label: 'Cream',
    group: 'Light',
    isDark: false,
    background: Color(0xFFFAF6F0),
    surface: Color(0xFFFFFFFF),
    primary: Color(0xFF8B6914),
    onBackground: Color(0xFF2C2416),
  ),
  'blush': ThemePalette(
    id: 'blush',
    label: 'Blush',
    group: 'Light',
    isDark: false,
    background: Color(0xFFFAF2F4),
    surface: Color(0xFFFFFFFF),
    primary: Color(0xFFC45C7A),
    onBackground: Color(0xFF3D1F2B),
  ),
  'mint': ThemePalette(
    id: 'mint',
    label: 'Mint',
    group: 'Light',
    isDark: false,
    background: Color(0xFFEEF8F4),
    surface: Color(0xFFFFFFFF),
    primary: Color(0xFF2E7D5A),
    onBackground: Color(0xFF1A3328),
  ),
  'plum': ThemePalette(
    id: 'plum',
    label: 'Plum',
    group: 'Colorful',
    isDark: true,
    background: Color(0xFFAF70B5),
    surface: Color(0xFFBF86C4),
    primary: Color(0xFF8A4F90),
    onBackground: Color(0xFFFAF0FB),
  ),
  'terracotta': ThemePalette(
    id: 'terracotta',
    label: 'Terracotta',
    group: 'Colorful',
    isDark: true,
    background: Color(0xFFC77469),
    surface: Color(0xFFD4897E),
    primary: Color(0xFFA04E42),
    onBackground: Color(0xFFFFF5F3),
  ),
  'amber': ThemePalette(
    id: 'amber',
    label: 'Amber',
    group: 'Colorful',
    isDark: false,
    background: Color(0xFFF5AB51),
    surface: Color(0xFFFFF4E6),
    primary: Color(0xFFC47A10),
    onBackground: Color(0xFF2C1A08),
  ),
  'meadow': ThemePalette(
    id: 'meadow',
    label: 'Meadow',
    group: 'Colorful',
    isDark: true,
    background: Color(0xFF5DA165),
    surface: Color(0xFF6EB378),
    primary: Color(0xFF3D7A48),
    onBackground: Color(0xFFF0FFF2),
  ),
  'lagoon': ThemePalette(
    id: 'lagoon',
    label: 'Lagoon',
    group: 'Colorful',
    isDark: true,
    background: Color(0xFF5D97A1),
    surface: Color(0xFF6FAAB4),
    primary: Color(0xFF3D7580),
    onBackground: Color(0xFFEEF8FA),
  ),
  'denim': ThemePalette(
    id: 'denim',
    label: 'Denim',
    group: 'Colorful',
    isDark: true,
    background: Color(0xFF325B99),
    surface: Color(0xFF3E6AAB),
    primary: Color(0xFF5B8FD4),
    onBackground: Color(0xFFE8EEF8),
  ),
  'high-contrast': ThemePalette(
    id: 'high-contrast',
    label: 'High contrast',
    group: 'Dark',
    isDark: true,
    background: Color(0xFF000000),
    surface: Color(0xFF111111),
    primary: Color(0xFFFFD600),
    onBackground: Color(0xFFFFFFFF),
  ),
  'sunset': ThemePalette(
    id: 'sunset',
    label: 'Sunset',
    group: 'Dark',
    isDark: true,
    background: Color(0xFF2A1F2D),
    surface: Color(0xFF3D2D42),
    primary: Color(0xFFE07A5F),
    onBackground: Color(0xFFF5E6F0),
  ),
  'forest': ThemePalette(
    id: 'forest',
    label: 'Forest',
    group: 'Dark',
    isDark: true,
    background: Color(0xFF1A2421),
    surface: Color(0xFF243029),
    primary: Color(0xFF6DBF8A),
    onBackground: Color(0xFFE8F0EC),
  ),
  'slate': ThemePalette(
    id: 'slate',
    label: 'Slate',
    group: 'Dark',
    isDark: true,
    background: Color(0xFF1E293B),
    surface: Color(0xFF334155),
    primary: Color(0xFF94A3B8),
    onBackground: Color(0xFFF1F5F9),
  ),
};

List<ThemePalette> get kPalettes => [
  for (final group in kThemeGroups)
    for (final id in group.ids) _paletteById[id]!,
];

bool isKnownTheme(String id) => _paletteById.containsKey(id);

ThemePalette paletteFor(String id) =>
    _paletteById[id] ?? _paletteById[kDefaultThemeId]!;

/// Known theme id, or [kDefaultThemeId] when [id] is missing or unknown.
String canonicalThemeId(String? id) =>
    id != null && isKnownTheme(id) ? id : kDefaultThemeId;

/// Global theme, unless [collectionScope] and the collection has its own.
String effectiveThemeId({
  required bool collectionScope,
  required String globalThemeId,
  String? collectionThemeId,
}) {
  final global = canonicalThemeId(globalThemeId);
  if (!collectionScope) return global;
  if (collectionThemeId != null && isKnownTheme(collectionThemeId)) {
    return collectionThemeId;
  }
  return global;
}
