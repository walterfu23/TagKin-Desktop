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
import 'fake_persons_repository.dart';
import 'fake_usage_repository.dart';

void main() {
  testWidgets('photo detail: comments stay; no tag edit or corrections list',
      (tester) async {
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
    final comments = FakeCommentsRepository(authorUserId: 'acc_ui');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          itemsRepositoryProvider.overrideWithValue(items),
          correctionsRepositoryProvider.overrideWithValue(
            FakeCorrectionsRepository(items: items),
          ),
          commentsRepositoryProvider.overrideWithValue(comments),
          personsRepositoryProvider.overrideWithValue(
            FakePersonsRepository(persons: const []),
          ),
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

    expect(find.byKey(const Key('item-fields-left')), findsOneWidget);
    expect(find.byKey(const Key('item-fields-right')), findsOneWidget);
    expect(find.byKey(const Key('knowledge-view')), findsOneWidget);
    expect(find.text('picnic'), findsOneWidget);
    expect(find.byKey(const Key('tag-add-what')), findsNothing);
    expect(find.byKey(const Key('tag-remove-tag_what')), findsNothing);
    expect(find.byKey(const Key('corrections-history')), findsNothing);
    expect(find.byKey(const Key('item-comment-field')), findsOneWidget);
    expect(find.byKey(const Key('comments-view')), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('item-comment-field')));
    await tester.enterText(
      find.byKey(const Key('item-comment-field')),
      'looks great',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('item-detail-save')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('item-detail-save')));
    await tester.pumpAndSettle();
    expect(comments.createItemCalls, hasLength(1));
    expect(find.text('looks great'), findsWidgets);
    expect(find.textContaining('acc_ui'), findsNothing);
  });
}
