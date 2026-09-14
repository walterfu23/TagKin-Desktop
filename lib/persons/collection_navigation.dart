import 'package:flutter_riverpod/flutter_riverpod.dart';

/// File-menu / AppBar collection actions (signed-in shell listens and runs UI).
enum CollectionMenuCommand {
  newCollection,
  open,
  openRecent,
  save,
  saveAs,
  rename,
  delete,
  addFolder,
  removeFolder,
}

class CollectionMenuRequest {
  const CollectionMenuRequest({
    required this.command,
    required this.nonce,
    this.recentCollectionId,
  });

  final CollectionMenuCommand command;
  final int nonce;
  final String? recentCollectionId;
}

int _collectionMenuNonce = 0;

final collectionMenuRequestProvider = StateProvider<CollectionMenuRequest?>(
  (ref) => null,
);

/// Named Folders view is dirty (`View01*`). Root-scoped so macOS File Save
/// (outside the signed-in [ProviderScope]) can enable Cmd-S.
final activeViewDirtyProvider = StateProvider<bool>((ref) => false);

void requestCollectionMenu(
  WidgetRef ref,
  CollectionMenuCommand command, {
  String? recentCollectionId,
}) {
  ref
      .read(collectionMenuRequestProvider.notifier)
      .state = CollectionMenuRequest(
    command: command,
    nonce: ++_collectionMenuNonce,
    recentCollectionId: recentCollectionId,
  );
}
