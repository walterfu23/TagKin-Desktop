// D7 Tagging & Jobs Lifecycle integration: photo-detail Status matches
// Folders; delete against fake JobsRepository (mocked API per §5).
//   flutter test integration_test/jobs_lifecycle_test.dart -d macos
//   flutter test integration_test/jobs_lifecycle_test.dart -d windows

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/main.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/persons/collections_store.dart';

import '../test/fake_comments_repository.dart';
import '../test/fake_corrections_repository.dart';
import '../test/fake_items_repository.dart';
import '../test/fake_jobs_repository.dart';
import '../test/fake_usage_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('photo detail shows Folders status; delete removes from list',
      (WidgetTester tester) async {
    final item = fixtureItem(
      id: 'item_int',
      analysisRef: 'ref_int',
      analysisRefState: AnalysisRefState.ready,
      processingStatus: ProcessingStatus.failed,
    );
    final items = FakeItemsRepository(items: [item]);
    final jobs = FakeJobsRepository(
      itemId: 'item_int',
      item: item,
      onDelete: items.removeItem,
    );

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
          correctionsRepositoryProvider.overrideWithValue(
            FakeCorrectionsRepository(items: items),
          ),
          commentsRepositoryProvider.overrideWithValue(
            FakeCommentsRepository(),
          ),
          usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
          jobsRepositoryProvider.overrideWithValue(jobs),
          collectionsStoreProvider.overrideWithValue(MemoryCollectionsStore()),
        ],
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('item-row-item_int')), findsOneWidget);
    expect(find.byKey(const Key('processing-status-failed')), findsOneWidget);

    await tester.tap(find.byKey(const Key('item-row-item_int')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('processing-status-failed')), findsOneWidget);
    expect(find.byKey(const Key('item-analyze')), findsNothing);
    expect(find.byKey(const Key('item-retry-job')), findsNothing);
    expect(find.byKey(const Key('item-cancel-job')), findsNothing);
    expect(find.text('Tagging & jobs'), findsNothing);

    await tester.tap(find.byKey(const Key('item-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-remove-confirm')));
    await tester.pumpAndSettle();
    expect(jobs.deleteCallCount, 1);
    expect(find.byKey(const Key('item-row-item_int')), findsNothing);
  });
}
