// D8 Review UI integration: approved knowledge + key-period scrub against
// mocked API (§5). Local media is intentionally missing so media_kit is not
// required for the smoke path.
//   flutter test integration_test/review_test.dart -d macos
//   flutter test integration_test/review_test.dart -d windows

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/main.dart';

import '../test/fake_comments_repository.dart';
import '../test/fake_corrections_repository.dart';
import '../test/fake_items_repository.dart';
import '../test/fake_jobs_repository.dart';
import '../test/fake_usage_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('item detail review renders knowledge + key periods',
      (WidgetTester tester) async {
    final item = fixtureItem(
      id: 'item_review',
      type: ItemType.video,
      processingStatus: ProcessingStatus.tagged,
    );
    final knowledge = fixtureKnowledge(
      item: item,
      tags: [
        fixtureTag(id: 'w1', dimension: 'who', value: 'Alex'),
        fixtureTag(id: 'w2', dimension: 'what', value: 'birthday'),
      ],
      keyPeriods: [
        KeyPeriodKnowledge(
          id: 'kp_int',
          itemId: 'item_review',
          startMs: 0,
          endMs: 3000,
          tags: [
            fixtureTag(
              id: 'kp_t',
              dimension: 'what',
              value: 'candles',
              keyPeriodId: 'kp_int',
            ),
          ],
        ),
      ],
    );
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {'item_review': knowledge},
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
          itemsRepositoryProvider.overrideWithValue(items),
          correctionsRepositoryProvider.overrideWithValue(
            FakeCorrectionsRepository(items: items),
          ),
          commentsRepositoryProvider.overrideWithValue(
            FakeCommentsRepository(),
          ),
          usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
          jobsRepositoryProvider.overrideWithValue(
            FakeJobsRepository(itemId: 'item_review', item: item),
          ),
        ],
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('item-row-item_review')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('item-review')), findsOneWidget);
    expect(find.byKey(const Key('knowledge-view')), findsOneWidget);
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('birthday'), findsOneWidget);
    expect(find.byKey(const Key('key-period-scrubber')), findsOneWidget);
    expect(find.byKey(const Key('key-period-kp_int')), findsOneWidget);
    expect(find.textContaining('candles'), findsOneWidget);
    expect(find.byKey(const Key('media-status-missing')), findsOneWidget);
  });
}
