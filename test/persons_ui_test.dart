import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/persons/person_detail_page.dart';
import 'package:tagkin_desktop/persons/person_name_dialog.dart';
import 'package:tagkin_desktop/persons/persons_list_page.dart';

import 'fake_persons_repository.dart';

void main() {
  testWidgets('persons list renders suggested vs confirmed sections',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_s',
          name: 'Suggested Sam',
          linkState: LinkState.suggested,
        ),
        fixturePersonDetail(
          id: 'person_c',
          name: 'Confirmed Chris',
          linkState: LinkState.confirmed,
          appearances: [
            fixtureAppearance(
              id: 'ap_c',
              personId: 'person_c',
              linkState: LinkState.confirmed,
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
    expect(find.byKey(const Key('persons-section-suggested')), findsOneWidget);
    expect(find.byKey(const Key('persons-section-confirmed')), findsOneWidget);
    expect(find.text('Suggested Sam'), findsOneWidget);
    expect(find.text('Confirmed Chris'), findsOneWidget);
    expect(find.byKey(const Key('person-row-person_s')), findsOneWidget);
    expect(find.byKey(const Key('person-row-person_c')), findsOneWidget);
  });

  testWidgets('person detail: confirm then disables Confirm button',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_1',
          name: 'Sam',
          linkState: LinkState.suggested,
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

    expect(find.byKey(const Key('person-detail')), findsOneWidget);
    expect(find.byKey(const Key('person-detail-name')), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
    expect(find.byKey(const Key('person-confirm')), findsOneWidget);

    await tester.tap(find.byKey(const Key('person-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('person-confirm')), findsNothing);
    expect(find.byKey(const Key('link-state-confirmed')), findsWidgets);
    expect(persons.confirmCalls, ['person_1']);
  });

  testWidgets('person detail: rename round-trips', (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_1',
          name: 'Sam',
          linkState: LinkState.confirmed,
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

    // Already confirmed — no Confirm button.
    expect(find.byKey(const Key('person-confirm')), findsNothing);

    await tester.tap(find.byKey(const Key('person-rename')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('person-rename-field')),
      'Samantha',
    );
    await tester.tap(find.byKey(const Key('person-rename-save')));
    await tester.pumpAndSettle();

    expect(find.text('Samantha'), findsOneWidget);
    expect(persons.renameCalls.single.name, 'Samantha');
  });

  testWidgets('person detail: unnamed shows name field by default',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_1',
          name: null,
          linkState: LinkState.suggested,
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
    await tester.tap(find.byKey(const Key('person-rename-save')));
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

  testWidgets('person detail: unlink / split controls present (R6)',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_1',
          name: 'Sam',
          linkState: LinkState.suggested,
          appearances: [
            fixtureAppearance(id: 'ap_1', personId: 'person_1'),
            fixtureAppearance(id: 'ap_2', personId: 'person_1'),
          ],
        ),
        fixturePersonDetail(
          id: 'person_2',
          name: 'Alex',
          linkState: LinkState.confirmed,
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

    expect(find.byKey(const Key('appearance-unlink-ap_1')), findsOneWidget);
    expect(find.byKey(const Key('appearance-split-ap_1')), findsOneWidget);
    expect(
      find.byKey(const Key('appearance-reassign-ap_1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('appearance-split-ap_2')));
    await tester.pumpAndSettle();
    expect(persons.splitCalls.single.appearanceIds, ['ap_2']);
  });
}
