import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/persons/who_face_linker.dart';
import 'package:tagkin_desktop/prepass/face_embedder.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';

import 'fake_items_repository.dart';

Uint8List _solidJpeg() {
  final image = img.Image(width: 80, height: 80);
  img.fill(image, color: img.ColorRgb8(180, 90, 40));
  return Uint8List.fromList(img.encodeJpg(image));
}

class _FixedModelEmbedder implements FaceEmbedder {
  _FixedModelEmbedder(this.modelId);

  final String modelId;

  @override
  Future<List<FaceAppearance>> embed(Uint8List bytes) async {
    return [
      FaceAppearance(
        embedding: List<double>.filled(kFaceEmbeddingDim, 0.01),
        embeddingModelId: modelId,
      ),
    ];
  }
}

void main() {
  test('refineWhoRegionForEmbed insets large boxes', () {
    const large = TagRegion(yMin: 0.0, xMin: 0.0, yMax: 0.8, xMax: 0.6);
    final refined = refineWhoRegionForEmbed(large);
    expect(refined.yMin, greaterThan(large.yMin));
    expect(refined.yMax, lessThan(large.yMax));
    expect(refined.xMin, greaterThan(large.xMin));
    expect(refined.xMax, lessThan(large.xMax));
  });

  test('refineWhoRegionForEmbed barely changes small face boxes', () {
    const small = TagRegion(yMin: 0.2, xMin: 0.3, yMax: 0.35, xMax: 0.42);
    final refined = refineWhoRegionForEmbed(small);
    expect(refined.yMin, closeTo(small.yMin, 0.05));
    expect(refined.yMax, closeTo(small.yMax, 0.05));
  });

  test('cropWhoFaceJpeg returns a non-empty jpeg for a valid region', () {
    final image = img.Image(width: 100, height: 100);
    img.fill(image, color: img.ColorRgb8(200, 100, 50));
    final bytes = Uint8List.fromList(img.encodeJpg(image));
    const region = TagRegion(yMin: 0.2, xMin: 0.2, yMax: 0.6, xMax: 0.6);
    final crop = cropWhoFaceJpeg(bytes, region);
    expect(crop, isNotNull);
    expect(crop!.length, greaterThan(50));
    expect(img.decodeImage(crop), isNotNull);
  });

  test('cropWhoFaceJpegAsync returns a non-empty jpeg for a valid region',
      () async {
    final image = img.Image(width: 100, height: 100);
    img.fill(image, color: img.ColorRgb8(200, 100, 50));
    final bytes = Uint8List.fromList(img.encodeJpg(image));
    const region = TagRegion(yMin: 0.2, xMin: 0.2, yMax: 0.6, xMax: 0.6);
    final crop = await cropWhoFaceJpegAsync(bytes, region);
    expect(crop, isNotNull);
    expect(crop!.length, greaterThan(50));
    expect(img.decodeImage(crop), isNotNull);
  });

  test('canCropLocalMediaForDisplay allows available and hashMismatch', () {
    final file = File('/tmp/unused');
    expect(
      canCropLocalMediaForDisplay(
        LocalMediaResolution(
          status: LocalMediaStatus.available,
          file: file,
        ),
      ),
      isTrue,
    );
    expect(
      canCropLocalMediaForDisplay(
        LocalMediaResolution(
          status: LocalMediaStatus.hashMismatch,
          file: file,
        ),
      ),
      isTrue,
    );
    expect(
      canCropLocalMediaForDisplay(
        const LocalMediaResolution(status: LocalMediaStatus.accessDenied),
      ),
      isFalse,
    );
  });

  test('WhoFaceLinker skips posting when embedder is stub', () async {
    debugResetFaceEmbedderStubNotice();
    final dir = await Directory.systemTemp.createTemp('who_stub_');
    final file = File('${dir.path}/face.jpg');
    await file.writeAsBytes(_solidJpeg());

    final item = fixtureItem(
      id: 'item_1',
      type: ItemType.photo,
      sourceRef: 'file://${file.path}',
      processingStatus: ProcessingStatus.tagged,
      contentHash: null,
    );
    final items = FakeItemsRepository(items: [item]);
    items.setKnowledge(
      item.id,
      fixtureKnowledge(
        item: item,
        tags: [
          fixtureTag(
            id: '00000000-0000-4000-8000-000000000001',
            itemId: item.id,
            dimension: 'who',
            value: 'Someone',
            region: const TagRegion(
              yMin: 0.2,
              xMin: 0.2,
              yMax: 0.6,
              xMax: 0.6,
            ),
          ),
        ],
      ),
    );

    final linker = WhoFaceLinker(
      items: items,
      embedder: StubFaceEmbedder(),
    );
    final result = await linker.linkWhoFacesForItem(item);
    expect(result, isNull);
    expect(items.whoAppearancesRecorded, isEmpty);
    expect(consumeFaceEmbedderStubNotice(), isTrue);

    await dir.delete(recursive: true);
  });

  test('WhoFaceLinker posts when embedder is a real model id', () async {
    final dir = await Directory.systemTemp.createTemp('who_onnx_');
    final file = File('${dir.path}/face.jpg');
    await file.writeAsBytes(_solidJpeg());

    final item = fixtureItem(
      id: 'item_1',
      type: ItemType.photo,
      sourceRef: 'file://${file.path}',
      processingStatus: ProcessingStatus.tagged,
      contentHash: null,
    );
    final items = FakeItemsRepository(items: [item]);
    items.setKnowledge(
      item.id,
      fixtureKnowledge(
        item: item,
        tags: [
          fixtureTag(
            id: '00000000-0000-4000-8000-000000000002',
            itemId: item.id,
            dimension: 'who',
            value: 'Someone',
            region: const TagRegion(
              yMin: 0.2,
              xMin: 0.2,
              yMax: 0.6,
              xMax: 0.6,
            ),
          ),
        ],
      ),
    );

    final linker = WhoFaceLinker(
      items: items,
      embedder: _FixedModelEmbedder('onnx-arcface-w600k-r50-v5'),
      autoConfirmMinConfidencePercent: 90,
    );
    final result = await linker.linkWhoFacesForItem(item);
    expect(result, isNotNull);
    expect(items.whoAppearancesRecorded, hasLength(1));
    expect(
      items.whoAppearancesRecorded.single.appearances.single.embeddingModelId,
      'onnx-arcface-w600k-r50-v5',
    );
    expect(
      items.whoAppearancesRecorded.single.autoConfirmMinConfidencePercent,
      90,
    );

    await dir.delete(recursive: true);
  });

  test('WhoFaceLinker omits autoConfirm when percent is null', () async {
    final dir = await Directory.systemTemp.createTemp('who_omit_');
    final file = File('${dir.path}/face.jpg');
    await file.writeAsBytes(_solidJpeg());

    final item = fixtureItem(
      id: 'item_1',
      type: ItemType.photo,
      sourceRef: 'file://${file.path}',
      processingStatus: ProcessingStatus.tagged,
      contentHash: null,
    );
    final items = FakeItemsRepository(items: [item]);
    items.setKnowledge(
      item.id,
      fixtureKnowledge(
        item: item,
        tags: [
          fixtureTag(
            id: '00000000-0000-4000-8000-000000000002',
            itemId: item.id,
            dimension: 'who',
            value: 'Someone',
            region: const TagRegion(
              yMin: 0.2,
              xMin: 0.2,
              yMax: 0.6,
              xMax: 0.6,
            ),
          ),
        ],
      ),
    );

    final linker = WhoFaceLinker(
      items: items,
      embedder: _FixedModelEmbedder('onnx-arcface-w600k-r50-v5'),
    );
    await linker.linkWhoFacesForItem(item);
    expect(
      items.whoAppearancesRecorded.single.autoConfirmMinConfidencePercent,
      isNull,
    );

    await dir.delete(recursive: true);
  });
}
