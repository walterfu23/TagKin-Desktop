import 'dart:io';

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
class MediaViewer extends StatelessWidget {
  const MediaViewer({
    super.key,
    required this.itemType,
    required this.resolution,
    this.player,
    this.videoController,
  });

  final ItemType itemType;
  final LocalMediaResolution resolution;

  /// Shared video [Player] owned by the review section (seekable by scrubber).
  final Player? player;

  /// Matching [VideoController] for [player].
  final VideoController? videoController;

  @override
  Widget build(BuildContext context) {
    if (resolution.status == LocalMediaStatus.missing) {
      return const _MediaBanner(
        key: Key('media-missing'),
        message: 'Local media not found at sourceRef.',
      );
    }
    if (resolution.status == LocalMediaStatus.hashMismatch) {
      return const _MediaBanner(
        key: Key('media-hash-mismatch'),
        message: 'Local file contentHash does not match the item record.',
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
        child: Image.file(
          resolution.file!,
          key: const Key('media-photo'),
          fit: BoxFit.contain,
          height: 320,
          errorBuilder: (context, error, stack) => const _MediaBanner(
            key: Key('media-photo-error'),
            message: 'Could not decode local photo.',
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

    return SizedBox(
      key: const Key('media-video'),
      height: 240,
      child: Video(controller: controller),
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
