import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';

/// Brand accent — filled Clerk strategy / Continue buttons (`ClerkMaterialButton` dark).
const Color kTagKinClerkAccent = Color(0xFF3B5BDB);

/// Clerk furniture theme aligned with TagKin brand colors.
ClerkThemeExtension tagKinClerkTheme() {
  return ClerkThemeExtension(
    colors: const ClerkThemeColors(
      background: Colors.white,
      altBackground: Color(0xFFEEF1F8),
      borderSide: Color(0xFFC5CDDE),
      text: Color(0xFF1A1A1A),
      icon: Color(0xFF5A6478),
      lightweightText: Color(0xFF5A6478),
      error: Color(0xFFD92D20),
      accent: kTagKinClerkAccent,
    ),
  );
}
