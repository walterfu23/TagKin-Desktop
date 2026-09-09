import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/ingest/folder_ingest_queue.dart';
import 'package:tagkin_desktop/ingest/folder_ingest_status_banner.dart';
import 'package:tagkin_desktop/ingest/media_enumerator.dart';
import 'package:tagkin_desktop/library/folder_remove_queue.dart';
import 'package:tagkin_desktop/persons/collection.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/persons/collections_store.dart';

import 'fake_items_repository.dart';
import 'fake_jobs_repository.dart';

void main() {
  testWidgets(
    'ingest banner hides Collection1 jobs after File New Collection2',
    (tester) async {
      final store = MemoryCollectionsStore(
        const CollectionsFile(
          collections: [
            Collection(
              id: 'c1',
              name: 'First',
              leafFolders: ['/albums/Old'],
            ),
          ],
          currentCollectionId: 'c1',
        ),
      );
      CollectionsController? cols;
      final hold = Completer<List<MediaCandidate>>();
      final ingest = FolderIngestQueue(
        itemsRepository: FakeItemsRepository(),
        jobsRepository: FakeJobsRepository(),
        isUsageBlocked: () => false,
        currentCollectionId: () {
          final c = cols;
          return c != null && c.sessionReady ? c.current.id : null;
        },
        enumerateFolder: (_) => hold.future,
        contentHasher: (path) async => 'hash-$path',
        perceptualHasher: (path) async => null,
        physicalMemoryBytes: () async => 16 * 1024 * 1024 * 1024,
      );
      final remove = FolderRemoveQueue(
        jobsRepository: FakeJobsRepository(),
        removeBookmark: (_) async {},
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectionsStoreProvider.overrideWithValue(store),
            folderIngestQueueProvider.overrideWith((ref) => ingest),
            folderRemoveQueueProvider.overrideWith((ref) => remove),
          ],
          child: const MaterialApp(
            home: Scaffold(body: FolderIngestStatusBanner()),
          ),
        ),
      );
      await tester.pump();

      final c = ProviderScope.containerOf(
        tester.element(find.byType(FolderIngestStatusBanner)),
      ).read(collectionsControllerProvider);
      cols = c;
      if (!c.loaded) await c.load();
      expect(await c.open('c1'), isTrue);

      expect(
        await ingest.enqueue('/albums/Old'),
        FolderIngestEnqueueResult.started,
      );
      await tester.pump();
      expect(find.byKey(const Key('folder-ingest-status-banner')), findsOneWidget);
      expect(find.text('Loading 1 folder…'), findsOneWidget);

      expect(await c.create(name: 'Second'), isTrue);
      await tester.pump();
      expect(find.byKey(const Key('folder-ingest-status-banner')), findsNothing);

      expect(await c.open('c1'), isTrue);
      await tester.pump();
      expect(find.byKey(const Key('folder-ingest-status-banner')), findsOneWidget);
      expect(find.text('Loading 1 folder…'), findsOneWidget);

      hold.complete(const []);
      for (var i = 0; i < 80 && ingest.hasActiveJobs; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    },
  );
}
