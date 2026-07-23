import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/item_detail_page.dart';
import 'package:tagkin_desktop/review/item_review_page.dart';

import 'fake_comments_repository.dart';
import 'fake_corrections_repository.dart';
import 'fake_items_repository.dart';
import 'fake_jobs_repository.dart';
import 'fake_persons_repository.dart';
import 'fake_usage_repository.dart';

void main() {
  testWidgets('KnowledgeView renders who/what/when/where + provenance',
      (tester) async {
    final item = fixtureItem(
      id: 'item_1',
      processingStatus: ProcessingStatus.tagged,
    );
    final knowledge = fixtureKnowledge(item: item);
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {'item_1': knowledge},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          itemsRepositoryProvider.overrideWithValue(items),
          correctionsRepositoryProvider.overrideWithValue(
            FakeCorrectionsRepository(items: items),
          ),
          commentsRepositoryProvider.overrideWithValue(
            FakeCommentsRepository(),
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

    expect(find.byKey(const Key('item-review')), findsOneWidget);
    expect(find.byKey(const Key('knowledge-view')), findsOneWidget);
    expect(find.byKey(const Key('knowledge-dimension-who')), findsOneWidget);
    expect(find.byKey(const Key('knowledge-dimension-what')), findsOneWidget);
    expect(find.byKey(const Key('knowledge-dimension-when')), findsOneWidget);
    expect(find.byKey(const Key('knowledge-dimension-where')), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('picnic'), findsOneWidget);
    expect(find.byKey(const Key('tag-provenance-tag_who')), findsOneWidget);
    expect(find.byKey(const Key('media-status-missing')), findsOneWidget);

    // Photo: no key-period scrubber; no browse/search chrome (R2 / §1).
    expect(find.byKey(const Key('key-period-scrubber')), findsNothing);
    expect(find.textContaining('Search'), findsNothing);
    expect(find.textContaining('Filter'), findsNothing);
  });

  testWidgets('Video item shows key-period scrubber with start/end',
      (tester) async {
    final item = fixtureItem(
      id: 'item_v',
      type: ItemType.video,
      processingStatus: ProcessingStatus.tagged,
    );
    final knowledge = fixtureKnowledge(
      item: item,
      tags: [fixtureTag(dimension: 'what', value: 'party')],
      keyPeriods: [
        KeyPeriodKnowledge(
          id: 'kp_1',
          itemId: 'item_v',
          startMs: 2500,
          endMs: 8000,
          tags: const [],
        ),
      ],
    );
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {'item_v': knowledge},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          itemsRepositoryProvider.overrideWithValue(items),
          correctionsRepositoryProvider.overrideWithValue(
            FakeCorrectionsRepository(items: items),
          ),
          commentsRepositoryProvider.overrideWithValue(
            FakeCommentsRepository(),
          ),
          usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
          jobsRepositoryProvider.overrideWithValue(
            FakeJobsRepository(itemId: 'item_v', item: item),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ItemReviewSection(itemId: 'item_v', openVideo: false),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('key-period-scrubber')), findsOneWidget);
    expect(find.byKey(const Key('key-period-kp_1')), findsOneWidget);
    expect(find.byKey(const Key('key-period-range-kp_1')), findsOneWidget);
    expect(find.textContaining('00:02.50'), findsOneWidget);
    expect(find.textContaining('00:08.00'), findsOneWidget);
    expect(find.text('party'), findsOneWidget);
  });

  testWidgets('Find person matches prompts to name unnamed persons',
      (tester) async {
    final item = fixtureItem(
      id: 'item_1',
      processingStatus: ProcessingStatus.tagged,
    );
    final knowledge = fixtureKnowledge(item: item);
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {'item_1': knowledge},
    );
    items.linkPeopleResult.add(
      fixtureAppearance(
        id: 'ap_new',
        personId: 'person_new',
        itemId: 'item_1',
        linkState: LinkState.suggested,
      ),
    );
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_new',
          name: null,
          linkState: LinkState.suggested,
          appearances: [
            fixtureAppearance(
              id: 'ap_new',
              personId: 'person_new',
              itemId: 'item_1',
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          itemsRepositoryProvider.overrideWithValue(items),
          personsRepositoryProvider.overrideWithValue(persons),
          correctionsRepositoryProvider.overrideWithValue(
            FakeCorrectionsRepository(items: items),
          ),
          commentsRepositoryProvider.overrideWithValue(
            FakeCommentsRepository(),
          ),
          usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
          jobsRepositoryProvider.overrideWithValue(
            FakeJobsRepository(itemId: 'item_1', item: item),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ItemReviewSection(itemId: 'item_1', openVideo: false),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('item-link-people')));
    await tester.tap(find.byKey(const Key('item-link-people')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('person-name-dialog')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('person-name-field')),
      'Jordan',
    );
    await tester.tap(find.byKey(const Key('person-name-save')));
    await tester.pumpAndSettle();

    expect(items.linkPeopleCalls, ['item_1']);
    expect(persons.renameCalls.single.name, 'Jordan');
    expect(
      find.byKey(const Key('link-people-status')),
      findsOneWidget,
    );
    expect(find.textContaining('Jordan'), findsOneWidget);
  });
}
