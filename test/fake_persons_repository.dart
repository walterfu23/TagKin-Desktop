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
  final List<({String appearanceId, String? personId, String? name})>
      reassignCalls =
      <({String appearanceId, String? personId, String? name})>[];
  final List<({String personId, String name})> renameCalls =
      <({String personId, String name})>[];
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
        .map(
          (d) => Person(
            id: d.id,
            name: d.name,
            createdAt: d.createdAt,
          ),
        )
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

  @override
  Future<Person> renamePerson(String personId, String name) async {
    renameCalls.add((personId: personId, name: name));
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
  Future<PersonAppearance> reassignAppearance(
    String appearanceId, {
    String? personId,
    String? name,
  }) async {
    reassignCalls.add(
      (appearanceId: appearanceId, personId: personId, name: name),
    );
    PersonAppearance? found;
    for (var i = 0; i < _persons.length; i++) {
      final person = _persons[i];
      final idx = person.appearances.indexWhere((a) => a.id == appearanceId);
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
      final uIdx =
          unassignedAppearances.indexWhere((a) => a.id == appearanceId);
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
    final moved = PersonAppearance(
      id: found.id,
      personId: targetPersonId,
      faceGroupId: null,
      faceGroupKind: null,
      itemId: found.itemId,
      keyPeriodId: found.keyPeriodId,
      tagId: found.tagId,
      region: found.region,
      createdAt: found.createdAt,
    );
    _persons[targetIndex] = PersonDetail(
      id: target.id,
      name: target.name,
      createdAt: target.createdAt,
      appearances: [...target.appearances, moved],
    );
    return moved;
  }

  @override
  Future<PersonDetail> assignFaceGroup(
    String faceGroupId, {
    String? personId,
    String? name,
  }) async {
    assignFaceGroupCalls.add(
      (faceGroupId: faceGroupId, personId: personId, name: name),
    );
    final members =
        unassignedAppearances.where((a) => a.faceGroupId == faceGroupId).toList();
    if (members.isEmpty) {
      throw ApiException(statusCode: 404, message: 'Face group not found');
    }
    unassignedAppearances.removeWhere((a) => a.faceGroupId == faceGroupId);

    var targetPersonId = personId;
    if (targetPersonId == null) {
      if (name == null || name.isEmpty) {
        throw ApiException(
          statusCode: 400,
          message: 'assign requires personId or name',
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
    final moved = [
      for (final m in members)
        PersonAppearance(
          id: m.id,
          personId: targetPersonId,
          faceGroupId: null,
          faceGroupKind: null,
          itemId: m.itemId,
          keyPeriodId: m.keyPeriodId,
          tagId: m.tagId,
          region: m.region,
          createdAt: m.createdAt,
        ),
    ];
    final updatedTarget = PersonDetail(
      id: target.id,
      name: target.name,
      createdAt: target.createdAt,
      appearances: [...target.appearances, ...moved],
    );
    _persons[targetIndex] = updatedTarget;
    return updatedTarget;
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
      faceGroupId = 'fg_fa_$_newFaceGroupCounter';
      faceGroupKind = FaceGroupKind.fa;
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

  @override
  Future<void> deletePerson(String personId) async {
    deleteCalls.add(personId);
    final index = _persons.indexWhere((p) => p.id == personId);
    if (index < 0) {
      throw ApiException(statusCode: 404, message: 'Not found');
    }
    final person = _persons[index];
    for (final a in person.appearances) {
      unassignedAppearances.add(
        PersonAppearance(
          id: a.id,
          personId: null,
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
  String? itemId = 'item_1',
  String? keyPeriodId,
  String? tagId,
  TagRegion? region,
}) {
  return PersonAppearance(
    id: id,
    personId: personId,
    faceGroupId: faceGroupId,
    faceGroupKind: faceGroupKind,
    itemId: itemId,
    keyPeriodId: keyPeriodId,
    tagId: tagId,
    region: region,
    createdAt: '2026-07-20T00:00:00.000Z',
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
    appearances: appearances ??
        [
          fixtureAppearance(id: 'ap_1', personId: id),
        ],
  );
}
