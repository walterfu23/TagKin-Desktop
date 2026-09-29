import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/comments_repository.dart';
import 'package:tagkin_desktop/api/item_lists_repository.dart';
import 'package:tagkin_desktop/api/items_repository.dart';
import 'package:tagkin_desktop/api/persons_repository.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart'
    hide ItemListExportFormat;
import 'package:tagkin_desktop/contract/contract.dart'
    as api
    show ItemListExportFormat;
import 'package:tagkin_desktop/ingest/folder_bookmark_store.dart';
import 'package:tagkin_desktop/item_lists/item_list_fcp7_xml.dart';
import 'package:tagkin_desktop/item_lists/item_list_fcpxml.dart';
import 'package:tagkin_desktop/item_lists/item_list_export_jobs.dart';
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
typedef ItemListFileSaver =
    Future<String?> Function({
      required String contents,
      required ItemListExportFormat format,
      required String fileStem,
    });

/// Native Save As. Returns the path (and macOS handle), or null if cancelled.
/// [fileStem] is the suggested name without an extension.
typedef ItemListSavePathPicker =
    Future<ItemListSavePick?> Function({
      required String fileExtension,
      required String fileStem,
    });

/// Path from Save As. [macSaveHandle] is set on macOS so each export keeps
/// its own panel URL.
class ItemListSavePick {
  const ItemListSavePick({required this.path, this.macSaveHandle});

  final String path;
  final String? macSaveHandle;
}

/// Save As name without an extension. A named view uses its name. Built-in
/// All, a blank name, or a name with no legal characters uses `All`.
String itemListExportFileStem(SavedView? view) {
  final raw = view?.name.trim() ?? '';
  final stem = raw.isEmpty ? 'All' : raw;
  final cleaned = stem
      .replaceAll(RegExp(r'[\x00-\x1f\\/:*?"<>|]'), '')
      .trim()
      .replaceAll(RegExp(r'\.+$'), '')
      .trim();
  return cleaned.isEmpty ? 'All' : cleaned;
}

Future<ItemListSavePick?> pickItemListSavePath({
  required String fileExtension,
  required String fileStem,
}) async {
  final ext = fileExtension;
  final name = '$fileStem.$ext';
  if (SecurityScopedBookmarks.isSupported) {
    final picked = await SecurityScopedBookmarks.pickSaveFile(
      fileName: name,
      fileExtension: ext,
    );
    if (picked == null) return null;
    final path = picked.path.toLowerCase().endsWith('.$ext')
        ? picked.path
        : '${picked.path}.$ext';
    return ItemListSavePick(path: path, macSaveHandle: picked.handle);
  }
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Export item list',
    fileName: name,
    type: FileType.custom,
    allowedExtensions: [ext],
    lockParentWindow: true,
  );
  if (path == null || path.isEmpty) return null;
  final full = path.toLowerCase().endsWith('.$ext') ? path : '$path.$ext';
  return ItemListSavePick(path: full);
}

Future<String?> saveItemListToFile({
  required String contents,
  required ItemListExportFormat format,
  required String fileStem,
}) async {
  final picked = await pickItemListSavePath(
    fileExtension: format.fileExtension,
    fileStem: fileStem,
  );
  if (picked == null) return null;
  final path = picked.path;
  final handle = picked.macSaveHandle;
  try {
    if (handle != null && SecurityScopedBookmarks.isSupported) {
      final dir = Directory.systemTemp.createTempSync('tagkin-export-');
      try {
        final tmp = File('${dir.path}/item-list.${format.fileExtension}');
        await tmp.writeAsString(contents);
        final n = await SecurityScopedBookmarks.installSaveFile(
          handle: handle,
          sourcePath: tmp.path,
        );
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
    if (handle != null) {
      try {
        await SecurityScopedBookmarks.releaseSaveFile(handle);
      } catch (_) {}
    }
  }
}

Future<void> itemListRenderMp4Default({
  required ItemListNleTimeline timeline,
  required String? audioPath,
  required String outputPath,
  required int sequenceWidth,
  required int sequenceHeight,
  required bool scaleToFit,
  double soundtrackDuck = kItemListMp4SoundtrackDuckDefault,
  ItemListMp4ProgressCallback? onProgress,
  ItemListMp4CancelToken? cancel,
  String? macSaveHandle,
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
    macSaveHandle: macSaveHandle,
  );
}

String itemListEntryKey(ItemListEntry entry) =>
    entry.keyPeriodId ?? 'photo-${entry.itemId}';

ItemListFileSaver _resolveItemListSaver(
  ItemListJsonSaver? saveJson,
  ItemListFileSaver? saveFile,
) {
  if (saveJson != null) {
    return ({required contents, required format, required fileStem}) =>
        saveJson(contents);
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
    this.itemListsRepository,
    ItemListExportJobManager? jobs,
  }) : thumbCache = thumbCache ?? LocalThumbCache(),
       saveFile = _resolveItemListSaver(saveJson, saveFile),
       pickSavePath = pickSavePath ?? pickItemListSavePath,
       renderMp4 = renderMp4 ?? itemListRenderMp4Default,
       probeMediaSize = probeMediaSize ?? probeItemListMediaSize,
       _ownsExportJobs = jobs == null,
       exportJobs =
           jobs ??
           ItemListExportJobManager(
             renderMp4: renderMp4 ?? itemListRenderMp4Default,
             probeMediaSize: probeMediaSize ?? probeItemListMediaSize,
             itemListsRepository: itemListsRepository,
           ),
       _ownsLibraryTable = libraryTable == null {
    this.libraryTable =
        libraryTable ??
        LibraryTableController(
          itemsRepository: itemsRepository,
          commentsRepository: commentsRepository,
          personsRepository: personsRepository,
          thumbCache: this.thumbCache,
        );
    this.libraryTable.addListener(_onLibraryTableChanged);
  }

  final PersonsRepository? personsRepository;
  final ItemListsRepository? itemListsRepository;
  final LocalThumbCache thumbCache;
  final ItemListFileSaver saveFile;
  final ItemListSavePathPicker pickSavePath;
  final ItemListMp4Renderer renderMp4;
  final ItemListMediaSizeProbe probeMediaSize;
  final ItemListExportJobManager exportJobs;
  late final LibraryTableController libraryTable;
  final bool _ownsLibraryTable;
  final bool _ownsExportJobs;

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

  bool get hasEntries => entries.isNotEmpty;

  Future<void> load({Set<String>? collectionFolders, SavedView? view}) async {
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
  Future<void> selectView(SavedView? view) async {
    selectedView = view;
    _removedKeys.clear();
    final filters = view?.filters ?? LibraryViewFilters.all;
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
  Future<String?> exportJson({DateTime? exportedAt}) {
    return export(format: ItemListExportFormat.json, exportedAt: exportedAt);
  }

  /// Save the current filmstrip in [format]. Returns the path, or null if
  /// cancelled or nothing is visible.
  Future<String?> export({
    ItemListExportFormat format = ItemListExportFormat.json,
    DateTime? exportedAt,
    double stillDurationSeconds = kItemListNleStillDurationSeconds,
    ExportPhotoTransition transition = ExportPhotoTransition.crossDissolve,
    double transitionSeconds = kItemListNleTransitionSeconds,
    ExportSequenceSize sequenceSize = ExportSequenceSize.matchSmallest,
  }) async {
    if (entries.isEmpty) return null;
    if (format.isMp4) {
      throw ArgumentError('MP4 uses exportMp4');
    }
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
        exportedAt: exportedAt ?? DateTime.now(),
      ),
      ItemListExportFormat.fcp7Xml => itemListToFcp7Xml(
        entries: entries,
        itemsById: itemsById,
        view: selectedView,
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
        stillDurationSeconds: stillDurationSeconds,
        transition: transition,
        transitionSeconds: transitionSeconds,
        sequenceWidth: sequenceWidth,
        sequenceHeight: sequenceHeight,
        fileSizesByItemId: fileSizes,
        scaleToFit: sequenceSize.scaleToFit,
      ),
      ItemListExportFormat.mp4WithMusic ||
      ItemListExportFormat.mp4 => throw ArgumentError('MP4 uses exportMp4'),
    };
    final path = await saveFileOrDefault(
      contents: contents,
      format: format,
      fileStem: itemListExportFileStem(selectedView),
    );
    if (path != null && path.isNotEmpty) {
      unawaited(
        _recordSuccessfulExport(
          format: format,
          stillDurationSeconds: stillDurationSeconds,
          transition: transition,
          transitionSeconds: transitionSeconds,
        ),
      );
    }
    return path;
  }

  /// NLE timeline for the current filmstrip (preview duration / MP4 render).
  ItemListNleTimeline currentTimeline({
    double stillDurationSeconds = kItemListNleStillDurationSeconds,
    ExportPhotoTransition transition = ExportPhotoTransition.crossDissolve,
    double transitionSeconds = kItemListNleTransitionSeconds,
    double endFadeSeconds = kItemListNleEndFadeSeconds,
  }) {
    return itemListNleTimeline(
      entries: entries,
      itemsById: itemsById,
      view: selectedView,
      stillDurationSeconds: stillDurationSeconds,
      transition: transition,
      transitionSeconds: transitionSeconds,
      endFadeSeconds: endFadeSeconds,
    );
  }

  /// Queue a local MP4 export (stills + key periods + generated music).
  ///
  /// Opens Save As first, snapshots the filmstrip, and returns the job.
  /// Encoding continues after this future completes. Null when the list is
  /// empty or Save As is cancelled.
  Future<ItemListExportJob?> exportMp4({
    String? audioPath,
    double stillDurationSeconds = kItemListNleStillDurationSeconds,
    ExportPhotoTransition transition = ExportPhotoTransition.crossDissolve,
    double transitionSeconds = kItemListNleTransitionSeconds,
    ExportSequenceSize sequenceSize = ExportSequenceSize.matchSmallest,
    double soundtrackDuck = kItemListMp4SoundtrackDuckDefault,
  }) async {
    if (entries.isEmpty) return null;
    final picked = await pickSavePathOrDefault(
      fileExtension: 'mp4',
      fileStem: itemListExportFileStem(selectedView),
    );
    if (picked == null || picked.path.isEmpty) return null;
    return exportJobs.start(
      ItemListMp4ExportRequest(
        entries: List<ItemListEntry>.from(entries),
        itemsById: Map<String, Item>.from(itemsById),
        view: selectedView,
        stillDurationSeconds: stillDurationSeconds,
        transition: transition,
        transitionSeconds: transitionSeconds,
        sequenceSize: sequenceSize,
        soundtrackDuck: soundtrackDuck,
        audioPath: audioPath,
        outputPath: picked.path,
        macSaveHandle: picked.macSaveHandle,
      ),
    );
  }

  Future<void> _recordSuccessfulExport({
    required ItemListExportFormat format,
    required double stillDurationSeconds,
    required ExportPhotoTransition transition,
    required double transitionSeconds,
    int? encodeWallMs,
  }) async {
    final repo = itemListsRepository;
    if (repo == null) return;
    try {
      final timeline = currentTimeline(
        stillDurationSeconds: stillDurationSeconds,
        transition: transition,
        transitionSeconds: transitionSeconds,
        endFadeSeconds: format == ItemListExportFormat.json
            ? 0
            : kItemListNleEndFadeSeconds,
      );
      await repo.recordExport(
        RecordItemListExport(
          format: api.ItemListExportFormat.fromWire(switch (format) {
            ItemListExportFormat.json => 'json',
            ItemListExportFormat.fcp7Xml => 'fcp7Xml',
            ItemListExportFormat.fcpxml => 'fcpxml',
            ItemListExportFormat.mp4WithMusic => 'mp4WithMusic',
            ItemListExportFormat.mp4 => 'mp4WithoutMusic',
          }),
          photoCount: entries
              .where((e) => e.kind == ItemListEntryKind.photo)
              .length,
          keyPeriodCount: entries
              .where((e) => e.kind == ItemListEntryKind.keyperiod)
              .length,
          outputDurationMs: itemListNleTimelineDurationMs(timeline),
          encodeWallMs: encodeWallMs,
        ),
      );
    } catch (e, st) {
      debugPrint('item-list-export record failed: $e\n$st');
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
    itemsById = {for (final row in libraryTable.allRows) row.item.id: row.item};
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
    final incomingByKey = {for (final e in incoming) itemListEntryKey(e): e};
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
    libraryTable.removeListener(_onLibraryTableChanged);
    if (_ownsExportJobs) exportJobs.dispose();
    if (_ownsLibraryTable) {
      libraryTable.dispose();
    }
    super.dispose();
  }
}

final itemListJsonSaverProvider = Provider<ItemListJsonSaver?>((ref) => null);

final itemListFileSaverProvider = Provider<ItemListFileSaver>(
  (ref) => saveItemListToFile,
);

final itemListSavePathPickerProvider = Provider<ItemListSavePathPicker>(
  (ref) => pickItemListSavePath,
);

final itemListMp4RendererProvider = Provider<ItemListMp4Renderer>(
  (ref) => itemListRenderMp4Default,
);

final itemListExportJobManagerProvider =
    ChangeNotifierProvider<ItemListExportJobManager>(
      (ref) {
        return ItemListExportJobManager(
          renderMp4: ref.watch(itemListMp4RendererProvider),
          itemListsRepository: ref.watch(itemListsRepositoryProvider),
        );
      },
      dependencies: [itemListMp4RendererProvider, itemListsRepositoryProvider],
    );

final itemListExportControllerProvider =
    ChangeNotifierProvider.autoDispose<ItemListExportController>(
      (ref) {
        return ItemListExportController(
          itemsRepository: ref.watch(itemsRepositoryProvider),
          commentsRepository: ref.watch(commentsRepositoryProvider),
          personsRepository: ref.watch(personsRepositoryProvider),
          itemListsRepository: ref.watch(itemListsRepositoryProvider),
          saveJson: ref.watch(itemListJsonSaverProvider),
          saveFile: ref.watch(itemListFileSaverProvider),
          pickSavePath: ref.watch(itemListSavePathPickerProvider),
          renderMp4: ref.watch(itemListMp4RendererProvider),
          // read, not watch: each encode progress tick notifies the job manager.
          // Watching it rebuilds this controller and drops the filmstrip, which
          // disables Export while a job is running.
          jobs: ref.read(itemListExportJobManagerProvider),
        );
      },
      dependencies: [
        itemsRepositoryProvider,
        commentsRepositoryProvider,
        personsRepositoryProvider,
        itemListsRepositoryProvider,
        itemListJsonSaverProvider,
        itemListFileSaverProvider,
        itemListSavePathPickerProvider,
        itemListMp4RendererProvider,
        itemListExportJobManagerProvider,
      ],
    );
