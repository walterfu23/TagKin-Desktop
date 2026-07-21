import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/jobs/export_controller.dart';

import 'fake_jobs_repository.dart';

void main() {
  group('ExportController', () {
    test('exportLibrary writes knowledge JSON with no byte fields (R1)',
        () async {
      final dir = await Directory.systemTemp.createTemp('tagkin-export-');
      addTearDown(() => dir.delete(recursive: true));
      final target = File('${dir.path}/out.json');

      final repo = FakeJobsRepository(
        export: fixtureLibraryExport(),
      );
      final controller = ExportController(
        jobsRepository: repo,
        writer: ({required suggestedName, required contents}) async {
          await target.writeAsString(contents);
          return target.path;
        },
      );

      await controller.exportLibrary();

      expect(repo.exportCallCount, 1);
      expect(controller.phase, ExportPhase.done);
      expect(controller.savedPath, target.path);
      final decoded = jsonDecode(await target.readAsString()) as Map;
      expect(decoded.containsKey('items'), isTrue);
      expect(decoded.containsKey('tags'), isTrue);
      expect(decoded.containsKey('bytes'), isFalse);
      expect(decoded.containsKey('blob'), isFalse);
      expect(decoded.containsKey('media'), isFalse);
      controller.dispose();
    });

    test('user-cancel save dialog yields cancelled phase', () async {
      final repo = FakeJobsRepository();
      final controller = ExportController(
        jobsRepository: repo,
        writer: ({required suggestedName, required contents}) async => null,
      );

      await controller.exportLibrary();

      expect(controller.phase, ExportPhase.cancelled);
      expect(controller.savedPath, isNull);
      controller.dispose();
    });

    test('export error surfaces without retry', () async {
      final repo = FakeJobsRepository(
        exportError: StateError('export down'),
      );
      final controller = ExportController(jobsRepository: repo);

      await controller.exportLibrary();

      expect(controller.phase, ExportPhase.error);
      expect(controller.error, isA<StateError>());
      controller.dispose();
    });
  });
}
