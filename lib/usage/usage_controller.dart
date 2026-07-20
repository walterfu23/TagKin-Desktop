import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/usage_repository.dart';
import 'package:tagkin_desktop/app_shell.dart' show usageRepositoryProvider;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/usage/usage_gate.dart';

/// Lifecycle phase of a usage fetch (D6).
enum UsagePhase { idle, loading, loaded, error }

/// Loads `GET /usage` once (on-demand) and exposes [UsageGate] for ingest UI.
///
/// Does not auto-retry on error (matches D1 [ApiClient] no-silent-retry).
/// Does not poll — refresh by calling [load] again (e.g. on page re-entry).
///
/// `/analyze`-time reject/queue reason display is owned by D7; this
/// controller only covers the pre-ingest kill-switch / hard-limit gate.
class UsageController extends ChangeNotifier {
  UsageController({required this.usageRepository});

  final UsageRepository usageRepository;

  UsagePhase phase = UsagePhase.idle;
  UsageSummary? summary;
  UsageGate gate = UsageGate.open;
  Object? error;

  /// Fetches usage. On failure sets [phase] to [UsagePhase.error] and leaves
  /// [gate] at [UsageGate.open] (fail-open for display; server still
  /// authorizes paid work). Never silently retries.
  Future<void> load() async {
    phase = UsagePhase.loading;
    error = null;
    notifyListeners();

    try {
      final loaded = await usageRepository.getUsage();
      summary = loaded;
      gate = UsageGate.fromSummary(loaded);
      phase = UsagePhase.loaded;
    } catch (e) {
      error = e;
      phase = UsagePhase.error;
      // Fail-open: do not invent a blocked state from a fetch failure.
      gate = UsageGate.open;
      summary = null;
    }
    notifyListeners();
  }
}

final usageControllerProvider = Provider.autoDispose<UsageController>(
  (ref) {
    final controller = UsageController(
      usageRepository: ref.watch(usageRepositoryProvider),
    );
    ref.onDispose(controller.dispose);
    return controller;
  },
  dependencies: [usageRepositoryProvider],
);
