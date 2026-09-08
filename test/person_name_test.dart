import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/persons/person_name.dart';

void main() {
  test('personNameKey is trim + case-insensitive', () {
    expect(personNameKey(' Alex '), 'alex');
    expect(personNameKey('ALEX'), personNameKey('alex'));
  });

  test('findPersonByName matches case-insensitively and can exclude self', () {
    const persons = [
      Person(id: 'p1', name: 'Alex', createdAt: '2026-08-13T00:00:00.000Z'),
      Person(id: 'p2', name: 'Sam', createdAt: '2026-08-13T00:00:00.000Z'),
    ];
    expect(findPersonByName(persons, 'alex')?.id, 'p1');
    expect(findPersonByName(persons, 'ALEX', excludeId: 'p1'), isNull);
    expect(findPersonByName(persons, 'Pat'), isNull);
  });

  test('comparePersonNames is case-insensitive then id', () {
    const zoe = Person(id: 'p_z', name: 'zoe', createdAt: '');
    const ada = Person(id: 'p_a', name: 'Ada', createdAt: '');
    const bob = Person(id: 'p_b', name: 'bob', createdAt: '');
    const ada2 = Person(id: 'p_a2', name: 'ADA', createdAt: '');
    expect(comparePersonNames(ada, zoe), lessThan(0));
    expect(comparePersonNames(zoe, bob), greaterThan(0));
    expect(comparePersonNames(ada, ada2), lessThan(0));
    expect(
      sortedPersonsByName([zoe, ada2, bob, ada]).map((p) => p.id).toList(),
      ['p_a', 'p_a2', 'p_b', 'p_z'],
    );
  });

  test('skippedSamePhotoFacesMessage counts named vs leftover faces', () {
    expect(
      skippedSamePhotoFacesMessage(named: 2, skipped: 1),
      'Named 2 faces. 1 face from the same photo stayed in Unassigned.',
    );
    expect(
      skippedSamePhotoFacesMessage(named: 1, skipped: 2),
      'Named 1 face. 2 faces from the same photo stayed in Unassigned.',
    );
  });
}
