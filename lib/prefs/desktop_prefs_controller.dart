import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_store.dart';
import 'package:tagkin_desktop/prepass/onnx_face_embedder.dart';
import 'package:tagkin_desktop/where/where_place_label.dart';

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
    applyDesktopPrefsRuntime(_prefs);
    _loaded = true;
    notifyListeners();
  }

  Future<void> update(DesktopPrefs next) async {
    if (next == _prefs) return;
    _prefs = next;
    applyDesktopPrefsRuntime(next);
    notifyListeners();
    await _store.save(next);
  }

  Future<void> restoreDefaults() async {
    await update(DesktopPrefs.defaults);
  }

  /// Appends [region] to familiar regions if not already listed.
  /// Returns true when prefs changed.
  Future<bool> addFamiliarRegion(String region) async {
    final trimmed = region.trim();
    if (!isValidFamiliarRegionToken(trimmed)) return false;
    final next = normalizeFamiliarRegionsCsv(
      encodeFamiliarRegions([
        ...parseFamiliarRegions(_prefs.familiarRegions),
        trimmed,
      ]),
    );
    if (next == _prefs.familiarRegions) return false;
    await update(_prefs.copyWith(familiarRegions: next));
    return true;
  }
}

/// Syncs prefs that non-Riverpod code reads (e.g. ONNX detect threshold).
void applyDesktopPrefsRuntime(DesktopPrefs prefs) {
  OnnxFaceEmbedder.defaultDetectScoreThreshold =
      prefs.facesDetectScoreThreshold;
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
