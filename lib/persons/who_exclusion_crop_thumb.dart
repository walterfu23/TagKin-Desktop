import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/persons/face_crop_cache.dart';
import 'package:tagkin_desktop/persons/who_face_linker.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';

/// Face crop thumb from a known [TagRegion] (excluded crops, or region on wire).
///
/// Crops locally from [region] (R1: never uploads bytes). When [fill] is true,
/// expands to the parent (tray grid cell) via [LayoutBuilder].
class WhoExclusionCropThumb extends ConsumerStatefulWidget {
  const WhoExclusionCropThumb({
    super.key,
    required this.itemId,
    required this.region,
    this.item,
    this.size = 56,
    this.fill = false,
    this.borderRadius = 6,
    this.tooltip = 'Excluded face',
  });

  final String itemId;
  final TagRegion region;

  /// When the caller already has the [Item] (e.g. from a batch `listItems()`
  /// just before rendering the tray), pass it to skip a per-thumb `getItem`
  /// network round trip — the dominant Faces render-latency cost on large
  /// folders. Falls back to fetching by [itemId] when omitted.
  final Item? item;

  final double size;
  final bool fill;
  final double borderRadius;
  final String tooltip;

  @override
  ConsumerState<WhoExclusionCropThumb> createState() =>
      _WhoExclusionCropThumbState();
}

class _WhoExclusionCropThumbState extends ConsumerState<WhoExclusionCropThumb> {
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(WhoExclusionCropThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemId != widget.itemId ||
        oldWidget.item?.contentHash != widget.item?.contentHash ||
        oldWidget.region.yMin != widget.region.yMin ||
        oldWidget.region.xMin != widget.region.xMin ||
        oldWidget.region.yMax != widget.region.yMax ||
        oldWidget.region.xMax != widget.region.xMax) {
      _future = _load();
    }
  }

  Future<Uint8List?> _load() async {
    try {
      final known = widget.item;
      final cached = FaceCropCache.instance.peek(
        itemId: widget.itemId,
        contentHash: known?.contentHash,
        region: widget.region,
      );
      if (cached != null) return cached;

      final item =
          known ??
          await ref.read(itemsRepositoryProvider).getItem(widget.itemId);
      final crop = await FaceCropCache.instance.getOrCropFace(
        itemId: widget.itemId,
        contentHash: item.contentHash,
        region: widget.region,
        loadFileBytes: () async {
          final media = await resolveLocalMedia(item, verifyHash: false);
          if (!canCropLocalMediaForDisplay(media)) {
            debugPrint(
              'WhoExclusionCropThumb ${widget.itemId}: media '
              '${media.status.name} path=${media.path}',
            );
            throw StateError('media unavailable: ${media.status.name}');
          }
          return media.file!.readAsBytes();
        },
      );
      if (crop == null) {
        debugPrint(
          'WhoExclusionCropThumb ${widget.itemId}: crop decode failed',
        );
      }
      return crop;
    } catch (e, st) {
      debugPrint('WhoExclusionCropThumb ${widget.itemId}: $e\n$st');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
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
            _ when snapshot.data != null => SelectionContainer.disabled(
              child: Image.memory(
                snapshot.data!,
                fit: BoxFit.cover,
                width: side,
                height: side,
                gaplessPlayback: true,
              ),
            ),
            _ => Icon(
              Icons.person_off_outlined,
              size: iconSide.clamp(14, 28),
              color: scheme.onSurfaceVariant,
            ),
          };
          return Tooltip(
            message: widget.tooltip,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              child: Container(
                key: Key('who-exclusion-thumb-${widget.itemId}'),
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
