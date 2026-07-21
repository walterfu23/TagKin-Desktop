// D6 Cost & Usage Surface integration: GET /usage gate against a fake
// UsageRepository (mocked API per §5; no live network).
//   flutter test integration_test/usage_test.dart -d macos   (or -d windows)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/main.dart';

import '../test/fake_items_repository.dart';
import '../test/fake_jobs_repository.dart';
import '../test/fake_usage_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'kill-switch fixture disables Add from folder and shows pause reason',
      (WidgetTester tester) async {
    final usage = FakeUsageRepository(
      summary: fixtureUsageSummary(
        killSwitchEnabled: true,
        pauseReason: 'integration kill switch',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          testSessionProvider.overrideWithValue(
            const TestSession(
              token: 'integration-token',
              account: Account(
                id: 'acc_integration',
                email: 'integration@example.com',
                createdAt: '2026-07-18T00:00:00.000Z',
              ),
            ),
          ),
          itemsRepositoryProvider.overrideWithValue(FakeItemsRepository()),
          usageRepositoryProvider.overrideWithValue(usage),
          jobsRepositoryProvider.overrideWithValue(FakeJobsRepository()),
        ],
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('usage-banner-blocked')), findsOneWidget);
    expect(find.textContaining('integration kill switch'), findsOneWidget);

    final fab = tester.widget<FloatingActionButton>(
      find.byKey(const Key('add-from-folder')),
    );
    expect(fab.onPressed, isNull);
    expect(usage.getUsageCallCount, greaterThan(0));
  });
}
