import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:tagkin_desktop/item_lists/item_list_mp4_filter.dart';
import 'package:tagkin_desktop/item_lists/item_list_nle.dart';

/// Playback used by the music preview. Tests supply fakes.
abstract class ItemListPreviewPlayer {
  Duration get position;

  /// Video surface, or null for an audio-only player.
  Widget? get video;

  Future<void> openFile(String path);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration to);
  Future<void> setVolume(double volume);
  Future<void> dispose();
}

/// Soundtrack volume while [keyPeriod] is on screen. 100 is full.
double itemListPreviewSoundtrackVolume({
  required bool keyPeriod,
  required double soundtrackDuck,
}) {
  if (!keyPeriod) return 100;
  return soundtrackDuck.clamp(0.0, 1.0) * 100;
}

/// True once [frame] has reached the white ending.
bool itemListPreviewInEndFade({
  required int frame,
  required ItemListNleEndFade? endFade,
}) {
  if (endFade == null) return false;
  return frame >= endFade.startFrame;
}

/// White overlay opacity during the ending. 0 before it, 1 at the end.
double itemListPreviewEndFadeOpacity({
  required int frame,
  required ItemListNleEndFade? endFade,
}) {
  if (!itemListPreviewInEndFade(frame: frame, endFade: endFade)) return 0;
  final span = endFade!.durationFrames < 1 ? 1 : endFade.durationFrames;
  final t = (frame - endFade.startFrame) / span;
  if (t > 1) return 1;
  return t;
}

/// Where to seek the source file for [clip] at [soundtrackPosition].
Duration itemListPreviewSeek({
  required ItemListNleClip clip,
  required Duration soundtrackPosition,
}) {
  final timelineStartMs = (clip.timelineStart * 1000 / kItemListNleTimebase)
      .round();
  final into = soundtrackPosition.inMilliseconds - timelineStartMs;
  final elapsed = into < 0 ? 0 : into;
  var ms = (clip.entry.startMs ?? 0) + elapsed;
  final end = clip.entry.endMs;
  if (end != null && ms > end) ms = end;
  if (ms < 0) ms = 0;
  return Duration(milliseconds: ms);
}

typedef ItemListPreviewPlayerFactory = ItemListPreviewPlayer Function();

ItemListPreviewPlayer _mediaKitAudioPlayer() =>
    _MediaKitPreviewPlayer(Player(), video: false);

ItemListPreviewPlayer _mediaKitVideoPlayer() =>
    _MediaKitPreviewPlayer(Player(), video: true);

class _MediaKitPreviewPlayer implements ItemListPreviewPlayer {
  _MediaKitPreviewPlayer(this._player, {required bool video}) {
    if (video) _controller = VideoController(_player);
  }

  final Player _player;
  VideoController? _controller;

  @override
  Duration get position => _player.state.position;

  @override
  Widget? get video {
    final controller = _controller;
    if (controller == null) return null;
    return Video(
      controller: controller,
      key: const Key('item-list-preview-video'),
      fit: BoxFit.contain,
      controls: NoVideoControls,
      wakelock: false,
    );
  }

  @override
  Future<void> openFile(String path) => _player.open(Media(path), play: false);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration to) async {
    if (_player.state.duration <= Duration.zero) {
      final done = Completer<void>();
      final sub = _player.stream.duration.listen((duration) {
        if (duration > Duration.zero && !done.isCompleted) done.complete();
      });
      try {
        if (_player.state.duration <= Duration.zero) {
          await done.future.timeout(const Duration(seconds: 2));
        }
      } on TimeoutException {
        // Seek anyway. A slow file still shows the first frame it has.
      } finally {
        await sub.cancel();
      }
    }
    final native = _player.platform;
    if (native is NativePlayer && to > Duration.zero) {
      final seconds = to.inMicroseconds / Duration.microsecondsPerSecond;
      await native.command(['seek', '$seconds', 'absolute+exact']);
      return;
    }
    await _player.seek(to);
  }

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> dispose() => _player.dispose();
}

/// Steps through [timeline] while playing [audioPath].
///
/// Photos are stills. A key period plays that clip, with its own audio at
/// full level and the soundtrack ducked.
class ItemListSlideshowPreview extends StatefulWidget {
  const ItemListSlideshowPreview({
    super.key,
    required this.timeline,
    required this.audioPath,
    this.soundtrackDuck = kItemListMp4SoundtrackDuckDefault,
    this.playerFactory,
    this.videoPlayerFactory,
  });

  final ItemListNleTimeline timeline;
  final String audioPath;
  final double soundtrackDuck;
  final ItemListPreviewPlayerFactory? playerFactory;
  final ItemListPreviewPlayerFactory? videoPlayerFactory;

  @override
  State<ItemListSlideshowPreview> createState() =>
      _ItemListSlideshowPreviewState();
}

class _ItemListSlideshowPreviewState extends State<ItemListSlideshowPreview> {
  ItemListPreviewPlayer? _audio;
  ItemListPreviewPlayer? _video;
  Timer? _ticker;
  int _clipIndex = 0;
  int _followGen = 0;
  bool _playing = false;
  bool _showingVideo = false;
  bool _inEndFade = false;
  double _endFadeOpacity = 0;
  String? _videoPath;
  String? _videoError;

  @override
  void didUpdateWidget(ItemListSlideshowPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioPath == widget.audioPath &&
        _timelineSig(oldWidget.timeline) == _timelineSig(widget.timeline)) {
      return;
    }
    _resetPlayback();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _followGen += 1;
    unawaited(_audio?.dispose());
    unawaited(_video?.dispose());
    super.dispose();
  }

  String _timelineSig(ItemListNleTimeline timeline) {
    return [
      for (final clip in timeline.clips)
        '${clip.entry.itemId}:${clip.entry.keyPeriodId}:${clip.timelineStart}',
    ].join('|');
  }

  ItemListNleClip? get _clip {
    if (widget.timeline.clips.isEmpty) return null;
    final i = _clipIndex.clamp(0, widget.timeline.clips.length - 1);
    return widget.timeline.clips[i];
  }

  void _resetPlayback() {
    _ticker?.cancel();
    _ticker = null;
    _followGen += 1;
    final audio = _audio;
    final video = _video;
    _audio = null;
    _video = null;
    _videoPath = null;
    _clipIndex = 0;
    _playing = false;
    _showingVideo = false;
    _inEndFade = false;
    _endFadeOpacity = 0;
    _videoError = null;
    unawaited(audio?.dispose());
    unawaited(video?.dispose());
  }

  Future<void> _toggle() async {
    if (_playing) {
      _ticker?.cancel();
      _ticker = null;
      _followGen += 1;
      await _audio?.pause();
      await _video?.pause();
      if (!mounted) return;
      setState(() => _playing = false);
      return;
    }
    _audio ??= (widget.playerFactory ?? _mediaKitAudioPlayer)();
    _clipIndex = 0;
    await _audio!.openFile(widget.audioPath);
    await _audio!.play();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _syncClip();
    });
    if (!mounted) return;
    setState(() => _playing = true);
    await _followClip(_clipIndex);
  }

  void _syncClip() {
    final pos = _audio?.position ?? Duration.zero;
    final frame = (pos.inMilliseconds * kItemListNleTimebase / 1000).floor();
    final opacity = itemListPreviewEndFadeOpacity(
      frame: frame,
      endFade: widget.timeline.endFade,
    );
    final inTail = itemListPreviewInEndFade(
      frame: frame,
      endFade: widget.timeline.endFade,
    );
    if (inTail && !_inEndFade) {
      _inEndFade = true;
      unawaited(_video?.pause());
    } else if (!inTail) {
      _inEndFade = false;
    }
    var idx = 0;
    for (var i = 0; i < widget.timeline.clips.length; i++) {
      final clip = widget.timeline.clips[i];
      if (frame >= clip.timelineStart && frame < clip.timelineEnd) {
        idx = i;
        break;
      }
      if (frame >= clip.timelineEnd) idx = i;
    }
    final opacityChanged = (opacity - _endFadeOpacity).abs() > 0.02;
    final indexChanged = idx != _clipIndex;
    if (!indexChanged && !opacityChanged) return;
    _clipIndex = idx;
    _endFadeOpacity = opacity;
    if (mounted) setState(() {});
    if (indexChanged && !inTail) unawaited(_followClip(idx));
  }

  Future<void> _followClip(int index) async {
    final gen = ++_followGen;
    final clips = widget.timeline.clips;
    final clip = index < 0 || index >= clips.length ? null : clips[index];
    final path = clip?.localPath;
    if (clip == null || clip.isStill || path == null || path.isEmpty) {
      await _audio?.setVolume(
        itemListPreviewSoundtrackVolume(
          keyPeriod: false,
          soundtrackDuck: widget.soundtrackDuck,
        ),
      );
      if (gen != _followGen) return;
      await _video?.pause();
      if (gen != _followGen || !mounted) return;
      if (_showingVideo) setState(() => _showingVideo = false);
      return;
    }
    await _audio?.setVolume(
      itemListPreviewSoundtrackVolume(
        keyPeriod: true,
        soundtrackDuck: widget.soundtrackDuck,
      ),
    );
    if (gen != _followGen) return;
    try {
      _video ??= (widget.videoPlayerFactory ?? _mediaKitVideoPlayer)();
      if (_videoPath != path) {
        await _video!.openFile(path);
        if (gen != _followGen) return;
        _videoPath = path;
      }
      await _video!.seek(
        itemListPreviewSeek(
          clip: clip,
          soundtrackPosition: _audio?.position ?? Duration.zero,
        ),
      );
      if (gen != _followGen || !_playing) return;
      await _video!.play();
      if (gen != _followGen || !mounted) return;
      setState(() {
        _showingVideo = true;
        _videoError = null;
      });
    } catch (_) {
      if (gen != _followGen || !mounted) return;
      setState(() {
        _showingVideo = false;
        _videoError = 'Could not play key period';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final clip = _clip;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 180, child: _picture(clip)),
        const SizedBox(height: 8),
        FilledButton.tonal(
          key: const Key('item-list-music-preview-play'),
          onPressed: clip == null ? null : _toggle,
          child: Text(_playing ? 'Pause preview' : 'Play preview'),
        ),
      ],
    );
  }

  Widget _picture(ItemListNleClip? clip) {
    final picture = _pictureBody(clip);
    if (_endFadeOpacity <= 0) return picture;
    return Stack(
      fit: StackFit.expand,
      children: [
        picture,
        ColoredBox(
          key: const Key('item-list-preview-end-fade'),
          color: Color.fromRGBO(255, 255, 255, _endFadeOpacity),
        ),
      ],
    );
  }

  Widget _pictureBody(ItemListNleClip? clip) {
    if (clip == null) return const Center(child: Text('Nothing to preview'));
    final path = clip.localPath;
    if (path == null || path.isEmpty) {
      return const Center(child: Text('Missing local file'));
    }
    if (!clip.isStill) {
      if (_videoError != null) return Center(child: Text(_videoError!));
      final view = _showingVideo ? _video?.video : null;
      if (view != null) {
        return SelectionContainer.disabled(child: view);
      }
      if (_playing) {
        return const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      }
      return Center(
        child: Text(
          'Key period ${clip.entry.startMs ?? 0}–${clip.entry.endMs ?? 0} ms',
        ),
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.contain,
      errorBuilder: (_, error, stackTrace) =>
          const Center(child: Text('Could not load still')),
    );
  }
}
