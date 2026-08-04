import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/api/items_repository.dart';
import 'package:tagkin_desktop/api/jobs_repository.dart';
import 'package:tagkin_desktop/app_shell.dart'
    show itemsRepositoryProvider, jobsRepositoryProvider;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/batch_ingest_controller.dart';
import 'package:tagkin_desktop/ingest/content_hash.dart';
import 'package:tagkin_desktop/ingest/dedup.dart';
import 'package:tagkin_desktop/ingest/media_enumerator.dart';
import 'package:tagkin_desktop/ingest/perceptual_hash.dart';
import 'package:tagkin_desktop/ingest/post_ingest_pipeline_controller.dart';
import 'package:tagkin_desktop/ingest/upload_controller.dart';
import 'package:tagkin_desktop/persons/who_face_linker.dart';
import 'package:tagkin_desktop/persons/face_crop_folder_scope.dart';
import 'package:tagkin_desktop/prepass/prepass_controller.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';
import 'package:tagkin_desktop/usage/usage_controller.dart';

/// Phase of one background folder ingest job (full D3→D4→D5→D7 chain).
enum FolderIngestJobPhase {
  scanning,
  registering,
  prePass,
  upload,
  analyze,
  done,
  error,
}

/// Result of [FolderIngestQueue.enqueue].
enum FolderIngestEnqueueResult {
  started,
  alreadyActive,
  cancelled,
}

/// One folder's background ingest run.
class FolderIngestJob {
  FolderIngestJob({required this.folderPath});

  final String folderPath;
  FolderIngestJobPhase phase = FolderIngestJobPhase.scanning;
  Object? error;

  int registerDone = 0;
  int registerTotal = 0;
  int createdCount = 0;

  bool get isActive =>
      phase != FolderIngestJobPhase.done && phase != FolderIngestJobPhase.error;

  String get folderLabel {
    final base = p.basename(folderPath);
    return base.isEmpty ? folderPath : base;
  }

  String get statusLabel {
    switch (phase) {
      case FolderIngestJobPhase.scanning:
        return 'Scanning…';
      case FolderIngestJobPhase.registering:
        if (registerTotal == 0) return 'Adding items…';
        return 'Adding items… $registerDone of $registerTotal';
      case FolderIngestJobPhase.prePass:
        return 'Pre-pass…';
      case FolderIngestJobPhase.upload:
        return 'Uploading…';
      case FolderIngestJobPhase.analyze:
        return 'Analyzing…';
      case FolderIngestJobPhase.done:
        return createdCount == 0
            ? 'Done (nothing new)'
            : 'Done ($createdCount added)';
      case FolderIngestJobPhase.error:
        return 'Failed';
    }
  }
}

/// App-scoped queue: multiple folders in parallel; same path blocked while active.
///
/// Skip review — auto-registers all dedup representatives, then runs the
/// post-ingest pipeline for that job only.
class FolderIngestQueue extends ChangeNotifier {
  FolderIngestQueue({
    required this.itemsRepository,
    required this.jobsRepository,
    required this.isUsageBlocked,
    this.enumerateFolder = enumerateMedia,
    this.contentHasher = computeContentHash,
    this.perceptualHasher = computePerceptualHashFromFile,
    this.nearDuplicateHammingThreshold = kDefaultNearDuplicateThreshold,
    this.samplingPrefs,
    this.prePassFactory,
    this.uploadFactory,
    this.whoFaceLinkerFactory,
  });

  final ItemsRepository itemsRepository;
  final JobsRepository jobsRepository;
  final bool Function() isUsageBlocked;
  final Future<List<MediaCandidate>> Function(String path) enumerateFolder;
  final Future<String> Function(String path) contentHasher;
  final Future<String?> Function(String path) perceptualHasher;
  final int nearDuplicateHammingThreshold;
  final DesktopPrefs Function()? samplingPrefs;

  /// Test hooks — production builds per-job controllers.
  final PrePassController Function()? prePassFactory;
  final UploadController Function()? uploadFactory;
  final WhoFaceLinker Function()? whoFaceLinkerFactory;

  List<FolderIngestJob> _jobs = const [];
  int _libraryRefreshTick = 0;
  bool _disposed = false;

  List<FolderIngestJob> get jobs => List.unmodifiable(_jobs);

  /// Bumps when items are created so the library can reload.
  int get libraryRefreshTick => _libraryRefreshTick;

  bool get hasActiveJobs => _jobs.any((j) => j.isActive);

  int get activeJobCount => _jobs.where((j) => j.isActive).length;

  static String normalizePath(String path) => p.normalize(path);

  /// Whether [path] (ingest root or a nested Faces leaf) is still being loaded.
  ///
  /// Active job roots hide themselves and every descendant leaf until the job
  /// finishes — so Faces only lists a folder after load complete.
  bool isLoadingPath(String path) {
    final normalized = normalizePath(path);
    return _jobs.any(
      (j) => j.isActive && pathIsUnderFolder(normalized, j.folderPath),
    );
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

  /// Starts a background job for [folderPath], or refuses if that path is busy.
  Future<FolderIngestEnqueueResult> enqueue(String folderPath) async {
    final normalized = normalizePath(folderPath);
    if (_jobs.any((j) => j.folderPath == normalized && j.isActive)) {
      return FolderIngestEnqueueResult.alreadyActive;
    }
    final job = FolderIngestJob(folderPath: normalized);
    _jobs = [..._jobs, job];
    _safeNotify();
    unawaited(_runJob(job));
    return FolderIngestEnqueueResult.started;
  }

  void dismissJob(FolderIngestJob job) {
    if (job.isActive) return;
    _jobs = _jobs.where((j) => j != job).toList(growable: false);
    _safeNotify();
  }

  void dismissFinished() {
    _jobs = _jobs.where((j) => j.isActive).toList(growable: false);
    _safeNotify();
  }

  Future<void> _runJob(FolderIngestJob job) async {
    try {
      job.phase = FolderIngestJobPhase.scanning;
      job.error = null;
      _safeNotify();

      final candidates = await enumerateFolder(job.folderPath);
      if (_disposed) return;
      final hashed = <HashedCandidate>[];
      for (final candidate in candidates) {
        final contentHash = await contentHasher(candidate.path);
        final perceptualHash = candidate.type == ItemType.photo
            ? await perceptualHasher(candidate.path)
            : null;
        hashed.add(
          HashedCandidate(
            candidate: candidate,
            contentHash: contentHash,
            perceptualHash: perceptualHash,
          ),
        );
      }

      final existingItems = await itemsRepository.listItems();
      if (_disposed) return;
      final existingHashes = existingItems
          .map((item) => item.contentHash)
          .whereType<String>()
          .toSet();

      final result = dedupCandidates(
        candidates: hashed,
        existingContentHashes: existingHashes,
        nearDuplicateHammingThreshold: nearDuplicateHammingThreshold,
      );

      job.phase = FolderIngestJobPhase.registering;
      job.registerTotal = result.representatives.length;
      job.registerDone = 0;
      _safeNotify();

      final outcomes = <IngestOutcome>[];
      for (final candidate in result.representatives) {
        if (_disposed) return;
        final path = candidate.candidate.path;
        try {
          final item = await itemsRepository.createItem(
            CreateItem(
              type: candidate.candidate.type,
              sourceType: SourceType.local,
              sourceRef: Uri.file(path).toString(),
              contentHash: candidate.contentHash,
              capturedAt: candidate.candidate.modifiedAt.toIso8601String(),
            ),
          );
          outcomes.add(IngestOutcome(path: path, item: item));
          job.createdCount++;
          _libraryRefreshTick++;
        } catch (e) {
          outcomes.add(IngestOutcome(path: path, error: e));
        }
        job.registerDone++;
        _safeNotify();
      }

      final succeeded = outcomes.where((o) => o.succeeded).length;
      if (succeeded == 0) {
        job.phase = FolderIngestJobPhase.done;
        // Still bump so Faces/Library can reveal folders that were hidden
        // while this job was active (e.g. items from a prior register).
        _libraryRefreshTick++;
        _safeNotify();
        return;
      }

      final prePass = prePassFactory?.call() ??
          PrePassController(
            itemsRepository: itemsRepository,
            samplingPrefs: samplingPrefs?.call(),
          );
      final upload = uploadFactory?.call() ??
          UploadController(itemsRepository: itemsRepository);
      final linker = whoFaceLinkerFactory?.call() ??
          WhoFaceLinker(items: itemsRepository);
      final pipeline = PostIngestPipelineController(
        prePass: prePass,
        upload: upload,
        jobsRepository: jobsRepository,
        whoFaceLinker: linker,
      );

      void syncPipelinePhase() {
        final phase = pipeline.phase;
        if (phase == PostIngestPipelinePhase.runningPrePass) {
          job.phase = FolderIngestJobPhase.prePass;
        } else if (phase == PostIngestPipelinePhase.runningUpload) {
          job.phase = FolderIngestJobPhase.upload;
        } else if (phase == PostIngestPipelinePhase.runningAnalyze) {
          job.phase = FolderIngestJobPhase.analyze;
        } else if (phase == PostIngestPipelinePhase.done ||
            phase == PostIngestPipelinePhase.skippedUpload) {
          job.phase = FolderIngestJobPhase.done;
        } else if (phase == PostIngestPipelinePhase.error) {
          job.phase = FolderIngestJobPhase.error;
          job.error = pipeline.error;
        }
        _safeNotify();
      }

      pipeline.addListener(syncPipelinePhase);
      try {
        await pipeline.start(
          ingestOutcomes: outcomes,
          usageBlocked: isUsageBlocked(),
        );
      } finally {
        pipeline.removeListener(syncPipelinePhase);
        pipeline.dispose();
        prePass.dispose();
        upload.dispose();
      }

      if (_disposed) return;
      if (pipeline.phase == PostIngestPipelinePhase.error) {
        job.phase = FolderIngestJobPhase.error;
        job.error = pipeline.error;
      } else {
        job.phase = FolderIngestJobPhase.done;
      }
      _libraryRefreshTick++;
      _safeNotify();
    } catch (e) {
      job.phase = FolderIngestJobPhase.error;
      job.error = e;
      _libraryRefreshTick++;
      _safeNotify();
    }
  }
}

/// Session-scoped ingest queue (survives navigation away from Library).
final folderIngestQueueProvider = ChangeNotifierProvider<FolderIngestQueue>(
  (ref) {
    // Keep usage gate alive for isUsageBlocked callbacks during long jobs.
    ref.watch(usageControllerProvider);
    return FolderIngestQueue(
      itemsRepository: ref.watch(itemsRepositoryProvider),
      jobsRepository: ref.watch(jobsRepositoryProvider),
      isUsageBlocked: () => ref.read(usageControllerProvider).gate.blocked,
      enumerateFolder: ref.watch(mediaEnumeratorProvider),
      contentHasher: ref.watch(contentHasherProvider),
      perceptualHasher: ref.watch(perceptualHasherProvider),
      nearDuplicateHammingThreshold:
          ref.watch(desktopPrefsProvider).nearDuplicateThreshold,
      samplingPrefs: () => ref.read(desktopPrefsProvider),
    );
  },
  dependencies: [
    itemsRepositoryProvider,
    jobsRepositoryProvider,
    usageControllerProvider,
    mediaEnumeratorProvider,
    contentHasherProvider,
    perceptualHasherProvider,
    desktopPrefsProvider,
  ],
);
