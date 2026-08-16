import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/usage/usage_controller.dart';
import 'package:tagkin_desktop/usage/usage_gate.dart';

import 'fake_usage_repository.dart';

void main() {
  group('UsageGate.fromSummary', () {
    test('open when under soft and hard limits', () {
      final gate = UsageGate.fromSummary(fixtureUsageSummary());
      expect(gate.blocked, isFalse);
      expect(gate.warn, isFalse);
      expect(gate.reasonText, isNull);
    });

    test('warn when softLimitExceeded and not blocked', () {
      final gate = UsageGate.fromSummary(
        fixtureUsageSummary(softLimitExceeded: true, spentCents: 800),
      );
      expect(gate.blocked, isFalse);
      expect(gate.warn, isTrue);
    });

    test('blocked by kill switch; surfaces reason verbatim', () {
      final gate = UsageGate.fromSummary(
        fixtureUsageSummary(
          killSwitchEnabled: true,
          killSwitchReason: 'maintenance',
          pauseReason: 'kill switch on',
        ),
      );
      expect(gate.blocked, isTrue);
      expect(gate.warn, isFalse);
      expect(gate.reasonText, 'kill switch on');
    });

    test('blocked by kill switch falls back to killSwitch.reason', () {
      final gate = UsageGate.fromSummary(
        fixtureUsageSummary(
          killSwitchEnabled: true,
          killSwitchReason: 'ops pause',
        ),
      );
      expect(gate.blocked, isTrue);
      expect(gate.reasonText, 'ops pause');
    });

    test('blocked when spent+reserved >= hardLimitCents', () {
      final gate = UsageGate.fromSummary(
        fixtureUsageSummary(
          hardLimitCents: 1000,
          spentCents: 600,
          reservedCents: 400,
          pauseReason: 'hard budget',
        ),
      );
      expect(gate.blocked, isTrue);
      expect(gate.reasonText, 'hard budget');
    });

    test('creditAdmission: low remaining warns and does not block', () {
      final gate = UsageGate.fromSummary(
        fixtureUsageSummary(
          creditAdmission: true,
          remainingCredits: 400,
          lowCreditWarning: true,
        ),
      );
      expect(gate.blocked, isFalse);
      expect(gate.warn, isTrue);
      expect(gate.notice, UsageNotice.lowCredits);
      expect(gate.remainingCredits, 400);
    });

    test('creditAdmission: zero remaining is out of credits', () {
      final gate = UsageGate.fromSummary(
        fixtureUsageSummary(
          creditAdmission: true,
          remainingCredits: 0,
        ),
      );
      expect(gate.blocked, isTrue);
      expect(gate.warn, isFalse);
      expect(gate.notice, UsageNotice.outOfCredits);
    });

    test('creditAdmission: paid pause blocks while remaining is positive', () {
      final gate = UsageGate.fromSummary(
        fixtureUsageSummary(
          creditAdmission: true,
          remainingCredits: 80,
          pauseReason: 'Estimate overrun absorbed',
        ),
      );
      expect(gate.blocked, isTrue);
      expect(gate.notice, UsageNotice.budgetBlocked);
      expect(gate.reasonText, 'Estimate overrun absorbed');
    });

    test('creditAdmission false still derives from cents', () {
      final gate = UsageGate.fromSummary(
        fixtureUsageSummary(
          creditAdmission: false,
          remainingCredits: 0,
          softLimitExceeded: true,
          spentCents: 800,
        ),
      );
      expect(gate.blocked, isFalse);
      expect(gate.warn, isTrue);
      expect(gate.notice, UsageNotice.budgetWarn);
    });

    test('derives only from fixture fields — no local cost model', () {
      // Unusual limits still produce gate output driven solely by the fixture.
      final gate = UsageGate.fromSummary(
        fixtureUsageSummary(
          softLimitCents: 99999,
          hardLimitCents: 1,
          spentCents: 0,
          reservedCents: 0,
          softLimitExceeded: true,
        ),
      );
      // softLimitExceeded is true but atOrAboveHard is false (0 < 1) and
      // kill switch off → warn only.
      expect(gate.blocked, isFalse);
      expect(gate.warn, isTrue);
    });
  });

  group('UsageController', () {
    test('load populates summary and gate from repository', () async {
      final repo = FakeUsageRepository(
        summary: fixtureUsageSummary(
          spentCents: 50,
          softLimitExceeded: true,
        ),
      );
      final controller = UsageController(usageRepository: repo);
      await controller.load();
      expect(controller.phase, UsagePhase.loaded);
      expect(controller.summary!.spentCents, 50);
      expect(controller.gate.warn, isTrue);
      expect(repo.getUsageCallCount, 1);
      controller.dispose();
    });

    test('load does not auto-retry on error', () async {
      final repo = FakeUsageRepository(
        getUsageError: ApiException(statusCode: 500, message: 'boom'),
      );
      final controller = UsageController(usageRepository: repo);
      await controller.load();
      expect(controller.phase, UsagePhase.error);
      expect(controller.error, isA<ApiException>());
      expect(controller.gate, UsageGate.open);
      expect(repo.getUsageCallCount, 1);
      controller.dispose();
    });

    test('noteAnalyzeReject stores credit codes and refreshes usage', () async {
      final repo = FakeUsageRepository(
        summary: fixtureUsageSummary(
          creditAdmission: true,
          remainingCredits: 40,
        ),
      );
      final controller = UsageController(usageRepository: repo);
      await controller.load();
      expect(repo.getUsageCallCount, 1);
      controller.noteAnalyzeReject(
        'insufficientCredits',
        'Not enough credits for this analysis',
      );
      expect(controller.analyzeRejectCode, 'insufficientCredits');
      await Future<void>.delayed(Duration.zero);
      expect(repo.getUsageCallCount, 2);
      controller.load();
      await Future<void>.delayed(Duration.zero);
      expect(controller.analyzeRejectCode, 'insufficientCredits');
      controller.clearAnalyzeReject();
      expect(controller.analyzeRejectCode, isNull);
      controller.dispose();
    });

    test('noteAnalyzeReject ignores non-credit codes', () async {
      final repo = FakeUsageRepository();
      final controller = UsageController(usageRepository: repo);
      controller.noteAnalyzeReject('hard_limit', 'budget');
      expect(controller.analyzeRejectCode, isNull);
      expect(repo.getUsageCallCount, 0);
      controller.dispose();
    });
  });
}
