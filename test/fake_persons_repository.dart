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

  final List<String> confirmCalls = <String>[];
  final List<String> unlinkCalls = <String>[];
  final List<({String appearanceId, String? personId})> reassignCalls =
      <({String appearanceId, String? personId})>[];
  final List<({String personId, String? name})> renameCalls =
      <({String personId, String? name})>[];
  final List<String> deleteCalls = <String>[];

  int _newPersonCounter = 0;

  @override
  Future<List<Person>> listPersons({LinkState? linkState}) async {
    if (listError != null) throw listError!;
    var list = _persons
        .map(
          (d) => Person(
            id: d.id,
            name: d.name,
            linkState: d.linkState,
            createdAt: d.createdAt,
          ),
        )
        .toList();
    if (linkState != null) {
      list = list.where((p) => p.linkState == linkState).toList();
    }
    return list;
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
  Future<Person> renamePerson(String personId, String? name) async {
    renameCalls.add((personId: personId, name: name));
    final index = _persons.indexWhere((p) => p.id == personId);
    if (index < 0) {
      throw ApiException(statusCode: 404, message: 'Not found');
    }
    final prev = _persons[index];
    final updated = PersonDetail(
      id: prev.id,
      name: name,
      linkState: prev.linkState,
      createdAt: prev.createdAt,
      appearances: prev.appearances,
    );
    _persons[index] = updated;
    return Person(
      id: updated.id,
      name: updated.name,
      linkState: updated.linkState,
      createdAt: updated.createdAt,
    );
  }

  @override
  Future<PersonDetail> confirmPerson(String personId) async {
    confirmCalls.add(personId);
    final index = _persons.indexWhere((p) => p.id == personId);
    if (index < 0) {
      throw ApiException(statusCode: 404, message: 'Not found');
    }
    final prev = _persons[index];
    final updated = PersonDetail(
      id: prev.id,
      name: prev.name,
      linkState: LinkState.confirmed,
      createdAt: prev.createdAt,
      appearances: prev.appearances
          .map(
            (a) => PersonAppearance(
              id: a.id,
              personId: a.personId,
              itemId: a.itemId,
              keyPeriodId: a.keyPeriodId,
              tagId: a.tagId,
              region: a.region,
              linkState: LinkState.confirmed,
              createdAt: a.createdAt,
            ),
          )
          .toList(),
    );
    _persons[index] = updated;
    return updated;
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
        linkState: person.linkState,
        createdAt: person.createdAt,
        appearances: remaining,
      );
      return PersonAppearance(
        id: appearance.id,
        personId: null,
        itemId: appearance.itemId,
        keyPeriodId: appearance.keyPeriodId,
        tagId: appearance.tagId,
        region: appearance.region,
        linkState: LinkState.suggested,
        createdAt: appearance.createdAt,
      );
    }
    throw ApiException(statusCode: 404, message: 'Not found');
  }

  @override
  Future<PersonAppearance> reassignAppearance(
    String appearanceId,
    String? personId,
  ) async {
    reassignCalls.add((appearanceId: appearanceId, personId: personId));
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
        linkState: person.linkState,
        createdAt: person.createdAt,
        appearances: remaining,
      );
      break;
    }
    if (found == null) {
      throw ApiException(statusCode: 404, message: 'Not found');
    }

    var targetPersonId = personId;
    if (targetPersonId == null) {
      _newPersonCounter += 1;
      targetPersonId = 'person_new_$_newPersonCounter';
      _persons.add(
        PersonDetail(
          id: targetPersonId,
          name: null,
          linkState: LinkState.confirmed,
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
      itemId: found.itemId,
      keyPeriodId: found.keyPeriodId,
      tagId: found.tagId,
      region: found.region,
      linkState: LinkState.confirmed,
      createdAt: found.createdAt,
    );
    _persons[targetIndex] = PersonDetail(
      id: target.id,
      name: target.name,
      linkState: target.linkState,
      createdAt: target.createdAt,
      appearances: [...target.appearances, moved],
    );
    return moved;
  }

  @override
  Future<void> deletePerson(String personId) async {
    deleteCalls.add(personId);
    final index = _persons.indexWhere((p) => p.id == personId);
    if (index < 0) {
      throw ApiException(statusCode: 404, message: 'Not found');
    }
    final person = _persons[index];
    if (person.linkState != LinkState.suggested) {
      throw ApiException(
        statusCode: 400,
        message: 'Only suggested persons can be deleted',
      );
    }
    _persons.removeAt(index);
  }

  final List<PersonAppearance> unassignedAppearances = <PersonAppearance>[];
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

/// Fixture [PersonAppearance] for D9 tests.
PersonAppearance fixtureAppearance({
  String id = 'ap_1',
  String? personId = 'person_1',
  String? itemId = 'item_1',
  String? keyPeriodId,
  String? tagId,
  TagRegion? region,
  LinkState linkState = LinkState.suggested,
}) {
  return PersonAppearance(
    id: id,
    personId: personId,
    itemId: itemId,
    keyPeriodId: keyPeriodId,
    tagId: tagId,
    region: region,
    linkState: linkState,
    createdAt: '2026-07-20T00:00:00.000Z',
  );
}

/// Fixture [PersonDetail] for D9 tests.
PersonDetail fixturePersonDetail({
  String id = 'person_1',
  String? name = 'Sam',
  LinkState linkState = LinkState.suggested,
  List<PersonAppearance>? appearances,
}) {
  return PersonDetail(
    id: id,
    name: name,
    linkState: linkState,
    createdAt: '2026-07-20T00:00:00.000Z',
    appearances: appearances ??
        [
          fixtureAppearance(id: 'ap_1', personId: id, linkState: linkState),
        ],
  );
}
