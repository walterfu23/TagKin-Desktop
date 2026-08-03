import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/config/app_config.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/items_list_page.dart';
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

List<Override> _signedInOverrides() => [
      testSessionProvider.overrideWithValue(
        TestSession(token: 'tok', account: _account('acc_1')),
      ),
      itemsRepositoryProvider.overrideWithValue(FakeItemsRepository()),
      usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
      jobsRepositoryProvider.overrideWithValue(FakeJobsRepository()),
      personsRepositoryProvider.overrideWithValue(FakePersonsRepository()),
      collectionsStoreProvider.overrideWithValue(MemoryCollectionsStore()),
    ];

void main() {
  testWidgets('valid session populates account and shows items library',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _signedInOverrides(),
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('items-empty')), findsOneWidget);
    expect(find.byKey(const Key('account-label')), findsOneWidget);
    expect(find.text('acc_1@example.com'), findsOneWidget);
    expect(find.byKey(const Key('nav-folders')), findsOneWidget);
    expect(find.byKey(const Key('nav-face-crops')), findsOneWidget);
    expect(find.byKey(const Key('nav-persons')), findsOneWidget);
    expect(find.byKey(const Key('shell-collection-label')), findsOneWidget);
    expect(find.text('Collection1'), findsOneWidget);
    // Folders → Faces → Persons in the AppBar actions.
    final folders = tester.getTopLeft(find.byKey(const Key('nav-folders')));
    final faceCrops =
        tester.getTopLeft(find.byKey(const Key('nav-face-crops')));
    final persons = tester.getTopLeft(find.byKey(const Key('nav-persons')));
    expect(folders.dx, lessThan(faceCrops.dx));
    expect(faceCrops.dx, lessThan(persons.dx));
  });

  testWidgets('top-level tabs switch Folders / Faces / Persons without push',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _signedInOverrides(),
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('items-empty')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav-persons')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('persons-empty')), findsOneWidget);
    // Still one route — tabs do not push.
    expect(find.byType(BackButton), findsNothing);

    await tester.tap(find.byKey(const Key('nav-face-crops')));
    await tester.pumpAndSettle();
    expect(find.text('Faces'), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav-folders')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('items-empty')), findsOneWidget);
  });

  testWidgets('401 on /me surfaces unauthorized — no crash, no retry loop',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          testSessionProvider.overrideWithValue(
            TestSession(
              token: 'expired',
              meError: UnauthorizedException(message: 'Expired'),
            ),
          ),
          itemsRepositoryProvider.overrideWithValue(FakeItemsRepository()),
          collectionsStoreProvider.overrideWithValue(MemoryCollectionsStore()),
        ],
        child: const MaterialApp(
          home: AuthShell(
            signedInHome: ItemsListPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('auth-unauthorized')), findsOneWidget);
    expect(find.byKey(const Key('items-list')), findsNothing);
    expect(find.byKey(const Key('items-empty')), findsNothing);
  });

  testWidgets('missing Clerk key shows configure prompt (no crash)',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(apiUrl: 'http://localhost:8787'),
          ),
        ],
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('missing-clerk-config')), findsOneWidget);
  });
}
