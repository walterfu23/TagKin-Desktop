import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/library_membership_sync.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/persons/collection.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/persons/collections_store.dart';

import 'fake_comments_repository.dart';
import 'fake_items_repository.dart';

void main() {
  test('publish adopts pending leaf even when table statusFilter is tagged',
      () async {
    final items = FakeItemsRepository(
      items: [
        fixtureItem(
          id: 'a1',
          sourceRef: 'file:///albums/Alpha/1.jpg',
          processingStatus: ProcessingStatus.tagged,
          contentHash: 'h1',
        ),
        fixtureItem(
          id: 'b1',
          sourceRef: 'file:///albums/Beta/1.jpg',
          processingStatus: ProcessingStatus.pending,
          contentHash: 'h2',
        ),
      ],
    );
    final store = MemoryCollectionsStore(
      const CollectionsFile(
        collections: [
          Collection(
            id: 'c1',
            name: 'Grow',
            leafFolders: ['/albums/Alpha'],
          ),
        ],
        currentCollectionId: 'c1',
      ),
    );
    final cols = CollectionsController(store: store);
    await cols.load();
    expect(await cols.open('c1'), isTrue);

    final table = LibraryTableController(
      itemsRepository: items,
      commentsRepository: FakeCommentsRepository(),
    );
    table.statusFilter = ProcessingStatus.tagged;
    await table.load();
    expect(
      table.allRows.map((r) => r.item.id),
      ['a1'],
    );

    await publishCollectionMembershipFromLibrary(
      items: items,
      cols: cols,
      table: table,
    );

    expect(
      cols.current.leafFolders.toSet(),
      containsAll(['/albums/Alpha', '/albums/Beta']),
    );
    expect(
      table.collectionLeafFolders,
      containsAll(['/albums/Alpha', '/albums/Beta']),
    );
    // Pending Beta is still filtered from the table view, but load ran.
    expect(table.hasLoadedOnce, isTrue);
  });

  test('publish does not shrink membership when leaf missing from filter',
      () async {
    final items = FakeItemsRepository(
      items: [
        fixtureItem(
          id: 'a1',
          sourceRef: 'file:///albums/Alpha/1.jpg',
          processingStatus: ProcessingStatus.tagged,
          contentHash: 'h1',
        ),
      ],
    );
    final store = MemoryCollectionsStore(
      const CollectionsFile(
        collections: [
          Collection(
            id: 'c1',
            name: 'Grow',
            leafFolders: ['/albums/Alpha', '/albums/Beta'],
          ),
        ],
        currentCollectionId: 'c1',
      ),
    );
    final cols = CollectionsController(store: store);
    await cols.load();
    expect(await cols.open('c1'), isTrue);

    final table = LibraryTableController(
      itemsRepository: items,
      commentsRepository: FakeCommentsRepository(),
    );
    await publishCollectionMembershipFromLibrary(
      items: items,
      cols: cols,
      table: table,
    );

    expect(
      cols.current.leafFolders.toSet(),
      containsAll(['/albums/Alpha', '/albums/Beta']),
    );
  });

  test('publish claims leaf owned by another collection under ingest root',
      () async {
    final items = FakeItemsRepository(
      items: [
        fixtureItem(
          id: 'a1',
          sourceRef: 'file:///Users/w/test/20260506/1.jpg',
          processingStatus: ProcessingStatus.tagged,
          contentHash: 'h1',
        ),
        fixtureItem(
          id: 'b1',
          sourceRef: 'file:///Users/w/test/20260508/1.jpg',
          processingStatus: ProcessingStatus.pending,
          contentHash: 'h2',
        ),
      ],
    );
    final store = MemoryCollectionsStore(
      const CollectionsFile(
        collections: [
          Collection(
            id: 'c-other',
            name: 'Other',
            leafFolders: ['/Users/w/test/20260508'],
          ),
          Collection(
            id: 'c-open',
            name: 'Open',
            leafFolders: ['/Users/w/test/20260506'],
          ),
        ],
        currentCollectionId: 'c-open',
      ),
    );
    final cols = CollectionsController(store: store);
    await cols.load();
    expect(await cols.open('c-open'), isTrue);

    final table = LibraryTableController(
      itemsRepository: items,
      commentsRepository: FakeCommentsRepository(),
    );

    await publishCollectionMembershipFromLibrary(
      items: items,
      cols: cols,
      table: table,
      claimUnderFolder: '/Users/w/test/20260508',
    );

    expect(
      cols.current.leafFolders.toSet(),
      containsAll(['/Users/w/test/20260506', '/Users/w/test/20260508']),
    );
    expect(cols.ownerCollectionId('/Users/w/test/20260508'), 'c-open');
    expect(
      cols.catalog.collections
          .firstWhere((c) => c.id == 'c-other')
          .leafFolders,
      isNot(contains('/Users/w/test/20260508')),
    );
    expect(
      table.collectionLeafFolders,
      contains('/Users/w/test/20260508'),
    );
  });
}
