import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/item_lists/item_list_export_page.dart';

/// Bumped by File → Export list… when signed in.
final openItemListExportTickProvider = StateProvider<int>((ref) => 0);

/// True while Export list is generating music.
///
/// MP4 exports use [ItemListExportJobManager.hasActive]. Module-level so the
/// signed-in window-close / Quit gate can read music-busy without `ref`
/// after the page disposes.
bool itemListExportBusy = false;

/// Quit-dialog copy when [activeCount] MP4 exports are still in flight.
String itemListQuitExportsBody(int activeCount) {
  if (activeCount <= 0) return '';
  if (activeCount == 1) {
    return '1 export is still running. Quit and cancel it?';
  }
  return '$activeCount exports are still running. Quit and cancel them?';
}

/// Confirm quit when background MP4 exports are queued, running, or paused.
///
/// Returns true when the user chooses Quit (caller cancels the jobs) or when
/// nothing is active.
Future<bool> confirmQuitItemListExports({
  required BuildContext context,
  required int activeCount,
}) async {
  if (activeCount <= 0) return true;
  final quit = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      key: const Key('item-list-quit-exports-dialog'),
      title: const Text('Cancel exports?'),
      content: Text(itemListQuitExportsBody(activeCount)),
      actions: [
        TextButton(
          key: const Key('item-list-quit-exports-stay'),
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Stay'),
        ),
        FilledButton(
          key: const Key('item-list-quit-exports-quit'),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Quit'),
        ),
      ],
    ),
  );
  return quit == true;
}

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
