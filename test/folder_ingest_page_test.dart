import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/batch_ingest_controller.dart';
import 'package:tagkin_desktop/ingest/folder_ingest_page.dart';
import 'package:tagkin_desktop/ingest/folder_picker.dart';
import 'package:tagkin_desktop/ingest/media_enumerator.dart';

import 'fake_items_repository.dart';

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
}
