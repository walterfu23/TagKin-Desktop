import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/item_detail_page.dart';
import 'package:tagkin_desktop/library/items_list_page.dart';
import 'package:tagkin_desktop/main.dart';

import 'fake_comments_repository.dart';
import 'fake_corrections_repository.dart';
import 'fake_items_repository.dart';
import 'fake_jobs_repository.dart';
import 'fake_usage_repository.dart';

Account _account(String id) => Account(
      id: id,
      email: '$id@example.com',
      createdAt: '2026-07-18T00:00:00.000Z',
    );

List<Override> _sessionOverrides({
  required FakeItemsRepository items,
  String accountId = 'acc_1',
  String token = 'tok',
  FakeUsageRepository? usage,
  FakeJobsRepository? jobs,
}) {
  return [
    testSessionProvider.overrideWithValue(
      TestSession(token: token, account: _account(accountId)),
    ),
    itemsRepositoryProvider.overrideWithValue(items),
    correctionsRepositoryProvider.overrideWithValue(
      FakeCorrectionsRepository(items: items),
    ),
    commentsRepositoryProvider.overrideWithValue(FakeCommentsRepository()),
    usageRepositoryProvider.overrideWithValue(
      usage ?? FakeUsageRepository(),
    ),
    jobsRepositoryProvider.overrideWithValue(
      jobs ?? FakeJobsRepository(),
    ),
  ];
}

void main() {
  testWidgets('items list renders fixture items with processingStatus',
      (tester) async {
    final items = [
      fixtureItem(id: 'item_1', processingStatus: ProcessingStatus.pending),
      fixtureItem(
        id: 'item_2',
        type: ItemType.video,
        processingStatus: ProcessingStatus.tagged,
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: _sessionOverrides(
          items: FakeItemsRepository(items: items),
        ),
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('items-list')), findsOneWidget);
    expect(find.byKey(const Key('item-row-item_1')), findsOneWidget);
    expect(find.byKey(const Key('item-row-item_2')), findsOneWidget);
    expect(find.byKey(const Key('processing-status-pending')), findsOneWidget);
    expect(find.byKey(const Key('processing-status-tagged')), findsOneWidget);
  });

  testWidgets('empty library shows empty state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _sessionOverrides(items: FakeItemsRepository()),
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('items-empty')), findsOneWidget);
  });

  testWidgets('tap row opens item detail', (tester) async {
    final item = fixtureItem(id: 'item_nav');
    await tester.pumpWidget(
      ProviderScope(
        overrides: _sessionOverrides(
          items: FakeItemsRepository(items: [item]),
        ),
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-row-item_nav')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('item-detail')), findsOneWidget);
    expect(find.byKey(const Key('item-id')), findsOneWidget);
    expect(find.text('item_nav'), findsWidgets);
  });

  testWidgets('foreign item id surfaces not-found without leaking data (R10)',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          itemsRepositoryProvider.overrideWithValue(
            FakeItemsRepository(
              getItemError: ApiException(statusCode: 404, message: 'Not found'),
            ),
          ),
          jobsRepositoryProvider.overrideWithValue(
            FakeJobsRepository(itemId: 'foreign-id'),
          ),
          usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
        ],
        child: const MaterialApp(
          home: ItemDetailPage(itemId: 'foreign-id'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('item-detail-not-found')), findsOneWidget);
    expect(find.textContaining('foreign-id'), findsNothing);
    expect(find.byKey(const Key('item-detail')), findsNothing);
  });

  testWidgets('account A fixture is not shown under account B session (R10)',
      (tester) async {
    // Second fake account only sees its own empty library — never A's items.
    await tester.pumpWidget(
      ProviderScope(
        overrides: _sessionOverrides(
          items: FakeItemsRepository(), // B has no items
          accountId: 'acc_b',
          token: 'tok-b',
        ),
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('items-empty')), findsOneWidget);
    expect(find.byKey(const Key('item-row-item_a')), findsNothing);
    expect(find.text('acc_b@example.com'), findsOneWidget);
  });

  testWidgets('list error shows retry', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _sessionOverrides(
          items: FakeItemsRepository(
            listError: ApiException(statusCode: 500, message: 'boom'),
          ),
        ),
        child: const MaterialApp(
          home: AuthShell(signedInHome: ItemsListPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('items-error')), findsOneWidget);
    expect(find.byKey(const Key('items-retry')), findsOneWidget);
  });
}
