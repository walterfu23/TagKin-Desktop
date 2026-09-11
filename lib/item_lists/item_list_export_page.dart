import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/item_lists/item_list_csv.dart';
import 'package:tagkin_desktop/item_lists/item_list_export_controller.dart';
import 'package:tagkin_desktop/library/local_thumb_cache.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';
import 'package:tagkin_desktop/shell/app_nav_tab_buttons.dart';
import 'package:tagkin_desktop/ui/format_local_datetime.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

/// Filter photos and video key periods, reorder, and export a CSV manifest.
class ItemListExportPage extends ConsumerStatefulWidget {
  const ItemListExportPage({super.key});

  @override
  ConsumerState<ItemListExportPage> createState() => _ItemListExportPageState();
}

class _ItemListExportPageState extends ConsumerState<ItemListExportPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(itemListExportControllerProvider).load());
    });
  }

  Future<void> _pickDay({required bool from}) async {
    final controller = ref.read(itemListExportControllerProvider);
    final initial = (from ? controller.whenFromDay : controller.whenToDay) ??
        DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (!mounted) return;
    if (from) {
      controller.setWhenFromDay(picked);
    } else {
      controller.setWhenToDay(picked);
    }
  }

  Future<void> _export() async {
    final path = await ref.read(itemListExportControllerProvider).exportCsv();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (path == null) return;
    messenger.showSnackBar(SnackBar(content: Text('Saved $path')));
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(itemListExportControllerProvider);
    final format = ref.watch(desktopPrefsProvider).dateTimeFormatOrLocal;

    return SelectableScope(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Item list'),
          actions: [
            SelectionContainer.disabled(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    key: const Key('item-list-export'),
                    onPressed: controller.hasEntries ? _export : null,
                    child: const Text('Export'),
                  ),
                  const AppNavTabButtons(),
                ],
              ),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final filterMax = math.min(280.0, constraints.maxHeight * 0.45);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: filterMax),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: _FilterPanel(
                      controller: controller,
                      onPickFrom: () => unawaited(_pickDay(from: true)),
                      onPickTo: () => unawaited(_pickDay(from: false)),
                      onPreview: () => unawaited(controller.preview()),
                    ),
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
                if (controller.loadingList || controller.loadingFacets)
                  const LinearProgressIndicator(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    '${controller.entries.length} '
                    '${controller.entries.length == 1 ? 'row' : 'rows'}',
                    key: const Key('item-list-count'),
                  ),
                ),
                Expanded(
                  child: SelectionContainer.disabled(
                    child: ReorderableListView.builder(
                      scrollDirection: Axis.horizontal,
                      buildDefaultDragHandles: true,
                      itemCount: controller.entries.length,
                      onReorderItem: controller.reorder,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      itemBuilder: (context, index) {
                        final entry = controller.entries[index];
                        return _FilmstripTile(
                          key: ValueKey(
                            entry.keyPeriodId ?? 'photo-${entry.itemId}',
                          ),
                          entry: entry,
                          format: format,
                          resolveThumb: () => controller.thumbFor(entry),
                          onRemove: () => controller.removeAt(index),
                        );
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

const double _kFilmstripStill = 180;

class _FilmstripTile extends StatefulWidget {
  const _FilmstripTile({
    super.key,
    required this.entry,
    required this.format,
    required this.resolveThumb,
    required this.onRemove,
  });

  final ItemListEntry entry;
  final DateTimeDisplayFormat format;
  final Future<LocalThumbResult> Function() resolveThumb;
  final VoidCallback onRemove;

  @override
  State<_FilmstripTile> createState() => _FilmstripTileState();
}

class _FilmstripTileState extends State<_FilmstripTile> {
  late final Future<LocalThumbResult> _thumb;

  @override
  void initState() {
    super.initState();
    _thumb = widget.resolveThumb();
  }

  String get _removeId =>
      widget.entry.keyPeriodId ?? widget.entry.itemId;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: _kFilmstripStill + 16,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _kFilmstripStill,
                height: _kFilmstripStill,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: FutureBuilder<LocalThumbResult>(
                        future: _thumb,
                        builder: (context, snapshot) {
                          final result = snapshot.data;
                          final path = result != null && result.hasImage
                              ? result.path
                              : null;
                          if (path != null) {
                            return Image.file(
                              File(path),
                              key: Key('item-list-still-$_removeId'),
                              fit: BoxFit.cover,
                              cacheWidth: (_kFilmstripStill * 2).round(),
                              cacheHeight: (_kFilmstripStill * 2).round(),
                              errorBuilder: (_, _, _) =>
                                  _placeholder(result?.status),
                            );
                          }
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const ColoredBox(
                              color: Colors.black12,
                              child: Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            );
                          }
                          return _placeholder(result?.status);
                        },
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IconButton(
                        key: Key('item-list-remove-$_removeId'),
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
      ),
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
        key: Key('item-list-still-placeholder-$_removeId'),
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

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.controller,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onPreview,
  });

  final ItemListExportController controller;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FacetChips(
          label: 'Who',
          values: controller.facets.who,
          selected: controller.selectedWho,
          onToggle: controller.toggleWho,
        ),
        _FacetChips(
          label: 'What',
          values: controller.facets.what,
          selected: controller.selectedWhat,
          onToggle: controller.toggleWhat,
        ),
        _FacetChips(
          label: 'Where',
          values: controller.facets.where,
          selected: controller.selectedWhere,
          onToggle: controller.toggleWhere,
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('When'),
            TextButton(
              key: const Key('item-list-when-from'),
              onPressed: onPickFrom,
              child: Text(
                controller.whenFromDay == null
                    ? 'From'
                    : _dayLabel(controller.whenFromDay!),
              ),
            ),
            TextButton(
              key: const Key('item-list-when-to'),
              onPressed: onPickTo,
              child: Text(
                controller.whenToDay == null
                    ? 'To'
                    : _dayLabel(controller.whenToDay!),
              ),
            ),
            if (controller.whenFromDay != null || controller.whenToDay != null)
              TextButton(
                onPressed: () {
                  controller.setWhenFromDay(null);
                  controller.setWhenToDay(null);
                },
                child: const Text('Clear dates'),
              ),
            FilledButton(
              key: const Key('item-list-preview'),
              onPressed: controller.loadingList ? null : onPreview,
              child: const Text('Preview'),
            ),
          ],
        ),
      ],
    );
  }

  String _dayLabel(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}

class _FacetChips extends StatelessWidget {
  const _FacetChips({
    required this.label,
    required this.values,
    required this.selected,
    required this.onToggle,
  });

  final String label;
  final List<String> values;
  final Set<String> selected;
  final void Function(String value) onToggle;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text('$label — none'),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(label),
          for (final value in values)
            FilterChip(
              key: Key('item-list-facet-$label-$value'),
              label: Text(value),
              selected: selected.contains(value),
              onSelected: (_) => onToggle(value),
            ),
        ],
      ),
    );
  }
}
