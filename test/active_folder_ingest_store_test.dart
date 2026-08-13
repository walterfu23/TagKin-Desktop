import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/ingest/active_folder_ingest_store.dart';

void main() {
  late Directory tempDir;
  late ActiveFolderIngestStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tagkin_ingest_store_');
    store = ActiveFolderIngestStore(supportDir: tempDir);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('add is idempotent and scoped by account', () async {
    await store.add('acc_1', '/albums/Paris');
    await store.add('acc_1', '/albums/Paris');
    await store.add('acc_2', '/albums/Rome');

    expect(await store.listForAccount('acc_1'), ['/albums/Paris']);
    expect(await store.listForAccount('acc_2'), ['/albums/Rome']);
  });

  test('remove drops only that account path', () async {
    await store.add('acc_1', '/albums/Paris');
    await store.add('acc_1', '/albums/Rome');
    await store.remove('acc_1', '/albums/Paris');

    expect(await store.listForAccount('acc_1'), ['/albums/Rome']);
    expect(await store.listForAccount('acc_2'), isEmpty);
  });

  test('survives a new store instance on the same dir', () async {
    await store.add('acc_1', '/albums/Paris');
    final reloaded = ActiveFolderIngestStore(supportDir: tempDir);
    expect(await reloaded.listForAccount('acc_1'), ['/albums/Paris']);
  });
}
