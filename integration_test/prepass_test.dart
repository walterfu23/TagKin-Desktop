// D4 Client Pre-pass integration: build + POST pre-pass-result against a
// fake ItemsRepository (mocked API per §5; no live network).
//   flutter test integration_test/prepass_test.dart -d macos   (or -d windows)

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/folder_picker.dart';
import 'package:tagkin_desktop/main.dart';

import '../test/fake_items_repository.dart';
import '../test/fake_jobs_repository.dart';
import '../test/fake_usage_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'folder ingest then client pre-pass records metadata-only payload',
      (WidgetTester tester) async {
    final dir = await Directory.systemTemp.createTemp('d4_integration_test_');
    addTearDown(() => dir.deleteSync(recursive: true));

    final image = img.Image(width: 32, height: 32);
    img.fill(image, color: img.ColorRgb8(90, 100, 110));
    await File('${dir.path}/trip.jpg').writeAsBytes(img.encodeJpg(image));

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
          usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
          jobsRepositoryProvider.overrideWithValue(FakeJobsRepository()),
          folderPickerProvider.overrideWithValue(() async => dir.path),
        ],
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-from-folder')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pick-folder-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('confirm-ingest-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ingest-done')), findsOneWidget);
    expect(find.byKey(const Key('run-prepass-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('run-prepass-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('prepass-done-summary')), findsOneWidget);
    expect(repo.prePassRecorded, hasLength(1));
    final payload = repo.prePassRecorded.single.input;
    expect(payload.contentHash, isNotNull);
    expect(payload.appearances, isNotNull);
    expect(payload.appearances!.single.embedding, hasLength(512));
    final json = payload.toJson();
    expect(json.containsKey('ownerUserId'), isFalse);
    expect(json.containsKey('bytes'), isFalse);
  });
}
