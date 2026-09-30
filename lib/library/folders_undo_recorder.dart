import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/persons/collection.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/undo/undo_controller.dart';
import 'package:tagkin_desktop/undo/undoable_action.dart';

/// Live Folders filters plus the open collection's saved views.
///
/// Hide-column is not part of the comparison: [filters] is
/// [LibraryTableController.persistableViewFilters].
class FoldersUndoSnapshot {
  const FoldersUndoSnapshot({
    required this.collectionId,
    required this.filters,
    required this.activeViewId,
    required this.activeViewSnapshot,
    required this.views,
    required this.recentViewIds,
    required this.currentViewId,
    required this.expandedDirs,
  });

  final String collectionId;
  final LibraryViewFilters filters;
  final String? activeViewId;
  final LibraryViewFilters? activeViewSnapshot;
  final List<SavedView> views;
  final List<String> recentViewIds;
  final String? currentViewId;

  /// Open path-group folders, sorted. Not part of a saved View.
  final List<String> expandedDirs;

  bool sameAs(FoldersUndoSnapshot other) {
    return collectionId == other.collectionId &&
        filters == other.filters &&
        activeViewId == other.activeViewId &&
        activeViewSnapshot == other.activeViewSnapshot &&
        _listEq(views, other.views) &&
        _listEq(recentViewIds, other.recentViewIds) &&
        currentViewId == other.currentViewId &&
        _listEq(expandedDirs, other.expandedDirs);
  }
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Records Folders view edits (hide, filter, sort, saved views) as snapshots.
class FoldersUndo {
  FoldersUndo(this.stack);

  final UndoController stack;
  FoldersUndoSnapshot? _filterBaseline;

  static FoldersUndoSnapshot capture(
    LibraryTableController table,
    CollectionsController cols,
  ) {
    final cur = cols.sessionReady ? cols.current : null;
    return FoldersUndoSnapshot(
      collectionId: cur?.id ?? '',
      filters: table.persistableViewFilters(),
      activeViewId: table.activeViewId,
      activeViewSnapshot: table.activeViewSnapshot,
      views: List<SavedView>.of(cur?.views ?? const []),
      recentViewIds: List<String>.of(cur?.recentViewIds ?? const []),
      currentViewId: cur?.currentViewId,
      expandedDirs: (table.expandedSourceDirs.toList()..sort()),
    );
  }

  static Future<void> restore(
    FoldersUndoSnapshot snap,
    LibraryTableController table,
    CollectionsController cols,
  ) async {
    if (snap.activeViewId != null &&
        !snap.views.any((v) => v.id == snap.activeViewId)) {
      throw StateError('View is gone');
    }
    await cols.restoreViewsState(
      collectionId: snap.collectionId,
      views: snap.views,
      recentViewIds: snap.recentViewIds,
      currentViewId: snap.currentViewId,
    );
    final hide = table.hiddenItemsFilter;
    await table.runViewCommitPaused(() async {
      await table.applyLibraryViewFilters(
        snap.filters.copyWith(hiddenItemsFilter: hide.name),
      );
      table.setActiveView(snap.activeViewId, snap.activeViewSnapshot);
      table.replaceExpandedSourceDirs(snap.expandedDirs);
    });
  }

  void clear() {
    _filterBaseline = null;
    stack.clear();
  }

  /// Remember filters when the Folders search field gains focus.
  void beginFilterEdit(
    LibraryTableController table,
    CollectionsController cols,
  ) {
    _filterBaseline ??= capture(table, cols);
  }

  /// One undo entry for the search field, from focus until blur or the next
  /// recorded gesture.
  Future<void> endFilterEdit({
    required LibraryTableController table,
    required CollectionsController cols,
    bool resume = false,
  }) async {
    final before = _filterBaseline;
    if (before == null) return;
    _filterBaseline = null;
    await table.awaitPendingViewCommit();
    await _pushIfChanged(
      stack: stack,
      table: table,
      cols: cols,
      label: 'Filter',
      before: before,
    );
    if (resume) _filterBaseline = capture(table, cols);
  }

  /// Snapshot, run [mutate], wait for an All→ViewNN mint, then push.
  ///
  /// [stack] defaults to the Folders host. Item detail passes its own stack
  /// so Hide item undoes on that screen.
  Future<void> record({
    required LibraryTableController table,
    required CollectionsController cols,
    required String label,
    required Future<void> Function() mutate,
    UndoController? stack,
  }) async {
    final target = stack ?? this.stack;
    if (_filterBaseline != null && identical(target, this.stack)) {
      await endFilterEdit(table: table, cols: cols, resume: true);
    }
    final before = capture(table, cols);
    await mutate();
    await table.awaitPendingViewCommit();
    await _pushIfChanged(
      stack: target,
      table: table,
      cols: cols,
      label: label,
      before: before,
    );
  }

  Future<void> _pushIfChanged({
    required UndoController stack,
    required LibraryTableController table,
    required CollectionsController cols,
    required String label,
    required FoldersUndoSnapshot before,
  }) async {
    final after = capture(table, cols);
    if (before.sameAs(after)) return;
    stack.push(
      CallbackUndoableAction(
        label: label,
        onUndo: () => restore(before, table, cols),
        onRedo: () => restore(after, table, cols),
      ),
    );
  }
}

final foldersUndoProvider = Provider<FoldersUndo>((ref) {
  final stack = UndoController();
  ref.onDispose(stack.dispose);
  return FoldersUndo(stack);
});
