import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/item_detail_page.dart';
import 'package:tagkin_desktop/persons/person_detail_page.dart';

import 'fake_comments_repository.dart';
import 'fake_corrections_repository.dart';
import 'fake_items_repository.dart';
import 'fake_jobs_repository.dart';
import 'fake_persons_repository.dart';
import 'fake_usage_repository.dart';

List<Override> _itemOverrides({
  required FakeItemsRepository items,
  required FakeCommentsRepository comments,
  required Item item,
}) {
  return [
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
      FakeJobsRepository(itemId: item.id, item: item),
    ),
  ];
}

void main() {
  testWidgets('item detail AppBar has Folders / Faces / Persons nav',
      (tester) async {
    final item = fixtureItem(id: 'item_1');
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {'item_1': fixtureKnowledge(item: item)},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _itemOverrides(
          items: items,
          comments: FakeCommentsRepository(),
          item: item,
        ),
        child: const MaterialApp(
          home: ItemDetailPage(itemId: 'item_1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('item-detail')), findsOneWidget);
    expect(find.byKey(const Key('nav-folders')), findsOneWidget);
    expect(find.byKey(const Key('nav-face-crops')), findsOneWidget);
    expect(find.byKey(const Key('nav-persons')), findsOneWidget);
  });

  testWidgets('item detail nav pops to first route and selects that tab',
      (tester) async {
    final item = fixtureItem(id: 'item_1');
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {'item_1': fixtureKnowledge(item: item)},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _itemOverrides(
          items: items,
          comments: FakeCommentsRepository(),
          item: item,
        ),
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
    expect(find.byKey(const Key('item-detail')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav-persons')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('item-detail')), findsNothing);
    expect(find.byKey(const Key('open-item')), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('open-item'))),
    );
    expect(
      container.read(activeTopLevelTabProvider),
      TopLevelTab.persons,
    );
  });

  testWidgets(
      'unsaved item edits prompt Save/Discard/Cancel when tapping app nav',
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
        overrides: _itemOverrides(
          items: items,
          comments: comments,
          item: item,
        ),
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

    await tester.tap(find.byKey(const Key('nav-folders')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('item-detail-dirty-dialog')), findsOneWidget);
    expect(find.byKey(const Key('item-detail')), findsOneWidget);

    await tester.tap(find.byKey(const Key('item-detail-dirty-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('item-detail')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav-face-crops')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('item-detail-dirty-dialog')), findsOneWidget);

    await tester.tap(find.byKey(const Key('item-detail-dirty-discard')));
    await tester.pumpAndSettle();

    expect(find.byType(ItemDetailPage), findsNothing);
    expect(comments.createItemCalls, isEmpty);
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('open-item'))),
    );
    expect(
      container.read(activeTopLevelTabProvider),
      TopLevelTab.faces,
    );
  });

  testWidgets('person detail AppBar has Folders / Faces / Persons nav',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [fixturePersonDetail(id: 'person_1', name: 'Sam')],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [personsRepositoryProvider.overrideWithValue(persons)],
        child: const MaterialApp(
          home: PersonDetailPage(personId: 'person_1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('person-detail')), findsOneWidget);
    expect(find.byKey(const Key('nav-folders')), findsOneWidget);
    expect(find.byKey(const Key('nav-face-crops')), findsOneWidget);
    expect(find.byKey(const Key('nav-persons')), findsOneWidget);
  });

  testWidgets('person detail nav pops to first route and selects that tab',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [fixturePersonDetail(id: 'person_1', name: 'Sam')],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [personsRepositoryProvider.overrideWithValue(persons)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const Key('open-person'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const PersonDetailPage(personId: 'person_1'),
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

    await tester.tap(find.byKey(const Key('open-person')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('person-detail')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav-face-crops')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('person-detail')), findsNothing);
    expect(find.byKey(const Key('open-person')), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('open-person'))),
    );
    expect(
      container.read(activeTopLevelTabProvider),
      TopLevelTab.faces,
    );
  });
}
