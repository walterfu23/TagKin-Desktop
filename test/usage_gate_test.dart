import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/usage/usage_controller.dart';
import 'package:tagkin_desktop/usage/usage_gate.dart';

import 'fake_usage_repository.dart';

void main() {
  group('UsageGate.fromSummary', () {
    test('open when remaining is above the warning threshold', () {
      final gate = UsageGate.fromSummary(fixtureUsageSummary());
      expect(gate.blocked, isFalse);
      expect(gate.warn, isFalse);
      expect(gate.reasonText, isNull);
      expect(gate.notice, UsageNotice.none);
    });

    test('low remaining warns and does not block', () {
      final gate = UsageGate.fromSummary(
        fixtureUsageSummary(
          remainingCredits: 400,
          lowCreditWarning: true,
        ),
      );
      expect(gate.blocked, isFalse);
      expect(gate.warn, isTrue);
      expect(gate.notice, UsageNotice.lowCredits);
      expect(gate.remainingCredits, 400);
    });

    test('blocked by kill switch; surfaces reason verbatim', () {
      final gate = UsageGate.fromSummary(
        fixtureUsageSummary(
          remainingCredits: 10000,
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
          remainingCredits: 10000,
          killSwitchEnabled: true,
          killSwitchReason: 'ops pause',
        ),
      );
      expect(gate.blocked, isTrue);
      expect(gate.reasonText, 'ops pause');
    });

    test('zero remaining is out of credits', () {
      final gate = UsageGate.fromSummary(
        fixtureUsageSummary(remainingCredits: 0),
      );
      expect(gate.blocked, isTrue);
      expect(gate.warn, isFalse);
      expect(gate.notice, UsageNotice.outOfCredits);
    });

    test('paid pause blocks while remaining is positive', () {
      final gate = UsageGate.fromSummary(
        fixtureUsageSummary(
          remainingCredits: 80,
          pauseReason: 'Estimate overrun absorbed',
        ),
      );
      expect(gate.blocked, isTrue);
      expect(gate.notice, UsageNotice.budgetBlocked);
      expect(gate.reasonText, 'Estimate overrun absorbed');
    });

    test('derives only from fixture fields — no local cost model', () {
      final gate = UsageGate.fromSummary(
        fixtureUsageSummary(
          remainingCredits: 400,
          lowCreditWarning: true,
        ),
      );
      expect(gate.blocked, isFalse);
      expect(gate.warn, isTrue);
      expect(gate.notice, UsageNotice.lowCredits);
    });
  });

  group('UsageController', () {
    test('load populates summary and gate from repository', () async {
      final repo = FakeUsageRepository(
        summary: fixtureUsageSummary(
          remainingCredits: 400,
          lowCreditWarning: true,
        ),
      );
      final controller = UsageController(usageRepository: repo);
      await controller.load();
      expect(controller.phase, UsagePhase.loaded);
      expect(controller.summary!.remainingCredits, 400);
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
        summary: fixtureUsageSummary(remainingCredits: 40),
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

    test('remainingCredits is null until a successful load', () async {
      final repo = FakeUsageRepository(
        summary: fixtureUsageSummary(remainingCredits: 1234),
      );
      final controller = UsageController(usageRepository: repo);
      expect(controller.remainingCredits, isNull);
      await controller.load();
      expect(controller.remainingCredits, 1234);
      controller.dispose();
    });

    test('remainingCredits stays null when load fails', () async {
      final repo = FakeUsageRepository(
        getUsageError: ApiException(statusCode: 500, message: 'boom'),
      );
      final controller = UsageController(usageRepository: repo);
      await controller.load();
      expect(controller.remainingCredits, isNull);
      expect(controller.phase, UsagePhase.error);
      controller.dispose();
    });

    test('ensureLoaded fetches once then no-ops', () async {
      final repo = FakeUsageRepository();
      final controller = UsageController(usageRepository: repo);
      await controller.ensureLoaded();
      await controller.ensureLoaded();
      expect(repo.getUsageCallCount, 1);
      expect(controller.phase, UsagePhase.loaded);
      controller.dispose();
    });

    test('ensureLoaded retries after a failed load', () async {
      final repo = FakeUsageRepository(
        getUsageError: ApiException(statusCode: 500, message: 'boom'),
      );
      final controller = UsageController(usageRepository: repo);
      await controller.ensureLoaded();
      expect(controller.phase, UsagePhase.error);
      repo.getUsageError = null;
      await controller.ensureLoaded();
      expect(controller.phase, UsagePhase.loaded);
      expect(repo.getUsageCallCount, 2);
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
