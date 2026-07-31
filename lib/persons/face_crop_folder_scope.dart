import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';

/// Last leaf folder chosen on Faces (session-scoped).
String? faceCropLastLeafFolder;

/// Parent directory of [item]'s local `sourceRef`, or null when unknown.
String? leafFolderFromItem(Item item) {
  return leafFolderFromSourceRef(item.sourceRef);
}

/// Parent directory of a `file://` [sourceRef], or null when unknown.
String? leafFolderFromSourceRef(String? sourceRef) {
  final path = localPathFromSourceRef(sourceRef);
  if (path == null || path.isEmpty) return null;
  final dir = p.normalize(p.dirname(path));
  if (dir.isEmpty || dir == '.') return null;
  return dir;
}

/// Sorted unique leaf folders among [items].
List<String> distinctLeafFolders(Iterable<Item> items) {
  final folders = <String>{};
  for (final item in items) {
    final folder = leafFolderFromItem(item);
    if (folder != null) folders.add(folder);
  }
  final list = folders.toList()..sort();
  return list;
}

/// Item ids whose source file lives directly in [leafFolder].
Set<String> itemIdsInLeafFolder(Iterable<Item> items, String leafFolder) {
  final target = p.normalize(leafFolder);
  final ids = <String>{};
  for (final item in items) {
    final folder = leafFolderFromItem(item);
    if (folder != null && folder == target) {
      ids.add(item.id);
    }
  }
  return ids;
}

/// Whether [filePath] is [folder] itself or a descendant under it.
bool pathIsUnderFolder(String filePath, String folder) {
  final normalizedFile = p.normalize(filePath);
  final normalizedFolder = p.normalize(folder);
  if (normalizedFile == normalizedFolder) return true;
  final prefix = normalizedFolder.endsWith(p.separator)
      ? normalizedFolder
      : '$normalizedFolder${p.separator}';
  return normalizedFile.startsWith(prefix);
}

/// Item ids whose source file lives in [folder] or any nested subdirectory.
Set<String> itemIdsUnderFolder(Iterable<Item> items, String folder) {
  final ids = <String>{};
  for (final item in items) {
    final path = localPathFromSourceRef(item.sourceRef);
    if (path != null && pathIsUnderFolder(path, folder)) {
      ids.add(item.id);
    }
  }
  return ids;
}

/// Pick a folder to open: prefer [preferred] if still listed, else first.
String? resolveLeafFolderSelection({
  required List<String> folders,
  String? preferred,
}) {
  if (folders.isEmpty) return null;
  if (preferred != null && folders.contains(preferred)) return preferred;
  return folders.first;
}

/// Short label for a leaf folder path (basename, or full path if bare).
String leafFolderLabel(String folder) {
  final base = p.basename(folder);
  return base.isEmpty ? folder : base;
}
