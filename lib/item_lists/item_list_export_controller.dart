import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/item_lists_repository.dart';
import 'package:tagkin_desktop/api/items_repository.dart';
import 'package:tagkin_desktop/api/persons_repository.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/item_lists/item_list_csv.dart';
import 'package:tagkin_desktop/item_lists/item_list_faces.dart';
import 'package:tagkin_desktop/item_lists/item_list_json.dart';
import 'package:tagkin_desktop/library/local_thumb_cache.dart';
import 'package:tagkin_desktop/review/knowledge_grouping.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';

/// Writes [json] via a native save dialog. Returns the path, or null if cancelled.
typedef ItemListJsonSaver = Future<String?> Function(String json);

Future<String?> saveItemListJsonToFile(String json) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Export item list',
    fileName: 'item-list.json',
    type: FileType.custom,
    allowedExtensions: const ['json'],
  );
  if (path == null || path.isEmpty) return null;
  final file = File(path.toLowerCase().endsWith('.json') ? path : '$path.json');
  await file.writeAsString(json);
  return file.path;
}

/// Filter builder + reorderable filmstrip for POST /item-lists (D13).
///
/// Matching/dedup/sort stay on the server. Manual reorder and remove are
/// client-only and only affect the JSON export. Preview reloads from the server.
class ItemListExportController extends ChangeNotifier {
  ItemListExportController({
    required this.repository,
    required this.itemsRepository,
    this.personsRepository,
    LocalThumbCache? thumbCache,
    ItemListJsonSaver? saveJson,
  })  : thumbCache = thumbCache ?? LocalThumbCache(),
        saveJson = saveJson ?? saveItemListJsonToFile;

  final ItemListsRepository repository;
  final ItemsRepository itemsRepository;
  final PersonsRepository? personsRepository;
  final LocalThumbCache thumbCache;
  final ItemListJsonSaver saveJson;

  ItemListFacets facets = const ItemListFacets(who: [], what: [], where: []);
  final Set<String> selectedWho = <String>{};
  final Set<String> selectedWhat = <String>{};
  final Set<String> selectedWhere = <String>{};
  DateTime? whenFromDay;
  DateTime? whenToDay;
  List<ItemListEntry> entries = const [];
  Map<String, Item> itemsById = const {};
  Map<String, ItemKnowledge> knowledgeByItemId = {};
  Map<String, String> personNameById = const {};
  final Map<String, Future<ItemKnowledge?>> _knowledgeInflight = {};
  bool loadingFacets = false;
  bool loadingList = false;
  String? error;
  /// Filter last sent to `POST /item-lists` that produced [entries].
  ItemListFilter? lastPreviewFilter;

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
    await _refreshPersons();
    await preview();
  }

  Future<void> _refreshPersons() async {
    final repo = personsRepository;
    if (repo == null) {
      personNameById = const {};
      return;
    }
    try {
      final people = await repo.listPersons();
      personNameById = {for (final p in people) p.id: p.name};
    } catch (_) {
      personNameById = const {};
    }
  }

  Future<void> preview() async {
    loadingList = true;
    error = null;
    notifyListeners();
    try {
      final filter = _snapshotFilter(buildFilter());
      final list = await repository.createItemList(filter);
      entries = List<ItemListEntry>.from(list.entries);
      lastPreviewFilter = filter;
      knowledgeByItemId = {};
      _knowledgeInflight.clear();
      await _refreshItems();
    } catch (e) {
      error = '$e';
      entries = const [];
      itemsById = const {};
      knowledgeByItemId = {};
      lastPreviewFilter = null;
    } finally {
      loadingList = false;
      notifyListeners();
    }
  }

  ItemListFilter _snapshotFilter(ItemListFilter filter) {
    return ItemListFilter(
      who: filter.who == null ? null : List<String>.from(filter.who!),
      what: filter.what == null ? null : List<String>.from(filter.what!),
      where: filter.where == null ? null : List<String>.from(filter.where!),
      whenFrom: filter.whenFrom,
      whenTo: filter.whenTo,
    );
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

  /// Cached [GET /items/{id}/knowledge]. Fail closed on 404 / network.
  Future<ItemKnowledge?> knowledgeFor(String itemId) {
    final hit = knowledgeByItemId[itemId];
    if (hit != null) return Future.value(hit);
    return _knowledgeInflight.putIfAbsent(itemId, () async {
      try {
        final knowledge = await itemsRepository.getKnowledge(itemId);
        knowledgeByItemId[itemId] = knowledge;
        notifyListeners();
        return knowledge;
      } catch (_) {
        return null;
      } finally {
        _knowledgeInflight.remove(itemId);
      }
    });
  }

  /// Analyze-frame timestamp for a key-period still (`sampleTimestampMs`).
  int timestampMsFor(ItemListEntry entry) {
    if (entry.kind != ItemListEntryKind.keyperiod) return 0;
    final knowledge = knowledgeByItemId[entry.itemId];
    if (knowledge != null) {
      final sample = sampleTimestampMsForKeyPeriodId(
        knowledge,
        entry.keyPeriodId,
      );
      if (sample != null) return sample;
    }
    return entry.startMs ?? 0;
  }

  List<({String id, TagRegion region})> faceRegionsFor(ItemListEntry entry) {
    final knowledge = knowledgeByItemId[entry.itemId];
    if (knowledge == null) return const [];
    return selectedWhoFaceRegions(
      entry: entry,
      knowledge: knowledge,
      selectedWho: selectedWho,
      personNameById: personNameById,
    );
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
        timestampMs: timestampMsFor(entry),
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

  /// Entries visible under the shared Hide blurry toggle
  /// ([DesktopPrefs.hideBlurryPhotos]). Photos below [threshold] on stored
  /// pre-pass sharpness are hidden. Unknown stays visible. Key periods and
  /// Who chips never change this rule.
  List<ItemListEntry> visibleEntries({
    required bool hideBlurry,
    double threshold = kBlurrySharpnessThreshold,
  }) {
    if (!hideBlurry) return entries;
    final out = <ItemListEntry>[];
    for (final entry in entries) {
      final item =
          entry.kind == ItemListEntryKind.photo ? itemsById[entry.itemId] : null;
      if (isBlurryItemListEntry(
        entry: entry,
        item: item,
        threshold: threshold,
      )) {
        continue;
      }
      out.add(entry);
    }
    return out;
  }

  /// Save the current visible order as JSON (Hide blurry excludes hidden
  /// photos from the export, same as from the on-screen filmstrip). Returns
  /// the path, or null if cancelled or nothing is visible.
  Future<String?> exportJson({
    required bool hideBlurry,
    double threshold = kBlurrySharpnessThreshold,
    String description = '',
    DateTime? exportedAt,
  }) async {
    final visible = visibleEntries(hideBlurry: hideBlurry, threshold: threshold);
    if (visible.isEmpty) return null;
    return saveJson(
      itemListToJson(
        entries: visible,
        itemsById: itemsById,
        filters: lastPreviewFilter,
        description: description.trim(),
        exportedAt: exportedAt ?? DateTime.now(),
      ),
    );
  }
}

final itemListJsonSaverProvider = Provider<ItemListJsonSaver>(
  (ref) => saveItemListJsonToFile,
);

final itemListExportControllerProvider =
    ChangeNotifierProvider.autoDispose<ItemListExportController>(
  (ref) {
    return ItemListExportController(
      repository: ref.watch(itemListsRepositoryProvider),
      itemsRepository: ref.watch(itemsRepositoryProvider),
      personsRepository: ref.watch(personsRepositoryProvider),
      saveJson: ref.watch(itemListJsonSaverProvider),
    );
  },
  dependencies: [
    itemListsRepositoryProvider,
    itemsRepositoryProvider,
    personsRepositoryProvider,
    itemListJsonSaverProvider,
  ],
);

