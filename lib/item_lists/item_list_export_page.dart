import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/item_lists/item_list_csv.dart';
import 'package:tagkin_desktop/item_lists/item_list_export_controller.dart';
import 'package:tagkin_desktop/library/item_hover_preview.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/library/local_thumb_cache.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';
import 'package:tagkin_desktop/prepass/sharpness_score_chip.dart';
import 'package:tagkin_desktop/shell/app_nav_tab_buttons.dart';
import 'package:tagkin_desktop/ui/format_local_datetime.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

/// Filter photos and video key periods from a Folders View, reorder, and
/// export JSON, FCP7 XML, or FCPXML.
class ItemListExportPage extends ConsumerStatefulWidget {
  const ItemListExportPage({super.key});

  @override
  ConsumerState<ItemListExportPage> createState() => _ItemListExportPageState();
}

class _ItemListExportPageState extends ConsumerState<ItemListExportPage> {
  final _previewScroll = ScrollController();
  final _description = TextEditingController();
  ItemListExportFormat _format = ItemListExportFormat.json;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = ref.read(itemListExportControllerProvider);
      final cols = ref.read(collectionsControllerProvider);
      Set<String>? folders;
      if (cols.sessionReady && cols.current.leafFolders.isNotEmpty) {
        folders = cols.current.leafFolders.toSet();
      }
      final viewId = ref.read(libraryTableControllerProvider).activeViewId;
      final view = viewId == null ? null : cols.viewById(viewId);
      unawaited(controller.load(collectionFolders: folders, view: view));
    });
  }

  @override
  void dispose() {
    _previewScroll.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    final prefs = ref.read(desktopPrefsProvider);
    final path = await ref.read(itemListExportControllerProvider).export(
          format: _format,
          description: _description.text,
          stillDurationSeconds:
              prefs.exportPhotoStillDurationSecondsOrDefault,
          transition: prefs.exportPhotoTransitionOrDefault,
          transitionSeconds: prefs.exportPhotoTransitionSecondsOrDefault,
          sequenceSize: prefs.exportSequenceSizeOrDefault,
        );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (path == null) return;
    messenger.showSnackBar(SnackBar(content: Text('Saved $path')));
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(itemListExportControllerProvider);
    final prefs = ref.watch(desktopPrefsProvider);
    final format = prefs.dateTimeFormatOrLocal;
    final visible = controller.entries;

    return SelectableScope(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Item list'),
          actions: const [
            SelectionContainer.disabled(
              child: AppNavTabButtons(),
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    key: const Key('item-list-description'),
                    controller: _description,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      hintText: 'Optional note saved with the export',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _ViewsDropdown(controller: controller),
                      const SizedBox(width: 16),
                      _FormatDropdown(
                        format: _format,
                        onSelected: (next) => setState(() => _format = next),
                      ),
                      const SizedBox(width: 16),
                      FilledButton(
                        key: const Key('item-list-export'),
                        onPressed: controller.hasEntries ? _export : null,
                        child: const Text('Export'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (controller.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  controller.error!,
                  key: const Key('item-list-error'),
                ),
              ),
            if (controller.loadingList) const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                '${visible.length} '
                '${visible.length == 1 ? 'item' : 'items'}',
                key: const Key('item-list-count'),
              ),
            ),
            Expanded(
              child: SelectionContainer.disabled(
                child: ItemHoverPreviewScope(
                  child: Scrollbar(
                    controller: _previewScroll,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _previewScroll,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 12,
                        children: [
                          for (var i = 0; i < controller.entries.length; i++)
                            _FilmstripTile(
                              key: ValueKey(
                                itemListEntryKey(controller.entries[i]),
                              ),
                              index: i,
                              entry: controller.entries[i],
                              item: controller.itemsById[
                                  controller.entries[i].itemId],
                              period: controller
                                  .periodFor(controller.entries[i]),
                              libraryTable: controller.libraryTable,
                              showSharpnessScore: prefs.showSharpnessScores,
                              format: format,
                              resolveThumb: () =>
                                  controller.thumbFor(controller.entries[i]),
                              onRemove: () => controller.removeAt(i),
                              onReorder: controller.reorder,
                            ),
                        ],
                      ),
                    ),
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

const double _kFilmstripStill = 180;

class _ViewsDropdown extends ConsumerWidget {
  const _ViewsDropdown({required this.controller});

  final ItemListExportController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cols = ref.watch(collectionsControllerProvider);
    final active = controller.selectedView;
    final label = active?.name ?? 'All';
    final views = cols.views;

    return PopupMenuButton<String>(
      key: const Key('item-list-views-menu'),
      tooltip: 'Views',
      onSelected: (id) {
        if (id.isEmpty) {
          unawaited(controller.selectView(null));
          return;
        }
        final view = cols.viewById(id);
        if (view == null) return;
        unawaited(controller.selectView(view));
      },
      itemBuilder: (context) {
        return [
          PopupMenuItem(
            key: const Key('item-list-views-all'),
            value: '',
            child: Text(active == null ? 'All ✓' : 'All'),
          ),
          if (views.isNotEmpty) const PopupMenuDivider(),
          for (final v in views)
            PopupMenuItem(
              key: Key('item-list-views-${v.id}'),
              value: v.id,
              child: Text(
                v.id == active?.id ? '${v.name} ✓' : v.name,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ];
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.layers_outlined, size: 18),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
      ),
    );
  }
}

class _FormatDropdown extends StatelessWidget {
  const _FormatDropdown({required this.format, required this.onSelected});

  final ItemListExportFormat format;
  final ValueChanged<ItemListExportFormat> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ItemListExportFormat>(
      key: const Key('item-list-format-menu'),
      tooltip: 'Format',
      onSelected: onSelected,
      itemBuilder: (context) {
        return [
          for (final f in ItemListExportFormat.values)
            PopupMenuItem(
              key: Key('item-list-format-${f.name}'),
              value: f,
              child: Text(f == format ? '${f.label} ✓' : f.label),
            ),
        ];
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file_outlined, size: 18),
            const SizedBox(width: 6),
            Text(
              format.label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
      ),
    );
  }
}

class _FilmstripTile extends StatefulWidget {
  const _FilmstripTile({
    super.key,
    required this.index,
    required this.entry,
    this.item,
    this.period,
    required this.libraryTable,
    required this.showSharpnessScore,
    required this.format,
    required this.resolveThumb,
    required this.onRemove,
    required this.onReorder,
  });

  final int index;
  final ItemListEntry entry;
  final Item? item;
  final KeyPeriodKnowledge? period;
  final LibraryTableController libraryTable;
  final bool showSharpnessScore;
  final DateTimeDisplayFormat format;
  final Future<LocalThumbResult> Function() resolveThumb;
  final VoidCallback onRemove;
  final void Function(int from, int to) onReorder;

  @override
  State<_FilmstripTile> createState() => _FilmstripTileState();
}

class _FilmstripTileState extends State<_FilmstripTile> {
  late Future<LocalThumbResult> _thumb;

  @override
  void initState() {
    super.initState();
    _thumb = widget.resolveThumb();
  }

  @override
  void didUpdateWidget(_FilmstripTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.itemId != widget.entry.itemId ||
        oldWidget.entry.keyPeriodId != widget.entry.keyPeriodId ||
        oldWidget.entry.startMs != widget.entry.startMs) {
      _thumb = widget.resolveThumb();
    }
  }

  String get _id => itemListEntryKey(widget.entry);

  @override
  Widget build(BuildContext context) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != widget.index,
      onAcceptWithDetails: (details) {
        widget.onReorder(details.data, widget.index);
      },
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: hovering
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  )
                : Border.all(color: Colors.transparent, width: 2),
          ),
          child: SizedBox(
            width: _kFilmstripStill,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Draggable<int>(
                    data: widget.index,
                    feedback: Material(
                      elevation: 6,
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 120,
                        height: 120,
                        child: ColoredBox(
                          color: Theme.of(context).colorScheme.surface,
                          child: Center(
                            child: Text(
                              itemListEntryKindLabel(widget.entry.kind),
                            ),
                          ),
                        ),
                      ),
                    ),
                    childWhenDragging: const Opacity(
                      opacity: 0.35,
                      child: Icon(Icons.drag_handle),
                    ),
                    child: Tooltip(
                      message: 'Reorder',
                      child: Icon(
                        Icons.drag_handle,
                        key: Key('item-list-drag-$_id'),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: _kFilmstripStill,
                  height: _kFilmstripStill,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _hoverStill(),
                      ),
                      if (widget.showSharpnessScore &&
                          widget.item != null &&
                          widget.item!.type == ItemType.photo)
                        Positioned(
                          left: 4,
                          bottom: 4,
                          child: SharpnessScoreChip(
                            key: Key('item-list-sharpness-$_id'),
                            item: widget.item!,
                          ),
                        ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: IconButton(
                          key: Key('item-list-remove-$_id'),
                          tooltip: 'Remove',
                          onPressed: widget.onRemove,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black54,
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  itemListEntryKindLabel(widget.entry.kind),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _caption(widget.entry, widget.format),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _hoverStill() {
    final item = widget.item;
    final still = _still();
    if (item == null) return still;
    return ItemHoverPreview(
      item: item,
      controller: widget.libraryTable,
      period: widget.period,
      child: still,
    );
  }

  Widget _still() {
    return FutureBuilder<LocalThumbResult>(
      future: _thumb,
      builder: (context, snapshot) {
        final result = snapshot.data;
        final path = result != null && result.hasImage ? result.path : null;
        if (path != null) {
          return Image.file(
            File(path),
            key: Key('item-list-still-$_id'),
            fit: BoxFit.cover,
            cacheWidth: (_kFilmstripStill * 2).round(),
            cacheHeight: (_kFilmstripStill * 2).round(),
            errorBuilder: (_, _, _) => _placeholder(result?.status),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const ColoredBox(
            color: Colors.black12,
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return _placeholder(result?.status);
      },
    );
  }

  Widget _placeholder(LocalMediaStatus? status) {
    final video = widget.entry.kind == ItemListEntryKind.keyperiod;
    final missing = status == LocalMediaStatus.missing ||
        status == LocalMediaStatus.accessDenied;
    return ColoredBox(
      color: Colors.black12,
      child: Icon(
        missing
            ? Icons.broken_image_outlined
            : (video ? Icons.videocam_outlined : Icons.image_outlined),
        key: Key('item-list-still-placeholder-$_id'),
      ),
    );
  }
}

String _caption(ItemListEntry entry, DateTimeDisplayFormat format) {
  if (entry.kind == ItemListEntryKind.keyperiod &&
      entry.startMs != null &&
      entry.endMs != null) {
    return '${formatKeyPeriodMs(entry.startMs!)}–${formatKeyPeriodMs(entry.endMs!)}';
  }
  return formatLocalDateTime(entry.when, format: format);
}
