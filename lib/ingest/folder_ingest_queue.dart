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
import 'package:tagkin_desktop/library/library_membership_sync.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/persons/who_face_linker.dart';
import 'package:tagkin_desktop/persons/face_crop_folder_scope.dart';
import 'package:tagkin_desktop/prepass/prepass_controller.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';
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

  /// Paths skipped because they were already registered (re-ingest).
  int alreadyInLibraryCount = 0;

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
        if (createdCount > 0) {
          return 'Done ($createdCount added)';
        }
        if (alreadyInLibraryCount > 0) {
          return 'Done ($alreadyInLibraryCount already in library)';
        }
        return 'Done (nothing new)';
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
    this.onLibraryMembershipPublish,
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

  /// Adopt / claim leaves for the open collection after register (or done).
  /// Receives the ingest root path so owned-elsewhere leaves can be claimed.
  final Future<void> Function(String folderPath)? onLibraryMembershipPublish;

  List<FolderIngestJob> _jobs = const [];
  int _libraryRefreshTick = 0;
  bool _disposed = false;

  List<FolderIngestJob> get jobs => List.unmodifiable(_jobs);

  /// Bumps when items are created so the library can reload.
  int get libraryRefreshTick => _libraryRefreshTick;

  bool get hasActiveJobs => _jobs.any((j) => j.isActive);

  int get activeJobCount => _jobs.where((j) => j.isActive).length;

  static String normalizePath(String path) => p.normalize(path);

  /// Whether Faces should hide [path] while this job is still scanning or
  /// registering items (not during pre-pass / upload / analyze).
  static bool hidesFacesFolder(FolderIngestJobPhase phase) =>
      phase == FolderIngestJobPhase.scanning ||
      phase == FolderIngestJobPhase.registering;

  /// Whether [path] (ingest root or a nested Faces leaf) is still registering.
  ///
  /// Only scanning/registering hide the folder — once items exist, Faces may
  /// list the leaf during analyze.
  bool isLoadingPath(String path) {
    final normalized = normalizePath(path);
    return _jobs.any(
      (j) =>
          hidesFacesFolder(j.phase) &&
          pathIsUnderFolder(normalized, j.folderPath),
    );
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> _publishMembership(String folderPath) async {
    final hook = onLibraryMembershipPublish;
    if (hook == null || _disposed) return;
    try {
      await hook(folderPath);
    } catch (e, st) {
      debugPrint('FolderIngestQueue membership publish failed: $e\n$st');
    }
  }

  /// Bump library refresh and adopt membership from an unfiltered item list.
  Future<void> _bumpLibraryAndPublish(String folderPath) async {
    _libraryRefreshTick++;
    await _publishMembership(folderPath);
    _safeNotify();
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
      final existingSourcePaths = <String>{
        for (final item in existingItems)
          if (localPathFromSourceRef(item.sourceRef) case final path?)
            normalizePath(path),
      };

      final nearDupThreshold = samplingPrefs?.call().nearDuplicateThreshold ??
          nearDuplicateHammingThreshold;

      final result = dedupCandidates(
        candidates: hashed,
        existingSourcePaths: existingSourcePaths,
        nearDuplicateHammingThreshold: nearDupThreshold,
      );

      job.alreadyInLibraryCount = result.skipped
          .where((s) => s.reason == SkipReason.existingInLibrary)
          .length;

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
        // Reveal Faces + adopt membership (e.g. prior items under this root).
        await _bumpLibraryAndPublish(job.folderPath);
        return;
      }

      // Leave registering before publish so isLoadingPath clears and Faces
      // can list the new leaf during pre-pass / upload / analyze.
      job.phase = FolderIngestJobPhase.prePass;
      await _bumpLibraryAndPublish(job.folderPath);
      if (_disposed) return;

      final prePass = prePassFactory?.call() ??
          PrePassController(
            itemsRepository: itemsRepository,
            samplingPrefs: samplingPrefs?.call(),
          );
      final upload = uploadFactory?.call() ??
          UploadController(itemsRepository: itemsRepository);
      final linker = whoFaceLinkerFactory?.call() ??
          () {
            final prefs = samplingPrefs?.call();
            return WhoFaceLinker(
              items: itemsRepository,
              autoConfirmMinConfidencePercent: prefs != null &&
                      prefs.autoConfirmHighConfidencePersonMatches
                  ? prefs.autoConfirmMinConfidencePercent
                  : null,
            );
          }();
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
      await _bumpLibraryAndPublish(job.folderPath);
    } catch (e) {
      job.phase = FolderIngestJobPhase.error;
      job.error = e;
      await _bumpLibraryAndPublish(job.folderPath);
    }
  }
}

/// Session-scoped ingest queue (survives navigation away from Library).
///
/// Must not `watch` churny inputs like [desktopPrefsProvider] — recreating the
/// queue orphans Folders/Faces listeners that bound a prior instance.
/// Must not `watch` [usageControllerProvider] either — that pulls apiClient
/// and fails in Faces widget tests without a signed-in shell.
final folderIngestQueueProvider = ChangeNotifierProvider<FolderIngestQueue>(
  (ref) {
    return FolderIngestQueue(
      itemsRepository: ref.read(itemsRepositoryProvider),
      jobsRepository: ref.read(jobsRepositoryProvider),
      isUsageBlocked: () {
        try {
          return ref.read(usageControllerProvider).gate.blocked;
        } catch (_) {
          return false;
        }
      },
      enumerateFolder: ref.read(mediaEnumeratorProvider),
      contentHasher: ref.read(contentHasherProvider),
      perceptualHasher: ref.read(perceptualHasherProvider),
      samplingPrefs: () => ref.read(desktopPrefsProvider),
      onLibraryMembershipPublish: (folderPath) async {
        final cols = ref.read(collectionsControllerProvider);
        final table = ref.read(libraryTableControllerProvider);
        await publishCollectionMembershipFromLibrary(
          items: ref.read(itemsRepositoryProvider),
          cols: cols,
          table: table,
          claimUnderFolder: folderPath,
        );
      },
    );
  },
  dependencies: [
    itemsRepositoryProvider,
    jobsRepositoryProvider,
    usageControllerProvider,
    mediaEnumeratorProvider,
    contentHasherProvider,
    perceptualHasherProvider,
    collectionsControllerProvider,
    libraryTableControllerProvider,
  ],
);
