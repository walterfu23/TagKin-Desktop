// D7 Tagging & Jobs Lifecycle integration: analyze → terminal, cancel,
// delete, export against fake JobsRepository (mocked API per §5).
//   flutter test integration_test/jobs_lifecycle_test.dart -d macos
//   flutter test integration_test/jobs_lifecycle_test.dart -d windows

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/jobs/export_controller.dart';
import 'package:tagkin_desktop/main.dart';

import '../test/fake_comments_repository.dart';
import '../test/fake_corrections_repository.dart';
import '../test/fake_items_repository.dart';
import '../test/fake_jobs_repository.dart';
import '../test/fake_usage_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('analyze reaches completed; delete removes from list; export runs',
      (WidgetTester tester) async {
    final item = fixtureItem(
      id: 'item_int',
      analysisRef: 'ref_int',
      analysisRefState: AnalysisRefState.ready,
      processingStatus: ProcessingStatus.awaitingModelAccess,
    );
    final items = FakeItemsRepository(items: [item]);
    final jobs = FakeJobsRepository(
      itemId: 'item_int',
      item: item,
      onDelete: items.removeItem,
    );
    String? savedPath;

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
          exportControllerProvider.overrideWith((ref) {
            final controller = ExportController(
              jobsRepository: jobs,
              writer: ({required suggestedName, required contents}) async {
                savedPath = '/tmp/$suggestedName';
                return savedPath;
              },
            );
            ref.onDispose(controller.dispose);
            return controller;
          }),
        ],
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('item-row-item_int')), findsOneWidget);

    // Export from list.
    await tester.tap(find.byKey(const Key('export-library')));
    await tester.pumpAndSettle();
    expect(jobs.exportCallCount, 1);
    expect(savedPath, isNotNull);
    expect(find.byKey(const Key('export-success')), findsOneWidget);

    // Analyze on detail.
    await tester.tap(find.byKey(const Key('item-row-item_int')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-analyze')));
    await tester.pumpAndSettle();
    expect(jobs.analyzeCallCount, 1);
    expect(find.byKey(const Key('job-state-completed')), findsOneWidget);

    // Delete.
    await tester.tap(find.byKey(const Key('item-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-confirm')));
    await tester.pumpAndSettle();
    expect(jobs.deleteCallCount, 1);
    expect(find.byKey(const Key('item-row-item_int')), findsNothing);
  });

  testWidgets('cancel while job non-terminal reflects cancelled',
      (WidgetTester tester) async {
    // Tall surface so Cancel stays hittable above the D10 review section.
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final item = fixtureItem(id: 'item_cancel');
    final items = FakeItemsRepository(items: [item]);
    final jobs = FakeJobsRepository(
      itemId: 'item_cancel',
      item: item,
      jobs: [
        fixtureJob(
          id: 'job_open',
          itemId: 'item_cancel',
          state: JobState.processing,
        ),
      ],
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
        ],
        child: const TagKinDesktopApp(),
      ),
    );
    // List has no spinner — settle is fine here.
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-row-item_cancel')));
    // Detail with non-terminal job animates a progress indicator — no settle.
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('item-cancel-job')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('item-cancel-job')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('item-cancel-job')));
    // Allow cancel + notifyListeners; avoid pumpAndSettle (progress spinner).
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(jobs.cancelCallCount, 1);
    expect(find.byKey(const Key('job-state-cancelled')), findsOneWidget);
  });
}
