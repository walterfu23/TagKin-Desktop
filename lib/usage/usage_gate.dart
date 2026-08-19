import 'package:tagkin_desktop/contract/contract.dart';

/// Which copy [UsageBanner] should prefer from [UsageSummary] alone.
enum UsageNotice {
  none,
  budgetBlocked,
  lowCredits,
  outOfCredits,
}

/// Server 409 codes that mean a paid-analyze credit reject (S5 Phase 3).
bool isCreditRejectCode(String? code) =>
    code == 'insufficientCredits' ||
    code == 'outOfCredits' ||
    code == 'paidPaused';

/// Credit rejects that must stop further analyze attempts in a batch.
bool isHardCreditStop(String? code) =>
    code == 'outOfCredits' || code == 'paidPaused';

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
    this.creditAdmission = true,
    this.remainingCredits = 0,
    this.notice = UsageNotice.none,
  });

  /// Kill-switch on, out of credits, or a paid pause.
  final bool blocked;

  /// Low-credit warning while still allowed to ingest.
  final bool warn;

  /// Server `pauseReason` or kill-switch reason when [blocked]; else null.
  final String? reasonText;

  /// True when this account reserves in credits (always, after Phase 6).
  final bool creditAdmission;

  /// Spendable credits already net of open holds. Do not subtract again.
  final int remainingCredits;

  /// /usage-derived notice. Analyze 409 copy is layered on by [UsageBanner].
  final UsageNotice notice;

  /// Open / unpaused gate (default before the first successful load).
  static const UsageGate open = UsageGate(blocked: false, warn: false);

  /// Derive gate state from a [UsageSummary]. Values come only from the
  /// fixture/API response — no local cost model.
  factory UsageGate.fromSummary(UsageSummary summary) {
    final remaining = summary.remainingCredits;
    final kill = summary.killSwitch.enabled;
    final paused =
        summary.pauseReason != null && summary.pauseReason!.isNotEmpty;
    final blocked = kill || remaining == 0 || paused;
    final warn = summary.lowCreditWarning && !blocked;

    final UsageNotice notice;
    if (kill || (paused && remaining > 0)) {
      notice = UsageNotice.budgetBlocked;
    } else if (remaining == 0) {
      notice = UsageNotice.outOfCredits;
    } else if (warn) {
      notice = UsageNotice.lowCredits;
    } else {
      notice = UsageNotice.none;
    }

    String? reasonText;
    if (blocked) {
      reasonText = summary.pauseReason ?? summary.killSwitch.reason;
    }

    return UsageGate(
      blocked: blocked,
      warn: warn,
      reasonText: reasonText,
      creditAdmission: true,
      remainingCredits: remaining,
      notice: notice,
    );
  }
}
