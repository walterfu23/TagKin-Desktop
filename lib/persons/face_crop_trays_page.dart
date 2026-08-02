import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/folder_ingest_queue.dart';
import 'package:tagkin_desktop/library/item_detail_page.dart';
import 'package:tagkin_desktop/persons/face_crop_drag.dart';
import 'package:tagkin_desktop/persons/face_crop_folder_scope.dart';
import 'package:tagkin_desktop/persons/person_detail_controller.dart';
import 'package:tagkin_desktop/persons/person_name_dialog.dart';
import 'package:tagkin_desktop/persons/who_exclusion_crop_thumb.dart';
import 'package:tagkin_desktop/persons/who_face_crop_thumb.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

/// Request to focus the (already-mounted) Faces trays on a person / folder.
///
/// Written by [openFaceCropTrays]; consumed by [FaceCropTraysPage] via
/// [faceCropFocusRequestProvider]. [nonce] makes repeated identical focuses
/// distinguishable so the listener always fires.
class FaceCropFocusRequest {
  const FaceCropFocusRequest({
    this.personId,
    this.leafFolder,
    required this.nonce,
  });

  final String? personId;
  final String? leafFolder;
  final int nonce;
}

int _faceCropFocusNonce = 0;

/// Pending focus for the Faces tab (null when idle).
final faceCropFocusRequestProvider =
    StateProvider<FaceCropFocusRequest?>((ref) => null);

/// One successful tray move — enough to patch local lists without a full reload.
class _FaceMoveResult {
  const _FaceMoveResult({
    this.removedAppearanceId,
    this.removedExclusionId,
    this.addedAppearance,
    this.addedExclusion,
  });

  final String? removedAppearanceId;
  final String? removedExclusionId;
  final PersonAppearance? addedAppearance;
  final WhoExclusion? addedExclusion;
}

/// Override for widget tests (Cmd/Ctrl simulation is flaky under flutter_test).
@visibleForTesting
bool Function()? debugFaceCropMetaPressed;

bool faceCropMetaPressed() {
  final override = debugFaceCropMetaPressed;
  if (override != null) return override();
  final keys = HardwareKeyboard.instance.logicalKeysPressed;
  return keys.contains(LogicalKeyboardKey.metaLeft) ||
      keys.contains(LogicalKeyboardKey.metaRight) ||
      keys.contains(LogicalKeyboardKey.controlLeft) ||
      keys.contains(LogicalKeyboardKey.controlRight);
}

/// Resolves Finder-style single vs double click without [GestureDetector.onDoubleTap]
/// (that delays [onTap] and breaks [WidgetTester.pumpAndSettle] / immediate select chrome).
class FaceCropTapTracker {
  String? _lastId;
  DateTime? _lastAt;

  /// Returns true if this tap should open the item (second click of a double-click).
  bool registerTap(String id) {
    final now = DateTime.now();
    if (_lastId == id &&
        _lastAt != null &&
        now.difference(_lastAt!) < kDoubleTapTimeout) {
      _lastId = null;
      _lastAt = null;
      return true;
    }
    _lastId = id;
    _lastAt = now;
    return false;
  }

  void clear() {
    _lastId = null;
    _lastAt = null;
  }
}

/// Side-by-side Faces trays: Assigned | Unassigned | Excluded.
///
/// Work is scoped to one **leaf folder** at a time (picker in the app bar).
/// Persons stay library-wide; trays only show faces from the selected folder.
///
/// Finder-style face thumbs: single-click selects, Cmd/Ctrl+click multi-selects,
/// double-click opens the item. Drag a selection between trays. **Assigned**
/// holds appearances on a named person (boxes when ≥2 faces — GroupP).
/// **Unassigned** holds loose faces (personId and faceGroupId both null) plus
/// auto/manual likeness clusters (GroupFA/GroupFM, boxed when ≥2) — **Set
/// name** promotes a cluster or a loose Unassigned face straight to a named
/// person.
class FaceCropTraysPage extends ConsumerStatefulWidget {
  const FaceCropTraysPage({
    super.key,
    this.initialPersonId,
    this.initialLeafFolder,
  });

  /// When set, load this person into the Assigned column.
  final String? initialPersonId;

  /// When set (and still present in the library), select this leaf folder.
  final String? initialLeafFolder;

  @override
  ConsumerState<FaceCropTraysPage> createState() => _FaceCropTraysPageState();
}

class _FaceCropTraysPageState extends ConsumerState<FaceCropTraysPage> {
  /// Sentinel dropdown value: next drop onto Assigned names a new person.
  static const _newPersonSentinel = '__new_person__';

  String? _personId;
  PersonDetailController? _assignedController;
  List<Person> _persons = const [];
  List<PersonAppearance> _assignedOverview = const [];
  List<PersonAppearance> _unassigned = const [];
  List<WhoExclusion> _excluded = const [];
  List<String> _leafFolders = const [];
  String? _leafFolder;
  Set<String> _scopedItemIds = const {};
  bool _loading = true;
  bool _busy = false;
  Object? _error;

  /// One-shot: next [_reload] selects the first person with faces in the folder.
  bool _autoSelectFirstInFolder = false;

  /// Person dropdown on "New Person...": drop onto Assigned prompts for a name.
  bool _assignAsNewPerson = false;

  final _renameController = TextEditingController();
  bool _renaming = false;

  /// Multi-select (same tray + kind only).
  final Set<String> _selectedIds = <String>{};
  FaceCropTray? _selectionTray;
  FaceCropSelectKind? _selectionKind;
  final FaceCropTapTracker _faceTapTracker = FaceCropTapTracker();
  final _clusterScrollController = ScrollController();
  final Map<String, GlobalKey> _clusterKeys = <String, GlobalKey>{};

  static const _trayPageLimit = 500;

  int _lastIngestRefreshTick = 0;
  bool _lastIngestHadActiveJobs = false;
  FolderIngestQueue? _ingestQueue;

  /// Last [FaceCropFocusRequest.nonce] applied (avoids re-applying).
  int? _lastFocusNonce;

  void _clearSelection() {
    _faceTapTracker.clear();
    if (_selectedIds.isEmpty &&
        _selectionTray == null &&
        _selectionKind == null) {
      return;
    }
    setState(() {
      _selectedIds.clear();
      _selectionTray = null;
      _selectionKind = null;
    });
  }

  void _selectAppearance(
    PersonAppearance a,
    FaceCropTray tray, {
    required bool toggle,
  }) {
    setState(() {
      if (toggle &&
          _selectionTray == tray &&
          _selectionKind == FaceCropSelectKind.appearance) {
        if (!_selectedIds.remove(a.id)) {
          _selectedIds.add(a.id);
        }
        if (_selectedIds.isEmpty) {
          _selectionTray = null;
          _selectionKind = null;
        }
      } else {
        _selectedIds
          ..clear()
          ..add(a.id);
        _selectionTray = tray;
        _selectionKind = FaceCropSelectKind.appearance;
      }
    });
    final pid = a.personId;
    if (pid != null) {
      _selectPerson(pid);
    }
  }

  void _selectExclusion(WhoExclusion e, {required bool toggle}) {
    setState(() {
      if (toggle &&
          _selectionTray == FaceCropTray.excluded &&
          _selectionKind == FaceCropSelectKind.exclusion) {
        if (!_selectedIds.remove(e.id)) {
          _selectedIds.add(e.id);
        }
        if (_selectedIds.isEmpty) {
          _selectionTray = null;
          _selectionKind = null;
        }
      } else {
        _selectedIds
          ..clear()
          ..add(e.id);
        _selectionTray = FaceCropTray.excluded;
        _selectionKind = FaceCropSelectKind.exclusion;
      }
    });
  }

  /// Selects every face in a boxed Unassigned FaceGroup (FA/FM) for dragging.
  void _selectFaceGroupCluster(String faceGroupId, List<PersonAppearance> faces) {
    if (faces.isEmpty) return;
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(faces.map((a) => a.id));
      _selectionTray = FaceCropTray.unassigned;
      _selectionKind = FaceCropSelectKind.appearance;
    });
  }

  /// Selects every exclusion in a boxed Excluded FaceGroup for dragging.
  void _selectExcludedFaceGroupCluster(List<WhoExclusion> faces) {
    if (faces.isEmpty) return;
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(faces.map((e) => e.id));
      _selectionTray = FaceCropTray.excluded;
      _selectionKind = FaceCropSelectKind.exclusion;
    });
  }

  FaceCropDragPayload _excludedClusterDragPayload(List<WhoExclusion> faces) {
    return FaceCropDragPayload(
      source: FaceCropTray.excluded,
      items: [
        for (final e in faces)
          FaceCropDragData.exclusion(
            source: FaceCropTray.excluded,
            exclusionId: e.id,
            itemId: e.itemId,
            region: e.region,
            createdFromTagId: e.createdFromTagId,
            faceGroupId: e.faceGroupId,
            faceGroupKind: e.faceGroupKind,
          ),
      ],
    );
  }

  Set<String> _selectionFor(FaceCropTray tray, FaceCropSelectKind kind) {
    if (_selectionTray == tray && _selectionKind == kind) {
      return Set<String>.from(_selectedIds);
    }
    return const {};
  }

  GlobalKey _clusterKey(String id) => _clusterKeys.putIfAbsent(id, GlobalKey.new);

  void _scrollToCluster(String personId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _clusterKey(personId).currentContext;
      if (ctx == null || !ctx.mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.05,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Person? _lookupPerson(String? id) {
    if (id == null) return null;
    for (final p in _persons) {
      if (p.id == id) return p;
    }
    return null;
  }

  Person _personForId(String id) {
    return _lookupPerson(id) ?? Person(id: id, name: id, createdAt: '');
  }

  /// Group in-folder Assigned appearances by personId (dropdown order).
  List<({Person person, List<PersonAppearance> faces})> _clustersFrom(
    List<PersonAppearance> appearances,
  ) {
    final byPerson = <String, List<PersonAppearance>>{};
    for (final a in appearances) {
      final pid = a.personId;
      if (pid == null) continue;
      (byPerson[pid] ??= <PersonAppearance>[]).add(a);
    }
    if (byPerson.isEmpty) return const [];
    final inFolder = byPerson.keys.toSet();
    final ordered = <({Person person, List<PersonAppearance> faces})>[];
    for (final p in _sortPersonsForDropdown(_persons, inFolder)) {
      final faces = byPerson.remove(p.id);
      if (faces == null) continue;
      ordered.add((person: p, faces: faces));
    }
    for (final entry in byPerson.entries) {
      ordered.add((
        person: _personForId(entry.key),
        faces: entry.value,
      ));
    }
    return ordered;
  }

  List<PersonAppearance> get _linkedInFolder =>
      _scopedAppearances(_assignedOverview);

  /// Person, ≥2 faces in folder — Assigned cluster boxes (GroupP).
  List<({Person person, List<PersonAppearance> faces})> _assignedMultiClusters() {
    return [
      for (final c in _clustersFrom(_linkedInFolder))
        if (c.faces.length >= 2) c,
    ];
  }

  /// Person, exactly one face in folder — Assigned loose thumbs.
  List<PersonAppearance> _assignedSoloFaces() {
    return [
      for (final c in _clustersFrom(_linkedInFolder))
        if (c.faces.length == 1) c.faces.first,
    ];
  }

  /// FaceGroup (FA/FM), ≥2 faces in folder — Unassigned cluster boxes.
  List<({String faceGroupId, FaceGroupKind kind, List<PersonAppearance> faces})>
      _faceGroupMultiClusters() {
    final byGroup = <String, List<PersonAppearance>>{};
    final kindByGroup = <String, FaceGroupKind>{};
    for (final a in _scopedAppearances(_unassigned)) {
      final fg = a.faceGroupId;
      if (fg == null) continue;
      (byGroup[fg] ??= <PersonAppearance>[]).add(a);
      final kind = a.faceGroupKind;
      if (kind != null) kindByGroup[fg] = kind;
    }
    final clusters = [
      for (final entry in byGroup.entries)
        if (entry.value.length >= 2)
          (
            faceGroupId: entry.key,
            kind: kindByGroup[entry.key] ?? FaceGroupKind.fa,
            faces: entry.value,
          ),
    ];
    clusters.sort((a, b) => a.faceGroupId.compareTo(b.faceGroupId));
    return clusters;
  }

  /// FaceGroup (FA/FM), ≥2 exclusions in folder — Excluded cluster boxes.
  List<({String faceGroupId, FaceGroupKind kind, List<WhoExclusion> faces})>
      _excludedFaceGroupMultiClusters() {
    final scoped = [
      for (final e in _excluded)
        if (_exclusionInScope(e)) e,
    ];
    final byGroup = <String, List<WhoExclusion>>{};
    final kindByGroup = <String, FaceGroupKind>{};
    for (final e in scoped) {
      final fg = e.faceGroupId;
      if (fg == null) continue;
      (byGroup[fg] ??= <WhoExclusion>[]).add(e);
      final kind = e.faceGroupKind;
      if (kind != null) kindByGroup[fg] = kind;
    }
    final clusters = [
      for (final entry in byGroup.entries)
        if (entry.value.length >= 2)
          (
            faceGroupId: entry.key,
            kind: kindByGroup[entry.key] ?? FaceGroupKind.fa,
            faces: entry.value,
          ),
    ];
    clusters.sort((a, b) => a.faceGroupId.compareTo(b.faceGroupId));
    return clusters;
  }

  /// No faceGroupId, or a FA/FM group with <2 faces in this folder.
  List<PersonAppearance> _unassignedLooseFaces() {
    final counts = <String, int>{};
    for (final a in _scopedAppearances(_unassigned)) {
      final fg = a.faceGroupId;
      if (fg != null) counts[fg] = (counts[fg] ?? 0) + 1;
    }
    return [
      for (final a in _scopedAppearances(_unassigned))
        if (a.faceGroupId == null || (counts[a.faceGroupId] ?? 0) < 2) a,
    ];
  }

  /// Exclusions with no faceGroupId, or a FA/FM group with <2 in this folder.
  List<WhoExclusion> _excludedLooseFaces() {
    final scoped = [
      for (final e in _excluded)
        if (_exclusionInScope(e)) e,
    ];
    final counts = <String, int>{};
    for (final e in scoped) {
      final fg = e.faceGroupId;
      if (fg != null) counts[fg] = (counts[fg] ?? 0) + 1;
    }
    return [
      for (final e in scoped)
        if (e.faceGroupId == null || (counts[e.faceGroupId] ?? 0) < 2) e,
    ];
  }

  int get _unassignedTrayFaceCount => _scopedAppearances(_unassigned).length;

  void _selectCluster(
    Person person,
    List<PersonAppearance> faces,
    FaceCropTray tray,
  ) {
    if (faces.isEmpty) return;
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(faces.map((a) => a.id));
      _selectionTray = tray;
      _selectionKind = FaceCropSelectKind.appearance;
    });
    _selectPerson(person.id);
  }

  FaceCropDragPayload _clusterDragPayload(
    List<PersonAppearance> faces,
    FaceCropTray source,
  ) {
    return FaceCropDragPayload(
      source: source,
      items: [
        for (final a in faces)
          if (a.itemId != null && a.tagId != null)
            FaceCropDragData.appearance(
              source: source,
              appearanceId: a.id,
              itemId: a.itemId!,
              tagId: a.tagId!,
              personId: a.personId,
              faceGroupId: a.faceGroupId,
              faceGroupKind: a.faceGroupKind,
              region: a.region,
            ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _personId = widget.initialPersonId;
    _leafFolder = widget.initialLeafFolder ?? faceCropLastLeafFolder;
    // First open: land on first in-folder person (same as folder switch).
    // Deep links with initialPersonId keep that selection.
    if (widget.initialPersonId == null) {
      _autoSelectFirstInFolder = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final ingest = ref.read(folderIngestQueueProvider);
        _ingestQueue = ingest;
        _lastIngestRefreshTick = ingest.libraryRefreshTick;
        _lastIngestHadActiveJobs = ingest.hasActiveJobs;
        ingest.addListener(_onIngestQueueChanged);
      } catch (_) {
        // Widget tests often omit jobs/api overrides; treat as no active ingest.
        _ingestQueue = null;
      }
      // Consume any focus request published before this page mounted (e.g.
      // Person Detail → Faces before the Faces tab was ever opened).
      unawaited(_applyFocusRequest(ref.read(faceCropFocusRequestProvider)));
    });
  }

  /// Apply a [FaceCropFocusRequest] from [openFaceCropTrays] / deep links.
  Future<void> _applyFocusRequest(FaceCropFocusRequest? request) async {
    if (request == null) {
      await _reload();
      return;
    }
    if (_lastFocusNonce == request.nonce) {
      if (_loading && _persons.isEmpty) await _reload();
      return;
    }
    _lastFocusNonce = request.nonce;
    if (request.leafFolder != null) {
      _leafFolder = request.leafFolder;
      faceCropLastLeafFolder = request.leafFolder;
    }
    if (request.personId != null) {
      _personId = request.personId;
      _autoSelectFirstInFolder = false;
    } else if (widget.initialPersonId == null && _personId == null) {
      _autoSelectFirstInFolder = true;
    }
    await _reload();
  }

  @override
  void dispose() {
    _ingestQueue?.removeListener(_onIngestQueueChanged);
    _assignedController?.dispose();
    _renameController.dispose();
    _clusterScrollController.dispose();
    super.dispose();
  }

  void _onIngestQueueChanged() {
    if (!mounted) return;
    final queue = _ingestQueue;
    if (queue == null) return;
    final tick = queue.libraryRefreshTick;
    final active = queue.hasActiveJobs;
    if (tick == _lastIngestRefreshTick &&
        active == _lastIngestHadActiveJobs) {
      return;
    }
    _lastIngestRefreshTick = tick;
    _lastIngestHadActiveJobs = active;
    // Mid-ingest: folders stay hidden via isLoadingPath. When the job
    // finishes (or a new job starts), quietly refresh the Faces picker.
    unawaited(_refreshFoldersQuietly());
  }

  /// Rebuild the folder dropdown from items without a full-page loading flash.
  Future<void> _refreshFoldersQuietly() async {
    try {
      final itemsRepo = ref.read(itemsRepositoryProvider);
      FolderIngestQueue? ingestQueue = _ingestQueue;
      if (ingestQueue == null) {
        try {
          ingestQueue = ref.read(folderIngestQueueProvider);
          _ingestQueue = ingestQueue;
        } catch (_) {
          ingestQueue = null;
        }
      }
      final items = await itemsRepo.listItems();
      if (!mounted) return;
      final folders = [
        for (final f in distinctLeafFolders(items))
          if (ingestQueue == null || !ingestQueue.isLoadingPath(f)) f,
      ];
      final prevFolder = _leafFolder;
      final folder = resolveLeafFolderSelection(
        folders: folders,
        preferred: _leafFolder ?? faceCropLastLeafFolder,
      );
      faceCropLastLeafFolder = folder;
      final scopedIds =
          folder == null ? <String>{} : itemIdsInLeafFolder(items, folder);
      final folderChanged = folder != prevFolder;
      final foldersChanged = folders.length != _leafFolders.length ||
          !_listEquals(folders, _leafFolders);
      final prevScoped = _scopedItemIds;
      final scopeChanged = scopedIds.length != prevScoped.length ||
          !scopedIds.containsAll(prevScoped);

      if (!foldersChanged && !folderChanged && !scopeChanged) {
        return;
      }

      setState(() {
        _leafFolders = folders;
        _leafFolder = folder;
        _scopedItemIds = scopedIds;
      });

      if (folderChanged || scopeChanged) {
        if (folderChanged && folder != null) {
          _autoSelectFirstInFolder = true;
        }
        await _refreshTraysQuietly();
        // Auto-select first in-folder person when landing on a newly revealed
        // folder (quiet path does not run the full _reload auto-select).
        if (_autoSelectFirstInFolder && mounted) {
          _autoSelectFirstInFolder = false;
          final pid = _firstPersonIdInFolder(_persons, _assignedOverview);
          final canCreateNew =
              _unassignedTrayFaceCount > 0 || _excluded.isNotEmpty;
          if (pid != null) {
            await _selectPerson(pid);
          } else if (canCreateNew) {
            setState(() {
              _personId = null;
              _assignAsNewPerson = true;
              _assignedController?.dispose();
              _assignedController = null;
            });
          }
        }
      }
    } catch (e, st) {
      debugPrint('Faces quiet folder refresh failed: $e\n$st');
    }
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  PersonDetailController _controllerFor(String personId) {
    final existing = _assignedController;
    if (existing != null && existing.personId == personId) return existing;
    existing?.dispose();
    final next = PersonDetailController(
      personId: personId,
      personsRepository: ref.read(personsRepositoryProvider),
    );
    _assignedController = next;
    return next;
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final personsRepo = ref.read(personsRepositoryProvider);
      final itemsRepo = ref.read(itemsRepositoryProvider);
      FolderIngestQueue? ingestQueue = _ingestQueue;
      if (ingestQueue == null) {
        try {
          ingestQueue = ref.read(folderIngestQueueProvider);
          _ingestQueue = ingestQueue;
        } catch (_) {
          ingestQueue = null;
        }
      }
      final items = await itemsRepo.listItems();
      // Hide leaf folders still covered by an active ingest job — items exist
      // from registering, but Faces should wait until load complete.
      final folders = [
        for (final f in distinctLeafFolders(items))
          if (ingestQueue == null || !ingestQueue.isLoadingPath(f)) f,
      ];
      final folder = resolveLeafFolderSelection(
        folders: folders,
        preferred: _leafFolder ?? faceCropLastLeafFolder,
      );
      faceCropLastLeafFolder = folder;
      final scopedIds =
          folder == null ? <String>{} : itemIdsInLeafFolder(items, folder);

      final persons = await personsRepo.listPersons();
      final assignedPage = await personsRepo.listAssignedAppearances(
        limit: _trayPageLimit,
      );
      final unPage = await personsRepo.listUnassignedAppearances(
        limit: _trayPageLimit,
      );
      final exPage = await personsRepo.listAccountWhoExclusions(
        limit: _trayPageLimit,
      );

      final assignedOverview = assignedPage.appearances
          .where((a) => a.itemId != null && scopedIds.contains(a.itemId))
          .toList();
      final unassigned = unPage.appearances
          .where((a) => a.itemId != null && scopedIds.contains(a.itemId))
          .toList();
      final excluded = exPage.exclusions
          .where((e) => scopedIds.contains(e.itemId))
          .toList();

      // Exclude / unlink can prune the selected person server-side.
      // Folder switch: land on the first in-folder person, or New Person…
      // create-mode when the folder has no named people yet.
      var pid = _personId;
      var assignAsNew = _assignAsNewPerson;
      final inFolderIds = _personIdsFromAppearances(assignedOverview);
      final canCreateNew = unassigned.isNotEmpty || excluded.isNotEmpty;

      if (_autoSelectFirstInFolder) {
        _autoSelectFirstInFolder = false;
        pid = _firstPersonIdInFolder(persons, assignedOverview);
        if (pid != _personId) {
          _assignedController?.dispose();
          _assignedController = null;
          _renameController.clear();
        }
        if (pid != null) {
          assignAsNew = false;
          await _controllerFor(pid).load();
          _renameController.text = _assignedController?.detail?.name ?? '';
        } else if (canCreateNew) {
          assignAsNew = true;
          pid = null;
        }
      } else {
        final stillListed =
            pid != null && persons.any((p) => p.id == pid);
        if (pid != null && !stillListed) {
          _assignedController?.dispose();
          _assignedController = null;
          _renameController.clear();
          pid = null;
        } else if (pid != null) {
          await _controllerFor(pid).load();
          _renameController.text =
              _assignedController?.detail?.name ?? '';
        }
        // No named people left in this folder → empty Assigned = create mode.
        if (inFolderIds.isEmpty && canCreateNew && pid == null) {
          assignAsNew = true;
        }
      }

      if (!canCreateNew) {
        assignAsNew = false;
      }

      if (!mounted) return;
      setState(() {
        _personId = pid;
        _assignAsNewPerson = assignAsNew;
        if (pid != null) _assignAsNewPerson = false;
        _renaming = pid == null ? false : _renaming;
        _persons = persons;
        _leafFolders = folders;
        _leafFolder = folder;
        _scopedItemIds = scopedIds;
        _assignedOverview = assignedOverview;
        _unassigned = unassigned;
        _excluded = excluded;
        _loading = false;
      });
      if (pid != null) _scrollToCluster(pid);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _selectLeafFolder(String? folder) async {
    if (folder == null || folder == _leafFolder) return;
    faceCropLastLeafFolder = folder;
    _autoSelectFirstInFolder = true;
    _assignAsNewPerson = false;
    _clearSelection();
    setState(() => _leafFolder = folder);
    await _reload();
  }

  List<PersonAppearance> _scopedAppearances(List<PersonAppearance> all) {
    if (_scopedItemIds.isEmpty) return const [];
    return all
        .where((a) => a.itemId != null && _scopedItemIds.contains(a.itemId))
        .toList();
  }

  /// Ids with at least one face in [assignedInFolder].
  static Set<String> _personIdsFromAppearances(
    List<PersonAppearance> assignedInFolder,
  ) {
    final ids = <String>{};
    for (final a in assignedInFolder) {
      final pid = a.personId;
      if (pid != null) ids.add(pid);
    }
    return ids;
  }

  /// Sort: in-folder first, then by name (auto-select order).
  static List<Person> _sortPersonsForDropdown(
    List<Person> persons,
    Set<String> inFolder,
  ) {
    final list = List<Person>.from(persons);
    list.sort((a, b) {
      final ra = inFolder.contains(a.id) ? 0 : 1;
      final rb = inFolder.contains(b.id) ? 0 : 1;
      if (ra != rb) return ra.compareTo(rb);
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  /// First person (in-folder order) with faces in [assignedInFolder].
  static String? _firstPersonIdInFolder(
    List<Person> persons,
    List<PersonAppearance> assignedInFolder,
  ) {
    final inFolder = _personIdsFromAppearances(assignedInFolder);
    if (inFolder.isEmpty) return null;
    for (final p in _sortPersonsForDropdown(persons, inFolder)) {
      if (inFolder.contains(p.id)) return p.id;
    }
    return null;
  }

  /// Display name for chrome / subtitle. Person.name is always non-empty (R2).
  static String personDisplayName(Person p) => p.name.isNotEmpty ? p.name : p.id;

  static String _personDropdownLabel(Person p, {required bool inFolder}) {
    final base = personDisplayName(p);
    return inFolder ? '$base · in folder' : base;
  }

  Future<void> _selectPerson(String? id) async {
    if (id == null) {
      setState(() {
        _personId = null;
        _assignAsNewPerson = false;
        _renaming = false;
        _renameController.clear();
        _assignedController?.dispose();
        _assignedController = null;
      });
      return;
    }
    if (id == _newPersonSentinel) {
      setState(() {
        _personId = null;
        _assignAsNewPerson = true;
        _renaming = false;
        _renameController.clear();
        _assignedController?.dispose();
        _assignedController = null;
      });
      return;
    }
    final controller = _controllerFor(id);
    setState(() {
      _personId = id;
      _assignAsNewPerson = false;
      _renaming = false;
      // Clear immediately so a freshly-loaded person never shows a stale name
      // while load() is in flight.
      _renameController.clear();
    });
    _scrollToCluster(id);
    await controller.load();
    if (!mounted) return;
    setState(() {
      _renameController.text = controller.detail?.name ?? '';
    });
    _scrollToCluster(id);
  }

  Future<void> _openItem(String itemId) async {
    final container = ProviderScope.containerOf(context);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SelectableScope(
          child: UncontrolledProviderScope(
            container: container,
            child: ItemDetailPage(itemId: itemId),
          ),
        ),
      ),
    );
  }

  /// Prompts for a name, then assigns [appearanceId] straight to a new
  /// named person (R6). Unassigned Person.name is never null — no more
  /// "unnamed" mint step.
  Future<void> _setNameFromAppearance(String appearanceId) async {
    if (_busy) return;
    final name = await showPersonNameDialog(context);
    if (name == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final persons = ref.read(personsRepositoryProvider);
      final updated = await persons.reassignAppearance(
        appearanceId,
        name: name,
      );
      final newId = updated.personId;
      if (newId != null) {
        _personId = newId;
      }
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('face-crop-trays-error'),
          content: Text('Set name failed: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Prompts for a name, then promotes the whole FaceGroup [faceGroupId] to a
  /// named person (R6).
  Future<void> _setFaceGroupName(String faceGroupId) async {
    if (_busy) return;
    final name =
        await showPersonNameDialog(context, title: 'Name this group');
    if (name == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final persons = ref.read(personsRepositoryProvider);
      final detail = await persons.assignFaceGroup(faceGroupId, name: name);
      _personId = detail.id;
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('face-crop-trays-error'),
          content: Text('Set name failed: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<_FaceMoveResult> _applyOneDrop(
    FaceCropTray target,
    FaceCropDragData data, {
    String? assignPersonId,
    String? assignName,
  }) async {
    final persons = ref.read(personsRepositoryProvider);
    final items = ref.read(itemsRepositoryProvider);

    switch (target) {
      case FaceCropTray.unassigned:
        // Appearance batches (single unlink vs. bulk unassign) are handled
        // directly in [_onDrop]; only exclusion undos reach here.
        if (data.isExclusion && data.exclusionId != null) {
          await items.undoWhoExclusion(data.itemId, data.exclusionId!);
          // Appearance id is server-assigned; quiet refresh fills Unassigned.
          return _FaceMoveResult(removedExclusionId: data.exclusionId);
        }
        return const _FaceMoveResult();
      case FaceCropTray.excluded:
        final tagId = data.tagId;
        if (tagId == null) {
          throw StateError('Exclude requires a who tag id');
        }
        final created = await items.createWhoExclusion(data.itemId, tagId);
        return _FaceMoveResult(
          removedAppearanceId: data.appearanceId,
          removedExclusionId: null,
          addedExclusion: created.exclusion,
        );
      case FaceCropTray.assigned:
        final pid = assignPersonId ?? _personId;
        final name = assignName;
        if (pid == null && (name == null || name.isEmpty)) {
          throw StateError('Select a person before assigning');
        }
        if (data.isExclusion && data.exclusionId != null) {
          await items.undoWhoExclusion(data.itemId, data.exclusionId!);
          final tagId = data.tagId ?? data.createdFromTagId;
          final page = await persons.listUnassignedAppearances(
            limit: _trayPageLimit,
          );
          PersonAppearance? match;
          for (final a in page.appearances) {
            if (a.tagId == tagId) {
              match = a;
              break;
            }
          }
          if (match == null) {
            throw StateError('Could not find appearance after undo exclude');
          }
          final updated = name != null && name.isNotEmpty
              ? await persons.reassignAppearance(match.id, name: name)
              : await persons.reassignAppearance(match.id, personId: pid!);
          return _FaceMoveResult(
            removedExclusionId: data.exclusionId,
            removedAppearanceId: match.id,
            addedAppearance: updated,
          );
        }
        // Loose face (no faceGroupId) — FaceGroup members are promoted in
        // bulk in [_onDrop] via assignFaceGroup.
        if (data.appearanceId != null) {
          final updated = name != null && name.isNotEmpty
              ? await persons.reassignAppearance(
                  data.appearanceId!,
                  name: name,
                )
              : await persons.reassignAppearance(
                  data.appearanceId!,
                  personId: pid!,
                );
          return _FaceMoveResult(
            removedAppearanceId: data.appearanceId,
            addedAppearance: updated,
          );
        }
        return const _FaceMoveResult();
    }
  }

  bool _appearanceInScope(PersonAppearance a) {
    final itemId = a.itemId;
    return itemId != null && _scopedItemIds.contains(itemId);
  }

  bool _exclusionInScope(WhoExclusion e) =>
      _scopedItemIds.contains(e.itemId);

  void _applyMoveResults(List<_FaceMoveResult> results) {
    if (results.isEmpty) return;
    setState(() {
      var assigned = List<PersonAppearance>.of(_assignedOverview);
      var unassigned = List<PersonAppearance>.of(_unassigned);
      var excluded = List<WhoExclusion>.of(_excluded);

      for (final r in results) {
        final removedAp = r.removedAppearanceId;
        if (removedAp != null) {
          assigned = assigned.where((a) => a.id != removedAp).toList();
          unassigned = unassigned.where((a) => a.id != removedAp).toList();
        }
        final removedEx = r.removedExclusionId;
        if (removedEx != null) {
          excluded = excluded.where((e) => e.id != removedEx).toList();
        }
        final addedAp = r.addedAppearance;
        if (addedAp != null && _appearanceInScope(addedAp)) {
          assigned = assigned.where((a) => a.id != addedAp.id).toList();
          unassigned = unassigned.where((a) => a.id != addedAp.id).toList();
          if (addedAp.personId != null) {
            assigned = [...assigned, addedAp];
          } else {
            unassigned = [...unassigned, addedAp];
          }
        }
        final addedEx = r.addedExclusion;
        if (addedEx != null && _exclusionInScope(addedEx)) {
          excluded = [
            ...excluded.where((e) => e.id != addedEx.id),
            addedEx,
          ];
        }
      }

      _assignedOverview = assigned;
      _unassigned = unassigned;
      _excluded = excluded;
      _selectedIds.clear();
      _selectionTray = null;
      _selectionKind = null;
      _faceTapTracker.clear();

      final pid = _personId;
      if (pid != null &&
          !assigned.any((a) => a.personId == pid)) {
        _personId = null;
        _renaming = false;
        _renameController.clear();
        _assignedController?.dispose();
        _assignedController = null;
      }
    });
  }

  /// Sync trays from the API without blanking the page (no [listItems]).
  Future<void> _refreshTraysQuietly() async {
    try {
      final personsRepo = ref.read(personsRepositoryProvider);
      final results = await Future.wait<Object>([
        personsRepo.listPersons(),
        personsRepo.listAssignedAppearances(limit: _trayPageLimit),
        personsRepo.listUnassignedAppearances(limit: _trayPageLimit),
        personsRepo.listAccountWhoExclusions(limit: _trayPageLimit),
      ]);
      if (!mounted) return;

      final persons = results[0] as List<Person>;
      final assignedPage = results[1] as AssignedAppearancesPage;
      final unPage = results[2] as UnassignedAppearancesPage;
      final exPage = results[3] as AccountWhoExclusionsPage;
      final scopedIds = _scopedItemIds;

      final assignedOverview = assignedPage.appearances
          .where((a) => a.itemId != null && scopedIds.contains(a.itemId))
          .toList();
      final unassigned = unPage.appearances
          .where((a) => a.itemId != null && scopedIds.contains(a.itemId))
          .toList();
      final excluded = exPage.exclusions
          .where((e) => scopedIds.contains(e.itemId))
          .toList();

      var pid = _personId;
      if (pid != null && !persons.any((p) => p.id == pid)) {
        _assignedController?.dispose();
        _assignedController = null;
        _renameController.clear();
        pid = null;
      }
      final inFolderIds = _personIdsFromAppearances(assignedOverview);
      final canCreateNew = unassigned.isNotEmpty || excluded.isNotEmpty;
      var assignAsNew = _assignAsNewPerson;
      if (pid != null) {
        assignAsNew = false;
      } else if (inFolderIds.isEmpty && canCreateNew) {
        assignAsNew = true;
      }
      if (!canCreateNew) {
        assignAsNew = false;
      }

      setState(() {
        _personId = pid;
        _assignAsNewPerson = assignAsNew;
        _renaming = pid == null ? false : _renaming;
        _persons = persons;
        _assignedOverview = assignedOverview;
        _unassigned = unassigned;
        _excluded = excluded;
      });
    } catch (e, st) {
      debugPrint('Faces quiet tray refresh failed: $e\n$st');
    }
  }

  Future<void> _onDrop(FaceCropTray target, FaceCropDragPayload payload) async {
    if (_busy || payload.items.isEmpty) return;
    final toApply = [
      for (final data in payload.items)
        if (!ignoreSameTrayFaceCropDrop(
          source: data.source,
          target: target,
          dataPersonId: data.personId,
          selectedPersonId: _personId,
        ))
          data,
    ];
    if (toApply.isEmpty) return;

    setState(() => _busy = true);
    var failed = 0;
    Object? lastError;
    final applied = <_FaceMoveResult>[];
    try {
      if (target == FaceCropTray.unassigned) {
        // Appearances leaving Assigned: ≥2 become one GroupFM via a single
        // batched call; exactly one becomes loose (R6). Exclusion undos
        // still go through the per-item path.
        final appearanceItems = [
          for (final d in toApply)
            if (d.isAppearance && d.appearanceId != null) d,
        ];
        final otherItems = [
          for (final d in toApply)
            if (!(d.isAppearance && d.appearanceId != null)) d,
        ];
        if (appearanceItems.isNotEmpty) {
          try {
            final persons = ref.read(personsRepositoryProvider);
            if (appearanceItems.length >= 2) {
              final ids = [
                for (final d in appearanceItems) d.appearanceId!,
              ];
              final updated = await persons.unassignAppearances(ids);
              for (final u in updated) {
                applied.add(_FaceMoveResult(
                  removedAppearanceId: u.id,
                  addedAppearance: u,
                ));
              }
            } else {
              final id = appearanceItems.single.appearanceId!;
              final updated = await persons.unlinkAppearance(id);
              applied.add(_FaceMoveResult(
                removedAppearanceId: id,
                addedAppearance: updated,
              ));
            }
          } catch (e) {
            failed += appearanceItems.length;
            lastError = e;
          }
        }
        for (final data in otherItems) {
          try {
            applied.add(await _applyOneDrop(target, data));
          } catch (e) {
            failed++;
            lastError = e;
          }
        }
      } else if (target == FaceCropTray.assigned) {
        // Appearances from a FaceGroup are promoted whole (assignFaceGroup);
        // excluded FaceGroups are undone then promoted whole; loose faces /
        // loose exclusion undos are reassigned one at a time.
        var personId = _personId;
        String? createName;
        if (_assignAsNewPerson) {
          createName = await showPersonNameDialog(context);
          if (createName == null || !mounted) return;
        } else if (personId == null) {
          failed = toApply.length;
          lastError = StateError('Select a person before assigning');
        }

        if (failed == 0) {
          final byFaceGroup = <String, List<FaceCropDragData>>{};
          final singles = <FaceCropDragData>[];
          for (final data in toApply) {
            final fg = data.faceGroupId;
            if (fg != null && (data.isAppearance || data.isExclusion)) {
              (byFaceGroup[fg] ??= <FaceCropDragData>[]).add(data);
            } else {
              singles.add(data);
            }
          }
          for (final entry in byFaceGroup.entries) {
            try {
              final persons = ref.read(personsRepositoryProvider);
              final items = ref.read(itemsRepositoryProvider);

              // Promote every known member of the FaceGroup (appearances in
              // Unassigned, or exclusions in Excluded), not just the drag subset.
              final unassignedMembers = _scopedAppearances(_unassigned)
                  .where((a) => a.faceGroupId == entry.key)
                  .toList();
              final excludedMembers = [
                for (final e in _excluded)
                  if (_exclusionInScope(e) && e.faceGroupId == entry.key) e,
              ];

              for (final e in excludedMembers) {
                await items.undoWhoExclusion(e.itemId, e.id);
                applied.add(_FaceMoveResult(removedExclusionId: e.id));
              }

              final detail = createName != null
                  ? await persons.assignFaceGroup(
                      entry.key,
                      name: createName,
                    )
                  : await persons.assignFaceGroup(
                      entry.key,
                      personId: personId!,
                    );
              personId = detail.id;
              createName = null;
              final byId = {for (final a in detail.appearances) a.id: a};

              // Members that were already unassigned before this drop.
              for (final member in unassignedMembers) {
                final updated = byId[member.id];
                if (updated != null) {
                  applied.add(_FaceMoveResult(
                    removedAppearanceId: member.id,
                    addedAppearance: updated,
                  ));
                }
              }
              // Members restored from Excluded: match by tagId on the detail.
              for (final e in excludedMembers) {
                final tagId = e.createdFromTagId;
                PersonAppearance? updated;
                if (tagId != null) {
                  for (final a in detail.appearances) {
                    if (a.tagId == tagId) {
                      updated = a;
                      break;
                    }
                  }
                }
                if (updated != null) {
                  applied.add(_FaceMoveResult(
                    removedAppearanceId: updated.id,
                    addedAppearance: updated,
                  ));
                }
              }
            } catch (e) {
              failed += entry.value.length;
              lastError = e;
            }
          }
          for (final data in singles) {
            try {
              final nameForThis = createName;
              final result = await _applyOneDrop(
                target,
                data,
                assignPersonId: personId,
                assignName: nameForThis,
              );
              applied.add(result);
              final newPid = result.addedAppearance?.personId;
              if (newPid != null) {
                personId = newPid;
                createName = null;
              }
            } catch (e) {
              failed++;
              lastError = e;
            }
          }

          if (_assignAsNewPerson &&
              applied.isNotEmpty &&
              personId != null &&
              mounted) {
            final listed =
                await ref.read(personsRepositoryProvider).listPersons();
            if (!mounted) return;
            _assignAsNewPerson = false;
            _personId = personId;
            _persons = listed;
            final controller = _controllerFor(personId);
            await controller.load();
            if (mounted) {
              _renameController.text = controller.detail?.name ?? '';
            }
          }
        }
      } else {
        // Drop onto Excluded: preserve FaceGroup membership. Appearances that
        // already share a faceGroupId are excluded per-face (server copies the
        // id). ≥2 ungrouped appearances (typical Assigned multi-drag) are
        // minted into one GroupFM first, then excluded.
        final appearanceItems = [
          for (final d in toApply)
            if (d.isAppearance && d.appearanceId != null) d,
        ];
        final otherItems = [
          for (final d in toApply)
            if (!(d.isAppearance && d.appearanceId != null)) d,
        ];

        final grouped = <FaceCropDragData>[];
        final ungrouped = <FaceCropDragData>[];
        for (final d in appearanceItems) {
          if (d.faceGroupId != null) {
            grouped.add(d);
          } else {
            ungrouped.add(d);
          }
        }

        if (ungrouped.length >= 2) {
          try {
            final persons = ref.read(personsRepositoryProvider);
            final items = ref.read(itemsRepositoryProvider);
            final ids = [for (final d in ungrouped) d.appearanceId!];
            final minted = await persons.unassignAppearances(ids);
            final byOldId = <String, PersonAppearance>{
              for (final a in minted) a.id: a,
            };
            for (final d in ungrouped) {
              final mintedAp = byOldId[d.appearanceId];
              final tagId = mintedAp?.tagId ?? d.tagId;
              if (tagId == null) {
                throw StateError('Exclude requires a who tag id');
              }
              final created =
                  await items.createWhoExclusion(d.itemId, tagId);
              applied.add(_FaceMoveResult(
                removedAppearanceId: d.appearanceId,
                addedExclusion: created.exclusion,
              ));
            }
          } catch (e) {
            failed += ungrouped.length;
            lastError = e;
          }
        } else {
          for (final data in [...grouped, ...ungrouped]) {
            try {
              applied.add(await _applyOneDrop(target, data));
            } catch (e) {
              failed++;
              lastError = e;
            }
          }
        }

        for (final data in otherItems) {
          try {
            applied.add(await _applyOneDrop(target, data));
          } catch (e) {
            failed++;
            lastError = e;
          }
        }
      }

      if (applied.isNotEmpty) {
        _applyMoveResults(applied);
      } else {
        setState(() {
          _selectedIds.clear();
          _selectionTray = null;
          _selectionKind = null;
        });
      }
      if (!mounted) return;
      if (failed > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            key: const Key('face-crop-trays-error'),
            content: Text(
              'Move failed for $failed of ${toApply.length}: $lastError',
            ),
          ),
        );
      }
      // Reconcile with server without a full-page loading flash.
      unawaited(_refreshTraysQuietly());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmRemovePerson(PersonDetailController controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove person?'),
        content: const Text(
          'Removes this person. Its faces move to Unassigned '
          'so you can assign them again. To detach one face only, '
          'drag it to Unassigned.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('face-crop-person-unassign-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await controller.unassignPerson();
    if (ok && mounted) {
      await _selectPerson(null);
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Local [_assignedController] — do not watch autoDispose
    // personDetailControllerProvider here (UncontrolledProviderScope + dispose
    // mid-build asserts "Only one task can be scheduled at a time").
    final controller = _assignedController;

    ref.listen<FaceCropFocusRequest?>(faceCropFocusRequestProvider,
        (previous, next) {
      if (next == null) return;
      if (_lastFocusNonce == next.nonce) return;
      unawaited(_applyFocusRequest(next));
    });

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _clearSelection();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Faces'),
        actions: [
          if (!_loading && _error == null && _leafFolders.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    key: const Key('face-crop-folder-select'),
                    // ignore: deprecated_member_use
                    value: _leafFolder != null &&
                            _leafFolders.contains(_leafFolder)
                        ? _leafFolder
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Folder',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                    items: [
                      for (final folder in _leafFolders)
                        DropdownMenuItem(
                          value: folder,
                          child: Text(
                            leafFolderLabel(folder),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _busy ? null : _selectLeafFolder,
                  ),
                ),
              ),
            ),
          IconButton(
            key: const Key('face-crop-trays-refresh'),
            tooltip: 'Refresh',
            onPressed: _busy || _loading ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                key: Key('face-crop-trays-loading'),
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Could not load trays: $_error',
                          key: const Key('face-crop-trays-error-text'),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _reload,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _leafFolders.isEmpty
                  ? const Center(
                      child: Text(
                        'No local folders in the library yet.\n'
                        'Add photos from a folder, then open Faces.',
                        key: Key('face-crop-trays-no-folders'),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _buildAssignedColumn(controller)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildUnassignedColumn()),
                      const SizedBox(width: 8),
                      Expanded(child: _buildExcludedColumn()),
                    ],
                  ),
                ),
      ),
    );
  }

  Widget? _personChromeWidget(PersonDetailController? controller) {
    final detail = controller?.detail;
    if (controller == null ||
        detail == null ||
        controller.phase != PersonDetailPhase.ready ||
        _personId != detail.id) {
      return null;
    }
    return _PersonChrome(
      key: ValueKey('face-crop-person-chrome-${detail.id}'),
      detail: detail,
      controller: controller,
      renameController: _renameController,
      renaming: _renaming,
      busy: _busy || controller.isBusy,
      onStartRename: () {
        setState(() {
          _renaming = true;
          _renameController.text = detail.name;
        });
      },
      onDoneRename: () async {
        final ok = await controller.rename(_renameController.text);
        if (!mounted) return;
        if (ok) {
          setState(() => _renaming = false);
          final persons =
              await ref.read(personsRepositoryProvider).listPersons();
          if (mounted) setState(() => _persons = persons);
        }
      },
      onCancelRename: () => setState(() => _renaming = false),
      onRemovePerson: () => _confirmRemovePerson(controller),
    );
  }

  Widget _buildAssignedColumn(PersonDetailController? controller) {
    final pid = _personId;
    Person? selectedPerson;
    if (pid != null) {
      for (final p in _persons) {
        if (p.id == pid) {
          selectedPerson = p;
          break;
        }
      }
    }
    // Prefer list entry; fall back to controller detail so a just-created
    // person still shows before the next full refresh.
    final selectedId = pid != null &&
            (selectedPerson != null ||
                controller?.personId == pid ||
                controller?.detail?.id == pid)
        ? pid
        : null;
    final selectedName = selectedPerson != null
        ? personDisplayName(selectedPerson)
        : (controller?.detail != null && controller!.detail!.id == pid
            ? personDisplayName(
                Person(
                  id: controller.detail!.id,
                  name: controller.detail!.name,
                  createdAt: controller.detail!.createdAt,
                ),
              )
            : null);
    final showNewPerson =
        _unassignedTrayFaceCount > 0 || _excluded.isNotEmpty;
    final allClusters = _assignedMultiClusters();
    final allSolos = _assignedSoloFaces();
    final inFolderIds = <String>{
      for (final c in allClusters) c.person.id,
      for (final a in allSolos)
        if (a.personId != null) a.personId!,
    };
    var inFolderPersons = [
      for (final p in _sortPersonsForDropdown(_persons, inFolderIds))
        if (inFolderIds.contains(p.id)) p,
    ];
    if (selectedId != null &&
        !inFolderIds.contains(selectedId) &&
        selectedName != null) {
      inFolderPersons = [
        ...inFolderPersons,
        selectedPerson ??
            Person(id: selectedId, name: selectedName, createdAt: ''),
      ];
    }
    final dropdownValue = _assignAsNewPerson && showNewPerson
        ? _newPersonSentinel
        : (selectedId != null &&
                inFolderPersons.any((p) => p.id == selectedId)
            ? selectedId
            : null);
    // New Person... → empty drop target. Selected person → only that person's
    // faces (dropdown name and tray must agree). No selection → overview.
    final clusters = _assignAsNewPerson
        ? const <({Person person, List<PersonAppearance> faces})>[]
        : selectedId == null
            ? allClusters
            : [
                for (final c in allClusters)
                  if (c.person.id == selectedId) c,
              ];
    final solos = _assignAsNewPerson
        ? const <PersonAppearance>[]
        : selectedId == null
            ? allSolos
            : [
                for (final a in allSolos)
                  if (a.personId == selectedId) a,
              ];
    final scheme = Theme.of(context).colorScheme;
    final showPersonSelect = showNewPerson || inFolderPersons.isNotEmpty;
    final Widget? personSelect = showPersonSelect
        ? DropdownButtonFormField<String>(
            key: const Key('face-crop-person-select'),
            // ignore: deprecated_member_use
            value: dropdownValue,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            hint: showNewPerson ? const Text('New Person...') : null,
            selectedItemBuilder: (context) {
              return [
                if (showNewPerson)
                  const Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'New Person...',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                for (final p in inFolderPersons)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      _personDropdownLabel(p, inFolder: true),
                      key: Key('face-crop-person-select-label-${p.id}'),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: scheme.primary,
                      ),
                    ),
                  ),
              ];
            },
            items: [
              if (showNewPerson)
                const DropdownMenuItem(
                  value: _newPersonSentinel,
                  child: Text(
                    'New Person...',
                    key: Key('face-crop-person-option-new'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              for (final p in inFolderPersons)
                DropdownMenuItem(
                  value: p.id,
                  child: Text(
                    _personDropdownLabel(p, inFolder: true),
                    key: Key('face-crop-person-option-in-folder-${p.id}'),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                ),
            ],
            onChanged: _busy
                ? null
                : (id) async {
                    await _selectPerson(id);
                  },
          )
        : null;

    Widget buildTray({required String subtitle}) {
      final chrome =
          selectedId != null ? _personChromeWidget(controller) : null;
      final empty = clusters.isEmpty && solos.isEmpty;
      return _TrayColumn(
        key: const Key('face-crop-tray-assigned'),
        title: 'Assigned',
        tagline: 'named people',
        subtitle: subtitle,
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?personSelect,
            if (chrome != null) ...[
              if (personSelect != null) const SizedBox(height: 8),
              chrome,
            ],
          ],
        ),
        onAccept: (d) => _onDrop(FaceCropTray.assigned, d),
        child: empty
            ? Center(
                child: Text(
                  _assignAsNewPerson
                      ? 'Drop faces to name a new person'
                      : _unassignedTrayFaceCount == 0 && _excluded.isEmpty
                          ? 'No faces in this folder yet'
                          : selectedId != null
                              ? 'No faces for this person in this folder'
                              : 'No named people in this folder — group faces '
                                  'in Unassigned and click Set name, or check '
                                  'Unassigned',
                  key: const Key('face-crop-assigned-empty'),
                  textAlign: TextAlign.center,
                ),
              )
            : ListView(
                controller: _clusterScrollController,
                padding: const EdgeInsets.all(8),
                children: [
                  for (var i = 0; i < clusters.length; i++) ...[
                    Padding(
                      key: _clusterKey(clusters[i].person.id),
                      padding: EdgeInsets.only(
                        bottom: i == clusters.length - 1 && solos.isEmpty
                            ? 0
                            : 10,
                      ),
                      child: _PersonClusterCard(
                        person: clusters[i].person,
                        faces: clusters[i].faces,
                        focused: clusters[i].person.id == selectedId,
                        busy: _busy ||
                            (clusters[i].person.id == selectedId &&
                                (controller?.isBusy ?? false)),
                        selectedIds: _selectionFor(
                          FaceCropTray.assigned,
                          FaceCropSelectKind.appearance,
                        ),
                        tapTracker: _faceTapTracker,
                        dragPayload: _clusterDragPayload(
                          clusters[i].faces,
                          FaceCropTray.assigned,
                        ),
                        onSelectCluster: () => _selectCluster(
                          clusters[i].person,
                          clusters[i].faces,
                          FaceCropTray.assigned,
                        ),
                        onSelectAppearance: (a, {required toggle}) =>
                            _selectAppearance(
                          a,
                          FaceCropTray.assigned,
                          toggle: toggle,
                        ),
                        onOpenItem: _openItem,
                      ),
                    ),
                  ],
                  if (solos.isNotEmpty)
                    _AppearanceGrid(
                      appearances: solos,
                      source: FaceCropTray.assigned,
                      busy: _busy || (controller?.isBusy ?? false),
                      selectedIds: _selectionFor(
                        FaceCropTray.assigned,
                        FaceCropSelectKind.appearance,
                      ),
                      tapTracker: _faceTapTracker,
                      shrinkWrap: true,
                      onSelect: (a, {required toggle}) => _selectAppearance(
                        a,
                        FaceCropTray.assigned,
                        toggle: toggle,
                      ),
                      onOpenItem: _openItem,
                    ),
                ],
              ),
      );
    }

    if (controller == null) {
      return buildTray(
        subtitle: _assignAsNewPerson
            ? 'Drop faces to name a new person'
            : emptyAssignedSubtitle(clusters, solos),
      );
    }

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final detail = controller.detail;
        final String subtitle;
        if (_assignAsNewPerson) {
          subtitle = 'Drop faces to name a new person';
        } else if (clusters.isEmpty && solos.isEmpty) {
          subtitle = 'Select a person';
        } else if (controller.phase == PersonDetailPhase.loading &&
            selectedId != null) {
          subtitle = 'Loading…';
        } else if (detail != null && selectedId == detail.id) {
          subtitle = personDisplayName(
            Person(id: detail.id, name: detail.name, createdAt: detail.createdAt),
          );
        } else {
          subtitle = emptyAssignedSubtitle(clusters, solos);
        }
        return buildTray(subtitle: subtitle);
      },
    );
  }

  static String emptyAssignedSubtitle(
    List<({Person person, List<PersonAppearance> faces})> clusters,
    List<PersonAppearance> solos,
  ) {
    final faces = clusters.fold<int>(0, (n, c) => n + c.faces.length) +
        solos.length;
    if (faces == 0) return 'Select a person';
    final groups = clusters.length;
    if (groups == 0) return '$faces ${faces == 1 ? 'face' : 'faces'}';
    return '$groups ${groups == 1 ? 'group' : 'groups'} · $faces faces';
  }

  Widget _buildUnassignedColumn() {
    final clusters = _faceGroupMultiClusters();
    final loose = _unassignedLooseFaces();

    final body = () {
      if (clusters.isEmpty && loose.isEmpty) {
        return const Center(
          child: Text(
            'No unassigned faces',
            key: Key('face-crop-unassigned-empty'),
            textAlign: TextAlign.center,
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(8),
        children: [
          for (var i = 0; i < clusters.length; i++)
            Padding(
              key: _clusterKey(clusters[i].faceGroupId),
              padding: EdgeInsets.only(
                bottom: i == clusters.length - 1 && loose.isEmpty ? 0 : 10,
              ),
              child: _FaceGroupClusterCard(
                faceGroupId: clusters[i].faceGroupId,
                kind: clusters[i].kind,
                faces: clusters[i].faces,
                busy: _busy,
                selectedIds: _selectionFor(
                  FaceCropTray.unassigned,
                  FaceCropSelectKind.appearance,
                ),
                tapTracker: _faceTapTracker,
                dragPayload: _clusterDragPayload(
                  clusters[i].faces,
                  FaceCropTray.unassigned,
                ),
                onSelectCluster: () => _selectFaceGroupCluster(
                  clusters[i].faceGroupId,
                  clusters[i].faces,
                ),
                onSetName: () => _setFaceGroupName(clusters[i].faceGroupId),
                onSelectAppearance: (a, {required toggle}) =>
                    _selectAppearance(
                  a,
                  FaceCropTray.unassigned,
                  toggle: toggle,
                ),
                onOpenItem: _openItem,
              ),
            ),
          if (loose.isNotEmpty)
            _AppearanceGrid(
              appearances: loose,
              source: FaceCropTray.unassigned,
              busy: _busy,
              selectedIds: _selectionFor(
                FaceCropTray.unassigned,
                FaceCropSelectKind.appearance,
              ),
              tapTracker: _faceTapTracker,
              shrinkWrap: true,
              onSelect: (a, {required toggle}) => _selectAppearance(
                a,
                FaceCropTray.unassigned,
                toggle: toggle,
              ),
              onOpenItem: _openItem,
              onSetName: _setNameFromAppearance,
            ),
        ],
      );
    }();

    return _TrayColumn(
      key: const Key('face-crop-tray-unassigned'),
      title: 'Unassigned',
      tagline: 'not yet named — includes auto-grouped similar faces',
      subtitle: '$_unassignedTrayFaceCount '
          '${_unassignedTrayFaceCount == 1 ? 'face' : 'faces'}',
      onAccept: (d) => _onDrop(FaceCropTray.unassigned, d),
      child: body,
    );
  }

  Widget _buildExcludedColumn() {
    final clusters = _excludedFaceGroupMultiClusters();
    final loose = _excludedLooseFaces();
    final faceCount = [
      for (final e in _excluded)
        if (_exclusionInScope(e)) e,
    ].length;

    final body = () {
      if (clusters.isEmpty && loose.isEmpty) {
        return const Center(
          child: Text(
            'No excluded faces',
            textAlign: TextAlign.center,
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(8),
        children: [
          for (var i = 0; i < clusters.length; i++)
            Padding(
              key: _clusterKey('ex-${clusters[i].faceGroupId}'),
              padding: EdgeInsets.only(
                bottom: i == clusters.length - 1 && loose.isEmpty ? 0 : 10,
              ),
              child: _ExcludedFaceGroupClusterCard(
                faceGroupId: clusters[i].faceGroupId,
                kind: clusters[i].kind,
                faces: clusters[i].faces,
                busy: _busy,
                selectedIds: _selectionFor(
                  FaceCropTray.excluded,
                  FaceCropSelectKind.exclusion,
                ),
                tapTracker: _faceTapTracker,
                dragPayload: _excludedClusterDragPayload(clusters[i].faces),
                onSelectCluster: () =>
                    _selectExcludedFaceGroupCluster(clusters[i].faces),
                onSelectExclusion: (e, {required toggle}) =>
                    _selectExclusion(e, toggle: toggle),
                onOpenItem: _openItem,
              ),
            ),
          if (loose.isNotEmpty)
            _ExclusionGrid(
              exclusions: loose,
              busy: _busy,
              selectedIds: _selectionFor(
                FaceCropTray.excluded,
                FaceCropSelectKind.exclusion,
              ),
              tapTracker: _faceTapTracker,
              shrinkWrap: true,
              onSelect: (e, {required toggle}) =>
                  _selectExclusion(e, toggle: toggle),
              onOpenItem: _openItem,
            ),
        ],
      );
    }();

    return _TrayColumn(
      key: const Key('face-crop-tray-excluded'),
      title: 'Excluded',
      tagline: 'faces should not be assigned to a person',
      subtitle: '$faceCount ${faceCount == 1 ? 'face' : 'faces'}',
      onAccept: (d) => _onDrop(FaceCropTray.excluded, d),
      child: body,
    );
  }
}

class _PersonClusterCard extends StatelessWidget {
  const _PersonClusterCard({
    required this.person,
    required this.faces,
    required this.focused,
    required this.busy,
    required this.selectedIds,
    required this.tapTracker,
    required this.dragPayload,
    required this.onSelectCluster,
    required this.onSelectAppearance,
    required this.onOpenItem,
  });

  final Person person;
  final List<PersonAppearance> faces;
  final bool focused;
  final bool busy;
  final Set<String> selectedIds;
  final FaceCropTapTracker tapTracker;
  final FaceCropDragPayload dragPayload;
  final VoidCallback onSelectCluster;
  final void Function(PersonAppearance appearance, {required bool toggle})
      onSelectAppearance;
  final void Function(String itemId) onOpenItem;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = _FaceCropTraysPageState.personDisplayName(person);
    final header = Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('face-crop-cluster-header-${person.id}'),
        onTap: busy ? null : onSelectCluster,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$label · ${faces.length} '
                  '${faces.length == 1 ? 'face' : 'faces'}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: focused ? FontWeight.w700 : null,
                        color: focused ? scheme.primary : null,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dragPayload.items.isEmpty)
          header
        else
          Draggable<FaceCropDragPayload>(
            data: dragPayload,
            feedback: Material(
              elevation: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$label · ${dragPayload.count}',
                  key: Key('face-crop-cluster-drag-${person.id}'),
                  style: TextStyle(color: scheme.onPrimaryContainer),
                ),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.45, child: header),
            child: header,
          ),
        _AppearanceGrid(
          appearances: faces,
          source: dragPayload.source,
          busy: busy,
          selectedIds: selectedIds,
          tapTracker: tapTracker,
          shrinkWrap: true,
          onSelect: onSelectAppearance,
          onOpenItem: onOpenItem,
        ),
      ],
    );

    return DecoratedBox(
      key: Key('face-crop-cluster-${person.id}'),
      decoration: BoxDecoration(
        border: Border.all(
          color: focused ? scheme.primary : scheme.outlineVariant,
          width: focused ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
        color: focused
            ? scheme.primaryContainer.withValues(alpha: 0.18)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      ),
      child: body,
    );
  }
}

/// Boxed Unassigned FaceGroup (GroupFA/GroupFM) — no Person exists yet.
/// "Set name" promotes the whole group to a named person (R6).
class _FaceGroupClusterCard extends StatelessWidget {
  const _FaceGroupClusterCard({
    required this.faceGroupId,
    required this.kind,
    required this.faces,
    required this.busy,
    required this.selectedIds,
    required this.tapTracker,
    required this.dragPayload,
    required this.onSelectCluster,
    required this.onSetName,
    required this.onSelectAppearance,
    required this.onOpenItem,
  });

  final String faceGroupId;
  final FaceGroupKind kind;
  final List<PersonAppearance> faces;
  final bool busy;
  final Set<String> selectedIds;
  final FaceCropTapTracker tapTracker;
  final FaceCropDragPayload dragPayload;
  final VoidCallback onSelectCluster;
  final VoidCallback onSetName;
  final void Function(PersonAppearance appearance, {required bool toggle})
      onSelectAppearance;
  final void Function(String itemId) onOpenItem;

  String get _label =>
      kind == FaceGroupKind.fa ? 'Similar faces' : 'Grouped faces';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final header = Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('face-crop-facegroup-header-$faceGroupId'),
        onTap: busy ? null : onSelectCluster,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$_label · ${faces.length} '
                  '${faces.length == 1 ? 'face' : 'faces'}',
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                key: Key('face-crop-facegroup-set-name-$faceGroupId'),
                onPressed: busy ? null : onSetName,
                child: const Text('Set name'),
              ),
            ],
          ),
        ),
      ),
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dragPayload.items.isEmpty)
          header
        else
          Draggable<FaceCropDragPayload>(
            data: dragPayload,
            feedback: Material(
              elevation: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$_label · ${dragPayload.count}',
                  key: Key('face-crop-facegroup-drag-$faceGroupId'),
                  style: TextStyle(color: scheme.onPrimaryContainer),
                ),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.45, child: header),
            child: header,
          ),
        _AppearanceGrid(
          appearances: faces,
          source: dragPayload.source,
          busy: busy,
          selectedIds: selectedIds,
          tapTracker: tapTracker,
          shrinkWrap: true,
          onSelect: onSelectAppearance,
          onOpenItem: onOpenItem,
        ),
      ],
    );

    return DecoratedBox(
      key: Key('face-crop-facegroup-$faceGroupId'),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      ),
      child: body,
    );
  }
}

/// Boxed Excluded FaceGroup (GroupFA/GroupFM) — same membership as Unassigned.
/// No "Set name" here; drag to Assigned (or Unassigned) to promote / restore.
class _ExcludedFaceGroupClusterCard extends StatelessWidget {
  const _ExcludedFaceGroupClusterCard({
    required this.faceGroupId,
    required this.kind,
    required this.faces,
    required this.busy,
    required this.selectedIds,
    required this.tapTracker,
    required this.dragPayload,
    required this.onSelectCluster,
    required this.onSelectExclusion,
    required this.onOpenItem,
  });

  final String faceGroupId;
  final FaceGroupKind kind;
  final List<WhoExclusion> faces;
  final bool busy;
  final Set<String> selectedIds;
  final FaceCropTapTracker tapTracker;
  final FaceCropDragPayload dragPayload;
  final VoidCallback onSelectCluster;
  final void Function(WhoExclusion exclusion, {required bool toggle})
      onSelectExclusion;
  final void Function(String itemId) onOpenItem;

  String get _label =>
      kind == FaceGroupKind.fa ? 'Similar faces' : 'Grouped faces';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final header = Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('face-crop-facegroup-header-$faceGroupId'),
        onTap: busy ? null : onSelectCluster,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$_label · ${faces.length} '
                  '${faces.length == 1 ? 'face' : 'faces'}',
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dragPayload.items.isEmpty)
          header
        else
          Draggable<FaceCropDragPayload>(
            data: dragPayload,
            feedback: Material(
              elevation: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$_label · ${dragPayload.count}',
                  key: Key('face-crop-facegroup-drag-$faceGroupId'),
                  style: TextStyle(color: scheme.onPrimaryContainer),
                ),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.45, child: header),
            child: header,
          ),
        _ExclusionGrid(
          exclusions: faces,
          busy: busy,
          selectedIds: selectedIds,
          tapTracker: tapTracker,
          shrinkWrap: true,
          onSelect: onSelectExclusion,
          onOpenItem: onOpenItem,
        ),
      ],
    );

    return DecoratedBox(
      key: Key('face-crop-facegroup-$faceGroupId'),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      ),
      child: body,
    );
  }
}

class _PersonChrome extends StatelessWidget {
  const _PersonChrome({
    super.key,
    required this.detail,
    required this.controller,
    required this.renameController,
    required this.renaming,
    required this.busy,
    required this.onStartRename,
    required this.onDoneRename,
    required this.onCancelRename,
    required this.onRemovePerson,
  });

  final PersonDetail detail;
  final PersonDetailController controller;
  final TextEditingController renameController;
  final bool renaming;
  final bool busy;
  final VoidCallback onStartRename;
  final Future<void> Function() onDoneRename;
  final VoidCallback onCancelRename;
  final VoidCallback onRemovePerson;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('face-crop-person-chrome'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: renaming
                  ? TextField(
                      key: const Key('face-crop-person-rename'),
                      controller: renameController,
                      enabled: !busy,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => onDoneRename(),
                    )
                  : Text(
                      detail.name,
                      key: const Key('face-crop-person-name'),
                      style: Theme.of(context).textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            if (renaming) ...[
              TextButton(
                key: const Key('face-crop-person-rename-done'),
                onPressed: busy ? null : onDoneRename,
                child: const Text('Done'),
              ),
              TextButton(
                key: const Key('face-crop-person-rename-cancel'),
                onPressed: busy ? null : onCancelRename,
                child: const Text('Cancel'),
              ),
            ] else
              Tooltip(
                message: 'Change this person’s name',
                child: TextButton(
                  key: const Key('face-crop-person-rename-start'),
                  onPressed: busy ? null : onStartRename,
                  child: const Text('Rename'),
                ),
              ),
            if (controller.canUnassign)
              Tooltip(
                message:
                    'Remove this person. Faces move to Unassigned. '
                    'Drag a face to Unassigned to detach only that face.',
                child: TextButton(
                  key: const Key('face-crop-person-unassign'),
                  onPressed: busy ? null : onRemovePerson,
                  child: const Text('Remove'),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TrayColumn extends StatelessWidget {
  const _TrayColumn({
    super.key,
    required this.title,
    required this.tagline,
    required this.subtitle,
    required this.onAccept,
    required this.child,
    this.header,
  });

  final String title;
  final String tagline;
  final String subtitle;
  final Future<void> Function(FaceCropDragPayload data) onAccept;
  final Widget child;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<FaceCropDragPayload>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: hovering ? scheme.primary : scheme.outlineVariant,
              width: hovering ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
            color: hovering
                ? scheme.primaryContainer.withValues(alpha: 0.25)
                : scheme.surface,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  tagline,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
                child: Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (header != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: header,
                ),
              const Divider(height: 16),
              Expanded(child: child),
            ],
          ),
        );
      },
    );
  }
}

Widget _appearanceThumb(PersonAppearance a, {bool fill = false, double size = 72}) {
  final itemId = a.itemId;
  final tagId = a.tagId;
  if (itemId == null) {
    return Icon(Icons.person_outline, size: fill ? 28 : size * 0.45);
  }
  if (a.region != null) {
    return WhoExclusionCropThumb(
      itemId: itemId,
      region: a.region!,
      size: size,
      fill: fill,
      tooltip: 'Who face',
    );
  }
  if (tagId != null) {
    return WhoFaceCropThumb(
      itemId: itemId,
      tagId: tagId,
      region: a.region,
      size: size,
      fill: fill,
    );
  }
  return Icon(Icons.person_outline, size: fill ? 28 : size * 0.45);
}

class _AppearanceGrid extends StatelessWidget {
  const _AppearanceGrid({
    required this.appearances,
    required this.source,
    required this.busy,
    required this.selectedIds,
    required this.tapTracker,
    required this.onSelect,
    required this.onOpenItem,
    this.onSetName,
    this.shrinkWrap = false,
  });

  final List<PersonAppearance> appearances;
  final FaceCropTray source;
  final bool busy;
  final Set<String> selectedIds;
  final FaceCropTapTracker tapTracker;
  final void Function(PersonAppearance appearance, {required bool toggle})
      onSelect;
  final void Function(String itemId) onOpenItem;
  /// When set (Unassigned tray), shows Set name on each loose thumb.
  final void Function(String appearanceId)? onSetName;
  final bool shrinkWrap;

  FaceCropDragData _dragItem(PersonAppearance a) {
    return FaceCropDragData.appearance(
      source: source,
      appearanceId: a.id,
      itemId: a.itemId!,
      tagId: a.tagId!,
      personId: a.personId,
      faceGroupId: a.faceGroupId,
      faceGroupKind: a.faceGroupKind,
      region: a.region,
    );
  }

  FaceCropDragPayload _payloadFor(PersonAppearance a) {
    if (selectedIds.contains(a.id)) {
      final items = <FaceCropDragData>[
        for (final x in appearances)
          if (selectedIds.contains(x.id) &&
              x.itemId != null &&
              x.tagId != null)
            _dragItem(x),
      ];
      if (items.isNotEmpty) {
        return FaceCropDragPayload(source: source, items: items);
      }
    }
    return FaceCropDragPayload.single(_dragItem(a));
  }

  void _onTap(PersonAppearance a) {
    if (busy) return;
    final itemId = a.itemId;
    if (tapTracker.registerTap(a.id) && itemId != null) {
      onOpenItem(itemId);
      return;
    }
    onSelect(a, toggle: faceCropMetaPressed());
  }

  @override
  Widget build(BuildContext context) {
    if (appearances.isEmpty) {
      return const Center(child: Text('No faces'));
    }
    final scheme = Theme.of(context).colorScheme;
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1,
      ),
      itemCount: appearances.length,
      itemBuilder: (context, index) {
        final a = appearances[index];
        final itemId = a.itemId;
        final tagId = a.tagId;
        final canDrag = !busy && itemId != null && tagId != null;
        final selected = selectedIds.contains(a.id);
        final thumb = _appearanceThumb(a, size: 72);
        final faceBody = DecoratedBox(
          key: selected ? Key('face-crop-selected-${a.id}') : null,
          decoration: BoxDecoration(
            border: selected
                ? Border.all(color: scheme.primary, width: 2)
                : Border.all(color: Colors.transparent, width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(child: thumb),
        );
        final tile = Material(
          key: Key('face-crop-appearance-${a.id}'),
          color: Colors.transparent,
          child: faceBody,
        );
        final interactive = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _onTap(a),
          child: tile,
        );
        final setNameHandler = onSetName;
        final setNameButton = setNameHandler == null
            ? null
            : Positioned(
                top: 0,
                right: 0,
                child: TextButton(
                  key: Key('face-crop-set-name-${a.id}'),
                  onPressed: busy ? null : () => setNameHandler(a.id),
                  style: TextButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    visualDensity: VisualDensity.compact,
                    foregroundColor: scheme.primary,
                    backgroundColor:
                        scheme.surface.withValues(alpha: 0.92),
                  ),
                  child: const Text('Set name'),
                ),
              );
        if (!canDrag) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              interactive,
              ?setNameButton,
            ],
          );
        }
        final payload = _payloadFor(a);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Draggable<FaceCropDragPayload>(
              data: payload,
              feedback: Material(
                elevation: 4,
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _appearanceThumb(a, size: 72),
                      if (payload.count > 1)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: CircleAvatar(
                            radius: 10,
                            backgroundColor: scheme.primary,
                            child: Text(
                              '${payload.count}',
                              key: Key(
                                'face-crop-drag-count-${payload.count}',
                              ),
                              style: TextStyle(
                                color: scheme.onPrimary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              childWhenDragging: Opacity(opacity: 0.35, child: interactive),
              child: interactive,
            ),
            ?setNameButton,
          ],
        );
      },
    );
  }
}

class _ExclusionGrid extends StatelessWidget {
  const _ExclusionGrid({
    required this.exclusions,
    required this.busy,
    required this.selectedIds,
    required this.tapTracker,
    required this.onSelect,
    required this.onOpenItem,
    this.shrinkWrap = false,
  });

  final List<WhoExclusion> exclusions;
  final bool busy;
  final Set<String> selectedIds;
  final FaceCropTapTracker tapTracker;
  final void Function(WhoExclusion exclusion, {required bool toggle}) onSelect;
  final void Function(String itemId) onOpenItem;
  final bool shrinkWrap;

  FaceCropDragData _dragItem(WhoExclusion e) {
    return FaceCropDragData.exclusion(
      source: FaceCropTray.excluded,
      exclusionId: e.id,
      itemId: e.itemId,
      region: e.region,
      createdFromTagId: e.createdFromTagId,
      faceGroupId: e.faceGroupId,
      faceGroupKind: e.faceGroupKind,
    );
  }

  FaceCropDragPayload _payloadFor(WhoExclusion e) {
    if (selectedIds.contains(e.id)) {
      final items = <FaceCropDragData>[
        for (final x in exclusions)
          if (selectedIds.contains(x.id)) _dragItem(x),
      ];
      if (items.isNotEmpty) {
        return FaceCropDragPayload(
          source: FaceCropTray.excluded,
          items: items,
        );
      }
    }
    return FaceCropDragPayload.single(_dragItem(e));
  }

  void _onTap(WhoExclusion e) {
    if (busy) return;
    if (tapTracker.registerTap(e.id)) {
      onOpenItem(e.itemId);
      return;
    }
    onSelect(e, toggle: faceCropMetaPressed());
  }

  @override
  Widget build(BuildContext context) {
    if (exclusions.isEmpty) {
      return const Center(child: Text('No excluded faces'));
    }
    final scheme = Theme.of(context).colorScheme;
    return GridView.builder(
      padding: shrinkWrap ? EdgeInsets.zero : const EdgeInsets.all(8),
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1,
      ),
      itemCount: exclusions.length,
      itemBuilder: (context, index) {
        final e = exclusions[index];
        final selected = selectedIds.contains(e.id);
        final thumb = WhoExclusionCropThumb(
          itemId: e.itemId,
          region: e.region,
          size: 72,
        );
        final tile = Material(
          key: Key('face-crop-exclusion-${e.id}'),
          color: Colors.transparent,
          child: DecoratedBox(
            key: selected ? Key('face-crop-selected-${e.id}') : null,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: selected ? scheme.primary : Colors.transparent,
                width: selected ? 2 : 0,
              ),
            ),
            child: InkWell(
              onTap: () => _onTap(e),
              borderRadius: BorderRadius.circular(6),
              child: thumb,
            ),
          ),
        );
        return Draggable<FaceCropDragPayload>(
          data: _payloadFor(e),
          feedback: Material(
            elevation: 4,
            child: Opacity(opacity: 0.9, child: thumb),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: tile),
          child: tile,
        );
      },
    );
  }
}

/// Navigate to the Faces trays workspace (optionally focused on a person
/// and/or leaf folder). Switches the top-level Faces tab and pops any
/// drill-down routes so the persistent trays page is visible.
Future<void> openFaceCropTrays(
  BuildContext context, {
  String? personId,
  String? leafFolder,
}) async {
  final container = ProviderScope.containerOf(context);
  if (personId != null || leafFolder != null) {
    container.read(faceCropFocusRequestProvider.notifier).state =
        FaceCropFocusRequest(
      personId: personId,
      leafFolder: leafFolder,
      nonce: ++_faceCropFocusNonce,
    );
  }
  container.read(activeTopLevelTabProvider.notifier).state = TopLevelTab.faces;
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.popUntil((route) => route.isFirst);
  }
}
