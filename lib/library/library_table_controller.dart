import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/api/comments_repository.dart';
import 'package:tagkin_desktop/api/items_repository.dart';
import 'package:tagkin_desktop/app_shell.dart'
    show commentsRepositoryProvider, itemsRepositoryProvider;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/local_thumb_cache.dart';
import 'package:tagkin_desktop/persons/collection.dart';
import 'package:tagkin_desktop/persons/face_crop_folder_scope.dart';
import 'package:tagkin_desktop/review/knowledge_grouping.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';
import 'package:tagkin_desktop/where/where_label_resolver.dart';
import 'package:tagkin_desktop/where/where_place_label.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';

/// Columns that support header sorting on the library table.
enum LibrarySortColumn { who, what, where, source, comment, type, status }

/// One sort key in a multi-column sort stack.
class LibrarySortKey {
  const LibrarySortKey(this.column, {this.ascending = true});

  final LibrarySortColumn column;
  final bool ascending;

  LibrarySortKey toggled() => LibrarySortKey(column, ascending: !ascending);
}

/// One row in the library list after path grouping (header or item).
sealed class LibraryVisibleEntry {
  const LibraryVisibleEntry();
}

/// Collapse/expand header for a shared parent directory (2+ items).
class LibraryPathGroupHeader extends LibraryVisibleEntry {
  const LibraryPathGroupHeader({
    required this.dir,
    required this.label,
    required this.count,
    required this.collapsed,
    this.depth = 0,
  });

  /// Absolute directory path (toggle / identity key).
  final String dir;

  /// Display label (absolute at top level, relative when nested).
  final String label;
  final int count;
  final bool collapsed;
  final int depth;
}

/// An item row under the path tree.
class LibraryItemEntry extends LibraryVisibleEntry {
  const LibraryItemEntry({
    required this.row,
    required this.sourceDisplay,
    this.depth = 0,
  });

  final LibraryTableRow row;

  /// Source column text (full path, relative path, or basename).
  final String sourceDisplay;
  final int depth;

  /// True when [sourceDisplay] is not the full [LibraryTableRow.sourceLabel].
  bool get showBasenameOnly => sourceDisplay != row.sourceLabel;
}

/// View-model for one library table row.
class LibraryTableRow {
  const LibraryTableRow({
    required this.item,
    this.who = const [],
    this.what = const [],
    this.whereEntries = const [],
    this.whereRaw = const [],
    this.comments = const [],
    this.knowledgeLoaded = false,
    this.commentsLoaded = false,
    this.thumb,
  });

  final Item item;
  final List<String> who;
  final List<String> what;

  /// Structured where labels (GPS reverse-geocoded when applicable).
  final List<WhereDisplay> whereEntries;

  /// Joined where labels for filter / sort.
  List<String> get where => [for (final e in whereEntries) e.label];

  /// Raw where tag values (for re-resolving after prefs change).
  final List<String> whereRaw;
  final List<String> comments;
  final bool knowledgeLoaded;
  final bool commentsLoaded;
  final LocalThumbResult? thumb;

  String get sourceLabel {
    final ref = item.sourceRef;
    if (ref == null || ref.isEmpty) return '';
    final path = localPathFromSourceRef(ref);
    return path ?? ref;
  }

  /// Parent directory of [sourceLabel], or '' when missing / not a path.
  String get sourceDir {
    final label = sourceLabel;
    if (label.isEmpty) return '';
    final dir = p.dirname(label);
    // dirname of a bare filename is '.' — treat as no shared folder key.
    if (dir.isEmpty || dir == '.') return '';
    return dir;
  }

  String get sourceFileName {
    final label = sourceLabel;
    if (label.isEmpty) return '';
    return p.basename(label);
  }

  LibraryTableRow copyWith({
    Item? item,
    List<String>? who,
    List<String>? what,
    List<WhereDisplay>? whereEntries,
    List<String>? whereRaw,
    List<String>? comments,
    bool? knowledgeLoaded,
    bool? commentsLoaded,
    LocalThumbResult? thumb,
  }) {
    return LibraryTableRow(
      item: item ?? this.item,
      who: who ?? this.who,
      what: what ?? this.what,
      whereEntries: whereEntries ?? this.whereEntries,
      whereRaw: whereRaw ?? this.whereRaw,
      comments: comments ?? this.comments,
      knowledgeLoaded: knowledgeLoaded ?? this.knowledgeLoaded,
      commentsLoaded: commentsLoaded ?? this.commentsLoaded,
      thumb: thumb ?? this.thumb,
    );
  }
}

/// Loads items + knowledge/comment summaries and owns client-side table state.
class LibraryTableController extends ChangeNotifier {
  LibraryTableController({
    required this.itemsRepository,
    required this.commentsRepository,
    LocalThumbCache? thumbCache,
    WhereLabelResolver? whereLabelResolver,
    this._pageSize = 50,
    this.knowledgeConcurrency = 6,
  })  : _thumbCache = thumbCache ?? LocalThumbCache(),
        _whereLabels = whereLabelResolver ?? WhereLabelResolver();

  final ItemsRepository itemsRepository;
  final CommentsRepository commentsRepository;
  final LocalThumbCache _thumbCache;
  final WhereLabelResolver _whereLabels;
  int _pageSize;
  final int knowledgeConcurrency;

  int get pageSize => _pageSize;

  set pageSize(int value) {
    final next = value.clamp(2, 200);
    if (next == _pageSize) return;
    _pageSize = next;
    if (pageIndex >= pageCount && pageCount > 0) {
      pageIndex = pageCount - 1;
    }
    notifyListeners();
  }

  List<LibraryTableRow> _rows = const [];
  Object? error;
  bool loading = false;
  bool knowledgeWarming = false;

  /// True once [load] has settled (success or error) at least once. Callers
  /// that need real rows before computing a baseline (e.g. Folders
  /// auto-expand) should await [ensureLoaded] first instead of reading
  /// [allRows] immediately after sign-in / mint.
  bool hasLoadedOnce = false;
  Future<void>? _loadFuture;

  /// Awaits the first [load] (kicking one off if none has ever run/is in
  /// flight); no-ops on later calls. Dedupes with a concurrent caller (e.g.
  /// [ItemsListPage.initState]) that also triggers the initial load.
  Future<void> ensureLoaded() {
    if (hasLoadedOnce) return Future.value();
    return _loadFuture ??= load();
  }

  String filterQuery = '';
  ProcessingStatus? statusFilter;
  List<LibrarySortKey> sortKeys = const [];
  int pageIndex = 0;

  /// When non-null, only rows whose leaf folder is in this set are shown.
  Set<String>? collectionLeafFolders;

  /// Item ids with who/where/comment expanded in the table.
  final Set<String> expandedWho = {};
  final Set<String> expandedWhere = {};
  final Set<String> expandedComments = {};

  /// Parent dirs the user has expanded (multi-item groups default collapsed).
  /// Sibling-folder parents (2+ child directories) are auto-seeded into this set.
  final Set<String> expandedSourceDirs = {};

  /// Multi-child folder parents already considered for auto-expand this session.
  /// Prevents re-expanding after the user collapses one.
  final Set<String> _seededBranchParents = {};

  int? _loadGeneration;

  /// Live ingest/retry patches. [load] must not revert these to a stale
  /// `GET /items` snapshot (pending overlapping an in-flight analyze).
  final Map<String, Item> _adoptedById = {};

  List<LibraryTableRow> get allRows => _rows;

  List<LibraryTableRow> get filteredSorted {
    var list = List<LibraryTableRow>.from(_rows);
    final collectionFolders = collectionLeafFolders;
    if (collectionFolders != null) {
      list = list.where((r) {
        final folder = leafFolderFromItem(r.item);
        return folder != null && collectionFolders.contains(folder);
      }).toList();
    }
    final q = filterQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((r) {
        final hay = [
          r.item.type.wire,
          r.item.processingStatus.wire,
          r.sourceLabel,
          ...r.who,
          ...r.what,
          ...r.where,
          ...r.comments,
          r.item.capturedAt ?? '',
        ].join(' ').toLowerCase();
        return hay.contains(q);
      }).toList();
    }
    if (sortKeys.isNotEmpty) {
      list.sort((a, b) {
        for (final key in sortKeys) {
          final cmp = _compare(a, b, key.column);
          if (cmp != 0) return key.ascending ? cmp : -cmp;
        }
        return a.item.id.compareTo(b.item.id);
      });
    }
    return list;
  }

  /// Visible list rows after nested path grouping (headers + shown item rows).
  List<LibraryVisibleEntry> get visibleEntries {
    return _buildPathGroupedEntries(
      items: filteredSorted,
      expandedSourceDirs: expandedSourceDirs,
    );
  }

  /// Visible entry count (used for pagination).
  int get totalFiltered => visibleEntries.length;

  int get pageCount {
    final n = totalFiltered;
    if (n == 0) return 1;
    return ((n - 1) ~/ pageSize) + 1;
  }

  List<LibraryVisibleEntry> get visiblePageEntries {
    final all = visibleEntries;
    if (all.isEmpty) return const [];
    final start = pageIndex * pageSize;
    if (start >= all.length) return const [];
    final end = (start + pageSize).clamp(0, all.length);
    return all.sublist(start, end);
  }

  /// Replace a loaded row's [Item] (folder Retry, ingest upload/analyze).
  /// Preserves thumbs / who / what / where already on the row.
  /// Inserts a row when the id is not loaded yet (first fetch still in flight).
  void adoptItem(Item item) {
    _adoptedById[item.id] = item;
    final idx = _rows.indexWhere((r) => r.item.id == item.id);
    if (idx < 0) {
      _rows = [..._rows, LibraryTableRow(item: item)];
      notifyListeners();
      return;
    }
    _replaceRow(item.id, (r) => r.copyWith(item: item));
  }

  static int _processingRank(ProcessingStatus status) {
    switch (status) {
      case ProcessingStatus.pending:
        return 0;
      case ProcessingStatus.awaitingModelAccess:
        return 1;
      case ProcessingStatus.processing:
        return 2;
      case ProcessingStatus.tagged:
      case ProcessingStatus.failed:
      case ProcessingStatus.cancelled:
        return 3;
    }
  }

  Item _resolveLiveItem(Item fetched) {
    final adopted = _adoptedById[fetched.id];
    if (adopted == null) return fetched;
    if (_processingRank(adopted.processingStatus) >=
        _processingRank(fetched.processingStatus)) {
      return adopted;
    }
    return fetched;
  }

  /// Item rows on the current visible page (excludes path group headers).
  List<LibraryTableRow> get pageRows {
    return [
      for (final e in visiblePageEntries)
        if (e is LibraryItemEntry) e.row,
    ];
  }

  Future<void> load() async {
    final gen = DateTime.now().microsecondsSinceEpoch;
    _loadGeneration = gen;
    final showSpinner = !hasLoadedOnce;
    if (showSpinner) {
      loading = true;
      error = null;
      notifyListeners();
    } else {
      error = null;
    }

    try {
      try {
        final items = await itemsRepository.listItems(status: statusFilter);
        if (_loadGeneration != gen) return;
        _thumbCache.clear();
        expandedWho.clear();
        expandedWhere.clear();
        expandedComments.clear();
        final previousById = {for (final r in _rows) r.item.id: r};
        // Keep folder expand/collapse across reload (e.g. after delete).
        // Prefer live-adopted status so an overlapping GET cannot revert tagged.
        _rows = [
          for (final item in items)
            previousById[item.id]?.copyWith(item: _resolveLiveItem(item)) ??
                LibraryTableRow(item: _resolveLiveItem(item)),
        ];
        _pruneExpandedSourceDirs();
        _autoExpandSiblingFolderParents(filteredSorted);
        pageIndex = 0;
        loading = false;
        hasLoadedOnce = true;
        notifyListeners();

        unawaited(_warmThumbs(gen));
        unawaited(_warmKnowledge(gen));
        unawaited(_warmComments(gen));
      } catch (e) {
        if (_loadGeneration != gen) return;
        error = e;
        loading = false;
        hasLoadedOnce = true;
        notifyListeners();
      }
    } finally {
      _loadFuture = null;
    }
  }

  void setFilterQuery(String value) {
    filterQuery = value;
    pageIndex = 0;
    notifyListeners();
  }

  /// Snapshot of Folders look for the open collection.
  CollectionLibraryUi captureCollectionLibraryUi() {
    return CollectionLibraryUi(
      filterQuery: filterQuery,
      statusFilter: statusFilter?.wire,
      sortKeys: [
        for (final k in sortKeys)
          CollectionSortKey(k.column.name, ascending: k.ascending),
      ],
      expandedDirs: expandedSourceDirs.toList()..sort(),
    );
  }

  /// Restore Folders look from a saved collection (no network reload unless
  /// status filter requires it).
  Future<void> applyCollectionLibraryUi(CollectionLibraryUi ui) async {
    filterQuery = ui.filterQuery;
    pageIndex = 0;
    sortKeys = [
      for (final k in ui.sortKeys)
        if (_sortColumnFromName(k.column) != null)
          LibrarySortKey(
            _sortColumnFromName(k.column)!,
            ascending: k.ascending,
          ),
    ];
    expandedSourceDirs
      ..clear()
      ..addAll(ui.expandedDirs);
    // Empty saved expansion → default expand sibling-folder parents.
    // Non-empty → respect saved set; mark all current branches seeded so we
    // do not immediately re-expand a collapsed parent.
    final branches = _multiChildFolderParentPaths(filteredSorted);
    if (ui.expandedDirs.isEmpty) {
      expandedSourceDirs.addAll(branches);
    }
    _seededBranchParents
      ..clear()
      ..addAll(branches);
    ProcessingStatus? nextStatus;
    final raw = ui.statusFilter;
    if (raw != null && raw.isNotEmpty) {
      try {
        nextStatus = ProcessingStatus.fromWire(raw);
      } catch (_) {
        nextStatus = null;
      }
    }
    if (nextStatus != statusFilter) {
      statusFilter = nextStatus;
      await load();
    } else {
      notifyListeners();
    }
  }

  static LibrarySortColumn? _sortColumnFromName(String name) {
    for (final c in LibrarySortColumn.values) {
      if (c.name == name) return c;
    }
    return null;
  }

  void setCollectionLeafFolders(Set<String>? folders) {
    final prev = collectionLeafFolders;
    if (prev == null && folders == null) return;
    if (prev != null &&
        folders != null &&
        prev.length == folders.length &&
        prev.containsAll(folders)) {
      return;
    }
    collectionLeafFolders = folders;
    pageIndex = 0;
    _autoExpandSiblingFolderParents(filteredSorted);
    notifyListeners();
  }

  Future<void> setStatusFilter(ProcessingStatus? status) async {
    statusFilter = status;
    await load();
  }

  /// Click a column header (Cliptorium-style).
  ///
  /// [multiColumn] false: cycle primary asc → desc → none (single key).
  /// [multiColumn] true: append as next key, or cycle that key asc → desc → remove.
  void toggleSort(LibrarySortColumn column, {bool multiColumn = false}) {
    if (!multiColumn) {
      if (sortKeys.isNotEmpty && sortKeys.first.column == column) {
        final primary = sortKeys.first;
        if (primary.ascending) {
          sortKeys = [LibrarySortKey(column, ascending: false)];
        } else {
          sortKeys = const [];
        }
      } else {
        sortKeys = [LibrarySortKey(column)];
      }
    } else {
      final idx = sortKeys.indexWhere((k) => k.column == column);
      if (idx < 0) {
        sortKeys = [...sortKeys, LibrarySortKey(column)];
      } else {
        final next = List<LibrarySortKey>.from(sortKeys);
        final key = next[idx];
        if (key.ascending) {
          next[idx] = LibrarySortKey(column, ascending: false);
          sortKeys = next;
        } else {
          next.removeAt(idx);
          sortKeys = next;
        }
      }
    }
    pageIndex = 0;
    notifyListeners();
  }

  /// When multi-column sort is disabled, keep only the primary sort column.
  void enforceSingleColumn() {
    if (sortKeys.length <= 1) return;
    sortKeys = [sortKeys.first];
    pageIndex = 0;
    notifyListeners();
  }

  /// Re-resolve display where labels from [LibraryTableRow.whereRaw] (prefs change).
  Future<void> refreshWhereLabels() async {
    final snapshot = List<LibraryTableRow>.from(_rows);
    for (final row in snapshot) {
      if (!row.knowledgeLoaded || row.whereRaw.isEmpty) continue;
      final entries = await _whereLabels.resolveAllDisplays(row.whereRaw);
      _replaceRow(row.item.id, (r) => r.copyWith(whereEntries: entries));
    }
  }

  void setPage(int index) {
    pageIndex = index.clamp(0, pageCount - 1);
    notifyListeners();
  }

  void toggleExpandWho(String itemId) {
    if (!expandedWho.add(itemId)) expandedWho.remove(itemId);
    notifyListeners();
  }

  void toggleExpandWhere(String itemId) {
    if (!expandedWhere.add(itemId)) expandedWhere.remove(itemId);
    notifyListeners();
  }

  void toggleExpandComments(String itemId) {
    if (!expandedComments.add(itemId)) expandedComments.remove(itemId);
    notifyListeners();
  }

  /// Expand or collapse a multi-item source directory group.
  void toggleCollapseSourceDir(String dir) {
    if (!expandedSourceDirs.add(dir)) expandedSourceDirs.remove(dir);
    notifyListeners();
  }

  /// Drop expanded folder keys that no longer appear in the loaded rows
  /// (or as ancestors of those paths).
  void _pruneExpandedSourceDirs() {
    if (expandedSourceDirs.isEmpty && _seededBranchParents.isEmpty) return;
    final valid = <String>{};
    final ctx = p.context;
    for (final row in _rows) {
      var dir = row.sourceDir;
      while (dir.isNotEmpty && dir != '.') {
        valid.add(dir);
        final parent = ctx.dirname(dir);
        if (parent == dir) break;
        dir = parent;
      }
    }
    expandedSourceDirs.removeWhere((d) => !valid.contains(d));
    _seededBranchParents.removeWhere((d) => !valid.contains(d));
  }

  /// First time a parent has 2+ subdirectory children, expand it so sibling
  /// folders are visible. File-only groups (no subdirs) stay collapsed.
  void _autoExpandSiblingFolderParents(List<LibraryTableRow> items) {
    final branches = _multiChildFolderParentPaths(items);
    for (final dir in branches) {
      if (_seededBranchParents.contains(dir)) continue;
      _seededBranchParents.add(dir);
      expandedSourceDirs.add(dir);
    }
    _seededBranchParents.removeWhere((d) => !branches.contains(d));
  }

  /// Absolute paths of directory nodes that have two or more child folders.
  static Set<String> _multiChildFolderParentPaths(List<LibraryTableRow> items) {
    if (items.isEmpty) return {};
    final ctx = p.context;
    final root = _PathNode(segment: '', absolutePath: '');
    for (final row in items) {
      final dir = row.sourceDir;
      if (dir.isEmpty) continue;
      root.insert(row, dir, ctx);
    }
    final out = <String>{};
    void walk(_PathNode node) {
      if (node.children.length >= 2 && node.absolutePath.isNotEmpty) {
        out.add(node.absolutePath);
      }
      for (final child in node.children.values) {
        walk(child);
      }
    }
    walk(root);
    return out;
  }

  Future<void> _warmThumbs(int gen) async {
    final snapshot = List<LibraryTableRow>.from(_rows);
    for (final row in snapshot) {
      if (_loadGeneration != gen) return;
      final thumb = await _thumbCache.resolve(row.item);
      if (_loadGeneration != gen) return;
      _replaceRow(row.item.id, (r) => r.copyWith(thumb: thumb));
    }
  }

  Future<void> _warmKnowledge(int gen) async {
    knowledgeWarming = true;
    notifyListeners();
    final ids = _rows.map((r) => r.item.id).toList();
    var cursor = 0;
    Future<void> worker() async {
      while (true) {
        if (_loadGeneration != gen) return;
        final i = cursor++;
        if (i >= ids.length) return;
        final id = ids[i];
        try {
          final knowledge = await itemsRepository.getKnowledge(id);
          if (_loadGeneration != gen) return;
          final grouped = groupItemLevelTagsByDimension(knowledge.tags);
          final whereRaw = grouped['where']!.map((t) => t.value).toList();
          final whereEntries = await _whereLabels.resolveAllDisplays(whereRaw);
          if (_loadGeneration != gen) return;
          _replaceRow(
            id,
            (r) => r.copyWith(
              who: grouped['who']!.map((t) => t.value).toList(),
              what: grouped['what']!.map((t) => t.value).toList(),
              whereEntries: whereEntries,
              whereRaw: whereRaw,
              knowledgeLoaded: true,
            ),
          );
        } catch (_) {
          if (_loadGeneration != gen) return;
          _replaceRow(id, (r) => r.copyWith(knowledgeLoaded: true));
        }
      }
    }

    final workers = List.generate(
      knowledgeConcurrency.clamp(1, 16),
      (_) => worker(),
    );
    await Future.wait(workers);
    if (_loadGeneration != gen) return;
    knowledgeWarming = false;
    notifyListeners();
  }

  Future<void> _warmComments(int gen) async {
    final ids = _rows.map((r) => r.item.id).toList();
    var cursor = 0;
    Future<void> worker() async {
      while (true) {
        if (_loadGeneration != gen) return;
        final i = cursor++;
        if (i >= ids.length) return;
        final id = ids[i];
        try {
          final list = await commentsRepository.listItemComments(id);
          if (_loadGeneration != gen) return;
          final bodies = list
              .where((c) => c.keyPeriodId == null && c.deletedAt == null)
              .map((c) => c.body)
              .toList();
          _replaceRow(
            id,
            (r) => r.copyWith(comments: bodies, commentsLoaded: true),
          );
        } catch (_) {
          if (_loadGeneration != gen) return;
          _replaceRow(id, (r) => r.copyWith(commentsLoaded: true));
        }
      }
    }

    final workers = List.generate(
      knowledgeConcurrency.clamp(1, 16),
      (_) => worker(),
    );
    await Future.wait(workers);
  }

  void _replaceRow(
    String itemId,
    LibraryTableRow Function(LibraryTableRow) map,
  ) {
    final idx = _rows.indexWhere((r) => r.item.id == itemId);
    if (idx < 0) return;
    final next = List<LibraryTableRow>.from(_rows);
    next[idx] = map(next[idx]);
    _rows = next;
    notifyListeners();
  }

  static int _compare(
    LibraryTableRow a,
    LibraryTableRow b,
    LibrarySortColumn column,
  ) {
    String primary(LibraryTableRow r) {
      switch (column) {
        case LibrarySortColumn.who:
          return r.who.join(', ');
        case LibrarySortColumn.what:
          return r.what.join(', ');
        case LibrarySortColumn.where:
          return r.where.join(', ');
        case LibrarySortColumn.source:
          return r.sourceLabel;
        case LibrarySortColumn.comment:
          return r.comments.join(', ');
        case LibrarySortColumn.type:
          return r.item.type.wire;
        case LibrarySortColumn.status:
          return r.item.processingStatus.wire;
      }
    }

    return primary(a).toLowerCase().compareTo(primary(b).toLowerCase());
  }
}

final libraryTableControllerProvider =
    ChangeNotifierProvider.autoDispose<LibraryTableController>(
  (ref) {
    return LibraryTableController(
      itemsRepository: ref.watch(itemsRepositoryProvider),
      commentsRepository: ref.watch(commentsRepositoryProvider),
      whereLabelResolver: ref.watch(whereLabelResolverProvider),
      pageSize: ref.read(desktopPrefsProvider).libraryPageSize,
    );
  },
  dependencies: [
    itemsRepositoryProvider,
    commentsRepositoryProvider,
    whereLabelResolverProvider,
    desktopPrefsProvider,
  ],
);

/// Builds a compressed directory trie and flattens it to visible library rows.
List<LibraryVisibleEntry> _buildPathGroupedEntries({
  required List<LibraryTableRow> items,
  required Set<String> expandedSourceDirs,
  p.Context? pathContext,
}) {
  final ctx = pathContext ?? p.context;
  if (items.isEmpty) return const [];

  final indexOf = <String, int>{
    for (var i = 0; i < items.length; i++) items[i].item.id: i,
  };

  final root = _PathNode(segment: '', absolutePath: '');
  final noPath = <LibraryTableRow>[];
  for (final row in items) {
    final dir = row.sourceDir;
    if (dir.isEmpty) {
      noPath.add(row);
      continue;
    }
    root.insert(row, dir, ctx);
  }

  final out = <LibraryVisibleEntry>[];
  final tops = <_TopEmit>[];

  for (final child in root.children.values) {
    for (final topNode in _collectTopNodes(child)) {
      tops.add(
        _TopEmit(
          firstIndex: topNode.firstIndex(indexOf),
          emit: (list) => _emitPathNode(
            node: topNode,
            depth: 0,
            parentAbs: null,
            expandedSourceDirs: expandedSourceDirs,
            indexOf: indexOf,
            ctx: ctx,
            out: list,
          ),
        ),
      );
    }
  }
  for (final row in noPath) {
    tops.add(
      _TopEmit(
        firstIndex: indexOf[row.item.id] ?? 0,
        emit: (list) => list.add(
          LibraryItemEntry(
            row: row,
            depth: 0,
            sourceDisplay: row.sourceLabel,
          ),
        ),
      ),
    );
  }
  tops.sort((a, b) => a.firstIndex.compareTo(b.firstIndex));
  for (final top in tops) {
    top.emit(out);
  }
  return out;
}

class _TopEmit {
  _TopEmit({required this.firstIndex, required this.emit});

  final int firstIndex;
  final void Function(List<LibraryVisibleEntry>) emit;
}

/// True for `/` or a Windows drive root — never a useful library group header.
bool _isFsRoot(String path) {
  if (path == '/' || path == r'\') return true;
  return RegExp(r'^[A-Za-z]:\\?$').hasMatch(path);
}

/// Top-level forest nodes: skip bare filesystem roots so unrelated trees
/// (e.g. /fixture_a vs /fixture_b) stay separate.
List<_PathNode> _collectTopNodes(_PathNode node) {
  if (_isFsRoot(node.absolutePath) &&
      node.files.isEmpty &&
      node.children.isNotEmpty) {
    return [
      for (final child in node.children.values) ..._collectTopNodes(child),
    ];
  }
  return [node.compressed];
}

class _PathNode {
  _PathNode({required this.segment, required this.absolutePath});

  final String segment;
  final String absolutePath;
  final Map<String, _PathNode> children = {};
  final List<LibraryTableRow> files = [];

  int get itemCount {
    var n = files.length;
    for (final c in children.values) {
      n += c.itemCount;
    }
    return n;
  }

  /// Collapse unary directory chains (single child, no files).
  _PathNode get compressed {
    var n = this;
    while (n.children.length == 1 && n.files.isEmpty) {
      n = n.children.values.single;
    }
    return n;
  }

  void insert(LibraryTableRow row, String dir, p.Context ctx) {
    final parts = ctx.split(ctx.normalize(dir));
    var node = this;
    for (final part in parts) {
      if (part.isEmpty) continue;
      node = node.children.putIfAbsent(part, () {
        final abs = node.absolutePath.isEmpty
            ? part
            : ctx.join(node.absolutePath, part);
        return _PathNode(segment: part, absolutePath: abs);
      });
    }
    node.files.add(row);
  }

  int firstIndex(Map<String, int> indexOf) {
    var best = 1 << 30;
    for (final f in files) {
      final i = indexOf[f.item.id];
      if (i != null && i < best) best = i;
    }
    for (final c in children.values) {
      final i = c.firstIndex(indexOf);
      if (i < best) best = i;
    }
    return best;
  }

  List<LibraryTableRow> allFilesOrdered(Map<String, int> indexOf) {
    final all = <LibraryTableRow>[...files];
    for (final c in children.values) {
      all.addAll(c.allFilesOrdered(indexOf));
    }
    all.sort(
      (a, b) => (indexOf[a.item.id] ?? 0).compareTo(indexOf[b.item.id] ?? 0),
    );
    return all;
  }
}

void _emitPathNode({
  required _PathNode node,
  required int depth,
  required String? parentAbs,
  required Set<String> expandedSourceDirs,
  required Map<String, int> indexOf,
  required p.Context ctx,
  required List<LibraryVisibleEntry> out,
}) {
  final count = node.itemCount;
  if (count < 2) {
    _emitSingletonFiles(
      node: node,
      depth: depth,
      parentAbs: parentAbs,
      indexOf: indexOf,
      ctx: ctx,
      out: out,
    );
    return;
  }

  final label = parentAbs == null || parentAbs.isEmpty
      ? node.absolutePath
      : ctx.relative(node.absolutePath, from: parentAbs);
  final collapsed = !expandedSourceDirs.contains(node.absolutePath);
  out.add(
    LibraryPathGroupHeader(
      dir: node.absolutePath,
      label: label,
      count: count,
      collapsed: collapsed,
      depth: depth,
    ),
  );
  if (collapsed) return;

  _emitPathChildren(
    parent: node,
    depth: depth + 1,
    parentAbs: node.absolutePath,
    expandedSourceDirs: expandedSourceDirs,
    indexOf: indexOf,
    ctx: ctx,
    out: out,
  );
}

void _emitPathChildren({
  required _PathNode parent,
  required int depth,
  required String parentAbs,
  required Set<String> expandedSourceDirs,
  required Map<String, int> indexOf,
  required p.Context ctx,
  required List<LibraryVisibleEntry> out,
}) {
  final kids = parent.children.values.toList()
    ..sort((a, b) => a.firstIndex(indexOf).compareTo(b.firstIndex(indexOf)));
  for (final child in kids) {
    _emitPathNode(
      node: child.compressed,
      depth: depth,
      parentAbs: parentAbs,
      expandedSourceDirs: expandedSourceDirs,
      indexOf: indexOf,
      ctx: ctx,
      out: out,
    );
  }

  final direct = List<LibraryTableRow>.from(parent.files)
    ..sort(
      (a, b) => (indexOf[a.item.id] ?? 0).compareTo(indexOf[b.item.id] ?? 0),
    );
  for (final row in direct) {
    out.add(
      LibraryItemEntry(
        row: row,
        depth: depth,
        sourceDisplay: ctx.relative(row.sourceLabel, from: parentAbs),
      ),
    );
  }
}

void _emitSingletonFiles({
  required _PathNode node,
  required int depth,
  required String? parentAbs,
  required Map<String, int> indexOf,
  required p.Context ctx,
  required List<LibraryVisibleEntry> out,
}) {
  for (final row in node.allFilesOrdered(indexOf)) {
    final display = parentAbs == null || parentAbs.isEmpty
        ? row.sourceLabel
        : ctx.relative(row.sourceLabel, from: parentAbs);
    out.add(
      LibraryItemEntry(
        row: row,
        depth: depth,
        sourceDisplay: display,
      ),
    );
  }
}
