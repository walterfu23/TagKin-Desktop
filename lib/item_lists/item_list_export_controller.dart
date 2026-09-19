import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/comments_repository.dart';
import 'package:tagkin_desktop/api/items_repository.dart';
import 'package:tagkin_desktop/api/persons_repository.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/folder_bookmark_store.dart';
import 'package:tagkin_desktop/item_lists/item_list_fcp7_xml.dart';
import 'package:tagkin_desktop/item_lists/item_list_fcpxml.dart';
import 'package:tagkin_desktop/item_lists/item_list_json.dart';
import 'package:tagkin_desktop/item_lists/item_list_media_size.dart';
import 'package:tagkin_desktop/item_lists/item_list_mp4_filter.dart';
import 'package:tagkin_desktop/item_lists/item_list_mp4_render.dart';
import 'package:tagkin_desktop/item_lists/item_list_nle.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/library/local_thumb_cache.dart';
import 'package:tagkin_desktop/persons/collection.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';

export 'package:tagkin_desktop/item_lists/item_list_nle.dart'
    show ItemListExportFormat;

/// Writes JSON via a native save dialog. Returns the path, or null if cancelled.
typedef ItemListJsonSaver = Future<String?> Function(String json);

/// Writes export [contents] via a native save dialog. Returns the path, or
/// null if cancelled.
typedef ItemListFileSaver = Future<String?> Function({
  required String contents,
  required ItemListExportFormat format,
});

/// Native Save As. Returns the path with [fileExtension], or null if cancelled.
typedef ItemListSavePathPicker = Future<String?> Function({
  required String fileExtension,
});

String? _activeSaveBookmark;
bool _macSaveSession = false;

Future<void> releaseItemListSavePath() async {
  final bookmark = _activeSaveBookmark;
  _activeSaveBookmark = null;
  final mac = _macSaveSession;
  _macSaveSession = false;
  if (mac && SecurityScopedBookmarks.isSupported) {
    try {
      await SecurityScopedBookmarks.releaseSaveFile();
    } catch (_) {}
  }
  if (bookmark == null || bookmark.isEmpty) return;
  if (!SecurityScopedBookmarks.isSupported) return;
  try {
    await SecurityScopedBookmarks.stopAccess(bookmark);
  } catch (_) {}
}

Future<void> deleteEmptyItemListExport(String path) async {
  try {
    final file = File(path);
    if (file.existsSync() && file.lengthSync() == 0) {
      await file.delete();
    }
  } catch (_) {}
}

void ensureItemListExportNonEmpty(String path) {
  final file = File(path);
  if (!file.existsSync() || file.lengthSync() == 0) {
    throw ItemListMp4RenderException(
      'The exported file was empty. Save As again and keep it in a folder TagKin can write.',
    );
  }
}

Future<String?> pickItemListSavePath({
  required String fileExtension,
}) async {
  await releaseItemListSavePath();
  final ext = fileExtension;
  if (SecurityScopedBookmarks.isSupported) {
    final picked = await SecurityScopedBookmarks.pickSaveFile(
      fileName: 'item-list.$ext',
      fileExtension: ext,
    );
    if (picked == null) return null;
    _macSaveSession = true;
    return picked.toLowerCase().endsWith('.$ext') ? picked : '$picked.$ext';
  }
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Export item list',
    fileName: 'item-list.$ext',
    type: FileType.custom,
    allowedExtensions: [ext],
    lockParentWindow: true,
  );
  if (path == null || path.isEmpty) return null;
  return path.toLowerCase().endsWith('.$ext') ? path : '$path.$ext';
}

Future<String?> saveItemListToFile({
  required String contents,
  required ItemListExportFormat format,
}) async {
  final path = await pickItemListSavePath(fileExtension: format.fileExtension);
  if (path == null) return null;
  try {
    if (_macSaveSession && SecurityScopedBookmarks.isSupported) {
      final dir = Directory.systemTemp.createTempSync('tagkin-export-');
      try {
        final tmp = File('${dir.path}/item-list.${format.fileExtension}');
        await tmp.writeAsString(contents);
        final n = await SecurityScopedBookmarks.installSaveFile(tmp.path);
        if (contents.isNotEmpty && n <= 0) {
          throw ItemListMp4RenderException(
            'The exported file was empty. Save As again and keep it in a folder TagKin can write.',
          );
        }
      } finally {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      }
    } else {
      await File(path).writeAsString(contents);
      if (contents.isNotEmpty) ensureItemListExportNonEmpty(path);
    }
    return path;
  } catch (e) {
    await deleteEmptyItemListExport(path);
    rethrow;
  } finally {
    await releaseItemListSavePath();
  }
}

typedef ItemListMp4Renderer = Future<void> Function({
  required ItemListNleTimeline timeline,
  required String audioPath,
  required String outputPath,
  required int sequenceWidth,
  required int sequenceHeight,
  required bool scaleToFit,
  double soundtrackDuck,
  ItemListMp4ProgressCallback? onProgress,
  ItemListMp4CancelToken? cancel,
});

Future<void> itemListRenderMp4Default({
  required ItemListNleTimeline timeline,
  required String audioPath,
  required String outputPath,
  required int sequenceWidth,
  required int sequenceHeight,
  required bool scaleToFit,
  double soundtrackDuck = kItemListMp4SoundtrackDuckDefault,
  ItemListMp4ProgressCallback? onProgress,
  ItemListMp4CancelToken? cancel,
}) {
  return itemListRenderMp4(
    timeline: timeline,
    audioPath: audioPath,
    outputPath: outputPath,
    sequenceWidth: sequenceWidth,
    sequenceHeight: sequenceHeight,
    scaleToFit: scaleToFit,
    soundtrackDuck: soundtrackDuck,
    onProgress: onProgress,
    cancel: cancel,
  );
}

String itemListEntryKey(ItemListEntry entry) =>
    entry.keyPeriodId ?? 'photo-${entry.itemId}';

ItemListFileSaver _resolveItemListSaver(
  ItemListJsonSaver? saveJson,
  ItemListFileSaver? saveFile,
) {
  if (saveJson != null) {
    return ({required contents, required format}) => saveJson(contents);
  }
  return saveFile ?? saveItemListToFile;
}

/// When [view] is Folders' current named view, overlay Folders' live
/// persistable filters so Export matches the table (unsaved Hide folder /
/// Hide item). Other saved views keep their last-saved snapshot.
SavedView exportViewMatchingFolders(
  SavedView view,
  LibraryTableController foldersTable,
) {
  if (view.id != foldersTable.activeViewId) return view;
  return view.copyWith(filters: foldersTable.persistableViewFilters());
}

/// Reorderable filmstrip of the photos and video key periods in a Folders View.
///
/// Matching uses D2's client-side [LibraryViewFilters] (a separate
/// [LibraryTableController] so Folders' own filters stay untouched). Manual
/// reorder and remove are client-only and only affect the export file.
class ItemListExportController extends ChangeNotifier {
  ItemListExportController({
    required ItemsRepository itemsRepository,
    required CommentsRepository commentsRepository,
    this.personsRepository,
    LocalThumbCache? thumbCache,
    ItemListJsonSaver? saveJson,
    ItemListFileSaver? saveFile,
    ItemListSavePathPicker? pickSavePath,
    ItemListMp4Renderer? renderMp4,
    LibraryTableController? libraryTable,
    ItemListMediaSizeProbe? probeMediaSize,
  })  : thumbCache = thumbCache ?? LocalThumbCache(),
        saveFile = _resolveItemListSaver(saveJson, saveFile),
        pickSavePath = pickSavePath ?? pickItemListSavePath,
        renderMp4 = renderMp4 ?? itemListRenderMp4Default,
        probeMediaSize = probeMediaSize ?? probeItemListMediaSize,
        _ownsLibraryTable = libraryTable == null {
    this.libraryTable = libraryTable ??
        LibraryTableController(
          itemsRepository: itemsRepository,
          commentsRepository: commentsRepository,
          personsRepository: personsRepository,
          thumbCache: this.thumbCache,
        );
    this.libraryTable.addListener(_onLibraryTableChanged);
  }

  final PersonsRepository? personsRepository;
  final LocalThumbCache thumbCache;
  final ItemListFileSaver saveFile;
  final ItemListSavePathPicker pickSavePath;
  final ItemListMp4Renderer renderMp4;
  final ItemListMediaSizeProbe probeMediaSize;
  late final LibraryTableController libraryTable;
  final bool _ownsLibraryTable;

  /// [saveFile] with a hot-reload fallback (new non-null fields read as
  /// null on instances created before the field existed).
  ItemListFileSaver get saveFileOrDefault {
    try {
      return saveFile;
    } on TypeError {
      return saveItemListToFile;
    }
  }

  ItemListSavePathPicker get pickSavePathOrDefault {
    try {
      return pickSavePath;
    } on TypeError {
      return pickItemListSavePath;
    }
  }

  ItemListMp4Renderer get renderMp4OrDefault {
    try {
      return renderMp4;
    } on TypeError {
      return itemListRenderMp4Default;
    }
  }

  ItemListMediaSizeProbe get probeMediaSizeOrDefault {
    try {
      return probeMediaSize;
    } on TypeError {
      return probeItemListMediaSize;
    }
  }

  List<ItemListEntry> entries = const [];
  Map<String, Item> itemsById = const {};
  bool loadingList = false;
  String? error;
  SavedView? selectedView;
  final Set<String> _removedKeys = <String>{};
  bool _disposed = false;
  ItemListMp4Phase? mp4Phase;
  int? mp4ClipIndex;
  int? mp4ClipCount;
  ItemListMp4CancelToken? _mp4Cancel;

  bool get hasEntries => entries.isNotEmpty;

  /// Status line while MP4 export is encoding; null otherwise.
  String? get mp4ProgressLabel {
    final phase = mp4Phase;
    if (phase == null) return null;
    return itemListMp4ProgressLabel(
      ItemListMp4Progress(
        phase: phase,
        clipIndex: mp4ClipIndex,
        clipCount: mp4ClipCount,
      ),
    );
  }

  void _clearMp4Progress() {
    mp4Phase = null;
    mp4ClipIndex = null;
    mp4ClipCount = null;
  }

  /// Kill in-flight ffmpeg for this export (no-op when idle).
  void cancelMp4() {
    _mp4Cancel?.cancel();
  }

  Future<void> load({
    Set<String>? collectionFolders,
    SavedView? view,
  }) async {
    if (collectionFolders != null) {
      libraryTable.setCollectionLeafFolders(collectionFolders);
    }
    loadingList = true;
    error = null;
    notifyListeners();
    await libraryTable.ensureLoaded();
    if (_disposed) return;
    if (view != null) {
      await selectView(view);
      return;
    }
    _onLibraryTableChanged();
  }

  void setCollectionFolders(Set<String>? folders) {
    libraryTable.setCollectionLeafFolders(folders);
  }

  /// Apply a saved Folders view, or [LibraryViewFilters.all] when [view] is null.
  Future<void> selectView(SavedView? view, {double? blurThreshold}) async {
    selectedView = view;
    _removedKeys.clear();
    final filters = view?.filters ?? LibraryViewFilters.all;
    libraryTable.setHideBlurryPhotos(
      filters.hideBlurryPhotos,
      threshold: blurThreshold,
    );
    await libraryTable.applyLibraryViewFilters(filters);
    if (_disposed) return;
    loadingList = libraryTable.loading;
    entries = _entriesFromTable();
    _syncItemsById();
    notifyListeners();
  }

  /// Cached [GET /items/{id}/knowledge] periods for hover preview.
  KeyPeriodKnowledge? periodFor(ItemListEntry entry) {
    if (entry.kind != ItemListEntryKind.keyperiod) return null;
    final row = libraryTable.rowById(entry.itemId);
    if (row == null) return null;
    for (final period in row.keyPeriods) {
      if (period.id == entry.keyPeriodId) return period;
    }
    return null;
  }

  /// Local still for a filmstrip tile (photo or first frame of a key period).
  /// Never uploads bytes (R1).
  Future<LocalThumbResult> thumbFor(ItemListEntry entry) {
    final item = itemsById[entry.itemId];
    if (item == null) {
      return Future.value(
        const LocalThumbResult(status: LocalMediaStatus.missing),
      );
    }
    if (entry.kind == ItemListEntryKind.keyperiod) {
      return thumbCache.resolveKeyPeriod(
        item,
        keyPeriodId: entry.keyPeriodId ?? entry.itemId,
        timestampMs: entry.startMs ?? 0,
      );
    }
    return thumbCache.resolve(item);
  }

  /// Drag-reorder. [newIndex] is already adjusted (Flutter [onReorderItem]).
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= entries.length) return;
    if (newIndex < 0 || newIndex >= entries.length) return;
    if (oldIndex == newIndex) return;
    final next = List<ItemListEntry>.from(entries);
    final item = next.removeAt(oldIndex);
    next.insert(newIndex, item);
    entries = next;
    notifyListeners();
  }

  /// Drop one preview row. Client-only; selecting the view again restores it.
  void removeAt(int index) {
    if (index < 0 || index >= entries.length) return;
    final next = List<ItemListEntry>.from(entries);
    final removed = next.removeAt(index);
    _removedKeys.add(itemListEntryKey(removed));
    entries = next;
    notifyListeners();
  }

  /// Save the current filmstrip as JSON. Returns the path, or null if
  /// cancelled or nothing is visible.
  Future<String?> exportJson({
    String description = '',
    DateTime? exportedAt,
  }) {
    return export(
      format: ItemListExportFormat.json,
      description: description,
      exportedAt: exportedAt,
    );
  }

  /// Save the current filmstrip in [format]. Returns the path, or null if
  /// cancelled or nothing is visible.
  Future<String?> export({
    ItemListExportFormat format = ItemListExportFormat.json,
    String description = '',
    DateTime? exportedAt,
    double stillDurationSeconds = kItemListNleStillDurationSeconds,
    ExportPhotoTransition transition = ExportPhotoTransition.crossDissolve,
    double transitionSeconds = kItemListNleTransitionSeconds,
    ExportSequenceSize sequenceSize = ExportSequenceSize.matchSmallest,
  }) async {
    if (entries.isEmpty) return null;
    if (format == ItemListExportFormat.mp4WithMusic) {
      throw ArgumentError('MP4 with music uses exportMp4');
    }
    final trimmed = description.trim();
    var fileSizes = const <String, ItemListPixelSize>{};
    var sequenceWidth = kItemListNleWidth;
    var sequenceHeight = kItemListNleHeight;
    if (format != ItemListExportFormat.json) {
      fileSizes = await _probeFileSizes();
      final seq = itemListNleSequencePixelSize(
        mode: sequenceSize,
        probed: fileSizes.values,
      );
      sequenceWidth = seq.width;
      sequenceHeight = seq.height;
    }
    final contents = switch (format) {
      ItemListExportFormat.json => itemListToJson(
          entries: entries,
          itemsById: itemsById,
          view: selectedView,
          description: trimmed,
          exportedAt: exportedAt ?? DateTime.now(),
        ),
      ItemListExportFormat.fcp7Xml => itemListToFcp7Xml(
          entries: entries,
          itemsById: itemsById,
          view: selectedView,
          description: trimmed,
          stillDurationSeconds: stillDurationSeconds,
          transition: transition,
          transitionSeconds: transitionSeconds,
          sequenceWidth: sequenceWidth,
          sequenceHeight: sequenceHeight,
          fileSizesByItemId: fileSizes,
          scaleToFit: sequenceSize.scaleToFit,
        ),
      ItemListExportFormat.fcpxml => itemListToFcpxml(
          entries: entries,
          itemsById: itemsById,
          view: selectedView,
          description: trimmed,
          stillDurationSeconds: stillDurationSeconds,
          transition: transition,
          transitionSeconds: transitionSeconds,
          sequenceWidth: sequenceWidth,
          sequenceHeight: sequenceHeight,
          fileSizesByItemId: fileSizes,
          scaleToFit: sequenceSize.scaleToFit,
        ),
      ItemListExportFormat.mp4WithMusic => throw ArgumentError(
          'MP4 with music uses exportMp4',
        ),
    };
    return saveFileOrDefault(contents: contents, format: format);
  }

  /// NLE timeline for the current filmstrip (preview duration / MP4 render).
  ItemListNleTimeline currentTimeline({
    String description = '',
    double stillDurationSeconds = kItemListNleStillDurationSeconds,
    ExportPhotoTransition transition = ExportPhotoTransition.crossDissolve,
    double transitionSeconds = kItemListNleTransitionSeconds,
  }) {
    return itemListNleTimeline(
      entries: entries,
      itemsById: itemsById,
      view: selectedView,
      description: description,
      stillDurationSeconds: stillDurationSeconds,
      transition: transition,
      transitionSeconds: transitionSeconds,
    );
  }

  /// Render a local MP4 (stills + key periods + generated music).
  ///
  /// Opens Save As first, then encodes to that path.
  Future<String?> exportMp4({
    required String audioPath,
    String description = '',
    double stillDurationSeconds = kItemListNleStillDurationSeconds,
    ExportPhotoTransition transition = ExportPhotoTransition.crossDissolve,
    double transitionSeconds = kItemListNleTransitionSeconds,
    ExportSequenceSize sequenceSize = ExportSequenceSize.matchSmallest,
    double soundtrackDuck = kItemListMp4SoundtrackDuckDefault,
  }) async {
    if (entries.isEmpty) return null;
    final picked = await pickSavePathOrDefault(fileExtension: 'mp4');
    if (picked == null || picked.isEmpty) return null;
    _mp4Cancel = ItemListMp4CancelToken();
    mp4Phase = ItemListMp4Phase.staging;
    if (!_disposed) notifyListeners();
    try {
      final fileSizes = await _probeFileSizes();
      _mp4Cancel?.throwIfCancelled();
      final seq = itemListNleSequencePixelSize(
        mode: sequenceSize,
        probed: fileSizes.values,
      );
      final timeline = itemListNleTimeline(
        entries: entries,
        itemsById: itemsById,
        view: selectedView,
        description: description.trim(),
        stillDurationSeconds: stillDurationSeconds,
        transition: transition,
        transitionSeconds: transitionSeconds,
      );
      await renderMp4OrDefault(
        timeline: timeline,
        audioPath: audioPath,
        outputPath: picked,
        sequenceWidth: seq.width,
        sequenceHeight: seq.height,
        scaleToFit: sequenceSize.scaleToFit,
        soundtrackDuck: soundtrackDuck,
        onProgress: (progress) {
          if (_disposed) return;
          mp4Phase = progress.phase;
          mp4ClipIndex = progress.clipIndex;
          mp4ClipCount = progress.clipCount;
          notifyListeners();
        },
        cancel: _mp4Cancel,
      );
      if (!(_macSaveSession && SecurityScopedBookmarks.isSupported)) {
        ensureItemListExportNonEmpty(picked);
      }
      return picked;
    } catch (e) {
      await deleteEmptyItemListExport(picked);
      if (e is ItemListMp4CancelledException) return null;
      rethrow;
    } finally {
      _mp4Cancel = null;
      _clearMp4Progress();
      if (!_disposed) notifyListeners();
      await releaseItemListSavePath();
    }
  }

  Future<Map<String, ItemListPixelSize>> _probeFileSizes() async {
    final out = <String, ItemListPixelSize>{};
    final seen = <String>{};
    for (final e in entries) {
      if (!seen.add(e.itemId)) continue;
      final path = itemListNleLocalPath(e, itemsById);
      if (path == null || path.isEmpty) continue;
      final size = await probeMediaSizeOrDefault(
        path,
        isStill: e.kind != ItemListEntryKind.keyperiod,
      );
      if (size != null && size.isValid) out[e.itemId] = size;
    }
    return out;
  }

  void _onLibraryTableChanged() {
    if (_disposed) return;
    loadingList = libraryTable.loading;
    final tableError = libraryTable.error;
    error = tableError == null ? null : '$tableError';
    _syncItemsById();
    entries = _mergeEntries(entries, _entriesFromTable());
    notifyListeners();
  }

  void _syncItemsById() {
    itemsById = {
      for (final row in libraryTable.allRows) row.item.id: row.item,
    };
  }

  List<ItemListEntry> _entriesFromTable() {
    final out = <ItemListEntry>[];
    for (final row in libraryTable.filteredSorted) {
      if (row.item.type == ItemType.photo) {
        out.add(
          ItemListEntry(
            kind: ItemListEntryKind.photo,
            itemId: row.item.id,
            when: row.item.capturedAt,
            who: row.who,
            what: row.what,
            where: row.where,
          ),
        );
        continue;
      }
      final periods = List<KeyPeriodKnowledge>.from(row.keyPeriods)
        ..sort((a, b) => a.startMs.compareTo(b.startMs));
      for (final period in periods) {
        final summary = row.summaryFor(period);
        out.add(
          ItemListEntry(
            kind: ItemListEntryKind.keyperiod,
            itemId: row.item.id,
            keyPeriodId: period.id,
            startMs: period.startMs,
            endMs: period.endMs,
            when: row.item.capturedAt,
            who: summary?.who ?? row.who,
            what: summary?.what ?? row.what,
            where: summary != null
                ? [for (final e in summary.whereEntries) e.label]
                : row.where,
          ),
        );
      }
    }
    return out;
  }

  List<ItemListEntry> _mergeEntries(
    List<ItemListEntry> current,
    List<ItemListEntry> incoming,
  ) {
    final incomingByKey = {
      for (final e in incoming) itemListEntryKey(e): e,
    };
    final seen = <String>{};
    final out = <ItemListEntry>[];
    for (final e in current) {
      final key = itemListEntryKey(e);
      if (_removedKeys.contains(key)) continue;
      final fresh = incomingByKey[key];
      if (fresh == null) continue;
      seen.add(key);
      out.add(fresh);
    }
    for (final e in incoming) {
      final key = itemListEntryKey(e);
      if (_removedKeys.contains(key)) continue;
      if (seen.add(key)) out.add(e);
    }
    return out;
  }

  @override
  void dispose() {
    _disposed = true;
    _mp4Cancel?.cancel();
    libraryTable.removeListener(_onLibraryTableChanged);
    if (_ownsLibraryTable) {
      libraryTable.dispose();
    }
    super.dispose();
  }
}

final itemListJsonSaverProvider = Provider<ItemListJsonSaver?>(
  (ref) => null,
);

final itemListFileSaverProvider = Provider<ItemListFileSaver>(
  (ref) => saveItemListToFile,
);

final itemListSavePathPickerProvider = Provider<ItemListSavePathPicker>(
  (ref) => pickItemListSavePath,
);

final itemListMp4RendererProvider = Provider<ItemListMp4Renderer>(
  (ref) => itemListRenderMp4Default,
);

final itemListExportControllerProvider =
    ChangeNotifierProvider.autoDispose<ItemListExportController>(
  (ref) {
    return ItemListExportController(
      itemsRepository: ref.watch(itemsRepositoryProvider),
      commentsRepository: ref.watch(commentsRepositoryProvider),
      personsRepository: ref.watch(personsRepositoryProvider),
      saveJson: ref.watch(itemListJsonSaverProvider),
      saveFile: ref.watch(itemListFileSaverProvider),
      pickSavePath: ref.watch(itemListSavePathPickerProvider),
      renderMp4: ref.watch(itemListMp4RendererProvider),
    );
  },
  dependencies: [
    itemsRepositoryProvider,
    commentsRepositoryProvider,
    personsRepositoryProvider,
    itemListJsonSaverProvider,
    itemListFileSaverProvider,
    itemListSavePathPickerProvider,
    itemListMp4RendererProvider,
  ],
);
