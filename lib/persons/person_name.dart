import 'package:tagkin_desktop/contract/contract.dart';

/// Case-insensitive trimmed key — matches API `lower(name)` for BMP names.
String personNameKey(String name) => name.trim().toLowerCase();

/// Case-insensitive name order, then [Person.id] so equal names stay stable.
int comparePersonNames(Person a, Person b) {
  final byName = personNameKey(a.name).compareTo(personNameKey(b.name));
  if (byName != 0) return byName;
  return a.id.compareTo(b.id);
}

/// Copy of [persons] ordered by [comparePersonNames].
List<Person> sortedPersonsByName(Iterable<Person> persons) =>
    List<Person>.from(persons)..sort(comparePersonNames);

/// First person whose name matches [name] (trim + case-insensitive).
Person? findPersonByName(
  Iterable<Person> persons,
  String name, {
  String? excludeId,
}) {
  final key = personNameKey(name);
  if (key.isEmpty) return null;
  for (final p in persons) {
    if (excludeId != null && p.id == excludeId) continue;
    if (personNameKey(p.name) == key) return p;
  }
  return null;
}

String personAlreadyOnPhotoMessage(String? name) {
  final n = name?.trim();
  return n != null && n.isNotEmpty
      ? '$n is already on another face in this photo.'
      : 'That person is already on another face in this photo.';
}

String skippedSamePhotoFacesMessage({
  required int named,
  required int skipped,
}) {
  final namedLabel = named == 1 ? 'face' : 'faces';
  final skippedLabel = skipped == 1 ? 'face' : 'faces';
  return 'Named $named $namedLabel. $skipped $skippedLabel from the same photo stayed in Unassigned.';
}
