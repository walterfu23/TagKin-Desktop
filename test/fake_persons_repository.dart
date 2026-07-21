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
  final List<({String personId, List<String> appearanceIds})> splitCalls =
      <({String personId, List<String> appearanceIds})>[];
  final List<String> unlinkCalls = <String>[];
  final List<({String appearanceId, String personId})> reassignCalls =
      <({String appearanceId, String personId})>[];
  final List<({String personId, String? name})> renameCalls =
      <({String personId, String? name})>[];

  int _splitCounter = 0;

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
  Future<PersonDetail> splitPerson(
    String personId,
    List<String> appearanceIds,
  ) async {
    splitCalls.add((personId: personId, appearanceIds: appearanceIds));
    final index = _persons.indexWhere((p) => p.id == personId);
    if (index < 0) {
      throw ApiException(statusCode: 404, message: 'Not found');
    }
    final prev = _persons[index];
    final moving = prev.appearances
        .where((a) => appearanceIds.contains(a.id))
        .toList();
    if (moving.isEmpty) {
      throw ApiException(statusCode: 400, message: 'No appearances to split');
    }
    final remaining = prev.appearances
        .where((a) => !appearanceIds.contains(a.id))
        .toList();
    _persons[index] = PersonDetail(
      id: prev.id,
      name: prev.name,
      linkState: prev.linkState,
      createdAt: prev.createdAt,
      appearances: remaining,
    );

    _splitCounter += 1;
    final newId = 'person_split_$_splitCounter';
    final created = PersonDetail(
      id: newId,
      name: null,
      linkState: LinkState.suggested,
      createdAt: '2026-07-20T00:00:00.000Z',
      appearances: moving
          .map(
            (a) => PersonAppearance(
              id: a.id,
              personId: newId,
              itemId: a.itemId,
              keyPeriodId: a.keyPeriodId,
              linkState: LinkState.suggested,
              createdAt: a.createdAt,
            ),
          )
          .toList(),
    );
    _persons.add(created);
    return created;
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
        linkState: LinkState.suggested,
        createdAt: appearance.createdAt,
      );
    }
    throw ApiException(statusCode: 404, message: 'Not found');
  }

  @override
  Future<PersonAppearance> reassignAppearance(
    String appearanceId,
    String personId,
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
    final targetIndex = _persons.indexWhere((p) => p.id == personId);
    if (targetIndex < 0) {
      throw ApiException(statusCode: 404, message: 'Target person not found');
    }
    final target = _persons[targetIndex];
    final moved = PersonAppearance(
      id: found.id,
      personId: personId,
      itemId: found.itemId,
      keyPeriodId: found.keyPeriodId,
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
}

/// Fixture [PersonAppearance] for D9 tests.
PersonAppearance fixtureAppearance({
  String id = 'ap_1',
  String? personId = 'person_1',
  String? itemId = 'item_1',
  String? keyPeriodId,
  LinkState linkState = LinkState.suggested,
}) {
  return PersonAppearance(
    id: id,
    personId: personId,
    itemId: itemId,
    keyPeriodId: keyPeriodId,
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
