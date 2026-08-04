// D3 Local Folder Ingest: FAB → background queue → library refresh.
//   flutter test integration_test/folder_ingest_test.dart -d macos

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
      'folder pick enqueues background ingest and refreshes the library',
      (WidgetTester tester) async {
    final dir = await Directory.systemTemp.createTemp('d3_integration_test_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final photoPath = '${dir.path}/trip.jpg';
    await File(photoPath).writeAsBytes([1, 2, 3]);

    final repo = FakeItemsRepository();
    final jobs = FakeJobsRepository();

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
                      appearances: [
                        PrePassAppearanceInput(
                          embedding: List<double>.filled(512, 0.0),
                          embeddingModelId: 'stub-face-embed-v1',
                        ),
                      ],
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

    expect(find.byKey(const Key('items-empty')), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-from-folder')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('folder-ingest-status-banner')), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TagKinDesktopApp)),
    );
    final queue = container.read(folderIngestQueueProvider);
    for (var i = 0; i < 100 && queue.hasActiveJobs; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    expect(repo.created, hasLength(1));
    expect(find.byKey(const Key('items-list')), findsOneWidget);
    expect(find.byKey(const Key('items-empty')), findsNothing);
  });
}
