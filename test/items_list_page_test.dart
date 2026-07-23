import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/item_detail_page.dart';
import 'package:tagkin_desktop/library/items_list_page.dart';
import 'package:tagkin_desktop/main.dart';

import 'fake_comments_repository.dart';
import 'fake_corrections_repository.dart';
import 'fake_items_repository.dart';
import 'fake_jobs_repository.dart';
import 'fake_usage_repository.dart';

Account _account(String id) => Account(
      id: id,
      email: '$id@example.com',
      createdAt: '2026-07-18T00:00:00.000Z',
    );

List<Override> _sessionOverrides({
  required FakeItemsRepository items,
  String accountId = 'acc_1',
  String token = 'tok',
  FakeUsageRepository? usage,
  FakeJobsRepository? jobs,
}) {
  return [
    testSessionProvider.overrideWithValue(
      TestSession(token: token, account: _account(accountId)),
    ),
    itemsRepositoryProvider.overrideWithValue(items),
    correctionsRepositoryProvider.overrideWithValue(
      FakeCorrectionsRepository(items: items),
    ),
    commentsRepositoryProvider.overrideWithValue(FakeCommentsRepository()),
    usageRepositoryProvider.overrideWithValue(
      usage ?? FakeUsageRepository(),
    ),
    jobsRepositoryProvider.overrideWithValue(
      jobs ?? FakeJobsRepository(),
    ),
  ];
}

Future<void> _pumpLibrary(
  WidgetTester tester, {
  required FakeItemsRepository items,
  FakeJobsRepository? jobs,
}) async {
  // Match the wide library window so fixed table columns fit.
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: _sessionOverrides(items: items, jobs: jobs),
      child: const TagKinDesktopApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('library table renders fixture items with processingStatus',
      (tester) async {
    final item1 = fixtureItem(
      id: 'item_1',
      processingStatus: ProcessingStatus.pending,
    );
    final item2 = fixtureItem(
      id: 'item_2',
      type: ItemType.video,
      processingStatus: ProcessingStatus.tagged,
    );
    await _pumpLibrary(
      tester,
      items: FakeItemsRepository(
        items: [item1, item2],
        knowledgeByItemId: {
          'item_2': fixtureKnowledge(item: item2),
        },
      ),
    );

    expect(find.byKey(const Key('items-list')), findsOneWidget);
    expect(find.byKey(const Key('item-row-item_1')), findsOneWidget);
    expect(find.byKey(const Key('item-row-item_2')), findsOneWidget);
    expect(find.byKey(const Key('processing-status-pending')), findsOneWidget);
    expect(find.byKey(const Key('processing-status-tagged')), findsOneWidget);
    expect(find.byKey(const Key('sort-header-who')), findsOneWidget);
    expect(find.byKey(const Key('library-filter')), findsOneWidget);
  });

  testWidgets('empty library shows empty state', (tester) async {
    await _pumpLibrary(tester, items: FakeItemsRepository());
    expect(find.byKey(const Key('items-empty')), findsOneWidget);
  });

  testWidgets('tap row opens item detail', (tester) async {
    final item = fixtureItem(id: 'item_nav');
    await _pumpLibrary(
      tester,
      items: FakeItemsRepository(items: [item]),
    );
    // Prefer the what-cell control — FAB may cover the bottom of a single row.
    await tester.ensureVisible(find.byKey(const Key('item-what-item_nav')));
    await tester.tap(find.byKey(const Key('item-what-item_nav')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('item-detail')), findsOneWidget);
    expect(find.byKey(const Key('item-id')), findsOneWidget);
    expect(find.text('item_nav'), findsWidgets);
  });

  testWidgets('tap thumb opens item detail', (tester) async {
    final item = fixtureItem(id: 'item_thumb_nav');
    await _pumpLibrary(
      tester,
      items: FakeItemsRepository(items: [item]),
    );
    await tester.ensureVisible(
      find.byKey(const Key('item-thumb-placeholder-item_thumb_nav')),
    );
    await tester.tap(
      find.byKey(const Key('item-thumb-placeholder-item_thumb_nav')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('item-detail')), findsOneWidget);
  });

  testWidgets('source control does not open detail', (tester) async {
    final item = fixtureItem(id: 'item_src');
    await _pumpLibrary(
      tester,
      items: FakeItemsRepository(items: [item]),
    );
    await tester.tap(find.byKey(const Key('item-source-item_src')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('item-detail')), findsNothing);
    expect(find.byKey(const Key('item-row-item_src')), findsOneWidget);
  });

  testWidgets('who more expands remaining names', (tester) async {
    final item = fixtureItem(
      id: 'item_who',
      processingStatus: ProcessingStatus.tagged,
    );
    await _pumpLibrary(
      tester,
      items: FakeItemsRepository(
        items: [item],
        knowledgeByItemId: {
          'item_who': fixtureKnowledge(
            item: item,
            tags: [
              fixtureTag(
                id: 'w1',
                itemId: 'item_who',
                dimension: 'who',
                value: 'Sam',
              ),
              fixtureTag(
                id: 'w2',
                itemId: 'item_who',
                dimension: 'who',
                value: 'Ada',
              ),
            ],
          ),
        },
      ),
    );
    // Wait for knowledge warm.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('item-who-more-item_who')), findsOneWidget);
    await tester.tap(find.byKey(const Key('item-who-more-item_who')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ada'), findsWidgets);
    expect(find.byKey(const Key('item-who-less-item_who')), findsOneWidget);
  });

  testWidgets('filter narrows visible rows', (tester) async {
    final a = fixtureItem(id: 'a', processingStatus: ProcessingStatus.tagged);
    final b = fixtureItem(id: 'b', processingStatus: ProcessingStatus.tagged);
    await _pumpLibrary(
      tester,
      items: FakeItemsRepository(
        items: [a, b],
        knowledgeByItemId: {
          'a': fixtureKnowledge(
            item: a,
            tags: [
              fixtureTag(id: 'wa', itemId: 'a', dimension: 'who', value: 'Sam'),
            ],
          ),
          'b': fixtureKnowledge(
            item: b,
            tags: [
              fixtureTag(id: 'wb', itemId: 'b', dimension: 'who', value: 'Ada'),
            ],
          ),
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('library-filter')), 'Ada');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('item-row-b')), findsOneWidget);
    expect(find.byKey(const Key('item-row-a')), findsNothing);
  });

  testWidgets('sort header reorders by who', (tester) async {
    final a = fixtureItem(id: 'a', processingStatus: ProcessingStatus.tagged);
    final b = fixtureItem(id: 'b', processingStatus: ProcessingStatus.tagged);
    await _pumpLibrary(
      tester,
      items: FakeItemsRepository(
        items: [a, b],
        knowledgeByItemId: {
          'a': fixtureKnowledge(
            item: a,
            tags: [
              fixtureTag(id: 'wa', itemId: 'a', dimension: 'who', value: 'Zoe'),
            ],
          ),
          'b': fixtureKnowledge(
            item: b,
            tags: [
              fixtureTag(id: 'wb', itemId: 'b', dimension: 'who', value: 'Ann'),
            ],
          ),
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sort-header-who')));
    await tester.pumpAndSettle();

    final rows = find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('item-row-'),
    );
    expect(rows, findsNWidgets(2));
    // First visible row after asc sort should be Ann (b).
    final firstRow = tester.widgetList(rows).first;
    expect((firstRow.key! as ValueKey<String>).value, 'item-row-b');
  });

  testWidgets('sort header cycles to none on third click', (tester) async {
    final a = fixtureItem(id: 'a', processingStatus: ProcessingStatus.tagged);
    final b = fixtureItem(id: 'b', processingStatus: ProcessingStatus.tagged);
    await _pumpLibrary(
      tester,
      items: FakeItemsRepository(
        items: [a, b],
        knowledgeByItemId: {
          'a': fixtureKnowledge(
            item: a,
            tags: [
              fixtureTag(id: 'wa', itemId: 'a', dimension: 'who', value: 'Zoe'),
            ],
          ),
          'b': fixtureKnowledge(
            item: b,
            tags: [
              fixtureTag(id: 'wb', itemId: 'b', dimension: 'who', value: 'Ann'),
            ],
          ),
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    final header = find.byKey(const Key('sort-header-who'));
    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_upward), findsWidgets);
    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_downward), findsWidgets);
    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_upward), findsNothing);
    expect(find.byIcon(Icons.arrow_downward), findsNothing);
  });

  testWidgets('comment column renders item-level comments', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final item = fixtureItem(
      id: 'item_c',
      processingStatus: ProcessingStatus.tagged,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._sessionOverrides(
            items: FakeItemsRepository(
              items: [item],
              knowledgeByItemId: {item.id: fixtureKnowledge(item: item)},
            ),
          ),
          commentsRepositoryProvider.overrideWithValue(
            FakeCommentsRepository(
              comments: [
                fixtureComment(id: 'c1', itemId: 'item_c', body: 'beach trip'),
              ],
            ),
          ),
        ],
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sort-header-comment')), findsOneWidget);
    expect(find.byKey(const Key('item-comment-item_c')), findsOneWidget);
    expect(find.text('beach trip'), findsOneWidget);
  });

  testWidgets('foreign item id surfaces not-found without leaking data (R10)',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          itemsRepositoryProvider.overrideWithValue(
            FakeItemsRepository(
              getItemError: ApiException(statusCode: 404, message: 'Not found'),
            ),
          ),
          jobsRepositoryProvider.overrideWithValue(
            FakeJobsRepository(itemId: 'foreign-id'),
          ),
          usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
        ],
        child: const MaterialApp(
          home: ItemDetailPage(itemId: 'foreign-id'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('item-detail-not-found')), findsOneWidget);
    expect(find.textContaining('foreign-id'), findsNothing);
    expect(find.byKey(const Key('item-detail')), findsNothing);
  });

  testWidgets('account A fixture is not shown under account B session (R10)',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Second fake account only sees its own empty library — never A's items.
    await tester.pumpWidget(
      ProviderScope(
        overrides: _sessionOverrides(
          items: FakeItemsRepository(),
          accountId: 'acc_b',
          token: 'tok-b',
        ),
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('items-empty')), findsOneWidget);
    expect(find.byKey(const Key('item-row-item_a')), findsNothing);
    expect(find.text('acc_b@example.com'), findsOneWidget);
  });

  testWidgets('list error shows retry', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: _sessionOverrides(
          items: FakeItemsRepository(
            listError: ApiException(statusCode: 500, message: 'boom'),
          ),
        ),
        child: const MaterialApp(
          home: AuthShell(signedInHome: ItemsListPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('items-error')), findsOneWidget);
    expect(find.byKey(const Key('items-retry')), findsOneWidget);
  });

  testWidgets('list delete confirms and removes row via API', (tester) async {
    final item = fixtureItem(id: 'item_list_del');
    final items = FakeItemsRepository(items: [item]);
    final jobs = FakeJobsRepository(
      itemId: 'item_list_del',
      item: item,
      onDelete: items.removeItem,
    );
    await _pumpLibrary(tester, items: items, jobs: jobs);
    expect(find.byKey(const Key('item-row-item_list_del')), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('item-list-delete-item_list_del')),
    );
    await tester.tap(find.byKey(const Key('item-list-delete-item_list_del')));
    await tester.pumpAndSettle();
    expect(find.text('Delete item?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('delete-confirm')));
    await tester.pumpAndSettle();

    expect(jobs.deletedItemIds, ['item_list_del']);
    expect(find.byKey(const Key('item-row-item_list_del')), findsNothing);
    expect(find.byKey(const Key('items-empty')), findsOneWidget);
  });
}
