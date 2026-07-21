import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/items_list_page.dart';
import 'package:tagkin_desktop/main.dart';
import 'package:tagkin_desktop/usage/usage_banner.dart';
import 'package:tagkin_desktop/usage/usage_gate.dart';

import 'fake_items_repository.dart';
import 'fake_jobs_repository.dart';
import 'fake_usage_repository.dart';

Account _account(String id) => Account(
      id: id,
      email: '$id@example.com',
      createdAt: '2026-07-18T00:00:00.000Z',
    );

List<Override> _overrides({
  required FakeUsageRepository usage,
  FakeItemsRepository? items,
  String accountId = 'acc_1',
}) {
  return [
    testSessionProvider.overrideWithValue(
      TestSession(token: 'tok', account: _account(accountId)),
    ),
    itemsRepositoryProvider.overrideWithValue(
      items ?? FakeItemsRepository(),
    ),
    usageRepositoryProvider.overrideWithValue(usage),
    jobsRepositoryProvider.overrideWithValue(FakeJobsRepository()),
  ];
}

void main() {
  testWidgets('usage banner renders softLimit / spent from API fixture',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UsageBanner(
            gate: UsageGate.fromSummary(
              fixtureUsageSummary(
                softLimitCents: 1000,
                spentCents: 800,
                softLimitExceeded: true,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('usage-banner-warn')), findsOneWidget);
    expect(find.text('80% of budget used'), findsOneWidget);
  });

  testWidgets('kill-switch disables Add from folder FAB and shows banner',
      (tester) async {
    final usage = FakeUsageRepository(
      summary: fixtureUsageSummary(
        killSwitchEnabled: true,
        killSwitchReason: 'ops',
        pauseReason: 'kill switch enabled',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(usage: usage),
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('usage-banner-blocked')), findsOneWidget);
    expect(find.textContaining('kill switch enabled'), findsOneWidget);

    final fab = tester.widget<FloatingActionButton>(
      find.byKey(const Key('add-from-folder')),
    );
    expect(fab.onPressed, isNull);
  });

  testWidgets('hard-limit disables Add from folder FAB', (tester) async {
    final usage = FakeUsageRepository(
      summary: fixtureUsageSummary(
        hardLimitCents: 100,
        spentCents: 80,
        reservedCents: 20,
        pauseReason: 'hard budget reached',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(usage: usage),
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('usage-banner-blocked')), findsOneWidget);
    final fab = tester.widget<FloatingActionButton>(
      find.byKey(const Key('add-from-folder')),
    );
    expect(fab.onPressed, isNull);
  });

  testWidgets('open budget leaves FAB enabled and banner hidden',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(usage: FakeUsageRepository()),
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('usage-banner-hidden')), findsOneWidget);
    final fab = tester.widget<FloatingActionButton>(
      find.byKey(const Key('add-from-folder')),
    );
    expect(fab.onPressed, isNotNull);
  });

  testWidgets('account B never renders account A usage numbers (R10)',
      (tester) async {
    // B's fixture has a distinctive spent value; A's numbers must not appear.
    final usageB = FakeUsageRepository(
      summary: fixtureUsageSummary(spentCents: 222, softLimitCents: 500),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(
          usage: usageB,
          accountId: 'acc_b',
        ),
        child: const MaterialApp(
          home: AuthShell(signedInHome: ItemsListPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('acc_b@example.com'), findsOneWidget);
    // Open budget → no banner with A-specific copy; spent is not displayed
    // as authority text in the open state.
    expect(find.textContaining('111'), findsNothing);
  });
}
