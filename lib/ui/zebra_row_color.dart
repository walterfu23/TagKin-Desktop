import 'package:flutter/material.dart';

/// Slight grey for every second row (0-based odd index), from the theme.
Color zebraRowColor(ColorScheme scheme) =>
    scheme.onSurface.withValues(alpha: 0.04);
