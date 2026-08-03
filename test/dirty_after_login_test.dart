// Repro/regression coverage for: the freshly-minted collection is marked
// dirty immediately after login, before any user edit. Root cause: the
// Folders auto-expand-sibling-folders baseline is captured before the
// library table has loaded any rows (ItemsListPage.load() runs in a later
// postFrameCallback than the shell's UI-restore), so the later real
// auto-expand (once items arrive) diffs against a stale empty baseline.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/main.dart';
import 'package:tagkin_desktop/persons/collection.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/persons/collections_store.dart';

import 'fake_items_repository.dart';
import 'fake_jobs_repository.dart';
import 'fake_persons_repository.dart';
import 'fake_usage_repository.dart';

Account _account(String id) => Account(
      id: id,
      email: '$id@example.com',
      createdAt: '2026-07-18T00:00:00.000Z',
    );

void main() {
  testWidgets(
      'fresh login with a multi-folder library does not mark the collection dirty',
      (tester) async {
    // Two sibling subfolders under a common parent -> triggers Folders
    // auto-expand-sibling-folder-parents once items load.
    final items = [
      fixtureItem(id: 'a1', sourceRef: 'file:///albums/Trip/Alpha/1.jpg'),
      fixtureItem(id: 'b1', sourceRef: 'file:///albums/Trip/Beta/1.jpg'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          testSessionProvider.overrideWithValue(
            TestSession(token: 'tok', account: _account('acc_1')),
          ),
          itemsRepositoryProvider.overrideWithValue(
            FakeItemsRepository(items: items),
          ),
          usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
          jobsRepositoryProvider.overrideWithValue(FakeJobsRepository()),
          personsRepositoryProvider.overrideWithValue(FakePersonsRepository()),
          collectionsStoreProvider.overrideWithValue(MemoryCollectionsStore()),
        ],
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-collection-label')), findsOneWidget);
    expect(
      find.textContaining('*'),
      findsNothing,
      reason: 'Collection marked dirty right after login with no user edits',
    );
  });

  testWidgets(
      'reopening an existing collection with already-matching folders stays clean',
      (tester) async {
    // Unlike the first-run mint above, leafFolders already matches the
    // library, so CollectionsController.fillMembershipIfEmpty (which
    // happens to re-baseline as a side effect) never runs — this is the
    // scenario that would NOT self-heal if the Folders-look baseline is
    // captured before the library table has loaded real rows.
    final items = [
      fixtureItem(id: 'a1', sourceRef: 'file:///albums/Trip/Alpha/1.jpg'),
      fixtureItem(id: 'b1', sourceRef: 'file:///albums/Trip/Beta/1.jpg'),
    ];
    final store = MemoryCollectionsStore(
      const CollectionsFile(
        collections: [
          Collection(
            id: 'c1',
            name: 'Existing',
            leafFolders: ['/albums/Trip/Alpha', '/albums/Trip/Beta'],
          ),
        ],
        currentCollectionId: 'c1',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          testSessionProvider.overrideWithValue(
            TestSession(token: 'tok', account: _account('acc_1')),
          ),
          itemsRepositoryProvider.overrideWithValue(
            FakeItemsRepository(items: items),
          ),
          usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
          jobsRepositoryProvider.overrideWithValue(FakeJobsRepository()),
          personsRepositoryProvider.overrideWithValue(FakePersonsRepository()),
          collectionsStoreProvider.overrideWithValue(store),
        ],
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Non-empty catalog -> start gate; open the existing collection
    // directly through the controller (bypassing the picker UI).
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TagKinDesktopApp)),
    );
    final opened = await container
        .read(collectionsControllerProvider)
        .open('c1');
    expect(opened, isTrue);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-collection-label')), findsOneWidget);
    expect(
      find.textContaining('*'),
      findsNothing,
      reason: 'Reopened collection marked dirty right after login',
    );
  });
}
