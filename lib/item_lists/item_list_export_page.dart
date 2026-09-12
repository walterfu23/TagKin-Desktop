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
import 'package:tagkin_desktop/prepass/hide_blurry_switch.dart';
import 'package:tagkin_desktop/prepass/sharpness_score_chip.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';
import 'package:tagkin_desktop/review/media_viewer.dart';
import 'package:tagkin_desktop/shell/app_nav_tab_buttons.dart';
import 'package:tagkin_desktop/ui/format_local_datetime.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

/// Filter photos and video key periods, reorder, and export a JSON manifest.
class ItemListExportPage extends ConsumerStatefulWidget {
  const ItemListExportPage({super.key});

  @override
  ConsumerState<ItemListExportPage> createState() => _ItemListExportPageState();
}

class _ItemListExportPageState extends ConsumerState<ItemListExportPage> {
  final _previewScroll = ScrollController();
  final _description = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(itemListExportControllerProvider).load());
    });
  }

  @override
  void dispose() {
    _previewScroll.dispose();
    _description.dispose();
    super.dispose();
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
    final prefs = ref.read(desktopPrefsProvider);
    final path = await ref.read(itemListExportControllerProvider).exportJson(
          description: _description.text,
          hideBlurry: prefs.hideBlurryPhotos,
          threshold: prefs.itemListBlurrySharpnessThreshold.toDouble(),
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
    final hideBlurry = prefs.hideBlurryPhotos;
    final blurBar = prefs.itemListBlurrySharpnessThreshold.toDouble();
    final visible = controller.visibleEntries(
      hideBlurry: hideBlurry,
      threshold: blurBar,
    );
    // [visible] is an identity-preserving subsequence of [controller.entries]
    // (Hide blurry only ever drops entries, never copies them), so a single
    // walk maps real indices -> hidden without relying on entry equality.
    final hiddenIndices = <int>{};
    if (hideBlurry) {
      var vi = 0;
      for (var i = 0; i < controller.entries.length; i++) {
        if (vi < visible.length && identical(controller.entries[i], visible[vi])) {
          vi++;
        } else {
          hiddenIndices.add(i);
        }
      }
    }

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
                      description: _description,
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
                    '${visible.length} '
                    '${visible.length == 1 ? 'item' : 'items'}',
                    key: const Key('item-list-count'),
                  ),
                ),
                Expanded(
                  child: SelectionContainer.disabled(
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
                              if (!hiddenIndices.contains(i))
                                _FilmstripTile(
                                  key: ValueKey(
                                    controller.entries[i].keyPeriodId ??
                                        'photo-${controller.entries[i].itemId}',
                                  ),
                                  index: i,
                                  entry: controller.entries[i],
                                  item: controller.itemsById[
                                      controller.entries[i].itemId],
                                  showSharpnessScore: prefs.showSharpnessScores,
                                  format: format,
                                  timestampMs: controller
                                      .timestampMsFor(controller.entries[i]),
                                  faceRegions: controller
                                      .faceRegionsFor(controller.entries[i]),
                                  ensureKnowledge: () => controller
                                      .knowledgeFor(controller.entries[i].itemId),
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
    required this.index,
    required this.entry,
    this.item,
    required this.showSharpnessScore,
    required this.format,
    required this.timestampMs,
    required this.faceRegions,
    required this.ensureKnowledge,
    required this.resolveThumb,
    required this.onRemove,
    required this.onReorder,
  });

  final int index;
  final ItemListEntry entry;
  final Item? item;
  final bool showSharpnessScore;
  final DateTimeDisplayFormat format;
  final int timestampMs;
  final List<({String id, TagRegion region})> faceRegions;
  final Future<ItemKnowledge?> Function() ensureKnowledge;
  final Future<LocalThumbResult> Function() resolveThumb;
  final VoidCallback onRemove;
  final void Function(int from, int to) onReorder;

  @override
  State<_FilmstripTile> createState() => _FilmstripTileState();
}

class _FilmstripTileState extends State<_FilmstripTile> {
  late Future<LocalThumbResult> _thumb;
  Size? _imageSize;

  @override
  void initState() {
    super.initState();
    _thumb = widget.resolveThumb();
    unawaited(widget.ensureKnowledge());
  }

  @override
  void didUpdateWidget(_FilmstripTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timestampMs != widget.timestampMs ||
        oldWidget.entry.itemId != widget.entry.itemId ||
        oldWidget.entry.keyPeriodId != widget.entry.keyPeriodId) {
      _thumb = widget.resolveThumb();
    }
  }

  String get _id => widget.entry.keyPeriodId ?? widget.entry.itemId;

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
                            child: Text(itemListEntryKindLabel(widget.entry.kind)),
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
                        child: _still(),
                      ),
                      if (widget.faceRegions.isNotEmpty)
                        _CoverFaceOverlay(
                          regions: widget.faceRegions,
                          imageSize: _imageSize,
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
            frameBuilder: (context, child, frame, sync) {
              if (frame != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _rememberImageSize(path);
                });
              }
              return child;
            },
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

  void _rememberImageSize(String path) {
    final stream = FileImage(File(path)).resolve(const ImageConfiguration());
    stream.addListener(
      ImageStreamListener((info, _) {
        final next = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
        if (!mounted || _imageSize == next) return;
        setState(() => _imageSize = next);
      }),
    );
  }
}

class _CoverFaceOverlay extends StatelessWidget {
  const _CoverFaceOverlay({
    required this.regions,
    this.imageSize,
  });

  final List<({String id, TagRegion region})> regions;
  final Size? imageSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final src = imageSize ?? viewport;
        final scheme = Theme.of(context).colorScheme;
        return IgnorePointer(
          child: Stack(
            children: [
              for (final face in regions)
                Builder(
                  builder: (context) {
                    final rect = coverMappedRegion(
                      region: face.region,
                      viewport: viewport,
                      imageSize: src,
                    );
                    if (rect.isEmpty) return const SizedBox.shrink();
                    return Positioned(
                      left: rect.left,
                      top: rect.top,
                      width: rect.width,
                      height: rect.height,
                      child: DecoratedBox(
                        key: Key('item-list-face-${face.id}'),
                        decoration: BoxDecoration(
                          border: Border.all(color: scheme.primary, width: 2),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
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
    required this.description,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onPreview,
  });

  final ItemListExportController controller;
  final TextEditingController description;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('item-list-description'),
          controller: description,
          decoration: const InputDecoration(
            labelText: 'Description',
            hintText: 'Optional note saved with the export',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
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
            const HideBlurrySwitch(),
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
