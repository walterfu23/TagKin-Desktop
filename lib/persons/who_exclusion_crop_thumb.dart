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
/// expands to the parent (tray grid cell).
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
    final items = ref.read(itemsRepositoryProvider);
    final item = await items.getItem(widget.itemId);
    final media = await resolveLocalMedia(item);
    if (!media.isAvailable || media.file == null) return null;
    final fileBytes = await media.file!.readAsBytes();
    return cropWhoFaceJpeg(fileBytes, widget.region);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dim = widget.fill ? null : widget.size;
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        final spinnerSide =
            widget.fill ? 24.0 : widget.size * 0.35;
        final iconSide = widget.fill ? 28.0 : widget.size * 0.45;
        final child = switch (snapshot.connectionState) {
          ConnectionState.waiting => Center(
              child: SizedBox(
                width: spinnerSide,
                height: spinnerSide,
                child: const CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          _ when snapshot.data != null => Image.memory(
              snapshot.data!,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
            ),
          _ => Icon(
              Icons.person_off_outlined,
              size: iconSide,
              color: scheme.onSurfaceVariant,
            ),
        };
        return Tooltip(
          message: widget.tooltip,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: Container(
              key: Key('who-exclusion-thumb-${widget.itemId}'),
              width: dim,
              height: dim,
              color: scheme.surfaceContainerHighest,
              alignment: Alignment.center,
              child: widget.fill ? SizedBox.expand(child: child) : child,
            ),
          ),
        );
      },
    );
  }
}
