import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/persons/collection.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/persons/collections_store.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tagkin_collections_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('CollectionsStore', () {
    test('missing file → empty catalog', () async {
      final store = CollectionsStore(supportDir: tempDir);
      expect(await store.load(), CollectionsFile.empty);
    });

    test('round-trips catalog with recents', () async {
      final store = CollectionsStore(supportDir: tempDir);
      const catalog = CollectionsFile(
        collections: [
          Collection(
            id: 'collection_1',
            name: 'Europe',
            leafFolders: ['/albums/Paris', '/albums/Rome'],
          ),
        ],
        currentCollectionId: 'collection_1',
        recentCollectionIds: ['collection_1'],
      );
      await store.save(catalog);
      expect(await store.load(), catalog);
    });

    test('round-trips saved views', () async {
      final store = CollectionsStore(supportDir: tempDir);
      const catalog = CollectionsFile(
        collections: [
          Collection(
            id: 'collection_1',
            name: 'Europe',
            leafFolders: ['/albums/Paris'],
            views: [
              SavedView(
                id: 'view_1',
                name: 'Ada',
                description: 'Ada photos',
                filters: LibraryViewFilters(
                  filterQuery: 'Ada',
                  whoNames: ['Ada'],
                  whoMatchAll: true,
                  hiddenItemsFilter: 'both',
                  hideBlurryPhotos: true,
                  hiddenFolders: ['/albums/Paris'],
                ),
              ),
            ],
            recentViewIds: ['view_1'],
          ),
        ],
        currentCollectionId: 'collection_1',
      );
      await store.save(catalog);
      expect(await store.load(), catalog);
    });
  });

  group('CollectionsController', () {
    late CollectionsController controller;

    setUp(() async {
      controller = CollectionsController(
        store: CollectionsStore(supportDir: tempDir),
      );
      await controller.load();
    });

    test('empty catalog bootstrap mints Collection1', () async {
      final ready = await controller.bootstrapSession(['/a', '/b']);
      expect(ready, isTrue);
      expect(controller.sessionReady, isTrue);
      expect(controller.current.name, 'Collection1');
      expect(controller.current.leafFolders, ['/a', '/b']);
      expect(controller.collections, hasLength(1));
      expect(controller.dirty, isFalse);
    });

    test('duplicate Collection1 name rejected on create', () async {
      await controller.create(name: 'Collection1', seedFolders: ['/x']);
      expect(await controller.create(name: 'Collection1'), isFalse);
    });

    test('bootstrap resumes currentCollectionId', () async {
      await controller.create(name: 'Europe', seedFolders: ['/a']);
      final id = controller.current.id;
      await controller.load();
      expect(controller.sessionReady, isFalse);
      expect(await controller.bootstrapSession(['/a']), isTrue);
      expect(controller.sessionReady, isTrue);
      expect(controller.current.id, id);
      expect(controller.current.name, 'Europe');
    });

    test('bootstrap returns false when currentCollectionId missing', () async {
      await controller.create(name: 'Europe', seedFolders: ['/a']);
      final store = CollectionsStore(supportDir: tempDir);
      await store.save(controller.catalog.copyWith(clearCurrent: true));
      await controller.load();
      expect(controller.collections, hasLength(1));
      expect(await controller.bootstrapSession(['/a']), isFalse);
      expect(controller.sessionReady, isFalse);
      expect(await controller.open(controller.collections.single.id), isTrue);
      expect(controller.sessionReady, isTrue);
    });

    test('bootstrap returns false when currentCollectionId is stale', () async {
      await controller.create(name: 'Europe', seedFolders: ['/a']);
      final store = CollectionsStore(supportDir: tempDir);
      await store.save(
        controller.catalog.copyWith(currentCollectionId: 'missing_id'),
      );
      await controller.load();
      expect(await controller.bootstrapSession(['/a']), isFalse);
      expect(controller.sessionReady, isFalse);
    });

    test('clearSession then bootstrap resumes from disk', () async {
      await controller.create(name: 'Europe', seedFolders: ['/a']);
      final id = controller.current.id;
      controller.clearSession();
      expect(controller.sessionReady, isFalse);
      expect(controller.collections, hasLength(1));
      expect(await controller.bootstrapSession(['/a']), isTrue);
      expect(controller.current.id, id);
      expect(controller.current.name, 'Europe');
    });

    test('saveAs starts empty membership and switches current', () async {
      await controller.bootstrapSession(['/a', '/b']);
      controller.removeFolder('/b');
      expect(controller.dirty, isTrue);
      expect(await controller.saveAs('Europe'), isTrue);
      expect(controller.current.name, 'Europe');
      expect(controller.current.leafFolders, isEmpty);
      expect(controller.dirty, isFalse);
      expect(
        controller.collections.map((c) => c.name),
        containsAll(['Collection1', 'Europe']),
      );
      // Source collection still owns /a.
      expect(controller.ownerCollectionId('/a'), isNot(controller.current.id));
    });

    test('minted ids are UUID v4 shaped', () async {
      await controller.bootstrapSession(['/a']);
      final id = controller.current.id;
      expect(
        id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            caseSensitive: false,
          ),
        ),
      );
      expect(await controller.create(name: 'Other'), isTrue);
      expect(controller.current.id, isNot(id));
      expect(
        controller.current.id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            caseSensitive: false,
          ),
        ),
      );
    });

    test(
      'create without seed starts empty; cannot steal owned folders',
      () async {
        await controller.create(name: 'Trip', seedFolders: ['/a']);
        expect(await controller.create(name: 'Other'), isTrue);
        expect(controller.current.leafFolders, isEmpty);
        expect(controller.addFolder('/a'), isFalse);
        expect(controller.current.leafFolders, isEmpty);
        expect(controller.addFolder('/b'), isTrue);
        expect(controller.current.leafFolders, ['/b']);
      },
    );

    test(
      'claimFoldersFor writes origin collection while another is open',
      () async {
        await controller.create(name: 'First', seedFolders: ['/old']);
        final firstId = controller.current.id;
        expect(await controller.create(name: 'Second'), isTrue);
        expect(controller.current.leafFolders, isEmpty);
        expect(
          await controller.claimFoldersFor(firstId, ['/old', '/also']),
          isTrue,
        );
        expect(controller.current.name, 'Second');
        expect(controller.current.leafFolders, isEmpty);
        expect(
          controller.catalog.collections
              .firstWhere((c) => c.id == firstId)
              .leafFolders
              .toSet(),
          {'/old', '/also'},
        );
      },
    );

    test(
      'create seedFolders skips paths owned by another collection',
      () async {
        await controller.create(name: 'Trip', seedFolders: ['/a']);
        expect(
          await controller.create(name: 'Other', seedFolders: ['/a', '/b']),
          isTrue,
        );
        expect(controller.current.leafFolders, ['/b']);
      },
    );

    test('create → open restores folders; touches recents', () async {
      await controller.create(name: 'Trip', seedFolders: ['/albums/Paris']);
      controller.addFolder('/albums/Rome');
      await controller.save();
      final id = controller.current.id;
      await controller.create(name: 'Other');
      expect(await controller.open(id), isTrue);
      expect(controller.current.leafFolders, ['/albums/Paris', '/albums/Rome']);
      expect(controller.recentCollections.first.id, id);
    });

    test('duplicate name create rejected', () async {
      await controller.create(name: 'Trip');
      expect(await controller.create(name: 'trip'), isFalse);
    });

    test('markDirty sets chrome asterisk; no-op when not ready', () async {
      controller.markDirty();
      expect(controller.dirty, isFalse);
      await controller.bootstrapSession(['/a']);
      expect(controller.dirty, isFalse);
      expect(controller.chromeLabel, 'Collection1');
      controller.markDirty();
      expect(controller.dirty, isTrue);
      expect(controller.chromeLabel, 'Collection1*');
      controller.markDirty();
      expect(controller.dirty, isTrue);
      await controller.save();
      expect(controller.dirty, isFalse);
      expect(controller.chromeLabel, 'Collection1');
    });

    test(
      'Faces folder look dirties; reverting to saved clears dirty',
      () async {
        await controller.bootstrapSession(['/a', '/b']);
        controller.updateFacesLook(leafFolder: '/a');
        await controller.save();
        expect(controller.dirty, isFalse);
        controller.updateFacesLook(leafFolder: '/b');
        expect(controller.dirty, isTrue);
        expect(controller.current.ui.faces.leafFolder, '/b');
        controller.updateFacesLook(leafFolder: '/a');
        expect(controller.dirty, isFalse);
        expect(controller.chromeLabel, 'Collection1');
      },
    );

    test('library look round-trips on save/open', () async {
      await controller.bootstrapSession(['/a']);
      controller.updateLibraryLook(
        const CollectionLibraryUi(
          filterQuery: 'beach',
          sortKeys: [CollectionSortKey('who', ascending: false)],
          expandedDirs: ['/albums'],
        ),
      );
      expect(controller.dirty, isTrue);
      await controller.save();
      final id = controller.current.id;
      await controller.create(name: 'Other', seedFolders: ['/x']);
      expect(await controller.open(id), isTrue);
      expect(controller.current.ui.library.filterQuery, 'beach');
      expect(controller.current.ui.library.sortKeys.single.column, 'who');
      expect(controller.dirty, isFalse);
    });

    test('adoptLibraryLook updates baseline without dirtying', () async {
      await controller.bootstrapSession(['/a']);
      expect(controller.dirty, isFalse);
      controller.adoptLibraryLook(
        const CollectionLibraryUi(expandedDirs: ['/albums']),
      );
      expect(controller.dirty, isFalse);
      expect(controller.current.ui.library.expandedDirs, ['/albums']);
      controller.updateLibraryLook(
        const CollectionLibraryUi(expandedDirs: ['/albums', '/other']),
      );
      expect(controller.dirty, isTrue);
    });

    test(
      'addFolder on new library path dirties; removeFolder stays off membership',
      () async {
        await controller.create(name: 'Trip', seedFolders: ['/a']);
        expect(controller.dirty, isFalse);
        expect(controller.addFolder('/b'), isTrue);
        expect(controller.dirty, isTrue);
        expect(controller.current.leafFolders, ['/a', '/b']);
        await controller.save();
        expect(controller.removeFolder('/b'), isTrue);
        expect(controller.dirty, isTrue);
        expect(controller.current.leafFolders, ['/a']);
        // Intentional remove: folder still in library does not get re-added by
        // addFolder when already considered (caller must only add *new* paths).
        expect(controller.addFolder('/a'), isTrue);
        expect(controller.current.leafFolders, ['/a']);
      },
    );

    test(
      'adoptUnownedFolders batches new leaves; skips other-owned; one dirty',
      () async {
        await controller.create(name: 'Trip', seedFolders: ['/a']);
        final tripId = controller.current.id;
        expect(
          await controller.create(name: 'Other', seedFolders: ['/owned']),
          isTrue,
        );
        expect(await controller.open(tripId), isTrue);
        expect(controller.dirty, isFalse);
        var notifies = 0;
        controller.addListener(() => notifies++);
        expect(
          controller.adoptUnownedFolders(['/a', '/b', '/c', '/owned', '']),
          isTrue,
        );
        expect(controller.current.leafFolders, ['/a', '/b', '/c']);
        expect(controller.dirty, isTrue);
        expect(notifies, 1);
        expect(controller.adoptUnownedFolders(['/b', '/c']), isFalse);
        expect(notifies, 1);
      },
    );

    test(
      'adoptUnownedFolders treats slash and backslash as the same leaf',
      () async {
        await controller.create(
          name: 'Trip',
          seedFolders: ['/albums/Trip/Alpha'],
        );
        expect(
          controller.adoptUnownedFolders([
            r'\albums\Trip\Alpha',
            r'\albums\Trip\Beta',
          ]),
          isTrue,
        );
        expect(controller.current.leafFolders.toSet(), {
          '/albums/Trip/Alpha',
          '/albums/Trip/Beta',
        });
      },
    );

    test(
      'claimFoldersForCurrent does not steal without stealFolders',
      () async {
        await controller.create(name: 'Trip', seedFolders: ['/a']);
        final tripId = controller.current.id;
        expect(
          await controller.create(name: 'Other', seedFolders: ['/owned']),
          isTrue,
        );
        expect(await controller.open(tripId), isTrue);
        expect(
          await controller.claimFoldersForCurrent(['/owned', '/b']),
          isTrue,
        );
        expect(controller.current.leafFolders, ['/a', '/b']);
        expect(controller.ownerCollectionId('/owned'), isNot(tripId));
        expect(
          controller.catalog.collections
              .firstWhere((c) => c.name == 'Other')
              .leafFolders,
          ['/owned'],
        );
      },
    );

    test(
      'claimFoldersForCurrent steals from other collection and persists',
      () async {
        final store = CollectionsStore(supportDir: tempDir);
        final controller = CollectionsController(store: store);
        await controller.load();
        await controller.create(name: 'Trip', seedFolders: ['/a']);
        final tripId = controller.current.id;
        expect(
          await controller.create(name: 'Other', seedFolders: ['/owned']),
          isTrue,
        );
        expect(await controller.open(tripId), isTrue);
        expect(controller.ownerCollectionId('/owned'), isNot(tripId));
        expect(
          await controller.claimFoldersForCurrent(
            ['/owned', '/b'],
            stealFolders: {'/owned'},
          ),
          isTrue,
        );
        expect(controller.current.leafFolders, ['/a', '/owned', '/b']);
        expect(controller.ownerCollectionId('/owned'), tripId);
        expect(controller.dirty, isFalse);
        final other = controller.catalog.collections.firstWhere(
          (c) => c.name == 'Other',
        );
        expect(other.leafFolders, isEmpty);
        // Survives reload.
        final reloaded = CollectionsController(store: store);
        await reloaded.load();
        expect(await reloaded.open(tripId), isTrue);
        expect(
          reloaded.current.leafFolders,
          containsAll(['/a', '/owned', '/b']),
        );
        expect(
          reloaded.catalog.collections
              .firstWhere((c) => c.name == 'Other')
              .leafFolders,
          isEmpty,
        );
      },
    );

    test('folderConflictsUnder lists nested leaves owned elsewhere', () async {
      await controller.create(name: 'Trip', seedFolders: ['/albums/Mine']);
      final tripId = controller.current.id;
      expect(
        await controller.create(
          name: 'Other',
          seedFolders: ['/albums/Trip/Day1', '/elsewhere'],
        ),
        isTrue,
      );
      expect(await controller.open(tripId), isTrue);
      final conflicts = controller.folderConflictsUnder(
        '/albums/Trip',
        exceptId: tripId,
      );
      expect(conflicts, hasLength(1));
      expect(conflicts.single.collectionName, 'Other');
      expect(conflicts.single.folders, ['/albums/Trip/Day1']);
      expect(
        controller.folderConflictsUnder('/albums/Mine', exceptId: tripId),
        isEmpty,
      );
    });

    test('removeFolders batches removals with one notify', () async {
      await controller.create(name: 'Trip', seedFolders: ['/a', '/b', '/c']);
      await controller.save();
      var notifies = 0;
      controller.addListener(() => notifies++);
      expect(controller.removeFolders(['/b', '/missing', '/c']), isTrue);
      expect(controller.current.leafFolders, ['/a']);
      expect(notifies, 1);
      expect(controller.removeFolders(['/b']), isFalse);
      expect(notifies, 1);
    });

    group('saved views', () {
      test('save / update / rename / delete', () async {
        await controller.create(name: 'Trip', seedFolders: ['/a']);
        const filters = LibraryViewFilters(filterQuery: 'Ada');
        final saved = await controller.saveView(
          name: 'Ada',
          description: 'Ada only',
          filters: filters,
        );
        expect(saved, isNotNull);
        expect(controller.views.single.name, 'Ada');
        expect(controller.views.single.description, 'Ada only');
        expect(controller.views.single.filters.filterQuery, 'Ada');
        expect(controller.dirty, isFalse);

        expect(
          await controller.updateView(
            saved!.id,
            const LibraryViewFilters(filterQuery: 'Sam'),
          ),
          isTrue,
        );
        expect(controller.viewById(saved.id)!.filters.filterQuery, 'Sam');

        expect(
          await controller.renameView(
            saved.id,
            name: 'Sam',
            description: 'Sam only',
          ),
          isTrue,
        );
        expect(controller.viewById(saved.id)!.name, 'Sam');
        expect(controller.viewById(saved.id)!.description, 'Sam only');

        expect(await controller.deleteView(saved.id), isTrue);
        expect(controller.views, isEmpty);
      });

      test('recentViews is MRU capped; all views remain', () async {
        final capped = CollectionsController(
          store: CollectionsStore(supportDir: tempDir),
          maxRecentViews: () => 2,
        );
        await capped.load();
        await capped.create(name: 'Trip', seedFolders: ['/a']);
        final a = await capped.saveView(
          name: 'A',
          filters: const LibraryViewFilters(filterQuery: 'a'),
        );
        final b = await capped.saveView(
          name: 'B',
          filters: const LibraryViewFilters(filterQuery: 'b'),
        );
        final c = await capped.saveView(
          name: 'C',
          filters: const LibraryViewFilters(filterQuery: 'c'),
        );
        expect(capped.views, hasLength(3));
        expect(capped.recentViews.map((v) => v.id), [c!.id, b!.id]);
        expect(capped.recentViews.map((v) => v.id), isNot(contains(a!.id)));
      });

      test('saving a view does not dirty or flush unsaved rename', () async {
        await controller.create(name: 'Trip', seedFolders: ['/a']);
        expect(controller.rename('TripDirty'), isTrue);
        expect(controller.dirty, isTrue);
        await controller.saveView(
          name: 'Ada',
          filters: const LibraryViewFilters(filterQuery: 'Ada'),
        );
        expect(controller.dirty, isTrue);
        expect(controller.current.name, 'TripDirty');
        expect(controller.views, hasLength(1));
        final disk = await CollectionsStore(supportDir: tempDir).load();
        expect(disk.collections.single.name, 'Trip');
        expect(disk.collections.single.views, hasLength(1));
        expect(disk.collections.single.views.single.name, 'Ada');
      });

      test('nextDefaultViewName skips taken ViewNN', () async {
        await controller.create(name: 'Trip', seedFolders: ['/a']);
        expect(controller.nextDefaultViewName(), 'View01');
        await controller.saveView(
          name: 'View01',
          filters: LibraryViewFilters.all,
        );
        expect(controller.nextDefaultViewName(), 'View02');
        await controller.saveView(
          name: 'view02',
          filters: const LibraryViewFilters(filterQuery: 'x'),
        );
        expect(controller.nextDefaultViewName(), 'View03');
      });

      test('hiddenFolders round-trips on a saved view', () async {
        await controller.create(name: 'Trip', seedFolders: ['/a']);
        const filters = LibraryViewFilters(hiddenFolders: ['/albums/Trip']);
        final saved = await controller.saveView(
          name: 'No trip',
          filters: filters,
        );
        expect(saved!.filters.hiddenFolders, ['/albums/Trip']);
        final disk = await CollectionsStore(supportDir: tempDir).load();
        expect(disk.collections.single.views.single.filters.hiddenFolders, [
          '/albums/Trip',
        ]);
      });

      test('hiddenItemIds round-trips on a saved view', () async {
        await controller.create(name: 'Trip', seedFolders: ['/a']);
        const filters = LibraryViewFilters(hiddenItemIds: ['item_a']);
        final saved = await controller.saveView(
          name: 'No a',
          filters: filters,
        );
        expect(saved!.filters.hiddenItemIds, ['item_a']);
        final disk = await CollectionsStore(supportDir: tempDir).load();
        expect(disk.collections.single.views.single.filters.hiddenItemIds, [
          'item_a',
        ]);
      });
    });
  });
}
