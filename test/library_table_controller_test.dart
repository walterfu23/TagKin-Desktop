import 'dart:async';

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

  test('shared source dir collapses; toggle expands basename rows', () async {
    final shared = '/users/w/test';
    final a = fixtureItem(
      id: 'a',
      sourceRef: 'file://$shared/a.jpg',
      processingStatus: ProcessingStatus.tagged,
    );
    final b = fixtureItem(
      id: 'b',
      sourceRef: 'file://$shared/b.mp4',
      processingStatus: ProcessingStatus.tagged,
    );
    final c = fixtureItem(
      id: 'c',
      sourceRef: 'file:///users/w/other/c.jpg',
      processingStatus: ProcessingStatus.tagged,
    );
    final controller = LibraryTableController(
      itemsRepository: FakeItemsRepository(items: [a, b, c]),
      commentsRepository: FakeCommentsRepository(),
      thumbCache: LocalThumbCache(),
      knowledgeConcurrency: 3,
    );
    await controller.load();

    // Common ancestor /users/w has two child folders → auto-expanded.
    // File group /users/w/test stays collapsed by default.
    final initial = controller.visibleEntries;
    expect(initial, hasLength(3)); // /users/w + test group + other singleton
    expect(
      initial[0],
      isA<LibraryPathGroupHeader>()
          .having((h) => h.dir, 'dir', '/users/w')
          .having((h) => h.count, 'count', 3)
          .having((h) => h.collapsed, 'collapsed', isFalse),
    );
    expect(
      initial[1],
      isA<LibraryPathGroupHeader>()
          .having((h) => h.dir, 'dir', shared)
          .having((h) => h.label, 'label', 'test')
          .having((h) => h.count, 'count', 2)
          .having((h) => h.collapsed, 'collapsed', isTrue),
    );
    expect(
      initial[2],
      isA<LibraryItemEntry>()
          .having((e) => e.row.item.id, 'id', 'c')
          .having((e) => e.sourceDisplay, 'display', 'other/c.jpg'),
    );

    controller.toggleCollapseSourceDir(shared);
    final expanded = controller.visibleEntries;
    expect(expanded, hasLength(5)); // /users/w + test header + a + b + c
    expect(
      expanded[2],
      isA<LibraryItemEntry>()
          .having((e) => e.row.item.id, 'id', 'a')
          .having((e) => e.sourceDisplay, 'display', 'a.jpg'),
    );
    expect(
      expanded[3],
      isA<LibraryItemEntry>()
          .having((e) => e.row.item.id, 'id', 'b')
          .having((e) => e.sourceDisplay, 'display', 'b.mp4'),
    );
  });

  test('date folders under shared parent are expanded; file groups stay collapsed',
      () async {
    const root = '/users/w/test';
    final a = fixtureItem(
      id: 'a',
      sourceRef: 'file://$root/20260508/a.jpg',
      processingStatus: ProcessingStatus.tagged,
    );
    final b = fixtureItem(
      id: 'b',
      sourceRef: 'file://$root/20260508/b.jpg',
      processingStatus: ProcessingStatus.tagged,
    );
    final c = fixtureItem(
      id: 'c',
      sourceRef: 'file://$root/20260506/c.jpg',
      processingStatus: ProcessingStatus.tagged,
    );
    final controller = LibraryTableController(
      itemsRepository: FakeItemsRepository(items: [a, b, c]),
      commentsRepository: FakeCommentsRepository(),
      thumbCache: LocalThumbCache(),
      knowledgeConcurrency: 3,
    );
    await controller.load();

    final mid = controller.visibleEntries;
    expect(mid, hasLength(3)); // root header + 20260508 group + singleton c
    expect(
      mid[0],
      isA<LibraryPathGroupHeader>()
          .having((h) => h.dir, 'dir', root)
          .having((h) => h.count, 'count', 3)
          .having((h) => h.collapsed, 'collapsed', isFalse),
    );
    expect(
      mid[1],
      isA<LibraryPathGroupHeader>()
          .having((h) => h.dir, 'dir', '$root/20260508')
          .having((h) => h.label, 'label', '20260508')
          .having((h) => h.count, 'count', 2)
          .having((h) => h.collapsed, 'collapsed', isTrue),
    );
    expect(
      mid[2],
      isA<LibraryItemEntry>()
          .having((e) => e.row.item.id, 'id', 'c')
          .having((e) => e.sourceDisplay, 'display', '20260506/c.jpg'),
    );

    controller.toggleCollapseSourceDir('$root/20260508');
    final open = controller.visibleEntries;
    expect(open, hasLength(5));
    expect(
      open[2],
      isA<LibraryItemEntry>()
          .having((e) => e.sourceDisplay, 'display', 'a.jpg'),
    );
    expect(
      open[3],
      isA<LibraryItemEntry>()
          .having((e) => e.sourceDisplay, 'display', 'b.jpg'),
    );
  });

  test('adding a sibling album auto-expands the shared parent', () async {
    const root = '/users/w/albums';
    final day1 = fixtureItem(
      id: 'd1',
      sourceRef: 'file://$root/Day1/a.jpg',
      processingStatus: ProcessingStatus.tagged,
    );
    final day2 = fixtureItem(
      id: 'd2',
      sourceRef: 'file://$root/Day2/b.jpg',
      processingStatus: ProcessingStatus.tagged,
    );
    final repo = FakeItemsRepository(items: [day1]);
    final controller = LibraryTableController(
      itemsRepository: repo,
      commentsRepository: FakeCommentsRepository(),
      thumbCache: LocalThumbCache(),
      knowledgeConcurrency: 3,
    );
    await controller.load();

    // Single album — no multi-child parent header.
    expect(
      controller.visibleEntries.whereType<LibraryPathGroupHeader>(),
      isEmpty,
    );
    expect(controller.visibleEntries, hasLength(1));

    repo.addItem(day2);
    await controller.load();

    final entries = controller.visibleEntries;
    expect(
      entries[0],
      isA<LibraryPathGroupHeader>()
          .having((h) => h.dir, 'dir', root)
          .having((h) => h.collapsed, 'collapsed', isFalse),
    );
    // Both child albums visible as item rows (singletons under expanded parent).
    expect(
      entries.whereType<LibraryItemEntry>().map((e) => e.row.item.id),
      containsAll(['d1', 'd2']),
    );
  });

  test('file-only shared dir stays collapsed by default', () async {
    const shared = '/users/w/test';
    final a = fixtureItem(
      id: 'a',
      sourceRef: 'file://$shared/a.jpg',
      processingStatus: ProcessingStatus.tagged,
    );
    final b = fixtureItem(
      id: 'b',
      sourceRef: 'file://$shared/b.jpg',
      processingStatus: ProcessingStatus.tagged,
    );
    final controller = LibraryTableController(
      itemsRepository: FakeItemsRepository(items: [a, b]),
      commentsRepository: FakeCommentsRepository(),
      thumbCache: LocalThumbCache(),
      knowledgeConcurrency: 3,
    );
    await controller.load();

    expect(controller.visibleEntries, hasLength(1));
    expect(
      controller.visibleEntries.single,
      isA<LibraryPathGroupHeader>()
          .having((h) => h.dir, 'dir', shared)
          .having((h) => h.collapsed, 'collapsed', isTrue),
    );
  });

  test('filter that leaves one file in a group becomes a singleton', () async {
    const shared = '/users/w/test';
    final a = fixtureItem(
      id: 'a',
      sourceRef: 'file://$shared/alpha.jpg',
      processingStatus: ProcessingStatus.tagged,
    );
    final b = fixtureItem(
      id: 'b',
      sourceRef: 'file://$shared/beta.jpg',
      processingStatus: ProcessingStatus.tagged,
    );
    final controller = LibraryTableController(
      itemsRepository: FakeItemsRepository(
        items: [a, b],
        knowledgeByItemId: {
          'a': fixtureKnowledge(
            item: a,
            tags: [
              fixtureTag(id: 'wa', itemId: 'a', dimension: 'who', value: 'Sam'),
            ],
          ),
          'b': fixtureKnowledge(
            item: b,
            tags: [
              fixtureTag(id: 'wb', itemId: 'b', dimension: 'who', value: 'Ada'),
            ],
          ),
        },
      ),
      commentsRepository: FakeCommentsRepository(),
      thumbCache: LocalThumbCache(),
      knowledgeConcurrency: 2,
    );
    await controller.load();
    await _awaitKnowledge(controller);

    expect(controller.visibleEntries.single, isA<LibraryPathGroupHeader>());

    controller.setFilterQuery('Ada');
    final visible = controller.visibleEntries;
    expect(visible, hasLength(1));
    expect(
      visible.single,
      isA<LibraryItemEntry>()
          .having((e) => e.row.item.id, 'id', 'b')
          .having((e) => e.sourceDisplay, 'display', '/users/w/test/beta.jpg'),
    );
  });

  test('expanded source folder stays open after reload removes an item', () async {
    const shared = '/users/w/photos';
    final a = fixtureItem(
      id: 'a',
      sourceRef: 'file://$shared/a.jpg',
      processingStatus: ProcessingStatus.tagged,
    );
    final b = fixtureItem(
      id: 'b',
      sourceRef: 'file://$shared/b.jpg',
      processingStatus: ProcessingStatus.tagged,
    );
    final items = FakeItemsRepository(items: [a, b]);
    final controller = LibraryTableController(
      itemsRepository: items,
      commentsRepository: FakeCommentsRepository(),
      thumbCache: LocalThumbCache(),
      knowledgeConcurrency: 2,
    );
    await controller.load();

    final header = controller.visibleEntries
        .whereType<LibraryPathGroupHeader>()
        .single;
    expect(header.collapsed, isTrue);
    controller.toggleCollapseSourceDir(header.dir);
    expect(controller.expandedSourceDirs.contains(header.dir), isTrue);
    expect(
      controller.visibleEntries.whereType<LibraryItemEntry>(),
      hasLength(2),
    );

    // Simulate delete of one item then list reload (same as UI _retry).
    items.removeItem('a');
    await controller.load();

    expect(controller.expandedSourceDirs.contains(header.dir), isTrue);
    expect(controller.allRows, hasLength(1));
    expect(
      controller.visibleEntries.whereType<LibraryItemEntry>(),
      hasLength(1),
    );
  });

  test('adoptItem updates processingStatus and keeps who/what', () async {
    final failed = fixtureItem(
      id: 'a',
      sourceRef: 'file:///albums/x/a.jpg',
      processingStatus: ProcessingStatus.failed,
    );
    final items = FakeItemsRepository(
      items: [failed],
      knowledgeByItemId: {
        'a': fixtureKnowledge(
          item: failed,
          tags: [
            fixtureTag(id: 'w1', itemId: 'a', dimension: 'who', value: 'Sam'),
            fixtureTag(id: 't1', itemId: 'a', dimension: 'what', value: 'swim'),
          ],
        ),
      },
    );
    final controller = LibraryTableController(
      itemsRepository: items,
      commentsRepository: FakeCommentsRepository(),
      thumbCache: LocalThumbCache(),
      knowledgeConcurrency: 1,
    );
    await controller.load();
    await _awaitKnowledge(controller);

    expect(
      controller.allRows.single.item.processingStatus,
      ProcessingStatus.failed,
    );
    expect(controller.allRows.single.who, ['Sam']);
    expect(controller.allRows.single.what, ['swim']);

    controller.adoptItem(
      fixtureItem(
        id: 'a',
        sourceRef: 'file:///albums/x/a.jpg',
        processingStatus: ProcessingStatus.tagged,
      ),
    );

    expect(
      controller.allRows.single.item.processingStatus,
      ProcessingStatus.tagged,
    );
    expect(controller.allRows.single.who, ['Sam']);
    expect(controller.allRows.single.what, ['swim']);
  });

  test('adoptItem insert then load keeps tagged over stale pending fetch',
      () async {
    final pending = fixtureItem(
      id: 'a',
      sourceRef: 'file:///albums/x/a.jpg',
      processingStatus: ProcessingStatus.pending,
    );
    final items = FakeItemsRepository(items: [pending]);
    final controller = LibraryTableController(
      itemsRepository: items,
      commentsRepository: FakeCommentsRepository(),
      thumbCache: LocalThumbCache(),
      knowledgeConcurrency: 1,
    );
    await controller.load();
    expect(
      controller.allRows.single.item.processingStatus,
      ProcessingStatus.pending,
    );

    controller.adoptItem(
      fixtureItem(
        id: 'a',
        sourceRef: 'file:///albums/x/a.jpg',
        processingStatus: ProcessingStatus.tagged,
      ),
    );
    await controller.load();

    expect(
      controller.allRows.single.item.processingStatus,
      ProcessingStatus.tagged,
    );
  });

  test('adoptItem inserts a row when the id is not loaded yet', () async {
    final items = FakeItemsRepository();
    final controller = LibraryTableController(
      itemsRepository: items,
      commentsRepository: FakeCommentsRepository(),
      thumbCache: LocalThumbCache(),
      knowledgeConcurrency: 1,
    );
    await controller.load();
    expect(controller.allRows, isEmpty);

    controller.adoptItem(
      fixtureItem(
        id: 'new_item',
        processingStatus: ProcessingStatus.tagged,
      ),
    );
    expect(controller.allRows, hasLength(1));
    expect(controller.allRows.single.item.id, 'new_item');
    expect(
      controller.allRows.single.item.processingStatus,
      ProcessingStatus.tagged,
    );
  });

  test('refresh after first load does not set loading', () async {
    final pending = fixtureItem(id: 'a');
    var gate = Completer<void>();
    var lists = 0;
    final items = FakeItemsRepository(
      items: [pending],
      onListItems: () async {
        lists++;
        if (lists > 1) await gate.future;
      },
    );
    final controller = LibraryTableController(
      itemsRepository: items,
      commentsRepository: FakeCommentsRepository(),
      thumbCache: LocalThumbCache(),
      knowledgeConcurrency: 1,
    );
    await controller.load();
    expect(controller.loading, isFalse);
    expect(controller.hasLoadedOnce, isTrue);

    final second = controller.load();
    await Future<void>.delayed(Duration.zero);
    expect(controller.loading, isFalse);
    gate.complete();
    await second;
    expect(controller.loading, isFalse);
  });
}
