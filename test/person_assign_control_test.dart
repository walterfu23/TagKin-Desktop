import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/persons/person_assign_control.dart';

List<String?> _dropdownValues(WidgetTester tester) {
  final button = tester.widget<DropdownButton<String>>(
    find.byType(DropdownButton<String>),
  );
  return button.items!.map((item) => item.value).toList();
}

void main() {
  testWidgets(
      'PersonAssignControl lists New person, then drafts, then persons A–Z',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PersonAssignControl(
            persons: const [
              Person(id: 'p_z', name: 'zoe', createdAt: ''),
              Person(id: 'p_a', name: 'Ada', createdAt: ''),
            ],
            draftPersonNames: const ['maya', 'Bea'],
            onAssign: ({personId, name}) async {},
          ),
        ),
      ),
    );

    expect(_dropdownValues(tester), [
      PersonAssignControl.newPersonSentinel,
      PersonAssignControl.draftValue('Bea'),
      PersonAssignControl.draftValue('maya'),
      'p_a',
      'p_z',
    ]);
  });
}
