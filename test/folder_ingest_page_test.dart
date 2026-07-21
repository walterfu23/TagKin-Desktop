import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/batch_ingest_controller.dart';
import 'package:tagkin_desktop/ingest/folder_ingest_page.dart';
import 'package:tagkin_desktop/ingest/folder_picker.dart';
import 'package:tagkin_desktop/ingest/media_enumerator.dart';
import 'package:tagkin_desktop/prepass/prepass_controller.dart';
import 'package:tagkin_desktop/prepass/prepass_payload_builder.dart';

import 'fake_items_repository.dart';
import 'fake_jobs_repository.dart';
import 'fake_usage_repository.dart';

// Widget tests never touch real `dart:io` here — `testWidgets`'s pumped
// frame loop (`AutomatedTestWidgetsFlutterBinding`) does not reliably drive
// genuine filesystem async completions, so enumerate/hash are faked via the
// same overridable providers `BatchIngestController` uses in production.
// `test/batch_ingest_controller_test.dart` (plain `test()`) already covers
// the real-filesystem path end to end.

MediaCandidate _fixtureCandidate(String path, {ItemType type = ItemType.photo}) {
  return MediaCandidate(
    path: path,
    type: type,
    size: 100,
    modifiedAt: DateTime(2026, 1, 1),
  );
}

Future<void> _pushFolderIngestPage(
  WidgetTester tester, {
  required FolderPicker folderPicker,
  required FakeItemsRepository repository,
  Future<List<MediaCandidate>> Function(String)? enumerate,
  Future<String> Function(String)? contentHasher,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        folderPickerProvider.overrideWithValue(folderPicker),
        itemsRepositoryProvider.overrideWithValue(repository),
        usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
          jobsRepositoryProvider.overrideWithValue(FakeJobsRepository()),
        if (enumerate != null) mediaEnumeratorProvider.overrideWithValue(enumerate),
        // No real file bytes to decode/hash in these widget fixtures.
        contentHasherProvider.overrideWithValue(
          contentHasher ?? (path) async => 'fixture-hash-$path',
        ),
        perceptualHasherProvider.overrideWithValue((path) async => null),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (_) => const FolderIngestPage(),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'pick → review → confirm shows a done summary and closes on Done',
      (tester) async {
    const folderPath = '/fixtures/d3-folder';
    final repo = FakeItemsRepository();

    await _pushFolderIngestPage(
      tester,
      folderPicker: () async => folderPath,
      repository: repo,
      enumerate: (path) async => [
        _fixtureCandidate('$path/a.jpg'),
        _fixtureCandidate('$path/b.mp4', type: ItemType.video),
      ],
    );

    await tester.tap(find.byKey(const Key('pick-folder-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ingest-review')), findsOneWidget);
    expect(find.byKey(const Key('confirm-ingest-button')), findsOneWidget);
    expect(find.byKey(Key('candidate-row-$folderPath/a.jpg')), findsOneWidget);
    expect(find.byKey(Key('candidate-row-$folderPath/b.mp4')), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirm-ingest-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ingest-done')), findsOneWidget);
    expect(find.text('Added 2 item(s).'), findsOneWidget);
    expect(repo.created, hasLength(2));

    await tester.tap(find.byKey(const Key('ingest-done-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ingest-done')), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets(
      'a byte-identical duplicate is shown as skipped and excluded from the create count',
      (tester) async {
    const folderPath = '/fixtures/d3-dupes';
    final repo = FakeItemsRepository();

    await _pushFolderIngestPage(
      tester,
      folderPicker: () async => folderPath,
      repository: repo,
      enumerate: (path) async => [
        _fixtureCandidate('$path/a.jpg'),
        _fixtureCandidate('$path/a-copy.jpg'),
      ],
      // Both candidates hash identically — simulates a byte-identical
      // duplicate within the batch.
      contentHasher: (path) async => 'same-fixture-hash',
    );

    await tester.tap(find.byKey(const Key('pick-folder-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ingest-review')), findsOneWidget);
    expect(
      find.byKey(Key('candidate-row-$folderPath/a.jpg')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('skipped-row-$folderPath/a-copy.jpg')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('confirm-ingest-button')));
    await tester.pumpAndSettle();

    expect(repo.created, hasLength(1));
  });

  testWidgets('cancelling the folder dialog leaves the idle picker view',
      (tester) async {
    await _pushFolderIngestPage(
      tester,
      folderPicker: () async => null,
      repository: FakeItemsRepository(),
    );

    await tester.tap(find.byKey(const Key('pick-folder-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pick-folder-button')), findsOneWidget);
    expect(find.byKey(const Key('ingest-review')), findsNothing);
  });

  testWidgets('a scan error shows the error view with retry', (tester) async {
    await _pushFolderIngestPage(
      tester,
      folderPicker: () async => '/fixtures/does-not-matter',
      repository: FakeItemsRepository(),
      enumerate: (path) async =>
          throw ArgumentError('Folder does not exist: $path'),
    );

    await tester.tap(find.byKey(const Key('pick-folder-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ingest-error')), findsOneWidget);
    expect(find.byKey(const Key('ingest-error-retry')), findsOneWidget);
  });

  testWidgets(
      'kill-switch disables Upload for analysis after pre-pass (D5/D6)',
      (tester) async {
    const folderPath = '/fixtures/d5-blocked';
    final repo = FakeItemsRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          folderPickerProvider.overrideWithValue(() async => folderPath),
          itemsRepositoryProvider.overrideWithValue(repo),
          usageRepositoryProvider.overrideWithValue(
            FakeUsageRepository(
              summary: fixtureUsageSummary(
                killSwitchEnabled: true,
                killSwitchReason: 'ops',
                pauseReason: 'kill switch enabled',
              ),
            ),
          ),
          jobsRepositoryProvider.overrideWithValue(FakeJobsRepository()),
          mediaEnumeratorProvider.overrideWithValue(
            (path) async => [_fixtureCandidate('$path/a.jpg')],
          ),
          contentHasherProvider.overrideWithValue(
            (path) async => 'fixture-hash-$path',
          ),
          perceptualHasherProvider.overrideWithValue((path) async => null),
          prePassControllerProvider.overrideWith((ref) {
            final controller = PrePassController(
              itemsRepository: repo,
              buildPayload: ({
                required path,
                required type,
                faceEmbedder,
                skipFaces = false,
                maxFrames = 20,
              }) async {
                return PrePassBuildResult(
                  payload: PrePassResult(
                    contentHash: 'hash',
                    appearances: [
                      PrePassAppearanceInput(
                        embedding: List<double>.filled(512, 0.0),
                        embeddingModelId: 'stub-face-embed-v1',
                      ),
                    ],
                  ),
                );
              },
            );
            ref.onDispose(controller.dispose);
            return controller;
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) => const FolderIngestPage(),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Folder pick is also blocked by kill-switch — force scan via controller
    // to reach the done view with upload button gated.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FolderIngestPage)),
    );
    final batch = container.read(batchIngestControllerProvider);
    await batch.scanFolder(folderPath);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('confirm-ingest-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('run-prepass-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('run-upload-button')), findsOneWidget);
    final uploadBtn = tester.widget<FilledButton>(
      find.byKey(const Key('run-upload-button')),
    );
    expect(uploadBtn.onPressed, isNull);
  });
}
