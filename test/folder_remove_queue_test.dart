import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/library/folder_remove_queue.dart';

import 'fake_items_repository.dart';
import 'fake_jobs_repository.dart';

void main() {
  test('enqueue soft-deletes all ids and bumps libraryRefreshTick', () async {
    final items = FakeItemsRepository(
      items: [
        fixtureItem(id: 'a'),
        fixtureItem(id: 'b'),
      ],
    );
    final jobs = FakeJobsRepository(onDelete: items.removeItem);
    final removedBookmarks = <String>[];
    final queue = FolderRemoveQueue(
      jobsRepository: jobs,
      removeBookmark: (dir) async {
        removedBookmarks.add(dir);
      },
    );

    final result = await queue.enqueue('/albums/trip', ['a', 'b']);
    expect(result, FolderRemoveEnqueueResult.started);
    expect(queue.activeJobCount, 1);
    expect(queue.isRemoving('/albums/trip'), isTrue);

    await pumpEventQueue();

    expect(queue.activeJobCount, 0);
    expect(queue.jobs.single.phase, FolderRemoveJobPhase.done);
    expect(queue.jobs.single.completed, 2);
    expect(jobs.deletedItemIds, ['a', 'b']);
    expect(removedBookmarks, ['/albums/trip']);
    expect(queue.libraryRefreshTick, 1);
  });

  test('enqueue refuses a path that is already active', () async {
    final jobs = FakeJobsRepository()
      ..deleteDelay = const Duration(milliseconds: 50);
    final queue = FolderRemoveQueue(jobsRepository: jobs);

    expect(
      await queue.enqueue('/albums/trip', ['a', 'b']),
      FolderRemoveEnqueueResult.started,
    );
    expect(
      await queue.enqueue('/albums/trip', ['c']),
      FolderRemoveEnqueueResult.alreadyActive,
    );

    await Future<void>.delayed(const Duration(milliseconds: 150));
    await pumpEventQueue();
    expect(queue.jobs.single.phase, FolderRemoveJobPhase.done);
  });

  test('enqueue with empty ids returns empty', () async {
    final queue = FolderRemoveQueue(jobsRepository: FakeJobsRepository());
    expect(
      await queue.enqueue('/albums/trip', const []),
      FolderRemoveEnqueueResult.empty,
    );
    expect(queue.jobs, isEmpty);
  });

  test('per-item failures are counted; job finishes as done when some succeed',
      () async {
    final jobs = FakeJobsRepository(
      onDelete: (id) {
        if (id == 'b') throw Exception('boom');
      },
    );
    final queue = FolderRemoveQueue(jobsRepository: jobs);
    await queue.enqueue('/albums/x', ['a', 'b']);
    await pumpEventQueue();

    expect(queue.jobs.single.phase, FolderRemoveJobPhase.done);
    expect(queue.jobs.single.failed, 1);
    expect(queue.jobs.single.completed, 2);
    expect(queue.jobs.single.statusLabel, 'Done (1 of 2 failed)');
  });

  test('all deletes failing marks the job as error', () async {
    final jobs = FakeJobsRepository(deleteError: Exception('nope'));
    final queue = FolderRemoveQueue(jobsRepository: jobs);
    await queue.enqueue('/albums/x', ['a', 'b']);
    await pumpEventQueue();

    expect(queue.jobs.single.phase, FolderRemoveJobPhase.error);
    expect(queue.jobs.single.failed, 2);
  });
}
