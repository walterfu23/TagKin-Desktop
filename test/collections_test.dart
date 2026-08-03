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

    test('saveAs copies membership and switches current', () async {
      await controller.bootstrapSession(['/a', '/b']);
      controller.removeFolder('/b');
      expect(controller.dirty, isTrue);
      expect(await controller.saveAs('Europe'), isTrue);
      expect(controller.current.name, 'Europe');
      expect(controller.current.leafFolders, ['/a']);
      expect(controller.dirty, isFalse);
      expect(controller.collections.map((c) => c.name), containsAll(['Collection1', 'Europe']));
    });

    test('create → open restores folders; touches recents', () async {
      await controller.create(name: 'Trip', seedFolders: ['/albums/Paris']);
      controller.addFolder('/albums/Rome');
      await controller.save();
      final id = controller.current.id;
      await controller.create(name: 'Other');
      expect(await controller.open(id), isTrue);
      expect(controller.current.leafFolders, [
        '/albums/Paris',
        '/albums/Rome',
      ]);
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

    test('Faces folder look dirties; reverting to saved clears dirty', () async {
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
    });

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

    test('addFolder on new library path dirties; removeFolder stays off membership',
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
    });
  });
}
