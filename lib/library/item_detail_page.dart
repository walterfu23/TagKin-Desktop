import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/jobs/job_state_view.dart';
import 'package:tagkin_desktop/jobs/jobs_controller.dart';
import 'package:tagkin_desktop/library/processing_status_view.dart';
import 'package:tagkin_desktop/review/item_review_page.dart';
import 'package:tagkin_desktop/usage/usage_controller.dart';

/// Item detail (D2 metadata + D7 tagging/jobs + D8 review).
class ItemDetailPage extends ConsumerStatefulWidget {
  const ItemDetailPage({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<ItemDetailPage> createState() => _ItemDetailPageState();
}

class _ItemDetailPageState extends ConsumerState<ItemDetailPage> {
  late Future<Item> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(jobsControllerProvider(widget.itemId)).refreshJobs();
    });
  }

  Future<Item> _load() {
    return ref.read(itemsRepositoryProvider).getItem(widget.itemId);
  }

  void _retry() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _confirmDelete(JobsController jobs) async {
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
    await jobs.delete();
    if (!mounted) return;
    if (jobs.deleted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobs = ref.watch(jobsControllerProvider(widget.itemId));
    final usage = ref.watch(usageControllerProvider);

    return ListenableBuilder(
      listenable: Listenable.merge([jobs, usage]),
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Item'),
            actions: [
              IconButton(
                key: const Key('item-delete'),
                tooltip: 'Delete item',
                onPressed: jobs.deleted ? null : () => _confirmDelete(jobs),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          body: FutureBuilder<Item>(
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

              final blocked = usage.gate.blocked;
              final isPhoto = item.type == ItemType.photo;
              final canAnalyze = isPhoto &&
                  !blocked &&
                  !jobs.isBusy &&
                  !jobs.deleted &&
                  item.processingStatus != ProcessingStatus.processing;

              return ListView(
                key: const Key('item-detail'),
                padding: const EdgeInsets.all(24),
                children: [
                  _DetailRow(label: 'id', value: item.id, valueKey: 'item-id'),
                  _DetailRow(
                    label: 'type',
                    value: item.type.wire,
                    valueKey: 'item-type',
                  ),
                  _DetailRow(
                    label: 'sourceType',
                    value: item.sourceType.wire,
                    valueKey: 'item-source-type',
                  ),
                  _DetailRow(
                    label: 'capturedAt',
                    value: item.capturedAt ?? '—',
                    valueKey: 'item-captured-at',
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 140,
                          child: Text(
                            'processingStatus',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ),
                        Expanded(
                          child: ProcessingStatusBadge(
                            status: item.processingStatus,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _DetailRow(
                    label: 'createdAt',
                    value: item.createdAt,
                    valueKey: 'item-created-at',
                  ),
                  if (item.sourceRef != null)
                    _DetailRow(
                      label: 'sourceRef',
                      value: item.sourceRef!,
                      valueKey: 'item-source-ref',
                    ),
                  if (item.contentHash != null)
                    _DetailRow(
                      label: 'contentHash',
                      value: item.contentHash!,
                      valueKey: 'item-content-hash',
                    ),
                  const SizedBox(height: 24),
                  Text(
                    'Tagging & jobs',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  if (jobs.latestJob != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        key: const Key('job-progress'),
                        children: [
                          if (jobs.isBusy) ...[
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                          ],
                          JobStateBadge(state: jobs.latestJob!.state),
                        ],
                      ),
                    ),
                  if (jobs.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        '${jobs.error}',
                        key: const Key('jobs-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        key: const Key('item-analyze'),
                        onPressed: canAnalyze
                            ? () => jobs.analyze(itemType: item.type)
                            : null,
                        child: const Text('Analyze'),
                      ),
                      if (jobs.canCancel)
                        OutlinedButton(
                          key: const Key('item-cancel-job'),
                          onPressed: () => jobs.cancel(),
                          child: const Text('Cancel'),
                        ),
                      if (jobs.canRetry)
                        OutlinedButton(
                          key: const Key('item-retry-job'),
                          onPressed: () =>
                              jobs.retry(itemType: item.type),
                          child: const Text('Retry'),
                        ),
                    ],
                  ),
                  if (!isPhoto)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Analyze is photo-only in v1 (sample-frame tagging).',
                        key: Key('analyze-photo-only-hint'),
                      ),
                    ),
                  if (blocked && isPhoto)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Budget pause blocks new analyze.',
                        key: Key('analyze-budget-blocked-hint'),
                      ),
                    ),
                  const SizedBox(height: 32),
                  ItemReviewSection(itemId: widget.itemId),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final String label;
  final String value;
  final String valueKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              key: Key(valueKey),
            ),
          ),
        ],
      ),
    );
  }
}
