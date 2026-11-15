import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/review/key_period_offsets.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';

/// Delay before a Folders thumb hover opens the enlarged preview.
const Duration kHoverPreviewDelay = Duration(milliseconds: 350);

/// Brief grace so an overlay rebuild does not treat `onExit` as a real leave.
const Duration kHoverPreviewHideDelay = Duration(milliseconds: 50);

/// Longer grace when the card has face boxes, so the pointer can reach it.
const Duration kHoverPreviewFaceHideDelay = Duration(milliseconds: 300);

/// Tap on a numbered face box (or a video name-strip label).
typedef HoverFaceTap = Future<void> Function(HoverPreviewFace face, Rect box);

/// Play window when a video has no key periods yet / none on `/knowledge`.
const Duration kHoverPreviewFallbackVideoWindow = Duration(seconds: 4);

/// How long hover waits for duration / an exact seek to land.
const Duration kHoverPreviewReadyTimeout = Duration(seconds: 2);

/// Position within this of [start] counts as a landed seek.
const Duration kHoverPreviewSeekSlop = Duration(milliseconds: 200);

const double kHoverPreviewMaxWidth = 840;
const double kHoverPreviewMaxHeight = 720;
const Size kHoverPreviewFallbackSize = Size(120, 80);
const double kHoverPreviewWindowInset = 48;

/// Uniformly scale [intrinsic] to fit inside [max] (no letterboxing).
Size fitHoverPreviewSize(Size intrinsic, Size max) {
  if (intrinsic.width <= 0 ||
      intrinsic.height <= 0 ||
      max.width <= 0 ||
      max.height <= 0) {
    return kHoverPreviewFallbackSize;
  }
  final scale = math.min(
    max.width / intrinsic.width,
    max.height / intrinsic.height,
  );
  return Size(intrinsic.width * scale, intrinsic.height * scale);
}

/// Cap for the hover card: 840×720, and the window minus [kHoverPreviewWindowInset].
Size hoverPreviewMaxForWindow(Size window) {
  return Size(
    math.min(
      kHoverPreviewMaxWidth,
      math.max(0, window.width - kHoverPreviewWindowInset),
    ),
    math.min(
      kHoverPreviewMaxHeight,
      math.max(0, window.height - kHoverPreviewWindowInset),
    ),
  );
}

/// Play window for a Folders hover video: seek [start], player-loop at [stopAt].
class HoverPreviewWindow {
  const HoverPreviewWindow({required this.start, required this.stopAt});

  final Duration start;
  final Duration stopAt;
}

/// mpv `ab-loop-a` / `ab-loop-b` timestamp (seconds).
String hoverAbLoopTimestamp(Duration d) {
  if (d <= Duration.zero) return '0';
  return (d.inMicroseconds / Duration.microsecondsPerSecond).toString();
}

Future<void> _setMpvAbLoop(
  Player player, {
  required Duration start,
  required Duration stopAt,
}) async {
  final native = player.platform;
  if (native is! NativePlayer) return;
  await native.setProperty('ab-loop-a', hoverAbLoopTimestamp(start));
  await native.setProperty('ab-loop-b', hoverAbLoopTimestamp(stopAt));
}

Future<void> _clearMpvAbLoop(Player player) async {
  final native = player.platform;
  if (native is! NativePlayer) return;
  await native.setProperty('ab-loop-a', 'no');
  await native.setProperty('ab-loop-b', 'no');
}

/// Stop time for hover video: earliest period's `endMs`, else [fallback].
Duration hoverPreviewStopAt({
  required List<KeyPeriodKnowledge> keyPeriods,
  Duration fallback = kHoverPreviewFallbackVideoWindow,
}) {
  return hoverPreviewWindow(keyPeriods: keyPeriods, fallback: fallback).stopAt;
}

/// Window for a specific [period], else that period's `[startMs, endMs)` /
/// [fallback] from 0 when none are known.
///
/// Never forces start to 0 when the stored period starts later.
HoverPreviewWindow hoverPreviewWindow({
  KeyPeriodKnowledge? period,
  List<KeyPeriodKnowledge> keyPeriods = const [],
  Duration fallback = kHoverPreviewFallbackVideoWindow,
}) {
  if (period != null) return _windowForPeriod(period, fallback);
  if (keyPeriods.isEmpty) {
    return HoverPreviewWindow(start: Duration.zero, stopAt: fallback);
  }
  var first = keyPeriods.first;
  for (final candidate in keyPeriods) {
    if (candidate.startMs < first.startMs) first = candidate;
  }
  return _windowForPeriod(first, fallback);
}

HoverPreviewWindow _windowForPeriod(
  KeyPeriodKnowledge period,
  Duration fallback,
) {
  final start = keyPeriodMsToSeek(period.startMs);
  final stop = keyPeriodMsToSeek(period.endMs);
  if (stop <= start) {
    return HoverPreviewWindow(start: start, stopAt: start + fallback);
  }
  return HoverPreviewWindow(start: start, stopAt: stop);
}

/// mpv `seek` argv so hover lands on [to], not the previous keyframe/open-at-0.
List<String> hoverExactSeekCommand(Duration to) {
  return ['seek', hoverAbLoopTimestamp(to), 'absolute+exact'];
}

/// Whether [position] is close enough to [start] to start audible playback.
bool hoverSeekPositionLanded({
  required Duration position,
  required Duration start,
  required Duration stopAt,
  Duration slop = kHoverPreviewSeekSlop,
}) {
  if (start <= Duration.zero) return true;
  if (position >= start && (stopAt <= start || position < stopAt)) {
    return true;
  }
  final diff = position >= start ? position - start : start - position;
  return diff <= slop;
}

/// Seek to a non-zero start was ignored (player still at the beginning).
bool hoverSeekStuckAtZero({
  required Duration position,
  required Duration start,
}) {
  return start > const Duration(seconds: 1) &&
      position < const Duration(milliseconds: 400);
}

/// Local video session used by the hover preview. Tests inject a fake.
abstract class HoverPreviewVideoSession {
  /// The player with its normal control bar. [onShowStill] adds a Show still
  /// button to the bar's button row.
  Widget buildView({VoidCallback? onShowStill});
  Stream<Size> get videoSize;

  /// Fires once when a non-looping clip reaches its stop (or the file ends).
  Stream<void> get clipEnded;

  /// Wait until the file can be seeked (duration known).
  Future<void> prepare();

  /// Plays `[start, stopAt)`. [loop] false plays once, then fires [clipEnded].
  Future<void> setClip(Duration start, Duration stopAt, {bool loop = true});
  Future<void> seek(Duration to);
  Future<void> play();
  Future<void> dispose();
}

Future<HoverPreviewVideoSession> _openMediaKitHoverVideo(File file) async {
  final player = Player();
  final controller = VideoController(player);
  await player.open(Media(file.path), play: false);
  return _MediaKitHoverPreviewVideoSession(player, controller);
}

class _MediaKitHoverPreviewVideoSession implements HoverPreviewVideoSession {
  _MediaKitHoverPreviewVideoSession(this._player, this._controller) {
    _widthSub = _player.stream.width.listen((_) => _emitSize());
    _heightSub = _player.stream.height.listen((_) => _emitSize());
    _emitSize();
  }

  final Player _player;
  final VideoController _controller;
  final StreamController<Size> _sizes = StreamController<Size>.broadcast();
  StreamSubscription<int?>? _widthSub;
  StreamSubscription<int?>? _heightSub;
  Size? _lastSize;
  Duration _clipStop = Duration.zero;
  bool _loop = true;
  bool _endFired = false;
  final StreamController<void> _ended = StreamController<void>.broadcast();
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<bool>? _doneSub;

  void _emitSize() {
    final w = _player.state.width;
    final h = _player.state.height;
    if (w == null || h == null || w <= 0 || h <= 0) return;
    final size = Size(w.toDouble(), h.toDouble());
    if (_lastSize == size) return;
    _lastSize = size;
    if (!_sizes.isClosed) _sizes.add(size);
  }

  Future<void> _waitUntilDurationReady() async {
    if (_player.state.duration > Duration.zero) return;
    final done = Completer<void>();
    final sub = _player.stream.duration.listen((d) {
      if (d > Duration.zero && !done.isCompleted) done.complete();
    });
    try {
      if (_player.state.duration > Duration.zero) return;
      await done.future.timeout(kHoverPreviewReadyTimeout);
    } on TimeoutException {
      // Seek/play anyway; a hung file still shows the spinner or first frame.
    } finally {
      await sub.cancel();
    }
  }

  Future<void> _seekExact(Duration to) async {
    final native = _player.platform;
    if (native is NativePlayer) {
      await native.command(hoverExactSeekCommand(to));
      return;
    }
    await _player.seek(to);
  }

  Future<bool> _waitUntilSeekLanded(Duration start) async {
    bool landed() => hoverSeekPositionLanded(
      position: _player.state.position,
      start: start,
      stopAt: _clipStop,
    );
    if (landed()) return true;
    final done = Completer<void>();
    final sub = _player.stream.position.listen((_) {
      if (landed() && !done.isCompleted) done.complete();
    });
    try {
      if (landed()) return true;
      await done.future.timeout(kHoverPreviewReadyTimeout);
      return true;
    } on TimeoutException {
      return landed();
    } finally {
      await sub.cancel();
    }
  }

  @override
  Widget buildView({VoidCallback? onShowStill}) {
    final video = Video(controller: _controller);
    return SelectionContainer.disabled(
      key: const Key('item-hover-preview-video-selection-off'),
      child: onShowStill == null
          ? video
          : MaterialDesktopVideoControlsTheme(
              normal: MaterialDesktopVideoControlsThemeData(
                bottomButtonBar: [
                  const MaterialDesktopSkipPreviousButton(),
                  const MaterialDesktopPlayOrPauseButton(),
                  const MaterialDesktopSkipNextButton(),
                  const MaterialDesktopVolumeButton(),
                  const MaterialDesktopPositionIndicator(),
                  const Spacer(),
                  Center(
                    child: _HoverClipButton(
                      buttonKey: const Key('hover-show-still'),
                      icon: Icons.image_outlined,
                      label: 'Show still',
                      onPressed: onShowStill,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const MaterialDesktopFullscreenButton(),
                ],
              ),
              fullscreen: const MaterialDesktopVideoControlsThemeData(),
              child: video,
            ),
    );
  }

  @override
  Stream<void> get clipEnded => _ended.stream;

  void _watchClipEnd() {
    _endFired = false;
    unawaited(_posSub?.cancel());
    unawaited(_doneSub?.cancel());
    void fire() {
      if (_endFired || _ended.isClosed) return;
      _endFired = true;
      unawaited(_player.pause());
      _ended.add(null);
    }

    _posSub = _player.stream.position.listen((position) {
      if (_clipStop > Duration.zero && position >= _clipStop) fire();
    });
    _doneSub = _player.stream.completed.listen((done) {
      if (done) fire();
    });
  }

  @override
  Stream<Size> get videoSize async* {
    final last = _lastSize;
    if (last != null) yield last;
    yield* _sizes.stream;
  }

  @override
  Future<void> prepare() => _waitUntilDurationReady();

  @override
  Future<void> setClip(Duration start, Duration stopAt, {bool loop = true}) {
    _clipStop = stopAt;
    _loop = loop;
    if (loop) return _setMpvAbLoop(_player, start: start, stopAt: stopAt);
    return _clearMpvAbLoop(_player);
  }

  @override
  Future<void> seek(Duration to) async {
    await _waitUntilDurationReady();
    await _seekExact(to);
    if (to <= Duration.zero) return;
    var ok = await _waitUntilSeekLanded(to);
    if (!ok &&
        hoverSeekStuckAtZero(position: _player.state.position, start: to)) {
      await _seekExact(to);
      await _waitUntilSeekLanded(to);
    }
  }

  @override
  Future<void> play() async {
    // Watch the stop only once the seek has landed, so an early position
    // cannot end a clip that has not started.
    if (!_loop) _watchClipEnd();
    await _player.play();
  }

  @override
  Future<void> dispose() async {
    await _posSub?.cancel();
    await _doneSub?.cancel();
    await _ended.close();
    await _widthSub?.cancel();
    await _heightSub?.cancel();
    await _sizes.close();
    await _clearMpvAbLoop(_player);
    await _player.dispose();
  }
}

/// Ensures only one Folders hover preview (and its video player) is active.
class ItemHoverPreviewScope extends StatefulWidget {
  const ItemHoverPreviewScope({super.key, required this.child});

  final Widget child;

  static ItemHoverPreviewScopeState? maybeOf(BuildContext context) {
    return context.findAncestorStateOfType<ItemHoverPreviewScopeState>();
  }

  @override
  State<ItemHoverPreviewScope> createState() => ItemHoverPreviewScopeState();
}

class ItemHoverPreviewScopeState extends State<ItemHoverPreviewScope> {
  VoidCallback? _hideActive;

  void claim(VoidCallback hide) {
    final previous = _hideActive;
    _hideActive = hide;
    if (previous != null && previous != hide) {
      previous();
    }
  }

  void release(VoidCallback hide) {
    if (_hideActive == hide) _hideActive = null;
  }

  @override
  void dispose() {
    _hideActive = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// One face on the enlarged preview while Folders is in edit mode.
class HoverPreviewFace {
  const HoverPreviewFace({
    required this.number,
    required this.region,
    this.personName,
    this.tagId,
    this.assigned = false,
  });

  /// 1-based index, matching the Who field badge on that row.
  final int number;
  final TagRegion region;
  final String? personName;

  /// Who-tag id for this box. Null when the preview is display-only.
  final String? tagId;

  /// True when this face already has a person, so Unassigned is offered.
  final bool assigned;

  String get label {
    final name = personName?.trim();
    if (name == null || name.isEmpty) return '$number Unassigned';
    return '$number $name';
  }
}

/// Enlarged photo / key-period video preview on Folders thumb hover.
class ItemHoverPreview extends StatefulWidget {
  const ItemHoverPreview({
    super.key,
    required this.item,
    required this.controller,
    required this.child,
    this.period,
    this.faces = const [],
    this.onFaceTap,
    this.faceStill,
    this.hoverDelay = kHoverPreviewDelay,
    this.hideDelay = kHoverPreviewHideDelay,
    this.fallbackVideoWindow = kHoverPreviewFallbackVideoWindow,
    this.resolveMedia,
    this.openVideo,
    this.buildPhoto,
  });

  final Item item;
  final LibraryTableController controller;

  /// When set, video hover plays this period's `[startMs, endMs)` (player loop).
  final KeyPeriodKnowledge? period;

  /// Face boxes drawn on a photo, or listed under a video, in edit mode.
  final List<HoverPreviewFace> faces;

  /// When set, a face box (or name-strip label) can be tapped.
  final HoverFaceTap? onFaceTap;

  /// Video with [faces]: the sample still the boxes were measured on. The card
  /// opens on it with numbered squares; a play button swaps in the clip.
  final Future<File?> Function()? faceStill;
  final Widget child;
  final Duration hoverDelay;
  final Duration hideDelay;
  final Duration fallbackVideoWindow;
  final Future<LocalMediaResolution> Function(Item item)? resolveMedia;
  final Future<HoverPreviewVideoSession> Function(File file)? openVideo;
  final Widget Function(File file)? buildPhoto;

  @override
  State<ItemHoverPreview> createState() => _ItemHoverPreviewState();
}

class _ItemHoverPreviewState extends State<ItemHoverPreview> {
  final OverlayPortalController _portal = OverlayPortalController();
  final GlobalKey _cardKey = GlobalKey();
  Timer? _timer;
  Offset? _pointer;
  bool _overThumb = false;
  bool _overCard = false;
  int _pins = 0;

  Future<LocalMediaResolution> _resolve(Item item) {
    final custom = widget.resolveMedia;
    if (custom != null) return custom(item);
    return resolveLocalMedia(item, verifyHash: false);
  }

  Future<HoverPreviewVideoSession> _openVideo(File file) {
    final custom = widget.openVideo;
    if (custom != null) return custom(file);
    return _openMediaKitHoverVideo(file);
  }

  void _onThumbEnter(PointerEvent event) {
    _pointer = event.position;
    _overThumb = true;
    _timer?.cancel();
    _timer = null;
    if (_portal.isShowing || _pins > 0) return;
    _timer = Timer(widget.hoverDelay, _show);
  }

  void _onThumbHover(PointerEvent event) {
    _pointer = event.position;
  }

  void _onThumbExit(PointerEvent event) {
    _pointer = event.position;
    _overThumb = false;
    // The enlarged card can cover the thumb. Exit then arrives after enter,
    // and a hide timer here would close the card the pointer is already on.
    if (_pointerIsOnCard()) {
      _overCard = true;
      _timer?.cancel();
      _timer = null;
      return;
    }
    _scheduleHide();
  }

  bool _pointerIsOnCard() {
    final pointer = _pointer;
    final box = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (pointer == null || box == null || !box.hasSize) return false;
    return box.size.contains(box.globalToLocal(pointer));
  }

  void _onCardEnter(PointerEvent _) {
    _overCard = true;
    _timer?.cancel();
    _timer = null;
  }

  void _onCardExit(PointerEvent _) {
    _overCard = false;
    _scheduleHide();
  }

  void _scheduleHide() {
    _timer?.cancel();
    if (_pins > 0 || _overThumb || _overCard) {
      _timer = null;
      return;
    }
    if (!_portal.isShowing) {
      _timer = null;
      return;
    }
    final delay = widget.faces.isEmpty
        ? widget.hideDelay
        : kHoverPreviewFaceHideDelay;
    _timer = Timer(delay, _hide);
  }

  Future<void> _handleFaceTap(HoverPreviewFace face, Rect box) async {
    final handler = widget.onFaceTap;
    if (handler == null) return;
    _pins++;
    _timer?.cancel();
    _timer = null;
    try {
      await handler(face, box);
    } finally {
      _pins--;
      if (mounted) _scheduleHide();
    }
  }

  void _show() {
    if (!mounted) return;
    ItemHoverPreviewScope.maybeOf(context)?.claim(_hide);
    if (!_portal.isShowing) {
      _portal.show();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _adoptPointerIfOnCard(),
      );
    });
  }

  /// A card that opens under a stationary pointer does not get [MouseRegion.onEnter].
  void _adoptPointerIfOnCard() {
    if (!mounted || widget.faces.isEmpty) return;
    if (!_pointerIsOnCard()) return;
    _overCard = true;
    _timer?.cancel();
    _timer = null;
  }

  void _hide() {
    _timer?.cancel();
    _timer = null;
    if (_portal.isShowing) {
      _portal.hide();
    }
    if (mounted) {
      ItemHoverPreviewScope.maybeOf(context)?.release(_hide);
    }
  }

  @override
  void didUpdateWidget(ItemHoverPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.faces.isNotEmpty &&
        widget.faces.isEmpty &&
        _portal.isShowing) {
      _overCard = false;
      _scheduleHide();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) {
        // A card with no faces ignores the pointer so it cannot steal hover
        // from the thumb. A card with faces stays up while the pointer is on
        // it, so a numbered box can be tapped.
        final card = Align(
          key: const Key('item-hover-preview-align'),
          alignment: Alignment.center,
          child: MouseRegion(
            key: _cardKey,
            onEnter: _onCardEnter,
            onExit: _onCardExit,
            onHover: _onThumbHover,
            child: _HoverPreviewCard(
              item: widget.item,
              controller: widget.controller,
              period: widget.period,
              faces: widget.faces,
              onFaceTap: widget.onFaceTap == null ? null : _handleFaceTap,
              faceStill: widget.faceStill,
              fallbackVideoWindow: widget.fallbackVideoWindow,
              resolveMedia: _resolve,
              openVideo: _openVideo,
              buildPhoto: widget.buildPhoto,
            ),
          ),
        );
        if (widget.faces.isEmpty) return IgnorePointer(child: card);
        return card;
      },
      child: MouseRegion(
        key: Key(_hoverPreviewKey(widget.item.id, widget.period)),
        onEnter: _onThumbEnter,
        onExit: _onThumbExit,
        onHover: _onThumbHover,
        child: widget.child,
      ),
    );
  }
}

String _hoverPreviewKey(String itemId, KeyPeriodKnowledge? period) {
  if (period == null) return 'item-hover-preview-$itemId';
  return 'item-hover-preview-$itemId-kp-${period.id}';
}

class _HoverPreviewCard extends StatelessWidget {
  const _HoverPreviewCard({
    required this.item,
    required this.controller,
    required this.fallbackVideoWindow,
    required this.resolveMedia,
    required this.openVideo,
    this.period,
    this.faces = const [],
    this.onFaceTap,
    this.faceStill,
    this.buildPhoto,
  });

  final Item item;
  final LibraryTableController controller;
  final KeyPeriodKnowledge? period;
  final List<HoverPreviewFace> faces;
  final HoverFaceTap? onFaceTap;
  final Future<File?> Function()? faceStill;
  final Duration fallbackVideoWindow;
  final Future<LocalMediaResolution> Function(Item item) resolveMedia;
  final Future<HoverPreviewVideoSession> Function(File file) openVideo;
  final Widget Function(File file)? buildPhoto;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('item-hover-preview-card'),
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: _HoverPreviewBody(
        item: item,
        controller: controller,
        period: period,
        faces: faces,
        onFaceTap: onFaceTap,
        faceStill: faceStill,
        fallbackVideoWindow: fallbackVideoWindow,
        resolveMedia: resolveMedia,
        openVideo: openVideo,
        buildPhoto: buildPhoto,
      ),
    );
  }
}

class _HoverPreviewBody extends StatefulWidget {
  const _HoverPreviewBody({
    required this.item,
    required this.controller,
    required this.fallbackVideoWindow,
    required this.resolveMedia,
    required this.openVideo,
    this.period,
    this.faces = const [],
    this.onFaceTap,
    this.faceStill,
    this.buildPhoto,
  });

  final Item item;
  final LibraryTableController controller;
  final KeyPeriodKnowledge? period;
  final List<HoverPreviewFace> faces;
  final HoverFaceTap? onFaceTap;
  final Future<File?> Function()? faceStill;
  final Duration fallbackVideoWindow;
  final Future<LocalMediaResolution> Function(Item item) resolveMedia;
  final Future<HoverPreviewVideoSession> Function(File file) openVideo;
  final Widget Function(File file)? buildPhoto;

  @override
  State<_HoverPreviewBody> createState() => _HoverPreviewBodyState();
}

class _HoverPreviewBodyState extends State<_HoverPreviewBody> {
  String? _error;
  File? _photo;

  /// Video sample still (edit mode with faces) and its pixel size.
  File? _still;
  Size? _stillSize;
  bool _playing = false;
  HoverPreviewVideoSession? _session;
  StreamSubscription<Size>? _sizeSub;
  StreamSubscription<void>? _endSub;
  Size? _intrinsic;
  Duration _startAt = Duration.zero;
  Duration _stopAt = kHoverPreviewFallbackVideoWindow;
  int _gen = 0;

  Size get _max => hoverPreviewMaxForWindow(MediaQuery.sizeOf(context));

  Size? get _fitted {
    final intrinsic = _intrinsic;
    if (intrinsic == null) return null;
    return fitHoverPreviewSize(intrinsic, _max);
  }

  HoverPreviewWindow _windowFromCache() {
    return hoverPreviewWindow(
      period: widget.period,
      keyPeriods:
          widget.controller.rowById(widget.item.id)?.keyPeriods ?? const [],
      fallback: widget.fallbackVideoWindow,
    );
  }

  bool get _cachedPeriodsReady {
    if (widget.period != null) return true;
    final row = widget.controller.rowById(widget.item.id);
    return row != null && row.knowledgeLoaded;
  }

  @override
  void initState() {
    super.initState();
    final window = _windowFromCache();
    _startAt = window.start;
    _stopAt = window.stopAt;
    unawaited(_load());
  }

  @override
  void dispose() {
    _gen++;
    _sizeSub?.cancel();
    _sizeSub = null;
    _endSub?.cancel();
    _endSub = null;
    final session = _session;
    _session = null;
    unawaited(session?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  Future<void> _load() async {
    final gen = ++_gen;
    try {
      final media = await widget.resolveMedia(widget.item);
      if (!mounted || gen != _gen) return;
      if (!media.isAvailable || media.file == null) {
        setState(() => _error = _statusMessage(media.status));
        return;
      }
      if (widget.item.type == ItemType.photo) {
        final file = media.file!;
        final known = _pixelSizeSync(file);
        setState(() {
          _photo = file;
          if (known != null) _intrinsic = known;
        });
        if (widget.buildPhoto != null || known != null) return;
        final decoded = await _decodePhotoSize(file);
        if (!mounted || gen != _gen) return;
        if (decoded == null) {
          setState(() => _error = 'Could not decode local photo.');
          return;
        }
        setState(() => _intrinsic = decoded);
        return;
      }
      if (widget.faces.isNotEmpty && widget.faceStill != null) {
        final still = await widget.faceStill!();
        if (!mounted || gen != _gen) return;
        final size = still == null ? null : await _stillPixelSize(still);
        if (!mounted || gen != _gen) return;
        if (still != null && size != null) {
          setState(() {
            _still = still;
            _stillSize = size;
            _intrinsic = size;
          });
          return;
        }
      }
      await _openClip(media.file!, gen);
    } catch (_) {
      if (!mounted || gen != _gen) return;
      setState(() => _error = 'Could not open this file.');
    }
  }

  Future<Size?> _stillPixelSize(File file) async {
    try {
      if (!file.existsSync()) return null;
    } catch (_) {
      return null;
    }
    return _pixelSizeSync(file) ?? await _decodePhotoSize(file);
  }

  Future<void> _openClip(File file, int gen) async {
    final session = await widget.openVideo(file);
    if (!mounted || gen != _gen) {
      await session.dispose();
      return;
    }
    _session = session;
    final window = _windowFromCache();
    _startAt = window.start;
    _stopAt = window.stopAt;
    // Still-based preview plays the period once, then returns to the still.
    final once = _still != null;
    await session.prepare();
    await session.setClip(_startAt, _stopAt, loop: !once);
    await session.seek(_startAt);
    await session.play();
    if (!mounted || gen != _gen) return;
    if (once) {
      _endSub = session.clipEnded.listen((_) {
        if (!mounted || gen != _gen || !_playing) return;
        _showStill();
      });
    }
    _sizeSub = session.videoSize.listen((size) {
      if (!mounted || gen != _gen) return;
      setState(() => _intrinsic = size);
    });
    setState(() {});
    if (widget.period == null && !_cachedPeriodsReady) {
      unawaited(_applyKeyPeriodStop(gen));
    }
  }

  /// Swap the sample still for the period clip (names move under the player).
  Future<void> _playClip() async {
    final gen = ++_gen;
    setState(() => _playing = true);
    try {
      final media = await widget.resolveMedia(widget.item);
      if (!mounted || gen != _gen) return;
      if (!media.isAvailable || media.file == null) {
        setState(() => _error = _statusMessage(media.status));
        return;
      }
      await _openClip(media.file!, gen);
    } catch (_) {
      if (!mounted || gen != _gen) return;
      setState(() => _error = 'Could not open this file.');
    }
  }

  void _showStill() {
    _gen++;
    _sizeSub?.cancel();
    _sizeSub = null;
    _endSub?.cancel();
    _endSub = null;
    final session = _session;
    _session = null;
    unawaited(session?.dispose() ?? Future<void>.value());
    setState(() {
      _playing = false;
      _intrinsic = _stillSize;
    });
  }

  /// Pixel size without the engine codec. Skips large files so hover stays async.
  Size? _pixelSizeSync(File file) {
    try {
      final length = file.lengthSync();
      if (length <= 0 || length > 4 * 1024 * 1024) return null;
      final bytes = file.readAsBytesSync();
      final decoded = img.decodeImage(bytes);
      if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
        return null;
      }
      return Size(decoded.width.toDouble(), decoded.height.toDouble());
    } catch (_) {
      return null;
    }
  }

  Future<Size?> _decodePhotoSize(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final size = Size(image.width.toDouble(), image.height.toDouble());
      image.dispose();
      if (size.width <= 0 || size.height <= 0) return null;
      return size;
    } catch (_) {
      return null;
    }
  }

  Future<void> _applyKeyPeriodStop(int gen) async {
    try {
      final periods = await widget.controller.ensureKeyPeriods(widget.item.id);
      if (!mounted || gen != _gen) return;
      final window = hoverPreviewWindow(
        keyPeriods: periods,
        fallback: widget.fallbackVideoWindow,
      );
      if (window.start == _startAt && window.stopAt == _stopAt) return;
      _startAt = window.start;
      _stopAt = window.stopAt;
      await _session?.setClip(_startAt, _stopAt, loop: _still == null);
      await _session?.seek(_startAt);
    } catch (_) {
      // Keep the fallback window.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _HoverPreviewMessage(message: _error!);
    }
    final still = _still;
    final photo = _photo ?? (_playing ? null : still);
    if (photo != null) {
      final custom = widget.buildPhoto;
      if (custom != null) {
        return _HoverPreviewFaces(
          faces: widget.faces,
          onFaceTap: widget.onFaceTap,
          child: custom(photo),
        );
      }
      final fitted = _fitted;
      if (fitted == null) {
        return const _HoverPreviewSpinner();
      }
      final faces = _HoverPreviewFaces(
        faces: widget.faces,
        onFaceTap: widget.onFaceTap,
        size: fitted,
        child: Image.file(
          photo,
          key: const Key('item-hover-preview-photo'),
          width: fitted.width,
          height: fitted.height,
          fit: BoxFit.fill,
          cacheWidth: (fitted.width * 2).round(),
          errorBuilder: (_, _, _) => const _HoverPreviewMessage(
            message: 'Could not decode local photo.',
          ),
        ),
      );
      if (still == null) return faces;
      return Stack(
        children: [
          faces,
          Positioned(
            right: 8,
            bottom: 8,
            child: _HoverClipButton(
              buttonKey: const Key('hover-play-period'),
              icon: Icons.play_arrow,
              label: 'Play',
              onPressed: _playClip,
            ),
          ),
        ],
      );
    }
    final session = _session;
    if (session != null) {
      final fitted = _fitted;
      if (fitted == null) {
        return const _HoverPreviewSpinner();
      }
      return _HoverPreviewFaces(
        faces: widget.faces,
        onFaceTap: widget.onFaceTap,
        child: SizedBox(
          key: const Key('item-hover-preview-video'),
          width: fitted.width,
          height: fitted.height,
          child: session.buildView(
            onShowStill: still == null ? null : _showStill,
          ),
        ),
      );
    }
    return const _HoverPreviewSpinner();
  }
}

class _HoverClipButton extends StatelessWidget {
  const _HoverClipButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Key buttonKey;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xCC000000),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: buttonKey,
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Numbered face boxes on a sized photo, or a name strip under other media.
class _HoverPreviewFaces extends StatelessWidget {
  const _HoverPreviewFaces({
    required this.faces,
    required this.child,
    this.onFaceTap,
    this.size,
  });

  final List<HoverPreviewFace> faces;
  final Widget child;
  final HoverFaceTap? onFaceTap;
  final Size? size;

  @override
  Widget build(BuildContext context) {
    if (faces.isEmpty) return child;
    final fitted = size;
    if (fitted == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          _HoverFaceStrip(faces: faces, onFaceTap: onFaceTap),
        ],
      );
    }
    // A face whose box cannot be placed still gets a labeled box, stacked at
    // the top-left in number order, so its name is never missing.
    final stacked = <HoverPreviewFace>[];
    final placed = <(HoverPreviewFace, Rect)>[];
    for (final face in faces) {
      final rect = hoverFaceBoxRect(face.region, fitted);
      if (rect == null) {
        stacked.add(face);
      } else {
        placed.add((face, rect));
      }
    }
    return SizedBox(
      width: fitted.width,
      height: fitted.height,
      child: Stack(
        children: [
          child,
          for (final (face, rect) in placed) ...[
            Positioned.fromRect(
              rect: rect,
              child: _HoverFaceHit(
                face: face,
                onTap: onFaceTap,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ),
            // Label sits outside the box widget so a small box still shows
            // the whole name, and the label is tappable too.
            Positioned(
              left: rect.left,
              top: rect.top,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.max(
                    kHoverFaceMinBox,
                    fitted.width - rect.left,
                  ),
                ),
                child: _HoverFaceHit(
                  face: face,
                  onTap: onFaceTap,
                  child: _HoverFaceLabel(face: face),
                ),
              ),
            ),
          ],
          for (var i = 0; i < stacked.length; i++)
            Positioned(
              left: 4,
              top: 4 + i * (kHoverFaceMinBox + 4),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.max(kHoverFaceMinBox, fitted.width - 8),
                ),
                child: _HoverFaceHit(
                  face: stacked[i],
                  onTap: onFaceTap,
                  child: DecoratedBox(
                    key: Key('hover-face-unplaced-${stacked[i].number}'),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: _HoverFaceLabel(face: stacked[i]),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Smallest side of a numbered box on the still, so a tiny face still shows.
const double kHoverFaceMinBox = 24;

/// Where a face box sits on a picture of [size]. The region is clamped to the
/// frame and a box smaller than [kHoverFaceMinBox] grows around its center.
/// Null when the region is empty, not finite, or entirely off the frame.
@visibleForTesting
Rect? hoverFaceBoxRect(TagRegion region, Size size) {
  final values = [region.xMin, region.yMin, region.xMax, region.yMax];
  if (values.any((v) => !v.isFinite) || size.isEmpty) return null;
  double unit(double v) => v.clamp(0.0, 1.0);
  final left = unit(region.xMin) * size.width;
  final top = unit(region.yMin) * size.height;
  final right = unit(region.xMax) * size.width;
  final bottom = unit(region.yMax) * size.height;
  if (right <= left || bottom <= top) return null;
  final width = math.min(math.max(right - left, kHoverFaceMinBox), size.width);
  final height = math.min(
    math.max(bottom - top, kHoverFaceMinBox),
    size.height,
  );
  final x = (((left + right) / 2) - width / 2).clamp(0.0, size.width - width);
  final y = (((top + bottom) / 2) - height / 2).clamp(
    0.0,
    size.height - height,
  );
  return Rect.fromLTWH(x, y, width, height);
}

class _HoverFaceLabel extends StatelessWidget {
  const _HoverFaceLabel({required this.face});

  final HoverPreviewFace face;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xCC000000),
      child: Text(
        face.label,
        key: Key('hover-face-label-${face.number}'),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}

class _HoverFaceHit extends StatelessWidget {
  const _HoverFaceHit({required this.face, required this.child, this.onTap});

  final HoverPreviewFace face;
  final HoverFaceTap? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final onTap = this.onTap;
    if (onTap == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;
        final rect = box.localToGlobal(Offset.zero) & box.size;
        unawaited(onTap(face, rect));
      },
      child: child,
    );
  }
}

class _HoverFaceStrip extends StatelessWidget {
  const _HoverFaceStrip({required this.faces, this.onFaceTap});

  final List<HoverPreviewFace> faces;
  final HoverFaceTap? onFaceTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 8,
        children: [
          for (final face in faces)
            _HoverFaceHit(
              face: face,
              onTap: onFaceTap,
              child: Text(
                face.label,
                key: Key('hover-face-label-${face.number}'),
              ),
            ),
        ],
      ),
    );
  }
}

class _HoverPreviewSpinner extends StatelessWidget {
  const _HoverPreviewSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 120,
      height: 80,
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _HoverPreviewMessage extends StatelessWidget {
  const _HoverPreviewMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('item-hover-preview-error'),
      padding: const EdgeInsets.all(16),
      child: Text(message, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

String _statusMessage(LocalMediaStatus status) {
  switch (status) {
    case LocalMediaStatus.missing:
      return 'Local media not found.';
    case LocalMediaStatus.accessDenied:
      return 'Cannot open this file.';
    case LocalMediaStatus.hashMismatch:
      return 'This file does not match the library record.';
    case LocalMediaStatus.unsupported:
    case LocalMediaStatus.available:
      return 'Local media is not available.';
  }
}
