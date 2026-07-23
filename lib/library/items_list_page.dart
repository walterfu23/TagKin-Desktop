import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/folder_ingest_page.dart';
import 'package:tagkin_desktop/jobs/export_controller.dart';
import 'package:tagkin_desktop/library/item_detail_page.dart';
import 'package:tagkin_desktop/library/library_items_table.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/library/source_reveal.dart';
import 'package:tagkin_desktop/usage/usage_banner.dart';
import 'package:tagkin_desktop/usage/usage_controller.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

/// Post-auth library home (D2): wide multi-column items table.
///
/// D6 gates the "Add from folder" FAB on [UsageGate.blocked] and shows a
/// warn/blocked [UsageBanner] above the table. D7 adds library export.
class ItemsListPage extends ConsumerStatefulWidget {
  const ItemsListPage({super.key});

  @override
  ConsumerState<ItemsListPage> createState() => _ItemsListPageState();
}

class _ItemsListPageState extends ConsumerState<ItemsListPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(usageControllerProvider).load();
      ref.read(libraryTableControllerProvider).load();
    });
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

  Future<void> _confirmDeleteFromList(Item item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete item?'),
        content: const Text(
          'Removes this item from your TagKin library. '
          'Original local media is not deleted.',
        ),
        actions: [
          TextButton(
            key: const Key('delete-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('delete-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(jobsRepositoryProvider).deleteItem(item.id);
      if (!mounted) return;
      _retry();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('list-delete-error'),
          content: Text('Delete failed: $e'),
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
    final container = ProviderScope.containerOf(context);
    final ingested = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => SelectableScope(
          child: UncontrolledProviderScope(
            container: container,
            child: const FolderIngestPage(),
          ),
        ),
      ),
    );
    if (ingested == true) {
      _retry();
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

    return LibraryItemsTable(
      controller: table,
      onOpenDetail: _openDetail,
      onDelete: _confirmDeleteFromList,
      onRevealSource: _revealSource,
    );
  }
}
