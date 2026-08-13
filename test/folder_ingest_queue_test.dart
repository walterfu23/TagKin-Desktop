import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/active_folder_ingest_store.dart';
import 'package:tagkin_desktop/ingest/folder_ingest_queue.dart';
import 'package:tagkin_desktop/ingest/folder_picker.dart';
import 'package:tagkin_desktop/ingest/media_enumerator.dart';
import 'package:tagkin_desktop/ingest/model_host_uploader.dart';
import 'package:tagkin_desktop/ingest/upload_controller.dart';
import 'package:tagkin_desktop/persons/who_face_linker.dart';
import 'package:tagkin_desktop/prepass/prepass_controller.dart';
import 'package:tagkin_desktop/prepass/prepass_payload_builder.dart';

import 'fake_items_repository.dart';
import 'fake_jobs_repository.dart';

MediaCandidate _photo(String path) {
  return MediaCandidate(
    path: path,
    type: ItemType.photo,
    size: 10,
    modifiedAt: DateTime(2026, 1, 1),
  );
}

FolderIngestQueue _queue({
  required FakeItemsRepository items,
  required FakeJobsRepository jobs,
  required Map<String, List<MediaCandidate>> byFolder,
  bool usageBlocked = false,
  void Function(Item item)? onItemUpdated,
  String? Function()? accountId,
  ActiveFolderIngestStore? checkpointStore,
  Future<void> Function(String folderPath)? ensureFolderAccess,
  Future<List<String>> Function()? bookmarkedFolders,
}) {
  return FolderIngestQueue(
    itemsRepository: items,
    jobsRepository: jobs,
    isUsageBlocked: () => usageBlocked,
    enumerateFolder: (path) async => byFolder[path] ?? const [],
    contentHasher: (path) async => 'hash-$path',
    perceptualHasher: (path) async => null,
    onItemUpdated: onItemUpdated,
    accountId: accountId,
    checkpointStore: checkpointStore,
    ensureFolderAccess: ensureFolderAccess,
    bookmarkedFolders: bookmarkedFolders,
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
          payload: PrePassResult(
            contentHash: 'hash',
            appearances: [
              PrePassAppearanceInput(
                embedding: List<double>.filled(512, 0.0),
                embeddingModelId: 'stub-face-embed-v1',
              ),
            ],
          ),
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
  test('processing statusLabel is Processing n of m', () {
    final job = FolderIngestJob(folderPath: '/albums/Paris');
    job.phase = FolderIngestJobPhase.processing;
    job.pipelineDone = 1;
    job.pipelineTotal = 3;
    expect(job.statusLabel, 'Processing 1 of 3…');
  });

  test('enqueue runs full chain and creates items', () async {
    final items = FakeItemsRepository();
    final jobs = FakeJobsRepository();
    final queue = _queue(
      items: items,
      jobs: jobs,
      byFolder: {
        '/albums/Paris': [_photo('/albums/Paris/a.jpg')],
      },
    );

    final result = await queue.enqueue('/albums/Paris');
    expect(result, FolderIngestEnqueueResult.started);

    await Future<void>.delayed(Duration.zero);
    for (var i = 0; i < 50 && queue.hasActiveJobs; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(queue.hasActiveJobs, isFalse);
    expect(queue.jobs.single.phase, FolderIngestJobPhase.done);
    expect(items.created, hasLength(1));
    expect(queue.libraryRefreshTick, greaterThan(0));
  });

  test('second enqueue of active path is refused', () async {
    final items = FakeItemsRepository();
    final jobs = FakeJobsRepository();
    var releaseScan = false;
    final queue = FolderIngestQueue(
      itemsRepository: items,
      jobsRepository: jobs,
      isUsageBlocked: () => false,
      enumerateFolder: (path) async {
        while (!releaseScan) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        return [_photo('$path/a.jpg')];
      },
      contentHasher: (path) async => 'hash-$path',
      perceptualHasher: (path) async => null,
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

    expect(
      await queue.enqueue('/albums/Paris'),
      FolderIngestEnqueueResult.started,
    );
    expect(
      await queue.enqueue('/albums/Paris'),
      FolderIngestEnqueueResult.alreadyActive,
    );
    expect(
      await queue.enqueue('/albums/Rome'),
      FolderIngestEnqueueResult.started,
    );
    expect(queue.activeJobCount, 2);

    releaseScan = true;
    for (var i = 0; i < 80 && queue.hasActiveJobs; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(queue.hasActiveJobs, isFalse);

    // After finish, same path can start again.
    expect(
      await queue.enqueue('/albums/Paris'),
      FolderIngestEnqueueResult.started,
    );
    for (var i = 0; i < 80 && queue.hasActiveJobs; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });

  test('isLoadingPath only during scanning and registering', () async {
    final items = FakeItemsRepository();
    final jobs = FakeJobsRepository();
    var releaseScan = false;
    final queue = FolderIngestQueue(
      itemsRepository: items,
      jobsRepository: jobs,
      isUsageBlocked: () => false,
      enumerateFolder: (path) async {
        while (!releaseScan) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        return const [];
      },
      contentHasher: (path) async => 'hash-$path',
      perceptualHasher: (path) async => null,
    );

    expect(queue.isLoadingPath('/albums/Trip'), isFalse);
    expect(
      FolderIngestQueue.hidesFacesFolder(FolderIngestJobPhase.scanning),
      isTrue,
    );
    expect(
      FolderIngestQueue.hidesFacesFolder(FolderIngestJobPhase.registering),
      isTrue,
    );
    expect(
      FolderIngestQueue.hidesFacesFolder(FolderIngestJobPhase.analyze),
      isFalse,
    );
    expect(
      FolderIngestQueue.hidesFacesFolder(FolderIngestJobPhase.processing),
      isFalse,
    );
    expect(
      FolderIngestQueue.hidesFacesFolder(FolderIngestJobPhase.prePass),
      isFalse,
    );

    await queue.enqueue('/albums');
    expect(queue.isLoadingPath('/albums'), isTrue);
    expect(queue.isLoadingPath('/albums/Trip'), isTrue);
    expect(queue.isLoadingPath('/albums/Trip/day1'), isTrue);
    expect(queue.isLoadingPath('/other'), isFalse);

    releaseScan = true;
    for (var i = 0; i < 80 && queue.hasActiveJobs; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(queue.isLoadingPath('/albums/Trip'), isFalse);
  });

  test('membership publish runs after registering', () async {
    final items = FakeItemsRepository();
    final jobs = FakeJobsRepository();
    var publishCount = 0;
    final hooked = FolderIngestQueue(
      itemsRepository: items,
      jobsRepository: jobs,
      isUsageBlocked: () => false,
      enumerateFolder: (path) async => [_photo('/albums/Paris/a.jpg')],
      contentHasher: (path) async => 'hash-$path',
      perceptualHasher: (path) async => null,
      onLibraryMembershipPublish: (_) async {
        publishCount++;
      },
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

    await hooked.enqueue('/albums/Paris');
    for (var i = 0; i < 80 && hooked.hasActiveJobs; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(publishCount, greaterThanOrEqualTo(1));
    expect(items.created, hasLength(1));
  });

  test('onItemUpdated patches tagged after each analyze before the job ends',
      () async {
    final items = FakeItemsRepository();
    final jobs = FakeJobsRepository(
      libraryItems: items,
      onAnalyzed: items.replaceItem,
      analyzeDelay: const Duration(milliseconds: 40),
    );
    final updated = <Item>[];
    final queue = _queue(
      items: items,
      jobs: jobs,
      onItemUpdated: updated.add,
      byFolder: {
        '/albums/Paris': [
          _photo('/albums/Paris/a.jpg'),
          _photo('/albums/Paris/b.jpg'),
        ],
      },
    );

    await queue.enqueue('/albums/Paris');

    var taggedCount = 0;
    for (var i = 0; i < 100; i++) {
      taggedCount = updated
          .where((it) => it.processingStatus == ProcessingStatus.tagged)
          .length;
      if (taggedCount >= 1) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(taggedCount, 1);
    expect(queue.hasActiveJobs, isTrue);
    expect(queue.jobs.single.phase, FolderIngestJobPhase.processing);
    expect(queue.jobs.single.statusLabel, contains('Processing'));
    expect(
      updated
          .where((it) => it.processingStatus == ProcessingStatus.tagged)
          .length,
      1,
    );

    for (var i = 0; i < 80 && queue.hasActiveJobs; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(queue.hasActiveJobs, isFalse);
    expect(
      updated
          .where((it) => it.processingStatus == ProcessingStatus.tagged)
          .length,
      2,
    );
  });

  test('continue-only patches tagged after each analyze before the job ends',
      () async {
    final a = fixtureItem(
      id: 'cont_a',
      sourceRef: Uri.file('/albums/Paris/a.jpg').toString(),
      processingStatus: ProcessingStatus.pending,
    );
    final b = fixtureItem(
      id: 'cont_b',
      sourceRef: Uri.file('/albums/Paris/b.jpg').toString(),
      processingStatus: ProcessingStatus.pending,
    );
    final items = FakeItemsRepository(items: [a, b]);
    final jobs = FakeJobsRepository(
      libraryItems: items,
      onAnalyzed: items.replaceItem,
      analyzeDelay: const Duration(milliseconds: 40),
    );
    final updated = <Item>[];
    final queue = _queue(
      items: items,
      jobs: jobs,
      onItemUpdated: updated.add,
      byFolder: const {},
    );

    await queue.restoreIncompleteFromLibrary();

    var taggedCount = 0;
    for (var i = 0; i < 100; i++) {
      taggedCount = updated
          .where((it) => it.processingStatus == ProcessingStatus.tagged)
          .length;
      if (taggedCount >= 1) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(taggedCount, 1);
    expect(queue.hasActiveJobs, isTrue);
    expect(queue.jobs.single.continueExistingOnly, isTrue);
    expect(queue.jobs.single.phase, FolderIngestJobPhase.processing);

    await _waitIdle(queue);
    expect(
      updated
          .where((it) => it.processingStatus == ProcessingStatus.tagged)
          .length,
      2,
    );
  });

  test('existing tagged items are not re-pipelined', () async {
    const path = '/albums/Paris/a.jpg';
    final existing = fixtureItem(
      id: 'item_1',
      sourceRef: Uri.file(path).toString(),
      processingStatus: ProcessingStatus.tagged,
      analysisRefState: AnalysisRefState.ready,
    );
    final items = FakeItemsRepository(items: [existing]);
    final jobs = FakeJobsRepository(libraryItems: items);
    final queue = _queue(
      items: items,
      jobs: jobs,
      byFolder: {
        '/albums/Paris': [_photo(path)],
      },
    );

    await queue.enqueue('/albums/Paris');
    await _waitIdle(queue);

    expect(items.created, isEmpty);
    expect(jobs.analyzedItemIds, isEmpty);
    expect(queue.jobs.single.phase, FolderIngestJobPhase.done);
    expect(queue.jobs.single.continuedCount, 0);
  });

  test('existing pending items continue through the pipeline', () async {
    const path = '/albums/Paris/a.jpg';
    final existing = fixtureItem(
      id: 'item_stuck',
      sourceRef: Uri.file(path).toString(),
      processingStatus: ProcessingStatus.pending,
      analysisRefState: AnalysisRefState.pending,
    );
    final items = FakeItemsRepository(items: [existing]);
    final jobs = FakeJobsRepository(
      libraryItems: items,
      onAnalyzed: items.replaceItem,
    );
    final queue = _queue(
      items: items,
      jobs: jobs,
      byFolder: {
        '/albums/Paris': [_photo(path)],
      },
    );

    await queue.enqueue('/albums/Paris');
    await _waitIdle(queue);

    expect(items.created, isEmpty);
    expect(jobs.analyzedItemIds, ['item_stuck']);
    expect(queue.jobs.single.continuedCount, 1);
    expect(queue.jobs.single.phase, FolderIngestJobPhase.done);
  });

  test('restoreInterrupted resumes a checkpointed pending folder', () async {
    final temp = await Directory.systemTemp.createTemp('tagkin_ingest_ckpt_');
    addTearDown(() => temp.delete(recursive: true));
    final store = ActiveFolderIngestStore(supportDir: temp);
    await store.add('acc_1', '/albums/Paris');

    const path = '/albums/Paris/a.jpg';
    final existing = fixtureItem(
      id: 'item_resume',
      sourceRef: Uri.file(path).toString(),
      processingStatus: ProcessingStatus.pending,
      analysisRefState: AnalysisRefState.pending,
    );
    final items = FakeItemsRepository(items: [existing]);
    final jobs = FakeJobsRepository(
      libraryItems: items,
      onAnalyzed: items.replaceItem,
    );
    final queue = _queue(
      items: items,
      jobs: jobs,
      accountId: () => 'acc_1',
      checkpointStore: store,
      byFolder: {
        '/albums/Paris': [_photo(path)],
      },
    );

    await queue.restoreInterrupted();
    await _waitIdle(queue);

    expect(jobs.analyzedItemIds, ['item_resume']);
    expect(items.created, isEmpty);
    expect(await store.listForAccount('acc_1'), isEmpty);
    expect(queue.jobs.single.phase, FolderIngestJobPhase.done);
  });

  test('restoreInterrupted without account id can retry after id is set',
      () async {
    final temp = await Directory.systemTemp.createTemp('tagkin_ingest_ckpt_');
    addTearDown(() => temp.delete(recursive: true));
    final store = ActiveFolderIngestStore(supportDir: temp);
    await store.add('acc_1', '/albums/Paris');

    String? id;
    const path = '/albums/Paris/a.jpg';
    final existing = fixtureItem(
      id: 'item_retry_restore',
      sourceRef: Uri.file(path).toString(),
      processingStatus: ProcessingStatus.pending,
      analysisRefState: AnalysisRefState.pending,
    );
    final items = FakeItemsRepository(items: [existing]);
    final jobs = FakeJobsRepository();
    final queue = _queue(
      items: items,
      jobs: jobs,
      byFolder: {
        '/albums/Paris': [_photo(path)],
      },
      accountId: () => id,
      checkpointStore: store,
    );

    await queue.restoreInterrupted();
    expect(queue.jobs, isEmpty);

    id = 'acc_1';
    await queue.restoreInterrupted();
    await _waitIdle(queue);

    expect(jobs.analyzedItemIds, ['item_retry_restore']);
    expect(queue.jobs.single.continuedCount, 1);
  });

  test('missing folder access fails the job and drops the checkpoint',
      () async {
    final temp = await Directory.systemTemp.createTemp('tagkin_ingest_ckpt_');
    addTearDown(() => temp.delete(recursive: true));
    final store = ActiveFolderIngestStore(supportDir: temp);
    await store.add('acc_1', '/albums/Paris');

    var enumerated = false;
    final items = FakeItemsRepository();
    final jobs = FakeJobsRepository();
    final queue = FolderIngestQueue(
      itemsRepository: items,
      jobsRepository: jobs,
      isUsageBlocked: () => false,
      enumerateFolder: (path) async {
        enumerated = true;
        return [_photo('$path/a.jpg')];
      },
      contentHasher: (path) async => 'hash-$path',
      perceptualHasher: (path) async => null,
      accountId: () => 'acc_1',
      checkpointStore: store,
      ensureFolderAccess: (_) async {
        throw FolderAccessException(
          'Add this folder again to continue ingest.',
        );
      },
    );

    await queue.restoreInterrupted();
    await _waitIdle(queue);

    expect(enumerated, isFalse);
    expect(queue.jobs.single.phase, FolderIngestJobPhase.error);
    expect(
      queue.jobs.single.statusLabel,
      contains('Add this folder again'),
    );
    expect(await store.listForAccount('acc_1'), isEmpty);
  });

  test('ensureFolderAccess runs before enumerate', () async {
    var accessCalled = false;
    var enumCalled = false;
    final items = FakeItemsRepository();
    final jobs = FakeJobsRepository();
    final queue = FolderIngestQueue(
      itemsRepository: items,
      jobsRepository: jobs,
      isUsageBlocked: () => false,
      ensureFolderAccess: (_) async {
        expect(enumCalled, isFalse);
        accessCalled = true;
      },
      enumerateFolder: (path) async {
        expect(accessCalled, isTrue);
        enumCalled = true;
        return [_photo('$path/a.jpg')];
      },
      contentHasher: (path) async => 'hash-$path',
      perceptualHasher: (path) async => null,
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

    await queue.enqueue('/albums/Paris');
    await _waitIdle(queue);

    expect(accessCalled, isTrue);
    expect(enumCalled, isTrue);
  });

  test('restoreIncompleteFromLibrary pipelines pending without create',
      () async {
    const path = '/albums/Paris/a.jpg';
    final existing = fixtureItem(
      id: 'item_lib',
      sourceRef: Uri.file(path).toString(),
      processingStatus: ProcessingStatus.pending,
      analysisRefState: AnalysisRefState.pending,
    );
    var enumerated = false;
    final items = FakeItemsRepository(items: [existing]);
    final jobs = FakeJobsRepository(
      libraryItems: items,
      onAnalyzed: items.replaceItem,
    );
    final queue = FolderIngestQueue(
      itemsRepository: items,
      jobsRepository: jobs,
      isUsageBlocked: () => false,
      enumerateFolder: (path) async {
        enumerated = true;
        return [_photo('$path/a.jpg')];
      },
      contentHasher: (path) async => 'hash-$path',
      perceptualHasher: (path) async => null,
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

    await queue.restoreIncompleteFromLibrary();
    await _waitIdle(queue);

    expect(enumerated, isFalse);
    expect(items.created, isEmpty);
    expect(jobs.analyzedItemIds, ['item_lib']);
    expect(queue.jobs.single.continueExistingOnly, isTrue);
    expect(queue.jobs.single.continuedCount, 1);
    expect(queue.jobs.single.phase, FolderIngestJobPhase.done);
  });

  test('restoreIncompleteFromLibrary skips tagged and continues failed',
      () async {
    final tagged = fixtureItem(
      id: 'item_ok',
      sourceRef: Uri.file('/albums/Paris/ok.jpg').toString(),
      processingStatus: ProcessingStatus.tagged,
      analysisRefState: AnalysisRefState.ready,
    );
    final failed = fixtureItem(
      id: 'item_fail',
      sourceRef: Uri.file('/albums/Paris/fail.jpg').toString(),
      processingStatus: ProcessingStatus.failed,
      analysisRefState: AnalysisRefState.ready,
    );
    final items = FakeItemsRepository(items: [tagged, failed]);
    final jobs = FakeJobsRepository(
      libraryItems: items,
      onAnalyzed: items.replaceItem,
    );
    final queue = _queue(
      items: items,
      jobs: jobs,
      byFolder: const {},
    );

    await queue.restoreIncompleteFromLibrary();
    await _waitIdle(queue);

    expect(items.created, isEmpty);
    expect(jobs.analyzedItemIds, ['item_fail']);
    expect(queue.jobs.single.continuedCount, 1);
  });

  test('restoreIncompleteFromLibrary collapses nested leaves to bookmark',
      () async {
    final day1 = fixtureItem(
      id: 'item_d1',
      sourceRef: Uri.file('/albums/Paris/day1/a.jpg').toString(),
      processingStatus: ProcessingStatus.pending,
    );
    final day2 = fixtureItem(
      id: 'item_d2',
      sourceRef: Uri.file('/albums/Paris/day2/b.jpg').toString(),
      processingStatus: ProcessingStatus.pending,
    );
    final items = FakeItemsRepository(items: [day1, day2]);
    final jobs = FakeJobsRepository(
      libraryItems: items,
      onAnalyzed: items.replaceItem,
    );
    final queue = _queue(
      items: items,
      jobs: jobs,
      byFolder: const {},
      bookmarkedFolders: () async => ['/albums/Paris'],
    );

    await queue.restoreIncompleteFromLibrary();
    await _waitIdle(queue);

    expect(queue.jobs, hasLength(1));
    expect(queue.jobs.single.folderPath, '/albums/Paris');
    expect(queue.jobs.single.continuedCount, 2);
    expect(jobs.analyzedItemIds, unorderedEquals(['item_d1', 'item_d2']));
  });

  test('restoreOnSignIn does not re-enqueue a checkpointed folder', () async {
    final temp = await Directory.systemTemp.createTemp('tagkin_ingest_ckpt_');
    addTearDown(() => temp.delete(recursive: true));
    final store = ActiveFolderIngestStore(supportDir: temp);
    await store.add('acc_1', '/albums/Paris');

    const path = '/albums/Paris/a.jpg';
    final existing = fixtureItem(
      id: 'item_once',
      sourceRef: Uri.file(path).toString(),
      processingStatus: ProcessingStatus.pending,
    );
    var enumCount = 0;
    final items = FakeItemsRepository(items: [existing]);
    final jobs = FakeJobsRepository(
      libraryItems: items,
      onAnalyzed: items.replaceItem,
    );
    final queue = FolderIngestQueue(
      itemsRepository: items,
      jobsRepository: jobs,
      isUsageBlocked: () => false,
      accountId: () => 'acc_1',
      checkpointStore: store,
      enumerateFolder: (path) async {
        enumCount++;
        return [_photo('$path/a.jpg')];
      },
      contentHasher: (path) async => 'hash-$path',
      perceptualHasher: (path) async => null,
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

    await queue.restoreOnSignIn();
    await _waitIdle(queue);

    expect(queue.jobs, hasLength(1));
    expect(queue.jobs.single.continueExistingOnly, isFalse);
    expect(enumCount, 1);
    expect(jobs.analyzedItemIds, ['item_once']);
  });

  test('continueExistingOnly missing access does not enumerate', () async {
    var enumerated = false;
    final existing = fixtureItem(
      id: 'item_no_access',
      sourceRef: Uri.file('/albums/Paris/a.jpg').toString(),
      processingStatus: ProcessingStatus.pending,
    );
    final items = FakeItemsRepository(items: [existing]);
    final jobs = FakeJobsRepository();
    final queue = FolderIngestQueue(
      itemsRepository: items,
      jobsRepository: jobs,
      isUsageBlocked: () => false,
      enumerateFolder: (path) async {
        enumerated = true;
        return [_photo('$path/a.jpg')];
      },
      contentHasher: (path) async => 'hash-$path',
      perceptualHasher: (path) async => null,
      ensureFolderAccess: (_) async {
        throw FolderAccessException(
          'Add this folder again to continue ingest.',
        );
      },
    );

    await queue.enqueue('/albums/Paris', continueExistingOnly: true);
    await _waitIdle(queue);

    expect(enumerated, isFalse);
    expect(queue.jobs.single.phase, FolderIngestJobPhase.error);
    expect(
      queue.jobs.single.statusLabel,
      contains('Add this folder again'),
    );
  });
}

Future<void> _waitIdle(FolderIngestQueue queue) async {
  await Future<void>.delayed(Duration.zero);
  for (var i = 0; i < 100 && queue.hasActiveJobs; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
