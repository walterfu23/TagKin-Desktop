import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/jobs/jobs_controller.dart';

import 'fake_items_repository.dart';
import 'fake_jobs_repository.dart';

void main() {
  group('JobsController', () {
    test('analyze → poll → reaches terminal completed', () async {
      final repo = FakeJobsRepository(
        itemId: 'item_1',
        item: fixtureItem(id: 'item_1'),
      );
      // After analyze inserts completed job; list returns it immediately.
      final controller = JobsController(
        itemId: 'item_1',
        jobsRepository: repo,
        pollInterval: const Duration(milliseconds: 1),
      );

      await controller.analyze(itemType: ItemType.photo);

      expect(repo.analyzeCallCount, 1);
      expect(controller.phase, JobsPhase.terminal);
      expect(controller.latestJob?.state, JobState.completed);
      expect(controller.item?.processingStatus, ProcessingStatus.tagged);
      controller.dispose();
    });

    test('analyze refuses video items (R9)', () async {
      final repo = FakeJobsRepository(itemId: 'item_v');
      final controller = JobsController(
        itemId: 'item_v',
        jobsRepository: repo,
      );

      await controller.analyze(itemType: ItemType.video);

      expect(repo.analyzeCallCount, 0);
      expect(controller.phase, JobsPhase.error);
      expect(controller.error, isA<StateError>());
      controller.dispose();
    });

    test('cancel stops polling and reflects cancelled', () async {
      final pending = fixtureJob(id: 'job_p', state: JobState.processing);
      final repo = FakeJobsRepository(
        itemId: 'item_1',
        jobs: [pending],
      );
      final pendingCallbacks = <void Function()>[];
      final controller = JobsController(
        itemId: 'item_1',
        jobsRepository: repo,
        pollInterval: const Duration(hours: 1),
        ticker: (d, cb) {
          pendingCallbacks.add(cb);
          return Timer(d, cb);
        },
      );

      await controller.refreshJobs();
      expect(controller.phase, JobsPhase.polling);
      expect(controller.canCancel, isTrue);

      await controller.cancel();

      expect(repo.cancelCallCount, 1);
      expect(controller.phase, JobsPhase.terminal);
      expect(controller.latestJob?.state, JobState.cancelled);
      expect(controller.canCancel, isFalse);
      controller.dispose();
    });

    test('stale refreshJobs after cancel does not clobber cancelled job',
        () async {
      final pending = fixtureJob(id: 'job_p', state: JobState.processing);
      final repo = FakeJobsRepository(
        itemId: 'item_1',
        jobs: [pending],
      );
      // First list is instant (enter polling); second is delayed so cancel
      // can finish while a refresh is still in flight.
      final controller = JobsController(
        itemId: 'item_1',
        jobsRepository: repo,
        pollInterval: const Duration(hours: 1),
        ticker: (d, cb) => Timer(d, cb),
      );

      await controller.refreshJobs();
      expect(controller.phase, JobsPhase.polling);

      repo.listJobsDelay = const Duration(milliseconds: 30);
      final staleRefresh = controller.refreshJobs();
      await controller.cancel();
      expect(controller.latestJob?.state, JobState.cancelled);

      await staleRefresh;
      expect(controller.latestJob?.state, JobState.cancelled);
      expect(controller.phase, JobsPhase.terminal);
      controller.dispose();
    });

    test('delete sets deleted and never touches local paths', () async {
      final repo = FakeJobsRepository(itemId: 'item_1');
      final controller = JobsController(
        itemId: 'item_1',
        jobsRepository: repo,
      );

      await controller.delete();

      expect(repo.deleteCallCount, 1);
      expect(repo.deletedItemIds, ['item_1']);
      expect(controller.deleted, isTrue);
      controller.dispose();
    });

    test('polling advances through non-terminal states to completed', () async {
      final repo = FakeJobsRepository(itemId: 'item_1');
      repo.jobsSequence.addAll([
        [fixtureJob(id: 'j1', state: JobState.processing)],
        [fixtureJob(id: 'j1', state: JobState.completed)],
      ]);
      final ticks = <void Function()>[];
      final controller = JobsController(
        itemId: 'item_1',
        jobsRepository: repo,
        pollInterval: const Duration(milliseconds: 10),
        ticker: (d, cb) {
          ticks.add(cb);
          // Fire immediately for the test (ignore duration).
          return Timer(Duration.zero, cb);
        },
      );

      await controller.refreshJobs();
      expect(controller.phase, JobsPhase.polling);
      expect(controller.latestJob?.state, JobState.processing);

      // Drive the scheduled poll tick.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.phase, JobsPhase.terminal);
      expect(controller.latestJob?.state, JobState.completed);
      controller.dispose();
    });

    test('retry only after failed job', () async {
      final repo = FakeJobsRepository(
        itemId: 'item_1',
        jobs: [fixtureJob(id: 'j_fail', state: JobState.failed)],
      );
      final controller = JobsController(
        itemId: 'item_1',
        jobsRepository: repo,
      );
      await controller.refreshJobs();
      expect(controller.canRetry, isTrue);

      await controller.retry(itemType: ItemType.photo);
      expect(repo.analyzeCallCount, 1);
      expect(controller.latestJob?.state, JobState.completed);
      controller.dispose();
    });

    test('409 from analyze surfaces error without retry', () async {
      final repo = FakeJobsRepository(
        itemId: 'item_1',
        analyzeError: ApiException(
          statusCode: 409,
          message: 'Hard budget exceeded',
          code: 'budget_exceeded',
        ),
      );
      final controller = JobsController(
        itemId: 'item_1',
        jobsRepository: repo,
      );

      await controller.analyze(itemType: ItemType.photo);

      expect(repo.analyzeCallCount, 1);
      expect(controller.phase, JobsPhase.error);
      expect(
        controller.error,
        isA<ApiException>().having((e) => e.statusCode, 'status', 409),
      );
      controller.dispose();
    });
  });
}
