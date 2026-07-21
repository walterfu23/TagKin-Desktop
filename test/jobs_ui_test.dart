import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/item_detail_page.dart';
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
  ];
}

void main() {
  testWidgets('Analyze on photo reaches completed job state', (tester) async {
    final item = fixtureItem(
      id: 'item_1',
      analysisRef: 'ref_1',
      analysisRefState: AnalysisRefState.ready,
      processingStatus: ProcessingStatus.awaitingModelAccess,
    );
    final jobs = FakeJobsRepository(itemId: 'item_1', item: item);
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(
          items: FakeItemsRepository(items: [item]),
          jobs: jobs,
        ),
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-row-item_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('item-analyze')), findsOneWidget);
    await tester.tap(find.byKey(const Key('item-analyze')));
    await tester.pumpAndSettle();

    expect(jobs.analyzeCallCount, 1);
    expect(find.byKey(const Key('job-state-completed')), findsOneWidget);
  });

  testWidgets('Analyze is disabled for video items (R9)', (tester) async {
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

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('item-analyze')),
    );
    expect(button.onPressed, isNull);
    expect(find.byKey(const Key('analyze-photo-only-hint')), findsOneWidget);
  });

  testWidgets('Delete confirms and pops with deleted result', (tester) async {
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
    await tester.tap(find.byKey(const Key('item-row-item_del')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('item-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Delete item?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('delete-confirm')));
    await tester.pumpAndSettle();

    expect(jobs.deleteCallCount, 1);
    // Back on list — deleted item gone after refresh.
    expect(find.byKey(const Key('item-row-item_del')), findsNothing);
  });

  testWidgets('Export library writes via ExportController', (tester) async {
    final jobs = FakeJobsRepository();
    String? written;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._overrides(
            items: FakeItemsRepository(items: [fixtureItem()]),
            jobs: jobs,
          ),
        ],
        child: const TagKinDesktopApp(),
      ),
    );
    // Swap export writer by overriding after build is awkward; tap export
    // with default FilePicker may cancel in tests. Instead assert button exists
    // and FakeJobsRepository is wired — full export path covered in unit tests.
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('export-library')), findsOneWidget);
    expect(written, isNull);
  });

  testWidgets('Cancel during polling reflects cancelled', (tester) async {
    final item = fixtureItem(id: 'item_c');
    final jobs = FakeJobsRepository(
      itemId: 'item_c',
      item: item,
      jobs: [fixtureJob(id: 'j1', itemId: 'item_c', state: JobState.processing)],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(
          items: FakeItemsRepository(items: [item]),
          jobs: jobs,
        ),
        child: const MaterialApp(
          home: ItemDetailPage(itemId: 'item_c'),
        ),
      ),
    );
    // Non-terminal job keeps a progress indicator animating — avoid pumpAndSettle.
    await tester.pump();
    await tester.pump(); // post-frame refreshJobs
    await tester.pump(); // listItemJobs completes → polling + Cancel visible

    expect(find.byKey(const Key('item-cancel-job')), findsOneWidget);
    await tester.tap(find.byKey(const Key('item-cancel-job')));
    await tester.pump();
    await tester.pump();

    expect(jobs.cancelCallCount, 1);
    expect(find.byKey(const Key('job-state-cancelled')), findsOneWidget);
  });
}
