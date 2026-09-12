import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';

/// Shared "Hide blurry" toggle — appears wherever photos are shown (Folders,
/// Export list). One persisted setting: flip it anywhere and it applies
/// everywhere ([DesktopPrefs.hideBlurryPhotos]).
class HideBlurrySwitch extends ConsumerWidget {
  const HideBlurrySwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(desktopPrefsProvider).hideBlurryPhotos;
    return Tooltip(
      message: 'Hide photos below the Settings blurry bar '
          '(current still, after auto-fix when it ran).',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            key: const Key('hide-blurry-switch'),
            value: on,
            onChanged: (value) {
              unawaited(
                ref.read(desktopPrefsControllerProvider).setHideBlurryPhotos(
                      value,
                    ),
              );
            },
          ),
          const Text('Hide blurry'),
        ],
      ),
    );
  }
}
