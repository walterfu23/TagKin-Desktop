import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/library/folders_undo_recorder.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/library/views_menu.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/persons/collections_store.dart';
import 'package:tagkin_desktop/undo/undo_controller.dart';

import '../fake_comments_repository.dart';
import '../fake_items_repository.dart';

void main() {
  test(
    'Hide item on All undoes the minted view and redo restores it',
    () async {
      final store = MemoryCollectionsStore();
      final cols = CollectionsController(store: store);
      await cols.load();
      expect(await cols.create(name: 'Trip', seedFolders: ['/a']), isTrue);

      final items = FakeItemsRepository(items: [fixtureItem(id: 'a')]);
      final table = LibraryTableController(
        itemsRepository: items,
        commentsRepository: FakeCommentsRepository(),
      );
      table.onViewFiltersChanged = () {
        return commitActiveView(table: table, cols: cols);
      };
      await table.load();

      final undo = FoldersUndo(UndoController());
      addTearDown(undo.stack.dispose);
      addTearDown(table.dispose);

      await undo.record(
        table: table,
        cols: cols,
        label: 'Hide item',
        mutate: () async {
          table.setItemHiddenInView('a', hidden: true);
        },
      );

      expect(undo.stack.canUndo, isTrue);
      expect(cols.views, hasLength(1));
      expect(table.activeViewId, cols.views.single.id);
      expect(table.isItemHiddenInView('a'), isTrue);

      await undo.stack.undo();
      expect(table.isItemHiddenInView('a'), isFalse);
      expect(table.activeViewId, isNull);
      expect(cols.views, isEmpty);
      expect(cols.current.currentViewId, isNull);

      await undo.stack.redo();
      expect(table.isItemHiddenInView('a'), isTrue);
      expect(cols.views, hasLength(1));
      expect(table.activeViewId, cols.views.single.id);
    },
  );

  test(
    'Hide item on a named view undoes the hide and keeps the view',
    () async {
      final store = MemoryCollectionsStore();
      final cols = CollectionsController(store: store);
      await cols.load();
      expect(await cols.create(name: 'Trip', seedFolders: ['/a']), isTrue);

      final items = FakeItemsRepository(items: [fixtureItem(id: 'a')]);
      final table = LibraryTableController(
        itemsRepository: items,
        commentsRepository: FakeCommentsRepository(),
      );
      table.onViewFiltersChanged = () {
        return commitActiveView(table: table, cols: cols);
      };
      await table.load();
      final saved = await cols.saveView(
        name: 'Ada',
        filters: table.persistableViewFilters(),
      );
      table.setActiveView(saved!.id, saved.filters);

      final undo = FoldersUndo(UndoController());
      addTearDown(undo.stack.dispose);
      addTearDown(table.dispose);

      await undo.record(
        table: table,
        cols: cols,
        label: 'Hide item',
        mutate: () async {
          table.setItemHiddenInView('a', hidden: true);
        },
      );
      expect(table.isActiveViewModified, isTrue);
      expect(cols.views, hasLength(1));

      await undo.stack.undo();
      expect(table.isItemHiddenInView('a'), isFalse);
      expect(table.activeViewId, saved.id);
      expect(table.isActiveViewModified, isFalse);
      expect(cols.views.single.name, 'Ada');
    },
  );

  test('collapse folder undoes open and redo collapses it', () async {
    final store = MemoryCollectionsStore();
    final cols = CollectionsController(store: store);
    await cols.load();
    expect(await cols.create(name: 'Trip', seedFolders: ['/a']), isTrue);

    final table = LibraryTableController(
      itemsRepository: FakeItemsRepository(),
      commentsRepository: FakeCommentsRepository(),
    );
    table.expandedSourceDirs.add('/albums');
    final undo = FoldersUndo(UndoController());
    addTearDown(undo.stack.dispose);
    addTearDown(table.dispose);

    await undo.record(
      table: table,
      cols: cols,
      label: 'Collapse folder',
      mutate: () async {
        table.toggleCollapseSourceDir('/albums');
      },
    );
    expect(table.expandedSourceDirs, isNot(contains('/albums')));
    expect(cols.views, isEmpty);
    expect(undo.stack.canUndo, isTrue);

    await undo.stack.undo();
    expect(table.expandedSourceDirs, contains('/albums'));

    await undo.stack.redo();
    expect(table.expandedSourceDirs, isNot(contains('/albums')));
  });

  test('collapse from All mints a view and undo returns to All', () async {
    const root = '/users/w/albums';
    final harness = await _siblingAlbums(root);
    final table = harness.table;
    final cols = harness.cols;
    final undo = harness.undo;

    expect(table.expandedSourceDirs, contains(root));
    expect(cols.views, isEmpty);
    expect(table.persistableViewFilters().expandedDirs, isNull);

    await undo.record(
      table: table,
      cols: cols,
      label: 'Collapse folder',
      mutate: () async {
        table.toggleCollapseSourceDir(root);
      },
    );

    expect(table.expandedSourceDirs, isNot(contains(root)));
    expect(cols.views, hasLength(1));
    expect(table.activeViewId, cols.views.single.id);
    expect(table.isActiveViewModified, isFalse);
    expect(cols.views.single.filters.expandedDirs, isEmpty);
    expect(cols.dirty, isFalse);
    cols.updateLibraryLook(table.captureCollectionLibraryUi());
    expect(cols.dirty, isFalse);

    await undo.stack.undo();
    expect(cols.views, isEmpty);
    expect(table.activeViewId, isNull);
    expect(table.expandedSourceDirs, contains(root));
    expect(table.isActiveViewModified, isFalse);

    await undo.stack.redo();
    expect(cols.views, hasLength(1));
    expect(table.activeViewId, cols.views.single.id);
    expect(table.expandedSourceDirs, isNot(contains(root)));
  });

  test('collapse on a named view stars it and undo clears the star', () async {
    const root = '/users/w/albums';
    final harness = await _siblingAlbums(root);
    final table = harness.table;
    final cols = harness.cols;
    final undo = harness.undo;
    final saved = await cols.saveView(
      name: 'Ada',
      filters: table.persistableViewFilters(),
    );
    table.setActiveView(saved!.id, saved.filters);
    expect(table.isActiveViewModified, isFalse);

    await undo.record(
      table: table,
      cols: cols,
      label: 'Collapse folder',
      mutate: () async {
        table.toggleCollapseSourceDir(root);
      },
    );

    expect(cols.views, hasLength(1));
    expect(cols.views.single.name, 'Ada');
    expect(table.activeViewId, saved.id);
    expect(table.isActiveViewModified, isTrue);
    expect(table.expandedSourceDirs, isNot(contains(root)));

    await undo.stack.undo();
    expect(table.activeViewId, saved.id);
    expect(table.isActiveViewModified, isFalse);
    expect(table.expandedSourceDirs, contains(root));
    expect(cols.views.single.name, 'Ada');
  });

  test('auto-expand alone does not mint a view', () async {
    const root = '/users/w/albums';
    final harness = await _siblingAlbums(root);
    expect(harness.table.expandedSourceDirs, contains(root));
    expect(harness.cols.views, isEmpty);
    expect(harness.table.activeViewId, isNull);
    expect(harness.table.persistableViewFilters().expandedDirs, isNull);
    expect(harness.cols.dirty, isFalse);
  });
}

class _AlbumHarness {
  _AlbumHarness(this.table, this.cols, this.undo);

  final LibraryTableController table;
  final CollectionsController cols;
  final FoldersUndo undo;
}

Future<_AlbumHarness> _siblingAlbums(String root) async {
  final store = MemoryCollectionsStore();
  final cols = CollectionsController(store: store);
  await cols.load();
  expect(await cols.create(name: 'Trip', seedFolders: ['/a']), isTrue);

  final table = LibraryTableController(
    itemsRepository: FakeItemsRepository(
      items: [
        fixtureItem(id: 'd1', sourceRef: 'file://$root/Day1/a.jpg'),
        fixtureItem(id: 'd2', sourceRef: 'file://$root/Day2/b.jpg'),
      ],
    ),
    commentsRepository: FakeCommentsRepository(),
  );
  table.onViewFiltersChanged = () {
    return commitActiveView(table: table, cols: cols);
  };
  await table.load();
  await table.applyCollectionLibraryUi(cols.current.ui.library);
  cols.adoptLibraryLook(table.captureCollectionLibraryUi());

  final undo = FoldersUndo(UndoController());
  addTearDown(undo.stack.dispose);
  addTearDown(table.dispose);
  return _AlbumHarness(table, cols, undo);
}
