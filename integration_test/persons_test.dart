// D9 Person Linking UI integration: named-person list, reassign to a new
// named person, unassign against mocked API (§5). Every Person is always
// named (R2) — there is no unnamed grouping to test here.
//   flutter test integration_test/persons_test.dart -d macos
//   flutter test integration_test/persons_test.dart -d windows

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/main.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/persons/collections_store.dart';

import '../test/fake_items_repository.dart';
import '../test/fake_jobs_repository.dart';
import '../test/fake_persons_repository.dart';
import '../test/fake_usage_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'persons: named list; reassign to new named person; unassign; delete',
      (WidgetTester tester) async {
    final item = fixtureItem(
      id: 'item_p',
      processingStatus: ProcessingStatus.tagged,
    );
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
      ],
    );
    final items = FakeItemsRepository(items: [item]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          testSessionProvider.overrideWithValue(
            const TestSession(
              token: 'integration-token',
              account: Account(
                id: 'acc_integration',
                email: 'integration@example.com',
                createdAt: '2026-07-18T00:00:00.000Z',
              ),
            ),
          ),
          itemsRepositoryProvider.overrideWithValue(items),
          usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
          jobsRepositoryProvider.overrideWithValue(
            FakeJobsRepository(itemId: 'item_p', item: item),
          ),
          personsRepositoryProvider.overrideWithValue(persons),
          collectionsStoreProvider.overrideWithValue(MemoryCollectionsStore()),
        ],
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Open Persons from the signed-in app bar.
    await tester.tap(find.byKey(const Key('nav-persons')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('persons-list')), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);

    // Open person detail.
    await tester.tap(find.byKey(const Key('person-row-person_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('person-detail')), findsOneWidget);

    // Reassign an appearance onto a brand-new named person — creating a
    // person always requires a name (R2), so the reassign button opens a
    // name dialog before calling the API.
    await tester.tap(find.byKey(const Key('appearance-reassign-select-ap_2')));
    await tester.pumpAndSettle();
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

    // Unassign the remaining appearance (undo path).
    await tester.tap(find.byKey(const Key('appearance-unassign-ap_1')));
    await tester.pumpAndSettle();
    expect(persons.unlinkCalls, ['ap_1']);

    // Unassign the (now empty) person.
    await tester.tap(find.byKey(const Key('person-unassign')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('person-unassign-confirm')));
    await tester.pumpAndSettle();
    expect(persons.deleteCalls, ['person_1']);

    // Back to the list — the person created from reassignment is named too.
    expect(find.byKey(const Key('persons-list')), findsOneWidget);
    expect(find.text('Riley'), findsOneWidget);
  });
}
