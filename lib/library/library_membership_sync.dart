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
/// root are **claimed** for the open collection even if another collection
/// previously owned them — Add-from-folder means "show this folder here".
Future<void> publishCollectionMembershipFromLibrary({
  required ItemsRepository items,
  required CollectionsController cols,
  required LibraryTableController table,
  String? claimUnderFolder,
}) async {
  if (!cols.hasCurrent) return;
  final all = await items.listItems();
  final folders = distinctLeafFolders(all);

  final root = claimUnderFolder == null || claimUnderFolder.isEmpty
      ? null
      : p.normalize(claimUnderFolder);
  if (root != null) {
    final under = [
      for (final f in folders)
        if (f == root || pathIsUnderFolder(f, root)) f,
    ];
    if (under.isNotEmpty) {
      await cols.claimFoldersForCurrent(under);
      // Ensure newly claimed sibling leaves are visible in the Folders tree.
      for (final leaf in under) {
        var dir = leaf;
        while (dir.isNotEmpty && dir != p.dirname(dir)) {
          table.expandedSourceDirs.add(dir);
          final parent = p.normalize(p.dirname(dir));
          if (parent == dir) break;
          dir = parent;
        }
      }
    } else if (cols.current.leafFolders.isEmpty && folders.isNotEmpty) {
      await cols.fillMembershipIfEmpty(folders);
    } else {
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
