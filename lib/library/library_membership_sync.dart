import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/api/items_repository.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/persons/face_crop_folder_scope.dart';

/// Adopt / claim library leaf folders into the open collection from an
/// **unfiltered** item list, then push the Folders membership filter.
///
/// Must not use [LibraryTableController.allRows] alone — that list follows
/// the table status filter, so pending ingest leaves would be skipped (and
/// previously could be shrunk out of membership).
///
/// When [claimUnderFolder] is set (folder ingest finish), leaves under that
/// root are **claimed** for [claimForCollectionId] (the collection that
/// started ingest) or the open collection when that id is omitted.
/// Add-from-folder on the open collection still means "show this folder here".
Future<void> publishCollectionMembershipFromLibrary({
  required ItemsRepository items,
  required CollectionsController cols,
  required LibraryTableController table,
  String? claimUnderFolder,
  String? claimForCollectionId,
}) async {
  if (!cols.hasCurrent) return;
  final all = await items.listItems();
  final folders = distinctLeafFolders(all);

  final root = claimUnderFolder == null || claimUnderFolder.isEmpty
      ? null
      : normalizeLeafFolder(claimUnderFolder);
  if (root != null) {
    final under = [
      for (final f in folders)
        if (f == root || pathIsUnderFolder(f, root)) f,
    ];
    final targetId = (claimForCollectionId != null &&
            claimForCollectionId.isNotEmpty)
        ? claimForCollectionId
        : cols.current.id;
    if (under.isNotEmpty) {
      await cols.claimFoldersFor(targetId, under);
      if (targetId == cols.current.id) {
        // Ensure newly claimed sibling leaves are visible in the Folders tree.
        for (final leaf in under) {
          var dir = normalizeLeafFolder(leaf);
          while (dir.isNotEmpty && dir != p.posix.dirname(dir)) {
            table.expandedSourceDirs.add(dir);
            final parent = p.posix.dirname(dir);
            if (parent == dir) break;
            dir = parent;
          }
        }
      }
    } else if (targetId == cols.current.id &&
        cols.current.leafFolders.isEmpty &&
        folders.isNotEmpty) {
      await cols.fillMembershipIfEmpty(folders);
    } else if (targetId == cols.current.id) {
      cols.adoptUnownedFolders(folders);
    }
  } else if (cols.current.leafFolders.isEmpty && folders.isNotEmpty) {
    await cols.fillMembershipIfEmpty(folders);
  } else {
    cols.adoptUnownedFolders(folders);
  }

  table.setCollectionLeafFolders(cols.current.leafFolders.toSet());
  // Reload Folders rows even if a tick listener was bound to a stale queue.
  await table.load();
}
