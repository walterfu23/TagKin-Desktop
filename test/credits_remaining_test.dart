import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/usage/credits_remaining.dart';
import 'package:tagkin_desktop/usage/usage_controller.dart';

import 'fake_credits_repository.dart';
import 'fake_usage_repository.dart';

void main() {
  testWidgets('chip is hidden until load then shows the formatted count',
      (tester) async {
    final repo = FakeUsageRepository(
      summary: fixtureUsageSummary(remainingCredits: 1234),
    );
    final controller = UsageController(usageRepository: repo);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: CreditsRemainingChip(controller: controller),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('credits-remaining-chip')), findsNothing);

    await controller.load();
    await tester.pump();
    expect(find.byKey(const Key('credits-remaining-chip')), findsOneWidget);
    expect(find.text('1,234 credits'), findsOneWidget);

    repo.summary = fixtureUsageSummary(remainingCredits: 5000);
    await controller.load();
    await tester.pump();
    expect(find.text('5,000 credits'), findsOneWidget);
    expect(find.text('1,234 credits'), findsNothing);
  });

  testWidgets('chip stays hidden when /usage fails', (tester) async {
    final controller = UsageController(
      usageRepository: FakeUsageRepository(
        getUsageError: ApiException(statusCode: 500, message: 'boom'),
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: CreditsRemainingChip(controller: controller),
          ),
        ),
      ),
    );
    await controller.load();
    await tester.pump();
    expect(find.byKey(const Key('credits-remaining-chip')), findsNothing);
    expect(find.byKey(const Key('credits-remaining-chip-hidden')), findsOneWidget);
  });

  testWidgets('tile shows remaining and refresh reloads /usage', (tester) async {
    final repo = FakeUsageRepository(
      summary: fixtureUsageSummary(remainingCredits: 1234),
    );
    final credits = FakeCreditsRepository();
    final controller = UsageController(usageRepository: repo);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: CreditsRemainingTile(
              controller: controller,
              creditsRepository: credits,
            ),
          ),
        ),
      ),
    );
    await controller.load();
    await tester.pump();
    expect(find.byKey(const Key('settings-credits-remaining')), findsOneWidget);
    expect(find.text('1,234'), findsOneWidget);

    repo.summary = fixtureUsageSummary(remainingCredits: 900);
    await tester.tap(find.byKey(const Key('settings-credits-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('900'), findsOneWidget);
    expect(repo.getUsageCallCount, 2);
    expect(find.byKey(const Key('credits-lots-dialog')), findsNothing);
  });

  testWidgets('tile shows Could not load when /usage fails', (tester) async {
    final controller = UsageController(
      usageRepository: FakeUsageRepository(
        getUsageError: ApiException(statusCode: 500, message: 'boom'),
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: CreditsRemainingTile(controller: controller),
          ),
        ),
      ),
    );
    await controller.load();
    await tester.pump();
    expect(find.text('Could not load'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('sentence is hidden until load', (tester) async {
    final controller = UsageController(
      usageRepository: FakeUsageRepository(
        summary: fixtureUsageSummary(remainingCredits: 1234),
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: CreditsRemainingSentence(
              textKey: const Key('buy-credits-remaining'),
              controller: controller,
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('buy-credits-remaining')), findsNothing);

    await controller.load();
    await tester.pump();
    expect(
      find.text('You have 1,234 credits.'),
      findsOneWidget,
    );
    expect(
      find.text('Credits expire 7 days after you receive them.'),
      findsOneWidget,
    );
  });

  test('groups lots by local day, earliest first', () {
    final groups = groupCreditLotsByLocalDay(const [
      CreditLot(
        expiresAt: '2026-10-11T18:00:00.000Z',
        remainingCredits: 50,
      ),
      CreditLot(
        expiresAt: '2026-10-08T12:00:00.000Z',
        remainingCredits: 500,
      ),
      CreditLot(
        expiresAt: '2026-10-11T12:00:00.000Z',
        remainingCredits: 200,
      ),
    ]);
    expect(groups.map((g) => g.remainingCredits), [500, 250]);
    expect(
      groups.first.label,
      formatCreditExpiryDay(DateTime.parse('2026-10-08T12:00:00.000Z')),
    );
    expect(
      groups.last.label,
      formatCreditExpiryDay(DateTime.parse('2026-10-11T12:00:00.000Z')),
    );
  });

  testWidgets('chip tap lists expiration dates soonest first', (tester) async {
    final credits = FakeCreditsRepository(
      lots: const CreditLotList(
        creditExpiryDays: 7,
        lots: [
          CreditLot(
            expiresAt: '2026-10-11T12:00:00.000Z',
            remainingCredits: 200,
          ),
          CreditLot(
            expiresAt: '2026-10-08T12:00:00.000Z',
            remainingCredits: 500,
          ),
        ],
      ),
    );
    final controller = UsageController(
      usageRepository: FakeUsageRepository(
        summary: fixtureUsageSummary(remainingCredits: 700),
      ),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: CreditsRemainingChip(
              controller: controller,
              creditsRepository: credits,
            ),
          ),
        ),
      ),
    );
    await controller.load();
    await tester.pump();
    await tester.tap(find.byKey(const Key('credits-remaining-chip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('credits-lots-dialog')), findsOneWidget);
    expect(find.text('Credits expire'), findsWidgets);
    final soon = tester.getTopLeft(find.text('500 credits'));
    final later = tester.getTopLeft(find.text('200 credits'));
    expect(soon.dy, lessThan(later.dy));
    expect(credits.listLotsCount, 1);
  });

  testWidgets('chip turns amber when the next pack expires within 48 hours',
      (tester) async {
    final controller = UsageController(
      usageRepository: FakeUsageRepository(
        summary: fixtureUsageSummary(
          remainingCredits: 10,
          nextExpiresAt: DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String(),
        ),
      ),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: CreditsRemainingChip(controller: controller)),
        ),
      ),
    );
    await controller.load();
    await tester.pump();
    expect(find.byKey(const Key('credits-expire-soon')), findsOneWidget);
  });

  testWidgets('tile says credits expire', (tester) async {
    final controller = UsageController(
      usageRepository: FakeUsageRepository(
        summary: fixtureUsageSummary(remainingCredits: 1234),
      ),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: CreditsRemainingTile(controller: controller)),
        ),
      ),
    );
    await controller.load();
    await tester.pump();
    expect(find.textContaining('Credits expire 7 days'), findsOneWidget);
    expect(find.textContaining('do not expire'), findsNothing);
  });
}
