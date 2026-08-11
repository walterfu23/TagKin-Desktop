// D5 Ingest Upload & Grants integration: folder ingest → pre-pass → upload
// against a fake ItemsRepository + injected model-host PUT (mocked API per §5).
// Background folder ingest (D3) auto-runs the pipeline after create.
//   flutter test integration_test/upload_test.dart -d macos   (or -d windows)

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/folder_ingest_queue.dart';
import 'package:tagkin_desktop/ingest/folder_picker.dart';
import 'package:tagkin_desktop/ingest/media_enumerator.dart';
import 'package:tagkin_desktop/ingest/model_host_uploader.dart';
import 'package:tagkin_desktop/ingest/upload_controller.dart';
import 'package:tagkin_desktop/main.dart';
import 'package:tagkin_desktop/persons/who_face_linker.dart';
import 'package:tagkin_desktop/prepass/prepass_controller.dart';
import 'package:tagkin_desktop/prepass/prepass_payload_builder.dart';

import '../test/fake_items_repository.dart';
import '../test/fake_jobs_repository.dart';
import '../test/fake_usage_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'folder ingest auto-runs pre-pass → upload and records analysisRef without bytes to api',
      (WidgetTester tester) async {
    final dir = await Directory.systemTemp.createTemp('d5_integration_test_');
    addTearDown(() => dir.deleteSync(recursive: true));

    final image = img.Image(width: 32, height: 32);
    img.fill(image, color: img.ColorRgb8(40, 50, 60));
    final photoPath = '${dir.path}/trip.jpg';
    await File(photoPath).writeAsBytes(img.encodeJpg(image));

    final repo = FakeItemsRepository();
    final jobs = FakeJobsRepository();
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
          jobsRepositoryProvider.overrideWithValue(jobs),
          folderPickerProvider.overrideWithValue(() async => dir.path),
          folderIngestQueueProvider.overrideWith((ref) {
            return FolderIngestQueue(
              itemsRepository: repo,
              jobsRepository: jobs,
              isUsageBlocked: () => false,
              enumerateFolder: (path) async => [
                MediaCandidate(
                  path: photoPath,
                  type: ItemType.photo,
                  size: 3,
                  modifiedAt: DateTime(2026, 1, 1),
                ),
              ],
              contentHasher: (path) async => 'integration-hash',
              perceptualHasher: (path) async => null,
              prePassFactory: () => PrePassController(
                itemsRepository: repo,
                buildPayload: ({
                  required path,
                  required type,
                  faceEmbedder,
                  skipFaces = false,
                  maxFrames = 20,
                  minIntervalMs = 2000,
                  maxIntervalMs = 10000,
                  sceneCutThreshold = 27.0,
                }) async {
                  return PrePassBuildResult(
                    payload: PrePassResult(
                      contentHash: 'integration-hash',
                      appearances: const [],
                    ),
                  );
                },
              ),
              uploadFactory: () => UploadController(
                itemsRepository: repo,
                readBytes: (path) async => [0xFF, 0xD8, 0xFF],
                putBytes: ({
                  required uploadUrl,
                  required bytes,
                  required mimeType,
                  httpClient,
                }) async {
                  putUrls.add(uploadUrl);
                  return const ModelHostUploadResult(
                    analysisRef: 'files/integration-ref',
                    rawBody: '{}',
                  );
                },
              ),
              whoFaceLinkerFactory: () => WhoFaceLinker(items: repo),
            );
          }),
        ],
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-from-folder')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('folder-ingest-status-banner')), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TagKinDesktopApp)),
    );
    final queue = container.read(folderIngestQueueProvider);
    for (var i = 0; i < 200 && queue.hasActiveJobs; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    expect(repo.created, hasLength(1));
    expect(putUrls, hasLength(1));
    expect(putUrls.single.contains('/items'), isFalse);
    expect(putUrls.single.contains('stub.tagkin.test'), isTrue);
    expect(repo.grantsMinted, hasLength(1));
    expect(repo.analysisRefRecorded, hasLength(1));
    expect(
      repo.analysisRefRecorded.single.input.analysisRef,
      'files/integration-ref',
    );

    final grantJson = repo.grantsMinted.single.input.toJson();
    expect(grantJson.containsKey('ownerUserId'), isFalse);
    expect(grantJson.containsKey('bytes'), isFalse);
  });
}
