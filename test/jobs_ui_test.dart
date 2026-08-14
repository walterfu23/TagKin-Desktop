import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/item_detail_page.dart';
import 'package:tagkin_desktop/main.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/persons/collections_store.dart';

import 'fake_comments_repository.dart';
import 'fake_corrections_repository.dart';
import 'fake_items_repository.dart';
import 'fake_jobs_repository.dart';
import 'fake_persons_repository.dart';
import 'fake_usage_repository.dart';

Account _account(String id) => Account(
      id: id,
      email: '$id@example.com',
      createdAt: '2026-07-18T00:00:00.000Z',
    );

List<Override> _overrides({
  required FakeItemsRepository items,
  required FakeJobsRepository jobs,
  FakeUsageRepository? usage,
}) {
  return [
    testSessionProvider.overrideWithValue(
      TestSession(token: 'tok', account: _account('acc_1')),
    ),
    itemsRepositoryProvider.overrideWithValue(items),
    correctionsRepositoryProvider.overrideWithValue(
      FakeCorrectionsRepository(items: items),
    ),
    commentsRepositoryProvider.overrideWithValue(FakeCommentsRepository()),
    usageRepositoryProvider.overrideWithValue(
      usage ?? FakeUsageRepository(),
    ),
    jobsRepositoryProvider.overrideWithValue(jobs),
    personsRepositoryProvider.overrideWithValue(FakePersonsRepository()),
    collectionsStoreProvider.overrideWithValue(MemoryCollectionsStore()),
  ];
}

void main() {
  testWidgets('photo detail has no Analyze button', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final item = fixtureItem(
      id: 'item_1',
      analysisRef: 'ref_1',
      analysisRefState: AnalysisRefState.ready,
      processingStatus: ProcessingStatus.awaitingModelAccess,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(
          items: FakeItemsRepository(items: [item]),
          jobs: FakeJobsRepository(itemId: 'item_1', item: item),
        ),
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('item-what-item_1')));
    await tester.tap(find.byKey(const Key('item-what-item_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('item-analyze')), findsNothing);
    expect(find.byKey(const Key('reanalyze-warning-dialog')), findsNothing);
    expect(find.text('Tagging & jobs'), findsNothing);
    expect(find.byKey(const Key('job-progress')), findsNothing);
    expect(
      find.byKey(const Key('processing-status-awaiting_model_access')),
      findsOneWidget,
    );
  });

  testWidgets('failed photo detail shows Folders status; no job Retry',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final item = fixtureItem(
      id: 'item_fail',
      analysisRef: 'ref_fail',
      analysisRefState: AnalysisRefState.ready,
      processingStatus: ProcessingStatus.failed,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(
          items: FakeItemsRepository(items: [item]),
          jobs: FakeJobsRepository(itemId: 'item_fail', item: item),
        ),
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('processing-status-failed')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('item-what-item_fail')));
    await tester.tap(find.byKey(const Key('item-what-item_fail')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('processing-status-failed')), findsOneWidget);
    expect(find.byKey(const Key('item-retry-job')), findsNothing);
    expect(find.byKey(const Key('item-cancel-job')), findsNothing);
    expect(find.byKey(const Key('item-reupload')), findsNothing);
    expect(find.text('Tagging & jobs'), findsNothing);
  });

  testWidgets('video detail has no Analyze button', (tester) async {
    final item = fixtureItem(id: 'item_v', type: ItemType.video);
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(
          items: FakeItemsRepository(items: [item]),
          jobs: FakeJobsRepository(itemId: 'item_v', item: item),
        ),
        child: const MaterialApp(
          home: ItemDetailPage(itemId: 'item_v'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('item-analyze')), findsNothing);
    expect(find.byKey(const Key('analyze-photo-only-hint')), findsNothing);
  });

  testWidgets('Delete confirms and pops with deleted result', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final item = fixtureItem(id: 'item_del');
    final items = FakeItemsRepository(items: [item]);
    final jobs = FakeJobsRepository(
      itemId: 'item_del',
      item: item,
      onDelete: items.removeItem,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(
          items: items,
          jobs: jobs,
        ),
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('item-what-item_del')));
    await tester.tap(find.byKey(const Key('item-what-item_del')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('item-delete')));
    await tester.pump();
    expect(find.text('Sure?'), findsOneWidget);
    expect(find.text('Delete item?'), findsNothing);
    await tester.tap(find.byKey(const Key('item-remove-confirm')));
    await tester.pumpAndSettle();

    expect(jobs.deleteCallCount, 1);
    // Back on list — deleted item gone after refresh.
    expect(find.byKey(const Key('item-row-item_del')), findsNothing);
  });

  testWidgets('tagged photo has no Analyze or re-analyze dialog',
      (tester) async {
    final item = fixtureItem(
      id: 'item_tagged',
      analysisRef: 'ref_1',
      analysisRefState: AnalysisRefState.ready,
      processingStatus: ProcessingStatus.tagged,
    );
    final jobs = FakeJobsRepository(itemId: 'item_tagged', item: item);
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(
          items: FakeItemsRepository(items: [item]),
          jobs: jobs,
        ),
        child: const MaterialApp(
          home: ItemDetailPage(itemId: 'item_tagged'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('item-analyze')), findsNothing);
    expect(find.byKey(const Key('reanalyze-warning-dialog')), findsNothing);
    expect(jobs.analyzeCallCount, 0);
  });

  testWidgets('photo detail has no Re-upload or job controls', (tester) async {
    final item = fixtureItem(
      id: 'item_exp',
      analysisRef: 'files/old',
      analysisRefState: AnalysisRefState.expired,
      processingStatus: ProcessingStatus.tagged,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(
          items: FakeItemsRepository(items: [item]),
          jobs: FakeJobsRepository(itemId: 'item_exp', item: item),
        ),
        child: const MaterialApp(
          home: ItemDetailPage(itemId: 'item_exp'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('processing-status-tagged')), findsOneWidget);
    expect(find.byKey(const Key('item-reupload')), findsNothing);
    expect(find.byKey(const Key('reupload-hint')), findsNothing);
    expect(find.byKey(const Key('item-retry-job')), findsNothing);
    expect(find.byKey(const Key('item-cancel-job')), findsNothing);
    expect(find.text('Tagging & jobs'), findsNothing);
  });
}
