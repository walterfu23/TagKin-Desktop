import 'package:tagkin_desktop/api/usage_repository.dart';
import 'package:tagkin_desktop/contract/contract.dart';

/// In-memory [UsageRepository] for widget/integration tests (no network).
class FakeUsageRepository implements UsageRepository {
  FakeUsageRepository({
    UsageSummary? summary,
    this.getUsageError,
  }) : summary = summary ?? fixtureUsageSummary();

  UsageSummary summary;
  final Object? getUsageError;

  int getUsageCallCount = 0;

  @override
  Future<UsageSummary> getUsage() async {
    getUsageCallCount++;
    if (getUsageError != null) throw getUsageError!;
    return summary;
  }
}

/// Fixture [UsageSummary] for tests. Defaults to an open (unpaused) budget.
UsageSummary fixtureUsageSummary({
  int softLimitCents = 1000,
  int hardLimitCents = 2000,
  int reservedCents = 0,
  int spentCents = 0,
  bool killSwitchEnabled = false,
  String? killSwitchReason,
  bool? softLimitExceeded,
  String? pauseReason,
  int remainingCredits = 0,
  int reservedCredits = 0,
  int lowCreditWarningCredits = 500,
  bool lowCreditWarning = false,
  bool creditAdmission = false,
}) {
  return UsageSummary(
    softLimitCents: softLimitCents,
    hardLimitCents: hardLimitCents,
    reservedCents: reservedCents,
    spentCents: spentCents,
    killSwitch: KillSwitchState(
      enabled: killSwitchEnabled,
      reason: killSwitchReason,
    ),
    softLimitExceeded: softLimitExceeded,
    pauseReason: pauseReason,
    remainingCredits: remainingCredits,
    reservedCredits: reservedCredits,
    lowCreditWarningCredits: lowCreditWarningCredits,
    lowCreditWarning: lowCreditWarning,
    creditAdmission: creditAdmission,
  );
}
