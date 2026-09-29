import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/api/item_lists_repository.dart';
import 'package:tagkin_desktop/contract/contract.dart' as api;
import 'package:tagkin_desktop/ingest/folder_bookmark_store.dart';
import 'package:tagkin_desktop/item_lists/item_list_media_size.dart';
import 'package:tagkin_desktop/item_lists/item_list_mp4_filter.dart';
import 'package:tagkin_desktop/item_lists/item_list_mp4_render.dart';
import 'package:tagkin_desktop/item_lists/item_list_nle.dart';
import 'package:tagkin_desktop/persons/collection.dart';

/// How many MP4 exports encode at once. Further exports wait.
const kItemListExportMaxConcurrent = 2;

enum ItemListExportJobState {
  queued,
  running,
  paused,
  done,
  failed,
  cancelled,
}

/// Immutable inputs for one MP4 export. Later filmstrip edits do not apply.
class ItemListMp4ExportRequest {
  const ItemListMp4ExportRequest({
    required this.entries,
    required this.itemsById,
    required this.outputPath,
    required this.audioPath,
    this.view,
    this.description = '',
    this.stillDurationSeconds = kItemListNleStillDurationSeconds,
    this.transition = ExportPhotoTransition.crossDissolve,
    this.transitionSeconds = kItemListNleTransitionSeconds,
    this.sequenceSize = ExportSequenceSize.matchSmallest,
    this.soundtrackDuck = kItemListMp4SoundtrackDuckDefault,
    this.macSaveHandle,
  });

  final List<api.ItemListEntry> entries;
  final Map<String, api.Item> itemsById;
  final String outputPath;
  final String audioPath;
  final SavedView? view;
  final String description;
  final double stillDurationSeconds;
  final ExportPhotoTransition transition;
  final double transitionSeconds;
  final ExportSequenceSize sequenceSize;
  final double soundtrackDuck;

  /// macOS Save As token. Null copies [outputPath] directly.
  final String? macSaveHandle;
}

/// One background MP4 export.
class ItemListExportJob extends ChangeNotifier {
  ItemListExportJob({
    required this.id,
    required this.request,
  }) : control = ItemListMp4CancelToken();

  ItemListExportJob.staged({
    required this.id,
    required String outputPath,
    required this.state,
    this.phase,
    this.clipIndex,
    this.clipCount,
    this.error,
  })  : request = ItemListMp4ExportRequest(
          entries: const [],
          itemsById: const {},
          outputPath: outputPath,
          audioPath: '',
        ),
        control = ItemListMp4CancelToken(),
        manual = true,
        started = state != ItemListExportJobState.queued;

  final String id;
  final ItemListMp4ExportRequest request;
  final ItemListMp4CancelToken control;

  /// Inserted for the jobs panel. The queue does not launch it.
  bool manual = false;

  /// True once [_run] has been scheduled. Pause/continue then signals ffmpeg
  /// instead of returning the job to the queue.
  bool started = false;

  ItemListExportJobState state = ItemListExportJobState.queued;
  ItemListMp4Phase? phase;
  int? clipIndex;
  int? clipCount;
  String? error;

  Future<void>? _run;
  final Completer<void> _done = Completer<void>();

  String get outputPath => request.outputPath;

  String get label => p.basename(outputPath);

  bool get isActive =>
      state == ItemListExportJobState.queued ||
      state == ItemListExportJobState.running ||
      state == ItemListExportJobState.paused;

  bool get isTerminal => !isActive;

  /// Completes when the job reaches a terminal state. Does not throw.
  Future<void> get completed => _done.future;

  String get progressLabel {
    switch (state) {
      case ItemListExportJobState.queued:
        return 'Waiting…';
      case ItemListExportJobState.paused:
        final phaseLabel = _phaseLabel();
        return phaseLabel == null ? 'Paused' : 'Paused · $phaseLabel';
      case ItemListExportJobState.running:
        return _phaseLabel() ?? 'Exporting…';
      case ItemListExportJobState.done:
        return 'Saved';
      case ItemListExportJobState.failed:
        return error ?? 'Export failed';
      case ItemListExportJobState.cancelled:
        return 'Cancelled';
    }
  }

  String? _phaseLabel() {
    final current = phase;
    if (current == null) return null;
    return itemListMp4ProgressLabel(
      ItemListMp4Progress(
        phase: current,
        clipIndex: clipIndex,
        clipCount: clipCount,
      ),
    );
  }

  void setProgress(ItemListMp4Progress progress) {
    phase = progress.phase;
    clipIndex = progress.clipIndex;
    clipCount = progress.clipCount;
    notifyListeners();
  }

  void markState(ItemListExportJobState next, {String? errorText}) {
    state = next;
    if (errorText != null) error = errorText;
    notifyListeners();
  }

  void attachRun(Future<void> run) {
    _run = run;
  }

  Future<void>? get run => _run;

  void finish() {
    if (!_done.isCompleted) _done.complete();
  }
}

/// App-level queue of MP4 exports. Survives leaving Export list.
class ItemListExportJobManager extends ChangeNotifier {
  ItemListExportJobManager({
    required this.renderMp4,
    ItemListMediaSizeProbe? probeMediaSize,
    this.itemListsRepository,
    int maxConcurrentJobs = kItemListExportMaxConcurrent,
  })  : _probeMediaSize = probeMediaSize ?? probeItemListMediaSize,
        maxConcurrent = maxConcurrentJobs < 1 ? 1 : maxConcurrentJobs;

  final ItemListMp4Renderer renderMp4;
  final ItemListMediaSizeProbe _probeMediaSize;
  final ItemListsRepository? itemListsRepository;
  final int maxConcurrent;

  final List<ItemListExportJob> _jobs = [];
  final Set<String> _releasedHandles = {};
  var _nextId = 1;
  var _disposed = false;

  List<ItemListExportJob> get jobs => List.unmodifiable(_jobs);

  bool get hasActive => _jobs.any((job) => job.isActive);

  int get activeCount => _jobs.where((job) => job.isActive).length;

  ItemListExportJob? jobById(String id) {
    for (final job in _jobs) {
      if (job.id == id) return job;
    }
    return null;
  }

  ItemListExportJob start(ItemListMp4ExportRequest request) {
    final job = ItemListExportJob(
      id: 'export-$_nextId',
      request: request,
    );
    _nextId += 1;
    _jobs.add(job);
    job.addListener(_onJob);
    _notify();
    _pump();
    return job;
  }

  /// Shows a job on the panel without encoding. Tests and previews.
  ItemListExportJob stageJob({
    required String outputPath,
    ItemListExportJobState state = ItemListExportJobState.running,
    ItemListMp4Phase? phase,
    int? clipIndex,
    int? clipCount,
    String? error,
  }) {
    final job = ItemListExportJob.staged(
      id: 'export-$_nextId',
      outputPath: outputPath,
      state: state,
      phase: phase,
      clipIndex: clipIndex,
      clipCount: clipCount,
      error: error,
    );
    _nextId += 1;
    _jobs.add(job);
    job.addListener(_onJob);
    _notify();
    return job;
  }

  void pause(String id) {
    final job = jobById(id);
    if (job == null) return;
    if (job.state != ItemListExportJobState.running &&
        job.state != ItemListExportJobState.queued) {
      return;
    }
    job.control.pause();
    job.markState(ItemListExportJobState.paused);
  }

  void resume(String id) {
    final job = jobById(id);
    if (job == null || job.state != ItemListExportJobState.paused) return;
    job.control.resume();
    if (job.started) {
      job.markState(ItemListExportJobState.running);
      return;
    }
    job.markState(ItemListExportJobState.queued);
    _pump();
  }

  void cancel(String id) {
    final job = jobById(id);
    if (job == null || job.isTerminal) return;
    if (job.run == null) {
      job.control.cancel();
      unawaited(_finishCancelled(job));
      return;
    }
    job.control.cancel();
  }

  Future<void> cancelAll() async {
    final pending = <Future<void>>[];
    for (final job in List<ItemListExportJob>.from(_jobs)) {
      if (!job.isActive) continue;
      pending.add(job.completed);
      cancel(job.id);
    }
    if (pending.isEmpty) return;
    await Future.wait(pending);
  }

  void dismiss(String id) {
    final job = jobById(id);
    if (job == null || job.isActive) return;
    job.removeListener(_onJob);
    _jobs.remove(job);
    _notify();
  }

  void clearFinished() {
    final done = [for (final job in _jobs) if (job.isTerminal) job];
    if (done.isEmpty) return;
    for (final job in done) {
      job.removeListener(_onJob);
      _jobs.remove(job);
    }
    _notify();
  }

  void _pump() {
    if (_disposed) return;
    while (_occupying < maxConcurrent) {
      ItemListExportJob? next;
      for (final job in _jobs) {
        if (job.manual || job.started) continue;
        if (job.state != ItemListExportJobState.queued) continue;
        next = job;
        break;
      }
      if (next == null) return;
      _launch(next);
    }
  }

  int get _occupying => _jobs.where((job) {
        if (!job.started || job.manual) return false;
        return job.state == ItemListExportJobState.running ||
            job.state == ItemListExportJobState.paused;
      }).length;

  void _launch(ItemListExportJob job) {
    job.started = true;
    job.markState(ItemListExportJobState.running);
    final run = _run(job);
    job.attachRun(run);
  }

  Future<void> _run(ItemListExportJob job) async {
    final wall = Stopwatch()..start();
    final request = job.request;
    try {
      await _gate(job);
      final fileSizes = await _probe(job);
      await _gate(job);
      final seq = itemListNleSequencePixelSize(
        mode: request.sequenceSize,
        probed: fileSizes.values,
      );
      final timeline = itemListNleTimeline(
        entries: request.entries,
        itemsById: request.itemsById,
        view: request.view,
        description: request.description,
        stillDurationSeconds: request.stillDurationSeconds,
        transition: request.transition,
        transitionSeconds: request.transitionSeconds,
      );
      await renderMp4(
        timeline: timeline,
        audioPath: request.audioPath,
        outputPath: request.outputPath,
        sequenceWidth: seq.width,
        sequenceHeight: seq.height,
        scaleToFit: request.sequenceSize.scaleToFit,
        soundtrackDuck: request.soundtrackDuck,
        onProgress: (progress) {
          if (job.isTerminal) return;
          job.setProgress(progress);
        },
        cancel: job.control,
        macSaveHandle: request.macSaveHandle,
      );
      await _gate(job);
      if (request.macSaveHandle == null) {
        ensureItemListExportNonEmpty(request.outputPath);
      }
      wall.stop();
      await _recordSuccess(
        job,
        timeline: timeline,
        encodeWallMs: wall.elapsedMilliseconds,
      );
      if (!job.isTerminal) job.markState(ItemListExportJobState.done);
    } on ItemListMp4CancelledException {
      await deleteEmptyItemListExport(request.outputPath);
      if (!job.isTerminal) job.markState(ItemListExportJobState.cancelled);
    } catch (e) {
      await deleteEmptyItemListExport(request.outputPath);
      if (!job.isTerminal) {
        job.markState(ItemListExportJobState.failed, errorText: '$e');
      }
    } finally {
      await _releaseHandle(job);
      job.finish();
      _notify();
      _pump();
    }
  }

  Future<void> _gate(ItemListExportJob job) async {
    await job.control.checkpoint();
    if (job.isTerminal) return;
    if (job.state == ItemListExportJobState.paused) return;
    if (!job.control.isPaused && !job.control.isCancelled) {
      job.markState(ItemListExportJobState.running);
    }
  }

  Future<Map<String, ItemListPixelSize>> _probe(ItemListExportJob job) async {
    final out = <String, ItemListPixelSize>{};
    final seen = <String>{};
    for (final entry in job.request.entries) {
      await job.control.checkpoint();
      if (!seen.add(entry.itemId)) continue;
      final path = itemListNleLocalPath(entry, job.request.itemsById);
      if (path == null || path.isEmpty) continue;
      final size = await _probeMediaSize(
        path,
        isStill: entry.kind != api.ItemListEntryKind.keyperiod,
      );
      if (size != null && size.isValid) out[entry.itemId] = size;
    }
    return out;
  }

  Future<void> _recordSuccess(
    ItemListExportJob job, {
    required ItemListNleTimeline timeline,
    required int encodeWallMs,
  }) async {
    final repo = itemListsRepository;
    if (repo == null) return;
    final request = job.request;
    try {
      await repo.recordExport(
        api.RecordItemListExport(
          format: api.ItemListExportFormat.fromWire('mp4WithMusic'),
          photoCount: request.entries
              .where((e) => e.kind == api.ItemListEntryKind.photo)
              .length,
          keyPeriodCount: request.entries
              .where((e) => e.kind == api.ItemListEntryKind.keyperiod)
              .length,
          outputDurationMs: itemListNleTimelineDurationMs(timeline),
          encodeWallMs: encodeWallMs,
        ),
      );
    } catch (e, st) {
      debugPrint('item-list-export record failed: $e\n$st');
    }
  }

  Future<void> _finishCancelled(ItemListExportJob job) async {
    await deleteEmptyItemListExport(job.outputPath);
    await _releaseHandle(job);
    if (!job.isTerminal) job.markState(ItemListExportJobState.cancelled);
    job.finish();
    _notify();
    _pump();
  }

  Future<void> _releaseHandle(ItemListExportJob job) async {
    final handle = job.request.macSaveHandle;
    if (handle == null || handle.isEmpty) return;
    if (!_releasedHandles.add(handle)) return;
    try {
      await SecurityScopedBookmarks.releaseSaveFile(handle);
    } catch (_) {}
  }

  void _onJob() => _notify();

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final job in List<ItemListExportJob>.from(_jobs)) {
      job.control.cancel();
      if (!job.isTerminal) job.markState(ItemListExportJobState.cancelled);
      job.finish();
      job.removeListener(_onJob);
    }
    super.dispose();
  }
}
