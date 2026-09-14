import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/item_hover_preview.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/library/local_thumb_cache.dart';
import 'package:tagkin_desktop/library/processing_status_view.dart';
import 'package:tagkin_desktop/persons/face_crop_folder_scope.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';
import 'package:tagkin_desktop/prepass/sharpness_score_chip.dart';
import 'package:tagkin_desktop/review/key_period_offsets.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';
import 'package:tagkin_desktop/where/where_label_resolver.dart';
import 'package:tagkin_desktop/where/where_place_label.dart';
import 'package:tagkin_desktop/ui/design_tokens.dart';
import 'package:tagkin_desktop/widgets/sure_action_button.dart';

const double _kThumbSize = 56;
const double _kColThumb = 72;
const double _kColWho = 280;
const double _kColWhat = 180;
const double _kColWhere = 160;
const double _kColComment = 200;

/// Narrow first column: reveal icon; wide enough for "File" + sort arrow.
const double _kColFile = 72;
const double _kColVisibility = 96;
const double _kColStatus = 184;

/// Per-depth indent for path-group chevrons and file icons.
const double _kPathIndent = 8;
const double _kTableMinWidth =
    _kColFile +
    _kColVisibility +
    _kColThumb +
    _kColWho +
    _kColWhat +
    _kColWhere +
    _kColComment +
    _kColStatus;

/// Slight grey for even (1-based) rows — index.isOdd in 0-based list.
const Color _kZebraRow = TagKinTokens.zebraRow;

/// Wide multi-column library table (D2 post-v1).
class LibraryItemsTable extends ConsumerWidget {
  const LibraryItemsTable({
    super.key,
    required this.controller,
    required this.onOpenDetail,
    required this.onHideToggle,
    required this.onHideFolder,
    required this.onRemoveFolder,
    required this.onRevealSource,
    this.onRetryFolder,
    this.isFolderRemoving,
    this.isFolderRetrying,
    this.retryEnabled = true,
  });

  final LibraryTableController controller;
  final void Function(Item item) onOpenDetail;
  final void Function(Item item) onHideToggle;
  final void Function(String dir, {required bool hide}) onHideFolder;
  final void Function(String dir, int count) onRemoveFolder;
  final void Function(Item item) onRevealSource;
  final void Function(String dir)? onRetryFolder;
  final bool Function(String dir)? isFolderRemoving;
  final bool Function(String dir)? isFolderRetrying;
  final bool retryEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final multiColumnSort = ref.watch(multiColumnSortProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final entries = controller.visiblePageEntries;
        return ItemHoverPreviewScope(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                                              failedCount: _failedCountUnder(
                                                controller,
                                                dir,
                                              ),
                                              retryTooltip: _retryTooltipUnder(
                                                controller,
                                                dir,
                                              ),
                                              onToggle: () => controller
                                                  .toggleCollapseSourceDir(dir),
                                              onRemoveFolder: () =>
                                                  onRemoveFolder(dir, count),
                                              onHideFolder: () => onHideFolder(
                                                dir,
                                                hide: !controller
                                                    .isFolderHidden(dir),
                                              ),
                                              folderHidden: controller
                                                  .isFolderHidden(dir),
                                              onRetryFolder:
                                                  onRetryFolder == null
                                                  ? null
                                                  : () => onRetryFolder!(dir),
                                              removing:
                                                  isFolderRemoving?.call(dir) ??
                                                  false,
                                              retrying:
                                                  isFolderRetrying?.call(dir) ??
                                                  false,
                                              retryEnabled: retryEnabled,
                                            ),
                                          LibraryItemEntry(
                                            :final row,
                                            :final period,
                                          ) =>
                                            _DataRow(
                                              index: index,
                                              row: row,
                                              period: period,
                                              controller: controller,
                                              onOpenDetail: onOpenDetail,
                                              onHideToggle: onHideToggle,
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
          ),
        );
      },
    );
  }
}

int _failedCountUnder(LibraryTableController controller, String dir) {
  final items = [for (final row in controller.allRows) row.item];
  final ids = itemIdsUnderFolder(items, dir);
  var n = 0;
  for (final item in items) {
    if (ids.contains(item.id) &&
        item.processingStatus == ProcessingStatus.failed) {
      n++;
    }
  }
  return n;
}

String _retryTooltipUnder(LibraryTableController controller, String dir) {
  final items = [for (final row in controller.allRows) row.item];
  final ids = itemIdsUnderFolder(items, dir);
  final messages = <String>{};
  for (final item in items) {
    if (ids.contains(item.id) &&
        item.processingStatus == ProcessingStatus.failed) {
      final err = item.processingError?.trim();
      if (err != null && err.isNotEmpty) messages.add(err);
    }
  }
  if (messages.isEmpty) return 'Retry failed items';
  return messages.join('\n');
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.controller, required this.multiColumnSort});

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
            SizedBox(
              width: _kColVisibility,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<HiddenItemsFilter>(
                    key: const Key('library-hidden-filter'),
                    isDense: true,
                    isExpanded: true,
                    value: controller.hiddenItemsFilter,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: HiddenItemsFilter.visible,
                        child: Text('Visible'),
                      ),
                      DropdownMenuItem(
                        value: HiddenItemsFilter.hidden,
                        child: Text('Hidden'),
                      ),
                      DropdownMenuItem(
                        value: HiddenItemsFilter.both,
                        child: Text('Both'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) controller.setHiddenItemsFilter(v);
                    },
                  ),
                ),
              ),
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
              trailing: _WhoFilterButton(controller: controller),
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
            SizedBox(
              width: _kColStatus,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<ProcessingStatus?>(
                    key: const Key('library-status-filter'),
                    isDense: true,
                    isExpanded: true,
                    value: controller.statusFilter,
                    hint: const Text(
                      'All statuses',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
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
    this.trailing,
  });

  final String label;
  final double width;
  final LibrarySortColumn column;
  final LibraryTableController controller;
  final bool multiColumnSort;

  /// Optional control (e.g. a column filter button) shown after the sort
  /// label, outside the sort tap target.
  final Widget? trailing;

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
      child: Row(
        children: [
          Expanded(
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
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Who column header filter icon; opens [_WhoFilterDialog].
class _WhoFilterButton extends StatelessWidget {
  const _WhoFilterButton({required this.controller});

  final LibraryTableController controller;

  @override
  Widget build(BuildContext context) {
    final active = controller.whoFilterNames.isNotEmpty;
    final color = active ? Theme.of(context).colorScheme.primary : null;
    final matchLabel = controller.whoFilterMatchAll ? 'Match All' : 'Match Any';
    final tooltip = active
        ? 'Who filter: ${controller.whoFilterNames.length} selected ($matchLabel)'
        : 'Filter Who';
    return Tooltip(
      message: tooltip,
      waitDuration: Duration.zero,
      child: IconButton(
        key: const Key('library-who-filter-button'),
        icon: Icon(
          active ? Icons.filter_alt : Icons.filter_alt_outlined,
          size: 18,
          color: color,
        ),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => _WhoFilterDialog(controller: controller),
        ),
      ),
    );
  }
}

/// Who filter dialog: checklist of names in the currently displayed
/// population (see [LibraryTableController.availableWhoNames]) plus a
/// Match Any (OR) / Match All (AND) toggle for combining multiple names.
class _WhoFilterDialog extends StatefulWidget {
  const _WhoFilterDialog({required this.controller});

  final LibraryTableController controller;

  @override
  State<_WhoFilterDialog> createState() => _WhoFilterDialogState();
}

class _WhoFilterDialogState extends State<_WhoFilterDialog> {
  late final Set<String> _selected = Set<String>.from(
    widget.controller.whoFilterNames,
  );
  late bool _matchAll = widget.controller.whoFilterMatchAll;

  @override
  Widget build(BuildContext context) {
    final names = widget.controller.availableWhoNames.toList();
    return AlertDialog(
      title: const Text('Filter Who'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<bool>(
              key: const Key('who-filter-match-mode'),
              segments: const [
                ButtonSegment(value: false, label: Text('Match Any')),
                ButtonSegment(value: true, label: Text('Match All')),
              ],
              selected: {_matchAll},
              onSelectionChanged: (s) => setState(() => _matchAll = s.first),
            ),
            const SizedBox(height: 12),
            if (names.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No names in the current view yet.'),
              )
            else
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final name in names)
                        CheckboxListTile(
                          key: Key('who-filter-option-$name'),
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(name),
                          value: _selected.contains(name),
                          onChanged: (checked) => setState(() {
                            if (checked ?? false) {
                              _selected.add(name);
                            } else {
                              _selected.remove(name);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('who-filter-clear'),
          onPressed: () => setState(_selected.clear),
          child: const Text('Clear'),
        ),
        TextButton(
          key: const Key('who-filter-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('who-filter-apply'),
          onPressed: () {
            widget.controller.setWhoFilter(
              names: _selected,
              matchAll: _matchAll,
            );
            Navigator.of(context).pop();
          },
          child: const Text('Apply'),
        ),
      ],
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
    required this.failedCount,
    this.retryTooltip = 'Retry failed items',
    required this.onToggle,
    required this.onRemoveFolder,
    required this.onHideFolder,
    required this.folderHidden,
    this.onRetryFolder,
    required this.removing,
    required this.retrying,
    required this.retryEnabled,
  });

  final int index;
  final String dir;
  final String label;
  final int count;
  final bool collapsed;
  final int depth;
  final int failedCount;
  final String retryTooltip;
  final VoidCallback onToggle;
  final VoidCallback onRemoveFolder;
  final VoidCallback onHideFolder;
  final bool folderHidden;
  final VoidCallback? onRetryFolder;
  final bool removing;
  final bool retrying;
  final bool retryEnabled;

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
            padding: EdgeInsets.only(left: 4 + depth * _kPathIndent, right: 8),
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
                removing
                    ? const SizedBox(
                        width: 32,
                        height: 32,
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (retrying)
                            const SizedBox(
                              width: 32,
                              height: 32,
                              child: Padding(
                                padding: EdgeInsets.all(8),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          else if (failedCount > 0)
                            Tooltip(
                              message: retryTooltip,
                              waitDuration: Duration.zero,
                              child: TextButton(
                                key: Key('source-group-retry-$dir'),
                                onPressed: retryEnabled ? onRetryFolder : null,
                                child: const Text('Retry'),
                              ),
                            ),
                          IconButton(
                            key: Key('source-group-hide-$dir'),
                            tooltip: folderHidden
                                ? 'Unhide folder'
                                : 'Hide folder',
                            icon: Icon(
                              folderHidden
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 18,
                            ),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            onPressed: onHideFolder,
                          ),
                          SureActionButton(
                            idleKey: Key('source-group-remove-$dir'),
                            confirmKey: Key('source-group-remove-confirm-$dir'),
                            tooltip: 'Remove folder',
                            confirmSemanticsLabel: 'Confirm remove folder',
                            icon: const Icon(
                              Icons.folder_off_outlined,
                              size: 18,
                            ),
                            iconSize: 18,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            onConfirm: onRemoveFolder,
                          ),
                        ],
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DataRow extends ConsumerWidget {
  const _DataRow({
    required this.index,
    required this.row,
    required this.controller,
    required this.onOpenDetail,
    required this.onHideToggle,
    required this.onRevealSource,
    this.period,
  });

  final int index;
  final LibraryTableRow row;
  final KeyPeriodKnowledge? period;
  final LibraryTableController controller;
  final void Function(Item item) onOpenDetail;
  final void Function(Item item) onHideToggle;
  final void Function(Item item) onRevealSource;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = row.item;
    final zebra = index.isOdd;
    final scopeId = foldersRowScopeId(item.id, period);
    final summary = row.summaryFor(period);
    final who = summary?.who ?? row.who;
    final what = summary?.what ?? row.what;
    final whereEntries = summary?.whereEntries ?? row.whereEntries;
    final comments = summary?.comments ?? row.comments;
    final expanded =
        controller.expandedWho.contains(scopeId) ||
        controller.expandedWhere.contains(scopeId) ||
        controller.expandedComments.contains(scopeId);
    return Material(
      color: zebra ? _kZebraRow : Colors.transparent,
      child: InkWell(
        key: Key('item-row-$scopeId'),
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
                    width: _kColVisibility,
                    child: Center(
                      child: IconButton(
                        key: Key('item-list-hide-$scopeId'),
                        tooltip: item.isHidden ? 'Unhide item' : 'Hide item',
                        icon: Icon(
                          item.isHidden
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 18,
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        onPressed: () => onHideToggle(item),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _kColThumb,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _ThumbCell(
                        row: row,
                        period: period,
                        controller: controller,
                        showScore: ref
                            .watch(desktopPrefsProvider)
                            .showSharpnessScores,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _kColWho,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _WhoValues(
                        itemId: scopeId,
                        values: who,
                        expanded: controller.expandedWho.contains(scopeId),
                        loading: !row.knowledgeLoaded,
                        onToggle: () => controller.toggleExpandWho(scopeId),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _kColWhat,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _WhatCell(
                        item: item,
                        scopeId: scopeId,
                        values: what,
                        loading: !row.knowledgeLoaded,
                        onOpenDetail: onOpenDetail,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _kColWhere,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _WhereValues(
                        itemId: scopeId,
                        entries: whereEntries,
                        expanded: controller.expandedWhere.contains(scopeId),
                        loading: !row.knowledgeLoaded,
                        onToggle: () => controller.toggleExpandWhere(scopeId),
                        onAddFamiliar: (region) async {
                          final added = await ref
                              .read(desktopPrefsControllerProvider)
                              .addFamiliarRegion(region);
                          if (!added) return;
                          ref.read(whereLabelResolverProvider).clearCache();
                          await controller.refreshWhereLabels();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Added “$region” to Familiar state/province',
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _kColComment,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _ExpandableValues(
                        keyPrefix: 'comment',
                        itemId: scopeId,
                        values: comments,
                        expanded: controller.expandedComments.contains(scopeId),
                        loading: !row.commentsLoaded,
                        onToggle: () =>
                            controller.toggleExpandComments(scopeId),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _kColStatus,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: ProcessingStatusBadge(
                            status: row.foldersBadgeStatus,
                            processingError: item.processingError,
                          ),
                        ),
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

class _ThumbCell extends StatelessWidget {
  const _ThumbCell({
    required this.row,
    required this.controller,
    required this.showScore,
    this.period,
  });

  final LibraryTableRow row;
  final LibraryTableController controller;
  final bool showScore;
  final KeyPeriodKnowledge? period;

  @override
  Widget build(BuildContext context) {
    return ItemHoverPreview(
      item: row.item,
      controller: controller,
      period: period,
      child: _Thumb(
        row: row,
        showScore: showScore && period == null,
        period: period,
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.row, required this.showScore, this.period});

  final LibraryTableRow row;
  final bool showScore;
  final KeyPeriodKnowledge? period;

  @override
  Widget build(BuildContext context) {
    final period = this.period;
    final thumb = period == null ? row.thumb : row.periodThumbs[period.id];
    final path = thumb?.hasImage == true ? thumb!.path : null;
    final Widget child;
    if (path != null) {
      child = Image.file(
        File(path),
        key: Key(_thumbKey(row.item.id, period)),
        width: _kThumbSize,
        height: _kThumbSize,
        fit: BoxFit.cover,
        cacheWidth: (_kThumbSize * 2).round(),
        cacheHeight: (_kThumbSize * 2).round(),
        errorBuilder: (_, _, _) => _placeholder(row.item, thumb),
      );
    } else {
      child = _placeholder(row.item, thumb);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: _kThumbSize,
        height: _kThumbSize,
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (showScore && row.item.type == ItemType.photo)
              Positioned(
                left: 2,
                bottom: 2,
                child: SharpnessScoreChip(
                  key: Key('item-sharpness-${row.item.id}'),
                  item: row.item,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(Item item, LocalThumbResult? thumb) {
    final icon = item.type == ItemType.video
        ? Icons.videocam_outlined
        : Icons.image_outlined;
    final status = thumb?.status;
    final missing =
        status == LocalMediaStatus.missing ||
        status == LocalMediaStatus.accessDenied;
    return ColoredBox(
      color: Colors.black12,
      child: Icon(
        missing ? Icons.broken_image_outlined : icon,
        key: Key(_thumbPlaceholderKey(item.id, period)),
      ),
    );
  }
}

String _thumbKey(String itemId, KeyPeriodKnowledge? period) {
  if (period == null) return 'item-thumb-$itemId';
  return 'item-thumb-$itemId-kp-${period.id}';
}

String _thumbPlaceholderKey(String itemId, KeyPeriodKnowledge? period) {
  if (period == null) return 'item-thumb-placeholder-$itemId';
  return 'item-thumb-placeholder-$itemId-kp-${period.id}';
}

class _WhereValues extends ConsumerWidget {
  const _WhereValues({
    required this.itemId,
    required this.entries,
    required this.expanded,
    required this.loading,
    required this.onToggle,
    required this.onAddFamiliar,
  });

  final String itemId;
  final List<WhereDisplay> entries;
  final bool expanded;
  final bool loading;
  final VoidCallback onToggle;
  final Future<void> Function(String region) onAddFamiliar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (loading && entries.isEmpty) {
      return Text(
        '…',
        key: Key('item-where-loading-$itemId'),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    if (entries.isEmpty) {
      return Text(
        '—',
        key: Key('item-where-empty-$itemId'),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final familiarCsv = ref.watch(desktopPrefsProvider).familiarRegions;
    final shown = expanded ? entries : entries.take(1).toList();
    final more = entries.length - 1;
    return ClipRect(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in shown)
            _WhereEntryLine(
              itemId: itemId,
              entry: entry,
              familiarCsv: familiarCsv,
              onAddFamiliar: onAddFamiliar,
            ),
          if (!expanded && more > 0)
            TextButton(
              key: Key('item-where-more-$itemId'),
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
              key: Key('item-where-less-$itemId'),
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

class _WhereEntryLine extends StatelessWidget {
  const _WhereEntryLine({
    required this.itemId,
    required this.entry,
    required this.familiarCsv,
    required this.onAddFamiliar,
  });

  final String itemId;
  final WhereDisplay entry;
  final String familiarCsv;
  final Future<void> Function(String region) onAddFamiliar;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    final regionName = entry.regionName;
    final showAdd =
        regionName != null &&
        entry.region != null &&
        !isFamiliarRegion(regionName, familiarCsv);

    // Plain / non-segmented (scene labels, raw coords, city-only).
    if (entry.locality == null &&
        entry.region == null &&
        entry.country == null) {
      return Text(
        entry.label,
        key: Key('item-where-$itemId'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    final children = <InlineSpan>[];
    void addText(String text, {bool commaBefore = false}) {
      if (commaBefore && children.isNotEmpty) {
        children.add(TextSpan(text: ', ', style: style));
      }
      children.add(TextSpan(text: text, style: style));
    }

    if (entry.locality != null) {
      addText(entry.locality!);
    }
    if (entry.region != null) {
      addText(entry.region!, commaBefore: true);
    }
    if (entry.country != null) {
      addText(entry.country!, commaBefore: true);
    }

    final place = Text.rich(
      TextSpan(children: children),
      key: Key('item-where-$itemId'),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );

    if (!showAdd) return place;

    final region = regionName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        place,
        Tooltip(
          message: 'Add to Familiar state/province',
          child: FilledButton.tonal(
            key: Key('item-where-add-familiar-$itemId'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => onAddFamiliar(region),
            child: Text(
              'Add $region',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}

/// Horizontal space left for Who names after the cell's 8px padding.
const double _kWhoTextWidth = _kColWho - 16;
const int _kWhoCollapsedMaxLines = 2;

/// How many leading [names] fit on [maxLines] at [maxWidth] without wrapping
/// past the last line. Always at least 1 when [names] is non-empty.
int _whoNamesFitting({
  required List<String> names,
  required TextStyle style,
  required double maxWidth,
  required int maxLines,
}) {
  if (names.isEmpty) return 0;
  for (var n = names.length; n >= 1; n--) {
    final painter = TextPainter(
      text: TextSpan(text: names.take(n).join(', '), style: style),
      maxLines: maxLines,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    final fits = !painter.didExceedMaxLines;
    painter.dispose();
    if (fits) return n;
  }
  return 1;
}

/// Library Who: as many names as fit, tooltip lists every name, +N more on overflow.
class _WhoValues extends StatelessWidget {
  const _WhoValues({
    required this.itemId,
    required this.values,
    required this.expanded,
    required this.loading,
    required this.onToggle,
  });

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
        key: Key('item-who-loading-$itemId'),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    if (values.isEmpty) {
      return Text(
        '—',
        key: Key('item-who-empty-$itemId'),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final style = DefaultTextStyle.of(context).style;
    final collapsedFit = _whoNamesFitting(
      names: values,
      style: style,
      maxWidth: _kWhoTextWidth,
      maxLines: _kWhoCollapsedMaxLines,
    );
    final overflowCount = values.length - collapsedFit;
    final shown = expanded ? values : values.take(collapsedFit).toList();
    final allNames = values.join(', ');
    final cell = ClipRect(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            shown.join(', '),
            key: Key('item-who-$itemId'),
            maxLines: expanded ? null : _kWhoCollapsedMaxLines,
            overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          ),
          if (!expanded && overflowCount > 0)
            TextButton(
              key: Key('item-who-more-$itemId'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onToggle,
              child: Text('+$overflowCount more'),
            ),
          if (expanded && overflowCount > 0)
            TextButton(
              key: Key('item-who-less-$itemId'),
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
    return Tooltip(
      key: Key('item-who-tooltip-$itemId'),
      message: allNames,
      waitDuration: Duration.zero,
      child: cell,
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
    this.scopeId,
  });

  final Item item;
  final String? scopeId;
  final List<String> values;
  final bool loading;
  final void Function(Item item) onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final id = scopeId ?? item.id;
    if (loading && values.isEmpty) {
      return Text(
        '…',
        key: Key('item-what-loading-$id'),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final label = values.isEmpty ? 'Details…' : values.join(', ');
    return TextButton(
      key: Key('item-what-$id'),
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
        icon: Icon(
          item.type == ItemType.video
              ? Icons.videocam_outlined
              : Icons.image_outlined,
          size: 18,
          semanticLabel: item.type == ItemType.video ? 'Video' : 'Photo',
        ),
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
              onPressed: page <= 0 ? null : () => controller.setPage(page - 1),
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
