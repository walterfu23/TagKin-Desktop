import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/item_lists/item_list_csv.dart';
import 'package:tagkin_desktop/item_lists/item_list_export_controller.dart';

import '../fake_items_repository.dart';
import '../fake_persons_repository.dart';
import 'fake_item_lists_repository.dart';

void main() {
  test('buildFilter omits empty dimensions and encodes when as ISO', () {
    final repo = FakeItemListsRepository();
    final controller = ItemListExportController(
      repository: repo,
      itemsRepository: FakeItemsRepository(),
    );
    controller.toggleWho('Sam');
    controller.toggleWhat('swimming');
    controller.setWhenFromDay(DateTime(2020, 1, 15));
    controller.setWhenToDay(DateTime(2020, 2, 1));

    final filter = controller.buildFilter();
    expect(filter.who, ['Sam']);
    expect(filter.what, ['swimming']);
    expect(filter.where, isNull);
    expect(filter.whenFrom, itemListWhenFromIso(DateTime(2020, 1, 15)));
    expect(filter.whenTo, itemListWhenToIso(DateTime(2020, 2, 1)));
  });

  test('reorder updates export JSON order', () async {
    final a = fixtureEntry(itemId: 'a', when: '2020-01-01T00:00:00.000Z');
    final b = fixtureEntry(itemId: 'b', when: '2020-02-01T00:00:00.000Z');
    String? saved;
    final repo = FakeItemListsRepository(list: ItemList(entries: [a, b]));
    final controller = ItemListExportController(
      repository: repo,
      itemsRepository: FakeItemsRepository(
        items: [
          fixtureItem(id: 'a', sourceRef: 'file:///albums/a.jpg'),
          fixtureItem(id: 'b', sourceRef: 'file:///albums/b.jpg'),
        ],
      ),
      saveJson: (json) async {
        saved = json;
        return '/tmp/item-list.json';
      },
    );
    await controller.preview();
    expect(controller.entries.map((e) => e.itemId), ['a', 'b']);
    controller.reorder(0, 1);
    expect(controller.entries.map((e) => e.itemId), ['b', 'a']);
    final path = await controller.exportJson(
      hideBlurry: false,
      description: 'Trip',
      exportedAt: DateTime.utc(2026, 9, 11, 12),
    );
    expect(path, '/tmp/item-list.json');
    final doc = jsonDecode(saved!) as Map<String, dynamic>;
    expect(doc['description'], 'Trip');
    expect(doc['exportedAt'], '2026-09-11T12:00:00.000Z');
    final entries = doc['entries'] as List<dynamic>;
    expect((entries[0] as Map)['itemId'], 'b');
    expect((entries[0] as Map)['path'], '/albums/b.jpg');
    expect((entries[1] as Map)['itemId'], 'a');
  });

  test('removeAt drops the row from JSON export', () async {
    final a = fixtureEntry(itemId: 'a', when: '2020-01-01T00:00:00.000Z');
    final b = fixtureEntry(itemId: 'b', when: '2020-02-01T00:00:00.000Z');
    String? saved;
    final repo = FakeItemListsRepository(list: ItemList(entries: [a, b]));
    final controller = ItemListExportController(
      repository: repo,
      itemsRepository: FakeItemsRepository(
        items: [
          fixtureItem(id: 'a'),
          fixtureItem(id: 'b'),
        ],
      ),
      saveJson: (json) async {
        saved = json;
        return '/tmp/item-list.json';
      },
    );
    await controller.preview();
    controller.removeAt(0);
    expect(controller.entries.map((e) => e.itemId), ['b']);
    await controller.exportJson(hideBlurry: false);
    final ids = (jsonDecode(saved!)['entries'] as List<dynamic>)
        .map((e) => (e as Map)['itemId'])
        .toList();
    expect(ids, ['b']);
  });

  test('preview passes the current filter to the server', () async {
    final repo = FakeItemListsRepository();
    final controller = ItemListExportController(
      repository: repo,
      itemsRepository: FakeItemsRepository(),
    );
    controller.toggleWhere('park');
    await controller.preview();
    expect(repo.lastFilter?.where, ['park']);
  });

  test('export JSON records the last Preview filter, not later chip changes',
      () async {
    String? saved;
    final repo = FakeItemListsRepository(
      list: ItemList(entries: [fixtureEntry(itemId: 'a')]),
    );
    final controller = ItemListExportController(
      repository: repo,
      itemsRepository: FakeItemsRepository(
        items: [fixtureItem(id: 'a', sourceRef: 'file:///albums/a.jpg')],
      ),
      saveJson: (json) async {
        saved = json;
        return '/tmp/item-list.json';
      },
    );
    controller.toggleWhere('park');
    await controller.preview();
    controller.toggleWho('Sam');
    await controller.exportJson(
      hideBlurry: false,
      exportedAt: DateTime.utc(2026, 1, 1),
    );
    final filters = jsonDecode(saved!)['filters'] as Map<String, dynamic>;
    expect(filters['where'], ['park']);
    expect(filters['who'], <dynamic>[]);
  });

  test('timestampMsFor prefers key-period sampleTimestampMs', () async {
    final entry = fixtureEntry(
      itemId: 'video-1',
      kind: ItemListEntryKind.keyperiod,
      keyPeriodId: 'kp-1',
      startMs: 0,
      endMs: 2000,
    );
    final item = fixtureItem(id: 'video-1', type: ItemType.video);
    final controller = ItemListExportController(
      repository: FakeItemListsRepository(list: ItemList(entries: [entry])),
      itemsRepository: FakeItemsRepository(
        items: [item],
        knowledgeByItemId: {
          'video-1': fixtureKnowledge(
            item: item,
            keyPeriods: [
              KeyPeriodKnowledge(
                id: 'kp-1',
                itemId: 'video-1',
                startMs: 0,
                endMs: 2000,
                sampleTimestampMs: 800,
                tags: const [],
              ),
            ],
          ),
        },
      ),
    );
    await controller.preview();
    await controller.knowledgeFor('video-1');
    expect(controller.timestampMsFor(entry), 800);
  });

  test('visibleEntries hides from stored sharpness immediately', () async {
    final sharp = fixtureEntry(itemId: 'sharp');
    final blurry = fixtureEntry(itemId: 'blurry');
    final controller = ItemListExportController(
      repository: FakeItemListsRepository(
        list: ItemList(entries: [sharp, blurry]),
      ),
      itemsRepository: FakeItemsRepository(
        items: [
          fixtureItem(id: 'sharp', sharpness: 400),
          fixtureItem(id: 'blurry', sharpness: 5),
        ],
      ),
    );
    await controller.preview();
    expect(
      controller.visibleEntries(hideBlurry: true).map((e) => e.itemId),
      ['sharp'],
    );
    expect(
      controller.visibleEntries(hideBlurry: false).map((e) => e.itemId),
      ['sharp', 'blurry'],
    );
  });

  test('visibleEntries stored-blurry stays hidden (no live unhide)', () async {
    final blurry = fixtureEntry(itemId: 'blurry');
    final controller = ItemListExportController(
      repository: FakeItemListsRepository(
        list: ItemList(entries: [blurry]),
      ),
      itemsRepository: FakeItemsRepository(
        items: [fixtureItem(id: 'blurry', sharpness: 5)],
      ),
    );
    await controller.preview();
    expect(controller.visibleEntries(hideBlurry: true), isEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(controller.visibleEntries(hideBlurry: true), isEmpty);
  });

  test('visibleEntries ignores Who face-crop scores (photos only)', () async {
    final a = fixtureEntry(itemId: 'a', who: const ['Sam']);
    final b = fixtureEntry(itemId: 'b', who: const ['Sam']);
    final itemA = fixtureItem(id: 'a', sharpness: 400);
    final itemB = fixtureItem(id: 'b', sharpness: 400);
    final controller = ItemListExportController(
      repository: FakeItemListsRepository(list: ItemList(entries: [a, b])),
      itemsRepository: FakeItemsRepository(
        items: [itemA, itemB],
        knowledgeByItemId: {
          'a': fixtureKnowledge(
            item: itemA,
            appearances: [
              fixtureAppearance(
                id: 'ap_a',
                personId: 'p1',
                itemId: 'a',
                sharpness: 4,
                region: const TagRegion(
                  yMin: 0.1,
                  xMin: 0.1,
                  yMax: 0.4,
                  xMax: 0.4,
                ),
              ),
            ],
          ),
          'b': fixtureKnowledge(
            item: itemB,
            appearances: [
              fixtureAppearance(
                id: 'ap_b',
                personId: 'p1',
                itemId: 'b',
                sharpness: 400,
                region: const TagRegion(
                  yMin: 0.1,
                  xMin: 0.1,
                  yMax: 0.4,
                  xMax: 0.4,
                ),
              ),
            ],
          ),
        },
      ),
    );
    await controller.preview();
    controller.personNameById = const {'p1': 'Sam'};
    controller.toggleWho('Sam');
    expect(
      controller.visibleEntries(hideBlurry: true).map((e) => e.itemId),
      ['a', 'b'],
    );
  });

  test('visibleEntries keeps photos with unknown (null) stored score',
      () async {
    final unknown = fixtureEntry(itemId: 'unknown');
    final controller = ItemListExportController(
      repository: FakeItemListsRepository(
        list: ItemList(entries: [unknown]),
      ),
      itemsRepository: FakeItemsRepository(
        items: [fixtureItem(id: 'unknown')],
      ),
    );
    await controller.preview();
    expect(
      controller.visibleEntries(hideBlurry: true).map((e) => e.itemId),
      ['unknown'],
    );
  });

  test('visibleEntries uses a custom sharpness bar', () async {
    final mid = fixtureEntry(itemId: 'mid');
    final controller = ItemListExportController(
      repository: FakeItemListsRepository(
        list: ItemList(entries: [mid]),
      ),
      itemsRepository: FakeItemsRepository(
        items: [fixtureItem(id: 'mid', sharpness: 100)],
      ),
    );
    await controller.preview();
    expect(
      controller.visibleEntries(hideBlurry: true, threshold: 200),
      isEmpty,
    );
  });

  test('visibleEntries keeps key periods', () async {
    final photo = fixtureEntry(itemId: 'photo');
    final period = fixtureEntry(
      itemId: 'video-1',
      kind: ItemListEntryKind.keyperiod,
      keyPeriodId: 'kp-1',
      startMs: 0,
      endMs: 1000,
    );
    final controller = ItemListExportController(
      repository: FakeItemListsRepository(
        list: ItemList(entries: [photo, period]),
      ),
      itemsRepository: FakeItemsRepository(
        items: [
          fixtureItem(id: 'photo', sharpness: 1),
          fixtureItem(id: 'video-1', type: ItemType.video),
        ],
      ),
    );
    await controller.preview();
    expect(
      controller.visibleEntries(hideBlurry: true).map((e) => e.itemId),
      ['video-1'],
    );
  });

  test('exportJson(hideBlurry: true) excludes hidden photos from the file',
      () async {
    final sharp = fixtureEntry(itemId: 'sharp');
    final blurry = fixtureEntry(itemId: 'blurry');
    String? saved;
    final controller = ItemListExportController(
      repository: FakeItemListsRepository(
        list: ItemList(entries: [sharp, blurry]),
      ),
      itemsRepository: FakeItemsRepository(
        items: [
          fixtureItem(
            id: 'sharp',
            sharpness: 400,
            sourceRef: 'file:///albums/sharp.jpg',
          ),
          fixtureItem(
            id: 'blurry',
            sharpness: 5,
            sourceRef: 'file:///albums/blurry.jpg',
          ),
        ],
      ),
      saveJson: (json) async {
        saved = json;
        return '/tmp/item-list.json';
      },
    );
    await controller.preview();
    await controller.exportJson(hideBlurry: true);
    final ids = (jsonDecode(saved!)['entries'] as List<dynamic>)
        .map((e) => (e as Map)['itemId'])
        .toList();
    expect(ids, ['sharp']);
  });
}
