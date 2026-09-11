import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/item_lists_repository.dart';
import 'package:tagkin_desktop/api/items_repository.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/item_lists/item_list_csv.dart';
import 'package:tagkin_desktop/library/local_thumb_cache.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';

/// Writes [csv] via a native save dialog. Returns the path, or null if cancelled.
typedef ItemListCsvSaver = Future<String?> Function(String csv);

Future<String?> saveItemListCsvToFile(String csv) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Export item list',
    fileName: 'item-list.csv',
    type: FileType.custom,
    allowedExtensions: const ['csv'],
  );
  if (path == null || path.isEmpty) return null;
  final file = File(path.toLowerCase().endsWith('.csv') ? path : '$path.csv');
  await file.writeAsString(csv);
  return file.path;
}

/// Filter builder + reorderable filmstrip for POST /item-lists (D13).
///
/// Matching/dedup/sort stay on the server. Manual reorder and remove are
/// client-only and only affect the CSV export. Preview reloads from the server.
class ItemListExportController extends ChangeNotifier {
  ItemListExportController({
    required this.repository,
    required this.itemsRepository,
    LocalThumbCache? thumbCache,
    ItemListCsvSaver? saveCsv,
  })  : thumbCache = thumbCache ?? LocalThumbCache(),
        saveCsv = saveCsv ?? saveItemListCsvToFile;

  final ItemListsRepository repository;
  final ItemsRepository itemsRepository;
  final LocalThumbCache thumbCache;
  final ItemListCsvSaver saveCsv;

  ItemListFacets facets = const ItemListFacets(who: [], what: [], where: []);
  final Set<String> selectedWho = <String>{};
  final Set<String> selectedWhat = <String>{};
  final Set<String> selectedWhere = <String>{};
  DateTime? whenFromDay;
  DateTime? whenToDay;
  List<ItemListEntry> entries = const [];
  Map<String, Item> itemsById = const {};
  bool loadingFacets = false;
  bool loadingList = false;
  String? error;

  bool get hasEntries => entries.isNotEmpty;

  ItemListFilter buildFilter() {
    return ItemListFilter(
      who: selectedWho.isEmpty ? null : selectedWho.toList(),
      what: selectedWhat.isEmpty ? null : selectedWhat.toList(),
      where: selectedWhere.isEmpty ? null : selectedWhere.toList(),
      whenFrom: whenFromDay == null ? null : itemListWhenFromIso(whenFromDay!),
      whenTo: whenToDay == null ? null : itemListWhenToIso(whenToDay!),
    );
  }

  Future<void> load() async {
    loadingFacets = true;
    error = null;
    notifyListeners();
    try {
      facets = await repository.listFacets();
    } catch (e) {
      error = '$e';
    } finally {
      loadingFacets = false;
      notifyListeners();
    }
    await preview();
  }

  Future<void> preview() async {
    loadingList = true;
    error = null;
    notifyListeners();
    try {
      final list = await repository.createItemList(buildFilter());
      entries = List<ItemListEntry>.from(list.entries);
      await _refreshItems();
    } catch (e) {
      error = '$e';
      entries = const [];
      itemsById = const {};
    } finally {
      loadingList = false;
      notifyListeners();
    }
  }

  Future<void> _refreshItems() async {
    itemsById = const {};
    if (entries.isEmpty) return;
    try {
      final all = await itemsRepository.listItems(limit: 5000);
      final needed = {for (final e in entries) e.itemId};
      itemsById = {
        for (final item in all)
          if (needed.contains(item.id)) item.id: item,
      };
    } catch (_) {
      itemsById = const {};
    }
  }

  /// Local still for a filmstrip tile (photo or key-period frame). Never
  /// uploads bytes (R1).
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

  void toggleWho(String value) {
    _toggle(selectedWho, value);
  }

  void toggleWhat(String value) {
    _toggle(selectedWhat, value);
  }

  void toggleWhere(String value) {
    _toggle(selectedWhere, value);
  }

  void setWhenFromDay(DateTime? day) {
    whenFromDay = day;
    notifyListeners();
  }

  void setWhenToDay(DateTime? day) {
    whenToDay = day;
    notifyListeners();
  }

  void _toggle(Set<String> set, String value) {
    if (!set.add(value)) set.remove(value);
    notifyListeners();
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

  /// Drop one preview row. Client-only; Preview restores from the server.
  void removeAt(int index) {
    if (index < 0 || index >= entries.length) return;
    final next = List<ItemListEntry>.from(entries)..removeAt(index);
    entries = next;
    notifyListeners();
  }

  /// Save the current row order as CSV. Returns the path, or null if cancelled.
  Future<String?> exportCsv() async {
    if (entries.isEmpty) return null;
    return saveCsv(itemListToCsv(entries));
  }
}

final itemListCsvSaverProvider = Provider<ItemListCsvSaver>(
  (ref) => saveItemListCsvToFile,
);

final itemListExportControllerProvider =
    ChangeNotifierProvider.autoDispose<ItemListExportController>(
  (ref) {
    return ItemListExportController(
      repository: ref.watch(itemListsRepositoryProvider),
      itemsRepository: ref.watch(itemsRepositoryProvider),
      saveCsv: ref.watch(itemListCsvSaverProvider),
    );
  },
  dependencies: [
    itemListsRepositoryProvider,
    itemsRepositoryProvider,
    itemListCsvSaverProvider,
  ],
);

