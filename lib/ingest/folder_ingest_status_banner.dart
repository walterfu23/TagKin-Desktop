import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/ingest/folder_ingest_queue.dart';
import 'package:tagkin_desktop/library/folder_remove_queue.dart';

/// Global folder activity progress — ingest + remove, visible from any signed-in page.
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
    final ingest = ref.watch(folderIngestQueueProvider);
    final remove = ref.watch(folderRemoveQueueProvider);
    return ListenableBuilder(
      listenable: Listenable.merge([ingest, remove]),
      builder: (context, _) {
        if (ingest.jobs.isEmpty && remove.jobs.isEmpty) {
          return const SizedBox.shrink();
        }
        final scheme = Theme.of(context).colorScheme;
        final loadingActive = ingest.activeJobCount;
        final removingActive = remove.activeJobCount;
        final active = loadingActive + removingActive;
        final summary = _summary(
          loadingActive: loadingActive,
          removingActive: removingActive,
          ingestFinished: ingest.jobs.isNotEmpty && loadingActive == 0,
          removeFinished: remove.jobs.isNotEmpty && removingActive == 0,
        );

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
                          key: Key(
                            removingActive > 0
                                ? 'folder-remove-status-summary'
                                : 'folder-ingest-status-summary',
                          ),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      if (active == 0)
                        TextButton(
                          key: const Key('folder-ingest-status-dismiss'),
                          onPressed: () {
                            ingest.dismissFinished();
                            remove.dismissFinished();
                          },
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
              if (_expanded) ...[
                for (final job in ingest.jobs)
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
                            onPressed: () => ingest.dismissJob(job),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                  ),
                for (final job in remove.jobs)
                  ListTile(
                    key: Key('folder-remove-job-${job.folderPath}'),
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
                            onPressed: () => remove.dismissJob(job),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  static String _summary({
    required int loadingActive,
    required int removingActive,
    required bool ingestFinished,
    required bool removeFinished,
  }) {
    final parts = <String>[];
    if (loadingActive > 0) {
      parts.add(
        'Loading $loadingActive folder${loadingActive == 1 ? '' : 's'}…',
      );
    }
    if (removingActive > 0) {
      parts.add(
        'Removing $removingActive folder${removingActive == 1 ? '' : 's'}…',
      );
    }
    if (parts.isNotEmpty) return parts.join(' · ');

    if (ingestFinished && removeFinished) {
      return 'Folder activity finished';
    }
    if (removeFinished) return 'Folder remove finished';
    if (ingestFinished) return 'Folder ingest finished';
    return 'Folder activity finished';
  }
}
