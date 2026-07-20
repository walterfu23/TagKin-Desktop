import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/folder_ingest_page.dart';
import 'package:tagkin_desktop/library/item_detail_page.dart';
import 'package:tagkin_desktop/library/processing_status_view.dart';
import 'package:tagkin_desktop/usage/usage_banner.dart';
import 'package:tagkin_desktop/usage/usage_controller.dart';

/// Post-auth library home (D2): lists the authenticated account's items.
///
/// D6 gates the "Add from folder" FAB on [UsageGate.blocked] and shows a
/// warn/blocked [UsageBanner] above the list.
class ItemsListPage extends ConsumerStatefulWidget {
  const ItemsListPage({super.key});

  @override
  ConsumerState<ItemsListPage> createState() => _ItemsListPageState();
}

class _ItemsListPageState extends ConsumerState<ItemsListPage> {
  late Future<List<Item>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    // On-demand usage fetch (no polling in D6 v1).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(usageControllerProvider).load();
    });
  }

  Future<List<Item>> _load() {
    return ref.read(itemsRepositoryProvider).listItems();
  }

  void _retry() {
    setState(() {
      _future = _load();
    });
    ref.read(usageControllerProvider).load();
  }

  void _openDetail(Item item) {
    final container = ProviderScope.containerOf(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UncontrolledProviderScope(
          container: container,
          child: ItemDetailPage(itemId: item.id),
        ),
      ),
    );
  }

  /// Opens D3 folder ingest; refreshes the list when it reports new items.
  Future<void> _openFolderIngest() async {
    // MaterialApp's navigator sits above the signed-in ProviderScope that
    // overrides apiClientProvider — re-bind the current container so the
    // pushed route still sees the authenticated client.
    final container = ProviderScope.containerOf(context);
    final ingested = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => UncontrolledProviderScope(
          container: container,
          child: const FolderIngestPage(),
        ),
      ),
    );
    if (ingested == true) {
      _retry();
    }
  }

  @override
  Widget build(BuildContext context) {
    final usage = ref.watch(usageControllerProvider);
    return ListenableBuilder(
      listenable: usage,
      builder: (context, _) {
        final blocked = usage.gate.blocked;
        return Scaffold(
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
              Expanded(child: _buildBody()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    return FutureBuilder<List<Item>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(key: Key('items-loading')),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Could not load items: ${snapshot.error}',
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

        final items = snapshot.data!;
        if (items.isEmpty) {
          return const Center(
            child: Text(
              'No items yet',
              key: Key('items-empty'),
            ),
          );
        }

        return ListView.separated(
          key: const Key('items-list'),
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = items[index];
            return ListTile(
              key: Key('item-row-${item.id}'),
              title: Text(
                item.type.wire,
                key: Key('item-type-${item.id}'),
              ),
              subtitle: Text(
                item.capturedAt ?? 'unknown capture time',
                key: Key('item-captured-at-${item.id}'),
              ),
              trailing: ProcessingStatusBadge(status: item.processingStatus),
              onTap: () => _openDetail(item),
            );
          },
        );
      },
    );
  }
}
