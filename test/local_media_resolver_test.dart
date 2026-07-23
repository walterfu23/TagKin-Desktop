import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/ingest/folder_bookmark_store.dart';
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
    final uri = Uri.file('/tmp/photo.jpg');
    final path = localPathFromSourceRef(uri.toString());
    expect(path, uri.toFilePath());
    expect(localPathFromSourceRef(null), isNull);
    expect(localPathFromSourceRef('https://example.com/a.jpg'), isNull);
  });

  test('resolveLocalMedia reports missing when file absent', () async {
    final item = fixtureItem(
      sourceRef: Uri.file(p.join(tmp.path, 'gone.jpg')).toString(),
      contentHash: 'abc',
    );
    final result = await resolveLocalMedia(item);
    expect(result.status, LocalMediaStatus.missing);
  });

  test('resolveLocalMedia available when contentHash is null', () async {
    final file = File(p.join(tmp.path, 'photo.png'));
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
    final file = File(p.join(tmp.path, 'photo.png'));
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
    final file = File(p.join(tmp.path, 'photo.png'));
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

  test('resolveLocalMedia reports accessDenied on PathAccessException', () async {
    final path = p.join(tmp.path, 'locked.jpg');
    final result = await resolveLocalMedia(
      fixtureItem(
        sourceRef: Uri.file(path).toString(),
        contentHash: 'x',
      ),
      fileExists: (_) => throw PathAccessException(
        'existsSync',
        OSError('Operation not permitted', 1),
        path,
      ),
    );
    expect(result.status, LocalMediaStatus.accessDenied);
    expect(result.path, path);
  });

  test('FolderBookmarkStore matches longest folder prefix', () async {
    final store = FolderBookmarkStore(supportDir: tmp);
    await store.save(tmp.path, 'bookmark-root');
    final nested = p.join(tmp.path, 'sub');
    await store.save(nested, 'bookmark-nested');
    final filePath = p.join(nested, 'a.jpg');
    expect(await store.bookmarkForFile(filePath), 'bookmark-nested');
  });
}
