import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/folder_ingest_queue.dart';
import 'package:tagkin_desktop/ingest/folder_picker.dart';
import 'package:tagkin_desktop/jobs/export_controller.dart';
import 'package:tagkin_desktop/library/folder_remove_queue.dart';
import 'package:tagkin_desktop/library/item_detail_page.dart';
import 'package:tagkin_desktop/library/library_items_table.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/library/source_reveal.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/persons/face_crop_folder_scope.dart';
import 'package:tagkin_desktop/usage/usage_banner.dart';
import 'package:tagkin_desktop/usage/usage_controller.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

/// Post-auth library home (D2): wide multi-column items table.
///
/// D6 gates the "Add from folder" FAB on [UsageGate.blocked] and shows a
/// warn/blocked [UsageBanner] above the table. D7 adds library export.
/// Folder ingest and folder remove run in the background; progress is in the
/// shell status banner ([FolderIngestQueue] / [FolderRemoveQueue]).
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(usageControllerProvider).load();
      // ensureLoaded (not load) dedupes with the shell's own initial
      // ensureLoaded call for Folders-look baseline capture.
      ref.read(libraryTableControllerProvider).ensureLoaded();
      final ingest = ref.read(folderIngestQueueProvider);
      _ingestQueue = ingest;
      _lastIngestRefreshTick = ingest.libraryRefreshTick;
      ingest.addListener(_onIngestQueueChanged);
      final remove = ref.read(folderRemoveQueueProvider);
      _removeQueue = remove;
      _lastRemoveRefreshTick = remove.libraryRefreshTick;
      remove.addListener(_onRemoveQueueChanged);
    });
  }

  @override
  void dispose() {
    _ingestQueue?.removeListener(_onIngestQueueChanged);
    _removeQueue?.removeListener(_onRemoveQueueChanged);
    super.dispose();
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
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => SelectableScope(
          child: UncontrolledProviderScope(
            container: container,
            child: ItemDetailPage(itemId: item.id),
          ),
        ),
      ),
    );
    if (deleted == true) {
      _retry();
    }
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

  Future<void> _exportLibrary() async {
    final export = ref.read(exportControllerProvider);
    await export.exportLibrary();
    if (!mounted) return;
    if (export.phase == ExportPhase.done) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('export-success'),
          content: Text('Exported to ${export.savedPath}'),
        ),
      );
    } else if (export.phase == ExportPhase.error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('export-error'),
          content: Text('Export failed: ${export.error}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final usage = ref.watch(usageControllerProvider);
    final export = ref.watch(exportControllerProvider);
    final table = ref.watch(libraryTableControllerProvider);
    return ListenableBuilder(
      listenable: Listenable.merge([usage, export, table]),
      builder: (context, _) {
        final blocked = usage.gate.blocked;
        final exporting = export.phase == ExportPhase.running;
        return Scaffold(
          floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
          floatingActionButton: FloatingActionButton.extended(
            key: const Key('add-from-folder'),
            onPressed: blocked ? null : _openFolderIngest,
            icon: const Icon(Icons.drive_folder_upload),
            label: const Text('Add from folder'),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UsageBanner(gate: usage.gate),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('export-library'),
                    onPressed: exporting ? null : _exportLibrary,
                    icon: exporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_outlined),
                    label: const Text('Export library…'),
                  ),
                ),
              ),
              Expanded(child: _buildBody(table)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(LibraryTableController table) {
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
          isFolderRemoving: removeQueue.isRemoving,
        );
      },
    );
  }
}
