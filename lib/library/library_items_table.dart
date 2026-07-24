import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/library/processing_status_view.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';

const double _kThumbSize = 56;
const double _kColThumb = 72;
const double _kColWho = 160;
const double _kColWhat = 180;
const double _kColWhere = 160;
const double _kColComment = 200;
/// Narrow first column: reveal icon; wide enough for "File" + sort arrow.
const double _kColFile = 72;
const double _kColActions = 200;
/// Per-depth indent for path-group chevrons and file icons.
const double _kPathIndent = 8;
const double _kTableMinWidth = _kColFile +
    _kColThumb +
    _kColWho +
    _kColWhat +
    _kColWhere +
    _kColComment +
    _kColActions;

/// Slight grey for even (1-based) rows — index.isOdd in 0-based list.
const Color _kZebraRow = Color(0xFFF3F4F6);

/// Wide multi-column library table (D2 post-v1).
class LibraryItemsTable extends ConsumerWidget {
  const LibraryItemsTable({
    super.key,
    required this.controller,
    required this.onOpenDetail,
    required this.onDelete,
    required this.onRevealSource,
  });

  final LibraryTableController controller;
  final void Function(Item item) onOpenDetail;
  final void Function(Item item) onDelete;
  final void Function(Item item) onRevealSource;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final multiColumnSort = ref.watch(multiColumnSortProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final entries = controller.visiblePageEntries;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FilterBar(controller: controller),
            const Divider(height: 1),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth < _kTableMinWidth
                      ? _kTableMinWidth
                      : constraints.maxWidth;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: width,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _HeaderRow(
                            controller: controller,
                            multiColumnSort: multiColumnSort,
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: entries.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No matching items',
                                      key: Key('items-filtered-empty'),
                                    ),
                                  )
                                : ListView.separated(
                                    key: const Key('items-list'),
                                    itemCount: entries.length,
                                    separatorBuilder: (_, _) =>
                                        const Divider(height: 1),
                                    itemBuilder: (context, index) {
                                      final entry = entries[index];
                                      return switch (entry) {
                                        LibraryPathGroupHeader(
                                          :final dir,
                                          :final label,
                                          :final count,
                                          :final collapsed,
                                          :final depth,
                                        ) =>
                                          _PathGroupHeader(
                                            index: index,
                                            dir: dir,
                                            label: label,
                                            count: count,
                                            collapsed: collapsed,
                                            depth: depth,
                                            onToggle: () => controller
                                                .toggleCollapseSourceDir(dir),
                                          ),
                                        LibraryItemEntry(
                                          :final row,
                                        ) =>
                                          _DataRow(
                                            index: index,
                                            row: row,
                                            controller: controller,
                                            onOpenDetail: onOpenDetail,
                                            onDelete: onDelete,
                                            onRevealSource: onRevealSource,
                                          ),
                                      };
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            _PaginationBar(controller: controller),
          ],
        );
      },
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.controller});

  final LibraryTableController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('library-filter'),
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: 'Filter who, what, where, source, comment…',
                border: OutlineInputBorder(),
              ),
              onChanged: controller.setFilterQuery,
            ),
          ),
          const SizedBox(width: 12),
          DropdownButton<ProcessingStatus?>(
            key: const Key('library-status-filter'),
            value: controller.statusFilter,
            hint: const Text('All statuses'),
            items: [
              const DropdownMenuItem<ProcessingStatus?>(
                value: null,
                child: Text('All statuses'),
              ),
              ...ProcessingStatus.values.map(
                (s) => DropdownMenuItem<ProcessingStatus?>(
                  value: s,
                  child: Text(s.wire),
                ),
              ),
            ],
            onChanged: (v) => controller.setStatusFilter(v),
          ),
          if (controller.knowledgeWarming) ...[
            const SizedBox(width: 12),
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.controller,
    required this.multiColumnSort,
  });

  final LibraryTableController controller;
  final bool multiColumnSort;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            _SortHeader(
              label: 'File',
              width: _kColFile,
              column: LibrarySortColumn.source,
              controller: controller,
              multiColumnSort: multiColumnSort,
            ),
            const SizedBox(
              width: _kColThumb,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Thumb',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            _SortHeader(
              label: 'Who',
              width: _kColWho,
              column: LibrarySortColumn.who,
              controller: controller,
              multiColumnSort: multiColumnSort,
            ),
            _SortHeader(
              label: 'What',
              width: _kColWhat,
              column: LibrarySortColumn.what,
              controller: controller,
              multiColumnSort: multiColumnSort,
            ),
            _SortHeader(
              label: 'Where',
              width: _kColWhere,
              column: LibrarySortColumn.where,
              controller: controller,
              multiColumnSort: multiColumnSort,
            ),
            _SortHeader(
              label: 'Comment',
              width: _kColComment,
              column: LibrarySortColumn.comment,
              controller: controller,
              multiColumnSort: multiColumnSort,
            ),
            const SizedBox(
              width: _kColActions,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Status',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortHeader extends StatelessWidget {
  const _SortHeader({
    required this.label,
    required this.width,
    required this.column,
    required this.controller,
    required this.multiColumnSort,
  });

  final String label;
  final double width;
  final LibrarySortColumn column;
  final LibraryTableController controller;
  final bool multiColumnSort;

  @override
  Widget build(BuildContext context) {
    final keys = controller.sortKeys;
    final idx = keys.indexWhere((k) => k.column == column);
    final key = idx >= 0 ? keys[idx] : null;
    IconData? icon;
    if (key != null) {
      icon = key.ascending ? Icons.arrow_upward : Icons.arrow_downward;
    }
    return SizedBox(
      width: width,
      child: InkWell(
        key: Key('sort-header-${column.name}'),
        onTap: () {
          controller.toggleSort(column, multiColumn: multiColumnSort);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: 4),
                Icon(icon, size: 14),
                if (multiColumnSort && keys.length > 1)
                  Text(
                    '${idx + 1}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PathGroupHeader extends StatelessWidget {
  const _PathGroupHeader({
    required this.index,
    required this.dir,
    required this.label,
    required this.count,
    required this.collapsed,
    required this.depth,
    required this.onToggle,
  });

  final int index;
  final String dir;
  final String label;
  final int count;
  final bool collapsed;
  final int depth;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final zebra = index.isOdd;
    const labelStyle = TextStyle(fontWeight: FontWeight.w600);
    final countText = Text(
      '($count)',
      key: Key('source-group-count-$dir'),
      style: labelStyle,
    );
    return Material(
      color: zebra ? _kZebraRow : Colors.transparent,
      child: InkWell(
        key: Key('source-group-$dir'),
        onTap: onToggle,
        child: SizedBox(
          height: 40,
          child: Padding(
            padding: EdgeInsets.only(
              left: 4 + depth * _kPathIndent,
              right: 8,
            ),
            child: Row(
              children: [
                Icon(
                  key: Key('source-group-toggle-$dir'),
                  collapsed ? Icons.chevron_right : Icons.expand_more,
                  size: 18,
                ),
                const SizedBox(width: 2),
                // Full-width row; path + (count) clustered on the left.
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Reserve space so (count) never ellipsizes away.
                      const countReserve = 48.0;
                      final pathMax = (constraints.maxWidth - countReserve)
                          .clamp(0.0, constraints.maxWidth);
                      final path = Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: labelStyle,
                      );
                      final pathChild = depth > 0
                          ? Stack(
                              alignment: Alignment.centerLeft,
                              children: [
                                path,
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  bottom: 0,
                                  width: pathMax.clamp(0.0, 220.0),
                                  child: Tooltip(
                                    message: dir,
                                    preferBelow: true,
                                    verticalOffset: 4,
                                    waitDuration: Duration.zero,
                                    child: const ColoredBox(
                                      color: Colors.transparent,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : path;
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: pathMax),
                              child: pathChild,
                            ),
                            const SizedBox(width: 8),
                            countText,
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.index,
    required this.row,
    required this.controller,
    required this.onOpenDetail,
    required this.onDelete,
    required this.onRevealSource,
  });

  final int index;
  final LibraryTableRow row;
  final LibraryTableController controller;
  final void Function(Item item) onOpenDetail;
  final void Function(Item item) onDelete;
  final void Function(Item item) onRevealSource;

  @override
  Widget build(BuildContext context) {
    final item = row.item;
    final zebra = index.isOdd;
    final expanded = controller.expandedWho.contains(item.id) ||
        controller.expandedWhere.contains(item.id) ||
        controller.expandedComments.contains(item.id);
    return Material(
      color: zebra ? _kZebraRow : Colors.transparent,
      child: InkWell(
        key: Key('item-row-${item.id}'),
        onTap: () => onOpenDetail(item),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: SizedBox(
            height: expanded ? null : 72,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: expanded ? 8 : 0),
              child: Row(
                crossAxisAlignment: expanded
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: _kColFile,
                    child: _FileReveal(
                      item: item,
                      path: row.sourceLabel,
                      onReveal: () => onRevealSource(item),
                    ),
                  ),
                  SizedBox(
                    width: _kColThumb,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _Thumb(row: row),
                    ),
                  ),
                  SizedBox(
                    width: _kColWho,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _ExpandableValues(
                        keyPrefix: 'who',
                        itemId: item.id,
                        values: row.who,
                        expanded: controller.expandedWho.contains(item.id),
                        loading: !row.knowledgeLoaded,
                        onToggle: () => controller.toggleExpandWho(item.id),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _kColWhat,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _WhatCell(
                        item: item,
                        values: row.what,
                        loading: !row.knowledgeLoaded,
                        onOpenDetail: onOpenDetail,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _kColWhere,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _ExpandableValues(
                        keyPrefix: 'where',
                        itemId: item.id,
                        values: row.where,
                        expanded: controller.expandedWhere.contains(item.id),
                        loading: !row.knowledgeLoaded,
                        onToggle: () => controller.toggleExpandWhere(item.id),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _kColComment,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _ExpandableValues(
                        keyPrefix: 'comment',
                        itemId: item.id,
                        values: row.comments,
                        expanded:
                            controller.expandedComments.contains(item.id),
                        loading: !row.commentsLoaded,
                        onToggle: () =>
                            controller.toggleExpandComments(item.id),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _kColActions,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: ProcessingStatusBadge(
                                status: item.processingStatus,
                              ),
                            ),
                          ),
                          IconButton(
                            key: Key('item-list-delete-${item.id}'),
                            tooltip: 'Delete item',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => onDelete(item),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.row});

  final LibraryTableRow row;

  @override
  Widget build(BuildContext context) {
    final thumb = row.thumb;
    final path = thumb?.hasImage == true ? thumb!.path : null;
    final Widget child;
    if (path != null) {
      child = Image.file(
        File(path),
        key: Key('item-thumb-${row.item.id}'),
        width: _kThumbSize,
        height: _kThumbSize,
        fit: BoxFit.cover,
        cacheWidth: (_kThumbSize * 2).round(),
        cacheHeight: (_kThumbSize * 2).round(),
        errorBuilder: (_, _, _) => _placeholder(row.item),
      );
    } else {
      child = _placeholder(row.item);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: _kThumbSize,
        height: _kThumbSize,
        child: child,
      ),
    );
  }

  Widget _placeholder(Item item) {
    final icon = item.type == ItemType.video
        ? Icons.videocam_outlined
        : Icons.image_outlined;
    final status = row.thumb?.status;
    final missing = status == LocalMediaStatus.missing ||
        status == LocalMediaStatus.accessDenied;
    return ColoredBox(
      color: Colors.black12,
      child: Icon(
        missing ? Icons.broken_image_outlined : icon,
        key: Key('item-thumb-placeholder-${item.id}'),
      ),
    );
  }
}

class _ExpandableValues extends StatelessWidget {
  const _ExpandableValues({
    required this.keyPrefix,
    required this.itemId,
    required this.values,
    required this.expanded,
    required this.loading,
    required this.onToggle,
  });

  final String keyPrefix;
  final String itemId;
  final List<String> values;
  final bool expanded;
  final bool loading;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    if (loading && values.isEmpty) {
      return Text(
        '…',
        key: Key('item-$keyPrefix-loading-$itemId'),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    if (values.isEmpty) {
      return Text(
        '—',
        key: Key('item-$keyPrefix-empty-$itemId'),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final shown = expanded ? values : values.take(1).toList();
    final more = values.length - 1;
    return ClipRect(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            shown.join(', '),
            key: Key('item-$keyPrefix-$itemId'),
            // Collapsed: one line so text + "+N more" fit in the 72px row.
            maxLines: expanded ? 4 : 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (!expanded && more > 0)
            TextButton(
              key: Key('item-$keyPrefix-more-$itemId'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onToggle,
              child: Text('+$more more'),
            ),
          if (expanded && more > 0)
            TextButton(
              key: Key('item-$keyPrefix-less-$itemId'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onToggle,
              child: const Text('Show less'),
            ),
        ],
      ),
    );
  }
}

class _WhatCell extends StatelessWidget {
  const _WhatCell({
    required this.item,
    required this.values,
    required this.loading,
    required this.onOpenDetail,
  });

  final Item item;
  final List<String> values;
  final bool loading;
  final void Function(Item item) onOpenDetail;

  @override
  Widget build(BuildContext context) {
    if (loading && values.isEmpty) {
      return Text(
        '…',
        key: Key('item-what-loading-${item.id}'),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final label = values.isEmpty ? 'Details…' : values.join(', ');
    return TextButton(
      key: Key('item-what-${item.id}'),
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        alignment: Alignment.centerLeft,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: () => onOpenDetail(item),
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.left,
      ),
    );
  }
}

class _FileReveal extends StatelessWidget {
  const _FileReveal({
    required this.item,
    required this.path,
    required this.onReveal,
  });

  final Item item;
  final String path;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) {
      return Center(
        child: Text(
          '—',
          key: Key('item-source-empty-${item.id}'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    return Tooltip(
      message: path,
      preferBelow: true,
      verticalOffset: 4,
      waitDuration: Duration.zero,
      child: IconButton(
        key: Key('item-source-${item.id}'),
        icon: const Icon(Icons.insert_drive_file_outlined, size: 18),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        visualDensity: VisualDensity.compact,
        onPressed: onReveal,
      ),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({required this.controller});

  final LibraryTableController controller;

  @override
  Widget build(BuildContext context) {
    final total = controller.totalFiltered;
    final pages = controller.pageCount;
    final page = controller.pageIndex;
    return Material(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Text(
              total == 0
                  ? '0 items'
                  : '${page * controller.pageSize + 1}–'
                      '${page * controller.pageSize + controller.visiblePageEntries.length} '
                      'of $total',
              key: const Key('library-page-label'),
            ),
            const Spacer(),
            IconButton(
              key: const Key('library-page-prev'),
              onPressed:
                  page <= 0 ? null : () => controller.setPage(page - 1),
              icon: const Icon(Icons.chevron_left),
            ),
            Text('Page ${page + 1} / $pages'),
            IconButton(
              key: const Key('library-page-next'),
              onPressed: page >= pages - 1
                  ? null
                  : () => controller.setPage(page + 1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}
