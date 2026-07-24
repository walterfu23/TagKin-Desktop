import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_store.dart';

/// In-memory prefs + JSON persistence (ChangeNotifier for ListenableBuilder).
class DesktopPrefsController extends ChangeNotifier {
  DesktopPrefsController({DesktopPrefsStore? store})
      : _store = store ?? DesktopPrefsStore();

  final DesktopPrefsStore _store;
  DesktopPrefs _prefs = DesktopPrefs.defaults;
  bool _loaded = false;

  DesktopPrefs get prefs => _prefs;
  bool get loaded => _loaded;

  Future<void> load() async {
    _prefs = await _store.load();
    _loaded = true;
    notifyListeners();
  }

  Future<void> update(DesktopPrefs next) async {
    if (next == _prefs) return;
    _prefs = next;
    notifyListeners();
    await _store.save(next);
  }
}

final desktopPrefsControllerProvider =
    ChangeNotifierProvider<DesktopPrefsController>((ref) {
  final controller = DesktopPrefsController();
  // Fire-and-forget initial load; UI may briefly see defaults.
  controller.load();
  return controller;
});

/// Convenience: current prefs snapshot.
final desktopPrefsProvider = Provider<DesktopPrefs>((ref) {
  return ref.watch(desktopPrefsControllerProvider).prefs;
});

/// Whether multi-column library sort is enabled (Cliptorium-style).
final multiColumnSortProvider = Provider<bool>((ref) {
  return ref.watch(desktopPrefsProvider).multiColumnSort;
});
