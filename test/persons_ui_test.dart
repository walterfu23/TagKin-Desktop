import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/persons/person_detail_page.dart';
import 'package:tagkin_desktop/persons/person_name_dialog.dart';
import 'package:tagkin_desktop/persons/persons_list_page.dart';

import 'fake_persons_repository.dart';

void main() {
  testWidgets('persons list renders named vs unnamed sections',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_s',
          name: null,
        ),
        fixturePersonDetail(
          id: 'person_c',
          name: 'Confirmed Chris',
          appearances: [
            fixtureAppearance(
              id: 'ap_c',
              personId: 'person_c',
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
        ],
        child: const MaterialApp(home: PersonsListPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('persons-list')), findsOneWidget);
    expect(find.byKey(const Key('persons-section-named')), findsOneWidget);
    expect(find.byKey(const Key('persons-section-unnamed')), findsOneWidget);
    expect(find.text('Confirmed Chris'), findsOneWidget);
    expect(find.byKey(const Key('person-row-person_s')), findsOneWidget);
    expect(find.byKey(const Key('person-row-person_c')), findsOneWidget);
  });

  testWidgets('person detail: rename round-trips', (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_1',
          name: 'Sam',
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
        ],
        child: const MaterialApp(
          home: PersonDetailPage(personId: 'person_1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('person-rename')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('person-rename-field')),
      'Samantha',
    );
    await tester.tap(find.byKey(const Key('person-rename-done')));
    await tester.pumpAndSettle();

    expect(find.text('Samantha'), findsOneWidget);
    expect(persons.renameCalls.single.name, 'Samantha');
  });

  testWidgets('person detail: unassign pops page', (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_1',
          name: null,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const Key('open-person'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const PersonDetailPage(
                        personId: 'person_1',
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-person')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('person-unassign')), findsOneWidget);

    await tester.tap(find.byKey(const Key('person-unassign')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('person-unassign-confirm')));
    await tester.pumpAndSettle();

    expect(persons.deleteCalls, ['person_1']);
    expect(find.byKey(const Key('person-detail')), findsNothing);
    expect(find.byKey(const Key('open-person')), findsOneWidget);
  });

  testWidgets('person detail: unnamed shows name field by default',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_1',
          name: null,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
        ],
        child: const MaterialApp(
          home: PersonDetailPage(personId: 'person_1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('(unnamed)'), findsOneWidget);
    expect(find.byKey(const Key('person-rename')), findsNothing);
    expect(find.byKey(const Key('person-rename-field')), findsOneWidget);
    expect(find.byKey(const Key('person-rename-cancel')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('person-rename-field')),
      'Alex',
    );
    await tester.tap(find.byKey(const Key('person-rename-done')));
    await tester.pumpAndSettle();

    expect(find.text('Alex'), findsOneWidget);
    expect(persons.renameCalls.single.name, 'Alex');
    expect(find.byKey(const Key('person-rename')), findsOneWidget);
  });

  testWidgets('person name dialog: save returns trimmed name', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('open-name-dialog'),
              onPressed: () async {
                result = await showPersonNameDialog(context);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-name-dialog')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('person-name-dialog')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('person-name-field')),
      '  Jordan  ',
    );
    await tester.tap(find.byKey(const Key('person-name-save')));
    await tester.pumpAndSettle();

    expect(result, 'Jordan');
  });

  testWidgets('person detail: unassign / reassign controls present (R6)',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_1',
          name: 'Sam',
          appearances: [
            fixtureAppearance(id: 'ap_1', personId: 'person_1'),
            fixtureAppearance(id: 'ap_2', personId: 'person_1'),
          ],
        ),
        fixturePersonDetail(
          id: 'person_2',
          name: 'Alex',
          appearances: const [],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
        ],
        child: const MaterialApp(
          home: PersonDetailPage(personId: 'person_1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('appearance-unassign-ap_1')), findsOneWidget);
    expect(find.byKey(const Key('appearance-split-ap_1')), findsNothing);
    expect(
      find.byKey(const Key('appearance-reassign-ap_1')),
      findsOneWidget,
    );

    // Reassign ap_2 to new person via dropdown + button.
    await tester.tap(find.byKey(const Key('appearance-reassign-select-ap_2')));
    await tester.pumpAndSettle();
    expect(find.text('New person'), findsWidgets);
    await tester.tap(find.text('New person').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('appearance-reassign-ap_2')));
    await tester.pumpAndSettle();
    expect(persons.reassignCalls.single.appearanceId, 'ap_2');
    expect(persons.reassignCalls.single.personId, isNull);
  });
}
