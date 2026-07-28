import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/persons/face_crop_folder_scope.dart';

import 'fake_items_repository.dart';

void main() {
  group('face_crop_folder_scope', () {
    test('leafFolderFromSourceRef uses parent directory', () {
      expect(
        leafFolderFromSourceRef('file:///Users/me/Trip/a.jpg'),
        '/Users/me/Trip',
      );
      expect(leafFolderFromSourceRef(null), isNull);
      expect(leafFolderFromSourceRef(''), isNull);
    });

    test('distinctLeafFolders is sorted unique', () {
      final items = [
        fixtureItem(id: 'a', sourceRef: 'file:///albums/Paris/1.jpg'),
        fixtureItem(id: 'b', sourceRef: 'file:///albums/Rome/2.jpg'),
        fixtureItem(id: 'c', sourceRef: 'file:///albums/Paris/3.jpg'),
      ];
      expect(distinctLeafFolders(items), [
        '/albums/Paris',
        '/albums/Rome',
      ]);
    });

    test('itemIdsInLeafFolder matches exact parent only', () {
      final items = [
        fixtureItem(id: 'a', sourceRef: 'file:///albums/Paris/1.jpg'),
        fixtureItem(id: 'b', sourceRef: 'file:///albums/Paris/day2/2.jpg'),
        fixtureItem(id: 'c', sourceRef: 'file:///albums/Rome/3.jpg'),
      ];
      expect(itemIdsInLeafFolder(items, '/albums/Paris'), {'a'});
      expect(itemIdsInLeafFolder(items, '/albums/Paris/day2'), {'b'});
    });

    test('resolveLeafFolderSelection prefers listed preferred', () {
      expect(
        resolveLeafFolderSelection(
          folders: ['/a', '/b'],
          preferred: '/b',
        ),
        '/b',
      );
      expect(
        resolveLeafFolderSelection(
          folders: ['/a', '/b'],
          preferred: '/missing',
        ),
        '/a',
      );
      expect(
        resolveLeafFolderSelection(folders: const [], preferred: '/a'),
        isNull,
      );
    });

    test('leafFolderLabel uses basename', () {
      expect(leafFolderLabel('/albums/Paris'), 'Paris');
    });
  });
}
