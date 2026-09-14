import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
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
  Widget get view;
  Stream<Size> get videoSize;

  /// Wait until the file can be seeked (duration known).
  Future<void> prepare();
  Future<void> setClip(Duration start, Duration stopAt);
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
  Widget get view {
    return SelectionContainer.disabled(
      key: const Key('item-hover-preview-video-selection-off'),
      child: Video(controller: _controller),
    );
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
  Future<void> setClip(Duration start, Duration stopAt) {
    _clipStop = stopAt;
    return _setMpvAbLoop(_player, start: start, stopAt: stopAt);
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
  Future<void> play() => _player.play();

  @override
  Future<void> dispose() async {
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

/// Enlarged photo / key-period video preview on Folders thumb hover.
class ItemHoverPreview extends StatefulWidget {
  const ItemHoverPreview({
    super.key,
    required this.item,
    required this.controller,
    required this.child,
    this.period,
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
  Timer? _timer;

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

  void _onEnter(PointerEvent _) {
    _timer?.cancel();
    _timer = null;
    if (_portal.isShowing) return;
    _timer = Timer(widget.hoverDelay, _show);
  }

  void _onExit(PointerEvent _) {
    _timer?.cancel();
    _timer = Timer(widget.hideDelay, _hide);
  }

  void _show() {
    if (!mounted) return;
    ItemHoverPreviewScope.maybeOf(context)?.claim(_hide);
    if (!_portal.isShowing) {
      _portal.show();
    }
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
        // Ignore pointer so the overlay cannot steal hover from the thumb
        // (which would flicker show/hide). The card is display-only.
        return IgnorePointer(
          child: Align(
            key: const Key('item-hover-preview-align'),
            alignment: Alignment.center,
            child: _HoverPreviewCard(
              item: widget.item,
              controller: widget.controller,
              period: widget.period,
              fallbackVideoWindow: widget.fallbackVideoWindow,
              resolveMedia: _resolve,
              openVideo: _openVideo,
              buildPhoto: widget.buildPhoto,
            ),
          ),
        );
      },
      child: MouseRegion(
        key: Key(_hoverPreviewKey(widget.item.id, widget.period)),
        onEnter: _onEnter,
        onExit: _onExit,
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
    this.buildPhoto,
  });

  final Item item;
  final LibraryTableController controller;
  final KeyPeriodKnowledge? period;
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
    this.buildPhoto,
  });

  final Item item;
  final LibraryTableController controller;
  final KeyPeriodKnowledge? period;
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
  HoverPreviewVideoSession? _session;
  StreamSubscription<Size>? _sizeSub;
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
        setState(() => _photo = media.file);
        if (widget.buildPhoto != null) return;
        final decoded = await _decodePhotoSize(media.file!);
        if (!mounted || gen != _gen) return;
        if (decoded == null) {
          setState(() => _error = 'Could not decode local photo.');
          return;
        }
        setState(() => _intrinsic = decoded);
        return;
      }
      final session = await widget.openVideo(media.file!);
      if (!mounted || gen != _gen) {
        await session.dispose();
        return;
      }
      _session = session;
      final window = _windowFromCache();
      _startAt = window.start;
      _stopAt = window.stopAt;
      await session.prepare();
      await session.setClip(_startAt, _stopAt);
      await session.seek(_startAt);
      await session.play();
      if (!mounted || gen != _gen) return;
      _sizeSub = session.videoSize.listen((size) {
        if (!mounted || gen != _gen) return;
        setState(() => _intrinsic = size);
      });
      setState(() {});
      if (widget.period == null && !_cachedPeriodsReady) {
        unawaited(_applyKeyPeriodStop(gen));
      }
    } catch (_) {
      if (!mounted || gen != _gen) return;
      setState(() => _error = 'Could not open this file.');
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
      await _session?.setClip(_startAt, _stopAt);
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
    final photo = _photo;
    if (photo != null) {
      final custom = widget.buildPhoto;
      if (custom != null) return custom(photo);
      final fitted = _fitted;
      if (fitted == null) {
        return const _HoverPreviewSpinner();
      }
      return Image.file(
        photo,
        key: const Key('item-hover-preview-photo'),
        width: fitted.width,
        height: fitted.height,
        fit: BoxFit.fill,
        cacheWidth: (fitted.width * 2).round(),
        errorBuilder: (_, _, _) => const _HoverPreviewMessage(
          message: 'Could not decode local photo.',
        ),
      );
    }
    final session = _session;
    if (session != null) {
      final fitted = _fitted;
      if (fitted == null) {
        return const _HoverPreviewSpinner();
      }
      return SizedBox(
        key: const Key('item-hover-preview-video'),
        width: fitted.width,
        height: fitted.height,
        child: session.view,
      );
    }
    return const _HoverPreviewSpinner();
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
