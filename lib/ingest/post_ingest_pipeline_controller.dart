import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/jobs_repository.dart';
import 'package:tagkin_desktop/app_shell.dart' show jobsRepositoryProvider;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/batch_ingest_controller.dart';
import 'package:tagkin_desktop/ingest/upload_controller.dart';
import 'package:tagkin_desktop/prepass/prepass_controller.dart';

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
/// Upload + analyze are skipped when [usageBlocked] is true (D6). Analyze is
/// photo-only (R9). Continues past per-item failures within each stage.
class PostIngestPipelineController extends ChangeNotifier {
  PostIngestPipelineController({
    required this.prePass,
    required this.upload,
    required this.jobsRepository,
  });

  final PrePassController prePass;
  final UploadController upload;
  final JobsRepository jobsRepository;

  PostIngestPipelinePhase phase = PostIngestPipelinePhase.idle;
  List<AnalyzeOutcome> analyzeOutcomes = const [];
  Object? error;
  bool _started = false;

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

  /// Starts the chain once per ingest session. No-ops if already started or
  /// there are no successful creates.
  Future<void> start({
    required List<IngestOutcome> ingestOutcomes,
    required bool usageBlocked,
  }) async {
    if (_started || phase != PostIngestPipelinePhase.idle) return;
    _started = true;
    await _run(
      ingestOutcomes: ingestOutcomes,
      usageBlocked: usageBlocked,
    );
  }

  /// Re-runs the full chain after a partial failure or usage skip.
  Future<void> retryFailed({
    required List<IngestOutcome> ingestOutcomes,
    required bool usageBlocked,
  }) async {
    if (isBusy || !canRetry) return;
    prePass.reset();
    upload.reset();
    analyzeOutcomes = const [];
    error = null;
    _started = true;
    phase = PostIngestPipelinePhase.idle;
    notifyListeners();
    await _run(
      ingestOutcomes: ingestOutcomes,
      usageBlocked: usageBlocked,
    );
  }

  Future<void> _run({
    required List<IngestOutcome> ingestOutcomes,
    required bool usageBlocked,
  }) async {
    final succeeded =
        ingestOutcomes.where((o) => o.succeeded && o.item != null).toList();
    if (succeeded.isEmpty) {
      phase = PostIngestPipelinePhase.done;
      notifyListeners();
      return;
    }

    try {
      phase = PostIngestPipelinePhase.runningPrePass;
      notifyListeners();
      await prePass.run(ingestOutcomes);

      if (usageBlocked) {
        phase = PostIngestPipelinePhase.skippedUpload;
        notifyListeners();
        return;
      }

      phase = PostIngestPipelinePhase.runningUpload;
      notifyListeners();
      await upload.run(prePass.outcomes, prePass.frameSamplesByItemId);

      phase = PostIngestPipelinePhase.runningAnalyze;
      notifyListeners();
      await _analyzePhotos(ingestOutcomes);

      phase = PostIngestPipelinePhase.done;
      notifyListeners();
    } catch (e) {
      error = e;
      phase = PostIngestPipelinePhase.error;
      notifyListeners();
    }
  }

  Future<void> _analyzePhotos(List<IngestOutcome> ingestOutcomes) async {
    final typeById = <String, ItemType>{
      for (final o in ingestOutcomes)
        if (o.item != null) o.item!.id: o.item!.type,
    };
    final photoUploads = upload.outcomes
        .where(
          (o) => o.succeeded && typeById[o.itemId] == ItemType.photo,
        )
        .toList();

    final newOutcomes = <AnalyzeOutcome>[];
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
      } catch (e) {
        newOutcomes.add(
          AnalyzeOutcome(
            itemId: uploadOutcome.itemId,
            error: e,
          ),
        );
      }
      analyzeOutcomes = List.unmodifiable(newOutcomes);
      notifyListeners();
    }
  }

  void reset() {
    _started = false;
    phase = PostIngestPipelinePhase.idle;
    analyzeOutcomes = const [];
    error = null;
    notifyListeners();
  }
}

final postIngestPipelineControllerProvider =
    Provider.autoDispose<PostIngestPipelineController>(
  (ref) {
    final controller = PostIngestPipelineController(
      prePass: ref.watch(prePassControllerProvider),
      upload: ref.watch(uploadControllerProvider),
      jobsRepository: ref.watch(jobsRepositoryProvider),
    );
    ref.onDispose(controller.dispose);
    return controller;
  },
  dependencies: [
    prePassControllerProvider,
    uploadControllerProvider,
    jobsRepositoryProvider,
  ],
);
