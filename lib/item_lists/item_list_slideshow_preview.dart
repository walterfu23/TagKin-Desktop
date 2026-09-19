import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:tagkin_desktop/item_lists/item_list_nle.dart';

/// Steps through [timeline] stills while playing [audioPath].
class ItemListSlideshowPreview extends StatefulWidget {
  const ItemListSlideshowPreview({
    super.key,
    required this.timeline,
    required this.audioPath,
    this.playerFactory,
  });

  final ItemListNleTimeline timeline;
  final String audioPath;
  final Player Function()? playerFactory;

  @override
  State<ItemListSlideshowPreview> createState() =>
      _ItemListSlideshowPreviewState();
}

class _ItemListSlideshowPreviewState extends State<ItemListSlideshowPreview> {
  Player? _player;
  Timer? _ticker;
  int _clipIndex = 0;
  bool _playing = false;

  @override
  void didUpdateWidget(ItemListSlideshowPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioPath == widget.audioPath) return;
    _ticker?.cancel();
    _player?.dispose();
    _player = null;
    _clipIndex = 0;
    _playing = false;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _player?.dispose();
    super.dispose();
  }

  ItemListNleClip? get _clip {
    if (widget.timeline.clips.isEmpty) return null;
    final i = _clipIndex.clamp(0, widget.timeline.clips.length - 1);
    return widget.timeline.clips[i];
  }

  Future<void> _toggle() async {
    if (_playing) {
      _ticker?.cancel();
      await _player?.pause();
      setState(() => _playing = false);
      return;
    }
    _player ??= (widget.playerFactory ?? Player.new)();
    await _player!.open(Media('file://${widget.audioPath}'));
    await _player!.play();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _syncClip();
    });
    setState(() => _playing = true);
  }

  void _syncClip() {
    final pos = _player?.state.position ?? Duration.zero;
    final frame =
        (pos.inMilliseconds * kItemListNleTimebase / 1000).floor();
    var idx = 0;
    for (var i = 0; i < widget.timeline.clips.length; i++) {
      final c = widget.timeline.clips[i];
      if (frame >= c.timelineStart && frame < c.timelineEnd) {
        idx = i;
        break;
      }
      if (frame >= c.timelineEnd) idx = i;
    }
    if (idx != _clipIndex && mounted) {
      setState(() => _clipIndex = idx);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clip = _clip;
    final path = clip?.localPath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 180,
          child: clip == null
              ? const Center(child: Text('Nothing to preview'))
              : path == null
                  ? const Center(child: Text('Missing local file'))
                  : clip.isStill
                      ? Image.file(
                          File(path),
                          fit: BoxFit.contain,
                          errorBuilder: (_, error, stackTrace) =>
                              const Center(child: Text('Could not load still')),
                        )
                      : Center(
                          child: Text(
                            'Key period ${clip.entry.startMs ?? 0}–'
                            '${clip.entry.endMs ?? 0} ms',
                          ),
                        ),
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          key: const Key('item-list-music-preview-play'),
          onPressed: clip == null ? null : _toggle,
          child: Text(_playing ? 'Pause preview' : 'Play preview'),
        ),
      ],
    );
  }
}
