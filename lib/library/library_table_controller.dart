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
import 'package:tagkin_desktop/review/knowledge_grouping.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';
import 'package:tagkin_desktop/where/where_label_resolver.dart';

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
    this.where = const [],
    this.whereRaw = const [],
    this.comments = const [],
    this.knowledgeLoaded = false,
    this.commentsLoaded = false,
    this.thumb,
  });

  final Item item;
  final List<String> who;
  final List<String> what;

  /// Display where labels (GPS reverse-geocoded when applicable).
  final List<String> where;

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
    List<String>? where,
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
      where: where ?? this.where,
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
    this.pageSize = 50,
    this.knowledgeConcurrency = 6,
  })  : _thumbCache = thumbCache ?? LocalThumbCache(),
        _whereLabels = whereLabelResolver ?? WhereLabelResolver();

  final ItemsRepository itemsRepository;
  final CommentsRepository commentsRepository;
  final LocalThumbCache _thumbCache;
  final WhereLabelResolver _whereLabels;
  final int pageSize;
  final int knowledgeConcurrency;

  List<LibraryTableRow> _rows = const [];
  Object? error;
  bool loading = false;
  bool knowledgeWarming = false;

  String filterQuery = '';
  ProcessingStatus? statusFilter;
  List<LibrarySortKey> sortKeys = const [];
  int pageIndex = 0;

  /// Item ids with who/where/comment expanded in the table.
  final Set<String> expandedWho = {};
  final Set<String> expandedWhere = {};
  final Set<String> expandedComments = {};

  /// Parent dirs the user has expanded (multi-item groups default collapsed).
  final Set<String> expandedSourceDirs = {};

  int? _loadGeneration;

  List<LibraryTableRow> get allRows => _rows;

  List<LibraryTableRow> get filteredSorted {
    var list = List<LibraryTableRow>.from(_rows);
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
    loading = true;
    error = null;
    notifyListeners();

    try {
      final items = await itemsRepository.listItems(status: statusFilter);
      if (_loadGeneration != gen) return;
      _thumbCache.clear();
      expandedWho.clear();
      expandedWhere.clear();
      expandedComments.clear();
      expandedSourceDirs.clear();
      _rows = items.map((item) => LibraryTableRow(item: item)).toList();
      pageIndex = 0;
      loading = false;
      notifyListeners();

      unawaited(_warmThumbs(gen));
      unawaited(_warmKnowledge(gen));
      unawaited(_warmComments(gen));
    } catch (e) {
      if (_loadGeneration != gen) return;
      error = e;
      loading = false;
      notifyListeners();
    }
  }

  void setFilterQuery(String value) {
    filterQuery = value;
    pageIndex = 0;
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
      final labels = await _whereLabels.resolveAll(row.whereRaw);
      _replaceRow(row.item.id, (r) => r.copyWith(where: labels));
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
          final whereLabels = await _whereLabels.resolveAll(whereRaw);
          if (_loadGeneration != gen) return;
          _replaceRow(
            id,
            (r) => r.copyWith(
              who: grouped['who']!.map((t) => t.value).toList(),
              what: grouped['what']!.map((t) => t.value).toList(),
              where: whereLabels,
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
    );
  },
  dependencies: [
    itemsRepositoryProvider,
    commentsRepositoryProvider,
    whereLabelResolverProvider,
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
