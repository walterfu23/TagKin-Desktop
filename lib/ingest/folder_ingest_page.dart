import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/ingest/batch_ingest_controller.dart';
import 'package:tagkin_desktop/ingest/dedup.dart';

/// D3 Local Folder Ingest & Batch: pick a folder → review deduped
/// candidates → batch `POST /items` (refs/hashes only, R1/R7).
///
/// Pops `true` when at least one item was created, so the caller can
/// refresh the library list; pops `false`/`null` otherwise.
class FolderIngestPage extends ConsumerWidget {
  const FolderIngestPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(batchIngestControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Add from folder')),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => _FolderIngestBody(controller: controller),
      ),
    );
  }
}

class _FolderIngestBody extends StatelessWidget {
  const _FolderIngestBody({required this.controller});

  final BatchIngestController controller;

  @override
  Widget build(BuildContext context) {
    switch (controller.phase) {
      case BatchIngestPhase.idle:
        return _IdleView(controller: controller);
      case BatchIngestPhase.scanning:
        return _ScanningView(controller: controller);
      case BatchIngestPhase.reviewing:
        return _ReviewView(controller: controller);
      case BatchIngestPhase.ingesting:
        return _IngestingView(controller: controller);
      case BatchIngestPhase.done:
        return _DoneView(controller: controller);
      case BatchIngestPhase.error:
        return _ErrorView(controller: controller);
    }
  }
}

class _IdleView extends StatelessWidget {
  const _IdleView({required this.controller});

  final BatchIngestController controller;

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
              onPressed: controller.pickAndScan,
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

class _DoneView extends StatelessWidget {
  const _DoneView({required this.controller});

  final BatchIngestController controller;

  @override
  Widget build(BuildContext context) {
    final succeeded = controller.outcomes.where((o) => o.succeeded).length;
    final failed = controller.outcomes.length - succeeded;
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
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  key: const Key('ingest-another-folder'),
                  onPressed: controller.reset,
                  child: const Text('Ingest another folder'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  key: const Key('ingest-done-close'),
                  onPressed: () => Navigator.of(context).pop(succeeded > 0),
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
