import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/persons/collection.dart';
import 'package:tagkin_desktop/persons/collections_store.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';
import 'package:uuid/uuid.dart';

/// Result of a dirty-prompt: save first, discard changes, or cancel the action.
enum DirtyPromptChoice { save, discard, cancel }

const _uuid = Uuid();

/// Mints a new collection GUID (UUID v4).
String newCollectionId() => _uuid.v4();

/// In-memory catalog + optional current named collection.
///
/// Under development — not shipped. No Untitled collection: first empty catalog
/// mints Collection1; later sessions resume [CollectionsFile.currentCollectionId]
/// when still in the catalog, otherwise show the New/Open start gate.
///
/// A library leaf folder path may appear in at most one collection's
/// [Collection.leafFolders] (enforced in memory against the loaded catalog).
///
/// Dirty = structural diff vs last-saved baseline (name / folders / page look)
/// OR sticky [markDirty] activity (Faces moves, deletes, etc.).
class CollectionsController extends ChangeNotifier {
  CollectionsController({
    CollectionsStore? store,
    this._maxRecents,
  }) : _store = store ?? CollectionsStore();

  final CollectionsStore _store;
  final int Function()? _maxRecents;
  CollectionsFile _catalog = CollectionsFile.empty;
  Collection? _current;
  Collection? _baseline;
  bool _dirty = false;
  bool _activityDirty = false;
  bool _loaded = false;

  /// True once this session has an active named collection (gate cleared).
  bool _sessionReady = false;

  /// Bumped when callers should re-apply [current.ui] (open / mint / discard).
  int _uiEpoch = 0;

  List<String> _libraryFolders = const [];

  CollectionsFile get catalog => _catalog;
  List<Collection> get collections => _catalog.collections;
  Collection? get currentOrNull => _current;
  Collection get current =>
      _current ??
      const Collection(id: '', name: '', leafFolders: []);
  bool get hasCurrent => _current != null;
  bool get dirty => _dirty;
  bool get loaded => _loaded;
  bool get sessionReady => _sessionReady && _current != null;
  int get uiEpoch => _uiEpoch;

  /// GUID of the collection that currently lists [folder], if any.
  /// Prefers the dirty in-memory current over a stale catalog row for the same id.
  String? ownerCollectionId(String folder) {
    if (folder.isEmpty) return null;
    final cur = _current;
    if (cur != null && cur.leafFolders.contains(folder)) return cur.id;
    for (final c in _catalog.collections) {
      if (cur != null && c.id == cur.id) continue;
      if (c.leafFolders.contains(folder)) return c.id;
    }
    return null;
  }

  /// Library folders claimed by any collection other than [exceptId].
  Set<String> foldersClaimedByOthers({required String exceptId}) {
    final claimed = <String>{};
    final cur = _current;
    for (final c in _catalog.collections) {
      if (c.id == exceptId) continue;
      if (cur != null && c.id == cur.id) continue;
      claimed.addAll(c.leafFolders);
    }
    if (cur != null && cur.id != exceptId) {
      claimed.addAll(cur.leafFolders);
    }
    return claimed;
  }

  List<Collection> get recentCollections {
    final byId = {for (final c in _catalog.collections) c.id: c};
    final limit =
        (_maxRecents?.call() ?? CollectionsFile.maxRecents).clamp(1, 100);
    final out = <Collection>[];
    for (final id in _catalog.recentCollectionIds) {
      final c = byId[id];
      if (c == null) continue;
      out.add(c);
      if (out.length >= limit) break;
    }
    return out;
  }

  String get chromeLabel {
    final c = _current;
    if (c == null) return '';
    return _dirty ? '${c.name}*' : c.name;
  }

  Future<void> load() async {
    _catalog = await _store.load();
    _current = null;
    _baseline = null;
    _dirty = false;
    _activityDirty = false;
    _sessionReady = false;
    _loaded = true;
    notifyListeners();
  }

  void setLibraryFolders(List<String> libraryFolders) {
    _libraryFolders = List<String>.of(libraryFolders);
  }

  /// First run: empty catalog → mint Collection1 (or CollectionN), open it.
  /// Otherwise resume [CollectionsFile.currentCollectionId] when still present.
  /// Returns true if a collection is ready (mint, resume, or already ready).
  /// Returns false when the start gate must show (non-empty, no valid current).
  Future<bool> bootstrapSession(List<String> libraryFolders) async {
    _libraryFolders = List<String>.of(libraryFolders);
    if (!_loaded) await load();
    if (_sessionReady && _current != null) return true;
    if (_catalog.collections.isEmpty) {
      await _mintDefaultCollection(libraryFolders);
      return true;
    }
    final id = _catalog.currentCollectionId;
    if (id != null && _catalog.collections.any((c) => c.id == id)) {
      return open(id);
    }
    return false;
  }

  /// Drop the in-memory open session; catalog on disk is unchanged.
  /// Used on sign-out so the next auth re-runs [bootstrapSession] from disk.
  void clearSession() {
    _current = null;
    _baseline = null;
    _dirty = false;
    _activityDirty = false;
    _sessionReady = false;
    notifyListeners();
  }

  /// If the open collection has no folders yet (e.g. minted before library load),
  /// fill with unowned [libraryFolders] and persist without marking dirty.
  Future<void> fillMembershipIfEmpty(List<String> libraryFolders) async {
    final cur = _current;
    if (cur == null || cur.leafFolders.isNotEmpty) return;
    if (libraryFolders.isEmpty) return;
    _libraryFolders = List<String>.of(libraryFolders);
    final claimed = foldersClaimedByOthers(exceptId: cur.id);
    final folders = [
      for (final f in libraryFolders)
        if (!claimed.contains(f)) f,
    ];
    if (folders.isEmpty) return;
    _current = cur.copyWith(leafFolders: folders);
    await _writeCurrentToCatalog(_current!);
    _captureBaseline();
    notifyListeners();
  }

  String _nextDefaultName() {
    var n = 1;
    while (_nameTaken('Collection$n')) {
      n++;
    }
    return 'Collection$n';
  }

  Future<void> _mintDefaultCollection(List<String> libraryFolders) async {
    final name = _nextDefaultName();
    final created = Collection(
      id: newCollectionId(),
      name: name,
      leafFolders: List<String>.of(libraryFolders),
    );
    _current = created;
    _sessionReady = true;
    await _writeCurrentToCatalog(created);
    await _touchRecent(created.id);
    _captureBaseline();
    _bumpUiEpoch();
    notifyListeners();
  }

  void _captureBaseline() {
    final cur = _current;
    _baseline = cur == null ? null : _cloneCollection(cur);
    _activityDirty = false;
    _dirty = false;
  }

  void _bumpUiEpoch() {
    _uiEpoch++;
  }

  Collection _cloneCollection(Collection c) => Collection(
        id: c.id,
        name: c.name,
        leafFolders: List<String>.of(c.leafFolders),
        ui: c.ui,
      );

  /// Structural fields only (id ignored for dirty — same collection).
  bool _structurallyEqual(Collection a, Collection b) =>
      a.name == b.name &&
      _listEq(a.leafFolders, b.leafFolders) &&
      a.ui == b.ui;

  void _recomputeDirty({bool notify = true}) {
    final baseline = _baseline;
    final cur = _current;
    final structural = cur != null &&
        baseline != null &&
        !_structurallyEqual(cur, baseline);
    final next = _activityDirty || structural;
    if (next == _dirty) {
      if (notify) notifyListeners();
      return;
    }
    _dirty = next;
    if (notify) notifyListeners();
  }

  bool _nameTaken(String name, {String? excludingId}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    for (final c in _catalog.collections) {
      if (excludingId != null && c.id == excludingId) continue;
      if (c.name.toLowerCase() == trimmed.toLowerCase()) return true;
    }
    final cur = _current;
    if (cur != null &&
        (excludingId == null || cur.id != excludingId) &&
        !_catalog.collections.any((c) => c.id == cur.id) &&
        cur.name.toLowerCase() == trimmed.toLowerCase()) {
      return true;
    }
    return false;
  }

  Future<bool> _resolveDirtyIfNeeded({
    Future<DirtyPromptChoice> Function()? resolveDirty,
  }) async {
    if (!_dirty) return true;
    final choice = resolveDirty == null
        ? DirtyPromptChoice.cancel
        : await resolveDirty();
    if (choice == DirtyPromptChoice.cancel) return false;
    if (choice == DirtyPromptChoice.save) {
      return save();
    }
    _discardInMemory();
    notifyListeners();
    return true;
  }

  void _discardInMemory() {
    final id = _current?.id;
    if (id != null) {
      for (final c in _catalog.collections) {
        if (c.id == id) {
          _current = c;
          _captureBaseline();
          _bumpUiEpoch();
          return;
        }
      }
    }
    _current = null;
    _baseline = null;
    _dirty = false;
    _activityDirty = false;
    _sessionReady = false;
  }

  Future<bool> create({
    required String name,
    List<String> seedFolders = const [],
    Future<DirtyPromptChoice> Function()? resolveDirty,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    if (!await _resolveDirtyIfNeeded(resolveDirty: resolveDirty)) return false;
    if (_nameTaken(trimmed)) return false;
    final id = newCollectionId();
    final claimed = foldersClaimedByOthers(exceptId: id);
    final folders = [
      for (final f in seedFolders)
        if (f.isNotEmpty && !claimed.contains(f)) f,
    ];
    _current = Collection(
      id: id,
      name: trimmed,
      leafFolders: folders,
    );
    _sessionReady = true;
    await _writeCurrentToCatalog(_current!);
    await _touchRecent(_current!.id);
    _captureBaseline();
    _bumpUiEpoch();
    notifyListeners();
    return true;
  }

  Future<bool> open(
    String id, {
    Future<DirtyPromptChoice> Function()? resolveDirty,
  }) async {
    Collection? target;
    for (final c in _catalog.collections) {
      if (c.id == id) {
        target = c;
        break;
      }
    }
    if (target == null) return false;
    if (_current?.id == id && !_dirty && _sessionReady) return true;
    if (!await _resolveDirtyIfNeeded(resolveDirty: resolveDirty)) return false;
    _current = target;
    _sessionReady = true;
    await _persistCurrentId(target.id);
    await _touchRecent(target.id);
    _captureBaseline();
    _bumpUiEpoch();
    notifyListeners();
    return true;
  }

  /// Sticky dirty for in-session work that is not in the collection file
  /// (Faces moves, item deletes, etc.). Cleared on Save; Discard does not
  /// roll back those server mutations.
  void markDirty() {
    if (!sessionReady) return;
    if (_activityDirty && _dirty) return;
    _activityDirty = true;
    _dirty = true;
    notifyListeners();
  }

  /// Updates Faces look; dirties when it differs from baseline, clears when
  /// everything matches again (and no activity dirty).
  void updateFacesLook({
    String? leafFolder,
    String? personId,
    bool clearPersonId = false,
    bool clearLeafFolder = false,
  }) {
    final cur = _current;
    if (cur == null || !sessionReady) return;
    final nextFaces = cur.ui.faces.copyWith(
      leafFolder: leafFolder,
      personId: personId,
      clearPersonId: clearPersonId,
      clearLeafFolder: clearLeafFolder,
    );
    if (nextFaces == cur.ui.faces) return;
    _current = cur.copyWith(ui: cur.ui.copyWith(faces: nextFaces));
    _recomputeDirty();
  }

  /// Updates Folders (library) look vs baseline.
  void updateLibraryLook(CollectionLibraryUi library) {
    final cur = _current;
    if (cur == null || !sessionReady) return;
    if (library == cur.ui.library) return;
    _current = cur.copyWith(ui: cur.ui.copyWith(library: library));
    _recomputeDirty();
  }

  /// Writes Folders look into current + baseline without marking dirty.
  /// Used after restoring collection UI (auto-expand) so login does not show *.
  void adoptLibraryLook(CollectionLibraryUi library) {
    final cur = _current;
    if (cur == null || !sessionReady) return;
    if (library == cur.ui.library &&
        _baseline != null &&
        library == _baseline!.ui.library) {
      return;
    }
    _current = cur.copyWith(ui: cur.ui.copyWith(library: library));
    final base = _baseline;
    if (base != null) {
      _baseline = base.copyWith(ui: base.ui.copyWith(library: library));
    }
    _recomputeDirty();
  }

  bool rename(String name) {
    final cur = _current;
    if (cur == null) return false;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    if (_nameTaken(trimmed, excludingId: cur.id)) return false;
    if (trimmed == cur.name) return true;
    _current = cur.copyWith(name: trimmed);
    _recomputeDirty();
    return true;
  }

  bool addFolder(String folder) {
    final cur = _current;
    if (cur == null || folder.isEmpty) return false;
    if (cur.leafFolders.contains(folder)) return true;
    final owner = ownerCollectionId(folder);
    if (owner != null && owner != cur.id) return false;
    _current = cur.copyWith(leafFolders: [...cur.leafFolders, folder]);
    _recomputeDirty();
    return true;
  }

  bool removeFolder(String folder) {
    final cur = _current;
    if (cur == null) return false;
    if (!cur.leafFolders.contains(folder)) return true;
    _current = cur.copyWith(
      leafFolders: [
        for (final f in cur.leafFolders)
          if (f != folder) f,
      ],
    );
    _recomputeDirty();
    return true;
  }

  Future<bool> save() async {
    final cur = _current;
    if (cur == null || cur.name.trim().isEmpty) return false;
    await _writeCurrentToCatalog(cur);
    await _touchRecent(cur.id);
    _captureBaseline();
    notifyListeners();
    return true;
  }

  /// Save a copy under [name] and switch current to that copy.
  /// New GUID + copied page look; folder membership starts empty (exclusivity).
  Future<bool> saveAs(String name) async {
    final cur = _current;
    if (cur == null) return false;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    if (_nameTaken(trimmed)) return false;
    // Persist dirty edits onto the original first so Save as keeps latest look.
    if (_dirty && _catalog.collections.any((c) => c.id == cur.id)) {
      await _writeCurrentToCatalog(cur);
    }
    final copy = Collection(
      id: newCollectionId(),
      name: trimmed,
      leafFolders: const [],
      ui: cur.ui,
    );
    _current = copy;
    _sessionReady = true;
    await _writeCurrentToCatalog(copy);
    await _touchRecent(copy.id);
    _captureBaseline();
    _bumpUiEpoch();
    notifyListeners();
    return true;
  }

  Future<bool> delete({
    Future<bool> Function()? confirm,
  }) async {
    final cur = _current;
    if (cur == null) return false;
    if (confirm != null) {
      final ok = await confirm();
      if (!ok) return false;
    }
    final next = [
      for (final c in _catalog.collections)
        if (c.id != cur.id) c,
    ];
    final recents = [
      for (final id in _catalog.recentCollectionIds)
        if (id != cur.id) id,
    ];
    _catalog = CollectionsFile(
      collections: next,
      currentCollectionId: null,
      recentCollectionIds: recents,
    );
    await _store.save(_catalog);
    _current = null;
    _baseline = null;
    _dirty = false;
    _activityDirty = false;
    _sessionReady = false;
    notifyListeners();
    if (next.isEmpty) {
      await _mintDefaultCollection(_libraryFolders);
    }
    return true;
  }

  Future<bool> confirmLeaveIfDirty({
    required Future<DirtyPromptChoice> Function() resolveDirty,
  }) async {
    if (!_dirty) return true;
    final choice = await resolveDirty();
    if (choice == DirtyPromptChoice.cancel) return false;
    if (choice == DirtyPromptChoice.discard) {
      _discardInMemory();
      notifyListeners();
      return true;
    }
    return save();
  }

  Future<void> _writeCurrentToCatalog(Collection cur) async {
    final next = <Collection>[];
    var found = false;
    for (final c in _catalog.collections) {
      if (c.id == cur.id) {
        next.add(cur);
        found = true;
      } else {
        next.add(c);
      }
    }
    if (!found) next.add(cur);
    _catalog = CollectionsFile(
      collections: next,
      currentCollectionId: cur.id,
      recentCollectionIds: _catalog.recentCollectionIds,
    );
    await _store.save(_catalog);
  }

  Future<void> _persistCurrentId(String? id) async {
    if (_catalog.currentCollectionId == id) return;
    _catalog = _catalog.copyWith(
      currentCollectionId: id,
      clearCurrent: id == null,
    );
    await _store.save(_catalog);
  }

  Future<void> _touchRecent(String id) async {
    final limit = (_maxRecents?.call() ?? CollectionsFile.maxRecents).clamp(1, 100);
    final next = <String>[id];
    for (final existing in _catalog.recentCollectionIds) {
      if (existing != id) next.add(existing);
      if (next.length >= limit) break;
    }
    if (_listEq(next, _catalog.recentCollectionIds)) return;
    _catalog = _catalog.copyWith(recentCollectionIds: next);
    await _store.save(_catalog);
  }
}

bool _listEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

final collectionsStoreProvider = Provider<CollectionsStore>((ref) {
  return CollectionsStore();
});

final collectionsControllerProvider =
    ChangeNotifierProvider<CollectionsController>((ref) {
  final controller = CollectionsController(
    store: ref.read(collectionsStoreProvider),
    maxRecents: () => ref.read(desktopPrefsProvider).recentCollectionsLimit,
  );
  controller.load();
  return controller;
});
