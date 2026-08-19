import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/usage/credits_remaining.dart';
import 'package:tagkin_desktop/usage/usage_controller.dart';

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
    final controller = UsageController(usageRepository: repo);
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
    expect(find.byKey(const Key('settings-credits-remaining')), findsOneWidget);
    expect(find.text('1,234'), findsOneWidget);

    repo.summary = fixtureUsageSummary(remainingCredits: 900);
    await tester.tap(find.byKey(const Key('settings-credits-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('900'), findsOneWidget);
    expect(repo.getUsageCallCount, 2);
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
  });
}
