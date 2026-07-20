import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/batch_ingest_controller.dart';
import 'package:tagkin_desktop/prepass/face_embedder.dart';
import 'package:tagkin_desktop/prepass/frame_sampler.dart';
import 'package:tagkin_desktop/prepass/prepass_controller.dart';
import 'package:tagkin_desktop/prepass/prepass_payload_builder.dart';

import 'fake_items_repository.dart';

void main() {
  group('PrePassController', () {
    test('posts pre-pass-result for each succeeded ingest outcome', () async {
      final repo = FakeItemsRepository(
        items: [
          fixtureItem(id: 'item_1', type: ItemType.photo),
          fixtureItem(id: 'item_2', type: ItemType.photo),
        ],
      );
      final controller = PrePassController(
        itemsRepository: repo,
        buildPayload: ({
          required String path,
          required ItemType type,
          FaceEmbedder? faceEmbedder,
          bool skipFaces = false,
          int maxFrames = kDefaultMaxFramesPerItem,
        }) async {
          return PrePassBuildResult(
            payload: PrePassResult(
              contentHash: 'abc',
              perceptualHash: '0123456789abcdef',
              appearances: [
                PrePassAppearanceInput(
                  embedding: List<double>.filled(kFaceEmbeddingDim, 0.1),
                  embeddingModelId: StubFaceEmbedder.modelId,
                ),
              ],
            ),
          );
        },
      );

      await controller.run([
        IngestOutcome(path: '/tmp/a.jpg', item: fixtureItem(id: 'item_1')),
        IngestOutcome(path: '/tmp/b.jpg', item: fixtureItem(id: 'item_2')),
        const IngestOutcome(path: '/tmp/bad.jpg', error: 'fail'),
      ]);

      expect(controller.phase, PrePassPhase.done);
      expect(controller.outcomes, hasLength(2));
      expect(controller.outcomes.every((o) => o.succeeded), isTrue);
      expect(repo.prePassRecorded, hasLength(2));
      expect(repo.prePassRecorded.map((e) => e.itemId), ['item_1', 'item_2']);
      for (final recorded in repo.prePassRecorded) {
        final json = recorded.input.toJson();
        expect(json.containsKey('ownerUserId'), isFalse);
        expect(json.containsKey('bytes'), isFalse);
      }
    });

    test('continues past individual failures', () async {
      final repo = FakeItemsRepository(
        items: [fixtureItem(id: 'item_1'), fixtureItem(id: 'item_2')],
      );
      var calls = 0;
      final controller = PrePassController(
        itemsRepository: repo,
        buildPayload: ({
          required String path,
          required ItemType type,
          FaceEmbedder? faceEmbedder,
          bool skipFaces = false,
          int maxFrames = kDefaultMaxFramesPerItem,
        }) async {
          calls++;
          if (path.endsWith('a.jpg')) {
            throw StateError('boom');
          }
          return const PrePassBuildResult(
            payload: PrePassResult(contentHash: 'ok'),
          );
        },
      );

      await controller.run([
        IngestOutcome(path: '/tmp/a.jpg', item: fixtureItem(id: 'item_1')),
        IngestOutcome(path: '/tmp/b.jpg', item: fixtureItem(id: 'item_2')),
      ]);

      expect(calls, 2);
      expect(controller.outcomes, hasLength(2));
      expect(controller.outcomes[0].succeeded, isFalse);
      expect(controller.outcomes[1].succeeded, isTrue);
      expect(repo.prePassRecorded, hasLength(1));
    });
  });
}
