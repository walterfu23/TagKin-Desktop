// D9 Person Linking UI integration: suggested → Save, reassign new, unassign
// against mocked API (§5).
//   flutter test integration_test/persons_test.dart -d macos
//   flutter test integration_test/persons_test.dart -d windows

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/main.dart';

import '../test/fake_items_repository.dart';
import '../test/fake_jobs_repository.dart';
import '../test/fake_persons_repository.dart';
import '../test/fake_usage_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'persons: Save suggested → confirmed; reassign new; unassign',
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
          linkState: LinkState.suggested,
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
        ],
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Open Persons from the signed-in app bar.
    await tester.tap(find.byKey(const Key('nav-persons')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('persons-list')), findsOneWidget);
    expect(find.byKey(const Key('persons-section-suggested')), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);

    // Open person detail and Save.
    await tester.tap(find.byKey(const Key('person-row-person_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('person-detail')), findsOneWidget);
    expect(find.byKey(const Key('person-save')), findsOneWidget);
    await tester.tap(find.byKey(const Key('person-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('person-save')), findsNothing);
    expect(persons.confirmCalls, ['person_1']);

    // Reassign an appearance onto a new person.
    await tester.tap(find.byKey(const Key('appearance-reassign-select-ap_2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New person').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('appearance-reassign-ap_2')));
    await tester.pumpAndSettle();
    expect(persons.reassignCalls.single.appearanceId, 'ap_2');
    expect(persons.reassignCalls.single.personId, isNull);

    // Unassign the remaining appearance (undo path).
    await tester.tap(find.byKey(const Key('appearance-unassign-ap_1')));
    await tester.pumpAndSettle();
    expect(persons.unlinkCalls, ['ap_1']);

    // Back to list — confirmed section should include Sam.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('persons-section-confirmed')), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
  });
}
