import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/comments_repository.dart';
import 'package:tagkin_desktop/api/items_repository.dart';
import 'package:tagkin_desktop/api/persons_repository.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/item_lists/item_list_fcp7_xml.dart';
import 'package:tagkin_desktop/item_lists/item_list_fcpxml.dart';
import 'package:tagkin_desktop/item_lists/item_list_json.dart';
import 'package:tagkin_desktop/item_lists/item_list_media_size.dart';
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

Future<String?> saveItemListToFile({
  required String contents,
  required ItemListExportFormat format,
}) async {
  final ext = format.fileExtension;
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Export item list',
    fileName: 'item-list.$ext',
    type: FileType.custom,
    allowedExtensions: [ext],
  );
  if (path == null || path.isEmpty) return null;
  final file = File(
    path.toLowerCase().endsWith('.$ext') ? path : '$path.$ext',
  );
  await file.writeAsString(contents);
  return file.path;
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
    LibraryTableController? libraryTable,
    ItemListMediaSizeProbe? probeMediaSize,
  })  : thumbCache = thumbCache ?? LocalThumbCache(),
        saveFile = _resolveItemListSaver(saveJson, saveFile),
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
    };
    return saveFileOrDefault(contents: contents, format: format);
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

final itemListExportControllerProvider =
    ChangeNotifierProvider.autoDispose<ItemListExportController>(
  (ref) {
    return ItemListExportController(
      itemsRepository: ref.watch(itemsRepositoryProvider),
      commentsRepository: ref.watch(commentsRepositoryProvider),
      personsRepository: ref.watch(personsRepositoryProvider),
      saveJson: ref.watch(itemListJsonSaverProvider),
      saveFile: ref.watch(itemListFileSaverProvider),
    );
  },
  dependencies: [
    itemsRepositoryProvider,
    commentsRepositoryProvider,
    personsRepositoryProvider,
    itemListJsonSaverProvider,
    itemListFileSaverProvider,
  ],
);
