import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/api/items_repository.dart';
import 'package:tagkin_desktop/api/jobs_repository.dart';
import 'package:tagkin_desktop/app_shell.dart'
    show
        itemsRepositoryProvider,
        jobsRepositoryProvider,
        signedInAccountIdProvider;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/active_folder_ingest_store.dart';
import 'package:tagkin_desktop/ingest/ingest_io.dart';
import 'package:tagkin_desktop/ingest/ingest_outcome.dart';
import 'package:tagkin_desktop/ingest/content_hash.dart';
import 'package:tagkin_desktop/ingest/dedup.dart';
import 'package:tagkin_desktop/ingest/folder_bookmark_store.dart';
import 'package:tagkin_desktop/ingest/folder_picker.dart';
import 'package:tagkin_desktop/ingest/media_enumerator.dart';
import 'package:tagkin_desktop/ingest/perceptual_hash.dart';
import 'package:tagkin_desktop/ingest/physical_memory.dart';
import 'package:tagkin_desktop/ingest/post_ingest_pipeline_controller.dart';
import 'package:tagkin_desktop/ingest/tagkin_fixed_sidecar.dart';
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
  processing,
  done,
  error,
}

/// Result of [FolderIngestQueue.enqueue].
enum FolderIngestEnqueueResult { started, alreadyActive, cancelled }

/// One folder's background ingest run.
class FolderIngestJob {
  FolderIngestJob({
    required this.folderPath,
    this.continueExistingOnly = false,
    this.collectionId,
    this.claimFromOtherCollections = const {},
  });

  final String folderPath;

  /// Sandbox-resolved path from [ensureFolderAccess], when it differs.
  String? resolvedFolderPath;

  /// Collection that started this job (banner + membership claim).
  /// Null when no collection session was open at enqueue.
  final String? collectionId;

  /// Leaves the user approved moving off another collection (pick-time).
  /// Empty on crash-resume so membership never silently steals.
  final Set<String> claimFromOtherCollections;

  /// Skip enumerate / create; pipeline incomplete library items under this root.
  final bool continueExistingOnly;
  FolderIngestJobPhase phase = FolderIngestJobPhase.scanning;
  Object? error;

  /// Scan listed the folder but found no supported photo/video files.
  bool noSupportedMedia = false;

  int registerDone = 0;
  int registerTotal = 0;
  int createdCount = 0;

  /// Paths skipped because they were already registered (re-ingest).
  int alreadyInLibraryCount = 0;

  /// Existing library items under this folder that were still incomplete
  /// and went through the post-ingest pipeline (crash resume).
  int continuedCount = 0;

  /// Post-register pipeline progress (one item at a time).
  int pipelineDone = 0;
  int pipelineTotal = 0;

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
      case FolderIngestJobPhase.processing:
        if (pipelineTotal == 0) return 'Processing…';
        return 'Processing $pipelineDone of $pipelineTotal…';
      case FolderIngestJobPhase.done:
        if (createdCount > 0) {
          return 'Done ($createdCount added)';
        }
        if (continuedCount > 0) {
          return 'Done ($continuedCount continued)';
        }
        if (alreadyInLibraryCount > 0) {
          return 'Done ($alreadyInLibraryCount already in library)';
        }
        if (noSupportedMedia) {
          return 'Done (no supported photos or videos)';
        }
        return 'Done (nothing new)';
      case FolderIngestJobPhase.error:
        final msg = error?.toString();
        if (msg != null && msg.isNotEmpty) return 'Failed — $msg';
        return 'Failed';
    }
  }
}

/// App-scoped queue: up to two folders in parallel (one when RAM is under
/// 8 GiB); same path blocked while active.
///
/// Skip review — auto-registers all dedup representatives, then runs the
/// post-ingest pipeline for that job only.
class FolderIngestQueue extends ChangeNotifier {
  FolderIngestQueue({
    required this.itemsRepository,
    required this.jobsRepository,
    required this.isUsageBlocked,
    this.onPaidReject,
    this.enumerateFolder = enumerateMedia,
    this.contentHasher = computeContentHash,
    this.perceptualHasher = computePerceptualHashFromFile,
    this.nearDuplicateHammingThreshold = kDefaultNearDuplicateThreshold,
    this.samplingPrefs,
    this.prePassFactory,
    this.uploadFactory,
    this.whoFaceLinkerFactory,
    this.onLibraryMembershipPublish,
    this.currentCollectionId,
    this.collectionIdForFolder,
    this.onItemUpdated,
    this.accountId,
    this.checkpointStore,
    this.ensureFolderAccess,
    this.bookmarkedFolders,
    this.physicalMemoryBytes = unknownPhysicalMemoryBytes,
  });

  final ItemsRepository itemsRepository;
  final JobsRepository jobsRepository;
  final bool Function() isUsageBlocked;
  final void Function(String? code, String message)? onPaidReject;
  final Future<List<MediaCandidate>> Function(String path) enumerateFolder;
  final Future<String> Function(String path) contentHasher;
  final Future<String?> Function(String path) perceptualHasher;
  final int nearDuplicateHammingThreshold;
  final DesktopPrefs Function()? samplingPrefs;

  /// Test hooks — production builds per-job controllers.
  final PrePassController Function()? prePassFactory;
  final UploadController Function()? uploadFactory;
  final WhoFaceLinker Function()? whoFaceLinkerFactory;

  /// Adopt / claim leaves after register (or done).
  /// [collectionId] is the collection that started the job, when known.
  /// [claimFromOtherCollections] is the pick-time Move-here set (empty on resume).
  final Future<void> Function(
    String folderPath, {
    String? collectionId,
    Set<String> claimFromOtherCollections,
  })?
  onLibraryMembershipPublish;

  /// Open collection at enqueue time (Add from folder).
  final String? Function()? currentCollectionId;

  /// Collection that already owns [folderPath], used on crash-resume enqueue.
  final String? Function(String folderPath)? collectionIdForFolder;

  /// Live Folders-row patch as upload/analyze finishes (no full table reload).
  final void Function(Item item)? onItemUpdated;

  /// Current signed-in account (scopes crash-resume checkpoints).
  final String? Function()? accountId;

  /// When set, persist in-progress folder paths across process death.
  final ActiveFolderIngestStore? checkpointStore;

  /// Restore sandbox / existence before enumerate. Returns the path to
  /// scan (sandbox-resolved on macOS). Null skips (unit tests).
  final Future<String?> Function(String folderPath)? ensureFolderAccess;

  /// macOS security-scoped ingest roots (empty on Windows / in most tests).
  final Future<List<String>> Function()? bookmarkedFolders;

  /// Total physical RAM in bytes. Tests inject or skip; production provider
  /// uses [probePhysicalMemoryBytes].
  final Future<int?> Function() physicalMemoryBytes;

  List<FolderIngestJob> _jobs = const [];
  int _libraryRefreshTick = 0;
  bool _disposed = false;
  bool _restoreStarted = false;
  int _maxParallelJobs = kDefaultFolderIngestMaxParallelJobs;
  Future<void>? _resolveCap;
  int _inFlightJobs = 0;
  final List<Completer<void>> _jobWaiters = [];
  List<Item>? _itemsCache;
  DateTime? _itemsCacheAt;

  /// Last [Item.processingStatus] pushed via [onItemUpdated], so upload then
  /// analyze can both patch the same row without repeating a no-op.
  final Map<String, ProcessingStatus> _liveStatusById = {};

  List<FolderIngestJob> get jobs => List.unmodifiable(_jobs);

  /// Bumps when items are created so the library can reload.
  int get libraryRefreshTick => _libraryRefreshTick;

  bool get hasActiveJobs => _jobs.any((j) => j.isActive);

  int get activeJobCount => _jobs.where((j) => j.isActive).length;

  /// Jobs whose [FolderIngestJob.collectionId] matches [collectionId].
  ///
  /// When [collectionId] is null (no open collection), returns every job.
  List<FolderIngestJob> jobsForCollection(String? collectionId) {
    if (collectionId == null) return jobs;
    return [
      for (final j in _jobs)
        if (j.collectionId == collectionId) j,
    ];
  }

  int activeJobCountForCollection(String? collectionId) =>
      jobsForCollection(collectionId).where((j) => j.isActive).length;

  /// 1 or 2 after the RAM probe; 2 until the first job slot is acquired.
  @visibleForTesting
  int get maxParallelJobs => _maxParallelJobs;

  static String normalizePath(String path) => normalizeLeafFolder(path);

  static Item? _libraryItemForSidecarOriginal(
    List<Item> existingItems,
    String sidecarPath,
  ) {
    final originals = {
      for (final path in originalPathsForTagkinFixedSidecar(sidecarPath))
        normalizePath(path),
    };
    for (final item in existingItems) {
      final path = localPathFromSourceRef(item.sourceRef);
      if (path == null) continue;
      if (originals.contains(normalizePath(path))) return item;
    }
    return null;
  }

  /// Whether Faces should hide a folder for this job phase.
  ///
  /// True for every in-flight phase; Faces lists the leaf only after `done`
  /// or `error` (failed jobs should still reveal whatever items exist).
  static bool hidesFacesFolder(FolderIngestJobPhase phase) =>
      phase != FolderIngestJobPhase.done && phase != FolderIngestJobPhase.error;

  /// Whether [path] (ingest root or a nested Faces leaf) is still ingesting.
  bool isLoadingPath(String path) {
    final normalized = normalizePath(path);
    return _jobs.any(
      (j) => hidesFacesFolder(j.phase) && _jobCoversPath(j, normalized),
    );
  }

  /// Drop the 5s `GET /items` cache (folder remove, or start of a new job).
  void invalidateItemsCache() {
    _itemsCache = null;
    _itemsCacheAt = null;
  }

  static bool _jobCoversPath(FolderIngestJob job, String filePath) {
    if (pathIsUnderFolder(filePath, job.folderPath)) return true;
    final resolved = job.resolvedFolderPath;
    if (resolved == null || resolved.isEmpty) return false;
    return pathIsUnderFolder(filePath, resolved);
  }

  String _claimPath(FolderIngestJob job) =>
      job.resolvedFolderPath ?? job.folderPath;

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> _publishMembership(
    String folderPath, {
    String? collectionId,
    Set<String> claimFromOtherCollections = const {},
  }) async {
    final hook = onLibraryMembershipPublish;
    if (hook == null || _disposed) return;
    try {
      await hook(
        folderPath,
        collectionId: collectionId,
        claimFromOtherCollections: claimFromOtherCollections,
      );
    } catch (e, st) {
      debugPrint('FolderIngestQueue membership publish failed: $e\n$st');
    }
  }

  void _emitItemUpdated(Item item) {
    if (_disposed) return;
    if (_liveStatusById[item.id] == item.processingStatus) return;
    _liveStatusById[item.id] = item.processingStatus;
    final hook = onItemUpdated;
    if (hook == null) return;
    try {
      hook(item);
    } catch (e, st) {
      debugPrint('FolderIngestQueue onItemUpdated failed: $e\n$st');
    }
  }

  /// Bump library refresh and adopt membership from an unfiltered item list.
  Future<void> _bumpLibraryAndPublish(FolderIngestJob job) async {
    _libraryRefreshTick++;
    await _publishMembership(
      _claimPath(job),
      collectionId: job.collectionId,
      claimFromOtherCollections: job.claimFromOtherCollections,
    );
    _safeNotify();
  }

  Future<void> _checkpointAdd(String folderPath) async {
    final store = checkpointStore;
    final id = accountId?.call();
    if (store == null || id == null || id.isEmpty) return;
    try {
      await store.add(id, folderPath);
    } catch (e, st) {
      debugPrint('FolderIngestQueue checkpoint add failed: $e\n$st');
    }
  }

  Future<void> _checkpointRemove(String folderPath) async {
    final store = checkpointStore;
    final id = accountId?.call();
    if (store == null || id == null || id.isEmpty) return;
    try {
      await store.remove(id, folderPath);
    } catch (e, st) {
      debugPrint('FolderIngestQueue checkpoint remove failed: $e\n$st');
    }
  }

  /// Re-open persisted ingest roots after sign-in (crash resume).
  ///
  /// Does not latch [restoreOnSignIn]; callers that need once-per-session
  /// should use that entry point.
  Future<void> restoreInterrupted() async {
    if (_disposed) return;
    final store = checkpointStore;
    final id = accountId?.call();
    if (store == null || id == null || id.isEmpty) return;
    final paths = await store.listForAccount(id);
    for (final path in paths) {
      if (_disposed) return;
      await enqueue(
        path,
        collectionId:
            collectionIdForFolder?.call(path) ?? currentCollectionId?.call(),
      );
    }
  }

  /// Pipeline unfinished library items on sign-in (no re-scan / re-create).
  Future<void> restoreIncompleteFromLibrary() async {
    if (_disposed) return;
    final items = await _listItemsCached();
    if (_disposed) return;
    final incomplete = items.where(_pipelineIncomplete);
    final bookmarks = await bookmarkedFolders?.call() ?? const <String>[];
    final roots = coveringFoldersForItems(
      incomplete,
      bookmarkedFolders: bookmarks,
    );
    for (final root in roots) {
      if (_disposed) return;
      if (_hasActiveJobCovering(root)) continue;
      await enqueue(
        root,
        continueExistingOnly: true,
        collectionId:
            collectionIdForFolder?.call(root) ?? currentCollectionId?.call(),
      );
    }
  }

  /// Crash checkpoints first, then leftover unfinished items in the library.
  Future<void> restoreOnSignIn() async {
    if (_disposed || _restoreStarted) return;
    final id = accountId?.call();
    if (id == null || id.isEmpty) return;
    _restoreStarted = true;
    await restoreInterrupted();
    if (_disposed) return;
    await restoreIncompleteFromLibrary();
  }

  bool _hasActiveJobCovering(String folderPath) {
    final normalized = normalizePath(folderPath);
    return _jobs.any((j) {
      if (!j.isActive) return false;
      return j.folderPath == normalized ||
          _jobCoversPath(j, normalized) ||
          pathIsUnderFolder(j.folderPath, normalized) ||
          (j.resolvedFolderPath != null &&
              pathIsUnderFolder(j.resolvedFolderPath!, normalized));
    });
  }

  static bool _pipelineIncomplete(Item item) {
    switch (item.processingStatus) {
      case ProcessingStatus.pending:
      case ProcessingStatus.awaitingModelAccess:
      case ProcessingStatus.processing:
      case ProcessingStatus.failed:
        return true;
      case ProcessingStatus.tagged:
      case ProcessingStatus.cancelled:
        return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final waiter in _jobWaiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _jobWaiters.clear();
    super.dispose();
  }

  /// Starts a background job for [folderPath], or refuses if that path is busy.
  Future<FolderIngestEnqueueResult> enqueue(
    String folderPath, {
    bool continueExistingOnly = false,
    String? collectionId,
    Set<String> claimFromOtherCollections = const {},
  }) async {
    final normalized = normalizePath(folderPath);
    if (_jobs.any((j) => j.folderPath == normalized && j.isActive)) {
      return FolderIngestEnqueueResult.alreadyActive;
    }
    final steal = <String>{
      for (final f in claimFromOtherCollections)
        if (normalizeLeafFolder(f) case final key when key.isNotEmpty) key,
    };
    final job = FolderIngestJob(
      folderPath: normalized,
      continueExistingOnly: continueExistingOnly,
      collectionId: collectionId ?? currentCollectionId?.call(),
      claimFromOtherCollections: steal,
    );
    _jobs = [..._jobs, job];
    _safeNotify();
    await _checkpointAdd(normalized);
    unawaited(_runJobGuarded(job));
    return FolderIngestEnqueueResult.started;
  }

  Future<void> _ensureParallelCap() {
    return _resolveCap ??= () async {
      try {
        final bytes = await physicalMemoryBytes();
        _maxParallelJobs = folderIngestMaxParallelJobs(bytes);
        if (_maxParallelJobs == kLowRamFolderIngestMaxParallelJobs) {
          debugPrint(
            'FolderIngestQueue: physical RAM under 8 GiB; '
            'one folder at a time',
          );
        }
      } on Object catch (e, st) {
        debugPrint('FolderIngestQueue: RAM probe failed: $e\n$st');
        _maxParallelJobs = kDefaultFolderIngestMaxParallelJobs;
      }
    }();
  }

  Future<void> _acquireJobSlot() async {
    await _ensureParallelCap();
    if (_inFlightJobs < _maxParallelJobs) {
      _inFlightJobs++;
      return;
    }
    final waiter = Completer<void>();
    _jobWaiters.add(waiter);
    await waiter.future;
    _inFlightJobs++;
  }

  void _releaseJobSlot() {
    _inFlightJobs--;
    if (_jobWaiters.isNotEmpty) {
      _jobWaiters.removeAt(0).complete();
    }
  }

  Future<void> _runJobGuarded(FolderIngestJob job) async {
    await _acquireJobSlot();
    try {
      if (_disposed) return;
      await _runJob(job);
    } finally {
      _releaseJobSlot();
    }
  }

  Future<List<Item>> _listItemsCached() async {
    final now = DateTime.now();
    if (_itemsCache != null &&
        _itemsCacheAt != null &&
        now.difference(_itemsCacheAt!) < const Duration(seconds: 5)) {
      return _itemsCache!;
    }
    final items = await itemsRepository.listItems();
    _itemsCache = items;
    _itemsCacheAt = now;
    return items;
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
      job.noSupportedMedia = false;
      invalidateItemsCache();
      _safeNotify();

      var scanRoot = job.folderPath;
      final ensure = ensureFolderAccess;
      if (ensure != null) {
        final resolved = await ensure(job.folderPath);
        if (resolved != null && resolved.isNotEmpty) {
          final normalized = normalizePath(resolved);
          job.resolvedFolderPath = normalized;
          scanRoot = normalized;
        }
      }

      if (job.continueExistingOnly) {
        final outcomes = await _continueOutcomes(job);
        if (_disposed) return;
        await _finishWithOutcomes(job, outcomes);
        return;
      }

      final enumerated = await enumerateFolder(scanRoot);
      if (_disposed) return;
      final candidates = preferTagkinFixedSidecars(enumerated);
      if (candidates.isEmpty) {
        job.noSupportedMedia = true;
        job.phase = FolderIngestJobPhase.done;
        await _checkpointRemove(job.folderPath);
        await _bumpLibraryAndPublish(job);
        return;
      }
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

      final existingItems = List<Item>.from(await _listItemsCached());
      if (_disposed) return;
      final existingSourcePaths = <String>{
        for (final item in existingItems)
          if (localPathFromSourceRef(item.sourceRef) case final path?)
            normalizePath(path),
      };

      final nearDupThreshold =
          samplingPrefs?.call().nearDuplicateThreshold ??
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
          _itemsCache = null;
          _itemsCacheAt = null;
          if (isTagkinFixedSidecar(path)) {
            final original = _libraryItemForSidecarOriginal(
              existingItems,
              path,
            );
            if (original != null) {
              final item = await itemsRepository.retargetSourceRef(
                original.id,
                sourceRef: Uri.file(path).toString(),
                contentHash: candidate.contentHash,
                perceptualHash: candidate.perceptualHash,
              );
              final idx = existingItems.indexWhere((i) => i.id == item.id);
              if (idx >= 0) existingItems[idx] = item;
              if (_pipelineIncomplete(item)) {
                outcomes.add(IngestOutcome(path: path, item: item));
                job.continuedCount++;
              } else {
                job.alreadyInLibraryCount++;
              }
              job.registerDone++;
              _safeNotify();
              continue;
            }
          }
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

      final createdPaths = {
        for (final o in outcomes)
          if (o.succeeded) normalizePath(o.path),
      };
      for (final item in existingItems) {
        if (!_pipelineIncomplete(item)) continue;
        final path = localPathFromSourceRef(item.sourceRef);
        if (path == null || !_jobCoversPath(job, path)) {
          continue;
        }
        final normalized = normalizePath(path);
        if (createdPaths.contains(normalized)) continue;
        outcomes.add(IngestOutcome(path: normalized, item: item));
        job.continuedCount++;
      }

      await _finishWithOutcomes(job, outcomes);
    } catch (e) {
      job.phase = FolderIngestJobPhase.error;
      job.error = e;
      await _checkpointRemove(job.folderPath);
      await _bumpLibraryAndPublish(job);
    }
  }

  Future<List<IngestOutcome>> _continueOutcomes(FolderIngestJob job) async {
    final existingItems = await _listItemsCached();
    if (_disposed) return const [];
    final outcomes = <IngestOutcome>[];
    for (final item in existingItems) {
      if (!_pipelineIncomplete(item)) continue;
      final path = localPathFromSourceRef(item.sourceRef);
      if (path == null || !_jobCoversPath(job, path)) {
        continue;
      }
      outcomes.add(IngestOutcome(path: normalizePath(path), item: item));
      job.continuedCount++;
    }
    return outcomes;
  }

  Future<void> _finishWithOutcomes(
    FolderIngestJob job,
    List<IngestOutcome> outcomes,
  ) async {
    final succeeded = outcomes.where((o) => o.succeeded).length;
    final failedCreates = [
      for (final o in outcomes)
        if (!o.succeeded && o.error != null) o,
    ];
    if (succeeded == 0 && failedCreates.isNotEmpty && job.continuedCount == 0) {
      job.phase = FolderIngestJobPhase.error;
      job.error = failedCreates.first.error;
      await _checkpointRemove(job.folderPath);
      await _bumpLibraryAndPublish(job);
      return;
    }
    if (succeeded == 0) {
      job.phase = FolderIngestJobPhase.done;
      await _checkpointRemove(job.folderPath);
      // Reveal Faces + adopt membership (e.g. prior items under this root).
      await _bumpLibraryAndPublish(job);
      return;
    }

    // Adopt collection membership now; Faces still hides via isLoadingPath
    // until this job reaches done/error.
    job.phase = FolderIngestJobPhase.processing;
    job.pipelineDone = 0;
    job.pipelineTotal = succeeded;
    await _bumpLibraryAndPublish(job);
    if (_disposed) return;

    final prePass =
        prePassFactory?.call() ??
        PrePassController(
          itemsRepository: itemsRepository,
          samplingPrefs: samplingPrefs?.call(),
        );
    final upload =
        uploadFactory?.call() ??
        UploadController(itemsRepository: itemsRepository);
    final linker =
        whoFaceLinkerFactory?.call() ??
        () {
          final prefs = samplingPrefs?.call();
          return WhoFaceLinker(
            items: itemsRepository,
            autoConfirmMinConfidencePercent:
                prefs != null && prefs.autoConfirmHighConfidencePersonMatches
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

    void flushLiveItems() {
      for (final o in upload.outcomes) {
        final item = o.item;
        if (item != null) _emitItemUpdated(item);
      }
      for (final o in pipeline.analyzeOutcomes) {
        final item = o.item;
        if (item != null) _emitItemUpdated(item);
      }
    }

    void syncPipelinePhase() {
      final phase = pipeline.phase;
      job.pipelineDone = pipeline.itemIndex;
      job.pipelineTotal = pipeline.itemTotal;
      if (phase == PostIngestPipelinePhase.runningPrePass ||
          phase == PostIngestPipelinePhase.runningUpload ||
          phase == PostIngestPipelinePhase.runningAnalyze) {
        job.phase = FolderIngestJobPhase.processing;
      } else if (phase == PostIngestPipelinePhase.error) {
        job.phase = FolderIngestJobPhase.error;
        job.error = pipeline.error;
      }
      // Job stays `processing` until start() returns — pipeline `done`
      // after item 1 must not mark the folder job complete.
      flushLiveItems();
      _safeNotify();
    }

    upload.addListener(flushLiveItems);
    pipeline.addListener(syncPipelinePhase);
    try {
      await pipeline.start(
        ingestOutcomes: outcomes,
        isUsageBlocked: isUsageBlocked,
        onPaidReject: onPaidReject,
      );
      await pipeline.retryFailedAnalyzeOnce();
    } finally {
      upload.removeListener(flushLiveItems);
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
    await _checkpointRemove(job.folderPath);
    await _bumpLibraryAndPublish(job);
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
      onPaidReject: (code, message) {
        try {
          ref.read(usageControllerProvider).noteAnalyzeReject(code, message);
        } catch (_) {
          // Faces widget tests may lack a signed-in usage controller.
        }
      },
      enumerateFolder: ref.read(mediaEnumeratorProvider),
      contentHasher: ref.read(contentHasherProvider),
      perceptualHasher: ref.read(perceptualHasherProvider),
      samplingPrefs: () => ref.read(desktopPrefsProvider),
      currentCollectionId: () {
        final cols = ref.read(collectionsControllerProvider);
        return cols.sessionReady ? cols.current.id : null;
      },
      collectionIdForFolder: (path) {
        return ref.read(collectionsControllerProvider).ownerCollectionId(path);
      },
      onLibraryMembershipPublish:
          (
            folderPath, {
            collectionId,
            claimFromOtherCollections = const {},
          }) async {
            final cols = ref.read(collectionsControllerProvider);
            final table = ref.read(libraryTableControllerProvider);
            await publishCollectionMembershipFromLibrary(
              items: ref.read(itemsRepositoryProvider),
              cols: cols,
              table: table,
              claimUnderFolder: folderPath,
              claimForCollectionId: collectionId,
              stealFolders: claimFromOtherCollections,
            );
          },
      onItemUpdated: (item) {
        ref.read(libraryTableControllerProvider).adoptItem(item);
      },
      accountId: () => ref.read(signedInAccountIdProvider),
      checkpointStore: activeFolderIngestStore,
      ensureFolderAccess: ensureIngestFolderAccess,
      bookmarkedFolders: folderBookmarkStore.listFolders,
      physicalMemoryBytes: probePhysicalMemoryBytes,
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
    signedInAccountIdProvider,
  ],
);
