import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/api/persons_repository.dart';
import 'package:tagkin_desktop/contract/contract.dart';

/// In-memory [PersonsRepository] for widget/integration tests (no network).
class FakePersonsRepository implements PersonsRepository {
  FakePersonsRepository({
    List<PersonDetail>? persons,
    this.listError,
    this.getError,
  }) : _persons = List<PersonDetail>.from(persons ?? const []);

  final List<PersonDetail> _persons;
  final Object? listError;
  final Object? getError;

  /// Test helper: mutable person details (exclude/undo linkage).
  List<PersonDetail> get personDetails => _persons;

  /// Replace a person detail by id (exclude/undo linkage).
  void replacePersonDetail(PersonDetail detail) {
    final index = _persons.indexWhere((p) => p.id == detail.id);
    if (index < 0) {
      throw StateError('Person ${detail.id} not found');
    }
    _persons[index] = detail;
  }

  void _assertPersonNotOnItem({
    required String personId,
    required String? itemId,
    String? exceptAppearanceId,
  }) {
    if (itemId == null) return;
    for (final p in _persons) {
      if (p.id != personId) continue;
      for (final a in p.appearances) {
        if (a.id == exceptAppearanceId) continue;
        if (a.itemId == itemId) {
          throw ApiException(
            statusCode: 409,
            code: 'person_already_on_item',
            message: '${p.name} is already on another face in this photo',
          );
        }
      }
    }
  }

  static void _assertNoSameItemPair(Iterable<PersonAppearance> members) {
    final seen = <String>{};
    for (final a in members) {
      final itemId = a.itemId;
      if (itemId == null) continue;
      if (!seen.add(itemId)) {
        throw ApiException(
          statusCode: 409,
          code: 'same_photo_faces',
          message:
              'Two of these faces are in the same photo, so they cannot be the same person',
        );
      }
    }
  }

  /// Remove and return an appearance by [tagId] from assigned or unassigned.
  PersonAppearance? takeAppearanceByTagId(String tagId) {
    for (var i = 0; i < _persons.length; i++) {
      final person = _persons[i];
      final idx = person.appearances.indexWhere((a) => a.tagId == tagId);
      if (idx < 0) continue;
      final found = person.appearances[idx];
      final remaining = List<PersonAppearance>.from(person.appearances)
        ..removeAt(idx);
      _persons[i] = PersonDetail(
        id: person.id,
        name: person.name,
        createdAt: person.createdAt,
        appearances: remaining,
      );
      return found;
    }
    final uIdx = unassignedAppearances.indexWhere((a) => a.tagId == tagId);
    if (uIdx >= 0) return unassignedAppearances.removeAt(uIdx);
    return null;
  }

  final List<String> unlinkCalls = <String>[];
  final List<
    ({
      String appearanceId,
      String? personId,
      String? name,
      bool? propagateAlike,
    })
  >
  reassignCalls =
      <
        ({
          String appearanceId,
          String? personId,
          String? name,
          bool? propagateAlike,
        })
      >[];

  /// When true, reassign moves remaining faces on the source person onto the
  /// target as unconfirmed (mirrors the API sweep). Off by default so existing
  /// tray tests keep moving a single face.
  bool sweepSiblingsOnReassign = false;

  final Map<String, String> _autoMovedFromPersonId = <String, String>{};
  final List<String> confirmAppearanceCalls = <String>[];
  final List<String> declineAutoAssignCalls = <String>[];
  final List<({String personId, String name})> renameCalls =
      <({String personId, String name})>[];
  final List<({String personId, String targetPersonId})> mergeCalls =
      <({String personId, String targetPersonId})>[];
  final List<String> deleteCalls = <String>[];
  final List<({String faceGroupId, String? personId, String? name})>
  assignFaceGroupCalls =
      <({String faceGroupId, String? personId, String? name})>[];
  final List<List<String>> unassignAppearancesCalls = <List<String>>[];

  int _newPersonCounter = 0;
  int _newFaceGroupCounter = 0;

  @override
  Future<List<Person>> listPersons() async {
    if (listError != null) throw listError!;
    return _persons
        .map((d) => Person(id: d.id, name: d.name, createdAt: d.createdAt))
        .toList();
  }

  @override
  Future<PersonDetail> getPerson(String personId) async {
    if (getError != null) throw getError!;
    for (final person in _persons) {
      if (person.id == personId) return person;
    }
    throw ApiException(statusCode: 404, message: 'Not found');
  }

  bool _nameTaken(String name, {String? excludeId}) {
    final key = name.trim().toLowerCase();
    return _persons.any(
      (p) => p.id != excludeId && p.name.trim().toLowerCase() == key,
    );
  }

  @override
  Future<Person> renamePerson(String personId, String name) async {
    renameCalls.add((personId: personId, name: name));
    if (_nameTaken(name, excludeId: personId)) {
      throw ApiException(
        statusCode: 400,
        message: 'A person with this name already exists',
      );
    }
    final index = _persons.indexWhere((p) => p.id == personId);
    if (index < 0) {
      throw ApiException(statusCode: 404, message: 'Not found');
    }
    final prev = _persons[index];
    final updated = PersonDetail(
      id: prev.id,
      name: name,
      createdAt: prev.createdAt,
      appearances: prev.appearances,
    );
    _persons[index] = updated;
    return Person(
      id: updated.id,
      name: updated.name,
      createdAt: updated.createdAt,
    );
  }

  /// Replace one appearance wherever it lives (assigned person or unassigned).
  PersonAppearance? replaceAppearance(PersonAppearance next) {
    for (var i = 0; i < _persons.length; i++) {
      final person = _persons[i];
      final idx = person.appearances.indexWhere((a) => a.id == next.id);
      if (idx < 0) continue;
      final remaining = List<PersonAppearance>.from(person.appearances);
      remaining[idx] = next;
      _persons[i] = PersonDetail(
        id: person.id,
        name: person.name,
        createdAt: person.createdAt,
        appearances: remaining,
      );
      return next;
    }
    final uIdx = unassignedAppearances.indexWhere((a) => a.id == next.id);
    if (uIdx >= 0) {
      unassignedAppearances[uIdx] = next;
      return next;
    }
    final aIdx = assignedAppearances.indexWhere((a) => a.id == next.id);
    if (aIdx >= 0) {
      assignedAppearances[aIdx] = next;
      return next;
    }
    return null;
  }

  PersonAppearance? _findAppearance(String appearanceId) {
    for (final person in _persons) {
      for (final a in person.appearances) {
        if (a.id == appearanceId) return a;
      }
    }
    for (final a in unassignedAppearances) {
      if (a.id == appearanceId) return a;
    }
    for (final a in assignedAppearances) {
      if (a.id == appearanceId) return a;
    }
    return null;
  }

  @override
  Future<PersonAppearance> confirmAppearanceAssignment(
    String appearanceId,
  ) async {
    confirmAppearanceCalls.add(appearanceId);
    final found = _findAppearance(appearanceId);
    if (found == null) {
      throw ApiException(statusCode: 404, message: 'Not found');
    }
    if (found.personId == null) {
      throw ApiException(
        statusCode: 400,
        message: 'Appearance is not assigned to a person',
      );
    }
    if (found.assignmentState == 'confirmed') return found;
    if (found.assignmentState != 'unconfirmed') {
      throw ApiException(
        statusCode: 400,
        message: 'appearance assignment is not unconfirmed',
      );
    }
    final confirmed = PersonAppearance(
      id: found.id,
      personId: found.personId,
      faceGroupId: found.faceGroupId,
      faceGroupKind: found.faceGroupKind,
      assignmentState: 'confirmed',
      itemId: found.itemId,
      keyPeriodId: found.keyPeriodId,
      tagId: found.tagId,
      region: found.region,
      createdAt: found.createdAt,
    );
    replaceAppearance(confirmed);
    return confirmed;
  }

  @override
  Future<PersonAppearance> declineAutoAssignAppearance(
    String appearanceId,
  ) async {
    return (await declineAutoAssignAppearances([appearanceId])).single;
  }

  final List<List<String>> declineAutoAssignAppearancesCalls = <List<String>>[];

  /// `POST /persons/appearances/decline-auto-assign` fake. Two or more
  /// declined together are restored as one GroupFA, mirroring the API.
  @override
  Future<List<PersonAppearance>> declineAutoAssignAppearances(
    List<String> appearanceIds,
  ) async {
    declineAutoAssignAppearancesCalls.add(List<String>.from(appearanceIds));
    declineAutoAssignCalls.addAll(appearanceIds);
    final found = <PersonAppearance>[];
    for (final appearanceId in appearanceIds) {
      PersonAppearance? match;
      for (var i = 0; i < _persons.length; i++) {
        final person = _persons[i];
        final idx = person.appearances.indexWhere((a) => a.id == appearanceId);
        if (idx < 0) continue;
        match = person.appearances[idx];
        final remaining = List<PersonAppearance>.from(person.appearances)
          ..removeAt(idx);
        _persons[i] = PersonDetail(
          id: person.id,
          name: person.name,
          createdAt: person.createdAt,
          appearances: remaining,
        );
        break;
      }
      if (match == null) {
        final aIdx = assignedAppearances.indexWhere(
          (a) => a.id == appearanceId,
        );
        if (aIdx >= 0) match = assignedAppearances.removeAt(aIdx);
      }
      if (match == null) {
        throw ApiException(statusCode: 404, message: 'Not found');
      }
      if (match.personId == null) {
        throw ApiException(
          statusCode: 400,
          message: 'Appearance is not assigned to a person',
        );
      }
      found.add(match);
    }

    final restore = <PersonAppearance>[];
    final unassign = <PersonAppearance>[];
    for (final a in found) {
      if (_autoMovedFromPersonId.containsKey(a.id)) {
        restore.add(a);
      } else {
        unassign.add(a);
      }
    }

    final restored = <PersonAppearance>[];
    for (final a in restore) {
      final fromId = _autoMovedFromPersonId.remove(a.id)!;
      final idx = _persons.indexWhere((p) => p.id == fromId);
      if (idx < 0) {
        throw ApiException(statusCode: 404, message: 'Prior person not found');
      }
      final dest = _persons[idx];
      final clash =
          a.itemId != null && dest.appearances.any((x) => x.itemId == a.itemId);
      if (clash) {
        unassign.add(a);
        continue;
      }
      final back = PersonAppearance(
        id: a.id,
        personId: fromId,
        faceGroupId: null,
        faceGroupKind: null,
        assignmentState: 'confirmed',
        itemId: a.itemId,
        keyPeriodId: a.keyPeriodId,
        tagId: a.tagId,
        region: a.region,
        createdAt: a.createdAt,
      );
      _persons[idx] = PersonDetail(
        id: dest.id,
        name: dest.name,
        createdAt: dest.createdAt,
        appearances: [...dest.appearances, back],
      );
      restored.add(back);
    }

    String? faceGroupId;
    FaceGroupKind? faceGroupKind;
    if (unassign.length >= 2) {
      _newFaceGroupCounter += 1;
      faceGroupId = 'fg_fa_$_newFaceGroupCounter';
      faceGroupKind = FaceGroupKind.fa;
    }

    final declined = <PersonAppearance>[
      for (final a in unassign)
        PersonAppearance(
          id: a.id,
          personId: null,
          faceGroupId: faceGroupId,
          faceGroupKind: faceGroupKind,
          assignmentState: null,
          itemId: a.itemId,
          keyPeriodId: a.keyPeriodId,
          tagId: a.tagId,
          region: a.region,
          createdAt: a.createdAt,
        ),
    ];
    unassignedAppearances.addAll(declined);
    assignedAppearances.removeWhere((a) => appearanceIds.contains(a.id));
    return [...restored, ...declined];
  }

  /// Test/undo helper: restore [assignmentState] to unconfirmed on an assigned
  /// appearance (no real API equivalent yet).
  @override
  Future<PersonAppearance> tryRestoreUnconfirmedAssignment(
    String appearanceId,
  ) async {
    final found = _findAppearance(appearanceId);
    if (found == null || found.personId == null) {
      throw ApiException(statusCode: 404, message: 'Not found');
    }
    final restored = PersonAppearance(
      id: found.id,
      personId: found.personId,
      faceGroupId: found.faceGroupId,
      faceGroupKind: found.faceGroupKind,
      assignmentState: 'unconfirmed',
      itemId: found.itemId,
      keyPeriodId: found.keyPeriodId,
      tagId: found.tagId,
      region: found.region,
      createdAt: found.createdAt,
    );
    replaceAppearance(restored);
    return restored;
  }

  @override
  Future<PersonAppearance> unlinkAppearance(String appearanceId) async {
    unlinkCalls.add(appearanceId);
    for (var i = 0; i < _persons.length; i++) {
      final person = _persons[i];
      final idx = person.appearances.indexWhere((a) => a.id == appearanceId);
      if (idx < 0) continue;
      final appearance = person.appearances[idx];
      final remaining = List<PersonAppearance>.from(person.appearances)
        ..removeAt(idx);
      _persons[i] = PersonDetail(
        id: person.id,
        name: person.name,
        createdAt: person.createdAt,
        appearances: remaining,
      );
      final unlinked = PersonAppearance(
        id: appearance.id,
        personId: null,
        itemId: appearance.itemId,
        keyPeriodId: appearance.keyPeriodId,
        tagId: appearance.tagId,
        region: appearance.region,
        createdAt: appearance.createdAt,
      );
      unassignedAppearances.add(unlinked);
      return unlinked;
    }
    final uIdx = unassignedAppearances.indexWhere((a) => a.id == appearanceId);
    if (uIdx >= 0) {
      final prev = unassignedAppearances.removeAt(uIdx);
      final unlinked = PersonAppearance(
        id: prev.id,
        personId: null,
        itemId: prev.itemId,
        keyPeriodId: prev.keyPeriodId,
        tagId: prev.tagId,
        region: prev.region,
        createdAt: prev.createdAt,
      );
      unassignedAppearances.add(unlinked);
      return unlinked;
    }
    throw ApiException(statusCode: 404, message: 'Not found');
  }

  @override
  Future<ReassignAppearanceResponse> reassignAppearance(
    String appearanceId, {
    String? personId,
    String? name,
    bool? propagateAlike,
  }) async {
    reassignCalls.add((
      appearanceId: appearanceId,
      personId: personId,
      name: name,
      propagateAlike: propagateAlike,
    ));
    PersonAppearance? found;
    String? previousPersonId;
    for (var i = 0; i < _persons.length; i++) {
      final person = _persons[i];
      final idx = person.appearances.indexWhere((a) => a.id == appearanceId);
      if (idx < 0) continue;
      found = person.appearances[idx];
      previousPersonId = person.id;
      final remaining = List<PersonAppearance>.from(person.appearances)
        ..removeAt(idx);
      _persons[i] = PersonDetail(
        id: person.id,
        name: person.name,
        createdAt: person.createdAt,
        appearances: remaining,
      );
      break;
    }
    if (found == null) {
      final uIdx = unassignedAppearances.indexWhere(
        (a) => a.id == appearanceId,
      );
      if (uIdx >= 0) {
        found = unassignedAppearances.removeAt(uIdx);
      }
    }
    if (found == null) {
      throw ApiException(statusCode: 404, message: 'Not found');
    }

    var targetPersonId = personId;
    if (targetPersonId == null) {
      if (name == null || name.isEmpty) {
        throw ApiException(
          statusCode: 400,
          message: 'reassign requires personId or name',
        );
      }
      if (_nameTaken(name)) {
        throw ApiException(
          statusCode: 400,
          message: 'A person with this name already exists',
        );
      }
      _newPersonCounter += 1;
      targetPersonId = 'person_new_$_newPersonCounter';
      _persons.add(
        PersonDetail(
          id: targetPersonId,
          name: name,
          createdAt: '2026-07-20T00:00:00.000Z',
          appearances: const [],
        ),
      );
    }

    final targetIndex = _persons.indexWhere((p) => p.id == targetPersonId);
    if (targetIndex < 0) {
      throw ApiException(statusCode: 404, message: 'Target person not found');
    }
    final target = _persons[targetIndex];
    _assertPersonNotOnItem(
      personId: targetPersonId,
      itemId: found.itemId,
      exceptAppearanceId: found.id,
    );
    final moved = PersonAppearance(
      id: found.id,
      personId: targetPersonId,
      faceGroupId: null,
      faceGroupKind: null,
      assignmentState: 'confirmed',
      itemId: found.itemId,
      keyPeriodId: found.keyPeriodId,
      tagId: found.tagId,
      region: found.region,
      createdAt: found.createdAt,
    );

    final alsoMoved = <PersonAppearance>[];
    if (propagateAlike != false &&
        sweepSiblingsOnReassign &&
        previousPersonId != null &&
        previousPersonId != targetPersonId) {
      final claimedItems = <String>{
        if (found.itemId != null) found.itemId!,
        for (final a in target.appearances)
          if (a.itemId != null) a.itemId!,
      };
      for (var i = 0; i < _persons.length; i++) {
        if (_persons[i].id != previousPersonId) continue;
        final leftover = <PersonAppearance>[];
        for (final a in _persons[i].appearances) {
          final itemId = a.itemId;
          if (itemId != null && claimedItems.contains(itemId)) {
            leftover.add(a);
            continue;
          }
          if (itemId != null) claimedItems.add(itemId);
          final swept = PersonAppearance(
            id: a.id,
            personId: targetPersonId,
            faceGroupId: null,
            faceGroupKind: null,
            assignmentState: 'unconfirmed',
            itemId: a.itemId,
            keyPeriodId: a.keyPeriodId,
            tagId: a.tagId,
            region: a.region,
            createdAt: a.createdAt,
          );
          alsoMoved.add(swept);
          _autoMovedFromPersonId[a.id] = previousPersonId;
        }
        _persons[i] = PersonDetail(
          id: _persons[i].id,
          name: _persons[i].name,
          createdAt: _persons[i].createdAt,
          appearances: leftover,
        );
        break;
      }
    }

    _persons[targetIndex] = PersonDetail(
      id: target.id,
      name: target.name,
      createdAt: target.createdAt,
      appearances: [...target.appearances, moved, ...alsoMoved],
    );
    return ReassignAppearanceResponse(appearance: moved, alsoMoved: alsoMoved);
  }

  @override
  Future<AssignFaceGroupResponse> assignFaceGroup(
    String faceGroupId, {
    String? personId,
    String? name,
  }) async {
    assignFaceGroupCalls.add((
      faceGroupId: faceGroupId,
      personId: personId,
      name: name,
    ));
    final members = unassignedAppearances
        .where((a) => a.faceGroupId == faceGroupId)
        .toList();
    if (members.isEmpty) {
      throw ApiException(statusCode: 404, message: 'Face group not found');
    }

    var targetPersonId = personId;
    if (targetPersonId == null) {
      if (name == null || name.isEmpty) {
        throw ApiException(
          statusCode: 400,
          message: 'assign requires personId or name',
        );
      }
      if (_nameTaken(name)) {
        throw ApiException(
          statusCode: 400,
          message: 'A person with this name already exists',
        );
      }
      _newPersonCounter += 1;
      targetPersonId = 'person_new_$_newPersonCounter';
      _persons.add(
        PersonDetail(
          id: targetPersonId,
          name: name,
          createdAt: '2026-07-20T00:00:00.000Z',
          appearances: const [],
        ),
      );
    }
    final targetIndex = _persons.indexWhere((p) => p.id == targetPersonId);
    if (targetIndex < 0) {
      throw ApiException(statusCode: 404, message: 'Target person not found');
    }
    final target = _persons[targetIndex];
    final claimed = {
      for (final a in target.appearances)
        if (a.itemId != null) a.itemId!,
    };
    final ordered = [...members]
      ..sort((a, b) {
        final byCreated = a.createdAt.compareTo(b.createdAt);
        if (byCreated != 0) return byCreated;
        return a.id.compareTo(b.id);
      });
    final byItem = <String?, List<PersonAppearance>>{};
    for (final m in ordered) {
      (byItem[m.itemId] ??= <PersonAppearance>[]).add(m);
    }
    final assign = <PersonAppearance>[];
    final skip = <PersonAppearance>[];
    for (final entry in byItem.entries) {
      final itemId = entry.key;
      final group = entry.value;
      if (itemId == null) {
        assign.addAll(group);
        continue;
      }
      if (claimed.contains(itemId)) {
        skip.addAll(group);
        continue;
      }
      assign.add(group.first);
      skip.addAll(group.skip(1));
      claimed.add(itemId);
    }
    if (assign.isEmpty) {
      throw ApiException(
        statusCode: 409,
        code: 'person_already_on_item',
        message: '${target.name} is already on another face in this photo',
      );
    }
    unassignedAppearances.removeWhere((a) => a.faceGroupId == faceGroupId);
    final moved = [
      for (final m in assign)
        PersonAppearance(
          id: m.id,
          personId: targetPersonId,
          faceGroupId: null,
          faceGroupKind: null,
          assignmentState: 'confirmed',
          itemId: m.itemId,
          keyPeriodId: m.keyPeriodId,
          tagId: m.tagId,
          region: m.region,
          createdAt: m.createdAt,
        ),
    ];
    final skipped = [
      for (final m in skip)
        PersonAppearance(
          id: m.id,
          personId: null,
          faceGroupId: null,
          faceGroupKind: null,
          assignmentState: null,
          itemId: m.itemId,
          keyPeriodId: m.keyPeriodId,
          tagId: m.tagId,
          region: m.region,
          createdAt: m.createdAt,
        ),
    ];
    unassignedAppearances.addAll(skipped);
    final updatedTarget = PersonDetail(
      id: target.id,
      name: target.name,
      createdAt: target.createdAt,
      appearances: [...target.appearances, ...moved],
    );
    _persons[targetIndex] = updatedTarget;
    return AssignFaceGroupResponse(
      person: updatedTarget,
      skippedAppearances: skipped,
    );
  }

  @override
  Future<List<PersonAppearance>> unassignAppearances(
    List<String> appearanceIds,
  ) async {
    unassignAppearancesCalls.add(List<String>.from(appearanceIds));
    final moved = <PersonAppearance>[];
    for (final id in appearanceIds) {
      PersonAppearance? found;
      for (var i = 0; i < _persons.length; i++) {
        final person = _persons[i];
        final idx = person.appearances.indexWhere((a) => a.id == id);
        if (idx < 0) continue;
        found = person.appearances[idx];
        final remaining = List<PersonAppearance>.from(person.appearances)
          ..removeAt(idx);
        _persons[i] = PersonDetail(
          id: person.id,
          name: person.name,
          createdAt: person.createdAt,
          appearances: remaining,
        );
        break;
      }
      if (found == null) {
        final idx = unassignedAppearances.indexWhere((a) => a.id == id);
        if (idx >= 0) found = unassignedAppearances.removeAt(idx);
      }
      if (found == null) {
        throw ApiException(statusCode: 404, message: 'Not found: $id');
      }
      moved.add(found);
    }

    String? faceGroupId;
    FaceGroupKind? faceGroupKind;
    if (moved.length >= 2) {
      _newFaceGroupCounter += 1;
      faceGroupId = 'fg_fm_$_newFaceGroupCounter';
      faceGroupKind = FaceGroupKind.fm;
    }

    final result = <PersonAppearance>[
      for (final a in moved)
        PersonAppearance(
          id: a.id,
          personId: null,
          faceGroupId: faceGroupId,
          faceGroupKind: faceGroupKind,
          itemId: a.itemId,
          keyPeriodId: a.keyPeriodId,
          tagId: a.tagId,
          region: a.region,
          createdAt: a.createdAt,
        ),
    ];
    unassignedAppearances.addAll(result);
    return result;
  }

  final List<List<String>> assembleAppearancesCalls = <List<String>>[];
  final List<List<String>> assembleExclusionsCalls = <List<String>>[];
  final List<String> ungroupFaceGroupCalls = <String>[];

  @override
  Future<AssembleAppearancesResponse> assembleAppearances(
    List<String> appearanceIds,
  ) async {
    assembleAppearancesCalls.add(List<String>.from(appearanceIds));
    if (appearanceIds.length < 2) {
      throw ApiException(statusCode: 400, message: 'need ≥2');
    }
    final members = <PersonAppearance>[];
    for (final id in appearanceIds) {
      final idx = unassignedAppearances.indexWhere((a) => a.id == id);
      if (idx < 0) {
        throw ApiException(statusCode: 400, message: 'Not loose: $id');
      }
      members.add(unassignedAppearances[idx]);
    }
    _assertNoSameItemPair(members);
    _newFaceGroupCounter += 1;
    final faceGroupId = 'fg_fm_$_newFaceGroupCounter';
    final updated = <PersonAppearance>[
      for (final a in members)
        PersonAppearance(
          id: a.id,
          personId: null,
          faceGroupId: faceGroupId,
          faceGroupKind: FaceGroupKind.fm,
          itemId: a.itemId,
          keyPeriodId: a.keyPeriodId,
          tagId: a.tagId,
          region: a.region,
          createdAt: a.createdAt,
        ),
    ];
    unassignedAppearances.removeWhere((a) => appearanceIds.contains(a.id));
    unassignedAppearances.addAll(updated);
    return AssembleAppearancesResponse(
      faceGroupId: faceGroupId,
      appearances: updated,
    );
  }

  @override
  Future<AssembleExclusionsResponse> assembleExclusions(
    List<String> exclusionIds,
  ) async {
    assembleExclusionsCalls.add(List<String>.from(exclusionIds));
    if (exclusionIds.length < 2) {
      throw ApiException(statusCode: 400, message: 'need ≥2');
    }
    final members = <WhoExclusion>[];
    for (final id in exclusionIds) {
      final idx = accountExclusions.indexWhere((e) => e.id == id);
      if (idx < 0) {
        throw ApiException(statusCode: 400, message: 'Not found: $id');
      }
      members.add(accountExclusions[idx]);
    }
    final exclusionItems = [for (final e in members) e.itemId];
    if (exclusionItems.toSet().length != exclusionItems.length) {
      throw ApiException(
        statusCode: 409,
        code: 'same_photo_faces',
        message:
            'Two of these faces are in the same photo, so they cannot be the same person',
      );
    }
    _newFaceGroupCounter += 1;
    final faceGroupId = 'fg_fm_$_newFaceGroupCounter';
    final updated = <WhoExclusion>[
      for (final e in members)
        WhoExclusion(
          id: e.id,
          itemId: e.itemId,
          region: e.region,
          faceGroupId: faceGroupId,
          faceGroupKind: FaceGroupKind.fm,
          createdFromTagId: e.createdFromTagId,
          createdAt: e.createdAt,
        ),
    ];
    accountExclusions.removeWhere((e) => exclusionIds.contains(e.id));
    accountExclusions.addAll(updated);
    return AssembleExclusionsResponse(
      faceGroupId: faceGroupId,
      exclusions: updated,
    );
  }

  @override
  Future<UngroupFaceGroupResponse> ungroupFaceGroup(String faceGroupId) async {
    ungroupFaceGroupCalls.add(faceGroupId);
    final aps = unassignedAppearances
        .where((a) => a.faceGroupId == faceGroupId)
        .toList();
    final exs = accountExclusions
        .where((e) => e.faceGroupId == faceGroupId)
        .toList();
    if (aps.isEmpty && exs.isEmpty) {
      throw ApiException(statusCode: 404, message: 'Face group not found');
    }
    if (aps.any((a) => a.faceGroupKind == FaceGroupKind.fa) ||
        exs.any((e) => e.faceGroupKind == FaceGroupKind.fa)) {
      throw ApiException(statusCode: 400, message: 'Only GroupFM');
    }
    final clearedAps = <PersonAppearance>[
      for (final a in aps)
        PersonAppearance(
          id: a.id,
          personId: null,
          faceGroupId: null,
          faceGroupKind: null,
          itemId: a.itemId,
          keyPeriodId: a.keyPeriodId,
          tagId: a.tagId,
          region: a.region,
          createdAt: a.createdAt,
        ),
    ];
    final clearedExs = <WhoExclusion>[
      for (final e in exs)
        WhoExclusion(
          id: e.id,
          itemId: e.itemId,
          region: e.region,
          faceGroupId: null,
          faceGroupKind: null,
          createdFromTagId: e.createdFromTagId,
          createdAt: e.createdAt,
        ),
    ];
    unassignedAppearances.removeWhere((a) => a.faceGroupId == faceGroupId);
    unassignedAppearances.addAll(clearedAps);
    accountExclusions.removeWhere((e) => e.faceGroupId == faceGroupId);
    accountExclusions.addAll(clearedExs);
    return UngroupFaceGroupResponse(
      faceGroupId: faceGroupId,
      appearances: clearedAps,
      exclusions: clearedExs,
    );
  }

  @override
  Future<void> deletePerson(String personId) async {
    deleteCalls.add(personId);
    final index = _persons.indexWhere((p) => p.id == personId);
    if (index < 0) {
      throw ApiException(statusCode: 404, message: 'Not found');
    }
    final person = _persons[index];
    String? faceGroupId;
    FaceGroupKind? faceGroupKind;
    if (person.appearances.length >= 2) {
      _newFaceGroupCounter += 1;
      faceGroupId = 'fg_fm_$_newFaceGroupCounter';
      faceGroupKind = FaceGroupKind.fm;
    }
    for (final a in person.appearances) {
      unassignedAppearances.add(
        PersonAppearance(
          id: a.id,
          personId: null,
          faceGroupId: faceGroupId,
          faceGroupKind: faceGroupKind,
          itemId: a.itemId,
          keyPeriodId: a.keyPeriodId,
          tagId: a.tagId,
          region: a.region,
          createdAt: a.createdAt,
        ),
      );
    }
    _persons.removeAt(index);
  }

  @override
  Future<PersonDetail> mergePerson(
    String personId,
    String targetPersonId,
  ) async {
    mergeCalls.add((personId: personId, targetPersonId: targetPersonId));
    if (personId == targetPersonId) {
      throw ApiException(
        statusCode: 400,
        message: 'Cannot merge a person into itself',
      );
    }
    final sourceIndex = _persons.indexWhere((p) => p.id == personId);
    final targetIndex = _persons.indexWhere((p) => p.id == targetPersonId);
    if (sourceIndex < 0 || targetIndex < 0) {
      throw ApiException(statusCode: 404, message: 'Not found');
    }
    final source = _persons[sourceIndex];
    final target = _persons[targetIndex];
    final moved = [
      for (final a in source.appearances)
        PersonAppearance(
          id: a.id,
          personId: targetPersonId,
          faceGroupId: null,
          faceGroupKind: null,
          assignmentState: 'confirmed',
          itemId: a.itemId,
          keyPeriodId: a.keyPeriodId,
          tagId: a.tagId,
          region: a.region,
          createdAt: a.createdAt,
        ),
    ];
    _persons[targetIndex] = PersonDetail(
      id: target.id,
      name: target.name,
      createdAt: target.createdAt,
      appearances: [...target.appearances, ...moved],
    );
    _persons.removeAt(sourceIndex);
    return _persons.firstWhere((p) => p.id == targetPersonId);
  }

  final List<PersonAppearance> unassignedAppearances = <PersonAppearance>[];
  final List<PersonAppearance> assignedAppearances = <PersonAppearance>[];
  final List<WhoExclusion> accountExclusions = <WhoExclusion>[];

  @override
  Future<UnassignedAppearancesPage> listUnassignedAppearances({
    int limit = 100,
    int offset = 0,
  }) async {
    final slice = unassignedAppearances.skip(offset).take(limit).toList();
    return UnassignedAppearancesPage(
      appearances: slice,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<AssignedAppearancesPage> listAssignedAppearances({
    int limit = 100,
    int offset = 0,
  }) async {
    // Prefer explicit list; otherwise flatten person details.
    final source = assignedAppearances.isNotEmpty
        ? assignedAppearances
        : [
            for (final p in _persons)
              for (final a in p.appearances)
                if (a.personId != null) a,
          ];
    final slice = source.skip(offset).take(limit).toList();
    return AssignedAppearancesPage(
      appearances: slice,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<AccountWhoExclusionsPage> listAccountWhoExclusions({
    int limit = 100,
    int offset = 0,
  }) async {
    final slice = accountExclusions.skip(offset).take(limit).toList();
    return AccountWhoExclusionsPage(
      exclusions: slice,
      limit: limit,
      offset: offset,
    );
  }
}

/// Fixture [PersonAppearance] for D9 tests. Pass [faceGroupId] +
/// [faceGroupKind] together to simulate an Unassigned GroupFA/GroupFM member.
PersonAppearance fixtureAppearance({
  String id = 'ap_1',
  String? personId = 'person_1',
  String? faceGroupId,
  FaceGroupKind? faceGroupKind,
  String? assignmentState,
  String? itemId = 'item_1',
  String? keyPeriodId,
  String? tagId,
  TagRegion? region,
  double? sharpness,
}) {
  final resolvedState =
      assignmentState ?? (personId != null ? 'confirmed' : null);
  return PersonAppearance(
    id: id,
    personId: personId,
    faceGroupId: faceGroupId,
    faceGroupKind: faceGroupKind,
    assignmentState: resolvedState,
    itemId: itemId,
    keyPeriodId: keyPeriodId,
    tagId: tagId,
    region: region,
    createdAt: '2026-07-20T00:00:00.000Z',
    sharpness: sharpness,
  );
}

/// Fixture [PersonDetail] for D9 tests. Person.name is always non-empty (R2).
PersonDetail fixturePersonDetail({
  String id = 'person_1',
  String name = 'Sam',
  List<PersonAppearance>? appearances,
}) {
  return PersonDetail(
    id: id,
    name: name,
    createdAt: '2026-07-20T00:00:00.000Z',
    appearances: appearances ?? [fixtureAppearance(id: 'ap_1', personId: id)],
  );
}
