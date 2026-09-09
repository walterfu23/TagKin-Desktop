import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';

/// Local photo / video viewer — bytes from authorized local disk only (D8).
///
/// Never loads media from `tagkin-api` or a model host (R1/R5/R7).
///
/// For video, pass an owned [player] (and matching [videoController]) so the
/// key-period scrubber can seek the same instance. When [player] is null and
/// the item is a video, a banner is shown instead of opening native playback
/// (widget tests avoid media_kit init this way).
///
/// [whoOverlays] draws one labeled square per who-tag that has a [TagRegion]
/// (VLM face box), mapped through [BoxFit.contain]. [personNameByWhoTagId]
/// overrides the box label with an assigned person name when present.
class MediaViewer extends StatelessWidget {
  const MediaViewer({
    super.key,
    required this.itemType,
    required this.resolution,
    this.player,
    this.videoController,
    this.whoOverlays = const [],
    this.personNameByWhoTagId = const {},
  });

  final ItemType itemType;
  final LocalMediaResolution resolution;

  /// Shared video [Player] owned by the review section (seekable by scrubber).
  final Player? player;

  /// Matching [VideoController] for [player].
  final VideoController? videoController;

  /// Who tags with regions to draw as face overlays on photos.
  final List<Tag> whoOverlays;

  /// Assigned person name per who-tag id; the box falls back to [Tag.value].
  final Map<String, String> personNameByWhoTagId;

  @override
  Widget build(BuildContext context) {
    if (resolution.status == LocalMediaStatus.missing) {
      return const _MediaBanner(
        key: Key('media-missing'),
        message: 'Local media not found.',
      );
    }
    if (resolution.status == LocalMediaStatus.accessDenied) {
      return const _MediaBanner(
        key: Key('media-access-denied'),
        message:
            'macOS blocked access to this file. Use Add from folder and '
            're-select the folder (security-scoped bookmark), then reopen.',
      );
    }
    if (resolution.status == LocalMediaStatus.hashMismatch) {
      return const _MediaBanner(
        key: Key('media-hash-mismatch'),
        message: 'This file does not match the library record.',
      );
    }
    if (resolution.status == LocalMediaStatus.unsupported ||
        !resolution.isAvailable) {
      return const _MediaBanner(
        key: Key('media-unavailable'),
        message: 'Local media is not available for review.',
      );
    }

    if (itemType == ItemType.photo) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 320,
          width: double.infinity,
          child: _PhotoWithWhoOverlays(
            file: resolution.file!,
            whoOverlays: whoOverlays,
            personNameByWhoTagId: personNameByWhoTagId,
          ),
        ),
      );
    }

    final controller = videoController;
    if (player == null || controller == null) {
      return const _MediaBanner(
        key: Key('media-video-waiting'),
        message: 'Opening local video…',
      );
    }

    return VideoPlaybackPane(
      child: Video(controller: controller),
    );
  }
}

/// Local video viewport. Opted out of route [SelectionArea] so media_kit
/// play/pause receive taps.
class VideoPlaybackPane extends StatelessWidget {
  const VideoPlaybackPane({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SelectionContainer.disabled(
      key: const Key('media-video-selection-off'),
      child: SizedBox(
        key: const Key('media-video'),
        height: 240,
        child: child,
      ),
    );
  }
}

class _PhotoWithWhoOverlays extends StatefulWidget {
  const _PhotoWithWhoOverlays({
    required this.file,
    required this.whoOverlays,
    this.personNameByWhoTagId = const {},
  });

  final File file;
  final List<Tag> whoOverlays;
  final Map<String, String> personNameByWhoTagId;

  @override
  State<_PhotoWithWhoOverlays> createState() => _PhotoWithWhoOverlaysState();
}

class _PhotoWithWhoOverlaysState extends State<_PhotoWithWhoOverlays> {
  Size? _imageSize;

  @override
  void initState() {
    super.initState();
    unawaited(_resolveImageSize());
  }

  @override
  void didUpdateWidget(covariant _PhotoWithWhoOverlays oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _imageSize = null;
      unawaited(_resolveImageSize());
    }
  }

  Future<void> _resolveImageSize() async {
    try {
      final bytes = await widget.file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _imageSize = Size(image.width.toDouble(), image.height.toDouble());
      });
      image.dispose();
    } catch (_) {
      // Overlay alignment falls back when decode fails; Image.file shows error.
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final imageSize = _imageSize ?? viewport;
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              widget.file,
              key: const Key('media-photo'),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) => const _MediaBanner(
                key: Key('media-photo-error'),
                message: 'Could not decode local photo.',
              ),
            ),
            WhoFaceOverlayLayer(
              whoOverlays: widget.whoOverlays,
              personNameByWhoTagId: widget.personNameByWhoTagId,
              viewport: viewport,
              imageSize: imageSize,
            ),
          ],
        );
      },
    );
  }
}

/// Face squares for who-tags with [TagRegion], mapped through [BoxFit.contain].
@visibleForTesting
class WhoFaceOverlayLayer extends StatelessWidget {
  const WhoFaceOverlayLayer({
    super.key,
    required this.whoOverlays,
    required this.viewport,
    required this.imageSize,
    this.personNameByWhoTagId = const {},
  });

  final List<Tag> whoOverlays;
  final Size viewport;
  final Size imageSize;
  final Map<String, String> personNameByWhoTagId;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (final tag in whoOverlays)
          if (tag.region != null)
            _WhoFaceOverlay(
              key: Key('who-face-overlay-${tag.id}'),
              tag: tag,
              viewport: viewport,
              imageSize: imageSize,
              personName: personNameByWhoTagId[tag.id],
            ),
      ],
    );
  }
}

/// Maps a normalized [TagRegion] into a [BoxFit.contain] image rect.
@visibleForTesting
Rect containMappedRegion({
  required TagRegion region,
  required Size viewport,
  required Size imageSize,
}) {
  if (viewport.isEmpty || imageSize.isEmpty) return Rect.zero;
  final scale = math.min(
    viewport.width / imageSize.width,
    viewport.height / imageSize.height,
  );
  final drawnW = imageSize.width * scale;
  final drawnH = imageSize.height * scale;
  final left = (viewport.width - drawnW) / 2;
  final top = (viewport.height - drawnH) / 2;
  return Rect.fromLTRB(
    left + region.xMin * drawnW,
    top + region.yMin * drawnH,
    left + region.xMax * drawnW,
    top + region.yMax * drawnH,
  );
}

class _WhoFaceOverlay extends StatelessWidget {
  const _WhoFaceOverlay({
    super.key,
    required this.tag,
    required this.viewport,
    required this.imageSize,
    this.personName,
  });

  final Tag tag;
  final Size viewport;
  final Size imageSize;
  final String? personName;

  @override
  Widget build(BuildContext context) {
    final region = tag.region!;
    final rect = containMappedRegion(
      region: region,
      viewport: viewport,
      imageSize: imageSize,
    );
    if (rect.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final assigned = personName?.trim();
    final label =
        (assigned != null && assigned.isNotEmpty) ? assigned : tag.value;
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: scheme.primary, width: 2),
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: ColoredBox(
              color: scheme.primary.withValues(alpha: 0.85),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  label,
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 11,
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens a local video file into a new [Player]. Caller must [Player.dispose].
Future<({Player player, VideoController controller})> openLocalVideo(
  File file, {
  Player Function()? playerFactory,
}) async {
  final player = playerFactory?.call() ?? Player();
  final controller = VideoController(player);
  await player.open(Media(file.path));
  return (player: player, controller: controller);
}

class _MediaBanner extends StatelessWidget {
  const _MediaBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(message),
    );
  }
}
