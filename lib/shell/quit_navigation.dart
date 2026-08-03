import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

/// Bumped by macOS Quit TagKin / Cmd+Q when a dirty collection needs confirm.
final quitAppTickProvider = StateProvider<int>((ref) => 0);

/// Request dirty-aware quit from the signed-in scaffold (platform menu).
void requestQuitApp(WidgetRef ref) {
  ref.read(quitAppTickProvider.notifier).state++;
}

/// Tear down the desktop window immediately (no leave prompt).
Future<void> quitDesktopAppNow() async {
  if (kIsWeb) return;
  try {
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  } catch (_) {
    try {
      await windowManager.destroy();
    } catch (_) {}
  }
}

/// Quit from the platform menu: dirty open collection → scaffold prompt;
/// otherwise destroy immediately (also covers signed-out).
void requestQuitAppOrExitNow(
  WidgetRef ref, {
  required bool needsDirtyConfirm,
}) {
  if (needsDirtyConfirm) {
    requestQuitApp(ref);
    return;
  }
  unawaited(quitDesktopAppNow());
}
