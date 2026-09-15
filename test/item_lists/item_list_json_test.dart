import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/item_lists/item_list_csv.dart';
import 'package:tagkin_desktop/item_lists/item_list_json.dart';
import 'package:tagkin_desktop/persons/collection.dart';

import '../fake_items_repository.dart';
import 'fake_item_lists_repository.dart';

void main() {
  test('itemListToJson includes path, selected view, description, and row order',
      () {
    final exportedAt = DateTime.utc(2026, 9, 11, 22, 42);
    final json = itemListToJson(
      entries: [
        fixtureEntry(
          itemId: 'photo-1',
          when: '2020-01-01T00:00:00.000Z',
          who: const ['Sam'],
          what: const ['swimming'],
        ),
        fixtureEntry(
          itemId: 'video-1',
          kind: ItemListEntryKind.keyperiod,
          keyPeriodId: 'kp-1',
          startMs: 1000,
          endMs: 4000,
          when: '2020-06-01T00:00:00.000Z',
          where: const ['park, beach'],
        ),
      ],
      itemsById: {
        'photo-1': fixtureItem(
          id: 'photo-1',
          sourceRef: 'file:///Pictures/Holiday.jpg',
        ),
        'video-1': fixtureItem(
          id: 'video-1',
          type: ItemType.video,
          sourceRef: 'file:///Pictures/clip.mp4',
        ),
      },
      view: const SavedView(
        id: 'v1',
        name: 'Beach',
        filters: LibraryViewFilters(
          whoNames: ['Sam'],
          filterQuery: 'swimming',
        ),
      ),
      description: 'Beach weekend with Sam',
      exportedAt: exportedAt,
    );
    final doc = jsonDecode(json) as Map<String, dynamic>;
    expect(doc['exportedAt'], '2026-09-11T22:42:00.000Z');
    expect(doc['description'], 'Beach weekend with Sam');
    final view = doc['view'] as Map<String, dynamic>;
    expect(view['id'], 'v1');
    expect(view['name'], 'Beach');
    expect((view['filters'] as Map)['whoNames'], ['Sam']);
    expect((view['filters'] as Map)['filterQuery'], 'swimming');
    final entries = doc['entries'] as List<dynamic>;
    expect(entries, hasLength(2));
    final photo = entries[0] as Map<String, dynamic>;
    expect(photo['kind'], 'photo');
    expect(photo['path'], '/Pictures/Holiday.jpg');
    expect(photo['itemId'], 'photo-1');
    expect(photo['who'], ['Sam']);
    final video = entries[1] as Map<String, dynamic>;
    expect(video['kind'], 'keyPeriod');
    expect(video['path'], '/Pictures/clip.mp4');
    expect(video['keyPeriodId'], 'kp-1');
    expect(video['startMs'], 1000);
    expect(video['where'], ['park, beach']);
  });

  test('itemListToJson writes view: null for All', () {
    final json = itemListToJson(
      entries: [fixtureEntry(itemId: 'photo-1')],
      itemsById: {
        'photo-1': fixtureItem(
          id: 'photo-1',
          sourceRef: 'file:///Pictures/Holiday.jpg',
        ),
      },
      exportedAt: DateTime.utc(2026, 1, 1),
    );
    final doc = jsonDecode(json) as Map<String, dynamic>;
    expect(doc['view'], isNull);
  });

  test('itemListEntryKindLabel uses canonical terms (R2)', () {
    expect(itemListEntryKindLabel(ItemListEntryKind.photo), 'Photo');
    expect(itemListEntryKindLabel(ItemListEntryKind.keyperiod), 'Key period');
  });

  test('formatKeyPeriodMs is m:ss', () {
    expect(formatKeyPeriodMs(0), '0:00');
    expect(formatKeyPeriodMs(65000), '1:05');
    expect(formatKeyPeriodMs(3600000), '1:00:00');
  });
}
