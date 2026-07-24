import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/prefs/settings_page.dart';

/// Bumped by the macOS menu / Cmd+, to open Settings when signed in.
final openSettingsTickProvider = StateProvider<int>((ref) => 0);

/// Request Settings from outside the signed-in scaffold (e.g. platform menu).
void requestOpenSettings(WidgetRef ref) {
  ref.read(openSettingsTickProvider.notifier).state++;
}

/// Push [SettingsPage] on the nearest navigator, preserving [ProviderScope].
Future<void> pushSettingsPage(BuildContext context) async {
  final container = ProviderScope.containerOf(context);
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'settings'),
      builder: (_) => UncontrolledProviderScope(
        container: container,
        child: const SettingsPage(),
      ),
    ),
  );
}
