import 'package:tagkin_desktop/contract/contract.dart';

/// Case-insensitive trimmed key — matches API `lower(name)` for BMP names.
String personNameKey(String name) => name.trim().toLowerCase();

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
