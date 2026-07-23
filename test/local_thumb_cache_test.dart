import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/local_thumb_cache.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';

import 'fake_items_repository.dart';

Uint8List _tinyJpeg({int width = 40, int height = 20}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(200, 40, 40));
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('thumb_cache_test_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('photo resolve writes a downscaled JPEG under cache', () async {
    final photo = File('${tmp.path}/shot.jpg');
    await photo.writeAsBytes(_tinyJpeg(width: 200, height: 100));
    final item = fixtureItem(
      id: 'p1',
      contentHash: 'h1',
      sourceRef: Uri.file(photo.path).toString(),
    );
    final cacheDir = Directory('${tmp.path}/cache');
    final cache = LocalThumbCache(cacheRoot: cacheDir);
    final result = await cache.resolve(item);
    expect(result.status, LocalMediaStatus.available);
    expect(result.path, isNot(photo.path));
    expect(result.path, contains('_thumb.jpg'));
    final decoded = img.decodeImage(await File(result.path!).readAsBytes());
    expect(decoded, isNotNull);
    expect(decoded!.width, lessThanOrEqualTo(kLibraryThumbLongEdge));
    expect(decoded.height, lessThanOrEqualTo(kLibraryThumbLongEdge));
  });

  test('missing photo returns missing status', () async {
    final item = fixtureItem(
      id: 'missing',
      sourceRef: Uri.file('${tmp.path}/nope.jpg').toString(),
    );
    final cache = LocalThumbCache(cacheRoot: Directory('${tmp.path}/cache'));
    final result = await cache.resolve(item);
    expect(result.status, LocalMediaStatus.missing);
    expect(result.path, isNull);
  });

  test('video poster uses injected ffmpeg runner and caches jpeg', () async {
    final video = File('${tmp.path}/clip.mp4');
    await video.writeAsBytes(List<int>.filled(8, 2));
    final cacheDir = Directory('${tmp.path}/cache');
    await cacheDir.create();
    final item = fixtureItem(
      id: 'v1',
      type: ItemType.video,
      contentHash: 'abc',
      sourceRef: Uri.file(video.path).toString(),
    );

    var ran = false;
    final cache = LocalThumbCache(
      cacheRoot: cacheDir,
      runFfmpeg: (ffmpeg, args) async {
        ran = true;
        final out = args.last;
        await File(out).writeAsBytes(_tinyJpeg());
        return const [];
      },
    );

    final first = await cache.resolve(item);
    expect(ran, isTrue);
    expect(first.hasImage, isTrue);
    expect(File(first.path!).existsSync(), isTrue);

    ran = false;
    final second = await cache.resolve(item);
    expect(ran, isFalse, reason: 'memory cache should hit');
    expect(second.path, first.path);
  });
}
