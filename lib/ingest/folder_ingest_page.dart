import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/batch_ingest_controller.dart';
import 'package:tagkin_desktop/ingest/dedup.dart';
import 'package:tagkin_desktop/ingest/post_ingest_pipeline_controller.dart';
import 'package:tagkin_desktop/ingest/upload_controller.dart';
import 'package:tagkin_desktop/prepass/prepass_controller.dart';
import 'package:tagkin_desktop/usage/usage_banner.dart';
import 'package:tagkin_desktop/usage/usage_controller.dart';
import 'package:tagkin_desktop/usage/usage_gate.dart';

/// D3 Local Folder Ingest & Batch + D4 Client Pre-pass + D5 Upload & Grants +
/// D7 analyze: pick a folder → review deduped candidates → batch `POST /items`
/// (refs/hashes only) → automatic classic pre-pass → direct model-host upload
/// + `analysisRef` recording → photo analyze (R9).
///
/// D6 gates the folder-pick and the post-ingest upload/analyze stages on
/// [UsageGate.blocked].
///
/// Pops `true` when at least one item was created, so the caller can
/// refresh the library list; pops `false`/`null` otherwise.
class FolderIngestPage extends ConsumerStatefulWidget {
  const FolderIngestPage({super.key});

  @override
  ConsumerState<FolderIngestPage> createState() => _FolderIngestPageState();
}

class _FolderIngestPageState extends ConsumerState<FolderIngestPage> {
  /// Ensures the post-ingest pipeline starts at most once per confirm session
  /// (DoneView remounts must not kick off a second chain).
  bool _pipelineArmed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(usageControllerProvider).load();
    });
  }

  /// Called from [_DoneView] once when the done screen appears.
  void tryStartPipeline({
    required BatchIngestController controller,
    required PostIngestPipelineController pipeline,
    required UsageGate gate,
  }) {
    if (_pipelineArmed) return;
    if (controller.phase != BatchIngestPhase.done) return;
    final succeeded =
        controller.outcomes.where((o) => o.succeeded).length;
    if (succeeded == 0) return;
    _pipelineArmed = true;
    pipeline.start(
      ingestOutcomes: controller.outcomes,
      usageBlocked: gate.blocked,
    );
  }

  void _resetPipelineArm() {
    _pipelineArmed = false;
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(batchIngestControllerProvider);
    final prePass = ref.watch(prePassControllerProvider);
    final upload = ref.watch(uploadControllerProvider);
    final pipeline = ref.watch(postIngestPipelineControllerProvider);
    final usage = ref.watch(usageControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Add from folder')),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          controller,
          prePass,
          upload,
          pipeline,
          usage,
        ]),
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UsageBanner(gate: usage.gate),
            Expanded(
              child: _FolderIngestBody(
                controller: controller,
                prePass: prePass,
                upload: upload,
                pipeline: pipeline,
                gate: usage.gate,
                onTryStartPipeline: () => tryStartPipeline(
                  controller: controller,
                  pipeline: pipeline,
                  gate: usage.gate,
                ),
                onIngestAnotherFolder: _resetPipelineArm,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderIngestBody extends StatelessWidget {
  const _FolderIngestBody({
    required this.controller,
    required this.prePass,
    required this.upload,
    required this.pipeline,
    required this.gate,
    required this.onTryStartPipeline,
    required this.onIngestAnotherFolder,
  });

  final BatchIngestController controller;
  final PrePassController prePass;
  final UploadController upload;
  final PostIngestPipelineController pipeline;
  final UsageGate gate;
  final VoidCallback onTryStartPipeline;
  final VoidCallback onIngestAnotherFolder;

  @override
  Widget build(BuildContext context) {
    switch (controller.phase) {
      case BatchIngestPhase.idle:
        return _IdleView(controller: controller, gate: gate);
      case BatchIngestPhase.scanning:
        return _ScanningView(controller: controller);
      case BatchIngestPhase.reviewing:
        return _ReviewView(controller: controller);
      case BatchIngestPhase.ingesting:
        return _IngestingView(controller: controller);
      case BatchIngestPhase.done:
        return _DoneView(
          controller: controller,
          prePass: prePass,
          upload: upload,
          pipeline: pipeline,
          gate: gate,
          onTryStartPipeline: onTryStartPipeline,
          onIngestAnotherFolder: onIngestAnotherFolder,
        );
      case BatchIngestPhase.error:
        return _ErrorView(controller: controller);
    }
  }
}

class _IdleView extends StatelessWidget {
  const _IdleView({
    required this.controller,
    required this.gate,
  });

  final BatchIngestController controller;
  final UsageGate gate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Pick a local folder to scan for photos and videos.\n'
              'Files never leave this device during scanning.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('pick-folder-button'),
              onPressed: gate.blocked ? null : controller.pickAndScan,
              child: const Text('Pick folder…'),
            ),
          ],
        ),
      ),
    );
  }
}
class _ScanningView extends StatelessWidget {
  const _ScanningView({required this.controller});

  final BatchIngestController controller;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          key: const Key('ingest-scanning'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Scanning ${controller.folderPath ?? ''}…'),
          ],
        ),
      ),
    );
  }
}

class _ReviewView extends StatelessWidget {
  const _ReviewView({required this.controller});

  final BatchIngestController controller;

  @override
  Widget build(BuildContext context) {
    final result = controller.dedupResult!;
    final selectedCount = controller.selectedPaths.length;
    return Column(
      key: const Key('ingest-review'),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Found ${controller.totalFound} file(s): '
            '${result.representatives.length} new, '
            '${result.skipped.length} skipped (duplicate/already in library).',
            key: const Key('ingest-summary'),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final rep in result.representatives)
                CheckboxListTile(
                  key: Key('candidate-row-${rep.candidate.path}'),
                  value: controller.selectedPaths.contains(rep.candidate.path),
                  onChanged: (_) =>
                      controller.toggleSelection(rep.candidate.path),
                  title: Text(rep.candidate.path),
                  subtitle: Text(rep.candidate.type.wire),
                ),
              for (final skip in result.skipped)
                ListTile(
                  key: Key('skipped-row-${skip.candidate.candidate.path}'),
                  title: Text(skip.candidate.candidate.path),
                  subtitle: Text(_skipReasonLabel(skip.reason)),
                  enabled: false,
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            key: const Key('confirm-ingest-button'),
            onPressed:
                selectedCount == 0 ? null : controller.confirmIngest,
            child: Text('Add $selectedCount item(s)'),
          ),
        ),
      ],
    );
  }

  static String _skipReasonLabel(SkipReason reason) {
    switch (reason) {
      case SkipReason.duplicateInBatch:
        return 'Duplicate of another file in this folder';
      case SkipReason.existingInLibrary:
        return 'Already in your library';
    }
  }
}

class _IngestingView extends StatelessWidget {
  const _IngestingView({required this.controller});

  final BatchIngestController controller;

  @override
  Widget build(BuildContext context) {
    final total = controller.selectedPaths.length;
    final done = controller.outcomes.length;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          key: const Key('ingest-progress'),
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              value: total == 0 ? null : done / total,
            ),
            const SizedBox(height: 16),
            Text('Adding items… $done of $total'),
          ],
        ),
      ),
    );
  }
}

class _DoneView extends StatefulWidget {
  const _DoneView({
    required this.controller,
    required this.prePass,
    required this.upload,
    required this.pipeline,
    required this.gate,
    required this.onTryStartPipeline,
    required this.onIngestAnotherFolder,
  });

  final BatchIngestController controller;
  final PrePassController prePass;
  final UploadController upload;
  final PostIngestPipelineController pipeline;
  final UsageGate gate;
  final VoidCallback onTryStartPipeline;
  final VoidCallback onIngestAnotherFolder;

  @override
  State<_DoneView> createState() => _DoneViewState();
}

class _DoneViewState extends State<_DoneView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onTryStartPipeline();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final prePass = widget.prePass;
    final upload = widget.upload;
    final pipeline = widget.pipeline;
    final gate = widget.gate;
    final onIngestAnotherFolder = widget.onIngestAnotherFolder;

    final succeeded = controller.outcomes.where((o) => o.succeeded).length;
    final failed = controller.outcomes.length - succeeded;
    final prePassRunning =
        pipeline.phase == PostIngestPipelinePhase.runningPrePass ||
            prePass.phase == PrePassPhase.running;
    final prePassDone = prePass.phase == PrePassPhase.done;
    final prePassOk = prePass.outcomes.where((o) => o.succeeded).length;
    final prePassFail = prePass.outcomes.length - prePassOk;
    final uploadRunning =
        pipeline.phase == PostIngestPipelinePhase.runningUpload ||
            upload.phase == UploadPhase.running;
    final uploadDone = upload.phase == UploadPhase.done;
    final uploadOk = upload.outcomes.where((o) => o.succeeded).length;
    final uploadFail = upload.outcomes.length - uploadOk;
    final analyzeRunning =
        pipeline.phase == PostIngestPipelinePhase.runningAnalyze;
    final analyzeDone = pipeline.phase == PostIngestPipelinePhase.done ||
        pipeline.phase == PostIngestPipelinePhase.skippedUpload ||
        pipeline.phase == PostIngestPipelinePhase.error;
    final analyzeOk =
        pipeline.analyzeOutcomes.where((o) => o.succeeded).length;
    final analyzeFail = pipeline.analyzeOutcomes.length - analyzeOk;
    final typeById = <String, ItemType>{
      for (final o in controller.outcomes)
        if (o.item != null) o.item!.id: o.item!.type,
    };
    final photoUploadCount = upload.outcomes
        .where(
          (o) => o.succeeded && typeById[o.itemId] == ItemType.photo,
        )
        .length;
    final skippedUpload =
        pipeline.phase == PostIngestPipelinePhase.skippedUpload;
    final busy = pipeline.isBusy;
    final showRetry = pipeline.canRetry;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          key: const Key('ingest-done'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              failed == 0
                  ? 'Added $succeeded item(s).'
                  : 'Added $succeeded item(s); $failed failed.',
              key: const Key('ingest-done-summary'),
              textAlign: TextAlign.center,
            ),
            if (prePassRunning) ...[
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
              const SizedBox(height: 8),
              Text(
                'Running client pre-pass… '
                '${prePass.outcomes.length} of $succeeded',
                key: const Key('prepass-progress'),
              ),
            ],
            if (prePassDone) ...[
              const SizedBox(height: 12),
              Text(
                prePassFail == 0
                    ? 'Pre-pass recorded for $prePassOk item(s).'
                    : 'Pre-pass: $prePassOk ok; $prePassFail failed.',
                key: const Key('prepass-done-summary'),
                textAlign: TextAlign.center,
              ),
              if (prePassFail > 0) ...[
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: 480, maxHeight: 160),
                  child: ListView(
                    key: const Key('prepass-failures'),
                    shrinkWrap: true,
                    children: [
                      for (final o
                          in prePass.outcomes.where((o) => !o.succeeded))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '${o.path}: ${o.error}',
                            key: Key('prepass-failure-${o.itemId}'),
                            textAlign: TextAlign.left,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
            if (uploadRunning) ...[
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
              const SizedBox(height: 8),
              Text(
                'Uploading for analysis… '
                '${upload.outcomes.length} of $prePassOk',
                key: const Key('upload-progress'),
              ),
            ],
            if (uploadDone) ...[
              const SizedBox(height: 12),
              Text(
                uploadFail == 0
                    ? 'Uploaded $uploadOk item(s) for analysis.'
                    : 'Upload: $uploadOk ok; $uploadFail failed.',
                key: const Key('upload-done-summary'),
                textAlign: TextAlign.center,
              ),
            ],
            if (skippedUpload) ...[
              const SizedBox(height: 12),
              Text(
                'Upload and analyze skipped — usage limit or kill switch.',
                key: const Key('pipeline-skipped-upload'),
                textAlign: TextAlign.center,
              ),
            ],
            if (analyzeRunning) ...[
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
              const SizedBox(height: 8),
              Text(
                'Analyzing… '
                '${pipeline.analyzeOutcomes.length} of $photoUploadCount',
                key: const Key('analyze-progress'),
              ),
            ],
            if (analyzeDone &&
                pipeline.phase == PostIngestPipelinePhase.done) ...[
              const SizedBox(height: 12),
              Text(
                analyzeFail == 0
                    ? 'Analyzed $analyzeOk photo(s).'
                    : 'Analyze: $analyzeOk ok; $analyzeFail failed.',
                key: const Key('analyze-done-summary'),
                textAlign: TextAlign.center,
              ),
            ],
            if (pipeline.phase == PostIngestPipelinePhase.error) ...[
              const SizedBox(height: 12),
              Text(
                'Pipeline error: ${pipeline.error}',
                key: const Key('pipeline-error'),
                textAlign: TextAlign.center,
              ),
            ],
            if (showRetry) ...[
              const SizedBox(height: 12),
              FilledButton.tonal(
                key: const Key('pipeline-retry-button'),
                onPressed: busy
                    ? null
                    : () => pipeline.retryFailed(
                          ingestOutcomes: controller.outcomes,
                          usageBlocked: gate.blocked,
                        ),
                child: const Text('Retry failed'),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  key: const Key('ingest-another-folder'),
                  onPressed: busy
                      ? null
                      : () {
                          onIngestAnotherFolder();
                          pipeline.reset();
                          upload.reset();
                          prePass.reset();
                          controller.reset();
                        },
                  child: const Text('Ingest another folder'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  key: const Key('ingest-done-close'),
                  onPressed: busy
                      ? null
                      : () => Navigator.of(context).pop(succeeded > 0),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.controller});

  final BatchIngestController controller;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Could not scan folder: ${controller.error}',
              key: const Key('ingest-error'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('ingest-error-retry'),
              onPressed: controller.reset,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
