// Repro/regression coverage for: after Cancel on the "Unsaved collection"
// dirty-leave prompt, Sign out (and other AppBar controls) reportedly went
// unresponsive. This drives the exact user-reported sequence — sign in with
// a dirty collection, tap Sign out, tap Cancel, tap Sign out again — through
// the real widget tree (including main.dart's app-wide SelectableScope) so a
// stuck gesture arena / hit-test regression shows up without manual clicking.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/main.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/persons/collections_store.dart';

import 'fake_items_repository.dart';
import 'fake_jobs_repository.dart';
import 'fake_persons_repository.dart';
import 'fake_usage_repository.dart';

Account _account(String id) => Account(
      id: id,
      email: '$id@example.com',
      createdAt: '2026-07-18T00:00:00.000Z',
    );

void main() {
  testWidgets(
      'Cancel on dirty-leave prompt leaves Sign out clickable for a second try',
      (tester) async {
    var signOutCalls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          testSessionProvider.overrideWithValue(
            TestSession(
              token: 'tok',
              account: _account('acc_1'),
              onSignOut: () async {
                signOutCalls++;
              },
            ),
          ),
          itemsRepositoryProvider.overrideWithValue(FakeItemsRepository()),
          usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
          jobsRepositoryProvider.overrideWithValue(FakeJobsRepository()),
          personsRepositoryProvider.overrideWithValue(FakePersonsRepository()),
          collectionsStoreProvider.overrideWithValue(MemoryCollectionsStore()),
        ],
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sign-out')), findsOneWidget);

    // Mark the collection dirty via the same container the shell reads from
    // (nested ProviderScope created once signed in), mirroring real dirty
    // state (e.g. a Faces move) without needing to drive that whole flow.
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('sign-out'))),
    );
    container.read(collectionsControllerProvider).markDirty();
    await tester.pump();
    expect(find.byKey(const Key('shell-collection-label')), findsOneWidget);
    expect(find.textContaining('*'), findsOneWidget);

    // 1st Sign out -> dirty prompt appears.
    await tester.tap(find.byKey(const Key('sign-out')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('collection-dirty-dialog')), findsOneWidget);

    // Cancel -> dialog closes, nothing signed out.
    await tester.tap(find.byKey(const Key('collection-dirty-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('collection-dirty-dialog')), findsNothing);
    expect(signOutCalls, 0);

    // 2nd Sign out -> must still be responsive and re-show the prompt.
    await tester.tap(find.byKey(const Key('sign-out')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('collection-dirty-dialog')),
      findsOneWidget,
      reason: 'Sign out went unresponsive after Cancel',
    );

    // Sanity: a different AppBar control is also still responsive.
    await tester.tap(find.byKey(const Key('collection-dirty-cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-persons')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('persons-empty')), findsOneWidget);
  });
}
