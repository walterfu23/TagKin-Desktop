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
/// Analyze-time credit rejects (`insufficientCredits` / `outOfCredits` /
/// `paidPaused`) are recorded via [noteAnalyzeReject] so [UsageBanner] can
/// show the server verdict. [load] does not clear that reject.
class UsageController extends ChangeNotifier {
  UsageController({required this.usageRepository});

  final UsageRepository usageRepository;

  UsagePhase phase = UsagePhase.idle;
  UsageSummary? summary;
  UsageGate gate = UsageGate.open;
  Object? error;

  /// Last credit-admission 409 from analyze. Null when none is pending.
  String? analyzeRejectCode;
  String? analyzeRejectMessage;

  /// Fetches usage. On failure sets [phase] to [UsagePhase.error] and leaves
  /// [gate] at [UsageGate.open] (fail-open for display; server still
  /// authorizes paid work). Never silently retries. Does not clear a stored
  /// analyze reject.
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

  /// Record a server credit reject and refresh `/usage` so the meter follows.
  /// Non-credit codes are ignored.
  void noteAnalyzeReject(String? code, String message) {
    if (!isCreditRejectCode(code)) return;
    analyzeRejectCode = code;
    analyzeRejectMessage = message;
    notifyListeners();
    load();
  }

  /// Drop a stored analyze reject (new ingest / retry session).
  void clearAnalyzeReject() {
    if (analyzeRejectCode == null && analyzeRejectMessage == null) return;
    analyzeRejectCode = null;
    analyzeRejectMessage = null;
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
