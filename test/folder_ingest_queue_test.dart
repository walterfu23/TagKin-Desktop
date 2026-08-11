import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/folder_ingest_queue.dart';
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
}) {
  return FolderIngestQueue(
    itemsRepository: items,
    jobsRepository: jobs,
    isUsageBlocked: () => usageBlocked,
    enumerateFolder: (path) async => byFolder[path] ?? const [],
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
}
