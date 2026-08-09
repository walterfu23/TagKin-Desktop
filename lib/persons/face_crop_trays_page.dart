import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/folder_ingest_queue.dart';
import 'package:tagkin_desktop/library/item_detail_page.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';
import 'package:tagkin_desktop/persons/face_crop_drag.dart';
import 'package:tagkin_desktop/persons/face_crop_folder_scope.dart';
import 'package:tagkin_desktop/persons/person_detail_controller.dart';
import 'package:tagkin_desktop/persons/person_name_dialog.dart';
import 'package:tagkin_desktop/persons/who_exclusion_crop_thumb.dart';
import 'package:tagkin_desktop/persons/who_face_crop_thumb.dart';
import 'package:tagkin_desktop/undo/undo_controller.dart';
import 'package:tagkin_desktop/undo/undo_shortcuts.dart';
import 'package:tagkin_desktop/undo/undoable_action.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

/// Menu actions for the Faces collection chrome.
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

/// Registered by [FaceCropTraysPage] while mounted; invoked by AppShell Cmd+A
/// when the Faces tab is active (focus-independent).
VoidCallback? facesSelectAllLooseHandler;

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

/// One reversible API pair for a tray drop gesture (D12).
class _FaceDropUndoStep {
  const _FaceDropUndoStep({required this.undo, required this.redo});

  final Future<void> Function() undo;
  final Future<void> Function() redo;
}

/// Rematch selection after tray-move undo/redo (ids mint on each hop).
/// Undo/redo tag lists may differ (e.g. bystander selection vs moved multi).
class _FaceDropSelectionRestore {
  const _FaceDropSelectionRestore({
    required this.undoTagIds,
    required this.undoTray,
    required this.undoKind,
    required this.redoTagIds,
    this.redoTray,
    this.redoKind,
  });

  final List<String> undoTagIds;
  final FaceCropTray undoTray;
  final FaceCropSelectKind undoKind;
  final List<String> redoTagIds;
  final FaceCropTray? redoTray;
  final FaceCropSelectKind? redoKind;
}

/// Override for widget tests (Cmd/Ctrl simulation is flaky under flutter_test).
@visibleForTesting
bool Function()? debugFaceCropMetaPressed;

/// Override for widget tests (Shift simulation is flaky under flutter_test).
@visibleForTesting
bool Function()? debugFaceCropShiftPressed;

bool faceCropMetaPressed() {
  final override = debugFaceCropMetaPressed;
  if (override != null) return override();
  final keys = HardwareKeyboard.instance.logicalKeysPressed;
  return keys.contains(LogicalKeyboardKey.metaLeft) ||
      keys.contains(LogicalKeyboardKey.metaRight) ||
      keys.contains(LogicalKeyboardKey.controlLeft) ||
      keys.contains(LogicalKeyboardKey.controlRight);
}

bool faceCropShiftPressed() {
  final override = debugFaceCropShiftPressed;
  if (override != null) return override();
  final keys = HardwareKeyboard.instance.logicalKeysPressed;
  return keys.contains(LogicalKeyboardKey.shiftLeft) ||
      keys.contains(LogicalKeyboardKey.shiftRight);
}

/// Resolves click modifiers into a [FaceCropSelectMode] (Shift wins over Cmd).
FaceCropSelectMode faceCropSelectMode() {
  if (faceCropShiftPressed()) return FaceCropSelectMode.range;
  if (faceCropMetaPressed()) return FaceCropSelectMode.toggle;
  return FaceCropSelectMode.replace;
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
/// An optional local **collection** narrows which folders appear in the picker.
/// Persons stay library-wide; trays only show faces from the selected folder.
///
/// Finder-style face thumbs: single-click selects, Cmd/Ctrl+click multi-selects,
/// Shift+click range-selects, Cmd/Ctrl+A selects all in the active tray,
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
  /// Full library leaf folders (before collection filter).
  List<String> _allLeafFolders = const [];
  /// Visible folders in the dropdown (filtered when a collection is open).
  List<String> _leafFolders = const [];
  String? _leafFolder;
  Set<String> _scopedItemIds = const {};
  bool _loading = true;
  bool _busy = false;
  Object? _error;

  /// Bumped when trays are intentionally resynced ([_reload], drop undo/redo).
  /// Stale [_refreshTraysQuietly] completions must not overwrite newer state.
  int _traySyncEpoch = 0;

  /// Skip collection dirty while restoring Faces look from a saved collection.
  bool _applyingCollectionFacesUi = false;
  int _appliedCollectionUiEpoch = -1;

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
  /// Anchor for Shift+click range (last plain / Cmd click, or cluster select).
  String? _selectionAnchorId;
  final FaceCropTapTracker _faceTapTracker = FaceCropTapTracker();
  final _clusterScrollController = ScrollController();
  final Map<String, GlobalKey> _clusterKeys = <String, GlobalKey>{};
  final UndoController _undoStack = UndoController();
  final FocusNode _trayFocusNode = FocusNode(debugLabel: 'faces-trays');

  int get _trayPageLimit =>
      ref.read(desktopPrefsProvider).facesTrayPageLimit.clamp(50, 500);

  int _lastIngestRefreshTick = 0;
  bool _lastIngestHadActiveJobs = false;
  FolderIngestQueue? _ingestQueue;

  /// Last [FaceCropFocusRequest.nonce] applied (avoids re-applying).
  int? _lastFocusNonce;

  /// Narrow [all] to the current collection's folders.
  List<String> _foldersForCollection(List<String> all) {
    final cols = ref.read(collectionsControllerProvider);
    if (!cols.hasCurrent) return all;
    final allowed = cols.current.leafFolders.toSet();
    return [for (final f in all) if (allowed.contains(f)) f];
  }

  Future<void> _refilterFromCollection() async {
    if (!mounted || _loading) return;
    final visible = _foldersForCollection(_allLeafFolders);
    final prevFolder = _leafFolder;
    final folder = resolveLeafFolderSelection(
      folders: visible,
      preferred: _leafFolder ?? faceCropLastLeafFolder,
    );
    faceCropLastLeafFolder = folder;
    final foldersChanged = visible.length != _leafFolders.length ||
        !_listEquals(visible, _leafFolders);
    if (!foldersChanged && folder == prevFolder) {
      setState(() {});
      return;
    }
    setState(() {
      _leafFolders = visible;
      _leafFolder = folder;
    });
    if (folder != prevFolder) {
      _autoSelectFirstInFolder = folder != null;
      await _reload();
    }
  }

  void _clearSelection() {
    _faceTapTracker.clear();
    if (_selectedIds.isEmpty &&
        _selectionTray == null &&
        _selectionKind == null &&
        _selectionAnchorId == null) {
      return;
    }
    setState(() {
      _selectedIds.clear();
      _selectionTray = null;
      _selectionKind = null;
      _selectionAnchorId = null;
    });
  }

  /// Visual order of appearance ids in [tray] (clusters then loose).
  List<String> _orderedAppearanceIds(FaceCropTray tray) {
    switch (tray) {
      case FaceCropTray.assigned:
        return [
          for (final c in _assignedMultiClusters())
            for (final a in c.faces) a.id,
          for (final a in _assignedSoloFaces()) a.id,
        ];
      case FaceCropTray.unassigned:
        return [
          for (final c in _faceGroupMultiClusters())
            for (final a in c.faces) a.id,
          for (final a in _unassignedLooseFaces()) a.id,
        ];
      case FaceCropTray.excluded:
        return const [];
    }
  }

  /// Visual order of exclusion ids (clusters then loose).
  List<String> _orderedExclusionIds() {
    return [
      for (final c in _excludedFaceGroupMultiClusters())
        for (final e in c.faces) e.id,
      for (final e in _excludedLooseFaces()) e.id,
    ];
  }

  void _applyRangeSelection(List<String> order, String clickedId) {
    final anchor = _selectionAnchorId;
    final a = anchor == null ? -1 : order.indexOf(anchor);
    final b = order.indexOf(clickedId);
    if (a < 0 || b < 0) {
      _selectedIds
        ..clear()
        ..add(clickedId);
      _selectionAnchorId = clickedId;
      return;
    }
    final lo = a < b ? a : b;
    final hi = a < b ? b : a;
    _selectedIds
      ..clear()
      ..addAll(order.sublist(lo, hi + 1));
  }

  void _selectAppearance(
    PersonAppearance a,
    FaceCropTray tray, {
    required FaceCropSelectMode mode,
  }) {
    setState(() {
      if (mode == FaceCropSelectMode.range &&
          _selectionTray == tray &&
          _selectionKind == FaceCropSelectKind.appearance) {
        _applyRangeSelection(_orderedAppearanceIds(tray), a.id);
      } else if (mode == FaceCropSelectMode.toggle &&
          _selectionTray == tray &&
          _selectionKind == FaceCropSelectKind.appearance) {
        if (!_selectedIds.remove(a.id)) {
          _selectedIds.add(a.id);
        }
        if (_selectedIds.isEmpty) {
          _selectionTray = null;
          _selectionKind = null;
          _selectionAnchorId = null;
        } else {
          _selectionAnchorId = a.id;
        }
      } else {
        _selectedIds
          ..clear()
          ..add(a.id);
        _selectionTray = tray;
        _selectionKind = FaceCropSelectKind.appearance;
        _selectionAnchorId = a.id;
      }
    });
    final pid = a.personId;
    if (pid == null) return;
    // Stay focused on the tapped person's filter (no overview mode).
    if (_personId != pid) {
      unawaited(_selectPerson(pid, recordUndo: false));
    }
  }

  void _selectExclusion(WhoExclusion e, {required FaceCropSelectMode mode}) {
    setState(() {
      if (mode == FaceCropSelectMode.range &&
          _selectionTray == FaceCropTray.excluded &&
          _selectionKind == FaceCropSelectKind.exclusion) {
        _applyRangeSelection(_orderedExclusionIds(), e.id);
      } else if (mode == FaceCropSelectMode.toggle &&
          _selectionTray == FaceCropTray.excluded &&
          _selectionKind == FaceCropSelectKind.exclusion) {
        if (!_selectedIds.remove(e.id)) {
          _selectedIds.add(e.id);
        }
        if (_selectedIds.isEmpty) {
          _selectionTray = null;
          _selectionKind = null;
          _selectionAnchorId = null;
        } else {
          _selectionAnchorId = e.id;
        }
      } else {
        _selectedIds
          ..clear()
          ..add(e.id);
        _selectionTray = FaceCropTray.excluded;
        _selectionKind = FaceCropSelectKind.exclusion;
        _selectionAnchorId = e.id;
      }
    });
  }

  void _selectAllInActiveTray() {
    // Cmd+A only covers loose/solo thumbs — not faces inside boxed groups.
    FaceCropTray? tray = _selectionTray;
    FaceCropSelectKind? kind = _selectionKind;
    if (tray == null || kind == null) {
      final unassigned = [for (final a in _unassignedLooseFaces()) a.id];
      if (unassigned.isNotEmpty) {
        tray = FaceCropTray.unassigned;
        kind = FaceCropSelectKind.appearance;
      } else {
        final excluded = [for (final e in _excludedLooseFaces()) e.id];
        if (excluded.isNotEmpty) {
          tray = FaceCropTray.excluded;
          kind = FaceCropSelectKind.exclusion;
        } else {
          final assigned = [for (final a in _assignedSoloFaces()) a.id];
          if (assigned.isEmpty) return;
          tray = FaceCropTray.assigned;
          kind = FaceCropSelectKind.appearance;
        }
      }
    }

    final List<String> ids;
    if (kind == FaceCropSelectKind.exclusion) {
      ids = [for (final e in _excludedLooseFaces()) e.id];
    } else {
      switch (tray) {
        case FaceCropTray.assigned:
          ids = [for (final a in _assignedSoloFaces()) a.id];
        case FaceCropTray.unassigned:
          ids = [for (final a in _unassignedLooseFaces()) a.id];
        case FaceCropTray.excluded:
          ids = const [];
      }
    }
    if (ids.isEmpty) return;
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(ids);
      _selectionTray = tray;
      _selectionKind = kind;
      _selectionAnchorId = ids.first;
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
      _selectionAnchorId = faces.first.id;
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
      _selectionAnchorId = faces.first.id;
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
      _selectionAnchorId = faces.first.id;
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
    facesSelectAllLooseHandler = _selectAllInActiveTray;
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
    facesSelectAllLooseHandler = null;
    _ingestQueue?.removeListener(_onIngestQueueChanged);
    _assignedController?.dispose();
    _renameController.dispose();
    _clusterScrollController.dispose();
    _trayFocusNode.dispose();
    _undoStack.dispose();
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
      final allFolders = [
        for (final f in distinctLeafFolders(items))
          if (ingestQueue == null || !ingestQueue.isLoadingPath(f)) f,
      ];
      final folders = _foldersForCollection(allFolders);
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

      if (!foldersChanged &&
          !folderChanged &&
          !scopeChanged &&
          _listEquals(allFolders, _allLeafFolders)) {
        return;
      }

      setState(() {
        _allLeafFolders = allFolders;
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
            await _selectPerson(pid, recordUndo: false);
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
    _traySyncEpoch++;
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
      final allFolders = [
        for (final f in distinctLeafFolders(items))
          if (ingestQueue == null || !ingestQueue.isLoadingPath(f)) f,
      ];
      final folders = _foldersForCollection(allFolders);
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
      // Never leave "Select a person" overview.
      var pid = _personId;
      var assignAsNew = _assignAsNewPerson;
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
        } else {
          assignAsNew = false;
        }
      } else {
        final stillListed =
            pid != null && persons.any((p) => p.id == pid);
        if (pid != null && !stillListed) {
          _assignedController?.dispose();
          _assignedController = null;
          _renameController.clear();
          pid = null;
        }
        final resolved = _resolvedAssignedFocus(
          personId: pid,
          assignAsNew: assignAsNew,
          persons: persons,
          assignedOverview: assignedOverview,
          canCreateNew: canCreateNew,
        );
        if (resolved.personId != pid) {
          _assignedController?.dispose();
          _assignedController = null;
          _renameController.clear();
        }
        pid = resolved.personId;
        assignAsNew = resolved.assignAsNew;
        if (pid != null) {
          await _controllerFor(pid).load();
          _renameController.text = _assignedController?.detail?.name ?? '';
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
        _allLeafFolders = allFolders;
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
    if (!_applyingCollectionFacesUi) {
      ref.read(collectionsControllerProvider).updateFacesLook(leafFolder: folder);
    }
    await _reload();
  }

  Future<void> _applyCollectionFacesUi(CollectionsController cols) async {
    if (!cols.sessionReady) return;
    _appliedCollectionUiEpoch = cols.uiEpoch;
    final faces = cols.current.ui.faces;
    _applyingCollectionFacesUi = true;
    try {
      final folder = faces.leafFolder;
      if (folder != null && folder != _leafFolder) {
        faceCropLastLeafFolder = folder;
        _autoSelectFirstInFolder = faces.personId == null;
        _assignAsNewPerson = false;
        _clearSelection();
        setState(() => _leafFolder = folder);
        await _reload();
      }
      if (!mounted) return;
      // null personId in saved ui means "unset", not "clear current selection".
      final personId = faces.personId;
      if (personId != null && personId != _personId) {
        await _selectPerson(personId);
      }
    } finally {
      _applyingCollectionFacesUi = false;
    }
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

  /// No "Select a person" overview: focused person, New Person…, or empty.
  static ({String? personId, bool assignAsNew}) _resolvedAssignedFocus({
    required String? personId,
    required bool assignAsNew,
    required List<Person> persons,
    required List<PersonAppearance> assignedOverview,
    required bool canCreateNew,
  }) {
    if (personId != null) {
      return (personId: personId, assignAsNew: false);
    }
    if (assignAsNew && canCreateNew) {
      return (personId: null, assignAsNew: true);
    }
    final first = _firstPersonIdInFolder(persons, assignedOverview);
    if (first != null) {
      return (personId: first, assignAsNew: false);
    }
    if (canCreateNew) {
      return (personId: null, assignAsNew: true);
    }
    return (personId: null, assignAsNew: false);
  }

  /// Display name for chrome / subtitle. Person.name is always non-empty (R2).
  static String personDisplayName(Person p) => p.name.isNotEmpty ? p.name : p.id;

  static String _personDropdownLabel(Person p, {required bool inFolder}) {
    final base = personDisplayName(p);
    return inFolder ? '$base · in folder' : base;
  }

  /// Encodes Assigned person dropdown selection for undo (sentinel = New Person…).
  String? _encodedPersonSelection() {
    if (_assignAsNewPerson) return _newPersonSentinel;
    return _personId;
  }

  Future<void> _selectPerson(
    String? id, {
    bool recordUndo = true,
  }) async {
    final prior = _encodedPersonSelection();
    if (id == null) {
      // Never enter overview — resolve to first in-folder person or New Person…
      final canCreateNew =
          _unassignedTrayFaceCount > 0 || _excluded.isNotEmpty;
      final resolved = _resolvedAssignedFocus(
        personId: null,
        assignAsNew: false,
        persons: _persons,
        assignedOverview: _assignedOverview,
        canCreateNew: canCreateNew,
      );
      if (resolved.personId != null) {
        await _selectPerson(resolved.personId, recordUndo: recordUndo);
        return;
      }
      if (resolved.assignAsNew) {
        await _selectPerson(_newPersonSentinel, recordUndo: recordUndo);
        return;
      }
      setState(() {
        _personId = null;
        _assignAsNewPerson = false;
        _renaming = false;
        _renameController.clear();
        _assignedController?.dispose();
        _assignedController = null;
      });
      if (!_applyingCollectionFacesUi) {
        ref
            .read(collectionsControllerProvider)
            .updateFacesLook(clearPersonId: true);
      }
    } else if (id == _newPersonSentinel) {
      setState(() {
        _personId = null;
        _assignAsNewPerson = true;
        _renaming = false;
        _renameController.clear();
        _assignedController?.dispose();
        _assignedController = null;
      });
      if (!_applyingCollectionFacesUi) {
        ref
            .read(collectionsControllerProvider)
            .updateFacesLook(clearPersonId: true);
      }
    } else {
      final controller = _controllerFor(id);
      setState(() {
        _personId = id;
        _assignAsNewPerson = false;
        _renaming = false;
        // Clear immediately so a freshly-loaded person never shows a stale name
        // while load() is in flight.
        _renameController.clear();
      });
      if (!_applyingCollectionFacesUi) {
        ref.read(collectionsControllerProvider).updateFacesLook(personId: id);
      }
      _scrollToCluster(id);
      await controller.load();
      if (!mounted) return;
      setState(() {
        _renameController.text = controller.detail?.name ?? '';
      });
      _scrollToCluster(id);
    }

    if (!mounted) return;
    final next = _encodedPersonSelection();
    if (recordUndo &&
        !_applyingCollectionFacesUi &&
        prior != next) {
      _undoStack.push(
        CallbackUndoableAction(
          label: 'Select person',
          onUndo: () => _selectPerson(prior, recordUndo: false),
          onRedo: () => _selectPerson(next, recordUndo: false),
        ),
      );
    }
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
      _markCollectionDirty();
      _undoStack.push(
        CallbackUndoableAction(
          label: 'Set name',
          onUndo: () async {
            await persons.unlinkAppearance(appearanceId);
            _markCollectionDirty();
            await _reload();
          },
          onRedo: () async {
            final restored = await persons.reassignAppearance(
              appearanceId,
              name: name,
            );
            final pid = restored.personId;
            if (pid != null && mounted) {
              _personId = pid;
            }
            _markCollectionDirty();
            await _reload();
          },
        ),
      );
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
      final appearanceIds = [for (final a in detail.appearances) a.id];
      final tagIds = [
        for (final a in detail.appearances)
          if (a.tagId != null) a.tagId!,
      ];
      await _reload();
      _markCollectionDirty();
      // assignFaceGroup deletes the prior FaceGroup; undo via unassign
      // (≥2 → new GroupFM). Redo uses that new faceGroupId (closure).
      // Resolve members by tagId — appearance ids remint across tray hops.
      var liveAppearanceIds = List<String>.from(appearanceIds);
      String? redoFaceGroupId;
      _undoStack.push(
        CallbackUndoableAction(
          label: 'Set name',
          onUndo: () async {
            final resolved = _assignedIdsForTagIds(tagIds);
            final ids = tagIds.isNotEmpty && resolved.length == tagIds.length
                ? resolved
                : liveAppearanceIds;
            final restored = await persons.unassignAppearances(ids);
            liveAppearanceIds = [for (final a in restored) a.id];
            redoFaceGroupId = restored
                .map((a) => a.faceGroupId)
                .whereType<String>()
                .firstOrNull;
            if (mounted) {
              _personId = null;
            }
            _markCollectionDirty();
            await _reload();
          },
          onRedo: () async {
            // Prefer tag resolve — a newer redo (e.g. Group) may have reminted.
            final fg = _faceGroupIdForTagIds(tagIds) ?? redoFaceGroupId;
            if (fg == null) {
              throw StateError('No FaceGroup to re-assign after undo');
            }
            final again = await persons.assignFaceGroup(fg, name: name);
            liveAppearanceIds = [for (final a in again.appearances) a.id];
            redoFaceGroupId = null;
            if (mounted) {
              _personId = again.id;
            }
            _markCollectionDirty();
            await _reload();
          },
        ),
      );
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

  void _markCollectionDirty() {
    ref.read(collectionsControllerProvider).markDirty();
  }

  String _faceDropUndoLabel(FaceCropTray target) => switch (target) {
        FaceCropTray.unassigned => 'Move to Unassigned',
        FaceCropTray.assigned => 'Assign faces',
        FaceCropTray.excluded => 'Exclude faces',
      };

  void _recordFaceDropUndo(
    List<_FaceDropUndoStep> steps,
    FaceCropTray target, {
    _FaceDropSelectionRestore? selectionRestore,
  }) {
    if (steps.isEmpty) return;
    final label = _faceDropUndoLabel(target);
    final restore = selectionRestore;
    _undoStack.push(
      CallbackUndoableAction(
        label: label,
        onUndo: () async {
          if (!mounted) return;
          setState(() => _busy = true);
          _traySyncEpoch++;
          try {
            for (var i = steps.length - 1; i >= 0; i--) {
              await steps[i].undo();
            }
            _markCollectionDirty();
            await _reload();
            if (!mounted || restore == null) return;
            if (restore.undoTagIds.isNotEmpty) {
              _restoreLooseSelectionByTagIds(
                tagIds: restore.undoTagIds,
                tray: restore.undoTray,
                kind: restore.undoKind,
              );
            }
          } finally {
            if (mounted) setState(() => _busy = false);
          }
        },
        onRedo: () async {
          if (!mounted) return;
          setState(() => _busy = true);
          _traySyncEpoch++;
          try {
            for (final step in steps) {
              await step.redo();
            }
            _markCollectionDirty();
            await _reload();
            if (!mounted || restore == null) return;
            final redoTray = restore.redoTray;
            final redoKind = restore.redoKind;
            if (restore.redoTagIds.isEmpty ||
                redoTray == null ||
                redoKind == null) {
              setState(() {
                _selectedIds.clear();
                _selectionTray = null;
                _selectionKind = null;
                _selectionAnchorId = null;
              });
            } else {
              _restoreLooseSelectionByTagIds(
                tagIds: restore.redoTagIds,
                tray: redoTray,
                kind: redoKind,
              );
            }
          } finally {
            if (mounted) setState(() => _busy = false);
          }
        },
      ),
    );
  }

  /// Stable tagIds for the current tray selection (empty if none / incomplete).
  ({List<String> tagIds, FaceCropTray tray, FaceCropSelectKind kind})?
      _snapshotSelectionByTagIds() {
    final tray = _selectionTray;
    final kind = _selectionKind;
    if (tray == null || kind == null || _selectedIds.isEmpty) return null;
    final tagIds = <String>[];
    if (kind == FaceCropSelectKind.exclusion) {
      for (final id in _selectedIds) {
        for (final e in _excluded) {
          if (e.id == id && e.createdFromTagId != null) {
            tagIds.add(e.createdFromTagId!);
            break;
          }
        }
      }
    } else {
      for (final id in _selectedIds) {
        String? tagId;
        for (final a in _unassigned) {
          if (a.id == id) {
            tagId = a.tagId;
            break;
          }
        }
        if (tagId == null) {
          for (final a in _assignedOverview) {
            if (a.id == id) {
              tagId = a.tagId;
              break;
            }
          }
        }
        if (tagId != null) tagIds.add(tagId);
      }
    }
    if (tagIds.isEmpty) return null;
    return (tagIds: tagIds, tray: tray, kind: kind);
  }

  /// Current Unassigned appearance ids for [tagIds] (loose-only when [looseOnly]).
  List<String> _unassignedIdsForTagIds(
    List<String> tagIds, {
    bool looseOnly = true,
  }) {
    final ids = <String>[];
    for (final tagId in tagIds) {
      for (final a in _unassigned) {
        if (a.tagId != tagId || a.personId != null) continue;
        if (looseOnly && a.faceGroupId != null) continue;
        ids.add(a.id);
        break;
      }
    }
    return ids;
  }

  /// Current Excluded ids for [tagIds] (loose-only when [looseOnly]).
  List<String> _exclusionIdsForTagIds(
    List<String> tagIds, {
    bool looseOnly = true,
  }) {
    final ids = <String>[];
    for (final tagId in tagIds) {
      for (final e in _excluded) {
        if (e.createdFromTagId != tagId) continue;
        if (looseOnly && e.faceGroupId != null) continue;
        ids.add(e.id);
        break;
      }
    }
    return ids;
  }

  /// Live exclusion id for [tagId] (account list, then tray). Remints across
  /// undo hops make frozen ids unsafe for [undoWhoExclusion].
  Future<String?> _liveExclusionIdForTag(String tagId) async {
    final persons = ref.read(personsRepositoryProvider);
    final page = await persons.listAccountWhoExclusions(limit: _trayPageLimit);
    for (final e in page.exclusions) {
      if (e.createdFromTagId == tagId) return e.id;
    }
    for (final e in _excluded) {
      if (e.createdFromTagId == tagId) return e.id;
    }
    return null;
  }

  Future<void> _undoWhoExclusionForTag({
    required String itemId,
    required String tagId,
    required String fallbackExclusionId,
  }) async {
    final items = ref.read(itemsRepositoryProvider);
    final id = await _liveExclusionIdForTag(tagId) ?? fallbackExclusionId;
    await items.undoWhoExclusion(itemId, id);
  }

  /// Assigned (named) appearance ids for [tagIds] in the overview tray.
  List<String> _assignedIdsForTagIds(List<String> tagIds) {
    final ids = <String>[];
    for (final tagId in tagIds) {
      for (final a in _assignedOverview) {
        if (a.tagId == tagId &&
            a.personId != null &&
            a.faceGroupId == null) {
          ids.add(a.id);
          break;
        }
      }
    }
    return ids;
  }

  /// Shared FaceGroup id for members matching [tagIds], if any.
  String? _faceGroupIdForTagIds(List<String> tagIds) {
    String? found;
    for (final tagId in tagIds) {
      String? fg;
      for (final a in _unassigned) {
        if (a.tagId == tagId && a.faceGroupId != null) {
          fg = a.faceGroupId;
          break;
        }
      }
      if (fg == null) {
        for (final e in _excluded) {
          if (e.createdFromTagId == tagId && e.faceGroupId != null) {
            fg = e.faceGroupId;
            break;
          }
        }
      }
      if (fg == null) return null;
      found ??= fg;
      if (found != fg) return null;
    }
    return found;
  }

  /// After tray-move undo/redo remint ids; reselect by stable tagId.
  /// Empty [tagIds] clears selection. ≥1 match is enough (bystander undo).
  void _restoreLooseSelectionByTagIds({
    required List<String> tagIds,
    required FaceCropTray tray,
    required FaceCropSelectKind kind,
  }) {
    if (tagIds.isEmpty) {
      setState(() {
        _selectedIds.clear();
        _selectionTray = null;
        _selectionKind = null;
        _selectionAnchorId = null;
      });
      return;
    }
    final ids = <String>[];
    if (kind == FaceCropSelectKind.exclusion) {
      for (final tagId in tagIds) {
        for (final e in _excluded) {
          if (e.createdFromTagId == tagId && e.faceGroupId == null) {
            ids.add(e.id);
            break;
          }
        }
      }
    } else if (tray == FaceCropTray.assigned) {
      for (final tagId in tagIds) {
        for (final a in _assignedOverview) {
          if (a.tagId == tagId &&
              a.personId != null &&
              a.faceGroupId == null) {
            ids.add(a.id);
            break;
          }
        }
      }
    } else {
      for (final tagId in tagIds) {
        for (final a in _unassigned) {
          if (a.tagId == tagId &&
              a.personId == null &&
              a.faceGroupId == null) {
            ids.add(a.id);
            break;
          }
        }
      }
    }
    if (ids.isEmpty) return;
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(ids);
      _selectionTray = tray;
      _selectionKind = kind;
      _selectionAnchorId = ids.first;
    });
    _pruneOrRemapLooseSelection();
  }

  /// Drop ids that are no longer loose in the active selection tray.
  void _pruneOrRemapLooseSelection() {
    final tray = _selectionTray;
    final kind = _selectionKind;
    if (tray == null || kind == null || _selectedIds.isEmpty) return;

    final kept = <String>[];
    if (tray == FaceCropTray.unassigned &&
        kind == FaceCropSelectKind.appearance) {
      final loose = _unassignedLooseFaces().map((a) => a.id).toSet();
      for (final id in _selectedIds) {
        if (loose.contains(id)) kept.add(id);
      }
    } else if (tray == FaceCropTray.excluded &&
        kind == FaceCropSelectKind.exclusion) {
      final loose = _excludedLooseFaces().map((e) => e.id).toSet();
      for (final id in _selectedIds) {
        if (loose.contains(id)) kept.add(id);
      }
    } else if (tray == FaceCropTray.assigned &&
        kind == FaceCropSelectKind.appearance) {
      final assigned = {
        for (final a in _assignedOverview)
          if (a.personId != null && a.faceGroupId == null) a.id,
      };
      for (final id in _selectedIds) {
        if (assigned.contains(id)) kept.add(id);
      }
    } else {
      return;
    }

    if (kept.length == _selectedIds.length) return;
    setState(() {
      if (kept.isEmpty) {
        _selectedIds.clear();
        _selectionTray = null;
        _selectionKind = null;
        _selectionAnchorId = null;
      } else {
        _selectedIds
          ..clear()
          ..addAll(kept);
        _selectionAnchorId = kept.first;
      }
    });
  }

  void _recordDropStepForOne(
    List<_FaceDropUndoStep>? steps,
    FaceCropTray target,
    FaceCropDragData data,
    _FaceMoveResult result, {
    String? assignPersonId,
    String? assignName,
  }) {
    if (steps == null) return;
    final persons = ref.read(personsRepositoryProvider);
    final items = ref.read(itemsRepositoryProvider);
    final source = data.source;

    switch (target) {
      case FaceCropTray.unassigned:
        if (data.isExclusion && data.exclusionId != null) {
          final tagId = data.tagId ?? data.createdFromTagId;
          if (tagId == null) return;
          final itemId = data.itemId;
          // Undo mints a new exclusion id; redo resolves by tagId (remints).
          var liveExclusionId = data.exclusionId!;
          steps.add(
            _FaceDropUndoStep(
              undo: () async {
                final created =
                    await items.createWhoExclusion(itemId, tagId);
                liveExclusionId = created.exclusion.id;
              },
              redo: () => _undoWhoExclusionForTag(
                itemId: itemId,
                tagId: tagId,
                fallbackExclusionId: liveExclusionId,
              ),
            ),
          );
        } else if (source == FaceCropTray.assigned &&
            data.personId != null &&
            data.appearanceId != null) {
          final id = result.addedAppearance?.id ?? data.appearanceId!;
          final pid = data.personId!;
          steps.add(
            _FaceDropUndoStep(
              undo: () => persons.reassignAppearance(id, personId: pid),
              redo: () => persons.unlinkAppearance(id),
            ),
          );
        }
      case FaceCropTray.excluded:
        final tagId = data.tagId;
        if (tagId == null) return;
        final itemId = data.itemId;
        final exclusionId = result.addedExclusion?.id;
        if (exclusionId == null) return;
        // createWhoExclusion remints ids; undo resolves by tagId.
        var liveExclusionId = exclusionId;
        if (source == FaceCropTray.assigned && data.personId != null) {
          final pid = data.personId!;
          steps.add(
            _FaceDropUndoStep(
              undo: () async {
                await _undoWhoExclusionForTag(
                  itemId: itemId,
                  tagId: tagId,
                  fallbackExclusionId: liveExclusionId,
                );
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
                  throw StateError(
                    'Could not find appearance after undo exclude',
                  );
                }
                await persons.reassignAppearance(match.id, personId: pid);
              },
              redo: () async {
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
                  // Still Assigned (first redo after forward exclude)?
                  final assignedPage = await persons.listAssignedAppearances(
                    limit: _trayPageLimit,
                  );
                  for (final a in assignedPage.appearances) {
                    if (a.tagId == tagId) {
                      match = a;
                      break;
                    }
                  }
                }
                if (match == null) {
                  throw StateError(
                    'Could not find appearance after redo exclude',
                  );
                }
                if (match.personId != null) {
                  await persons.unlinkAppearance(match.id);
                }
                final created =
                    await items.createWhoExclusion(itemId, tagId);
                liveExclusionId = created.exclusion.id;
              },
            ),
          );
        } else {
          steps.add(
            _FaceDropUndoStep(
              undo: () => _undoWhoExclusionForTag(
                itemId: itemId,
                tagId: tagId,
                fallbackExclusionId: liveExclusionId,
              ),
              redo: () async {
                final created =
                    await items.createWhoExclusion(itemId, tagId);
                liveExclusionId = created.exclusion.id;
              },
            ),
          );
        }
      case FaceCropTray.assigned:
        final pid = assignPersonId ?? _personId;
        final name = assignName;
        if (data.isExclusion && data.exclusionId != null) {
          final itemId = data.itemId;
          final tagId = data.tagId ?? data.createdFromTagId;
          final assigned = result.addedAppearance;
          if (assigned == null || tagId == null) return;
          // Forward undid exclusion [data.exclusionId]; undo remints a new one.
          var liveExclusionId = data.exclusionId!;
          steps.add(
            _FaceDropUndoStep(
              undo: () async {
                await persons.unlinkAppearance(assigned.id);
                final created =
                    await items.createWhoExclusion(itemId, tagId);
                liveExclusionId = created.exclusion.id;
              },
              redo: () async {
                await _undoWhoExclusionForTag(
                  itemId: itemId,
                  tagId: tagId,
                  fallbackExclusionId: liveExclusionId,
                );
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
                  throw StateError(
                    'Could not find appearance after undo exclude',
                  );
                }
                if (name != null && name.isNotEmpty) {
                  await persons.reassignAppearance(match.id, name: name);
                } else {
                  await persons.reassignAppearance(match.id, personId: pid!);
                }
              },
            ),
          );
        } else if (data.appearanceId != null) {
          final id = data.appearanceId!;
          steps.add(
            _FaceDropUndoStep(
              undo: () => persons.unlinkAppearance(id),
              redo: () => name != null && name.isNotEmpty
                  ? persons.reassignAppearance(id, name: name)
                  : persons.reassignAppearance(id, personId: pid!),
            ),
          );
        }
    }
  }

  Future<_FaceMoveResult> _applyOneDrop(
    FaceCropTray target,
    FaceCropDragData data, {
    String? assignPersonId,
    String? assignName,
    List<_FaceDropUndoStep>? undoSteps,
  }) async {
    final persons = ref.read(personsRepositoryProvider);
    final items = ref.read(itemsRepositoryProvider);

    switch (target) {
      case FaceCropTray.unassigned:
        // Appearance batches (single unlink vs. bulk unassign) are handled
        // directly in [_onDrop]; only exclusion undos reach here.
        if (data.isExclusion && data.exclusionId != null) {
          await items.undoWhoExclusion(data.itemId, data.exclusionId!);
          // Server mints a new appearance id; resolve it so the tray updates
          // immediately and loose multi-select can be reselected.
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
          final result = _FaceMoveResult(
            removedExclusionId: data.exclusionId,
            addedAppearance: match,
          );
          _recordDropStepForOne(
            undoSteps,
            target,
            data,
            result,
            assignPersonId: assignPersonId,
            assignName: assignName,
          );
          return result;
        }
        return const _FaceMoveResult();
      case FaceCropTray.excluded:
        final tagId = data.tagId;
        if (tagId == null) {
          throw StateError('Exclude requires a who tag id');
        }
        final created = await items.createWhoExclusion(data.itemId, tagId);
        final result = _FaceMoveResult(
          removedAppearanceId: data.appearanceId,
          removedExclusionId: null,
          addedExclusion: created.exclusion,
        );
        _recordDropStepForOne(
          undoSteps,
          target,
          data,
          result,
          assignPersonId: assignPersonId,
          assignName: assignName,
        );
        return result;
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
          final result = _FaceMoveResult(
            removedExclusionId: data.exclusionId,
            removedAppearanceId: match.id,
            addedAppearance: updated,
          );
          _recordDropStepForOne(
            undoSteps,
            target,
            data,
            result,
            assignPersonId: assignPersonId,
            assignName: assignName,
          );
          return result;
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
          final result = _FaceMoveResult(
            removedAppearanceId: data.appearanceId,
            addedAppearance: updated,
          );
          _recordDropStepForOne(
            undoSteps,
            target,
            data,
            result,
            assignPersonId: assignPersonId,
            assignName: assignName,
          );
          return result;
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

  /// Same-person ≥2 leaving Assigned → one GroupFM batch; solos / already-loose
  /// stay per-face.
  ({
    List<List<FaceCropDragData>> samePersonBatches,
    List<FaceCropDragData> perFace,
  }) _partitionLeaveAssignedAppearances(List<FaceCropDragData> items) {
    final byPerson = <String, List<FaceCropDragData>>{};
    final perFace = <FaceCropDragData>[];
    for (final d in items) {
      final pid = d.personId;
      if (pid == null) {
        perFace.add(d);
      } else {
        (byPerson[pid] ??= <FaceCropDragData>[]).add(d);
      }
    }
    final batches = <List<FaceCropDragData>>[];
    for (final group in byPerson.values) {
      if (group.length >= 2) {
        batches.add(group);
      } else {
        perFace.addAll(group);
      }
    }
    return (samePersonBatches: batches, perFace: perFace);
  }

  /// Applies tray-move patches and returns undo/redo selection restore metadata.
  _FaceDropSelectionRestore? _applyMoveResults(
    List<_FaceMoveResult> results, {
    ({List<String> tagIds, FaceCropTray tray, FaceCropSelectKind kind})?
        priorSelection,
  }) {
    if (results.isEmpty) return null;
    String? loadPersonId;
    var clearFacesPerson = false;
    var redoTagIds = <String>[];
    FaceCropTray? redoTray;
    FaceCropSelectKind? redoKind;
    var undoTagIds = <String>[];
    FaceCropTray? undoTray;
    FaceCropSelectKind? undoKind;
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

      // Loose multi-move: keep destination selection so Group / triage continues.
      final selectIds = <String>[];
      final tagIds = <String>[];
      FaceCropTray? selectTray;
      FaceCropSelectKind? selectKind;
      var allLoose = true;
      for (final r in results) {
        final ex = r.addedExclusion;
        if (ex != null && _exclusionInScope(ex)) {
          if (ex.faceGroupId != null) allLoose = false;
          selectIds.add(ex.id);
          final tagId = ex.createdFromTagId;
          if (tagId != null) tagIds.add(tagId);
          selectTray = FaceCropTray.excluded;
          selectKind = FaceCropSelectKind.exclusion;
        }
        final ap = r.addedAppearance;
        if (ap != null && _appearanceInScope(ap)) {
          if (ap.personId != null || ap.faceGroupId != null) allLoose = false;
          selectIds.add(ap.id);
          final tagId = ap.tagId;
          if (tagId != null) tagIds.add(tagId);
          selectTray = FaceCropTray.unassigned;
          selectKind = FaceCropSelectKind.appearance;
        }
      }
      if (allLoose &&
          selectIds.length >= 2 &&
          selectTray != null &&
          selectKind != null) {
        _selectedIds
          ..clear()
          ..addAll(selectIds);
        _selectionTray = selectTray;
        _selectionKind = selectKind;
        _selectionAnchorId = selectIds.first;
        if (tagIds.length == selectIds.length &&
            (selectTray == FaceCropTray.excluded ||
                selectTray == FaceCropTray.unassigned)) {
          redoTagIds = List<String>.of(tagIds);
          redoTray = selectTray;
          redoKind = selectKind;
          undoTagIds = List<String>.of(tagIds);
          undoTray = selectTray == FaceCropTray.excluded
              ? FaceCropTray.unassigned
              : FaceCropTray.excluded;
          undoKind = selectTray == FaceCropTray.excluded
              ? FaceCropSelectKind.appearance
              : FaceCropSelectKind.exclusion;
        }
      } else {
        _selectedIds.clear();
        _selectionTray = null;
        _selectionKind = null;
        _selectionAnchorId = null;
        // Unassigned/Excluded → Assigned clears forward selection, but undo
        // should reselect the loose source faces (≥2 with tagIds).
        final assignedTagIds = <String>[];
        var fromUnassigned = true;
        var fromExcluded = true;
        for (final r in results) {
          final ap = r.addedAppearance;
          if (ap == null ||
              !_appearanceInScope(ap) ||
              ap.personId == null ||
              ap.faceGroupId != null) {
            fromUnassigned = false;
            fromExcluded = false;
            assignedTagIds.clear();
            break;
          }
          final tagId = ap.tagId;
          if (tagId == null) {
            fromUnassigned = false;
            fromExcluded = false;
            assignedTagIds.clear();
            break;
          }
          assignedTagIds.add(tagId);
          if (r.removedExclusionId == null) fromExcluded = false;
          if (r.removedAppearanceId == null) fromUnassigned = false;
        }
        if (assignedTagIds.length >= 2 && fromUnassigned && !fromExcluded) {
          undoTagIds = List<String>.of(assignedTagIds);
          undoTray = FaceCropTray.unassigned;
          undoKind = FaceCropSelectKind.appearance;
          redoTagIds = List<String>.of(assignedTagIds);
          redoTray = FaceCropTray.assigned;
          redoKind = FaceCropSelectKind.appearance;
        } else if (assignedTagIds.length >= 2 && fromExcluded) {
          undoTagIds = List<String>.of(assignedTagIds);
          undoTray = FaceCropTray.excluded;
          undoKind = FaceCropSelectKind.exclusion;
          redoTagIds = List<String>.of(assignedTagIds);
          redoTray = FaceCropTray.assigned;
          redoKind = FaceCropSelectKind.appearance;
        }
      }
      _faceTapTracker.clear();

      // Focused person emptied → land on another in-folder person, or true
      // New Person… empty mode (never overview + New Person… hint).
      final pid = _personId;
      if (pid != null &&
          !assigned.any((a) => a.personId == pid)) {
        final next = _firstPersonIdInFolder(_persons, assigned);
        _renaming = false;
        _renameController.clear();
        _assignedController?.dispose();
        _assignedController = null;
        if (next != null) {
          _personId = next;
          _assignAsNewPerson = false;
          loadPersonId = next;
        } else {
          _personId = null;
          _assignAsNewPerson =
              unassigned.isNotEmpty || excluded.isNotEmpty;
          clearFacesPerson = true;
        }
      }
    });
    final nextId = loadPersonId;
    if (nextId != null) {
      if (!_applyingCollectionFacesUi) {
        ref
            .read(collectionsControllerProvider)
            .updateFacesLook(personId: nextId);
      }
      final controller = _controllerFor(nextId);
      unawaited(() async {
        await controller.load();
        if (!mounted) return;
        setState(() {
          _renameController.text = controller.detail?.name ?? '';
        });
        _scrollToCluster(nextId);
      }());
    } else if (clearFacesPerson && !_applyingCollectionFacesUi) {
      ref
          .read(collectionsControllerProvider)
          .updateFacesLook(clearPersonId: true);
    }

    // Prefer pre-drop bystander / source selection for undo when present.
    final prior = priorSelection;
    if (prior != null && prior.tagIds.isNotEmpty) {
      undoTagIds = List<String>.of(prior.tagIds);
      undoTray = prior.tray;
      undoKind = prior.kind;
    }
    if (undoTray == null || undoKind == null) {
      if (redoTagIds.isEmpty) return null;
      // Redo-only (no undo selection) — still record so redo can reselect.
      return _FaceDropSelectionRestore(
        undoTagIds: const [],
        undoTray: redoTray ?? FaceCropTray.unassigned,
        undoKind: redoKind ?? FaceCropSelectKind.appearance,
        redoTagIds: redoTagIds,
        redoTray: redoTray,
        redoKind: redoKind,
      );
    }
    if (undoTagIds.isEmpty && redoTagIds.isEmpty) return null;
    final uTray = undoTray;
    final uKind = undoKind;
    if (uTray == null || uKind == null) return null;
    return _FaceDropSelectionRestore(
      undoTagIds: undoTagIds,
      undoTray: uTray,
      undoKind: uKind,
      redoTagIds: redoTagIds,
      redoTray: redoTray,
      redoKind: redoKind,
    );
  }

  /// Sync trays from the API without blanking the page (no [listItems]).
  Future<void> _refreshTraysQuietly() async {
    _traySyncEpoch++;
    final epoch = _traySyncEpoch;
    try {
      final personsRepo = ref.read(personsRepositoryProvider);
      final results = await Future.wait<Object>([
        personsRepo.listPersons(),
        personsRepo.listAssignedAppearances(limit: _trayPageLimit),
        personsRepo.listUnassignedAppearances(limit: _trayPageLimit),
        personsRepo.listAccountWhoExclusions(limit: _trayPageLimit),
      ]);
      if (!mounted || epoch != _traySyncEpoch) return;

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
      final canCreateNew = unassigned.isNotEmpty || excluded.isNotEmpty;
      final resolved = _resolvedAssignedFocus(
        personId: pid,
        assignAsNew: _assignAsNewPerson,
        persons: persons,
        assignedOverview: assignedOverview,
        canCreateNew: canCreateNew,
      );
      if (resolved.personId != pid && resolved.personId != null) {
        _assignedController?.dispose();
        _assignedController = null;
        _renameController.clear();
      }
      pid = resolved.personId;
      final assignAsNew = resolved.assignAsNew;
      if (pid != null &&
          (_assignedController == null || _assignedController!.personId != pid)) {
        unawaited(_controllerFor(pid).load());
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
      _pruneOrRemapLooseSelection();
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

    final priorSelection = _snapshotSelectionByTagIds();
    setState(() => _busy = true);
    var failed = 0;
    Object? lastError;
    final applied = <_FaceMoveResult>[];
    final undoSteps = <_FaceDropUndoStep>[];
    try {
      if (target == FaceCropTray.unassigned) {
        // Same-person ≥2 leaving Assigned → one GroupFM. Solos / already-loose
        // unlink per face. Exclusion undos still go through the per-item path.
        final appearanceItems = [
          for (final d in toApply)
            if (d.isAppearance && d.appearanceId != null) d,
        ];
        final otherItems = [
          for (final d in toApply)
            if (!(d.isAppearance && d.appearanceId != null)) d,
        ];
        if (appearanceItems.isNotEmpty) {
          final partitioned =
              _partitionLeaveAssignedAppearances(appearanceItems);
          final persons = ref.read(personsRepositoryProvider);
          for (final batch in partitioned.samePersonBatches) {
            try {
              final ids = [for (final d in batch) d.appearanceId!];
              final personId = batch.first.personId!;
              final updated = await persons.unassignAppearances(ids);
              undoSteps.add(
                _FaceDropUndoStep(
                  undo: () async {
                    for (final id in ids) {
                      await persons.reassignAppearance(id, personId: personId);
                    }
                  },
                  redo: () => persons.unassignAppearances(ids),
                ),
              );
              for (final u in updated) {
                applied.add(_FaceMoveResult(
                  removedAppearanceId: u.id,
                  addedAppearance: u,
                ));
              }
            } catch (e) {
              failed += batch.length;
              lastError = e;
            }
          }
          for (final data in partitioned.perFace) {
            try {
              final id = data.appearanceId!;
              if (data.personId != null) {
                final personId = data.personId!;
                final updated = await persons.unlinkAppearance(id);
                undoSteps.add(
                  _FaceDropUndoStep(
                    undo: () =>
                        persons.reassignAppearance(id, personId: personId),
                    redo: () => persons.unlinkAppearance(id),
                  ),
                );
                applied.add(_FaceMoveResult(
                  removedAppearanceId: id,
                  addedAppearance: updated,
                ));
              } else {
                applied.add(
                  await _applyOneDrop(
                    target,
                    data,
                    undoSteps: undoSteps,
                  ),
                );
              }
            } catch (e) {
              failed++;
              lastError = e;
            }
          }
        }
        for (final data in otherItems) {
          try {
            applied.add(
              await _applyOneDrop(target, data, undoSteps: undoSteps),
            );
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

              final assignNameUsed = createName;
              final assignPersonIdUsed = personId;
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
              // Mutable: reminted across undo/redo (assignFaceGroup consumes FG).
              final liveAppearanceIds = <String>[];
              final memberTagIds = <String>[];

              // Members that were already unassigned before this drop.
              for (final member in unassignedMembers) {
                final updated = byId[member.id];
                if (updated != null) {
                  liveAppearanceIds.add(updated.id);
                  final tagId = updated.tagId ?? member.tagId;
                  if (tagId != null) memberTagIds.add(tagId);
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
                  liveAppearanceIds.add(updated.id);
                  if (tagId != null) memberTagIds.add(tagId);
                  applied.add(_FaceMoveResult(
                    removedAppearanceId: updated.id,
                    addedAppearance: updated,
                  ));
                }
              }

              // Origin exclusions (empty for Unassigned-only FaceGroup).
              final liveExclusions = [
                for (final e in excludedMembers)
                  (
                    itemId: e.itemId,
                    exclusionId: e.id,
                    tagId: e.createdFromTagId,
                  ),
              ];
              // assignFaceGroup consumed entry.key; undo remints via unassign.
              String? liveFaceGroupId;
              undoSteps.add(
                _FaceDropUndoStep(
                  undo: () async {
                    if (liveAppearanceIds.isEmpty) {
                      throw StateError('No appearances to unassign');
                    }
                    final restored = liveAppearanceIds.length >= 2
                        ? await persons.unassignAppearances(
                            List<String>.of(liveAppearanceIds),
                          )
                        : [
                            await persons.unlinkAppearance(
                              liveAppearanceIds.single,
                            ),
                          ];
                    liveFaceGroupId = restored
                        .map((a) => a.faceGroupId)
                        .whereType<String>()
                        .firstOrNull;
                    liveAppearanceIds
                      ..clear()
                      ..addAll(restored.map((a) => a.id));

                    // Excluded-origin: move GroupFM members back to Excluded
                    // (createWhoExclusion copies faceGroupId from appearance).
                    for (var i = 0; i < liveExclusions.length; i++) {
                      final e = liveExclusions[i];
                      final tagId = e.tagId;
                      if (tagId == null) continue;
                      final created =
                          await items.createWhoExclusion(e.itemId, tagId);
                      liveExclusions[i] = (
                        itemId: e.itemId,
                        exclusionId: created.exclusion.id,
                        tagId: tagId,
                      );
                    }
                  },
                  redo: () async {
                    if (liveExclusions.isNotEmpty) {
                      for (final e in liveExclusions) {
                        await items.undoWhoExclusion(
                          e.itemId,
                          e.exclusionId,
                        );
                      }
                    }
                    // Prefer tag resolve — sibling undos/redos remint FaceGroups.
                    final fg = (memberTagIds.isNotEmpty
                            ? _faceGroupIdForTagIds(memberTagIds)
                            : null) ??
                        liveFaceGroupId;
                    if (fg == null) {
                      throw StateError('No FaceGroup to re-assign after undo');
                    }
                    final again = assignNameUsed != null
                        ? await persons.assignFaceGroup(
                            fg,
                            name: assignNameUsed,
                          )
                        : await persons.assignFaceGroup(
                            fg,
                            personId: assignPersonIdUsed!,
                          );
                    liveFaceGroupId = null;
                    liveAppearanceIds.clear();
                    for (final tagId in memberTagIds) {
                      for (final a in again.appearances) {
                        if (a.tagId == tagId) {
                          liveAppearanceIds.add(a.id);
                          break;
                        }
                      }
                    }
                    if (liveAppearanceIds.isEmpty) {
                      liveAppearanceIds.addAll(
                        again.appearances.map((a) => a.id),
                      );
                    }
                  },
                ),
              );
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
                undoSteps: undoSteps,
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
        // id). Unassigned → Excluded never calls unassignAppearances (would mint
        // GroupFM). Only Assigned same-person ≥2 mint GroupFM then exclude.
        final appearanceItems = [
          for (final d in toApply)
            if (d.isAppearance && d.appearanceId != null) d,
        ];
        final otherItems = [
          for (final d in toApply)
            if (!(d.isAppearance && d.appearanceId != null)) d,
        ];

        final grouped = <FaceCropDragData>[];
        final fromAssignedUngrouped = <FaceCropDragData>[];
        final alwaysPerFace = <FaceCropDragData>[];
        for (final d in appearanceItems) {
          if (d.faceGroupId != null) {
            grouped.add(d);
          } else if (d.source == FaceCropTray.assigned && d.personId != null) {
            fromAssignedUngrouped.add(d);
          } else {
            // Unassigned (or already-loose): per-face exclude — stay loose.
            alwaysPerFace.add(d);
          }
        }

        final partitioned =
            _partitionLeaveAssignedAppearances(fromAssignedUngrouped);
        final persons = ref.read(personsRepositoryProvider);
        final items = ref.read(itemsRepositoryProvider);
        for (final batch in partitioned.samePersonBatches) {
          try {
            final ids = [for (final d in batch) d.appearanceId!];
            final minted = await persons.unassignAppearances(ids);
            final byOldId = <String, PersonAppearance>{
              for (final a in minted) a.id: a,
            };
            for (final d in batch) {
              final mintedAp = byOldId[d.appearanceId];
              final tagId = mintedAp?.tagId ?? d.tagId;
              if (tagId == null) {
                throw StateError('Exclude requires a who tag id');
              }
              final created =
                  await items.createWhoExclusion(d.itemId, tagId);
              var liveExclusionId = created.exclusion.id;
              final itemId = d.itemId;
              final personId = d.personId!;
              undoSteps.add(
                _FaceDropUndoStep(
                  undo: () async {
                    await _undoWhoExclusionForTag(
                      itemId: itemId,
                      tagId: tagId,
                      fallbackExclusionId: liveExclusionId,
                    );
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
                      throw StateError(
                        'Could not find appearance after undo exclude',
                      );
                    }
                    await persons.reassignAppearance(match.id, personId: personId);
                  },
                  redo: () async {
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
                      final assignedPage =
                          await persons.listAssignedAppearances(
                        limit: _trayPageLimit,
                      );
                      for (final a in assignedPage.appearances) {
                        if (a.tagId == tagId) {
                          match = a;
                          break;
                        }
                      }
                    }
                    if (match == null) {
                      throw StateError(
                        'Could not find appearance after redo exclude',
                      );
                    }
                    if (match.personId != null) {
                      await persons.unlinkAppearance(match.id);
                    }
                    final again =
                        await items.createWhoExclusion(itemId, tagId);
                    liveExclusionId = again.exclusion.id;
                  },
                ),
              );
              applied.add(_FaceMoveResult(
                removedAppearanceId: d.appearanceId,
                addedExclusion: created.exclusion,
              ));
            }
          } catch (e) {
            failed += batch.length;
            lastError = e;
          }
        }

        for (final data in [
          ...grouped,
          ...partitioned.perFace,
          ...alwaysPerFace,
        ]) {
          try {
            applied.add(
              await _applyOneDrop(target, data, undoSteps: undoSteps),
            );
          } catch (e) {
            failed++;
            lastError = e;
          }
        }

        for (final data in otherItems) {
          try {
            applied.add(
              await _applyOneDrop(target, data, undoSteps: undoSteps),
            );
          } catch (e) {
            failed++;
            lastError = e;
          }
        }
      }

      if (applied.isNotEmpty) {
        final selectionRestore = _applyMoveResults(
          applied,
          priorSelection: priorSelection,
        );
        _markCollectionDirty();
        if (failed == 0) {
          _recordFaceDropUndo(
            undoSteps,
            target,
            selectionRestore: selectionRestore,
          );
        }
        // Drag often leaves primary focus on the app-wide SelectionArea;
        // reclaim tray focus so local Cmd+A (and tests) stay reliable.
        _trayFocusNode.requestFocus();
      } else {
        setState(() {
          _selectedIds.clear();
          _selectionTray = null;
          _selectionKind = null;
          _selectionAnchorId = null;
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
      _markCollectionDirty();
      await _selectPerson(null, recordUndo: false);
      await _reload();
    }
  }

  bool get _canGroupSelection {
    if (_busy || _selectedIds.length < 2) return false;
    if (_selectionTray == FaceCropTray.unassigned &&
        _selectionKind == FaceCropSelectKind.appearance) {
      final loose = _unassignedLooseFaces().map((a) => a.id).toSet();
      return _selectedIds.every(loose.contains);
    }
    if (_selectionTray == FaceCropTray.excluded &&
        _selectionKind == FaceCropSelectKind.exclusion) {
      final loose = _excludedLooseFaces().map((e) => e.id).toSet();
      return _selectedIds.every(loose.contains);
    }
    return false;
  }

  Future<void> _groupSelection() async {
    if (!_canGroupSelection) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: Key('face-crop-group-unavailable'),
          content: Text(
            'Select at least two loose faces in Unassigned or Excluded to Group',
          ),
        ),
      );
      return;
    }
    final persons = ref.read(personsRepositoryProvider);
    setState(() => _busy = true);
    try {
      if (_selectionTray == FaceCropTray.unassigned) {
        final ids = _selectedIds.toList();
        final tagIds = [
          for (final id in ids)
            for (final a in _unassigned)
              if (a.id == id && a.tagId != null) a.tagId!,
        ];
        final result = await persons.assembleAppearances(ids);
        _markCollectionDirty();
        await _reload();
        if (!mounted) return;
        setState(() {
          _selectedIds
            ..clear()
            ..addAll(result.appearances.map((a) => a.id));
          _selectionTray = FaceCropTray.unassigned;
          _selectionKind = FaceCropSelectKind.appearance;
          _selectionAnchorId = result.appearances.first.id;
        });
        // assemble remints FaceGroup ids on redo; resolve by tagId on hops.
        var liveFaceGroupId = result.faceGroupId;
        var liveMemberIds = [for (final a in result.appearances) a.id];
        _undoStack.push(
          CallbackUndoableAction(
            label: 'Group faces',
            onUndo: () async {
              final fg =
                  _faceGroupIdForTagIds(tagIds) ?? liveFaceGroupId;
              final ungrouped = await persons.ungroupFaceGroup(fg);
              liveMemberIds = [for (final a in ungrouped.appearances) a.id];
              _markCollectionDirty();
              await _reload();
            },
            onRedo: () async {
              final resolved = _unassignedIdsForTagIds(tagIds);
              final memberIds =
                  tagIds.isNotEmpty && resolved.length == tagIds.length
                      ? resolved
                      : liveMemberIds;
              final again = await persons.assembleAppearances(memberIds);
              liveFaceGroupId = again.faceGroupId;
              liveMemberIds = [for (final a in again.appearances) a.id];
              _markCollectionDirty();
              await _reload();
            },
          ),
        );
      } else if (_selectionTray == FaceCropTray.excluded) {
        final ids = _selectedIds.toList();
        final tagIds = [
          for (final id in ids)
            for (final e in _excluded)
              if (e.id == id && e.createdFromTagId != null) e.createdFromTagId!,
        ];
        final result = await persons.assembleExclusions(ids);
        _markCollectionDirty();
        await _reload();
        if (!mounted) return;
        setState(() {
          _selectedIds
            ..clear()
            ..addAll(result.exclusions.map((e) => e.id));
          _selectionTray = FaceCropTray.excluded;
          _selectionKind = FaceCropSelectKind.exclusion;
          _selectionAnchorId = result.exclusions.first.id;
        });
        var liveFaceGroupId = result.faceGroupId;
        var liveMemberIds = [for (final e in result.exclusions) e.id];
        _undoStack.push(
          CallbackUndoableAction(
            label: 'Group exclusions',
            onUndo: () async {
              final fg =
                  _faceGroupIdForTagIds(tagIds) ?? liveFaceGroupId;
              final ungrouped = await persons.ungroupFaceGroup(fg);
              liveMemberIds = [for (final e in ungrouped.exclusions) e.id];
              _markCollectionDirty();
              await _reload();
            },
            onRedo: () async {
              final resolved = _exclusionIdsForTagIds(tagIds);
              final memberIds =
                  tagIds.isNotEmpty && resolved.length == tagIds.length
                      ? resolved
                      : liveMemberIds;
              final again = await persons.assembleExclusions(memberIds);
              liveFaceGroupId = again.faceGroupId;
              liveMemberIds = [for (final e in again.exclusions) e.id];
              _markCollectionDirty();
              await _reload();
            },
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('face-crop-trays-error'),
          content: Text('Group failed: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _ungroupFm(String faceGroupId) async {
    final persons = ref.read(personsRepositoryProvider);
    setState(() => _busy = true);
    try {
      final result = await persons.ungroupFaceGroup(faceGroupId);
      final appearanceIds = [for (final a in result.appearances) a.id];
      final exclusionIds = [for (final e in result.exclusions) e.id];
      final appearanceTagIds = [
        for (final a in result.appearances)
          if (a.tagId != null) a.tagId!,
      ];
      final exclusionTagIds = [
        for (final e in result.exclusions)
          if (e.createdFromTagId != null) e.createdFromTagId!,
      ];
      _markCollectionDirty();
      await _reload();
      if (!mounted) return;
      setState(() {
        if (appearanceIds.isNotEmpty) {
          _selectedIds
            ..clear()
            ..addAll(appearanceIds);
          _selectionTray = FaceCropTray.unassigned;
          _selectionKind = FaceCropSelectKind.appearance;
          _selectionAnchorId = appearanceIds.first;
        } else if (exclusionIds.isNotEmpty) {
          _selectedIds
            ..clear()
            ..addAll(exclusionIds);
          _selectionTray = FaceCropTray.excluded;
          _selectionKind = FaceCropSelectKind.exclusion;
          _selectionAnchorId = exclusionIds.first;
        } else {
          _selectedIds.clear();
          _selectionTray = null;
          _selectionKind = null;
          _selectionAnchorId = null;
        }
      });
      // Reverse of Group: re-assemble members (≥2). Redo ungroups the new FM.
      // Member / FaceGroup ids remint — resolve by tagId + liveFaceGroupId.
      final memberCount = appearanceIds.length + exclusionIds.length;
      if (memberCount >= 2) {
        var liveAppearanceIds = List<String>.from(appearanceIds);
        var liveExclusionIds = List<String>.from(exclusionIds);
        String? redoFaceGroupId;
        _undoStack.push(
          CallbackUndoableAction(
            label: 'Ungroup',
            onUndo: () async {
              if (exclusionTagIds.length >= 2 || liveExclusionIds.length >= 2) {
                final resolved = _exclusionIdsForTagIds(exclusionTagIds);
                final ids = exclusionTagIds.isNotEmpty &&
                        resolved.length == exclusionTagIds.length
                    ? resolved
                    : liveExclusionIds;
                final assembled = await persons.assembleExclusions(ids);
                redoFaceGroupId = assembled.faceGroupId;
                liveExclusionIds = [
                  for (final e in assembled.exclusions) e.id,
                ];
                _markCollectionDirty();
                await _reload();
                if (!mounted) return;
                setState(() {
                  _selectedIds
                    ..clear()
                    ..addAll(assembled.exclusions.map((e) => e.id));
                  _selectionTray = FaceCropTray.excluded;
                  _selectionKind = FaceCropSelectKind.exclusion;
                  _selectionAnchorId = assembled.exclusions.first.id;
                });
              } else {
                final resolved = _unassignedIdsForTagIds(appearanceTagIds);
                final ids = appearanceTagIds.isNotEmpty &&
                        resolved.length == appearanceTagIds.length
                    ? resolved
                    : liveAppearanceIds;
                final assembled = await persons.assembleAppearances(ids);
                redoFaceGroupId = assembled.faceGroupId;
                liveAppearanceIds = [
                  for (final a in assembled.appearances) a.id,
                ];
                _markCollectionDirty();
                await _reload();
                if (!mounted) return;
                setState(() {
                  _selectedIds
                    ..clear()
                    ..addAll(assembled.appearances.map((a) => a.id));
                  _selectionTray = FaceCropTray.unassigned;
                  _selectionKind = FaceCropSelectKind.appearance;
                  _selectionAnchorId = assembled.appearances.first.id;
                });
              }
            },
            onRedo: () async {
              final tags = exclusionTagIds.length >= 2
                  ? exclusionTagIds
                  : appearanceTagIds;
              // Prefer tag resolve — Group redo remints FaceGroup ids.
              final fg = _faceGroupIdForTagIds(tags) ?? redoFaceGroupId;
              if (fg == null) {
                throw StateError('No FaceGroup to ungroup after undo');
              }
              final again = await persons.ungroupFaceGroup(fg);
              liveAppearanceIds = [for (final a in again.appearances) a.id];
              liveExclusionIds = [for (final e in again.exclusions) e.id];
              redoFaceGroupId = null;
              _markCollectionDirty();
              await _reload();
              if (!mounted) return;
              setState(() {
                if (again.appearances.isNotEmpty) {
                  _selectedIds
                    ..clear()
                    ..addAll(again.appearances.map((a) => a.id));
                  _selectionTray = FaceCropTray.unassigned;
                  _selectionKind = FaceCropSelectKind.appearance;
                  _selectionAnchorId = again.appearances.first.id;
                } else if (again.exclusions.isNotEmpty) {
                  _selectedIds
                    ..clear()
                    ..addAll(again.exclusions.map((e) => e.id));
                  _selectionTray = FaceCropTray.excluded;
                  _selectionKind = FaceCropSelectKind.exclusion;
                  _selectionAnchorId = again.exclusions.first.id;
                }
              });
            },
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('face-crop-trays-error'),
          content: Text('Ungroup failed: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
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

    ref.listen(collectionsControllerProvider, (previous, next) {
      unawaited(_refilterFromCollection());
      if (next.sessionReady && next.uiEpoch != _appliedCollectionUiEpoch) {
        unawaited(_applyCollectionFacesUi(next));
      }
    });

    // Claim SelectAllTextIntent so app-wide SelectionArea does not steal Cmd+A
    // onto shell text (e.g. folder activity banner). Loose faces only.
    // Cmd/Ctrl+Z is hosted by ActiveUndoShortcuts above SelectableScope
    // (via ActiveUndoHost) so it still works when SelectionArea holds focus.
    final facesActive =
        ref.watch(activeTopLevelTabProvider) == TopLevelTab.faces;
    return ActiveUndoHost(
      controller: _undoStack,
      active: facesActive,
      child: Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true):
            const SelectAllTextIntent(SelectionChangedCause.keyboard),
        const SingleActivator(LogicalKeyboardKey.keyA, control: true):
            const SelectAllTextIntent(SelectionChangedCause.keyboard),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          SelectAllTextIntent: CallbackAction<SelectAllTextIntent>(
            onInvoke: (_) {
              _selectAllInActiveTray();
              return null;
            },
          ),
        },
        child: SelectionContainer.disabled(
          child: Focus(
            focusNode: _trayFocusNode,
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              if (event.logicalKey == LogicalKeyboardKey.escape) {
                _clearSelection();
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.keyA &&
                  (HardwareKeyboard.instance.isMetaPressed ||
                      HardwareKeyboard.instance.isControlPressed)) {
                _selectAllInActiveTray();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Faces'),
            const SizedBox(width: 8),
            UndoDepthBadge(controller: _undoStack),
          ],
        ),
        actions: [
          if (!_loading && _error == null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Text(
                  ref.watch(collectionsControllerProvider).chromeLabel,
                  key: const Key('face-crop-collection-label'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
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
                  ? Center(
                      child: Text(
                        _allLeafFolders.isEmpty
                            ? 'No local folders yet.\n'
                                'Add photos from a folder, then open Faces.'
                            : 'This collection has no folders that match '
                                'items you have added.\n'
                                'Add folders on the Folders page.',
                        key: const Key('face-crop-trays-no-folders'),
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
    ),
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
    // faces. Never show all-persons overview without a selection.
    final clusters = _assignAsNewPerson || selectedId == null
        ? const <({Person person, List<PersonAppearance> faces})>[]
        : [
            for (final c in allClusters)
              if (c.person.id == selectedId) c,
          ];
    final solos = _assignAsNewPerson || selectedId == null
        ? const <PersonAppearance>[]
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
            hint: null,
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
                        onSelectAppearance: (a, {required mode}) =>
                            _selectAppearance(
                          a,
                          FaceCropTray.assigned,
                          mode: mode,
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
                      onSelect: (a, {required mode}) => _selectAppearance(
                        a,
                        FaceCropTray.assigned,
                        mode: mode,
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
    if (faces == 0) return 'No faces';
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
                onUngroup: clusters[i].kind == FaceGroupKind.fm
                    ? () => _ungroupFm(clusters[i].faceGroupId)
                    : null,
                onSelectAppearance: (a, {required mode}) =>
                    _selectAppearance(
                  a,
                  FaceCropTray.unassigned,
                  mode: mode,
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
              onSelect: (a, {required mode}) => _selectAppearance(
                a,
                FaceCropTray.unassigned,
                mode: mode,
              ),
              onOpenItem: _openItem,
              onSetName: _setNameFromAppearance,
              onGroupSelection: _canGroupSelection &&
                      _selectionTray == FaceCropTray.unassigned
                  ? _groupSelection
                  : null,
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
                onUngroup: clusters[i].kind == FaceGroupKind.fm
                    ? () => _ungroupFm(clusters[i].faceGroupId)
                    : null,
                onSelectExclusion: (e, {required mode}) =>
                    _selectExclusion(e, mode: mode),
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
              onSelect: (e, {required mode}) =>
                  _selectExclusion(e, mode: mode),
              onOpenItem: _openItem,
              onGroupSelection: _canGroupSelection &&
                      _selectionTray == FaceCropTray.excluded
                  ? _groupSelection
                  : null,
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
  final void Function(PersonAppearance appearance, {required FaceCropSelectMode mode})
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
    this.onUngroup,
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
  final VoidCallback? onUngroup;
  final void Function(PersonAppearance appearance, {required FaceCropSelectMode mode})
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '$_label · ${faces.length} '
                '${faces.length == 1 ? 'face' : 'faces'}',
                style: Theme.of(context).textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  if (onUngroup != null)
                    OutlinedButton(
                      key: Key('face-crop-ungroup-$faceGroupId'),
                      onPressed: busy ? null : onUngroup,
                      style: _faceActionButtonStyle(scheme),
                      child: const Text('Ungroup'),
                    ),
                  OutlinedButton(
                    key: Key('face-crop-facegroup-set-name-$faceGroupId'),
                    onPressed: busy ? null : onSetName,
                    style: _faceActionButtonStyle(scheme),
                    child: const Text('Set name'),
                  ),
                ],
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
    this.onUngroup,
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
  final VoidCallback? onUngroup;
  final void Function(WhoExclusion exclusion, {required FaceCropSelectMode mode})
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '$_label · ${faces.length} '
                '${faces.length == 1 ? 'face' : 'faces'}',
                style: Theme.of(context).textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
              if (onUngroup != null) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton(
                    key: Key('face-crop-ungroup-$faceGroupId'),
                    onPressed: busy ? null : onUngroup,
                    style: _faceActionButtonStyle(scheme),
                    child: const Text('Ungroup'),
                  ),
                ),
              ],
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

/// Compact outlined style for Faces actions (Group / Ungroup / Set name).
ButtonStyle _faceActionButtonStyle(ColorScheme scheme) {
  return OutlinedButton.styleFrom(
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    minimumSize: Size.zero,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    visualDensity: VisualDensity.compact,
    foregroundColor: scheme.primary,
    backgroundColor: scheme.surface.withValues(alpha: 0.95),
    side: BorderSide(color: scheme.outlineVariant),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
  );
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
    this.onGroupSelection,
    this.shrinkWrap = false,
  });

  final List<PersonAppearance> appearances;
  final FaceCropTray source;
  final bool busy;
  final Set<String> selectedIds;
  final FaceCropTapTracker tapTracker;
  final void Function(PersonAppearance appearance, {required FaceCropSelectMode mode})
      onSelect;
  final void Function(String itemId) onOpenItem;
  /// When set (Unassigned tray), shows Set name on each loose thumb (single select).
  final void Function(String appearanceId)? onSetName;
  /// When set and ≥2 loose faces selected, shows Group on each selected thumb.
  final VoidCallback? onGroupSelection;
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
    onSelect(a, mode: faceCropSelectMode());
  }

  Widget? _overlayFor(
    PersonAppearance a,
    ColorScheme scheme,
    String? firstSelectedId,
  ) {
    final selected = selectedIds.contains(a.id);
    final multi = selectedIds.length >= 2;
    if (multi) {
      final groupHandler = onGroupSelection;
      if (!selected ||
          groupHandler == null ||
          a.id != firstSelectedId) {
        return null;
      }
      return Positioned(
        top: 0,
        right: 0,
        child: OutlinedButton(
          key: const Key('face-crop-group-selection'),
          onPressed: busy ? null : groupHandler,
          style: _faceActionButtonStyle(scheme),
          child: const Text('Group'),
        ),
      );
    }
    final setNameHandler = onSetName;
    if (setNameHandler == null) return null;
    return Positioned(
      top: 0,
      right: 0,
      child: OutlinedButton(
        key: Key('face-crop-set-name-${a.id}'),
        onPressed: busy ? null : () => setNameHandler(a.id),
        style: _faceActionButtonStyle(scheme),
        child: const Text('Set name'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (appearances.isEmpty) {
      return const Center(child: Text('No faces'));
    }
    final scheme = Theme.of(context).colorScheme;
    String? firstSelectedId;
    for (final a in appearances) {
      if (selectedIds.contains(a.id)) {
        firstSelectedId = a.id;
        break;
      }
    }
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
        final overlay = _overlayFor(a, scheme, firstSelectedId);
        if (!canDrag) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              interactive,
              ?overlay,
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
            ?overlay,
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
    this.onGroupSelection,
    this.shrinkWrap = false,
  });

  final List<WhoExclusion> exclusions;
  final bool busy;
  final Set<String> selectedIds;
  final FaceCropTapTracker tapTracker;
  final void Function(WhoExclusion exclusion, {required FaceCropSelectMode mode}) onSelect;
  final void Function(String itemId) onOpenItem;
  /// When set and ≥2 loose exclusions selected, shows Group on each selected thumb.
  final VoidCallback? onGroupSelection;
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
    onSelect(e, mode: faceCropSelectMode());
  }

  @override
  Widget build(BuildContext context) {
    if (exclusions.isEmpty) {
      return const Center(child: Text('No excluded faces'));
    }
    final scheme = Theme.of(context).colorScheme;
    String? firstSelectedId;
    for (final e in exclusions) {
      if (selectedIds.contains(e.id)) {
        firstSelectedId = e.id;
        break;
      }
    }
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
        final faceBody = DecoratedBox(
          key: selected ? Key('face-crop-selected-${e.id}') : null,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Center(child: thumb),
        );
        final tile = Material(
          key: Key('face-crop-exclusion-${e.id}'),
          color: Colors.transparent,
          child: faceBody,
        );
        final interactive = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _onTap(e),
          child: tile,
        );
        final groupHandler = onGroupSelection;
        final groupOverlay = selectedIds.length >= 2 &&
                selected &&
                groupHandler != null &&
                e.id == firstSelectedId
            ? Positioned(
                top: 0,
                right: 0,
                child: OutlinedButton(
                  key: const Key('face-crop-group-selection'),
                  onPressed: busy ? null : groupHandler,
                  style: _faceActionButtonStyle(scheme),
                  child: const Text('Group'),
                ),
              )
            : null;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Draggable<FaceCropDragPayload>(
              data: _payloadFor(e),
              feedback: Material(
                elevation: 4,
                child: Opacity(opacity: 0.9, child: thumb),
              ),
              childWhenDragging: Opacity(opacity: 0.35, child: interactive),
              child: interactive,
            ),
            ?groupOverlay,
          ],
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
