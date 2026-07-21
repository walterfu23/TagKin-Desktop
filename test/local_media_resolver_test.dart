import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';

import 'fake_items_repository.dart';
import 'fixtures/synthetic_images.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('tagkin_d8_media_');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('localPathFromSourceRef parses file:// URIs', () {
    final path = localPathFromSourceRef(Uri.file('/tmp/photo.jpg').toString());
    expect(path, '/tmp/photo.jpg');
    expect(localPathFromSourceRef(null), isNull);
    expect(localPathFromSourceRef('https://example.com/a.jpg'), isNull);
  });

  test('resolveLocalMedia reports missing when file absent', () async {
    final item = fixtureItem(
      sourceRef: Uri.file('${tmp.path}/gone.jpg').toString(),
      contentHash: 'abc',
    );
    final result = await resolveLocalMedia(item);
    expect(result.status, LocalMediaStatus.missing);
  });

  test('resolveLocalMedia available when contentHash is null', () async {
    final file = File('${tmp.path}/photo.png');
    await file.writeAsBytes(solidImagePng());
    final result = await resolveLocalMedia(
      fixtureItem(
        sourceRef: Uri.file(file.path).toString(),
        contentHash: null,
      ),
    );
    expect(result.status, LocalMediaStatus.available);
    expect(result.path, file.path);
  });

  test('resolveLocalMedia reports hashMismatch', () async {
    final file = File('${tmp.path}/photo.png');
    await file.writeAsBytes(solidImagePng());
    final result = await resolveLocalMedia(
      fixtureItem(
        sourceRef: Uri.file(file.path).toString(),
        contentHash: 'not-the-real-hash',
      ),
      contentHasher: (path) async => 'different-hash',
    );
    expect(result.status, LocalMediaStatus.hashMismatch);
    expect(result.file, isNotNull);
  });

  test('resolveLocalMedia reports available when hash matches', () async {
    final file = File('${tmp.path}/photo.png');
    await file.writeAsBytes(solidImagePng());
    final result = await resolveLocalMedia(
      fixtureItem(
        sourceRef: Uri.file(file.path).toString(),
        contentHash: 'exact',
      ),
      contentHasher: (path) async => 'exact',
    );
    expect(result.status, LocalMediaStatus.available);
    expect(result.path, file.path);
  });
}
