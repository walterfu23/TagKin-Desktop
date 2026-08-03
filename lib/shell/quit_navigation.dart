import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

/// Bumped by macOS Quit TagKin / Cmd+Q; signed-in scaffold runs leave + quit.
final quitAppTickProvider = StateProvider<int>((ref) => 0);

/// True while the signed-in scaffold owns window-close / Quit (gate armed).
///
/// Module-level (not a Riverpod provider) so the scaffold can clear it in
/// [State.dispose] without touching `ref` after dispose.
bool signedInQuitHandlerReady = false;

/// Request dirty-aware quit from the signed-in scaffold (platform menu).
void requestQuitApp(WidgetRef ref) {
  ref.read(quitAppTickProvider.notifier).state++;
}

/// Tear down the desktop window immediately (no leave prompt).
///
/// Only safe when the signed-in close gate is not armed; otherwise
/// [WidgetsBindingObserver.didRequestAppExit] cancels terminate.
/// Prefer [requestQuitAppOrExitNow].
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

/// Quit from the platform menu: signed-in scaffold owns gate + leave prompt;
/// otherwise destroy immediately (signed-out / gate never armed).
void requestQuitAppOrExitNow(WidgetRef ref) {
  if (signedInQuitHandlerReady) {
    requestQuitApp(ref);
    return;
  }
  unawaited(quitDesktopAppNow());
}
