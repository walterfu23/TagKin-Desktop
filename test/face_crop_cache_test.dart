import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/persons/face_crop_cache.dart';

Uint8List _jpeg(int r, int g, int b) {
  final image = img.Image(width: 100, height: 100);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  return Uint8List.fromList(img.encodeJpg(image));
}

const _regionA = TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.4, xMax: 0.4);
const _regionB = TagRegion(yMin: 0.5, xMin: 0.5, yMax: 0.9, xMax: 0.9);

void main() {
  setUp(() => FaceCropCache.instance.clear());

  test('peek is null before load and returns the crop after', () async {
    final bytes = _jpeg(200, 50, 50);
    expect(
      FaceCropCache.instance
          .peek(itemId: 'i1', contentHash: 'h1', region: _regionA),
      isNull,
    );

    final crop = await FaceCropCache.instance.getOrCropFace(
      itemId: 'i1',
      contentHash: 'h1',
      region: _regionA,
      loadFileBytes: () async => bytes,
    );

    expect(crop, isNotNull);
    expect(
      FaceCropCache.instance
          .peek(itemId: 'i1', contentHash: 'h1', region: _regionA),
      crop,
    );
  });

  test('second request for the same crop reuses the cache, no reload',
      () async {
    final bytes = _jpeg(10, 20, 30);
    var loadCount = 0;
    Future<Uint8List> load() async {
      loadCount++;
      return bytes;
    }

    final first = await FaceCropCache.instance.getOrCropFace(
      itemId: 'i2',
      contentHash: 'h2',
      region: _regionA,
      loadFileBytes: load,
    );
    final second = await FaceCropCache.instance.getOrCropFace(
      itemId: 'i2',
      contentHash: 'h2',
      region: _regionA,
      loadFileBytes: load,
    );

    expect(first, isNotNull);
    expect(second, first);
    expect(loadCount, 1);
  });

  test(
      'concurrent requests for two regions on the same photo coalesce into '
      'one file read', () async {
    final bytes = _jpeg(80, 160, 40);
    var loadCount = 0;
    Future<Uint8List> load() async {
      loadCount++;
      return bytes;
    }

    final futureA = FaceCropCache.instance.getOrCropFace(
      itemId: 'i3',
      contentHash: 'h3',
      region: _regionA,
      loadFileBytes: load,
    );
    final futureB = FaceCropCache.instance.getOrCropFace(
      itemId: 'i3',
      contentHash: 'h3',
      region: _regionB,
      loadFileBytes: load,
    );

    final results = await Future.wait([futureA, futureB]);

    expect(results[0], isNotNull);
    expect(results[1], isNotNull);
    expect(loadCount, 1, reason: 'both regions share one decode-once batch');
  });

  test('different contentHash for the same itemId is a cache miss (rescan)',
      () async {
    var loadCount = 0;
    Future<Uint8List> load(int r) => () async {
          loadCount++;
          return _jpeg(r, r, r);
        }();

    await FaceCropCache.instance.getOrCropFace(
      itemId: 'i4',
      contentHash: 'hash-old',
      region: _regionA,
      loadFileBytes: () => load(10),
    );
    await FaceCropCache.instance.getOrCropFace(
      itemId: 'i4',
      contentHash: 'hash-new',
      region: _regionA,
      loadFileBytes: () => load(20),
    );

    expect(loadCount, 2);
  });

  test('a decode failure completes with null, not an unhandled error',
      () async {
    final crop = await FaceCropCache.instance.getOrCropFace(
      itemId: 'i5',
      contentHash: 'h5',
      region: _regionA,
      loadFileBytes: () async => Uint8List.fromList([1, 2, 3]),
    );
    expect(crop, isNull);
  });

  test('a failed load rejects the returned future', () async {
    await expectLater(
      FaceCropCache.instance.getOrCropFace(
        itemId: 'i6',
        contentHash: 'h6',
        region: _regionA,
        loadFileBytes: () async => throw StateError('boom'),
      ),
      throwsA(isA<StateError>()),
    );
  });
}
