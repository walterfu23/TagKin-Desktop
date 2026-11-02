import 'package:flutter/material.dart';
import 'package:tagkin_desktop/theme/theme_palettes.dart';

/// Theme picker. Each row is painted with that palette.
class ThemePaletteDropdown extends StatelessWidget {
  const ThemePaletteDropdown({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = isKnownTheme(value) ? value : kDefaultThemeId;
    final items = <DropdownMenuItem<String>>[];
    final selectedBuilders = <Widget>[];
    for (final group in kThemeGroups) {
      items.add(
        DropdownMenuItem(
          value: '__header_${group.label}__',
          enabled: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              group.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      );
      selectedBuilders.add(const SizedBox.shrink());
      for (final id in group.ids) {
        final palette = paletteFor(id);
        final swatch = _ThemeSwatch(palette: palette);
        items.add(DropdownMenuItem(value: id, child: swatch));
        selectedBuilders.add(swatch);
      }
    }
    return DropdownButton<String>(
      key: const Key('settings-theme'),
      isExpanded: true,
      value: selected,
      selectedItemBuilder: (context) => selectedBuilders,
      items: items,
      onChanged: (next) {
        if (next != null && !next.startsWith('__header_')) onChanged(next);
      },
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.palette});

  final ThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: palette.onBackground.withValues(alpha: 0.12)),
      ),
      child: Text(
        palette.label,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: palette.onBackground,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
