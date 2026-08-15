import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/jobs/jobs_controller.dart';
import 'package:tagkin_desktop/library/item_detail_edits.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/review/item_review_page.dart';
import 'package:tagkin_desktop/undo/undo_shortcuts.dart';
import 'package:tagkin_desktop/widgets/sure_action_button.dart';

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

  @override
  void initState() {
    super.initState();
    _future = _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(jobsControllerProvider(widget.itemId)).refreshJobs();
    });
  }

  @override
  void dispose() {
    _edits.dispose();
    super.dispose();
  }

  Future<Item> _load() {
    return ref.read(itemsRepositoryProvider).getItem(widget.itemId);
  }

  void _retry() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _removeItem(JobsController jobs) async {
    await jobs.delete();
    if (!mounted) return;
    if (jobs.deleted) {
      ref.read(collectionsControllerProvider).markDirty();
      Navigator.of(context).pop(true);
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
            final item = jobs.item ?? snapshot.data;
            if (item == null) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: CircularProgressIndicator(
                    key: Key('item-detail-loading'),
                  ),
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
                          ? () => _edits.save!()
                          : null,
                      child: const Text('Save'),
                    ),
                    const SizedBox(width: 8),
                    SureActionButton(
                      idleKey: const Key('item-delete'),
                      confirmKey: const Key('item-remove-confirm'),
                      tooltip: 'Remove item',
                      confirmSemanticsLabel: 'Confirm remove item',
                      icon: const Icon(Icons.remove_circle_outline),
                      enabled: !jobs.deleted,
                      onConfirm: () => _removeItem(jobs),
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
