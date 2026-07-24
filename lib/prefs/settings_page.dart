import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';
import 'package:tagkin_desktop/where/where_label_resolver.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

/// Desktop display preferences (where labels + multi-column sort).
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late bool _showCountryWhenSameCountry;
  late bool _showStateWhenSameState;
  late bool _multiColumnSort;
  late TextEditingController _homeState;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(desktopPrefsProvider);
    _showCountryWhenSameCountry = prefs.showCountryWhenSameCountry;
    _showStateWhenSameState = prefs.showStateWhenSameState;
    _multiColumnSort = prefs.multiColumnSort;
    _homeState = TextEditingController(text: prefs.homeState);
  }

  @override
  void dispose() {
    _homeState.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final previous = ref.read(desktopPrefsProvider);
    final next = DesktopPrefs(
      showCountryWhenSameCountry: _showCountryWhenSameCountry,
      showStateWhenSameState: _showStateWhenSameState,
      multiColumnSort: _multiColumnSort,
      homeState: _homeState.text.trim(),
    );
    await ref.read(desktopPrefsControllerProvider).update(next);

    if (previous.multiColumnSort && !next.multiColumnSort) {
      ref.read(libraryTableControllerProvider).enforceSingleColumn();
    }

    final whereChanged =
        previous.showCountryWhenSameCountry !=
            next.showCountryWhenSameCountry ||
        previous.showStateWhenSameState != next.showStateWhenSameState ||
        previous.homeState != next.homeState;
    if (whereChanged) {
      ref.read(whereLabelResolverProvider).clearCache();
      await ref.read(libraryTableControllerProvider).refreshWhereLabels();
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SelectableScope(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          actions: [
            TextButton(
              key: const Key('settings-save'),
              onPressed: _save,
              child: const Text('Save'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Where labels',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const Key('pref-show-country-same'),
              title: const Text('Show country when in the same country'),
              subtitle: const Text(
                'Off (default): omit country when the photo matches '
                'this computer’s country.',
              ),
              value: _showCountryWhenSameCountry,
              onChanged: (v) =>
                  setState(() => _showCountryWhenSameCountry = v),
            ),
            SwitchListTile(
              key: const Key('pref-show-state-same'),
              title: const Text('Show state/province when in the same state'),
              subtitle: const Text(
                'Off (default): omit state when it matches Home state below.',
              ),
              value: _showStateWhenSameState,
              onChanged: (v) => setState(() => _showStateWhenSameState = v),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                key: const Key('pref-home-state'),
                controller: _homeState,
                decoration: const InputDecoration(
                  labelText: 'Home state / province',
                  hintText: 'e.g. CA or California',
                  helperText:
                      'Used to decide “same state”. Leave blank to always show state.',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Library table',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const Key('pref-multi-column-sort'),
              title: const Text('Multi-column sort'),
              subtitle: const Text(
                'Off (default): one sort column. On: click columns to build '
                'a priority stack (1, 2, …).',
              ),
              value: _multiColumnSort,
              onChanged: (v) => setState(() => _multiColumnSort = v),
            ),
          ],
        ),
      ),
    );
  }
}
