import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/ingest/folder_ingest_queue.dart';
import 'package:tagkin_desktop/library/folder_remove_queue.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';

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
    final cols = ref.watch(collectionsControllerProvider);
    return ListenableBuilder(
      listenable: Listenable.merge([ingest, remove, cols]),
      builder: (context, _) {
        final collectionId =
            cols.sessionReady ? cols.current.id : null;
        final ingestJobs = ingest.jobsForCollection(collectionId);
        final removeJobs = remove.jobsForCollection(collectionId);
        if (ingestJobs.isEmpty && removeJobs.isEmpty) {
          return const SizedBox.shrink();
        }
        final scheme = Theme.of(context).colorScheme;
        final loadingActive =
            ingest.activeJobCountForCollection(collectionId);
        final removingActive =
            remove.activeJobCountForCollection(collectionId);
        final active = loadingActive + removingActive;
        final ingestAlreadyInLibrary = ingestJobs.isNotEmpty &&
            ingestJobs.every(
              (j) =>
                  !j.isActive &&
                  j.phase == FolderIngestJobPhase.done &&
                  j.createdCount == 0 &&
                  j.continuedCount == 0 &&
                  j.alreadyInLibraryCount > 0,
            );
        final ingestNoMedia = ingestJobs.isNotEmpty &&
            ingestJobs.every(
              (j) =>
                  !j.isActive &&
                  j.phase == FolderIngestJobPhase.done &&
                  j.noSupportedMedia,
            );
        final ingestNothingNew = ingestJobs.isNotEmpty &&
            ingestJobs.every(
              (j) =>
                  !j.isActive &&
                  j.phase == FolderIngestJobPhase.done &&
                  j.createdCount == 0 &&
                  j.alreadyInLibraryCount == 0 &&
                  !j.noSupportedMedia,
            );
        final summary = _summary(
          loadingActive: loadingActive,
          removingActive: removingActive,
          ingestFinished: ingestJobs.isNotEmpty && loadingActive == 0,
          removeFinished: removeJobs.isNotEmpty && removingActive == 0,
          ingestNothingNew: ingestNothingNew,
          ingestAlreadyInLibrary: ingestAlreadyInLibrary,
          ingestNoMedia: ingestNoMedia,
        );

        return SelectionContainer.disabled(
          child: Material(
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
                for (final job in ingestJobs)
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
                for (final job in removeJobs)
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
    required bool ingestNothingNew,
    required bool ingestAlreadyInLibrary,
    required bool ingestNoMedia,
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
      if (ingestAlreadyInLibrary) {
        return 'Folder activity finished (already in library)';
      }
      if (ingestNoMedia) {
        return 'Folder activity finished (no supported photos or videos)';
      }
      return ingestNothingNew
          ? 'Folder activity finished (nothing new)'
          : 'Folder activity finished';
    }
    if (removeFinished) return 'Folder remove finished';
    if (ingestFinished) {
      if (ingestAlreadyInLibrary) {
        return 'Folder ingest finished (already in library)';
      }
      if (ingestNoMedia) {
        return 'Folder ingest finished (no supported photos or videos)';
      }
      return ingestNothingNew
          ? 'Folder ingest finished (nothing new)'
          : 'Folder ingest finished';
    }
    return 'Folder activity finished';
  }
}
