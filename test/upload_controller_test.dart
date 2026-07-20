import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/model_host_uploader.dart';
import 'package:tagkin_desktop/ingest/upload_controller.dart';
import 'package:tagkin_desktop/prepass/frame_sampler.dart';
import 'package:tagkin_desktop/prepass/prepass_controller.dart';

import 'fake_items_repository.dart';

PrePassOutcome _prePassOutcome({
  required Item item,
  required String path,
}) {
  return PrePassOutcome(
    itemId: item.id,
    path: path,
    response: PrePassResultResponse(
      item: item,
      keyPeriodIds: const [],
      appearanceIds: const [],
      tagIds: const [],
    ),
  );
}

void main() {
  group('UploadController', () {
    test('photo uploads whole original file bytes to model-host URL', () async {
      final item = fixtureItem(id: 'photo_1', type: ItemType.photo);
      final repo = FakeItemsRepository(items: [item]);
      final putUrls = <String>[];
      final putPaths = <String>[];

      final controller = UploadController(
        itemsRepository: repo,
        readBytes: (path) async {
          putPaths.add(path);
          return [0xFF, 0xD8, 0xFF];
        },
        putBytes: ({
          required uploadUrl,
          required bytes,
          required mimeType,
          httpClient,
        }) async {
          putUrls.add(uploadUrl);
          expect(mimeType, 'image/jpeg');
          expect(bytes, [0xFF, 0xD8, 0xFF]);
          expect(uploadUrl.contains('stub.tagkin.test'), isTrue);
          return const ModelHostUploadResult(
            analysisRef: null,
            rawBody: 'ok',
          );
        },
      );

      await controller.run(
        [_prePassOutcome(item: item, path: '/library/shot.jpg')],
        const {},
      );

      expect(controller.phase, UploadPhase.done);
      expect(controller.outcomes.single.succeeded, isTrue);
      expect(putPaths, ['/library/shot.jpg']);
      expect(putUrls, hasLength(1));
      expect(repo.grantsMinted, hasLength(1));
      expect(repo.grantsMinted.single.input.mimeType, 'image/jpeg');
      expect(repo.analysisRefRecorded, hasLength(1));
      expect(
        repo.analysisRefRecorded.single.input.analysisRef,
        'stub://files/photo_1',
      );
      // API grant/analysis-ref bodies never carry bytes or owner (R1/R10).
      expect(
        repo.grantsMinted.single.input.toJson().containsKey('ownerUserId'),
        isFalse,
      );
      expect(
        repo.analysisRefRecorded.single.input.toJson().containsKey('bytes'),
        isFalse,
      );
    });

    test('video uploads first D4 frame sample, not the source video path',
        () async {
      final item = fixtureItem(id: 'vid_1', type: ItemType.video);
      final repo = FakeItemsRepository(items: [item]);
      final putPaths = <String>[];

      final controller = UploadController(
        itemsRepository: repo,
        readBytes: (path) async {
          putPaths.add(path);
          return [1, 2, 3];
        },
        putBytes: ({
          required uploadUrl,
          required bytes,
          required mimeType,
          httpClient,
        }) async {
          expect(mimeType, 'image/jpeg');
          return const ModelHostUploadResult(
            analysisRef: 'files/frame-1',
            rawBody: '{}',
          );
        },
      );

      await controller.run(
        [_prePassOutcome(item: item, path: '/library/clip.mp4')],
        {
          'vid_1': [
            const FrameSample(
              path: '/tmp/frames/frame_0000.jpg',
              timestampMs: 500,
              keyPeriodIndex: 0,
            ),
          ],
        },
      );

      expect(controller.outcomes.single.succeeded, isTrue);
      expect(putPaths, ['/tmp/frames/frame_0000.jpg']);
      expect(putPaths, isNot(contains('/library/clip.mp4')));
      expect(
        repo.analysisRefRecorded.single.input.analysisRef,
        'files/frame-1',
      );
    });

    test('video with no frame samples is skipped (no grant call)', () async {
      final item = fixtureItem(id: 'vid_empty', type: ItemType.video);
      final repo = FakeItemsRepository(items: [item]);
      var putCalls = 0;

      final controller = UploadController(
        itemsRepository: repo,
        readBytes: (path) async => [1],
        putBytes: ({
          required uploadUrl,
          required bytes,
          required mimeType,
          httpClient,
        }) async {
          putCalls++;
          return const ModelHostUploadResult(analysisRef: 'x', rawBody: '');
        },
      );

      await controller.run(
        [_prePassOutcome(item: item, path: '/library/clip.mp4')],
        const {},
      );

      expect(controller.outcomes, isEmpty);
      expect(repo.grantsMinted, isEmpty);
      expect(repo.analysisRefRecorded, isEmpty);
      expect(putCalls, 0);
    });

    test('expired grant triggers one fresh request then succeeds', () async {
      final item = fixtureItem(id: 'photo_exp', type: ItemType.photo);
      final repo = FakeItemsRepository(items: [item]);
      repo.grantSequence.addAll([
        UploadGrant(
          uploadUrl: 'https://stub.tagkin.test/expired',
          expiresAt:
              DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String(),
        ),
        UploadGrant(
          uploadUrl: 'https://stub.tagkin.test/fresh',
          expiresAt:
              DateTime.now().add(const Duration(minutes: 15)).toIso8601String(),
        ),
      ]);

      final putUrls = <String>[];
      final controller = UploadController(
        itemsRepository: repo,
        readBytes: (path) async => [1],
        putBytes: ({
          required uploadUrl,
          required bytes,
          required mimeType,
          httpClient,
        }) async {
          putUrls.add(uploadUrl);
          return const ModelHostUploadResult(
            analysisRef: 'files/after-retry',
            rawBody: '{}',
          );
        },
      );

      await controller.run(
        [_prePassOutcome(item: item, path: '/a.jpg')],
        const {},
      );

      expect(controller.outcomes.single.succeeded, isTrue);
      // First grant was expired → skipped PUT; second grant used once.
      expect(repo.grantsMinted, hasLength(2));
      expect(putUrls, ['https://stub.tagkin.test/fresh']);
      expect(
        repo.analysisRefRecorded.single.input.analysisRef,
        'files/after-retry',
      );
    });

    test('model-host failure retries once with a fresh grant', () async {
      final item = fixtureItem(id: 'photo_retry', type: ItemType.photo);
      final repo = FakeItemsRepository(items: [item]);
      var putAttempts = 0;

      final controller = UploadController(
        itemsRepository: repo,
        readBytes: (path) async => [1],
        putBytes: ({
          required uploadUrl,
          required bytes,
          required mimeType,
          httpClient,
        }) async {
          putAttempts++;
          if (putAttempts == 1) {
            throw ModelHostUploadException(
              statusCode: 403,
              message: 'expired',
            );
          }
          return const ModelHostUploadResult(
            analysisRef: 'files/ok',
            rawBody: '{}',
          );
        },
      );

      await controller.run(
        [_prePassOutcome(item: item, path: '/a.jpg')],
        const {},
      );

      expect(putAttempts, 2);
      expect(repo.grantsMinted, hasLength(2));
      expect(controller.outcomes.single.succeeded, isTrue);
    });

    test('records analysisRef advancing item toward tagging', () async {
      final item = fixtureItem(id: 'photo_ready', type: ItemType.photo);
      final repo = FakeItemsRepository(items: [item]);

      final controller = UploadController(
        itemsRepository: repo,
        readBytes: (path) async => [1],
        putBytes: ({
          required uploadUrl,
          required bytes,
          required mimeType,
          httpClient,
        }) async {
          return const ModelHostUploadResult(
            analysisRef: 'files/ready-ref',
            rawBody: '{}',
          );
        },
      );

      await controller.run(
        [_prePassOutcome(item: item, path: '/a.jpg')],
        const {},
      );

      final updated = await repo.getItem('photo_ready');
      expect(updated.analysisRef, 'files/ready-ref');
      expect(updated.analysisRefState, AnalysisRefState.ready);
      expect(
        updated.processingStatus,
        ProcessingStatus.awaitingModelAccess,
      );
    });

    test('never implements local cost estimation as authority (R9)', () {
      // Source-level: UploadController has no estimate/reserve helpers.
      final source = File('lib/ingest/upload_controller.dart').readAsStringSync();
      expect(source.contains('estimateCost'), isFalse);
      expect(source.contains('reserve('), isFalse);
      expect(source.contains('hardLimitCents'), isFalse);
    });
  });
}
