import 'package:flutter/material.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/persons/person_name.dart';
import 'package:tagkin_desktop/persons/person_name_collision_dialog.dart';
import 'package:tagkin_desktop/persons/person_name_dialog.dart';

/// Prompt for a new person name, offering merge on collision (R6).
///
/// [draftPersonNames] are pending names on this item (not yet saved). A typed
/// match reuses that name instead of creating a second person.
Future<({String? personId, String? name})?> promptAssignPerson(
  BuildContext context, {
  required List<Person> persons,
  List<String> draftPersonNames = const [],
  String mergeLabel = 'Merge into that person',
}) async {
  var typed = await showPersonNameDialog(context);
  if (!context.mounted) return null;
  while (typed != null) {
    final clash = findPersonByName(persons, typed);
    if (clash != null) {
      final choice = await showPersonNameCollisionDialog(
        context,
        existingName: clash.name,
        mergeLabel: mergeLabel,
      );
      if (choice == PersonNameCollisionChoice.merge) {
        return (personId: clash.id, name: null);
      }
      if (choice != PersonNameCollisionChoice.otherName) return null;
      if (!context.mounted) return null;
      typed = await showPersonNameDialog(context, initialName: typed);
      if (!context.mounted) return null;
      continue;
    }
    final draft = _matchingDraftName(draftPersonNames, typed);
    if (draft != null) return (personId: null, name: draft);
    return (personId: null, name: typed);
  }
  return null;
}

String? _matchingDraftName(Iterable<String> draftPersonNames, String typed) {
  final key = personNameKey(typed);
  if (key.isEmpty) return null;
  for (final name in draftPersonNames) {
    if (personNameKey(name) == key) return name.trim();
  }
  return null;
}

/// Pending New person names on this item that are not already in [persons].
List<String> uniqueDraftPersonNames({
  required List<Person> persons,
  required Iterable<String?> names,
}) {
  final existing = {for (final p in persons) personNameKey(p.name)};
  final seen = <String>{};
  final out = <String>[];
  for (final raw in names) {
    final n = raw?.trim();
    if (n == null || n.isEmpty) continue;
    final key = personNameKey(n);
    if (existing.contains(key) || !seen.add(key)) continue;
    out.add(n);
  }
  return out;
}

/// Dropdown: existing named people + New person + pending draft names.
class PersonAssignControl extends StatelessWidget {
  const PersonAssignControl({
    super.key,
    required this.persons,
    required this.onAssign,
    this.currentPersonId,
    this.currentPersonName,
    this.draftPersonNames = const [],
    this.enabled = true,
    this.label = 'Assign to person',
  });

  static const newPersonSentinel = '__new_person__';
  static const draftNamePrefix = '__draft__:';

  static String draftValue(String name) => '$draftNamePrefix${name.trim()}';

  static String? nameFromDraftValue(String value) {
    if (!value.startsWith(draftNamePrefix)) return null;
    final name = value.substring(draftNamePrefix.length).trim();
    return name.isEmpty ? null : name;
  }

  final List<Person> persons;
  final String? currentPersonId;
  final String? currentPersonName;
  final List<String> draftPersonNames;
  final bool enabled;
  final String label;
  final Future<void> Function({String? personId, String? name}) onAssign;

  @override
  Widget build(BuildContext context) {
    final drafts = uniqueDraftPersonNames(
      persons: persons,
      names: [currentPersonName, ...draftPersonNames],
    );
    final current = currentPersonId;
    final known = current != null && persons.any((p) => p.id == current);
    final named = currentPersonName?.trim();
    final matchingPerson = named != null && named.isNotEmpty
        ? findPersonByName(persons, named)
        : null;
    final matchingDraft = named != null && named.isNotEmpty
        ? _matchingDraftName(drafts, named)
        : null;
    final value = known
        ? current
        : matchingPerson != null
            ? matchingPerson.id
            : matchingDraft != null
                ? draftValue(matchingDraft)
                : null;
    return DropdownButtonFormField<String>(
      // ignore: deprecated_member_use — value is stable across Flutter versions
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        const DropdownMenuItem(
          value: newPersonSentinel,
          child: Text('New person'),
        ),
        for (final name in drafts)
          DropdownMenuItem(
            value: draftValue(name),
            child: Text(name, key: Key('person-assign-draft-$name')),
          ),
        for (final person in persons)
          DropdownMenuItem(
            value: person.id,
            child: Text(person.name),
          ),
      ],
      onChanged: !enabled
          ? null
          : (selected) async {
              if (selected == null) return;
              if (selected == newPersonSentinel) {
                final resolved = await promptAssignPerson(
                  context,
                  persons: persons,
                  draftPersonNames: drafts,
                );
                if (resolved == null) return;
                await onAssign(
                  personId: resolved.personId,
                  name: resolved.name,
                );
                return;
              }
              final draftName = nameFromDraftValue(selected);
              if (draftName != null) {
                await onAssign(name: draftName);
                return;
              }
              await onAssign(personId: selected);
            },
    );
  }
}
