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
}
