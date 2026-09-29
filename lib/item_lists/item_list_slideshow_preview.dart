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

  /// Open media length. [Duration.zero] means it is not known yet.
  Duration get duration;

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

/// Elapsed clock for the preview bar (`m:ss`, or `h:mm:ss` past an hour).
String itemListPreviewClock(Duration position) {
  var seconds = position.inSeconds;
  if (seconds < 0) seconds = 0;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final secs = seconds % 60;
  final ss = secs.toString().padLeft(2, '0');
  if (hours > 0) {
    final mm = minutes.toString().padLeft(2, '0');
    return '$hours:$mm:$ss';
  }
  return '$minutes:$ss';
}

/// Clip under [position] on the soundtrack timeline.
int itemListPreviewClipIndex({
  required List<ItemListNleClip> clips,
  required Duration position,
}) {
  if (clips.isEmpty) return 0;
  final frame = (position.inMilliseconds * kItemListNleTimebase / 1000).floor();
  var idx = 0;
  for (var i = 0; i < clips.length; i++) {
    final clip = clips[i];
    if (frame >= clip.timelineStart && frame < clip.timelineEnd) return i;
    if (frame >= clip.timelineEnd) idx = i;
  }
  return idx;
}

/// Soundtrack seek. A known file shorter than the timeline stays at its end.
Duration itemListPreviewAudioSeek({
  required Duration position,
  required Duration audioDuration,
}) {
  var ms = position.inMilliseconds;
  if (ms < 0) ms = 0;
  final audioMs = audioDuration.inMilliseconds;
  if (audioMs > 0 && ms > audioMs) ms = audioMs;
  return Duration(milliseconds: ms);
}

Duration _clampTimelinePosition(
  ItemListNleTimeline timeline,
  Duration position,
) {
  final totalMs = itemListNleTimelineDurationMs(timeline);
  var ms = position.inMilliseconds;
  if (ms < 0) ms = 0;
  if (ms > totalMs) ms = totalMs;
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
  Duration get duration => _player.state.duration;

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
/// full level and the soundtrack ducked. The bar seeks the soundtrack, and
/// Play preview continues from that point.
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
  Timer? _scrubTimer;
  int _clipIndex = 0;
  int _followGen = 0;
  bool _playing = false;
  bool _audioOpen = false;
  bool _scrubbing = false;
  bool _resumeAfterScrub = false;
  bool _showingVideo = false;
  bool _inEndFade = false;
  double _endFadeOpacity = 0;
  Duration _position = Duration.zero;
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
    _scrubTimer?.cancel();
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
    _scrubTimer?.cancel();
    _scrubTimer = null;
    _followGen += 1;
    final audio = _audio;
    final video = _video;
    _audio = null;
    _video = null;
    _videoPath = null;
    _audioOpen = false;
    _clipIndex = 0;
    _playing = false;
    _scrubbing = false;
    _resumeAfterScrub = false;
    _showingVideo = false;
    _inEndFade = false;
    _endFadeOpacity = 0;
    _position = Duration.zero;
    _videoError = null;
    unawaited(audio?.dispose());
    unawaited(video?.dispose());
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _syncClip();
    });
  }

  Future<void> _ensureAudio() async {
    _audio ??= (widget.playerFactory ?? _mediaKitAudioPlayer)();
    if (_audioOpen) return;
    await _audio!.openFile(widget.audioPath);
    _audioOpen = true;
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _pausePlayback();
      return;
    }
    await _playFromCurrent();
  }

  Future<void> _pausePlayback() async {
    _resumeAfterScrub = false;
    _ticker?.cancel();
    _ticker = null;
    _followGen += 1;
    await _audio?.pause();
    await _video?.pause();
    if (!mounted) return;
    setState(() => _playing = false);
  }

  Future<void> _playFromCurrent() async {
    await _ensureAudio();
    if (!mounted) return;
    final audioTarget = itemListPreviewAudioSeek(
      position: _position,
      audioDuration: _audio?.duration ?? Duration.zero,
    );
    if (audioTarget != (_audio?.position ?? Duration.zero)) {
      await _audio!.seek(audioTarget);
      if (!mounted) return;
    }
    await _audio!.play();
    _startTicker();
    if (!mounted) return;
    setState(() => _playing = true);
    if (_inEndFade) {
      await _video?.pause();
      return;
    }
    await _followClip(_clipIndex);
  }

  void _applyVisual(Duration position) {
    _position = _clampTimelinePosition(widget.timeline, position);
    final frame = (_position.inMilliseconds * kItemListNleTimebase / 1000)
        .floor();
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
    _clipIndex = itemListPreviewClipIndex(
      clips: widget.timeline.clips,
      position: _position,
    );
    _endFadeOpacity = opacity;
    final clip = _clip;
    if (clip == null || clip.isStill || clip.localPath != _videoPath) {
      _showingVideo = false;
    }
  }

  void _syncClip() {
    if (_scrubbing) return;
    final audioPos = _audio?.position ?? _position;
    final audioLen = _audio?.duration ?? Duration.zero;
    // A scrub past the end of a short soundtrack keeps that picture. Playback
    // otherwise follows the soundtrack.
    final pos =
        audioLen > Duration.zero && audioPos >= audioLen && _position > audioPos
        ? _position
        : audioPos;
    final beforeIndex = _clipIndex;
    final beforeOpacity = _endFadeOpacity;
    final beforePos = _position;
    _applyVisual(pos);
    final opacityChanged = (_endFadeOpacity - beforeOpacity).abs() > 0.02;
    final indexChanged = _clipIndex != beforeIndex;
    final posChanged = _position != beforePos;
    if (!indexChanged && !opacityChanged && !posChanged) return;
    if (mounted) setState(() {});
    if (indexChanged && !_inEndFade) unawaited(_followClip(_clipIndex));
  }

  void _onScrubStart(double _) {
    _resumeAfterScrub = _playing;
    _scrubbing = true;
    _ticker?.cancel();
    _ticker = null;
    _scrubTimer?.cancel();
    unawaited(_audio?.pause());
    unawaited(_video?.pause());
  }

  void _onScrubChanged(double value) {
    _applyVisual(Duration(milliseconds: value.round()));
    if (mounted) setState(() {});
    final gen = ++_followGen;
    _scrubTimer?.cancel();
    _scrubTimer = Timer(const Duration(milliseconds: 120), () {
      if (!_scrubbing || !mounted) return;
      unawaited(_seekTransport(gen));
    });
  }

  void _onScrubEnd(double value) {
    unawaited(_finishScrub(value));
  }

  Future<void> _finishScrub(double value) async {
    _scrubTimer?.cancel();
    _scrubTimer = null;
    _scrubbing = false;
    _applyVisual(Duration(milliseconds: value.round()));
    if (mounted) setState(() {});
    final gen = ++_followGen;
    await _seekTransport(gen);
    if (!mounted || gen != _followGen) return;
    if (!_resumeAfterScrub) return;
    _resumeAfterScrub = false;
    await _audio?.play();
    if (!mounted) return;
    _startTicker();
    setState(() => _playing = true);
  }

  Future<void> _seekTransport(int gen) async {
    await _ensureAudio();
    if (gen != _followGen || !mounted) return;
    final audioTarget = itemListPreviewAudioSeek(
      position: _position,
      audioDuration: _audio?.duration ?? Duration.zero,
    );
    await _audio!.seek(audioTarget);
    if (gen != _followGen || !mounted) return;
    if (_inEndFade) {
      await _video?.pause();
      return;
    }
    await _followClip(_clipIndex, gen: gen);
  }

  Future<void> _followClip(int index, {int? gen}) async {
    final token = gen ?? ++_followGen;
    if (token != _followGen) return;
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
      if (token != _followGen) return;
      await _video?.pause();
      if (token != _followGen || !mounted) return;
      if (_showingVideo) setState(() => _showingVideo = false);
      return;
    }
    await _audio?.setVolume(
      itemListPreviewSoundtrackVolume(
        keyPeriod: true,
        soundtrackDuck: widget.soundtrackDuck,
      ),
    );
    if (token != _followGen) return;
    try {
      _video ??= (widget.videoPlayerFactory ?? _mediaKitVideoPlayer)();
      if (_videoPath != path) {
        await _video!.openFile(path);
        if (token != _followGen) return;
        _videoPath = path;
      }
      await _video!.seek(
        itemListPreviewSeek(clip: clip, soundtrackPosition: _position),
      );
      if (token != _followGen || !mounted) return;
      if (_playing && !_scrubbing) {
        await _video!.play();
        if (token != _followGen || !mounted) return;
      }
      setState(() {
        _showingVideo = true;
        _videoError = null;
      });
    } catch (_) {
      if (token != _followGen || !mounted) return;
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
        _scrubBar(),
        const SizedBox(height: 8),
        FilledButton.tonal(
          key: const Key('item-list-music-preview-play'),
          onPressed: clip == null ? null : _toggle,
          child: Text(_playing ? 'Pause preview' : 'Play preview'),
        ),
      ],
    );
  }

  Widget _scrubBar() {
    final totalMs = itemListNleTimelineDurationMs(widget.timeline);
    final total = Duration(milliseconds: totalMs);
    final valueMs = _position.inMilliseconds.clamp(0, totalMs);
    final enabled = widget.timeline.clips.isNotEmpty && totalMs > 0;
    return Row(
      children: [
        Expanded(
          // The route SelectionArea steals horizontal drags from the bar.
          child: SelectionContainer.disabled(
            child: Slider(
              key: const Key('item-list-preview-scrub'),
              min: 0,
              max: totalMs == 0 ? 1 : totalMs.toDouble(),
              value: totalMs == 0 ? 0.0 : valueMs.toDouble(),
              onChangeStart: enabled ? _onScrubStart : null,
              onChanged: enabled ? _onScrubChanged : null,
              onChangeEnd: enabled ? _onScrubEnd : null,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${itemListPreviewClock(_position)} / ${itemListPreviewClock(total)}',
          key: const Key('item-list-preview-time'),
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
