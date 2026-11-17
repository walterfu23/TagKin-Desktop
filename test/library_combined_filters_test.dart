import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/folders_undo_recorder.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/library/local_thumb_cache.dart';
import 'package:tagkin_desktop/library/views_menu.dart';
import 'package:tagkin_desktop/persons/collection.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/persons/collections_store.dart';
import 'package:tagkin_desktop/undo/undo_controller.dart';

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

Set<String> _ids(LibraryTableController c) =>
    c.filteredSorted.map((r) => r.item.id).toSet();

/// Five tagged photos:
///   a  Sam+Ada  Seattle   swim  2026-07-01
///   b  Sam      Seattle   swim  2026-08-15
///   c  Sam+Ada  Portland  hike  2026-07-10
///   d  Ada      Seattle   swim  2026-07-02
///   e  Sam+Ada  Seattle   swim  (no captured date)
Future<LibraryTableController> _buildController() async {
  Item photo(String id, String? capturedAt) => fixtureItem(
    id: id,
    processingStatus: ProcessingStatus.tagged,
    capturedAt: capturedAt,
  );
  final a = photo('a', '2026-07-01T12:00:00.000Z');
  final b = photo('b', '2026-08-15T12:00:00.000Z');
  final c = photo('c', '2026-07-10T12:00:00.000Z');
  final d = photo('d', '2026-07-02T12:00:00.000Z');
  final e = photo('e', null);

  ItemKnowledge knowledge(
    Item item, {
    required List<String> who,
    required String what,
    required String where,
  }) {
    var n = 0;
    Tag tag(String dimension, String value) => fixtureTag(
      id: '${item.id}_${n++}',
      itemId: item.id,
      dimension: dimension,
      value: value,
    );
    return fixtureKnowledge(
      item: item,
      tags: [
        for (final w in who) tag('who', w),
        tag('what', what),
        tag('where', where),
      ],
    );
  }

  final controller = LibraryTableController(
    itemsRepository: FakeItemsRepository(
      items: [a, b, c, d, e],
      knowledgeByItemId: {
        'a': knowledge(a, who: ['Sam', 'Ada'], what: 'swim', where: 'Seattle'),
        'b': knowledge(b, who: ['Sam'], what: 'swim', where: 'Seattle'),
        'c': knowledge(c, who: ['Sam', 'Ada'], what: 'hike', where: 'Portland'),
        'd': knowledge(d, who: ['Ada'], what: 'swim', where: 'Seattle'),
        'e': knowledge(e, who: ['Sam', 'Ada'], what: 'swim', where: 'Seattle'),
      },
    ),
    commentsRepository: FakeCommentsRepository(),
    thumbCache: LocalThumbCache(),
    knowledgeConcurrency: 3,
  );
  addTearDown(controller.dispose);
  await controller.load();
  await _awaitKnowledge(controller);
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Where filter', () {
    test('defaults to no selection and Match Any', () async {
      final c = await _buildController();
      expect(c.whereFilterNames, isEmpty);
      expect(c.whereFilterMatchAll, isFalse);
      expect(_ids(c), {'a', 'b', 'c', 'd', 'e'});
    });

    test('Match Any keeps rows with any selected place', () async {
      final c = await _buildController();
      c.setWhereFilter(names: {'Portland'});
      expect(_ids(c), {'c'});
      c.setWhereFilter(names: {'Portland', 'Seattle'});
      expect(_ids(c), {'a', 'b', 'c', 'd', 'e'});
    });

    test('Match All needs every selected place on the row', () async {
      final c = await _buildController();
      c.setWhereFilter(names: {'Portland', 'Seattle'}, matchAll: true);
      expect(_ids(c), isEmpty);
      c.setWhereFilter(names: {'Seattle'}, matchAll: true);
      expect(_ids(c), {'a', 'b', 'd', 'e'});
    });

    test(
      'availableWhereNames is A-Z and narrows by the other filters',
      () async {
        final c = await _buildController();
        expect(c.availableWhereNames.toList(), ['Portland', 'Seattle']);
        c.setWhatFilter(names: {'hike'});
        expect(c.availableWhereNames, {'Portland'});
        // The Where filter itself does not narrow its own checklist.
        c.setWhatFilter(names: {});
        c.setWhereFilter(names: {'Portland'});
        expect(c.availableWhereNames, {'Portland', 'Seattle'});
      },
    );
  });

  group('What filter', () {
    test('Match Any and Match All', () async {
      final c = await _buildController();
      c.setWhatFilter(names: {'hike'});
      expect(_ids(c), {'c'});
      c.setWhatFilter(names: {'hike', 'swim'});
      expect(_ids(c), {'a', 'b', 'c', 'd', 'e'});
      c.setWhatFilter(names: {'hike', 'swim'}, matchAll: true);
      expect(_ids(c), isEmpty);
    });

    test('availableWhatNames narrows by the Who filter', () async {
      final c = await _buildController();
      expect(c.availableWhatNames.toList(), ['hike', 'swim']);
      c.setWhoFilter(names: {'Ada'}, matchAll: true);
      expect(c.availableWhatNames.toList(), ['hike', 'swim']);
      c.setWhoFilter(names: {'Sam'});
      c.setWhereFilter(names: {'Portland'});
      expect(c.availableWhatNames, {'hike'});
    });
  });

  group('Captured date range', () {
    test('from only keeps that day and later', () async {
      final c = await _buildController();
      c.setCapturedRange(from: '2026-07-10');
      expect(_ids(c), {'b', 'c'});
    });

    test('to only keeps that day and earlier', () async {
      final c = await _buildController();
      c.setCapturedRange(to: '2026-07-02');
      expect(_ids(c), {'a', 'd'});
    });

    test('both ends are inclusive', () async {
      final c = await _buildController();
      c.setCapturedRange(from: '2026-07-02', to: '2026-07-10');
      expect(_ids(c), {'c', 'd'});
    });

    test(
      'an item with no captured date is left out while a range is set',
      () async {
        final c = await _buildController();
        c.setCapturedRange(from: '2020-01-01');
        expect(_ids(c), {'a', 'b', 'c', 'd'});
        c.setCapturedRange();
        expect(_ids(c), {'a', 'b', 'c', 'd', 'e'});
      },
    );

    test('a bad date string is ignored', () async {
      final c = await _buildController();
      c.setCapturedRange(from: 'not-a-date');
      expect(_ids(c), {'a', 'b', 'c', 'd', 'e'});
    });
  });

  group('combined filters', () {
    test('two people, a place, a date range and an activity (AND)', () async {
      final c = await _buildController();
      c.setWhoFilter(names: {'Sam', 'Ada'}, matchAll: true);
      expect(_ids(c), {'a', 'c', 'e'});
      c.setWhereFilter(names: {'Seattle'});
      expect(_ids(c), {'a', 'e'});
      c.setCapturedRange(from: '2026-06-25', to: '2026-07-31');
      expect(_ids(c), {'a'});
      c.setWhatFilter(names: {'swim'});
      expect(_ids(c), {'a'});
      c.setWhatFilter(names: {'hike'});
      expect(_ids(c), isEmpty);
    });

    test('the Who checklist narrows by place, activity and date', () async {
      final c = await _buildController();
      expect(c.availableWhoNames, {'Ada', 'Sam'});
      c.setWhereFilter(names: {'Seattle'});
      c.setCapturedRange(from: '2026-08-01');
      expect(c.availableWhoNames, {'Sam'});
    });

    test(
      'hasActiveFilters and activeFilterCount count each dimension',
      () async {
        final c = await _buildController();
        expect(c.hasActiveFilters, isFalse);
        expect(c.activeFilterCount, 0);
        c.setFilterQuery('swim');
        c.setWhoFilter(names: {'Sam'});
        c.setWhereFilter(names: {'Seattle'});
        c.setWhatFilter(names: {'swim'});
        c.setCapturedRange(from: '2026-07-01');
        expect(c.hasActiveFilters, isTrue);
        expect(c.activeFilterCount, 5);
      },
    );

    test(
      'clearFilters restores every row and leaves hidden items alone',
      () async {
        final c = await _buildController();
        c.setItemHiddenInView('a', hidden: true);
        c.setFilterQuery('swim');
        c.setWhoFilter(names: {'Sam'});
        c.setWhereFilter(names: {'Seattle'});
        c.setWhatFilter(names: {'swim'});
        c.setCapturedRange(from: '2026-07-01');
        await c.clearFilters();
        expect(c.filterQuery, '');
        expect(c.whoFilterNames, isEmpty);
        expect(c.whereFilterNames, isEmpty);
        expect(c.whatFilterNames, isEmpty);
        expect(c.capturedFrom, isNull);
        expect(c.capturedTo, isNull);
        expect(c.hasActiveFilters, isFalse);
        expect(_ids(c), {'a', 'b', 'c', 'd', 'e'});
        expect(c.isItemHiddenInView('a'), isTrue);
      },
    );

    test('changing a filter returns to the first page', () async {
      final c = await _buildController();
      c.pageSize = 2;
      c.setPage(1);
      expect(c.pageIndex, 1);
      c.setWhereFilter(names: {'Seattle'});
      expect(c.pageIndex, 0);
      c.setPage(1);
      c.setWhatFilter(names: {'swim'});
      expect(c.pageIndex, 0);
      c.setPage(1);
      c.setCapturedRange(from: '2026-07-01');
      expect(c.pageIndex, 0);
    });

    test('filtered rows can be hidden like any visible row', () async {
      final c = await _buildController();
      c.setWhereFilter(names: {'Seattle'});
      expect(_ids(c), {'a', 'b', 'd', 'e'});
      c.setItemHiddenInView('b', hidden: true);
      c.setHiddenItemsFilter(HiddenItemsFilter.visible);
      expect(_ids(c), {'a', 'd', 'e'});
    });
  });

  group('LibraryViewFilters', () {
    test('capture and apply round trip the new filters', () async {
      final c = await _buildController();
      c.setWhereFilter(names: {'Seattle', 'Portland'}, matchAll: true);
      c.setWhatFilter(names: {'swim'});
      c.setCapturedRange(from: '2026-07-01', to: '2026-07-31');
      final snap = c.captureViewFilters();
      expect(snap.whereNames, ['Portland', 'Seattle']);
      expect(snap.whereMatchAll, isTrue);
      expect(snap.whatNames, ['swim']);
      expect(snap.whatMatchAll, isFalse);
      expect(snap.capturedFrom, '2026-07-01');
      expect(snap.capturedTo, '2026-07-31');

      final other = await _buildController();
      await other.applyLibraryViewFilters(snap);
      expect(other.whereFilterNames, {'Seattle', 'Portland'});
      expect(other.whereFilterMatchAll, isTrue);
      expect(other.whatFilterNames, {'swim'});
      expect(other.capturedFrom, '2026-07-01');
      expect(other.capturedTo, '2026-07-31');

      await other.applyLibraryViewFilters(LibraryViewFilters.all);
      expect(other.whereFilterNames, isEmpty);
      expect(other.whatFilterNames, isEmpty);
      expect(other.capturedFrom, isNull);
      expect(other.capturedTo, isNull);
    });

    test('JSON round trip keeps the new fields', () {
      const f = LibraryViewFilters(
        whereNames: ['Portland', 'Seattle'],
        whereMatchAll: true,
        whatNames: ['swim'],
        whatMatchAll: true,
        capturedFrom: '2026-07-01',
        capturedTo: '2026-07-31',
      );
      final back = LibraryViewFilters.fromJson(f.toJson());
      expect(back, f);
      expect(back.whereNames, ['Portland', 'Seattle']);
      expect(back.capturedFrom, '2026-07-01');
    });

    test('a view saved before these fields existed still loads', () {
      final back = LibraryViewFilters.fromJson({
        'filterQuery': 'x',
        'whoNames': ['Sam'],
        'whoMatchAll': false,
        'hiddenItemsFilter': 'both',
        'sortKeys': <Object>[],
        'hiddenFolders': <Object>[],
        'hiddenItemIds': <Object>[],
      });
      expect(back.whereNames, isEmpty);
      expect(back.whatNames, isEmpty);
      expect(back.capturedFrom, isNull);
      expect(back.capturedTo, isNull);
      expect(back.filterQuery, 'x');
    });

    test('the default (All) has no new filters and unequal filters differ', () {
      expect(LibraryViewFilters.all.whereNames, isEmpty);
      expect(
        const LibraryViewFilters(whereNames: ['A']) ==
            const LibraryViewFilters(whereNames: ['B']),
        isFalse,
      );
      expect(
        const LibraryViewFilters(capturedFrom: '2026-01-01') ==
            LibraryViewFilters.all,
        isFalse,
      );
    });
  });

  group('undo', () {
    test('a Where filter undoes and redoes with the view', () async {
      final store = MemoryCollectionsStore();
      final cols = CollectionsController(store: store);
      await cols.load();
      expect(await cols.create(name: 'Trip', seedFolders: ['/a']), isTrue);

      final c = await _buildController();
      c.onViewFiltersChanged = () => commitActiveView(table: c, cols: cols);
      final undo = FoldersUndo(UndoController());
      addTearDown(undo.stack.dispose);

      await undo.record(
        table: c,
        cols: cols,
        label: 'Filter where',
        mutate: () async {
          c.setWhereFilter(names: {'Portland'});
        },
      );
      expect(_ids(c), {'c'});
      expect(cols.views, hasLength(1));

      await undo.stack.undo();
      expect(c.whereFilterNames, isEmpty);
      expect(_ids(c), {'a', 'b', 'c', 'd', 'e'});
      expect(cols.views, isEmpty);

      await undo.stack.redo();
      expect(c.whereFilterNames, {'Portland'});
      expect(_ids(c), {'c'});
    });

    test('a date range undoes', () async {
      final store = MemoryCollectionsStore();
      final cols = CollectionsController(store: store);
      await cols.load();
      expect(await cols.create(name: 'Trip', seedFolders: ['/a']), isTrue);

      final c = await _buildController();
      c.onViewFiltersChanged = () => commitActiveView(table: c, cols: cols);
      final undo = FoldersUndo(UndoController());
      addTearDown(undo.stack.dispose);

      await undo.record(
        table: c,
        cols: cols,
        label: 'Filter date',
        mutate: () async {
          c.setCapturedRange(from: '2026-08-01');
        },
      );
      expect(_ids(c), {'b'});

      await undo.stack.undo();
      expect(c.capturedFrom, isNull);
      expect(_ids(c), {'a', 'b', 'c', 'd', 'e'});
    });
  });
}
