import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/persons/face_crop_folder_scope.dart';

import 'fake_items_repository.dart';

void main() {
  group('face_crop_folder_scope', () {
    test('normalizeLeafFolder unifies Windows separators', () {
      expect(normalizeLeafFolder(r'\albums\Trip\Beta'), '/albums/Trip/Beta');
      expect(normalizeLeafFolder('/albums/Trip/Beta'), '/albums/Trip/Beta');
      expect(
        normalizeLeafFolder(r'C:\Users\me\Trip'),
        'C:/Users/me/Trip',
      );
    });

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

    test('distinctLeafFolders sorts by basename case-insensitively', () {
      final items = [
        fixtureItem(id: 'a', sourceRef: 'file:///z/apple/1.jpg'),
        fixtureItem(id: 'b', sourceRef: 'file:///a/Banana/2.jpg'),
        fixtureItem(id: 'c', sourceRef: 'file:///m/cherry/3.jpg'),
      ];
      expect(distinctLeafFolders(items), [
        '/z/apple',
        '/a/Banana',
        '/m/cherry',
      ]);
    });

    test('itemIdsInLeafFolder matches exact parent only', () {
      final items = [
        fixtureItem(id: 'a', sourceRef: 'file:///albums/Paris/1.jpg'),
        fixtureItem(id: 'b', sourceRef: 'file:///albums/Paris/day2/2.jpg'),
        fixtureItem(id: 'c', sourceRef: 'file:///albums/Rome/3.jpg'),
      ];
      expect(itemIdsInLeafFolder(items, '/albums/Paris'), {'a'});
      expect(itemIdsInLeafFolder(items, r'\albums\Paris'), {'a'});
      expect(itemIdsInLeafFolder(items, '/albums/Paris/day2'), {'b'});
    });

    test('itemIdsUnderFolder includes nested descendants', () {
      final items = [
        fixtureItem(id: 'a', sourceRef: 'file:///albums/Paris/1.jpg'),
        fixtureItem(id: 'b', sourceRef: 'file:///albums/Paris/day2/2.jpg'),
        fixtureItem(id: 'c', sourceRef: 'file:///albums/Rome/3.jpg'),
        fixtureItem(id: 'd', sourceRef: 'file:///albums/ParisExtra/4.jpg'),
      ];
      expect(itemIdsUnderFolder(items, '/albums/Paris'), {'a', 'b'});
      expect(itemIdsUnderFolder(items, '/albums/Paris/day2'), {'b'});
      expect(itemIdsUnderFolder(items, '/albums/Rome'), {'c'});
    });

    test('pathIsUnderFolder rejects sibling prefix names', () {
      expect(pathIsUnderFolder('/albums/Paris/1.jpg', '/albums/Paris'), isTrue);
      expect(
        pathIsUnderFolder('/albums/ParisExtra/1.jpg', '/albums/Paris'),
        isFalse,
      );
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

    test('minimalCoveringFolders drops nested paths', () {
      expect(
        minimalCoveringFolders([
          '/albums/Paris',
          '/albums/Paris/day1',
          '/albums/Rome',
        ]),
        ['/albums/Paris', '/albums/Rome'],
      );
    });

    test('coveringFoldersForItems prefers bookmarked ancestor', () {
      final items = [
        fixtureItem(
          id: 'a',
          sourceRef: 'file:///albums/Paris/day1/1.jpg',
        ),
        fixtureItem(
          id: 'b',
          sourceRef: 'file:///albums/Paris/day2/2.jpg',
        ),
      ];
      expect(
        coveringFoldersForItems(
          items,
          bookmarkedFolders: ['/albums/Paris'],
        ),
        ['/albums/Paris'],
      );
      expect(
        coveringFoldersForItems(items),
        ['/albums/Paris/day1', '/albums/Paris/day2'],
      );
    });
  });
}
