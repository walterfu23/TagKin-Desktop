// D5 Ingest Upload & Grants integration: folder ingest → pre-pass → upload
// against a fake ItemsRepository + injected model-host PUT (mocked API per §5).
//   flutter test integration_test/upload_test.dart -d macos   (or -d windows)

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/folder_picker.dart';
import 'package:tagkin_desktop/ingest/model_host_uploader.dart';
import 'package:tagkin_desktop/ingest/upload_controller.dart';
import 'package:tagkin_desktop/main.dart';

import '../test/fake_items_repository.dart';
import '../test/fake_usage_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'folder ingest → pre-pass → upload records analysisRef without bytes to api',
      (WidgetTester tester) async {
    final dir = await Directory.systemTemp.createTemp('d5_integration_test_');
    addTearDown(() => dir.deleteSync(recursive: true));

    final image = img.Image(width: 32, height: 32);
    img.fill(image, color: img.ColorRgb8(40, 50, 60));
    await File('${dir.path}/trip.jpg').writeAsBytes(img.encodeJpg(image));

    final repo = FakeItemsRepository();
    final putUrls = <String>[];

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
          folderPickerProvider.overrideWithValue(() async => dir.path),
          uploadControllerProvider.overrideWith((ref) {
            final controller = UploadController(
              itemsRepository: repo,
              putBytes: ({
                required uploadUrl,
                required bytes,
                required mimeType,
                httpClient,
              }) async {
                putUrls.add(uploadUrl);
                expect(uploadUrl.contains('/items'), isFalse);
                return const ModelHostUploadResult(
                  analysisRef: 'files/integration-ref',
                  rawBody: '{}',
                );
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
    expect(find.byKey(const Key('run-upload-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('run-upload-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('upload-done-summary')), findsOneWidget);
    expect(repo.grantsMinted, hasLength(1));
    expect(repo.analysisRefRecorded, hasLength(1));
    expect(
      repo.analysisRefRecorded.single.input.analysisRef,
      'files/integration-ref',
    );
    expect(putUrls, hasLength(1));
    expect(putUrls.single.contains('stub.tagkin.test'), isTrue);

    final grantJson = repo.grantsMinted.single.input.toJson();
    expect(grantJson.containsKey('ownerUserId'), isFalse);
    expect(grantJson.containsKey('bytes'), isFalse);
  });
}
