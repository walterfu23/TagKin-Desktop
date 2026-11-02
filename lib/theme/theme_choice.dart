import 'package:tagkin_desktop/theme/theme_palettes.dart';

/// One collection's saved theme, if it has one.
class CollectionThemeSlot {
  const CollectionThemeSlot({required this.id, this.themeId});

  final String id;
  final String? themeId;
}

/// Theme id to store after a Settings save while scope is This collection.
///
/// [stampMissing] fills collections that have no theme with [globalThemeId].
/// A known saved theme stays. [openThemeId] replaces the open collection.
String? assignedCollectionTheme({
  required String? existing,
  required String globalThemeId,
  required bool stampMissing,
  required bool isOpen,
  String? openThemeId,
}) {
  final known = existing != null && isKnownTheme(existing) ? existing : null;
  var theme = known;
  if (stampMissing && theme == null) theme = canonicalThemeId(globalThemeId);
  if (isOpen && openThemeId != null) theme = canonicalThemeId(openThemeId);
  return theme;
}

List<CollectionThemeSlot> assignCollectionThemes({
  required List<CollectionThemeSlot> collections,
  required String globalThemeId,
  required bool stampMissing,
  String? openCollectionId,
  String? openThemeId,
}) {
  return [
    for (final c in collections)
      CollectionThemeSlot(
        id: c.id,
        themeId: assignedCollectionTheme(
          existing: c.themeId,
          globalThemeId: globalThemeId,
          stampMissing: stampMissing,
          isOpen: openCollectionId != null && c.id == openCollectionId,
          openThemeId: openThemeId,
        ),
      ),
  ];
}
