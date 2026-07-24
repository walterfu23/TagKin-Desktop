import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/library/local_thumb_cache.dart';
import 'package:tagkin_desktop/where/reverse_geocoder.dart';
import 'package:tagkin_desktop/where/where_label_resolver.dart';
import 'package:tagkin_desktop/where/where_place_label.dart';

import 'fake_comments_repository.dart';
import 'fake_items_repository.dart';

Future<void> _awaitKnowledge(LibraryTableController c) async {
  for (var i = 0; i < 20; i++) {
    if (c.allRows.every((r) => r.knowledgeLoaded && r.commentsLoaded)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test('load fills who/what/where and item-level comments', () async {
    final a = fixtureItem(id: 'a', processingStatus: ProcessingStatus.tagged);
    final b = fixtureItem(id: 'b', processingStatus: ProcessingStatus.tagged);
    final items = FakeItemsRepository(
      items: [a, b],
      knowledgeByItemId: {
        'a': fixtureKnowledge(
          item: a,
          tags: [
            fixtureTag(id: 'w1', itemId: 'a', dimension: 'who', value: 'Sam'),
            fixtureTag(id: 't1', itemId: 'a', dimension: 'what', value: 'swim'),
            fixtureTag(id: 'r1', itemId: 'a', dimension: 'where', value: 'pool'),
          ],
        ),
        'b': fixtureKnowledge(
          item: b,
          tags: [
            fixtureTag(id: 'w2', itemId: 'b', dimension: 'who', value: 'Ada'),
            fixtureTag(id: 't2', itemId: 'b', dimension: 'what', value: 'hike'),
            fixtureTag(
              id: 'r2',
              itemId: 'b',
              dimension: 'where',
              value: 'trail',
            ),
          ],
        ),
      },
    );
    final comments = FakeCommentsRepository(
      comments: [
        fixtureComment(id: 'c1', itemId: 'a', body: 'nice day'),
        fixtureComment(
          id: 'c2',
          itemId: 'a',
          keyPeriodId: 'kp1',
          body: 'ignored key-period',
        ),
      ],
    );
    final controller = LibraryTableController(
      itemsRepository: items,
      commentsRepository: comments,
      thumbCache: LocalThumbCache(),
      knowledgeConcurrency: 2,
    );
    await controller.load();
    await _awaitKnowledge(controller);

    expect(controller.allRows, hasLength(2));
    final rowA = controller.allRows.firstWhere((r) => r.item.id == 'a');
    expect(rowA.who, ['Sam']);
    expect(rowA.what, ['swim']);
    expect(rowA.where, ['pool']);
    expect(rowA.comments, ['nice day']);
    expect(rowA.knowledgeLoaded, isTrue);
    expect(rowA.commentsLoaded, isTrue);
  });

  test('GPS where tags become city/state labels', () async {
    final item = fixtureItem(id: 'g', processingStatus: ProcessingStatus.tagged);
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {
        'g': fixtureKnowledge(
          item: item,
          tags: [
            fixtureTag(
              id: 'gps',
              itemId: 'g',
              dimension: 'where',
              value: '37.77,-122.42',
            ),
            fixtureTag(
              id: 'scene',
              itemId: 'g',
              dimension: 'where',
              value: 'restaurant',
            ),
          ],
        ),
      },
    );
    final controller = LibraryTableController(
      itemsRepository: items,
      commentsRepository: FakeCommentsRepository(),
      thumbCache: LocalThumbCache(),
      whereLabelResolver: WhereLabelResolver(
        geocoder: FakeReverseGeocoder({
          FakeReverseGeocoder.key(37.77, -122.42): const PlaceParts(
            locality: 'San Francisco',
            administrativeArea: 'CA',
            country: 'United States',
            isoCountryCode: 'US',
          ),
        }),
        deviceCountryCodeProvider: () => 'US',
      ),
    );
    await controller.load();
    await _awaitKnowledge(controller);

    final row = controller.allRows.single;
    expect(row.where, ['San Francisco, CA', 'restaurant']);
  });

  test('sort cycles asc → desc → none; multiColumn appends tie-break keys',
      () async {
    final items = <Item>[];
    final knowledge = <String, ItemKnowledge>{};
    for (var i = 0; i < 4; i++) {
      final id = 'item_$i';
      final item = fixtureItem(
        id: id,
        processingStatus: ProcessingStatus.tagged,
      );
      items.add(item);
      knowledge[id] = fixtureKnowledge(
        item: item,
        tags: [
          fixtureTag(
            id: 'who_$i',
            itemId: id,
            dimension: 'who',
            value: i < 2 ? 'Sam' : 'Ada',
          ),
          fixtureTag(
            id: 'what_$i',
            itemId: id,
            dimension: 'what',
            value: i.isEven ? 'zoo' : 'apple',
          ),
        ],
      );
    }
    final repo = FakeItemsRepository(items: items, knowledgeByItemId: knowledge);
    final controller = LibraryTableController(
      itemsRepository: repo,
      commentsRepository: FakeCommentsRepository(),
      thumbCache: LocalThumbCache(),
      pageSize: 50,
      knowledgeConcurrency: 4,
    );
    await controller.load();
    await _awaitKnowledge(controller);

    controller.toggleSort(LibrarySortColumn.who);
    expect(controller.sortKeys, hasLength(1));
    expect(controller.sortKeys.first.ascending, isTrue);
    expect(controller.filteredSorted.first.who.first, 'Ada');

    controller.toggleSort(LibrarySortColumn.who);
    expect(controller.sortKeys.first.ascending, isFalse);
    expect(controller.filteredSorted.first.who.first, 'Sam');

    controller.toggleSort(LibrarySortColumn.who);
    expect(controller.sortKeys, isEmpty);

    controller.toggleSort(LibrarySortColumn.who);
    controller.toggleSort(LibrarySortColumn.what, multiColumn: true);
    expect(controller.sortKeys, hasLength(2));
    // Within Ada (asc), apple before zoo.
    final adaRows =
        controller.filteredSorted.where((r) => r.who.first == 'Ada').toList();
    expect(adaRows.first.what.first, 'apple');
    expect(adaRows.last.what.first, 'zoo');

    // Multi-cycle secondary: desc then remove.
    controller.toggleSort(LibrarySortColumn.what, multiColumn: true);
    expect(controller.sortKeys.last.ascending, isFalse);
    controller.toggleSort(LibrarySortColumn.what, multiColumn: true);
    expect(controller.sortKeys, hasLength(1));

    // Stack two keys then collapse when multi-column is turned off.
    controller.toggleSort(LibrarySortColumn.what, multiColumn: true);
    expect(controller.sortKeys, hasLength(2));
    controller.enforceSingleColumn();
    expect(controller.sortKeys, hasLength(1));
    expect(controller.sortKeys.first.column, LibrarySortColumn.who);
  });

  test('who sort is case-insensitive', () async {
    final names = ['sam', 'Bob', 'ada'];
    final items = <Item>[];
    final knowledge = <String, ItemKnowledge>{};
    for (var i = 0; i < names.length; i++) {
      final id = 'item_$i';
      final item = fixtureItem(
        id: id,
        processingStatus: ProcessingStatus.tagged,
      );
      items.add(item);
      knowledge[id] = fixtureKnowledge(
        item: item,
        tags: [
          fixtureTag(
            id: 'who_$i',
            itemId: id,
            dimension: 'who',
            value: names[i],
          ),
        ],
      );
    }
    final controller = LibraryTableController(
      itemsRepository: FakeItemsRepository(
        items: items,
        knowledgeByItemId: knowledge,
      ),
      commentsRepository: FakeCommentsRepository(),
      thumbCache: LocalThumbCache(),
      knowledgeConcurrency: 3,
    );
    await controller.load();
    await _awaitKnowledge(controller);

    controller.toggleSort(LibrarySortColumn.who);
    expect(
      controller.filteredSorted.map((r) => r.who.first).toList(),
      ['ada', 'Bob', 'sam'],
    );
  });

  test('filter and pagination', () async {
    final items = <Item>[];
    final knowledge = <String, ItemKnowledge>{};
    for (var i = 0; i < 5; i++) {
      final id = 'item_$i';
      final item = fixtureItem(
        id: id,
        processingStatus: ProcessingStatus.tagged,
      );
      items.add(item);
      knowledge[id] = fixtureKnowledge(
        item: item,
        tags: [
          fixtureTag(
            id: 'who_$i',
            itemId: id,
            dimension: 'who',
            value: i.isEven ? 'Sam' : 'Ada',
          ),
        ],
      );
    }
    final repo = FakeItemsRepository(items: items, knowledgeByItemId: knowledge);
    final controller = LibraryTableController(
      itemsRepository: repo,
      commentsRepository: FakeCommentsRepository(),
      thumbCache: LocalThumbCache(),
      pageSize: 2,
      knowledgeConcurrency: 4,
    );
    await controller.load();
    await _awaitKnowledge(controller);

    controller.setFilterQuery('Sam');
    expect(controller.totalFiltered, 3);
    expect(controller.pageCount, 2);
    expect(controller.pageRows, hasLength(2));
    controller.setPage(1);
    expect(controller.pageRows, hasLength(1));
  });
}
