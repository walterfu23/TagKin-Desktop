import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';

/// Last leaf folder chosen on Faces (session-scoped).
String? faceCropLastLeafFolder;

/// Stable leaf-folder identity: POSIX separators so `/albums/X` and
/// `\albums\X` (Windows `Uri.toFilePath`) are the same membership key.
String normalizeLeafFolder(String folder) {
  final trimmed = folder.trim();
  if (trimmed.isEmpty) return trimmed;
  return p.posix.normalize(trimmed.replaceAll(r'\', '/'));
}

/// Parent directory of [item]'s local `sourceRef`, or null when unknown.
String? leafFolderFromItem(Item item) {
  return leafFolderFromSourceRef(item.sourceRef);
}

/// Parent directory of a `file://` [sourceRef], or null when unknown.
String? leafFolderFromSourceRef(String? sourceRef) {
  final path = localPathFromSourceRef(sourceRef);
  if (path == null || path.isEmpty) return null;
  final dir = p.dirname(path);
  if (dir.isEmpty || dir == '.') return null;
  final normalized = normalizeLeafFolder(dir);
  if (normalized.isEmpty || normalized == '.') return null;
  return normalized;
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
  final target = normalizeLeafFolder(leafFolder);
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
  final normalizedFile = normalizeLeafFolder(filePath);
  final normalizedFolder = normalizeLeafFolder(folder);
  if (normalizedFile == normalizedFolder) return true;
  final prefix = normalizedFolder.endsWith('/')
      ? normalizedFolder
      : '$normalizedFolder/';
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
  if (preferred != null) {
    final key = normalizeLeafFolder(preferred);
    for (final folder in folders) {
      if (normalizeLeafFolder(folder) == key) return folder;
    }
  }
  return folders.first;
}

/// Short label for a leaf folder path (basename, or full path if bare).
String leafFolderLabel(String folder) {
  final base = p.basename(folder);
  return base.isEmpty ? folder : base;
}

/// Drop folders that sit under another selected folder.
List<String> minimalCoveringFolders(Iterable<String> folders) {
  final unique = {
    for (final f in folders)
      if (f.isNotEmpty) normalizeLeafFolder(f),
  }.toList()
    ..sort();
  return [
    for (final folder in unique)
      if (!unique.any(
        (other) => other != folder && pathIsUnderFolder(folder, other),
      ))
        folder,
  ];
}

/// Ingest roots that cover [items]: longest bookmarked ancestor, else leaf
/// parent, then collapsed so nested paths are not separate jobs.
List<String> coveringFoldersForItems(
  Iterable<Item> items, {
  Iterable<String> bookmarkedFolders = const [],
}) {
  final bookmarks = [
    for (final f in bookmarkedFolders)
      if (f.isNotEmpty) normalizeLeafFolder(f),
  ];
  final roots = <String>{};
  for (final item in items) {
    final path = localPathFromSourceRef(item.sourceRef);
    if (path == null || path.isEmpty) continue;
    final normalized = normalizeLeafFolder(path);
    String? best;
    for (final folder in bookmarks) {
      if (pathIsUnderFolder(normalized, folder)) {
        if (best == null || folder.length > best.length) best = folder;
      }
    }
    final leaf = leafFolderFromSourceRef(item.sourceRef);
    final root = best ?? leaf;
    if (root != null && root.isNotEmpty) roots.add(root);
  }
  return minimalCoveringFolders(roots);
}
