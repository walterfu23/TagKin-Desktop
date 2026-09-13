import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';
import 'package:tagkin_desktop/review/media_viewer.dart';

/// Delay before a Folders thumb hover opens the enlarged preview.
const Duration kHoverPreviewDelay = Duration(milliseconds: 350);

/// Brief grace so an overlay rebuild does not treat `onExit` as a real leave.
const Duration kHoverPreviewHideDelay = Duration(milliseconds: 50);

/// Play window when a video has no key periods yet / none on `/knowledge`.
const Duration kHoverPreviewFallbackVideoWindow = Duration(seconds: 4);

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

/// Stop time for hover video: first key period's `endMs`, else [fallback].
Duration hoverPreviewStopAt({
  required List<KeyPeriodKnowledge> keyPeriods,
  Duration fallback = kHoverPreviewFallbackVideoWindow,
}) {
  if (keyPeriods.isEmpty) return fallback;
  var first = keyPeriods.first;
  for (final period in keyPeriods) {
    if (period.startMs < first.startMs) first = period;
  }
  if (first.endMs <= 0) return fallback;
  return Duration(milliseconds: first.endMs);
}

/// Local video session used by the hover preview. Tests inject a fake.
abstract class HoverPreviewVideoSession {
  Widget get view;
  Stream<Duration> get position;
  Stream<Size> get videoSize;
  Future<void> seek(Duration to);
  Future<void> play();
  Future<void> dispose();
}

Future<HoverPreviewVideoSession> _openMediaKitHoverVideo(File file) async {
  final opened = await openLocalVideo(file);
  return _MediaKitHoverPreviewVideoSession(opened.player, opened.controller);
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

  void _emitSize() {
    final w = _player.state.width;
    final h = _player.state.height;
    if (w == null || h == null || w <= 0 || h <= 0) return;
    final size = Size(w.toDouble(), h.toDouble());
    if (_lastSize == size) return;
    _lastSize = size;
    if (!_sizes.isClosed) _sizes.add(size);
  }

  @override
  Widget get view {
    return SelectionContainer.disabled(
      key: const Key('item-hover-preview-video-selection-off'),
      child: Video(controller: _controller),
    );
  }

  @override
  Stream<Duration> get position => _player.stream.position;

  @override
  Stream<Size> get videoSize async* {
    final last = _lastSize;
    if (last != null) yield last;
    yield* _sizes.stream;
  }

  @override
  Future<void> seek(Duration to) => _player.seek(to);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> dispose() async {
    await _widthSub?.cancel();
    await _heightSub?.cancel();
    await _sizes.close();
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

/// Enlarged photo / first-key-period video preview on Folders thumb hover.
class ItemHoverPreview extends StatefulWidget {
  const ItemHoverPreview({
    super.key,
    required this.item,
    required this.controller,
    required this.child,
    this.hoverDelay = kHoverPreviewDelay,
    this.hideDelay = kHoverPreviewHideDelay,
    this.fallbackVideoWindow = kHoverPreviewFallbackVideoWindow,
    this.resolveMedia,
    this.openVideo,
    this.buildPhoto,
  });

  final Item item;
  final LibraryTableController controller;
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
              fallbackVideoWindow: widget.fallbackVideoWindow,
              resolveMedia: _resolve,
              openVideo: _openVideo,
              buildPhoto: widget.buildPhoto,
            ),
          ),
        );
      },
      child: MouseRegion(
        key: Key('item-hover-preview-${widget.item.id}'),
        onEnter: _onEnter,
        onExit: _onExit,
        child: widget.child,
      ),
    );
  }
}

class _HoverPreviewCard extends StatelessWidget {
  const _HoverPreviewCard({
    required this.item,
    required this.controller,
    required this.fallbackVideoWindow,
    required this.resolveMedia,
    required this.openVideo,
    this.buildPhoto,
  });

  final Item item;
  final LibraryTableController controller;
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
    this.buildPhoto,
  });

  final Item item;
  final LibraryTableController controller;
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
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Size>? _sizeSub;
  Size? _intrinsic;
  Duration _stopAt = kHoverPreviewFallbackVideoWindow;
  int _gen = 0;

  Size get _max => hoverPreviewMaxForWindow(MediaQuery.sizeOf(context));

  Size? get _fitted {
    final intrinsic = _intrinsic;
    if (intrinsic == null) return null;
    return fitHoverPreviewSize(intrinsic, _max);
  }

  @override
  void initState() {
    super.initState();
    _stopAt = widget.fallbackVideoWindow;
    unawaited(_load());
  }

  @override
  void dispose() {
    _gen++;
    _posSub?.cancel();
    _posSub = null;
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
      await session.seek(Duration.zero);
      await session.play();
      if (!mounted || gen != _gen) return;
      _posSub = session.position.listen(_onPosition);
      _sizeSub = session.videoSize.listen((size) {
        if (!mounted || gen != _gen) return;
        setState(() => _intrinsic = size);
      });
      setState(() {});
      unawaited(_applyKeyPeriodStop(gen));
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
      _stopAt = hoverPreviewStopAt(
        keyPeriods: periods,
        fallback: widget.fallbackVideoWindow,
      );
    } catch (_) {
      // Keep the fallback window.
    }
  }

  void _onPosition(Duration position) {
    if (position >= _stopAt && position > const Duration(milliseconds: 16)) {
      unawaited(_session?.seek(Duration.zero) ?? Future<void>.value());
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
