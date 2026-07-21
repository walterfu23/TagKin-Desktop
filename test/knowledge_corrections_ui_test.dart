import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/item_detail_page.dart';

import 'fake_comments_repository.dart';
import 'fake_corrections_repository.dart';
import 'fake_items_repository.dart';
import 'fake_jobs_repository.dart';
import 'fake_usage_repository.dart';

void main() {
  testWidgets('corrections UI: add tag, undo, add comment', (tester) async {
    // Tall surface so correction/comment controls are reachable without
    // fighting the default 800×600 test window.
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final item = fixtureItem(
      id: 'item_1',
      processingStatus: ProcessingStatus.tagged,
    );
    final knowledge = fixtureKnowledge(
      item: item,
      tags: [fixtureTag(id: 'tag_what', dimension: 'what', value: 'picnic')],
      corrections: [
        fixtureCorrection(
          id: 'corr_existing',
          targetType: 'tag',
          targetId: 'tag_what',
          previousValue: 'walk',
          newValue: 'picnic',
        ),
      ],
    );
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {'item_1': knowledge},
    );
    final corrections = FakeCorrectionsRepository(items: items);
    final comments = FakeCommentsRepository(authorUserId: 'acc_ui');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          itemsRepositoryProvider.overrideWithValue(items),
          correctionsRepositoryProvider.overrideWithValue(corrections),
          commentsRepositoryProvider.overrideWithValue(comments),
          usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
          jobsRepositoryProvider.overrideWithValue(
            FakeJobsRepository(itemId: 'item_1', item: item),
          ),
        ],
        child: const MaterialApp(
          home: ItemDetailPage(itemId: 'item_1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('knowledge-view')), findsOneWidget);
    expect(find.byKey(const Key('corrections-history')), findsOneWidget);
    expect(find.byKey(const Key('correction-corr_existing')), findsOneWidget);
    expect(find.byKey(const Key('comments-view')), findsOneWidget);

    // Undo existing correction.
    await tester.ensureVisible(
      find.byKey(const Key('correction-undo-corr_existing')),
    );
    await tester.tap(find.byKey(const Key('correction-undo-corr_existing')));
    await tester.pumpAndSettle();
    expect(corrections.undoCalls, ['corr_existing']);

    // Add a comment.
    await tester.ensureVisible(find.byKey(const Key('comment-body-field')));
    await tester.enterText(
      find.byKey(const Key('comment-body-field')),
      'looks great',
    );
    await tester.tap(find.byKey(const Key('comment-add')));
    await tester.pumpAndSettle();
    expect(comments.createItemCalls, hasLength(1));
    expect(find.text('looks great'), findsOneWidget);
    expect(find.textContaining('acc_ui'), findsOneWidget);

    // Add tag via dialog.
    await tester.ensureVisible(find.byKey(const Key('tag-add-where')));
    await tester.tap(find.byKey(const Key('tag-add-where')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tag-edit-dialog')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('tag-value-field')), 'park');
    await tester.tap(find.byKey(const Key('tag-edit-save')));
    await tester.pumpAndSettle();
    expect(corrections.addTagCalls, hasLength(1));
    expect(corrections.addTagCalls.single.input.value, 'park');
    expect(find.text('park'), findsWidgets);
  });

  testWidgets('remove tag updates knowledge view', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final item = fixtureItem(
      id: 'item_1',
      processingStatus: ProcessingStatus.tagged,
    );
    final knowledge = fixtureKnowledge(
      item: item,
      tags: [fixtureTag(id: 'tag_what', dimension: 'what', value: 'picnic')],
    );
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {'item_1': knowledge},
    );
    final corrections = FakeCorrectionsRepository(items: items);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          itemsRepositoryProvider.overrideWithValue(items),
          correctionsRepositoryProvider.overrideWithValue(corrections),
          commentsRepositoryProvider.overrideWithValue(FakeCommentsRepository()),
          usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
          jobsRepositoryProvider.overrideWithValue(
            FakeJobsRepository(itemId: 'item_1', item: item),
          ),
        ],
        child: const MaterialApp(
          home: ItemDetailPage(itemId: 'item_1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('picnic'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('tag-remove-tag_what')));
    await tester.tap(find.byKey(const Key('tag-remove-tag_what')));
    await tester.pumpAndSettle();
    expect(corrections.removeTagCalls, ['tag_what']);
    expect(find.text('picnic'), findsNothing);
  });
}
