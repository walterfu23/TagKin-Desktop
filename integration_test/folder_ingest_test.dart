// D3 Local Folder Ingest & Batch integration: pick → review → confirm
// against a fake ItemsRepository + injected folder picker (mocked API per
// §5; no live network, no real native dialog).
//   flutter test integration_test/folder_ingest_test.dart -d macos   (or -d windows)

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/folder_picker.dart';
import 'package:tagkin_desktop/main.dart';

import '../test/fake_items_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'folder pick -> review -> confirm ingest refreshes the library on the '
      'desktop host', (WidgetTester tester) async {
    final dir = await Directory.systemTemp.createTemp('d3_integration_test_');
    addTearDown(() => dir.deleteSync(recursive: true));
    await File('${dir.path}/trip.jpg').writeAsBytes([1, 2, 3]);

    final repo = FakeItemsRepository();

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
          itemsRepositoryProvider.overrideWithValue(repo),
          folderPickerProvider.overrideWithValue(() async => dir.path),
        ],
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('items-empty')), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-from-folder')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pick-folder-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ingest-review')), findsOneWidget);
    expect(
      find.byKey(Key('candidate-row-${dir.path}/trip.jpg')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('confirm-ingest-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ingest-done')), findsOneWidget);
    expect(repo.created, hasLength(1));

    await tester.tap(find.byKey(const Key('ingest-done-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('items-list')), findsOneWidget);
    expect(find.byKey(const Key('items-empty')), findsNothing);
  });
}
