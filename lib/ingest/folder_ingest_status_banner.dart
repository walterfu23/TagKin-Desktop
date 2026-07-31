import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/ingest/folder_ingest_queue.dart';

/// Global folder-ingest progress — visible from any signed-in page.
class FolderIngestStatusBanner extends ConsumerStatefulWidget {
  const FolderIngestStatusBanner({super.key});

  @override
  ConsumerState<FolderIngestStatusBanner> createState() =>
      _FolderIngestStatusBannerState();
}

class _FolderIngestStatusBannerState
    extends ConsumerState<FolderIngestStatusBanner> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(folderIngestQueueProvider);
    return ListenableBuilder(
      listenable: queue,
      builder: (context, _) {
        if (queue.jobs.isEmpty) {
          return const SizedBox.shrink();
        }
        final scheme = Theme.of(context).colorScheme;
        final active = queue.activeJobCount;
        final summary = active > 0
            ? 'Loading $active folder${active == 1 ? '' : 's'}…'
            : 'Folder ingest finished';

        return Material(
          key: const Key('folder-ingest-status-banner'),
          color: scheme.surfaceContainerHighest,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      if (active > 0) ...[
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                      ] else
                        Icon(
                          Icons.check_circle_outline,
                          size: 18,
                          color: scheme.primary,
                        ),
                      if (active == 0) const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          summary,
                          key: const Key('folder-ingest-status-summary'),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      if (active == 0)
                        TextButton(
                          key: const Key('folder-ingest-status-dismiss'),
                          onPressed: queue.dismissFinished,
                          child: const Text('Dismiss'),
                        ),
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        key: const Key('folder-ingest-status-expand'),
                      ),
                    ],
                  ),
                ),
              ),
              if (_expanded)
                for (final job in queue.jobs)
                  ListTile(
                    dense: true,
                    title: Text(job.folderLabel),
                    subtitle: Text(
                      job.error != null
                          ? '${job.statusLabel}: ${job.error}'
                          : job.statusLabel,
                    ),
                    trailing: job.isActive
                        ? null
                        : IconButton(
                            tooltip: 'Dismiss',
                            onPressed: () => queue.dismissJob(job),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                  ),
            ],
          ),
        );
      },
    );
  }
}
