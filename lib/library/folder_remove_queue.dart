import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/api/jobs_repository.dart';
import 'package:tagkin_desktop/app_shell.dart' show jobsRepositoryProvider;
import 'package:tagkin_desktop/ingest/folder_bookmark_store.dart';

/// Phase of one background folder-remove job.
enum FolderRemoveJobPhase {
  running,
  done,
  error,
}

/// Result of [FolderRemoveQueue.enqueue].
enum FolderRemoveEnqueueResult {
  started,
  alreadyActive,
  empty,
}

/// One folder's background soft-delete run.
class FolderRemoveJob {
  FolderRemoveJob({
    required this.folderPath,
    required this.itemIds,
  }) : total = itemIds.length;

  final String folderPath;
  final List<String> itemIds;
  final int total;

  FolderRemoveJobPhase phase = FolderRemoveJobPhase.running;
  Object? error;
  int completed = 0;
  int failed = 0;

  bool get isActive => phase == FolderRemoveJobPhase.running;

  String get folderLabel {
    final base = p.basename(folderPath);
    return base.isEmpty ? folderPath : base;
  }

  String get statusLabel {
    switch (phase) {
      case FolderRemoveJobPhase.running:
        if (total == 0) return 'Removing…';
        return 'Removing… $completed of $total';
      case FolderRemoveJobPhase.done:
        if (failed > 0) {
          return 'Done ($failed of $total failed)';
        }
        return 'Done ($total removed)';
      case FolderRemoveJobPhase.error:
        return 'Failed';
    }
  }
}

/// App-scoped queue: soft-delete every item under a folder path in the background.
///
/// Progress is shown in the shell status banner (same pattern as folder ingest).
class FolderRemoveQueue extends ChangeNotifier {
  FolderRemoveQueue({
    required this.jobsRepository,
    this.removeBookmark,
  });

  final JobsRepository jobsRepository;

  /// Best-effort bookmark cleanup; defaults to [folderBookmarkStore.remove].
  final Future<void> Function(String dir)? removeBookmark;

  List<FolderRemoveJob> _jobs = const [];
  int _libraryRefreshTick = 0;
  bool _disposed = false;

  List<FolderRemoveJob> get jobs => List.unmodifiable(_jobs);

  /// Bumps when a remove job finishes so the library can reload.
  int get libraryRefreshTick => _libraryRefreshTick;

  bool get hasActiveJobs => _jobs.any((j) => j.isActive);

  int get activeJobCount => _jobs.where((j) => j.isActive).length;

  static String normalizePath(String path) => p.normalize(path);

  bool isRemoving(String folderPath) {
    final normalized = normalizePath(folderPath);
    return _jobs.any((j) => j.folderPath == normalized && j.isActive);
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Starts a background remove for [folderPath], or refuses if that path is busy.
  Future<FolderRemoveEnqueueResult> enqueue(
    String folderPath,
    List<String> itemIds,
  ) async {
    final normalized = normalizePath(folderPath);
    if (_jobs.any((j) => j.folderPath == normalized && j.isActive)) {
      return FolderRemoveEnqueueResult.alreadyActive;
    }
    if (itemIds.isEmpty) {
      return FolderRemoveEnqueueResult.empty;
    }
    final job = FolderRemoveJob(
      folderPath: normalized,
      itemIds: List<String>.from(itemIds),
    );
    _jobs = [..._jobs, job];
    _safeNotify();
    unawaited(_runJob(job));
    return FolderRemoveEnqueueResult.started;
  }

  void dismissJob(FolderRemoveJob job) {
    if (job.isActive) return;
    _jobs = _jobs.where((j) => j != job).toList(growable: false);
    _safeNotify();
  }

  void dismissFinished() {
    _jobs = _jobs.where((j) => j.isActive).toList(growable: false);
    _safeNotify();
  }

  Future<void> _runJob(FolderRemoveJob job) async {
    try {
      for (final id in job.itemIds) {
        try {
          await jobsRepository.deleteItem(id);
        } catch (e) {
          job.failed++;
          job.error = e;
        }
        job.completed++;
        _safeNotify();
      }

      try {
        final remove = removeBookmark ?? folderBookmarkStore.remove;
        await remove(job.folderPath);
      } catch (_) {
        // Bookmark cleanup is best-effort for sandbox reopen.
      }

      job.phase = job.failed == job.total && job.total > 0
          ? FolderRemoveJobPhase.error
          : FolderRemoveJobPhase.done;
    } catch (e) {
      job.error = e;
      job.phase = FolderRemoveJobPhase.error;
    }
    _libraryRefreshTick++;
    _safeNotify();
  }
}

final folderRemoveQueueProvider = ChangeNotifierProvider<FolderRemoveQueue>(
  (ref) {
    return FolderRemoveQueue(
      jobsRepository: ref.watch(jobsRepositoryProvider),
    );
  },
  // Required when the signed-in shell overrides jobsRepositoryProvider
  // (same pattern as folderIngestQueueProvider).
  dependencies: [jobsRepositoryProvider],
);
