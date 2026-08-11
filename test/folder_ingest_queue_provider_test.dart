import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/ingest/folder_ingest_queue.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';

import 'fake_items_repository.dart';
import 'fake_jobs_repository.dart';
import 'fake_usage_repository.dart';

void main() {
  test('folderIngestQueueProvider keeps the same instance across prefs update',
      () async {
    final prefsController = DesktopPrefsController();
    final container = ProviderContainer(
      overrides: [
        itemsRepositoryProvider.overrideWithValue(FakeItemsRepository()),
        jobsRepositoryProvider.overrideWithValue(FakeJobsRepository()),
        usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
        desktopPrefsControllerProvider.overrideWith((ref) => prefsController),
      ],
    );
    addTearDown(container.dispose);

    final first = container.read(folderIngestQueueProvider);
    expect(identical(first, container.read(folderIngestQueueProvider)), isTrue);

    // Simulate Settings/prefs notify (previously rebuilt the ingest queue).
    await prefsController.update(
      DesktopPrefs.defaults.copyWith(nearDuplicateThreshold: 8),
    );
    await Future<void>.delayed(Duration.zero);

    final second = container.read(folderIngestQueueProvider);
    expect(identical(first, second), isTrue);

    // Auto-assign Settings save — same prefs provider that used to orphan listeners.
    await prefsController.update(
      DesktopPrefs.defaults.copyWith(
        nearDuplicateThreshold: 8,
        autoConfirmHighConfidencePersonMatches: false,
        autoConfirmMinConfidencePercent: 75,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      identical(first, container.read(folderIngestQueueProvider)),
      isTrue,
    );
  });
}
