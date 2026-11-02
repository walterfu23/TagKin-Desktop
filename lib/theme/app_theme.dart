import 'package:flutter/material.dart';
import 'package:tagkin_desktop/auth/clerk_theme.dart';
import 'package:tagkin_desktop/theme/theme_palettes.dart';

/// Text and icons on [accent]. Light accents get dark text.
Color onAccent(Color accent) =>
    accent.computeLuminance() > 0.5 ? const Color(0xFF1A1A1A) : Colors.white;

ThemeData buildAppTheme({required String themeId}) {
  final p = paletteFor(themeId);
  final base = p.isDark ? ThemeData.dark() : ThemeData.light();
  final ink = onAccent(p.primary);
  // Container roles stay unset so they fall back to these palette colors,
  // the same way Cliptorium's scheme does. A seeded scheme invents tints.
  final scheme = ColorScheme(
    brightness: p.isDark ? Brightness.dark : Brightness.light,
    primary: p.primary,
    onPrimary: ink,
    secondary: p.primary,
    onSecondary: ink,
    error: base.colorScheme.error,
    onError: base.colorScheme.onError,
    surface: p.surface,
    onSurface: p.onBackground,
    outline: p.onBackground.withValues(alpha: 0.38),
    outlineVariant: p.onBackground.withValues(alpha: 0.15),
  );
  final accent = p.primary;
  return base.copyWith(
    scaffoldBackgroundColor: p.background,
    colorScheme: scheme,
    hoverColor: accent.withValues(alpha: 0.10),
    focusColor: accent.withValues(alpha: 0.16),
    highlightColor: accent.withValues(alpha: 0.14),
    splashColor: accent.withValues(alpha: 0.20),
    canvasColor: p.surface,
    textTheme: base.textTheme.apply(
      bodyColor: p.onBackground,
      displayColor: p.onBackground,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.surface,
      foregroundColor: p.onBackground,
      elevation: 0,
    ),
    cardColor: p.surface,
    dividerColor: p.onBackground.withValues(alpha: 0.15),
    extensions: <ThemeExtension<dynamic>>[tagKinClerkTheme()],
  );
}
