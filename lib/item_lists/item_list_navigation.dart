import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/item_lists/item_list_export_page.dart';

/// Bumped by File → Export list… when signed in.
final openItemListExportTickProvider = StateProvider<int>((ref) => 0);

/// Request the item-list export screen from outside the signed-in scaffold.
void requestOpenItemListExport(WidgetRef ref) {
  ref.read(openItemListExportTickProvider.notifier).state++;
}

/// Push [ItemListExportPage] on the nearest navigator, preserving [ProviderScope].
Future<void> pushItemListExportPage(BuildContext context) async {
  final container = ProviderScope.containerOf(context);
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'item-list-export'),
      builder: (_) => UncontrolledProviderScope(
        container: container,
        child: const ItemListExportPage(),
      ),
    ),
  );
}
