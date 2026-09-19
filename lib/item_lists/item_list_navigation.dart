import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/item_lists/item_list_export_page.dart';

/// Bumped by File → Export list… when signed in.
final openItemListExportTickProvider = StateProvider<int>((ref) => 0);

/// True while Export list is encoding MP4 or generating music.
///
/// Module-level so the signed-in window-close / Quit gate can read it without
/// importing the Export page (and without `ref` after dispose).
bool itemListExportBusy = false;

/// Set while [ItemListExportPage] is on screen. Return false to Stay (abort quit).
Future<bool> Function()? itemListConfirmLeaveIfBusy;

/// Tests only: clear the quit-gate hooks.
void resetItemListExportBusyLeave() {
  itemListExportBusy = false;
  itemListConfirmLeaveIfBusy = null;
}

/// When false, [didRequestAppExit] must run the leave prompt instead of exiting.
bool appExitCanSkipLeavePrompt({
  required bool collectionDirty,
  required bool viewDirty,
  required bool exportBusy,
}) {
  return !collectionDirty && !viewDirty && !exportBusy;
}

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
