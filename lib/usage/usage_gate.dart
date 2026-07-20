import 'package:tagkin_desktop/contract/contract.dart';

/// Client-side ingest gate derived solely from a server [UsageSummary].
///
/// Never computes cost authority locally (R9) — only derives warn/blocked
/// from fields the API already returned. Server-side reserve-before-spend
/// remains authoritative on paid paths (`/analyze`); this gate only disables
/// new ingest UI before those paths are reached.
class UsageGate {
  const UsageGate({
    required this.blocked,
    required this.warn,
    this.reasonText,
  });

  /// Kill-switch on, or spent+reserved at/above the hard limit.
  final bool blocked;

  /// Soft limit exceeded while still below hard limit / kill-switch.
  final bool warn;

  /// Server `pauseReason` or kill-switch reason when [blocked]; else null.
  final String? reasonText;

  /// Open / unpaused gate (default before the first successful load).
  static const UsageGate open = UsageGate(blocked: false, warn: false);

  /// Derive gate state from a [UsageSummary]. Values come only from the
  /// fixture/API response — no local cost model.
  factory UsageGate.fromSummary(UsageSummary summary) {
    final atOrAboveHard =
        (summary.spentCents + summary.reservedCents) >= summary.hardLimitCents;
    final blocked = summary.killSwitch.enabled || atOrAboveHard;
    final softExceeded = summary.softLimitExceeded ?? false;
    final warn = softExceeded && !blocked;

    String? reasonText;
    if (blocked) {
      reasonText = summary.pauseReason ?? summary.killSwitch.reason;
    }

    return UsageGate(
      blocked: blocked,
      warn: warn,
      reasonText: reasonText,
    );
  }
}
