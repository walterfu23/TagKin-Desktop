import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/persons/collection.dart';
import 'package:tagkin_desktop/persons/collections_store.dart';

void main() {
  test('each account keeps its own catalog', () async {
    final store = MemoryCollectionsStore();
    store.accountKey = 'uid-a';
    await store.save(
      const CollectionsFile(
        collections: [Collection(id: 'c1', name: 'One', leafFolders: [])],
      ),
    );
    store.accountKey = 'uid-b';
    expect((await store.load()).collections, isEmpty);
    store.accountKey = 'uid-a';
    expect((await store.load()).collections.single.name, 'One');
  });
}
