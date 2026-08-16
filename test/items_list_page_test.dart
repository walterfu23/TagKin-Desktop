import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/folder_ingest_queue.dart';
import 'package:tagkin_desktop/ingest/model_host_uploader.dart';
import 'package:tagkin_desktop/ingest/upload_controller.dart';
import 'package:tagkin_desktop/library/item_detail_page.dart';
import 'package:tagkin_desktop/library/items_list_page.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/main.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/persons/collections_store.dart';
import 'package:tagkin_desktop/persons/who_face_linker.dart';
import 'package:tagkin_desktop/prepass/prepass_controller.dart';
import 'package:tagkin_desktop/prepass/prepass_payload_builder.dart';

import 'fake_comments_repository.dart';
import 'fake_corrections_repository.dart';
import 'fake_items_repository.dart';
import 'fake_jobs_repository.dart';
import 'fake_persons_repository.dart';
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
    personsRepositoryProvider.overrideWithValue(FakePersonsRepository()),
    collectionsStoreProvider.overrideWithValue(MemoryCollectionsStore()),
  ];
}

Future<void> _pumpLibrary(
  WidgetTester tester, {
  required FakeItemsRepository items,
  FakeJobsRepository? jobs,
  FakeUsageRepository? usage,
  List<Override> extraOverrides = const [],
}) async {
  // Match the wide library window so fixed table columns fit.
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ..._sessionOverrides(items: items, jobs: jobs, usage: usage),
        ...extraOverrides,
      ],
      child: const TagKinDesktopApp(),
    ),
  );
  await tester.pumpAndSettle();
}

FolderIngestQueue _continueQueue({
  required FakeItemsRepository items,
  required FakeJobsRepository jobs,
  required void Function(Item item) onItemUpdated,
}) {
  return FolderIngestQueue(
    itemsRepository: items,
    jobsRepository: jobs,
    isUsageBlocked: () => false,
    enumerateFolder: (path) async => const [],
    contentHasher: (path) async => 'hash-$path',
    perceptualHasher: (path) async => null,
    onItemUpdated: onItemUpdated,
    prePassFactory: () => PrePassController(
      itemsRepository: items,
      buildPayload: ({
        required path,
        required type,
        faceEmbedder,
        skipFaces = false,
        maxFrames = 20,
        minIntervalMs = 1000,
        maxIntervalMs = 15000,
        sceneCutThreshold = 0.3,
      }) async {
        return PrePassBuildResult(
          payload: PrePassResult(contentHash: 'hash'),
        );
      },
    ),
    uploadFactory: () => UploadController(
      itemsRepository: items,
      readBytes: (path) async => [0xFF, 0xD8, 0xFF],
      putBytes: ({
        required uploadUrl,
        required bytes,
        required mimeType,
        httpClient,
      }) async {
        return const ModelHostUploadResult(
          analysisRef: 'files/test-ref',
          rawBody: '{}',
        );
      },
    ),
    whoFaceLinkerFactory: () => WhoFaceLinker(items: items),
  );
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
    // Prefer the what-cell control — toolbar may sit above a single row.
    await tester.ensureVisible(find.byKey(const Key('item-what-item_nav')));
    await tester.tap(find.byKey(const Key('item-what-item_nav')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('item-detail')), findsOneWidget);
    expect(find.byKey(const Key('item-type')), findsOneWidget);
    expect(find.text('item_nav'), findsNothing);
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

  testWidgets('who column shows multiple names without more', (tester) async {
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
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sam'), findsWidgets);
    expect(find.textContaining('Ada'), findsWidgets);
    expect(find.byKey(const Key('item-who-more-item_who')), findsNothing);
    expect(
      tester
          .widget<Tooltip>(find.byKey(const Key('item-who-tooltip-item_who')))
          .message,
      'Sam, Ada',
    );
  });

  testWidgets('who more expands remaining names', (tester) async {
    final item = fixtureItem(
      id: 'item_who',
      processingStatus: ProcessingStatus.tagged,
    );
    const names = [
      'Bartholomew Montgomery',
      'Alexandria Wellington',
      'Maximilian Harrington',
      'Marguerite Fitzgerald',
      'Christopher Bartholomew',
      'Anastasia Montgomery',
    ];
    await _pumpLibrary(
      tester,
      items: FakeItemsRepository(
        items: [item],
        knowledgeByItemId: {
          'item_who': fixtureKnowledge(
            item: item,
            tags: [
              for (var i = 0; i < names.length; i++)
                fixtureTag(
                  id: 'w$i',
                  itemId: 'item_who',
                  dimension: 'who',
                  value: names[i],
                ),
            ],
          ),
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('item-who-more-item_who')), findsOneWidget);
    expect(
      tester
          .widget<Tooltip>(find.byKey(const Key('item-who-tooltip-item_who')))
          .message,
      names.join(', '),
    );
    await tester.tap(find.byKey(const Key('item-who-more-item_who')));
    await tester.pumpAndSettle();
    expect(find.textContaining(names.last), findsWidgets);
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

  testWidgets('shared source path group collapses and expands', (tester) async {
    const shared = '/users/w/test';
    final a = fixtureItem(
      id: 'a',
      sourceRef: 'file://$shared/a.jpg',
      processingStatus: ProcessingStatus.tagged,
    );
    final b = fixtureItem(
      id: 'b',
      sourceRef: 'file://$shared/b.jpg',
      processingStatus: ProcessingStatus.tagged,
    );
    await _pumpLibrary(
      tester,
      items: FakeItemsRepository(items: [a, b]),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('source-group-$shared')), findsOneWidget);
    expect(find.byKey(const Key('item-row-a')), findsNothing);
    expect(find.byKey(const Key('item-row-b')), findsNothing);

    await tester.tap(find.byKey(const Key('source-group-toggle-$shared')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('item-row-a')), findsOneWidget);
    expect(find.byKey(const Key('item-row-b')), findsOneWidget);
    expect(find.byKey(const Key('item-source-a')), findsOneWidget);
    expect(find.byKey(const Key('item-source-b')), findsOneWidget);
    expect(find.text('a.jpg'), findsNothing);
    expect(find.text('b.jpg'), findsNothing);
  });

  testWidgets('nested date folders show sibling folders under expanded parent',
      (tester) async {
    const root = '/users/w/test';
    final a = fixtureItem(
      id: 'a',
      sourceRef: 'file://$root/20260508/a.jpg',
      processingStatus: ProcessingStatus.tagged,
    );
    final b = fixtureItem(
      id: 'b',
      sourceRef: 'file://$root/20260508/b.jpg',
      processingStatus: ProcessingStatus.tagged,
    );
    final c = fixtureItem(
      id: 'c',
      sourceRef: 'file://$root/20260506/c.jpg',
      processingStatus: ProcessingStatus.tagged,
    );
    await _pumpLibrary(
      tester,
      items: FakeItemsRepository(items: [a, b, c]),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('source-group-$root')), findsOneWidget);
    // Sibling folder headers/rows visible under auto-expanded parent.
    expect(
      find.byKey(const Key('source-group-$root/20260508')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('item-source-c')), findsOneWidget);
    expect(find.byKey(const Key('item-row-a')), findsNothing);

    await tester.tap(
      find.byKey(const Key('source-group-toggle-$root/20260508')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('item-row-a')), findsOneWidget);
    expect(find.byKey(const Key('item-row-b')), findsOneWidget);
    expect(find.byKey(const Key('item-source-a')), findsOneWidget);
  });

  testWidgets('File column header is shown', (tester) async {
    await _pumpLibrary(
      tester,
      items: FakeItemsRepository(items: [fixtureItem(id: 'f')]),
    );
    await tester.pumpAndSettle();
    expect(find.text('File'), findsOneWidget);
    expect(find.text('Source'), findsNothing);
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

  testWidgets('list remove uses Sure? then removes row via API', (tester) async {
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
      find.byKey(const Key('item-list-remove-item_list_del')),
    );
    await tester.tap(find.byKey(const Key('item-list-remove-item_list_del')));
    await tester.pump();
    expect(find.text('Sure?'), findsOneWidget);
    expect(find.text('Delete item?'), findsNothing);

    await tester.tap(
      find.byKey(const Key('item-list-remove-confirm-item_list_del')),
    );
    await tester.pumpAndSettle();

    expect(jobs.deletedItemIds, ['item_list_del']);
    expect(find.byKey(const Key('item-row-item_list_del')), findsNothing);
    expect(find.byKey(const Key('items-empty')), findsOneWidget);
  });

  testWidgets('remove folder confirms and soft-deletes subtree items',
      (tester) async {
    const shared = '/albums/remove_me';
    final a = fixtureItem(
      id: 'a',
      sourceRef: 'file://$shared/a.jpg',
      processingStatus: ProcessingStatus.tagged,
    );
    final b = fixtureItem(
      id: 'b',
      sourceRef: 'file://$shared/nested/b.jpg',
      processingStatus: ProcessingStatus.tagged,
    );
    final keep = fixtureItem(
      id: 'keep',
      sourceRef: 'file:///other_root/c.jpg',
      processingStatus: ProcessingStatus.tagged,
    );
    final items = FakeItemsRepository(items: [a, b, keep]);
    final jobs = FakeJobsRepository(onDelete: items.removeItem);
    await _pumpLibrary(tester, items: items, jobs: jobs);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('source-group-$shared')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('source-group-remove-$shared')),
    );
    await tester.tap(find.byKey(const Key('source-group-remove-$shared')));
    await tester.pump();
    expect(find.text('Sure?'), findsOneWidget);
    expect(find.text('Remove folder?'), findsNothing);
    await tester.tap(
      find.byKey(const Key('source-group-remove-confirm-$shared')),
    );
    await tester.pump(); // enqueue + snackbar
    expect(find.byKey(const Key('folder-remove-started')), findsOneWidget);
    await tester.pumpAndSettle();

    expect(jobs.deletedItemIds.toSet(), {'a', 'b'});
    expect(find.byKey(const Key('source-group-$shared')), findsNothing);
    expect(find.byKey(const Key('item-row-keep')), findsOneWidget);
  });

  testWidgets('remove folder shows in-progress banner until deletes finish',
      (tester) async {
    const shared = '/albums/slow_remove';
    final a = fixtureItem(
      id: 'a',
      sourceRef: 'file://$shared/a.jpg',
      processingStatus: ProcessingStatus.tagged,
    );
    final b = fixtureItem(
      id: 'b',
      sourceRef: 'file://$shared/b.jpg',
      processingStatus: ProcessingStatus.tagged,
    );
    final items = FakeItemsRepository(items: [a, b]);
    final jobs = FakeJobsRepository(onDelete: items.removeItem)
      ..deleteDelay = const Duration(milliseconds: 40);
    await _pumpLibrary(tester, items: items, jobs: jobs);
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('source-group-remove-$shared')),
    );
    await tester.tap(find.byKey(const Key('source-group-remove-$shared')));
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('source-group-remove-confirm-$shared')),
    );
    await tester.pump();

    expect(find.text('Removing 1 folder…'), findsOneWidget);
    expect(find.byKey(const Key('folder-ingest-status-banner')), findsOneWidget);

    // Idle remove control replaced by spinner while active.
    expect(
      find.byKey(const Key('source-group-remove-$shared')),
      findsNothing,
    );
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    await tester.pumpAndSettle();
    expect(jobs.deletedItemIds.toSet(), {'a', 'b'});
    expect(find.text('Folder remove finished'), findsOneWidget);
  });

  testWidgets('folder Retry is hidden when no items are failed', (tester) async {
    const shared = '/albums/all_ok';
    final a = fixtureItem(
      id: 'ok_a',
      sourceRef: 'file://$shared/a.jpg',
      processingStatus: ProcessingStatus.tagged,
    );
    final b = fixtureItem(
      id: 'ok_b',
      sourceRef: 'file://$shared/b.jpg',
      processingStatus: ProcessingStatus.tagged,
    );
    await _pumpLibrary(
      tester,
      items: FakeItemsRepository(items: [a, b]),
    );
    expect(find.byKey(const Key('source-group-$shared')), findsOneWidget);
    expect(find.byKey(const Key('source-group-retry-$shared')), findsNothing);
  });

  testWidgets('folder Retry re-analyzes failed photos in that folder',
      (tester) async {
    const shared = '/albums/retry_leaf';
    final tagged = fixtureItem(
      id: 'leaf_ok',
      sourceRef: 'file://$shared/ok.jpg',
      analysisRef: 'ref_ok',
      analysisRefState: AnalysisRefState.ready,
      processingStatus: ProcessingStatus.tagged,
    );
    final failed = fixtureItem(
      id: 'leaf_fail',
      sourceRef: 'file://$shared/fail.jpg',
      analysisRef: 'ref_fail',
      analysisRefState: AnalysisRefState.ready,
      processingStatus: ProcessingStatus.failed,
    );
    final items = FakeItemsRepository(items: [tagged, failed]);
    final jobs = FakeJobsRepository(
      libraryItems: items,
      onAnalyzed: items.replaceItem,
    );
    await _pumpLibrary(tester, items: items, jobs: jobs);

    expect(
      find.byKey(const Key('source-group-retry-$shared')),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const Key('source-group-retry-$shared')),
    );
    await tester.tap(find.byKey(const Key('source-group-retry-$shared')));
    await tester.pumpAndSettle();

    expect(jobs.analyzedItemIds, ['leaf_fail']);
    expect(find.byKey(const Key('folder-retry-done')), findsOneWidget);
    expect(find.byKey(const Key('processing-status-failed')), findsNothing);
    expect(
      find.byKey(const Key('source-group-retry-$shared')),
      findsNothing,
    );
  });

  testWidgets(
      'parent folder Retry re-analyzes all nested failed photos',
      (tester) async {
    const parent = '/albums/Trip';
    final a = fixtureItem(
      id: 'trip_a',
      sourceRef: 'file://$parent/day1/a.jpg',
      analysisRef: 'ref_a',
      analysisRefState: AnalysisRefState.ready,
      processingStatus: ProcessingStatus.tagged,
    );
    final b = fixtureItem(
      id: 'trip_b',
      sourceRef: 'file://$parent/day2/b.jpg',
      analysisRef: 'ref_b',
      analysisRefState: AnalysisRefState.ready,
      processingStatus: ProcessingStatus.failed,
    );
    final items = FakeItemsRepository(items: [a, b]);
    final jobs = FakeJobsRepository(
      libraryItems: items,
      onAnalyzed: items.replaceItem,
    );
    await _pumpLibrary(tester, items: items, jobs: jobs);

    expect(
      find.byKey(const Key('source-group-retry-$parent')),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const Key('source-group-retry-$parent')),
    );
    await tester.tap(find.byKey(const Key('source-group-retry-$parent')));
    await tester.pumpAndSettle();

    expect(jobs.analyzedItemIds, ['trip_b']);
    expect(find.byKey(const Key('processing-status-failed')), findsNothing);
  });

  testWidgets(
      'folder Retry flips each failed row to tagged as that analyze finishes',
      (tester) async {
    const shared = '/albums/retry_live';
    final a = fixtureItem(
      id: 'live_a',
      sourceRef: 'file://$shared/a.jpg',
      analysisRef: 'ref_a',
      analysisRefState: AnalysisRefState.ready,
      processingStatus: ProcessingStatus.failed,
    );
    final b = fixtureItem(
      id: 'live_b',
      sourceRef: 'file://$shared/b.jpg',
      analysisRef: 'ref_b',
      analysisRefState: AnalysisRefState.ready,
      processingStatus: ProcessingStatus.failed,
    );
    final items = FakeItemsRepository(items: [a, b]);
    final jobs = FakeJobsRepository(
      libraryItems: items,
      onAnalyzed: items.replaceItem,
      analyzeDelay: const Duration(milliseconds: 40),
    );
    await _pumpLibrary(tester, items: items, jobs: jobs);

    await tester.tap(find.byKey(const Key('source-group-toggle-$shared')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('item-row-live_a')), findsOneWidget);
    expect(find.byKey(const Key('item-row-live_b')), findsOneWidget);
    expect(find.byKey(const Key('processing-status-failed')), findsNWidgets(2));

    await tester.ensureVisible(
      find.byKey(const Key('source-group-retry-$shared')),
    );
    await tester.tap(find.byKey(const Key('source-group-retry-$shared')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('processing-status-tagged')), findsOneWidget);
    expect(find.byKey(const Key('processing-status-failed')), findsOneWidget);

    await tester.pumpAndSettle();
    expect(jobs.analyzedItemIds, ['live_a', 'live_b']);
    expect(find.byKey(const Key('processing-status-failed')), findsNothing);
    expect(find.byKey(const Key('processing-status-tagged')), findsNWidgets(2));
  });

  testWidgets(
      'folder Retry credit reject shows banner and snackbar without retrying',
      (tester) async {
    const shared = '/albums/retry_credits';
    final tagged = fixtureItem(
      id: 'credit_ok',
      sourceRef: 'file://$shared/ok.jpg',
      analysisRef: 'ref_ok',
      analysisRefState: AnalysisRefState.ready,
      processingStatus: ProcessingStatus.tagged,
    );
    final failed = fixtureItem(
      id: 'credit_fail',
      sourceRef: 'file://$shared/fail.jpg',
      analysisRef: 'ref_fail',
      analysisRefState: AnalysisRefState.ready,
      processingStatus: ProcessingStatus.failed,
    );
    final items = FakeItemsRepository(items: [tagged, failed]);
    final jobs = FakeJobsRepository(
      libraryItems: items,
      analyzeError: ApiException(
        statusCode: 409,
        code: 'insufficientCredits',
        message: 'Not enough credits for this analysis',
      ),
    );
    await _pumpLibrary(
      tester,
      items: items,
      jobs: jobs,
      usage: FakeUsageRepository(
        summary: fixtureUsageSummary(
          creditAdmission: true,
          remainingCredits: 40,
          lowCreditWarning: true,
        ),
      ),
    );

    await tester.ensureVisible(
      find.byKey(const Key('source-group-retry-$shared')),
    );
    await tester.tap(find.byKey(const Key('source-group-retry-$shared')));
    await tester.pumpAndSettle();

    expect(jobs.analyzeCallCount, 1);
    expect(find.byKey(const Key('folder-retry-credits')), findsOneWidget);
    expect(find.text('Not enough credits for this analysis'), findsWidgets);
    expect(
      find.byKey(const Key('usage-banner-insufficient-credits')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('folder-retry-done')), findsNothing);
  });

  testWidgets(
      'folder ingest continue flips each pending row to tagged as analyze finishes',
      (tester) async {
    const shared = '/albums/live_ingest';
    final a = fixtureItem(
      id: 'ing_a',
      sourceRef: 'file://$shared/a.jpg',
      processingStatus: ProcessingStatus.pending,
    );
    final b = fixtureItem(
      id: 'ing_b',
      sourceRef: 'file://$shared/b.jpg',
      processingStatus: ProcessingStatus.pending,
    );
    final items = FakeItemsRepository(items: [a, b]);
    final jobs = FakeJobsRepository(
      libraryItems: items,
      onAnalyzed: items.replaceItem,
      analyzeDelay: const Duration(milliseconds: 40),
    );

    final table = LibraryTableController(
      itemsRepository: items,
      commentsRepository: FakeCommentsRepository(),
      knowledgeConcurrency: 1,
    );

    await _pumpLibrary(
      tester,
      items: items,
      jobs: jobs,
      extraOverrides: [
        libraryTableControllerProvider.overrideWith((ref) => table),
        folderIngestQueueProvider.overrideWith((ref) {
          return _continueQueue(
            items: items,
            jobs: jobs,
            onItemUpdated: table.adoptItem,
          );
        }),
      ],
    );

    await tester.tap(find.byKey(const Key('source-group-toggle-$shared')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('item-row-ing_a')), findsOneWidget);
    expect(find.byKey(const Key('item-row-ing_b')), findsOneWidget);
    expect(find.byKey(const Key('processing-status-pending')), findsNWidgets(2));

    final ctx = tester.element(find.byType(ItemsListPage));
    final queue = ProviderScope.containerOf(ctx).read(folderIngestQueueProvider);
    await queue.restoreIncompleteFromLibrary();
    expect(queue.jobs, isNotEmpty);
    expect(queue.jobs.single.continueExistingOnly, isTrue);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      table.allRows
          .where((r) => r.item.processingStatus == ProcessingStatus.tagged)
          .length,
      1,
    );
    expect(queue.hasActiveJobs, isTrue);
    expect(find.byKey(const Key('processing-status-tagged')), findsOneWidget);
    expect(find.byKey(const Key('processing-status-pending')), findsOneWidget);

    await tester.pumpAndSettle();
    expect(jobs.analyzedItemIds, ['ing_a', 'ing_b']);
    expect(find.byKey(const Key('processing-status-pending')), findsNothing);
    expect(find.byKey(const Key('processing-status-tagged')), findsNWidgets(2));
  });
}
