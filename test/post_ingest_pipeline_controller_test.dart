import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/batch_ingest_controller.dart';
import 'package:tagkin_desktop/ingest/model_host_uploader.dart';
import 'package:tagkin_desktop/ingest/post_ingest_pipeline_controller.dart';
import 'package:tagkin_desktop/ingest/upload_controller.dart';
import 'package:tagkin_desktop/prepass/prepass_controller.dart';
import 'package:tagkin_desktop/prepass/prepass_payload_builder.dart';

import 'fake_items_repository.dart';
import 'fake_jobs_repository.dart';

IngestOutcome _ingest({
  required Item item,
  required String path,
}) {
  return IngestOutcome(path: path, item: item);
}

PrePassController _stubPrePass(FakeItemsRepository items) {
  return PrePassController(
    itemsRepository: items,
    buildPayload: ({
      required path,
      required type,
      faceEmbedder,
      skipFaces = false,
      maxFrames = 20,
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
  );
}

UploadController _stubUpload(FakeItemsRepository items) {
  return UploadController(
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
  );
}

void main() {
  group('PostIngestPipelineController', () {
    test('chains pre-pass → upload → photo-only analyze', () async {
      final photo = fixtureItem(id: 'item_1', type: ItemType.photo);
      final video = fixtureItem(id: 'item_2', type: ItemType.video);
      final items = FakeItemsRepository(items: [photo, video]);
      final jobs = FakeJobsRepository(itemId: 'item_1', item: photo);
      final prePass = _stubPrePass(items);
      final upload = _stubUpload(items);
      final pipeline = PostIngestPipelineController(
        prePass: prePass,
        upload: upload,
        jobsRepository: jobs,
      );

      await pipeline.start(
        ingestOutcomes: [
          _ingest(item: photo, path: '/a.jpg'),
          _ingest(item: video, path: '/b.mp4'),
        ],
        usageBlocked: false,
      );

      expect(pipeline.phase, PostIngestPipelinePhase.done);
      expect(prePass.outcomes, hasLength(2));
      expect(prePass.outcomes.every((o) => o.succeeded), isTrue);
      // Video with no frame samples is skipped by upload (null outcome).
      expect(upload.outcomes.where((o) => o.succeeded), hasLength(1));
      expect(upload.outcomes.single.itemId, 'item_1');
      expect(jobs.analyzedItemIds, ['item_1']);
      expect(pipeline.analyzeOutcomes, hasLength(1));
      expect(pipeline.analyzeOutcomes.single.succeeded, isTrue);
      expect(pipeline.canRetry, isFalse);
    });

    test('skips upload and analyze when usage is blocked', () async {
      final photo = fixtureItem(id: 'item_1', type: ItemType.photo);
      final items = FakeItemsRepository(items: [photo]);
      final jobs = FakeJobsRepository(itemId: 'item_1', item: photo);
      final prePass = _stubPrePass(items);
      final upload = _stubUpload(items);
      final pipeline = PostIngestPipelineController(
        prePass: prePass,
        upload: upload,
        jobsRepository: jobs,
      );

      await pipeline.start(
        ingestOutcomes: [_ingest(item: photo, path: '/a.jpg')],
        usageBlocked: true,
      );

      expect(pipeline.phase, PostIngestPipelinePhase.skippedUpload);
      expect(prePass.outcomes, hasLength(1));
      expect(upload.outcomes, isEmpty);
      expect(jobs.analyzeCallCount, 0);
      expect(pipeline.canRetry, isTrue);
    });

    test('continues past per-item analyze failure', () async {
      final photo = fixtureItem(id: 'item_1', type: ItemType.photo);
      final photo2 = fixtureItem(id: 'item_3', type: ItemType.photo);
      final items = FakeItemsRepository(items: [photo, photo2]);
      var analyzeCount = 0;
      final jobs = _SelectiveAnalyzeJobs(
        onAnalyze: (id) async {
          analyzeCount++;
          if (id == 'item_1') throw Exception('boom');
          return AnalyzeResultResponse(
            item: fixtureItem(id: id, type: ItemType.photo),
            tagIds: const [],
            provider: 'stub',
            modelId: 'stub',
            escalated: false,
          );
        },
      );
      final prePass = _stubPrePass(items);
      final upload = _stubUpload(items);
      final pipeline = PostIngestPipelineController(
        prePass: prePass,
        upload: upload,
        jobsRepository: jobs,
      );

      await pipeline.start(
        ingestOutcomes: [
          _ingest(item: photo, path: '/a.jpg'),
          _ingest(item: photo2, path: '/c.jpg'),
        ],
        usageBlocked: false,
      );

      expect(pipeline.phase, PostIngestPipelinePhase.done);
      expect(analyzeCount, 2);
      expect(pipeline.analyzeOutcomes, hasLength(2));
      expect(pipeline.analyzeOutcomes[0].succeeded, isFalse);
      expect(pipeline.analyzeOutcomes[1].succeeded, isTrue);
      expect(pipeline.canRetry, isTrue);
    });

    test('start is idempotent within a session', () async {
      final photo = fixtureItem(id: 'item_1', type: ItemType.photo);
      final items = FakeItemsRepository(items: [photo]);
      final jobs = FakeJobsRepository(itemId: 'item_1', item: photo);
      final pipeline = PostIngestPipelineController(
        prePass: _stubPrePass(items),
        upload: _stubUpload(items),
        jobsRepository: jobs,
      );
      final outcomes = [_ingest(item: photo, path: '/a.jpg')];

      await pipeline.start(ingestOutcomes: outcomes, usageBlocked: false);
      final firstAnalyze = jobs.analyzeCallCount;

      await pipeline.start(ingestOutcomes: outcomes, usageBlocked: false);
      expect(jobs.analyzeCallCount, firstAnalyze);
    });
  });
}

/// Minimal jobs fake that routes analyze through a callback.
class _SelectiveAnalyzeJobs extends FakeJobsRepository {
  _SelectiveAnalyzeJobs({required this.onAnalyze}) : super();

  final Future<AnalyzeResultResponse> Function(String id) onAnalyze;

  @override
  Future<AnalyzeResultResponse> analyzeItem(String id) => onAnalyze(id);
}
