import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/folder_ingest_queue.dart';
import 'package:tagkin_desktop/ingest/folder_picker.dart';
import 'package:tagkin_desktop/library/folder_remove_queue.dart';
import 'package:tagkin_desktop/library/item_detail_page.dart';
import 'package:tagkin_desktop/library/library_items_table.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/library/source_reveal.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/persons/face_crop_folder_scope.dart';
import 'package:tagkin_desktop/persons/who_face_linker.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';
import 'package:tagkin_desktop/usage/usage_banner.dart';
import 'package:tagkin_desktop/usage/usage_controller.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

/// Post-auth Folders home (D2): wide multi-column items table.
///
/// D6 gates the "Add from folder" FAB on [UsageGate.blocked] and shows a
/// warn/blocked [UsageBanner] above the table. Folder ingest and folder remove
/// run in the background; progress is in the shell status banner
/// ([FolderIngestQueue] / [FolderRemoveQueue]).
class ItemsListPage extends ConsumerStatefulWidget {
  const ItemsListPage({super.key});

  @override
  ConsumerState<ItemsListPage> createState() => _ItemsListPageState();
}

class _ItemsListPageState extends ConsumerState<ItemsListPage> {
  int _lastIngestRefreshTick = 0;
  int _lastRemoveRefreshTick = 0;
  FolderIngestQueue? _ingestQueue;
  FolderRemoveQueue? _removeQueue;
  final Set<String> _retryingFolders = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(usageControllerProvider).load();
      // ensureLoaded (not load) dedupes with the shell's own initial
      // ensureLoaded call for Folders-look baseline capture.
      ref.read(libraryTableControllerProvider).ensureLoaded();
      _bindIngestQueue(ref.read(folderIngestQueueProvider));
      _bindRemoveQueue(ref.read(folderRemoveQueueProvider));
    });
  }

  @override
  void dispose() {
    _ingestQueue?.removeListener(_onIngestQueueChanged);
    _removeQueue?.removeListener(_onRemoveQueueChanged);
    super.dispose();
  }

  void _bindIngestQueue(FolderIngestQueue next) {
    if (identical(_ingestQueue, next)) return;
    final hadPrior = _ingestQueue != null;
    _ingestQueue?.removeListener(_onIngestQueueChanged);
    _ingestQueue = next;
    _lastIngestRefreshTick = next.libraryRefreshTick;
    next.addListener(_onIngestQueueChanged);
    // Catch ticks that landed on a new instance while we held a stale one.
    if (hadPrior || next.libraryRefreshTick > 0) {
      ref.read(libraryTableControllerProvider).load();
    }
  }

  void _bindRemoveQueue(FolderRemoveQueue next) {
    if (identical(_removeQueue, next)) return;
    final hadPrior = _removeQueue != null;
    _removeQueue?.removeListener(_onRemoveQueueChanged);
    _removeQueue = next;
    _lastRemoveRefreshTick = next.libraryRefreshTick;
    next.addListener(_onRemoveQueueChanged);
    if (hadPrior || next.libraryRefreshTick > 0) {
      ref.read(libraryTableControllerProvider).load();
    }
  }

  void _onIngestQueueChanged() {
    if (!mounted) return;
    final queue = _ingestQueue;
    if (queue == null) return;
    if (queue.libraryRefreshTick == _lastIngestRefreshTick) return;
    _lastIngestRefreshTick = queue.libraryRefreshTick;
    ref.read(libraryTableControllerProvider).load();
  }

  void _onRemoveQueueChanged() {
    if (!mounted) return;
    final queue = _removeQueue;
    if (queue == null) return;
    if (queue.libraryRefreshTick == _lastRemoveRefreshTick) return;
    _lastRemoveRefreshTick = queue.libraryRefreshTick;
    ref.read(libraryTableControllerProvider).load();
  }

  void _retry() {
    ref.read(libraryTableControllerProvider).load();
    ref.read(usageControllerProvider).load();
  }

  Future<void> _openDetail(Item item) async {
    final container = ProviderScope.containerOf(context);
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => SelectableScope(
          child: UncontrolledProviderScope(
            container: container,
            child: ItemDetailPage(itemId: item.id),
          ),
        ),
      ),
    );
    if (!mounted) return;
    // Always reload: Retry/Analyze/Cancel/Re-upload change processingStatus
    // on the server, but this table still holds the Item from the last
    // listItems(). Reloading only after delete left the folder view showing
    // "failed" after a successful retry.
    _retry();
  }

  Future<void> _removeItemFromList(Item item) async {
    try {
      await ref.read(jobsRepositoryProvider).deleteItem(item.id);
      if (!mounted) return;
      ref.read(collectionsControllerProvider).markDirty();
      _retry();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('list-delete-error'),
          content: Text('Remove failed: $e'),
        ),
      );
    }
  }

  Future<void> _removeFolderFromList(String dir, int count) async {
    final queue = ref.read(folderRemoveQueueProvider);
    if (queue.isRemoving(dir)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: Key('folder-remove-already-active'),
          content: Text('That folder is already being removed'),
        ),
      );
      return;
    }

    final table = ref.read(libraryTableControllerProvider);
    final ids = itemIdsUnderFolder(
      table.allRows.map((r) => r.item),
      dir,
    ).toList()
      ..sort();
    if (ids.isEmpty) return;

    final result = await queue.enqueue(dir, ids);
    if (!mounted) return;
    if (result == FolderRemoveEnqueueResult.started) {
      ref.read(collectionsControllerProvider).markDirty();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: Key('folder-remove-started'),
          content: Text('Removing folder in the background…'),
        ),
      );
    } else if (result == FolderRemoveEnqueueResult.alreadyActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: Key('folder-remove-already-active'),
          content: Text('That folder is already being removed'),
        ),
      );
    }
  }

  Future<void> _retryFailedInFolder(String dir) async {
    if (_retryingFolders.contains(dir)) return;
    final usage = ref.read(usageControllerProvider);
    if (usage.gate.blocked) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: Key('folder-retry-blocked'),
          content: Text('Budget pause blocks new analyze.'),
        ),
      );
      return;
    }

    final table = ref.read(libraryTableControllerProvider);
    final items = [for (final row in table.allRows) row.item];
    final ids = itemIdsUnderFolder(items, dir);
    final toRetry = [
      for (final item in items)
        if (ids.contains(item.id) &&
            item.processingStatus == ProcessingStatus.failed &&
            item.type == ItemType.photo &&
            item.analysisRefState == AnalysisRefState.ready)
          item,
    ];
    if (toRetry.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: Key('folder-retry-none'),
          content: Text('No failed photos in this folder to retry.'),
        ),
      );
      return;
    }

    setState(() => _retryingFolders.add(dir));
    final jobs = ref.read(jobsRepositoryProvider);
    final prefs = ref.read(desktopPrefsProvider);
    final linker = WhoFaceLinker(
      items: ref.read(itemsRepositoryProvider),
      autoConfirmMinConfidencePercent:
          prefs.autoConfirmHighConfidencePersonMatches
              ? prefs.autoConfirmMinConfidencePercent
              : null,
    );
    var succeeded = 0;
    var stillFailed = 0;
    for (final item in toRetry) {
      try {
        final result = await jobs.analyzeItem(item.id);
        succeeded++;
        if (!mounted) return;
        // Flip this row failed → tagged before face-link / the rest of the
        // batch so the Folders table does not wait for the whole retry.
        table.adoptItem(result.item);
        try {
          await linker.linkWhoFacesForItem(result.item);
        } catch (_) {
          // Linking is best-effort; analyze already succeeded.
        }
      } catch (_) {
        stillFailed++;
      }
    }
    if (!mounted) return;
    setState(() => _retryingFolders.remove(dir));
    _retry();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('folder-retry-done'),
        content: Text(
          stillFailed == 0
              ? 'Retried $succeeded item(s).'
              : 'Retried $succeeded item(s); $stillFailed still failed.',
        ),
      ),
    );
  }

  Future<void> _revealSource(Item item) async {
    final ok = await revealSourceRef(item.sourceRef);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: Key('source-reveal-error'),
          content: Text('Could not reveal original file'),
        ),
      );
    }
  }

  Future<void> _openFolderIngest() async {
    final picker = ref.read(folderPickerProvider);
    String? path;
    try {
      path = await picker();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('folder-pick-error'),
          content: Text('Could not open folder picker: $e'),
        ),
      );
      return;
    }
    if (path == null || !mounted) return;

    final queue = ref.read(folderIngestQueueProvider);
    final result = await queue.enqueue(path);
    if (!mounted) return;
    if (result == FolderIngestEnqueueResult.started) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: Key('folder-ingest-started'),
          content: Text('Loading folder in the background…'),
        ),
      );
    } else if (result == FolderIngestEnqueueResult.alreadyActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: Key('folder-ingest-already-active'),
          content: Text(
            'That folder is already loading. Wait until it finishes.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<FolderIngestQueue>(folderIngestQueueProvider, (previous, next) {
      _bindIngestQueue(next);
    });
    ref.listen<FolderRemoveQueue>(folderRemoveQueueProvider, (previous, next) {
      _bindRemoveQueue(next);
    });
    final usage = ref.watch(usageControllerProvider);
    final table = ref.watch(libraryTableControllerProvider);
    return ListenableBuilder(
      listenable: Listenable.merge([usage, table]),
      builder: (context, _) {
        final blocked = usage.gate.blocked;
        return Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UsageBanner(gate: usage.gate),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('library-filter'),
                        decoration: const InputDecoration(
                          isDense: true,
                          prefixIcon: Icon(Icons.search, size: 20),
                          hintText:
                              'Filter who, what, where, source, comment…',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: table.setFilterQuery,
                      ),
                    ),
                    if (table.knowledgeWarming) ...[
                      const SizedBox(width: 12),
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      key: const Key('add-from-folder'),
                      onPressed: blocked ? null : _openFolderIngest,
                      icon: const Icon(Icons.drive_folder_upload),
                      label: const Text('Add from folder'),
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildBody(table, retryEnabled: !blocked)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(
    LibraryTableController table, {
    required bool retryEnabled,
  }) {
    if (table.loading && table.allRows.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(key: Key('items-loading')),
      );
    }
    if (table.error != null && table.allRows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Could not load items: ${table.error}',
                key: const Key('items-error'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('items-retry'),
                onPressed: _retry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (table.allRows.isEmpty) {
      return const Center(
        child: Text(
          'No items yet',
          key: Key('items-empty'),
        ),
      );
    }

    final removeQueue = ref.watch(folderRemoveQueueProvider);
    return ListenableBuilder(
      listenable: removeQueue,
      builder: (context, _) {
        return LibraryItemsTable(
          controller: table,
          onOpenDetail: _openDetail,
          onDelete: _removeItemFromList,
          onRemoveFolder: _removeFolderFromList,
          onRevealSource: _revealSource,
          onRetryFolder: _retryFailedInFolder,
          isFolderRemoving: removeQueue.isRemoving,
          isFolderRetrying: _retryingFolders.contains,
          retryEnabled: retryEnabled,
        );
      },
    );
  }
}
