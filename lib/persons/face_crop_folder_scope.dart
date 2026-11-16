import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';
import 'package:tagkin_desktop/ui/alpha_order.dart';

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
  final list = folders.toList()
    ..sort((a, b) {
      final byLabel = compareLabelsAlpha(leafFolderLabel(a), leafFolderLabel(b));
      return byLabel != 0 ? byLabel : a.compareTo(b);
    });
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

/// Faces-page status of one leaf folder, shown next to its name in the
/// Folder dropdown.
class FolderFaceStatus {
  const FolderFaceStatus({
    required this.analysisFinished,
    required this.unassignedLeft,
  });

  /// No item in the folder is still pending, waiting, or processing.
  final bool analysisFinished;

  /// Unassigned faces still to place in the folder.
  final int unassignedLeft;

  /// Analysis finished and no unassigned faces remain.
  bool get isDone => analysisFinished && unassignedLeft == 0;

  /// `Analyzing...` while analysis runs (the count can still grow), else
  /// `Done` or `N left`.
  String get label {
    if (!analysisFinished) return 'Analyzing...';
    if (unassignedLeft == 0) return 'Done';
    return '$unassignedLeft left';
  }

  FolderFaceStatus withUnassignedLeft(int count) =>
      FolderFaceStatus(analysisFinished: analysisFinished, unassignedLeft: count);

  @override
  bool operator ==(Object other) =>
      other is FolderFaceStatus &&
      other.analysisFinished == analysisFinished &&
      other.unassignedLeft == unassignedLeft;

  @override
  int get hashCode => Object.hash(analysisFinished, unassignedLeft);
}

/// Whether [item] is past analysis. Failed, cancelled, and refused files
/// are finished: they will never yield faces, so they must not block Done.
bool itemAnalysisFinished(Item item) {
  switch (item.processingStatus) {
    case ProcessingStatus.pending:
    case ProcessingStatus.awaitingModelAccess:
    case ProcessingStatus.processing:
      return false;
    case ProcessingStatus.tagged:
    case ProcessingStatus.failed:
    case ProcessingStatus.cancelled:
    case ProcessingStatus.refused:
      return true;
  }
}

/// Unassigned appearance count per item id (appearances without an item id
/// are ignored).
Map<String, int> unassignedCountByItemId(
  Iterable<PersonAppearance> unassigned,
) {
  final counts = <String, int>{};
  for (final a in unassigned) {
    final id = a.itemId;
    if (id == null) continue;
    counts[id] = (counts[id] ?? 0) + 1;
  }
  return counts;
}

/// Status per leaf folder (keyed like [distinctLeafFolders] entries).
Map<String, FolderFaceStatus> leafFolderStatuses(
  Iterable<Item> items,
  Map<String, int> unassignedByItemId,
) {
  final finished = <String, bool>{};
  final left = <String, int>{};
  for (final item in items) {
    final folder = leafFolderFromItem(item);
    if (folder == null) continue;
    finished[folder] =
        (finished[folder] ?? true) && itemAnalysisFinished(item);
    left[folder] = (left[folder] ?? 0) + (unassignedByItemId[item.id] ?? 0);
  }
  return {
    for (final folder in finished.keys)
      folder: FolderFaceStatus(
        analysisFinished: finished[folder]!,
        unassignedLeft: left[folder] ?? 0,
      ),
  };
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
