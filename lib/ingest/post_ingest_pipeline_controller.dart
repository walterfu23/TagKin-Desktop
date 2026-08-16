import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/api/jobs_repository.dart';
import 'package:tagkin_desktop/app_shell.dart'
    show itemsRepositoryProvider, jobsRepositoryProvider;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/batch_ingest_controller.dart';
import 'package:tagkin_desktop/ingest/upload_controller.dart';
import 'package:tagkin_desktop/persons/who_face_linker.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';
import 'package:tagkin_desktop/prepass/prepass_controller.dart';
import 'package:tagkin_desktop/usage/usage_gate.dart';

/// High-level phases of the automatic D4 → D5 → D7 chain after folder ingest.
enum PostIngestPipelinePhase {
  idle,
  runningPrePass,
  runningUpload,
  runningAnalyze,
  done,
  skippedUpload,
  error,
}

/// One photo's outcome after the pipeline's analyze stage.
class AnalyzeOutcome {
  const AnalyzeOutcome({
    required this.itemId,
    this.item,
    this.error,
  });

  final String itemId;
  final Item? item;
  final Object? error;

  bool get succeeded => item != null && error == null;
}

/// Chains client pre-pass → upload → photo analyze after batch `POST /items`.
///
/// One item at a time (pre-pass → upload → analyze) so peak memory stays
/// near a single file and the first tagged row can appear before later
/// items start. Upload + analyze are skipped when [usageBlocked] is true
/// (D6). Analyze is photo-only (R9). Continues past per-item failures
/// within each stage.
class PostIngestPipelineController extends ChangeNotifier {
  PostIngestPipelineController({
    required this.prePass,
    required this.upload,
    required this.jobsRepository,
    required this.whoFaceLinker,
  });

  final PrePassController prePass;
  final UploadController upload;
  final JobsRepository jobsRepository;
  final WhoFaceLinker whoFaceLinker;

  PostIngestPipelinePhase phase = PostIngestPipelinePhase.idle;
  List<AnalyzeOutcome> analyzeOutcomes = const [];
  Object? error;
  bool _started = false;

  /// 1-based index of the item currently in the chain; 0 before start.
  int itemIndex = 0;
  int itemTotal = 0;

  void Function(String? code, String message)? _onPaidReject;

  bool get isBusy =>
      phase == PostIngestPipelinePhase.runningPrePass ||
      phase == PostIngestPipelinePhase.runningUpload ||
      phase == PostIngestPipelinePhase.runningAnalyze;

  bool get hasStageFailures {
    final prePassFail = prePass.outcomes.any((o) => !o.succeeded);
    final uploadFail = upload.outcomes.any((o) => !o.succeeded);
    final analyzeFail = analyzeOutcomes.any((o) => !o.succeeded);
    return prePassFail || uploadFail || analyzeFail;
  }

  bool get canRetry =>
      !isBusy &&
      (phase == PostIngestPipelinePhase.done ||
          phase == PostIngestPipelinePhase.skippedUpload ||
          phase == PostIngestPipelinePhase.error) &&
      (hasStageFailures || phase == PostIngestPipelinePhase.skippedUpload);

  /// Starts the chain once per ingest session. Processes one item fully
  /// (pre-pass → upload → analyze) before the next so peak memory stays
  /// near a single file. No-ops if already started.
  Future<void> start({
    required List<IngestOutcome> ingestOutcomes,
    bool usageBlocked = false,
    bool Function()? isUsageBlocked,
    void Function(String? code, String message)? onPaidReject,
  }) async {
    if (_started || phase != PostIngestPipelinePhase.idle) return;
    _started = true;
    _onPaidReject = onPaidReject;
    await _run(
      ingestOutcomes: ingestOutcomes,
      isUsageBlocked: () => usageBlocked || (isUsageBlocked?.call() ?? false),
    );
  }

  /// Re-runs the full chain after a partial failure or usage skip.
  Future<void> retryFailed({
    required List<IngestOutcome> ingestOutcomes,
    bool usageBlocked = false,
    bool Function()? isUsageBlocked,
    void Function(String? code, String message)? onPaidReject,
  }) async {
    if (isBusy || !canRetry) return;
    prePass.reset();
    upload.reset();
    analyzeOutcomes = const [];
    itemIndex = 0;
    itemTotal = 0;
    error = null;
    _started = true;
    _onPaidReject = onPaidReject;
    phase = PostIngestPipelinePhase.idle;
    notifyListeners();
    await _run(
      ingestOutcomes: ingestOutcomes,
      isUsageBlocked: () => usageBlocked || (isUsageBlocked?.call() ?? false),
    );
  }

  Future<void> _run({
    required List<IngestOutcome> ingestOutcomes,
    required bool Function() isUsageBlocked,
  }) async {
    final succeeded =
        ingestOutcomes.where((o) => o.succeeded && o.item != null).toList();
    itemTotal = succeeded.length;
    itemIndex = 0;
    if (succeeded.isEmpty) {
      phase = PostIngestPipelinePhase.done;
      notifyListeners();
      return;
    }

    prePass.reset();
    upload.reset();
    analyzeOutcomes = const [];
    var skipPaid = isUsageBlocked();
    var anyPaid = false;

    try {
      for (final one in succeeded) {
        itemIndex++;
        phase = PostIngestPipelinePhase.runningPrePass;
        notifyListeners();
        await prePass.run([one], append: true);

        skipPaid = skipPaid || isUsageBlocked();
        if (skipPaid) {
          prePass.frameSamplesByItemId.clear();
          continue;
        }

        phase = PostIngestPipelinePhase.runningUpload;
        notifyListeners();
        await upload.run(
          prePass.outcomes
              .where((o) => o.itemId == one.item!.id)
              .toList(),
          prePass.frameSamplesByItemId,
          append: true,
        );
        anyPaid = true;

        phase = PostIngestPipelinePhase.runningAnalyze;
        notifyListeners();
        final stopPaid = await _analyzePhotos([one]);
        prePass.frameSamplesByItemId.clear();
        if (stopPaid) break;
      }

      phase = !anyPaid && skipPaid
          ? PostIngestPipelinePhase.skippedUpload
          : PostIngestPipelinePhase.done;
      notifyListeners();
    } catch (e) {
      error = e;
      phase = PostIngestPipelinePhase.error;
      notifyListeners();
    }
  }

  /// Returns true when a hard credit stop should halt the rest of the chain.
  Future<bool> _analyzePhotos(List<IngestOutcome> ingestOutcomes) async {
    final typeById = <String, ItemType>{
      for (final o in ingestOutcomes)
        if (o.item != null) o.item!.id: o.item!.type,
    };
    final currentIds = typeById.keys.toSet();
    final photoUploads = upload.outcomes
        .where(
          (o) =>
              o.succeeded &&
              currentIds.contains(o.itemId) &&
              typeById[o.itemId] == ItemType.photo,
        )
        .toList();

    final newOutcomes = List<AnalyzeOutcome>.from(analyzeOutcomes);
    for (final uploadOutcome in photoUploads) {
      try {
        final result =
            await jobsRepository.analyzeItem(uploadOutcome.itemId);
        newOutcomes.add(
          AnalyzeOutcome(
            itemId: uploadOutcome.itemId,
            item: result.item,
          ),
        );
        analyzeOutcomes = List.unmodifiable(newOutcomes);
        notifyListeners();
        try {
          await whoFaceLinker.linkWhoFacesForItem(result.item);
        } catch (_) {
          // Best-effort; analyze already succeeded.
        }
      } catch (e) {
        newOutcomes.add(
          AnalyzeOutcome(
            itemId: uploadOutcome.itemId,
            error: e,
          ),
        );
        analyzeOutcomes = List.unmodifiable(newOutcomes);
        notifyListeners();
        if (e is ApiException && isCreditRejectCode(e.code)) {
          _onPaidReject?.call(e.code, e.message);
          if (isHardCreditStop(e.code)) return true;
        }
      }
    }
    return false;
  }

  void reset() {
    _started = false;
    phase = PostIngestPipelinePhase.idle;
    analyzeOutcomes = const [];
    itemIndex = 0;
    itemTotal = 0;
    error = null;
    notifyListeners();
  }
}

final postIngestPipelineControllerProvider =
    Provider.autoDispose<PostIngestPipelineController>(
  (ref) {
    final prefs = ref.watch(desktopPrefsProvider);
    final controller = PostIngestPipelineController(
      prePass: ref.watch(prePassControllerProvider),
      upload: ref.watch(uploadControllerProvider),
      jobsRepository: ref.watch(jobsRepositoryProvider),
      whoFaceLinker: WhoFaceLinker(
        items: ref.watch(itemsRepositoryProvider),
        autoConfirmMinConfidencePercent:
            prefs.autoConfirmHighConfidencePersonMatches
                ? prefs.autoConfirmMinConfidencePercent
                : null,
      ),
    );
    ref.onDispose(controller.dispose);
    return controller;
  },
  dependencies: [
    prePassControllerProvider,
    uploadControllerProvider,
    jobsRepositoryProvider,
    itemsRepositoryProvider,
    desktopPrefsProvider,
  ],
);
