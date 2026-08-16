import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/persons/person_detail_page.dart';
import 'package:tagkin_desktop/persons/person_name_dialog.dart';
import 'package:tagkin_desktop/persons/persons_list_page.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';

import 'fake_persons_repository.dart';

void main() {
  testWidgets('persons list renders every (always-named) person',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(id: 'person_s', name: 'Sam'),
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
          desktopPrefsProvider.overrideWithValue(const DesktopPrefs()),
        ],
        child: const MaterialApp(home: PersonsListPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('persons-list')), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('Confirmed Chris'), findsOneWidget);
    expect(find.byKey(const Key('person-row-person_s')), findsOneWidget);
    expect(find.byKey(const Key('person-row-person_c')), findsOneWidget);
    final grid = tester.widget<GridView>(find.byKey(const Key('persons-list')));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 5);
  });

  testWidgets('persons list sorts A–Z case-insensitively', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(id: 'p_z', name: 'zoe'),
        fixturePersonDetail(id: 'p_a', name: 'Ada'),
        fixturePersonDetail(id: 'p_b', name: 'bob'),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          desktopPrefsProvider.overrideWithValue(const DesktopPrefs()),
        ],
        child: const MaterialApp(home: PersonsListPage()),
      ),
    );
    await tester.pumpAndSettle();

    final ada = tester.getTopLeft(find.byKey(const Key('person-row-p_a')));
    final bob = tester.getTopLeft(find.byKey(const Key('person-row-p_b')));
    final zoe = tester.getTopLeft(find.byKey(const Key('person-row-p_z')));
    expect(ada.dx, lessThan(bob.dx));
    expect(bob.dx, lessThan(zoe.dx));
    expect(ada.dy, bob.dy);
    expect(bob.dy, zoe.dy);
  });

  testWidgets('persons list uses Settings column count', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(id: 'p_a', name: 'Ada'),
        fixturePersonDetail(id: 'p_b', name: 'Bob'),
        fixturePersonDetail(id: 'p_c', name: 'Cara'),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          desktopPrefsProvider.overrideWithValue(
            const DesktopPrefs(personsListColumns: 2),
          ),
        ],
        child: const MaterialApp(home: PersonsListPage()),
      ),
    );
    await tester.pumpAndSettle();

    final grid = tester.widget<GridView>(find.byKey(const Key('persons-list')));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);
    final ada = tester.getTopLeft(find.byKey(const Key('person-row-p_a')));
    final bob = tester.getTopLeft(find.byKey(const Key('person-row-p_b')));
    final cara = tester.getTopLeft(find.byKey(const Key('person-row-p_c')));
    expect(ada.dy, bob.dy);
    expect(ada.dx, lessThan(bob.dx));
    expect(cara.dy, greaterThan(ada.dy));
  });

  testWidgets(
      'persons list reloads when returning to the Persons tab after a rename',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(id: 'person_s', name: 'Sam'),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        personsRepositoryProvider.overrideWithValue(persons),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PersonsListPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sam'), findsOneWidget);

    await persons.renamePerson('person_s', 'Riley');
    container.read(activeTopLevelTabProvider.notifier).state =
        TopLevelTab.faces;
    await tester.pump();
    container.read(activeTopLevelTabProvider.notifier).state =
        TopLevelTab.persons;
    await tester.pumpAndSettle();

    expect(find.text('Riley'), findsOneWidget);
    expect(find.text('Sam'), findsNothing);
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

  testWidgets('person detail: rename onto existing name offers merge',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_1',
          name: 'Sam',
          appearances: [
            fixtureAppearance(id: 'ap_s', personId: 'person_1'),
          ],
        ),
        fixturePersonDetail(
          id: 'person_2',
          name: 'Alex',
          appearances: [
            fixtureAppearance(id: 'ap_a', personId: 'person_2'),
          ],
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
      'alex',
    );
    await tester.tap(find.byKey(const Key('person-rename-done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('face-crop-rename-collision')), findsOneWidget);
    await tester.tap(find.byKey(const Key('face-crop-rename-collision-merge')));
    await tester.pumpAndSettle();

    expect(persons.mergeCalls, hasLength(1));
    expect(persons.mergeCalls.single.personId, 'person_1');
    expect(persons.mergeCalls.single.targetPersonId, 'person_2');
    expect(persons.renameCalls, isEmpty);
  });

  testWidgets('person detail: rename requires a non-empty name (R2)',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(id: 'person_1', name: 'Sam'),
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
      '   ',
    );
    await tester.tap(find.byKey(const Key('person-rename-done')));
    await tester.pumpAndSettle();

    // No API call for a blank name; editing stays open with the old name.
    expect(persons.renameCalls, isEmpty);
    expect(find.byKey(const Key('person-rename-field')), findsOneWidget);
    expect(find.byKey(const Key('person-action-error')), findsOneWidget);
  });

  testWidgets('person detail: unassign pops page', (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(id: 'person_1', name: 'Sam'),
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
    expect(
      find.byKey(const Key('appearance-reassign-ap_1')),
      findsOneWidget,
    );

    // Reassign ap_2 to a brand-new named person via dropdown + name dialog.
    await tester.tap(find.byKey(const Key('appearance-reassign-select-ap_2')));
    await tester.pumpAndSettle();
    expect(find.text('New person'), findsWidgets);
    await tester.tap(find.text('New person').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('appearance-reassign-ap_2')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('person-name-dialog')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('person-name-field')),
      'Riley',
    );
    await tester.tap(find.byKey(const Key('person-name-save')));
    await tester.pumpAndSettle();

    expect(persons.reassignCalls.single.appearanceId, 'ap_2');
    expect(persons.reassignCalls.single.personId, isNull);
    expect(persons.reassignCalls.single.name, 'Riley');
  });

  testWidgets(
      'person detail: reassign to an existing person needs no name prompt',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_1',
          name: 'Sam',
          appearances: [
            fixtureAppearance(id: 'ap_1', personId: 'person_1'),
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

    await tester.tap(find.byKey(const Key('appearance-reassign-select-ap_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alex').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('appearance-reassign-ap_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('person-name-dialog')), findsNothing);
    expect(persons.reassignCalls.single.appearanceId, 'ap_1');
    expect(persons.reassignCalls.single.personId, 'person_2');
    expect(persons.reassignCalls.single.name, isNull);
  });
}
