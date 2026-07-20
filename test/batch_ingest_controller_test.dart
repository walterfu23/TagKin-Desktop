import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/batch_ingest_controller.dart';
import 'package:tagkin_desktop/ingest/dedup.dart';

import 'fake_items_repository.dart';

Future<Directory> _tempFolder() async {
  final dir = await Directory.systemTemp.createTemp('d3_controller_test_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

void main() {
  group('BatchIngestController', () {
    test('pickAndScan stays idle when the folder dialog is cancelled',
        () async {
      final controller = BatchIngestController(
        itemsRepository: FakeItemsRepository(),
        folderPicker: () async => null,
      );
      await controller.pickAndScan();
      expect(controller.phase, BatchIngestPhase.idle);
      expect(controller.dedupResult, isNull);
    });

    test('scanning a non-existent folder surfaces phase.error', () async {
      final controller = BatchIngestController(
        itemsRepository: FakeItemsRepository(),
        folderPicker: () async => null,
      );
      await controller.scanFolder('/definitely/does/not/exist/d3-fixture');
      expect(controller.phase, BatchIngestPhase.error);
      expect(controller.error, isNotNull);
    });

    test(
        'scan finds distinct files and selects every representative by default',
        () async {
      final dir = await _tempFolder();
      await File('${dir.path}/a.jpg').writeAsBytes([1, 2, 3]);
      await File('${dir.path}/b.mp4').writeAsBytes([4, 5, 6]);

      final controller = BatchIngestController(
        itemsRepository: FakeItemsRepository(),
        folderPicker: () async => dir.path,
      );
      await controller.pickAndScan();

      expect(controller.phase, BatchIngestPhase.reviewing);
      expect(controller.dedupResult!.representatives, hasLength(2));
      expect(controller.dedupResult!.skipped, isEmpty);
      expect(controller.selectedPaths, hasLength(2));
    });

    test(
        'confirmIngest creates items with metadata/refs only — never bytes '
        'or an owner field (R1/R7/R10)', () async {
      final dir = await _tempFolder();
      await File('${dir.path}/a.jpg').writeAsBytes([1, 2, 3]);
      await File('${dir.path}/b.mp4').writeAsBytes([4, 5, 6]);

      final repo = FakeItemsRepository();
      final controller = BatchIngestController(
        itemsRepository: repo,
        folderPicker: () async => dir.path,
      );
      await controller.pickAndScan();
      await controller.confirmIngest();

      expect(controller.phase, BatchIngestPhase.done);
      expect(controller.outcomes, hasLength(2));
      expect(controller.outcomes.every((o) => o.succeeded), isTrue);
      expect(repo.created, hasLength(2));

      for (final created in repo.created) {
        final json = created.toJson();
        expect(
          json.keys.toSet(),
          {'type', 'sourceType', 'sourceRef', 'contentHash', 'capturedAt'},
        );
        expect(json.containsKey('ownerUserId'), isFalse);
        expect(json.containsKey('accountId'), isFalse);
        expect(json.containsKey('bytes'), isFalse);
        expect(json.containsKey('data'), isFalse);
        expect(created.sourceRef, isNotNull);
        expect(created.contentHash, isNotNull);
      }
    });

    test('deselecting a candidate excludes it from the batch create',
        () async {
      final dir = await _tempFolder();
      await File('${dir.path}/a.jpg').writeAsBytes([1, 2, 3]);
      await File('${dir.path}/b.jpg').writeAsBytes([4, 5, 6]);

      final repo = FakeItemsRepository();
      final controller = BatchIngestController(
        itemsRepository: repo,
        folderPicker: () async => dir.path,
      );
      await controller.pickAndScan();
      final toDrop = controller.dedupResult!.representatives.first.candidate.path;
      controller.toggleSelection(toDrop);
      expect(controller.selectedPaths.contains(toDrop), isFalse);

      await controller.confirmIngest();
      expect(repo.created, hasLength(1));
    });

    test(
        'two accounts scanning the same folder never cross-contaminate dedup '
        '(R10)', () async {
      final dir = await _tempFolder();
      await File('${dir.path}/shared.jpg').writeAsBytes([7, 7, 7]);

      Future<String> fixedHash(String path) async => 'fixed-shared-hash';

      final repoA = FakeItemsRepository(
        items: [
          Item(
            id: 'existing_a',
            type: ItemType.photo,
            sourceType: SourceType.local,
            analysisRefState: AnalysisRefState.pending,
            contentHash: 'fixed-shared-hash',
            processingStatus: ProcessingStatus.pending,
            schemaVersion: 1,
            createdAt: '2026-07-19T00:00:00.000Z',
          ),
        ],
      );
      final controllerA = BatchIngestController(
        itemsRepository: repoA,
        folderPicker: () async => dir.path,
        contentHasher: fixedHash,
      );
      await controllerA.pickAndScan();
      expect(controllerA.dedupResult!.representatives, isEmpty);
      expect(
        controllerA.dedupResult!.skipped.single.reason,
        SkipReason.existingInLibrary,
      );

      final repoB = FakeItemsRepository(); // account B has no existing items
      final controllerB = BatchIngestController(
        itemsRepository: repoB,
        folderPicker: () async => dir.path,
        contentHasher: fixedHash,
      );
      await controllerB.pickAndScan();
      // Account A's existing hash never suppresses account B's create.
      expect(controllerB.dedupResult!.representatives, hasLength(1));
    });

    test('reset returns the controller to idle', () async {
      final dir = await _tempFolder();
      await File('${dir.path}/a.jpg').writeAsBytes([1, 2, 3]);
      final controller = BatchIngestController(
        itemsRepository: FakeItemsRepository(),
        folderPicker: () async => dir.path,
      );
      await controller.pickAndScan();
      controller.reset();
      expect(controller.phase, BatchIngestPhase.idle);
      expect(controller.dedupResult, isNull);
      expect(controller.selectedPaths, isEmpty);
    });
  });
}
