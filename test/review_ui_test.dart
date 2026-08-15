import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/item_detail_page.dart';
import 'package:tagkin_desktop/persons/person_assign_control.dart';
import 'package:tagkin_desktop/review/item_review_page.dart';
import 'package:tagkin_desktop/ui/format_local_datetime.dart';
import 'package:tagkin_desktop/undo/undo_shortcuts.dart';

import 'fake_comments_repository.dart';
import 'fake_corrections_repository.dart';
import 'fake_items_repository.dart';
import 'fake_jobs_repository.dart';
import 'fake_persons_repository.dart';
import 'fake_usage_repository.dart';

FormFieldState<String> _assignFieldState(WidgetTester tester, Key key) {
  return tester.state<FormFieldState<String>>(
    find.descendant(
      of: find.byKey(key),
      matching: find.byType(DropdownButtonFormField<String>),
    ),
  );
}

void main() {
  testWidgets('KnowledgeView renders who/what/when/where as CSV',
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
    expect(find.byKey(const Key('knowledge-who')), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
    expect(find.byKey(const Key('item-fields-left')), findsOneWidget);
    expect(find.byKey(const Key('item-fields-right')), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Status')).dx,
      lessThan(
        tester
            .getTopLeft(find.byKey(const Key('knowledge-dimension-who')))
            .dx,
      ),
    );
    expect(
      tester.getTopLeft(find.text('Status')).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('item-type'))).dy),
    );
    expect(
      tester
          .getTopLeft(find.byKey(const Key('knowledge-dimension-who')))
          .dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const Key('knowledge-dimension-where')))
            .dy,
      ),
    );
    expect(find.text('picnic'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('item-captured-at'))).data,
      formatLocalDateTime(item.capturedAt),
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('item-created-at'))).data,
      formatLocalDateTime(item.createdAt),
    );
    expect(find.text('2026-07-01T12:00:00.000Z'), findsNothing);
    expect(find.text('2026-07-19T00:00:00.000Z'), findsNothing);
    expect(find.byKey(const Key('tag-provenance-tag_who')), findsNothing);
    expect(find.byKey(const Key('tag-add-who')), findsNothing);
    expect(find.byKey(const Key('tag-edit-tag_who')), findsNothing);
    expect(find.byKey(const Key('corrections-history')), findsNothing);
    expect(find.byKey(const Key('review-captured-at')), findsNothing);
    expect(find.byKey(const Key('captured-at-edit')), findsNothing);
    expect(find.byKey(const Key('media-status-missing')), findsOneWidget);
    expect(find.byKey(const Key('media-status-available')), findsNothing);
    expect(find.byKey(const Key('item-face-assign-grid')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('item-face-assign-grid'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('media-status-missing'))).dy,
      ),
    );

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

  testWidgets(
      'Assign face crop to a new person; no whole-item assign when crops exist',
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
      tags: [
        fixtureTag(
          id: 'tag_who',
          dimension: 'who',
          value: 'toddler',
          region: const TagRegion(
            yMin: 0.1,
            xMin: 0.1,
            yMax: 0.4,
            xMax: 0.4,
          ),
        ),
      ],
    );
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {'item_1': knowledge},
    );
    final persons = FakePersonsRepository(persons: const []);
    items.linkedPersons = persons;

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

    expect(find.byKey(const Key('item-link-people')), findsNothing);
    expect(find.byKey(const Key('item-assign-person')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('item-assign-face-tag_who')));
    await tester.tap(find.byKey(const Key('item-assign-face-tag_who')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New person').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('person-name-field')), 'Maya');
    await tester.tap(find.byKey(const Key('person-name-save')));
    await tester.pumpAndSettle();

    expect(items.assignPersonCalls, isEmpty);
    expect(
      _assignFieldState(tester, const Key('item-assign-face-tag_who')).value,
      PersonAssignControl.draftValue('Maya'),
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('item-assign-face-tag_who')),
        matching: find.text('Maya'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('item-assign-face-tag_who')),
        matching: find.text('New person'),
      ),
      findsNothing,
    );
    await tester.ensureVisible(find.byKey(const Key('item-detail-save')));
    await tester.tap(find.byKey(const Key('item-detail-save')));
    await tester.pumpAndSettle();

    expect(items.assignPersonCalls, hasLength(1));
    expect(items.assignPersonCalls.single.tagId, 'tag_who');
    expect(items.assignPersonCalls.single.name, 'Maya');
  });

  testWidgets('Exclude from photo is draft until Save', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final item = fixtureItem(
      id: 'item_1',
      processingStatus: ProcessingStatus.tagged,
    );
    final knowledge = fixtureKnowledge(
      item: item,
      tags: [
        fixtureTag(
          id: 'tag_who',
          dimension: 'who',
          value: 'toddler',
          region: const TagRegion(
            yMin: 0.1,
            xMin: 0.1,
            yMax: 0.4,
            xMax: 0.4,
          ),
        ),
      ],
    );
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {'item_1': knowledge},
    );
    final persons = FakePersonsRepository(persons: const []);
    items.linkedPersons = persons;

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

    expect(find.byKey(const Key('item-exclude-face-tag_who')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('item-exclude-face-tag_who')),
    );
    await tester.tap(find.byKey(const Key('item-exclude-face-tag_who')));
    await tester.pumpAndSettle();

    expect(items.createWhoExclusionCalls, isEmpty);
    expect(find.byKey(const Key('item-assign-face-tag_who')), findsNothing);
    expect(find.byKey(const Key('who-exclusion-draft-tag_who')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('item-detail-save')));
    await tester.tap(find.byKey(const Key('item-detail-save')));
    await tester.pumpAndSettle();

    expect(items.createWhoExclusionCalls, hasLength(1));
    expect(items.createWhoExclusionCalls.single.tagId, 'tag_who');
    expect(find.byKey(const Key('item-assign-face-tag_who')), findsNothing);
    expect(find.byKey(const Key('who-exclusion-draft-tag_who')), findsNothing);
    expect(find.byKey(const Key('who-exclusion-excl_tag_who_1')), findsOneWidget);
  });

  testWidgets(
      'Exclude then Cmd+Z under SelectableScope restores the crop',
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
      tags: [
        fixtureTag(
          id: 'tag_who',
          dimension: 'who',
          value: 'toddler',
          region: const TagRegion(
            yMin: 0.1,
            xMin: 0.1,
            yMax: 0.4,
            xMax: 0.4,
          ),
        ),
      ],
    );
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {'item_1': knowledge},
    );
    final persons = FakePersonsRepository(persons: const []);
    items.linkedPersons = persons;

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
        child: MaterialApp(
          builder: (context, child) {
            return ActiveUndoShortcuts(
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const UndoSelectableRoute(
            child: ItemDetailPage(itemId: 'item_1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('item-exclude-face-tag_who')),
    );
    await tester.tap(find.byKey(const Key('item-exclude-face-tag_who')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('who-exclusion-draft-tag_who')), findsOneWidget);
    expect(find.byKey(const Key('undo-depth')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byKey(const Key('undo-depth')),
      ),
      findsOneWidget,
    );
    expect(items.createWhoExclusionCalls, isEmpty);

    // Do not retarget focus onto SelectionArea — after Exclude, focus is
    // the route FocusScope (same as a real Cmd+Z after a button click).
    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('item-assign-face-tag_who')), findsOneWidget);
    expect(find.byKey(const Key('who-exclusion-draft-tag_who')), findsNothing);
    expect(find.byKey(const Key('undo-depth')), findsNothing);
    expect(items.createWhoExclusionCalls, isEmpty);
  });

  testWidgets('Include on a draft exclude restores the crop with no API',
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
      tags: [
        fixtureTag(
          id: 'tag_who',
          dimension: 'who',
          value: 'toddler',
          region: const TagRegion(
            yMin: 0.1,
            xMin: 0.1,
            yMax: 0.4,
            xMax: 0.4,
          ),
        ),
      ],
    );
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {'item_1': knowledge},
    );
    final persons = FakePersonsRepository(persons: const []);
    items.linkedPersons = persons;

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

    await tester.ensureVisible(
      find.byKey(const Key('item-exclude-face-tag_who')),
    );
    await tester.tap(find.byKey(const Key('item-exclude-face-tag_who')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('item-include-face-tag_who')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('item-include-face-tag_who')),
    );
    await tester.tap(find.byKey(const Key('item-include-face-tag_who')));
    await tester.pumpAndSettle();

    expect(items.createWhoExclusionCalls, isEmpty);
    expect(items.undoWhoExclusionCalls, isEmpty);
    expect(find.byKey(const Key('item-assign-face-tag_who')), findsOneWidget);
    expect(find.byKey(const Key('who-exclusion-draft-tag_who')), findsNothing);
    expect(find.byKey(const Key('item-detail-save')), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('item-detail-save'))).onPressed,
      isNull,
    );
  });

  testWidgets(
      'Include on a saved exclusion is draft; assign then Save undoes exclude',
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
      tags: const [],
      whoExclusions: [
        const WhoExclusion(
          id: 'ex_1',
          itemId: 'item_1',
          region: TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.4, xMax: 0.4),
          createdFromTagId: 'tag_who',
          createdAt: '2026-07-26T00:00:00.000Z',
        ),
      ],
    );
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {'item_1': knowledge},
    );
    final persons = FakePersonsRepository(persons: const []);
    items.linkedPersons = persons;

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

    expect(find.byKey(const Key('item-include-exclusion-ex_1')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('item-include-exclusion-ex_1')),
    );
    await tester.tap(find.byKey(const Key('item-include-exclusion-ex_1')));
    await tester.pumpAndSettle();

    expect(items.undoWhoExclusionCalls, isEmpty);
    expect(find.byKey(const Key('who-exclusion-ex_1')), findsNothing);
    expect(
      find.byKey(const Key('who-exclusion-included-ex_1')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('item-assign-included-ex_1')), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('item-assign-included-ex_1')),
    );
    await tester.tap(find.byKey(const Key('item-assign-included-ex_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New person').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('person-name-field')), 'Maya');
    await tester.tap(find.byKey(const Key('person-name-save')));
    await tester.pumpAndSettle();

    expect(items.assignPersonCalls, isEmpty);
    expect(
      _assignFieldState(tester, const Key('item-assign-included-ex_1')).value,
      PersonAssignControl.draftValue('Maya'),
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('item-assign-included-ex_1')),
        matching: find.text('Maya'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('item-assign-included-ex_1')),
        matching: find.text('New person'),
      ),
      findsNothing,
    );
    await tester.ensureVisible(find.byKey(const Key('item-detail-save')));
    await tester.tap(find.byKey(const Key('item-detail-save')));
    await tester.pumpAndSettle();

    expect(items.undoWhoExclusionCalls, hasLength(1));
    expect(items.undoWhoExclusionCalls.single.exclusionId, 'ex_1');
    expect(items.assignPersonCalls, hasLength(1));
    expect(items.assignPersonCalls.single.tagId, 'tag_who');
    expect(items.assignPersonCalls.single.name, 'Maya');
  });

  testWidgets(
      'Second included face can pick a draft New person name before Save',
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
      tags: const [],
      whoExclusions: [
        const WhoExclusion(
          id: 'ex_1',
          itemId: 'item_1',
          region: TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.4, xMax: 0.4),
          createdFromTagId: 'tag_a',
          createdAt: '2026-07-26T00:00:00.000Z',
        ),
        const WhoExclusion(
          id: 'ex_2',
          itemId: 'item_1',
          region: TagRegion(yMin: 0.5, xMin: 0.5, yMax: 0.8, xMax: 0.8),
          createdFromTagId: 'tag_b',
          createdAt: '2026-07-26T00:00:00.000Z',
        ),
      ],
    );
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {'item_1': knowledge},
    );
    final persons = FakePersonsRepository(persons: const []);
    items.linkedPersons = persons;

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

    await tester.ensureVisible(
      find.byKey(const Key('item-include-exclusion-ex_1')),
    );
    await tester.tap(find.byKey(const Key('item-include-exclusion-ex_1')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('item-include-exclusion-ex_2')),
    );
    await tester.tap(find.byKey(const Key('item-include-exclusion-ex_2')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('item-assign-included-ex_1')),
    );
    await tester.tap(find.byKey(const Key('item-assign-included-ex_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New person').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('person-name-field')), 'test');
    await tester.tap(find.byKey(const Key('person-name-save')));
    await tester.pumpAndSettle();

    expect(
      _assignFieldState(tester, const Key('item-assign-included-ex_1')).value,
      PersonAssignControl.draftValue('test'),
    );

    await tester.ensureVisible(
      find.byKey(const Key('item-assign-included-ex_2')),
    );
    await tester.tap(find.byKey(const Key('item-assign-included-ex_2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('person-assign-draft-test')), findsWidgets);
    await tester.tap(find.text('test').last);
    await tester.pumpAndSettle();

    expect(
      _assignFieldState(tester, const Key('item-assign-included-ex_2')).value,
      PersonAssignControl.draftValue('test'),
    );
    expect(items.assignPersonCalls, isEmpty);

    await tester.ensureVisible(find.byKey(const Key('item-detail-save')));
    await tester.tap(find.byKey(const Key('item-detail-save')));
    await tester.pumpAndSettle();

    expect(items.undoWhoExclusionCalls, hasLength(2));
    expect(items.assignPersonCalls, hasLength(2));
    expect(
      items.assignPersonCalls.map((c) => c.name).toList(),
      ['test', 'test'],
    );
  });

  testWidgets('Assign item to a person when there are no face crops',
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
    final persons = FakePersonsRepository(persons: const []);
    items.linkedPersons = persons;

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

    expect(find.byKey(const Key('item-assign-face-tag_who')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('item-assign-person')));
    await tester.tap(find.byKey(const Key('item-assign-person')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New person').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('person-name-field')), 'Dad');
    await tester.tap(find.byKey(const Key('person-name-save')));
    await tester.pumpAndSettle();

    expect(items.assignPersonCalls, isEmpty);
    await tester.ensureVisible(find.byKey(const Key('item-detail-save')));
    await tester.tap(find.byKey(const Key('item-detail-save')));
    await tester.pumpAndSettle();

    expect(items.assignPersonCalls, hasLength(1));
    expect(items.assignPersonCalls.single.tagId, isNull);
    expect(items.assignPersonCalls.single.name, 'Dad');
  });

  testWidgets('Who lists person names then original who-tag values',
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
      tags: [
        fixtureTag(
          id: 'tag_who',
          dimension: 'who',
          value: 'toddler',
          region: const TagRegion(
            yMin: 0.1,
            xMin: 0.1,
            yMax: 0.4,
            xMax: 0.4,
          ),
        ),
        fixtureTag(id: 'tag_what', dimension: 'what', value: 'picnic'),
      ],
      appearances: [
        fixtureAppearance(
          id: 'ap_1',
          personId: 'person_alex',
          itemId: 'item_1',
          tagId: 'tag_who',
        ),
      ],
    );
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {'item_1': knowledge},
    );
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_alex',
          name: 'Alex',
          appearances: [
            fixtureAppearance(
              id: 'ap_1',
              personId: 'person_alex',
              itemId: 'item_1',
              tagId: 'tag_who',
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

    expect(find.byKey(const Key('knowledge-who')), findsOneWidget);
    expect(find.text('Alex, toddler'), findsOneWidget);
    expect(find.text('Alex toddler'), findsOneWidget);
    expect(find.textContaining('person_alex'), findsNothing);
    expect(find.byKey(const Key('tag-provenance-tag_who')), findsNothing);
  });

  testWidgets('Excluded faces show crop thumbs', (tester) async {
    final item = fixtureItem(
      id: 'item_1',
      processingStatus: ProcessingStatus.tagged,
    );
    final knowledge = fixtureKnowledge(
      item: item,
      tags: [fixtureTag(id: 'tag_who', dimension: 'who', value: 'toddler')],
      whoExclusions: [
        const WhoExclusion(
          id: 'ex_1',
          itemId: 'item_1',
          region: TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.4, xMax: 0.4),
          createdFromTagId: 'tag_who',
          createdAt: '2026-07-26T00:00:00.000Z',
        ),
      ],
    );
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
          home: Scaffold(
            body: SingleChildScrollView(
              child: ItemReviewSection(itemId: 'item_1', openVideo: false),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('who-exclusion-ex_1')), findsOneWidget);
    expect(find.text('Excluded face'), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const Key('who-exclusion-ex_1'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('media-status-missing'))).dy,
      ),
    );
  });

  testWidgets('Face-person cells pair left-right under File/Comment',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    const regionA = TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.4, xMax: 0.4);
    const regionB = TagRegion(yMin: 0.1, xMin: 0.5, yMax: 0.4, xMax: 0.8);
    final item = fixtureItem(
      id: 'item_1',
      processingStatus: ProcessingStatus.tagged,
    );
    final knowledge = fixtureKnowledge(
      item: item,
      tags: [
        fixtureTag(
          id: 'tag_a',
          dimension: 'who',
          value: 'left',
          region: regionA,
        ),
        fixtureTag(
          id: 'tag_b',
          dimension: 'who',
          value: 'right',
          region: regionB,
        ),
      ],
    );
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {'item_1': knowledge},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          itemsRepositoryProvider.overrideWithValue(items),
          personsRepositoryProvider.overrideWithValue(
            FakePersonsRepository(persons: const []),
          ),
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

    final left = tester.getTopLeft(find.byKey(const Key('item-assign-face-tag_a')));
    final right =
        tester.getTopLeft(find.byKey(const Key('item-assign-face-tag_b')));
    expect(left.dx, lessThan(right.dx));
    expect((left.dy - right.dy).abs(), lessThan(24));
    expect(
      left.dy,
      greaterThan(tester.getTopLeft(find.byKey(const Key('item-comment-field'))).dy),
    );
  });

  testWidgets('unsaved item edits prompt Save/Discard/Cancel on back',
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
    final comments = FakeCommentsRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          itemsRepositoryProvider.overrideWithValue(items),
          personsRepositoryProvider.overrideWithValue(
            FakePersonsRepository(persons: const []),
          ),
          correctionsRepositoryProvider.overrideWithValue(
            FakeCorrectionsRepository(items: items),
          ),
          commentsRepositoryProvider.overrideWithValue(comments),
          usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
          jobsRepositoryProvider.overrideWithValue(
            FakeJobsRepository(itemId: 'item_1', item: item),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const Key('open-item'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ItemDetailPage(itemId: 'item_1'),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-item')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('item-comment-field')),
      'draft note',
    );
    await tester.pump();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('item-detail-dirty-dialog')), findsOneWidget);

    await tester.tap(find.byKey(const Key('item-detail-dirty-discard')));
    await tester.pumpAndSettle();

    expect(find.byType(ItemDetailPage), findsNothing);
    expect(comments.createItemCalls, isEmpty);
  });
}
