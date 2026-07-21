// D10 Knowledge Corrections & Comments UI integration: tag add/undo +
// comment create against mocked API (§5).
//   flutter test integration_test/knowledge_corrections_test.dart -d macos
//   flutter test integration_test/knowledge_corrections_test.dart -d windows

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/main.dart';

import '../test/fake_comments_repository.dart';
import '../test/fake_corrections_repository.dart';
import '../test/fake_items_repository.dart';
import '../test/fake_jobs_repository.dart';
import '../test/fake_persons_repository.dart';
import '../test/fake_usage_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'corrections: add tag → undo; comment author from server; foreign 404',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final item = fixtureItem(
      id: 'item_c',
      processingStatus: ProcessingStatus.tagged,
    );
    final knowledge = fixtureKnowledge(
      item: item,
      tags: [
        fixtureTag(id: 'tag_what', dimension: 'what', value: 'picnic'),
      ],
      corrections: [
        fixtureCorrection(
          id: 'corr_seed',
          previousValue: 'walk',
          newValue: 'picnic',
        ),
      ],
    );
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {'item_c': knowledge},
    );
    final corrections = FakeCorrectionsRepository(items: items);
    final comments = FakeCommentsRepository(authorUserId: 'acc_integration');

    // Account B cannot see account A's knowledge (R10).
    final foreignItems = FakeItemsRepository(
      getKnowledgeError: ApiException(
        statusCode: 404,
        message: 'Not found',
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
          itemsRepositoryProvider.overrideWithValue(items),
          correctionsRepositoryProvider.overrideWithValue(corrections),
          commentsRepositoryProvider.overrideWithValue(comments),
          usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
          jobsRepositoryProvider.overrideWithValue(
            FakeJobsRepository(itemId: 'item_c', item: item),
          ),
          personsRepositoryProvider.overrideWithValue(
            FakePersonsRepository(),
          ),
        ],
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Open item detail from the library list.
    await tester.tap(find.byKey(const Key('item-row-item_c')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('item-review')), findsOneWidget);
    expect(find.byKey(const Key('knowledge-view')), findsOneWidget);
    expect(find.text('picnic'), findsOneWidget);

    // Undo the seeded correction (visible history path).
    await tester.ensureVisible(
      find.byKey(const Key('correction-undo-corr_seed')),
    );
    await tester.tap(find.byKey(const Key('correction-undo-corr_seed')));
    await tester.pumpAndSettle();
    expect(corrections.undoCalls, contains('corr_seed'));

    // Add a where tag.
    await tester.ensureVisible(find.byKey(const Key('tag-add-where')));
    await tester.tap(find.byKey(const Key('tag-add-where')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tag-edit-dialog')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('tag-value-field')), 'park');
    await tester.tap(find.byKey(const Key('tag-edit-save')));
    await tester.pumpAndSettle();
    expect(corrections.addTagCalls, hasLength(1));
    expect(find.text('park'), findsWidgets);

    // Add a comment — author stamped by server fake.
    await tester.ensureVisible(find.byKey(const Key('comment-body-field')));
    await tester.enterText(
      find.byKey(const Key('comment-body-field')),
      'integration note',
    );
    await tester.tap(find.byKey(const Key('comment-add')));
    await tester.pumpAndSettle();
    expect(comments.createItemCalls, hasLength(1));
    expect(find.text('integration note'), findsOneWidget);
    expect(find.textContaining('acc_integration'), findsWidgets);

    // Foreign account knowledge stays 404 (tenant isolation).
    expect(
      () => foreignItems.getKnowledge('item_c'),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'status', 404),
      ),
    );
  });
}
