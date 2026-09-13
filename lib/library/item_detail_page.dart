import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/jobs/jobs_controller.dart';
import 'package:tagkin_desktop/library/item_detail_edits.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/review/item_review_page.dart';
import 'package:tagkin_desktop/ui/async_state_view.dart';
import 'package:tagkin_desktop/undo/undo_shortcuts.dart';

/// Item detail (D2 metadata + D7 tagging/jobs + D8 review).
class ItemDetailPage extends ConsumerStatefulWidget {
  const ItemDetailPage({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<ItemDetailPage> createState() => _ItemDetailPageState();
}

class _ItemDetailPageState extends ConsumerState<ItemDetailPage> {
  late Future<Item> _future;
  final ItemDetailEdits _edits = ItemDetailEdits();
  final GlobalKey _reviewKey = GlobalKey();
  LibraryTableController? _libraryTable;

  /// Set right after a successful [_toggleHidden] so the AppBar toggle
  /// reflects the new state immediately (before/regardless of [_future]).
  Item? _hiddenOverride;

  @override
  void initState() {
    super.initState();
    _future = _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(jobsControllerProvider(widget.itemId)).refreshJobs();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cacheLibraryTable();
  }

  @override
  void dispose() {
    _refreshFoldersRow();
    _edits.dispose();
    super.dispose();
  }

  void _cacheLibraryTable() {
    final container = ProviderScope.containerOf(context, listen: false);
    if (!container.exists(libraryTableControllerProvider)) return;
    _libraryTable = container.read(libraryTableControllerProvider);
  }

  void _refreshFoldersRow() {
    final table = _libraryTable;
    if (table == null) return;
    unawaited(table.refreshRowSummaries(widget.itemId));
  }

  Future<void> _saveAndRefreshFolders() async {
    final save = _edits.save;
    if (save == null) return;
    await save();
    if (!mounted) return;
    _cacheLibraryTable();
    _refreshFoldersRow();
  }

  Future<Item> _load() {
    return ref.read(itemsRepositoryProvider).getItem(widget.itemId);
  }

  void _retry() {
    setState(() {
      _future = _load();
    });
  }

  /// Current best-known [Item]: a just-applied hide/unhide wins, then any
  /// job-adopted refresh (analyze/cancel), then the last `_future` snapshot.
  Item? _currentItem(JobsController jobs, Item? snapshotItem) {
    return _hiddenOverride ?? jobs.item ?? snapshotItem;
  }

  /// Non-destructive show/hide (D2). The item stays fully in the library;
  /// this never closes the page (unlike the old destructive Remove).
  Future<void> _toggleHidden(Item item) async {
    try {
      final updated = await ref
          .read(itemsRepositoryProvider)
          .setItemHidden(item.id, !item.isHidden);
      if (!mounted) return;
      setState(() => _hiddenOverride = updated);
      _cacheLibraryTable();
      _libraryTable?.adoptItem(updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('item-detail-hide-error'),
          content: Text('Hide failed: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobs = ref.watch(jobsControllerProvider(widget.itemId));

    return ListenableBuilder(
      listenable: jobs,
      builder: (context, _) {
        final body = FutureBuilder<Item>(
          future: _future,
          builder: (context, snapshot) {
            final item = _currentItem(jobs, snapshot.data);
            if (item == null) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const AsyncStateView.loading(
                  key: Key('item-detail-loading'),
                );
              }
              if (snapshot.hasError) {
                final error = snapshot.error!;
                final isNotFound =
                    error is ApiException && error.statusCode == 404;
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isNotFound
                              ? 'Item not found'
                              : 'Could not load item: $error',
                          key: isNotFound
                              ? const Key('item-detail-not-found')
                              : const Key('item-detail-error'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (!isNotFound) ...[
                          const SizedBox(height: 16),
                          FilledButton(
                            key: const Key('item-detail-retry'),
                            onPressed: _retry,
                            child: const Text('Retry'),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            }

            return ListView(
              key: const Key('item-detail'),
              padding: const EdgeInsets.all(24),
              children: [
                ItemReviewSection(
                  key: _reviewKey,
                  itemId: widget.itemId,
                  item: item,
                  edits: _edits,
                  embedSaveButton: false,
                ),
              ],
            );
          },
        );

        return ListenableBuilder(
          listenable: _edits,
          builder: (context, _) {
            return PopScope(
              canPop: !_edits.isDirty,
              onPopInvokedWithResult: (didPop, result) async {
                if (didPop) return;
                final ok = await _edits.confirmLeave?.call() ?? true;
                if (ok && context.mounted) {
                  Navigator.of(context).pop(result);
                }
              },
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('Item'),
                  actions: [
                    AppNavTabButtons(
                      onBeforeNavigate: () async =>
                          await _edits.confirmLeave?.call() ?? true,
                    ),
                    ListenableBuilder(
                      listenable: _edits.undo,
                      builder: (context, _) {
                        if (_edits.undo.undoDepth == 0) {
                          return const SizedBox.shrink();
                        }
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            UndoDepthBadge(controller: _edits.undo),
                            const SizedBox(width: 8),
                          ],
                        );
                      },
                    ),
                    FilledButton(
                      key: const Key('item-detail-save'),
                      onPressed: _edits.isDirty &&
                              !_edits.saving &&
                              _edits.save != null
                          ? _saveAndRefreshFolders
                          : null,
                      child: const Text('Save'),
                    ),
                    const SizedBox(width: 8),
                    FutureBuilder<Item>(
                      future: _future,
                      builder: (context, snapshot) {
                        final item = _currentItem(jobs, snapshot.data);
                        if (item == null) return const SizedBox.shrink();
                        return IconButton(
                          key: const Key('item-hide-toggle'),
                          tooltip: item.isHidden
                              ? 'Unhide item'
                              : 'Hide item',
                          icon: Icon(
                            item.isHidden
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => _toggleHidden(item),
                        );
                      },
                    ),
                  ],
                ),
                body: body,
              ),
            );
          },
        );
      },
    );
  }
}
