import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/ingest/folder_bookmark_store.dart';

void main() {
  late Directory tempDir;
  late FolderBookmarkStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tagkin_bookmark_test_');
    store = FolderBookmarkStore(supportDir: tempDir);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('remove drops exact folder bookmark', () async {
    await store.save('/albums/Paris', 'bookmark-paris');
    await store.save('/albums/Rome', 'bookmark-rome');

    await store.remove('/albums/Paris');

    expect(await store.bookmarkForFile('/albums/Paris/1.jpg'), isNull);
    expect(
      await store.bookmarkForFile('/albums/Rome/1.jpg'),
      'bookmark-rome',
    );
  });

  test('remove is a no-op when path is unknown', () async {
    await store.save('/albums/Rome', 'bookmark-rome');
    await store.remove('/albums/Paris');
    expect(
      await store.bookmarkForFile('/albums/Rome/1.jpg'),
      'bookmark-rome',
    );
  });

  test('listFolders and folderForFile use longest prefix', () async {
    await store.save('/albums/Paris', 'bookmark-paris');
    await store.save('/albums/Paris/day1', 'bookmark-day1');

    expect(await store.listFolders(), unorderedEquals([
      '/albums/Paris',
      '/albums/Paris/day1',
    ]));
    expect(
      await store.folderForFile('/albums/Paris/day1/a.jpg'),
      '/albums/Paris/day1',
    );
    expect(
      await store.folderForFile('/albums/Paris/other/a.jpg'),
      '/albums/Paris',
    );
    expect(await store.folderForFile('/elsewhere/a.jpg'), isNull);
  });
}
