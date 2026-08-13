import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/persons/face_crop_cache.dart';
import 'package:tagkin_desktop/persons/who_face_linker.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';

/// Who-face crop thumbnail for a person appearance (D9).
///
/// Joins [itemId] + [tagId] → who [Tag.region] → local JPEG crop.
/// Never uploads bytes (R1). Falls back to a placeholder when media / region
/// is missing.
class WhoFaceCropThumb extends ConsumerStatefulWidget {
  const WhoFaceCropThumb({
    super.key,
    required this.itemId,
    required this.tagId,
    this.knowledge,
    this.region,
    this.item,
    this.size = 56,
    this.fill = false,
    this.borderRadius = 6,
  });

  final String itemId;
  final String tagId;

  /// When set (e.g. item review), skip an extra knowledge fetch.
  final ItemKnowledge? knowledge;

  /// When set (e.g. appearance.region from API), crop without a knowledge fetch.
  final TagRegion? region;

  /// When the caller already has the [Item] (e.g. from a batch `listItems()`
  /// just before rendering the tray), pass it to skip a per-thumb `getItem`
  /// network round trip — the dominant Faces render-latency cost on large
  /// folders. Falls back to fetching by [itemId] when omitted.
  final Item? item;

  final double size;
  final bool fill;
  final double borderRadius;

  @override
  ConsumerState<WhoFaceCropThumb> createState() => _WhoFaceCropThumbState();
}

class _WhoFaceCropThumbState extends ConsumerState<WhoFaceCropThumb> {
  late Future<_CropLoad> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(WhoFaceCropThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemId != widget.itemId ||
        oldWidget.tagId != widget.tagId ||
        oldWidget.knowledge != widget.knowledge ||
        oldWidget.item?.contentHash != widget.item?.contentHash ||
        !_sameRegion(oldWidget.region, widget.region)) {
      _future = _load();
    }
  }

  Future<_CropLoad> _load() async {
    try {
      final items = ref.read(itemsRepositoryProvider);
      TagRegion? region = widget.region;
      String? whoLabel;
      if (region == null) {
        final knowledge =
            widget.knowledge ?? await items.getKnowledge(widget.itemId);
        Tag? tag;
        for (final t in knowledge.tags) {
          if (t.id == widget.tagId) {
            tag = t;
            break;
          }
        }
        if (tag == null || tag.region == null) {
          return const _CropLoad(bytes: null, whoLabel: null);
        }
        region = tag.region;
        whoLabel = tag.value.trim().isEmpty ? null : tag.value.trim();
      }
      final resolvedRegion = region!;

      final cachedItem = widget.item;
      final cached = FaceCropCache.instance.peek(
        itemId: widget.itemId,
        contentHash: cachedItem?.contentHash,
        region: resolvedRegion,
      );
      if (cached != null) return _CropLoad(bytes: cached, whoLabel: whoLabel);

      final item = cachedItem ?? await items.getItem(widget.itemId);
      final crop = await FaceCropCache.instance.getOrCropFace(
        itemId: widget.itemId,
        contentHash: item.contentHash,
        region: resolvedRegion,
        loadFileBytes: () async {
          final media = await resolveLocalMedia(item, verifyHash: false);
          if (!canCropLocalMediaForDisplay(media)) {
            debugPrint(
              'WhoFaceCropThumb ${widget.itemId}/${widget.tagId}: media '
              '${media.status.name} path=${media.path}',
            );
            throw StateError('media unavailable: ${media.status.name}');
          }
          return media.file!.readAsBytes();
        },
      );
      if (crop == null) {
        debugPrint(
          'WhoFaceCropThumb ${widget.itemId}/${widget.tagId}: crop decode '
          'failed',
        );
      }
      return _CropLoad(bytes: crop, whoLabel: whoLabel);
    } catch (e, st) {
      debugPrint('WhoFaceCropThumb ${widget.itemId}/${widget.tagId}: $e\n$st');
      return const _CropLoad(bytes: null, whoLabel: null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<_CropLoad>(
      future: _future,
      builder: (context, snapshot) {
        final load = snapshot.data;
        Widget body(double side) {
          final spinnerSide = side * 0.35;
          final iconSide = side * 0.45;
          final child = switch (snapshot.connectionState) {
            ConnectionState.waiting => Center(
              child: SizedBox(
                width: spinnerSide.clamp(12, 24),
                height: spinnerSide.clamp(12, 24),
                child: const CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            _ when load?.bytes != null => SelectionContainer.disabled(
              child: Image.memory(
                load!.bytes!,
                fit: BoxFit.cover,
                width: side,
                height: side,
                cacheWidth: (side * MediaQuery.devicePixelRatioOf(context))
                    .round()
                    .clamp(32, 512),
                cacheHeight: (side * MediaQuery.devicePixelRatioOf(context))
                    .round()
                    .clamp(32, 512),
                gaplessPlayback: true,
              ),
            ),
            _ => Icon(
              Icons.person_outline,
              size: iconSide.clamp(14, 28),
              color: scheme.onSurfaceVariant,
            ),
          };
          return Tooltip(
            message: load?.whoLabel ?? 'Who face',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              child: Container(
                key: Key('who-face-thumb-${widget.tagId}'),
                width: side,
                height: side,
                color: scheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: child,
              ),
            ),
          );
        }

        if (!widget.fill) return body(widget.size);
        return SizedBox.expand(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final side = constraints.biggest.shortestSide;
              if (!side.isFinite || side <= 0) {
                return body(widget.size);
              }
              return body(side);
            },
          ),
        );
      },
    );
  }
}

/// Leading avatar for a person list row: first appearance with item+tag.
class PersonListFaceThumb extends ConsumerStatefulWidget {
  const PersonListFaceThumb({
    super.key,
    required this.personId,
    this.size = 48,
  });

  final String personId;
  final double size;

  @override
  ConsumerState<PersonListFaceThumb> createState() =>
      _PersonListFaceThumbState();
}

class _PersonListFaceThumbState extends ConsumerState<PersonListFaceThumb> {
  late Future<PersonAppearance?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(PersonListFaceThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.personId != widget.personId) {
      _future = _load();
    }
  }

  Future<PersonAppearance?> _load() async {
    final detail = await ref
        .read(personsRepositoryProvider)
        .getPerson(widget.personId);
    for (final a in detail.appearances) {
      if (a.itemId != null && a.tagId != null) return a;
    }
    return detail.appearances.isEmpty ? null : detail.appearances.first;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PersonAppearance?>(
      future: _future,
      builder: (context, snapshot) {
        final a = snapshot.data;
        if (a?.itemId != null && a?.tagId != null) {
          return WhoFaceCropThumb(
            key: Key('person-list-thumb-${widget.personId}'),
            itemId: a!.itemId!,
            tagId: a.tagId!,
            region: a.region,
            size: widget.size,
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Container(
            key: Key('person-list-thumb-placeholder-${widget.personId}'),
            width: widget.size,
            height: widget.size,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.person_outline,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        );
      },
    );
  }
}

class _CropLoad {
  const _CropLoad({required this.bytes, required this.whoLabel});

  final Uint8List? bytes;
  final String? whoLabel;
}

bool _sameRegion(TagRegion? a, TagRegion? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == b;
  return a.yMin == b.yMin &&
      a.xMin == b.xMin &&
      a.yMax == b.yMax &&
      a.xMax == b.xMax;
}
