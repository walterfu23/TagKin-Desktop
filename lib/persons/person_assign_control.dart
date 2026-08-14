import 'package:flutter/material.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/persons/person_name.dart';
import 'package:tagkin_desktop/persons/person_name_collision_dialog.dart';
import 'package:tagkin_desktop/persons/person_name_dialog.dart';

/// Prompt for a new person name, offering merge on collision (R6).
Future<({String? personId, String? name})?> promptAssignPerson(
  BuildContext context, {
  required List<Person> persons,
  String mergeLabel = 'Merge into that person',
}) async {
  var typed = await showPersonNameDialog(context);
  if (!context.mounted) return null;
  while (typed != null) {
    final clash = findPersonByName(persons, typed);
    if (clash == null) return (personId: null, name: typed);
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
  }
  return null;
}

/// Dropdown: existing named people + New person.
class PersonAssignControl extends StatelessWidget {
  const PersonAssignControl({
    super.key,
    required this.persons,
    required this.onAssign,
    this.currentPersonId,
    this.enabled = true,
    this.label = 'Assign to person',
  });

  static const newPersonSentinel = '__new_person__';

  final List<Person> persons;
  final String? currentPersonId;
  final bool enabled;
  final String label;
  final Future<void> Function({String? personId, String? name}) onAssign;

  @override
  Widget build(BuildContext context) {
    final current = currentPersonId;
    final known = current != null && persons.any((p) => p.id == current);
    return DropdownButtonFormField<String>(
      // ignore: deprecated_member_use — value is stable across Flutter versions
      value: known ? current : null,
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
        for (final person in persons)
          DropdownMenuItem(
            value: person.id,
            child: Text(person.name),
          ),
      ],
      onChanged: !enabled
          ? null
          : (value) async {
              if (value == null) return;
              if (value == newPersonSentinel) {
                final resolved = await promptAssignPerson(
                  context,
                  persons: persons,
                );
                if (resolved == null) return;
                await onAssign(
                  personId: resolved.personId,
                  name: resolved.name,
                );
                return;
              }
              await onAssign(personId: value);
            },
    );
  }
}
