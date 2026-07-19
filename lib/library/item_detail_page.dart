import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/processing_status_view.dart';

/// Item detail (D2): metadata/status only — no media (D8) and no knowledge (D8).
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
  }

  Future<Item> _load() {
    return ref.read(itemsRepositoryProvider).getItem(widget.itemId);
  }

  void _retry() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Item'),
      ),
      body: FutureBuilder<Item>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(key: Key('item-detail-loading')),
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

          final item = snapshot.data!;
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
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
            ],
          );
        },
      ),
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
