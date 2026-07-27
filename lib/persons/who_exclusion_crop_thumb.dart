import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
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
    this.size = 56,
    this.fill = false,
    this.borderRadius = 6,
    this.tooltip = 'Excluded face',
  });

  final String itemId;
  final TagRegion region;
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
        oldWidget.region.yMin != widget.region.yMin ||
        oldWidget.region.xMin != widget.region.xMin ||
        oldWidget.region.yMax != widget.region.yMax ||
        oldWidget.region.xMax != widget.region.xMax) {
      _future = _load();
    }
  }

  Future<Uint8List?> _load() async {
    try {
      final items = ref.read(itemsRepositoryProvider);
      final item = await items.getItem(widget.itemId);
      final media = await resolveLocalMedia(item);
      if (!canCropLocalMediaForDisplay(media)) {
        debugPrint(
          'WhoExclusionCropThumb ${widget.itemId}: media '
          '${media.status.name} path=${media.path}',
        );
        return null;
      }
      final fileBytes = await media.file!.readAsBytes();
      final crop = await cropWhoFaceJpegAsync(fileBytes, widget.region);
      if (crop == null) {
        debugPrint(
          'WhoExclusionCropThumb ${widget.itemId}: crop decode failed '
          '(${fileBytes.length} bytes)',
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
