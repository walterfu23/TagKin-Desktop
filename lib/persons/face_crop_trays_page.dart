import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/item_detail_page.dart';
import 'package:tagkin_desktop/persons/face_crop_drag.dart';
import 'package:tagkin_desktop/persons/face_crop_folder_scope.dart';
import 'package:tagkin_desktop/persons/person_detail_controller.dart';
import 'package:tagkin_desktop/persons/who_exclusion_crop_thumb.dart';
import 'package:tagkin_desktop/persons/who_face_crop_thumb.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

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
/// double-click opens the item. Drag a selection between trays. **Assigned** is
/// only faces linked to a **named** person (boxes when ≥2 faces). **Unassigned**
/// holds null-personId faces and **Unnamed** auto-linked clusters — **Set name**
/// moves a cluster to Assigned. **New person** on a loose Unassigned face
/// creates an Unnamed person (stays in Unassigned until named).
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

  Set<String> _selectionFor(FaceCropTray tray, FaceCropSelectKind kind) {
    if (_selectionTray == tray && _selectionKind == kind) {
      return Set<String>.from(_selectedIds);
    }
    return const {};
  }

  GlobalKey _clusterKey(String personId) =>
      _clusterKeys.putIfAbsent(personId, GlobalKey.new);

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

  static bool personHasName(Person? p) {
    final name = p?.name?.trim();
    return name != null && name.isNotEmpty;
  }

  Person? _lookupPerson(String? id) {
    if (id == null) return null;
    for (final p in _persons) {
      if (p.id == id) return p;
    }
    return null;
  }

  Person _personForId(String id) {
    return _lookupPerson(id) ??
        Person(id: id, name: null, createdAt: '');
  }

  /// Group in-folder appearances by personId (dropdown order).
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

  /// Named person, ≥2 faces — Assigned cluster boxes.
  List<({Person person, List<PersonAppearance> faces})> _namedMultiClusters() {
    return [
      for (final c in _clustersFrom(_linkedInFolder))
        if (personHasName(c.person) && c.faces.length >= 2) c,
    ];
  }

  /// Named person, exactly one face — Assigned loose thumbs.
  List<PersonAppearance> _namedSoloFaces() {
    return [
      for (final c in _clustersFrom(_linkedInFolder))
        if (personHasName(c.person) && c.faces.length == 1) c.faces.first,
    ];
  }

  /// Unnamed person, ≥2 faces — Unassigned cluster boxes.
  List<({Person person, List<PersonAppearance> faces})> _unnamedMultiClusters() {
    return [
      for (final c in _clustersFrom(_linkedInFolder))
        if (!personHasName(c.person) && c.faces.length >= 2) c,
    ];
  }

  /// Null personId + unnamed solos — Unassigned loose thumbs.
  List<PersonAppearance> _unassignedLooseFaces() {
    final loose = List<PersonAppearance>.of(_scopedAppearances(_unassigned));
    for (final c in _clustersFrom(_linkedInFolder)) {
      if (!personHasName(c.person) && c.faces.length == 1) {
        loose.add(c.faces.first);
      }
    }
    return loose;
  }

  int get _unassignedTrayFaceCount =>
      _unnamedMultiClusters().fold<int>(0, (n, c) => n + c.faces.length) +
      _unassignedLooseFaces().length;

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
      _reload();
    });
  }

  @override
  void dispose() {
    _assignedController?.dispose();
    _renameController.dispose();
    _clusterScrollController.dispose();
    super.dispose();
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
      final items = await itemsRepo.listItems();
      final folders = distinctLeafFolders(items);
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

      // Exclude / unlink can prune the selected person server-side; clear the
      // dropdown value before rebuild or DropdownButton asserts.
      // Folder switch: land on the first in-folder person (or overview if none).
      var pid = _personId;
      if (_autoSelectFirstInFolder) {
        _autoSelectFirstInFolder = false;
        pid = _firstPersonIdInFolder(persons, assignedOverview);
        if (pid != _personId) {
          _assignedController?.dispose();
          _assignedController = null;
          _renameController.clear();
        }
        if (pid != null) {
          await _controllerFor(pid).load();
          _renameController.text = _assignedController?.detail?.name ?? '';
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
      }

      if (!mounted) return;
      setState(() {
        _personId = pid;
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

  /// Named person ids that have at least one face in the selected folder.
  Set<String> _personIdsInCurrentFolder() {
    final ids = <String>{};
    for (final a in _linkedInFolder) {
      final pid = a.personId;
      if (pid != null && personHasName(_lookupPerson(pid))) ids.add(pid);
    }
    return ids;
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

  /// Sort: in-folder first, then by name/id (same order as the Person dropdown).
  static List<Person> _sortPersonsForDropdown(
    List<Person> persons,
    Set<String> inFolder,
  ) {
    final list = List<Person>.from(persons);
    list.sort((a, b) {
      final ra = inFolder.contains(a.id) ? 0 : 1;
      final rb = inFolder.contains(b.id) ? 0 : 1;
      if (ra != rb) return ra.compareTo(rb);
      final la = (a.name ?? a.id).toLowerCase();
      final lb = (b.name ?? b.id).toLowerCase();
      return la.compareTo(lb);
    });
    return list;
  }

  /// First **named** person (dropdown order) with faces in [assignedInFolder].
  static String? _firstPersonIdInFolder(
    List<Person> persons,
    List<PersonAppearance> assignedInFolder,
  ) {
    final inFolder = _personIdsFromAppearances(assignedInFolder);
    if (inFolder.isEmpty) return null;
    final named = persons.where(personHasName).toList();
    for (final p in _sortPersonsForDropdown(named, inFolder)) {
      if (inFolder.contains(p.id)) return p.id;
    }
    return null;
  }

  /// Named library persons; those in the current folder first.
  List<Person> _personsForDropdown(Set<String> inFolder) {
    return _sortPersonsForDropdown(
      _persons.where(personHasName).toList(),
      inFolder,
    );
  }

  /// Display name for dropdown / subtitle — never a bare UUID for unnamed.
  static String personDisplayName(Person p, {required List<Person> all}) {
    final name = p.name?.trim();
    if (name != null && name.isNotEmpty) return name;
    final unnamedCount = all.where((x) {
      final n = x.name?.trim();
      return n == null || n.isEmpty;
    }).length;
    if (unnamedCount <= 1) return 'Unnamed';
    final short = p.id.length >= 8 ? p.id.substring(0, 8) : p.id;
    return 'Unnamed · $short';
  }

  static String _personDropdownLabel(
    Person p, {
    required bool inFolder,
    required List<Person> all,
  }) {
    final base = personDisplayName(p, all: all);
    return inFolder ? '$base · in folder' : base;
  }

  Future<void> _selectPerson(String? id) async {
    if (id == null) {
      setState(() {
        _personId = null;
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
      _renaming = false;
      // Clear immediately so an unnamed person never shows the prior name
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

  Future<void> _createPersonFromAppearance(String appearanceId) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final persons = ref.read(personsRepositoryProvider);
      final updated = await persons.reassignAppearance(appearanceId, null);
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
          content: Text('New person failed: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<_FaceMoveResult> _applyOneDrop(
    FaceCropTray target,
    FaceCropDragData data,
  ) async {
    final persons = ref.read(personsRepositoryProvider);
    final items = ref.read(itemsRepositoryProvider);

    switch (target) {
      case FaceCropTray.unassigned:
        if (data.isAppearance && data.appearanceId != null) {
          final updated = await persons.unlinkAppearance(data.appearanceId!);
          return _FaceMoveResult(
            removedAppearanceId: data.appearanceId,
            addedAppearance: updated,
          );
        }
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
        final pid = _personId;
        if (pid == null) {
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
          final updated = await persons.reassignAppearance(match.id, pid);
          return _FaceMoveResult(
            removedExclusionId: data.exclusionId,
            removedAppearanceId: match.id,
            addedAppearance: updated,
          );
        }
        if (data.appearanceId != null) {
          final updated =
              await persons.reassignAppearance(data.appearanceId!, pid);
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

      setState(() {
        _personId = pid;
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
      for (final data in toApply) {
        try {
          applied.add(await _applyOneDrop(target, data));
        } catch (e) {
          failed++;
          lastError = e;
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
                      Expanded(child: _buildUnassignedColumn(controller)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _TrayColumn(
                          key: const Key('face-crop-tray-excluded'),
                          title: 'Excluded',
                          tagline: 'faces should not be assigned to a person',
                          subtitle: '${_excluded.length} faces',
                          onAccept: (d) => _onDrop(FaceCropTray.excluded, d),
                          child: _ExclusionGrid(
                            exclusions: _excluded,
                            busy: _busy,
                            selectedIds: _selectionFor(
                              FaceCropTray.excluded,
                              FaceCropSelectKind.exclusion,
                            ),
                            tapTracker: _faceTapTracker,
                            onSelect: (e, {required toggle}) =>
                                _selectExclusion(e, toggle: toggle),
                            onOpenItem: _openItem,
                          ),
                        ),
                      ),
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
          _renameController.text = detail.name ?? '';
        });
      },
      onDoneRename: () async {
        await controller.rename(_renameController.text);
        if (mounted) {
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
    final focusedNamed =
        pid != null && personHasName(_lookupPerson(pid)) ? pid : null;
    final selectedId = focusedNamed != null &&
            _persons.any((p) => p.id == focusedNamed)
        ? focusedNamed
        : null;
    final inFolder = _personIdsInCurrentFolder();
    final dropdownPersons = _personsForDropdown(inFolder);
    final scheme = Theme.of(context).colorScheme;
    final clusters = _namedMultiClusters();
    final solos = _namedSoloFaces();
    final personSelect = DropdownButtonFormField<String>(
      key: const Key('face-crop-person-select'),
      // ignore: deprecated_member_use
      value: selectedId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Person',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      selectedItemBuilder: (context) {
        return [
          for (final p in dropdownPersons)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                _personDropdownLabel(
                  p,
                  inFolder: inFolder.contains(p.id),
                  all: dropdownPersons,
                ),
                overflow: TextOverflow.ellipsis,
                style: inFolder.contains(p.id)
                    ? TextStyle(
                        fontWeight: FontWeight.w600,
                        color: scheme.primary,
                      )
                    : null,
              ),
            ),
        ];
      },
      items: [
        for (final p in dropdownPersons)
          DropdownMenuItem(
            value: p.id,
            child: Text(
              _personDropdownLabel(
                p,
                inFolder: inFolder.contains(p.id),
                all: dropdownPersons,
              ),
              key: Key(
                inFolder.contains(p.id)
                    ? 'face-crop-person-option-in-folder-${p.id}'
                    : 'face-crop-person-option-${p.id}',
              ),
              overflow: TextOverflow.ellipsis,
              style: inFolder.contains(p.id)
                  ? TextStyle(
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    )
                  : TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
      ],
      onChanged: _busy
          ? null
          : (id) async {
              await _selectPerson(id);
            },
    );

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
            personSelect,
            if (chrome != null) ...[
              const SizedBox(height: 8),
              chrome,
            ],
          ],
        ),
        onAccept: (d) => _onDrop(FaceCropTray.assigned, d),
        child: empty
            ? Center(
                child: Text(
                  _unassignedTrayFaceCount == 0 && _excluded.isEmpty
                      ? 'No faces in this folder yet'
                      : 'No named people in this folder — '
                          'name a group in Unassigned or check Unassigned',
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
                        allPersons: _persons,
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
                        onFocusPerson: () =>
                            _selectPerson(clusters[i].person.id),
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
        subtitle: emptyAssignedSubtitle(clusters, solos),
      );
    }

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final detail = controller.detail;
        final String subtitle;
        if (clusters.isEmpty && solos.isEmpty) {
          subtitle = 'Select a person';
        } else if (controller.phase == PersonDetailPhase.loading &&
            selectedId != null) {
          subtitle = 'Loading…';
        } else if (detail != null &&
            selectedId == detail.id &&
            personHasName(
              Person(
                id: detail.id,
                name: detail.name,
                createdAt: detail.createdAt,
              ),
            )) {
          subtitle = personDisplayName(
            Person(
              id: detail.id,
              name: detail.name,
              createdAt: detail.createdAt,
            ),
            all: _persons,
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

  Widget _buildUnassignedColumn(PersonDetailController? controller) {
    final clusters = _unnamedMultiClusters();
    final loose = _unassignedLooseFaces();
    final pid = _personId;
    final focusedUnnamed =
        pid != null && !personHasName(_lookupPerson(pid)) ? pid : null;
    final chrome = focusedUnnamed != null
        ? _personChromeWidget(controller)
        : null;

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
          for (var i = 0; i < clusters.length; i++) ...[
            Padding(
              key: _clusterKey(clusters[i].person.id),
              padding: EdgeInsets.only(
                bottom: i == clusters.length - 1 && loose.isEmpty ? 0 : 10,
              ),
              child: _PersonClusterCard(
                person: clusters[i].person,
                faces: clusters[i].faces,
                allPersons: _persons,
                focused: clusters[i].person.id == focusedUnnamed,
                busy: _busy ||
                    (clusters[i].person.id == focusedUnnamed &&
                        (controller?.isBusy ?? false)),
                selectedIds: _selectionFor(
                  FaceCropTray.unassigned,
                  FaceCropSelectKind.appearance,
                ),
                tapTracker: _faceTapTracker,
                dragPayload: _clusterDragPayload(
                  clusters[i].faces,
                  FaceCropTray.unassigned,
                ),
                onSelectCluster: () => _selectCluster(
                  clusters[i].person,
                  clusters[i].faces,
                  FaceCropTray.unassigned,
                ),
                onFocusPerson: () => _selectPerson(clusters[i].person.id),
                onSelectAppearance: (a, {required toggle}) =>
                    _selectAppearance(
                  a,
                  FaceCropTray.unassigned,
                  toggle: toggle,
                ),
                onOpenItem: _openItem,
              ),
            ),
          ],
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
              onNewPerson: _createPersonFromAppearance,
            ),
        ],
      );
    }();

    return _TrayColumn(
      key: const Key('face-crop-tray-unassigned'),
      title: 'Unassigned',
      tagline: 'not yet named — includes Unnamed likeness groups',
      subtitle: '$_unassignedTrayFaceCount '
          '${_unassignedTrayFaceCount == 1 ? 'face' : 'faces'}',
      header: chrome == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [chrome],
            ),
      onAccept: (d) => _onDrop(FaceCropTray.unassigned, d),
      child: body,
    );
  }
}

class _PersonClusterCard extends StatelessWidget {
  const _PersonClusterCard({
    required this.person,
    required this.faces,
    required this.allPersons,
    required this.focused,
    required this.busy,
    required this.selectedIds,
    required this.tapTracker,
    required this.dragPayload,
    required this.onSelectCluster,
    required this.onFocusPerson,
    required this.onSelectAppearance,
    required this.onOpenItem,
  });

  final Person person;
  final List<PersonAppearance> faces;
  final List<Person> allPersons;
  final bool focused;
  final bool busy;
  final Set<String> selectedIds;
  final FaceCropTapTracker tapTracker;
  final FaceCropDragPayload dragPayload;
  final VoidCallback onSelectCluster;
  final VoidCallback onFocusPerson;
  final void Function(PersonAppearance appearance, {required bool toggle})
      onSelectAppearance;
  final void Function(String itemId) onOpenItem;

  bool get _isUnnamed {
    final name = person.name?.trim();
    return name == null || name.isEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = _FaceCropTraysPageState.personDisplayName(
      person,
      all: allPersons,
    );
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
              if (!focused && _isUnnamed)
                TextButton(
                  key: Key('face-crop-cluster-set-name-${person.id}'),
                  onPressed: busy ? null : onFocusPerson,
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

  bool get _isUnnamed =>
      detail.name == null || detail.name!.trim().isEmpty;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('face-crop-person-chrome'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: renaming || _isUnnamed
                  ? TextField(
                      key: const Key('face-crop-person-rename'),
                      controller: renameController,
                      enabled: !busy,
                      decoration: InputDecoration(
                        labelText: 'Name',
                        hintText: _isUnnamed ? 'Enter a name' : null,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => onDoneRename(),
                    )
                  : Text(
                      detail.name!,
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
            if (renaming || _isUnnamed)
              TextButton(
                key: const Key('face-crop-person-rename-done'),
                onPressed: busy ? null : onDoneRename,
                child: Text(_isUnnamed && !renaming ? 'Set name' : 'Done'),
              )
            else
              Tooltip(
                message: 'Change this person’s name',
                child: TextButton(
                  key: const Key('face-crop-person-rename-start'),
                  onPressed: busy ? null : onStartRename,
                  child: const Text('Rename'),
                ),
              ),
            if (renaming)
              TextButton(
                key: const Key('face-crop-person-rename-cancel'),
                onPressed: busy ? null : onCancelRename,
                child: const Text('Cancel'),
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
    this.onNewPerson,
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
  /// When set (Unassigned tray), shows New person on each thumb.
  final void Function(String appearanceId)? onNewPerson;
  final bool shrinkWrap;

  FaceCropDragData _dragItem(PersonAppearance a) {
    return FaceCropDragData.appearance(
      source: source,
      appearanceId: a.id,
      itemId: a.itemId!,
      tagId: a.tagId!,
      personId: a.personId,
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
        final newPersonHandler = onNewPerson;
        final newPersonButton = newPersonHandler == null
            ? null
            : Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  key: Key('face-crop-new-person-${a.id}'),
                  tooltip: 'New person',
                  icon: const Icon(Icons.person_add, size: 16),
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: const Size(28, 28),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: busy ? null : () => newPersonHandler(a.id),
                ),
              );
        if (!canDrag) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              interactive,
              ?newPersonButton,
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
            ?newPersonButton,
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
  });

  final List<WhoExclusion> exclusions;
  final bool busy;
  final Set<String> selectedIds;
  final FaceCropTapTracker tapTracker;
  final void Function(WhoExclusion exclusion, {required bool toggle}) onSelect;
  final void Function(String itemId) onOpenItem;

  FaceCropDragData _dragItem(WhoExclusion e) {
    return FaceCropDragData.exclusion(
      source: FaceCropTray.excluded,
      exclusionId: e.id,
      itemId: e.itemId,
      region: e.region,
      createdFromTagId: e.createdFromTagId,
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
      padding: const EdgeInsets.all(8),
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
              border: selected
                  ? Border.all(color: scheme.primary, width: 2)
                  : Border.all(color: Colors.transparent, width: 2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(child: thumb),
          ),
        );
        final interactive = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _onTap(e),
          child: tile,
        );
        if (busy) return interactive;
        final payload = _payloadFor(e);
        return Draggable<FaceCropDragPayload>(
          data: payload,
          feedback: Material(
            elevation: 4,
            child: SizedBox(
              width: 72,
              height: 72,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  WhoExclusionCropThumb(
                    itemId: e.itemId,
                    region: e.region,
                    size: 72,
                  ),
                  if (payload.count > 1)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: CircleAvatar(
                        radius: 10,
                        backgroundColor: scheme.primary,
                        child: Text(
                          '${payload.count}',
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
        );
      },
    );
  }
}

/// Navigate to the Faces trays workspace (optionally focused on a person
/// and/or leaf folder).
Future<void> openFaceCropTrays(
  BuildContext context, {
  String? personId,
  String? leafFolder,
}) async {
  final container = ProviderScope.containerOf(context);
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => SelectableScope(
        child: UncontrolledProviderScope(
          container: container,
          child: FaceCropTraysPage(
            initialPersonId: personId,
            initialLeafFolder: leafFolder,
          ),
        ),
      ),
    ),
  );
}
