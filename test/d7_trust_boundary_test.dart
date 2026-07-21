import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// D7 §5 / R8: no long-lived provider key or server-only logic in D7 sources.
void main() {
  test('jobs lib sources contain no provider key / secret patterns (R8)', () {
    final roots = [
      Directory('lib/jobs'),
      Directory('lib/api'),
    ];
    final pattern = RegExp(
      r'sk_test_|sk_live_|CLERK_SECRET_KEY|GEMINI_API_KEY|AIza[0-9A-Za-z_-]{20,}',
    );
    final hits = <String>[];
    for (final root in roots) {
      if (!root.existsSync()) continue;
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final text = entity.readAsStringSync();
        if (pattern.hasMatch(text)) {
          hits.add(entity.path);
        }
      }
    }
    expect(hits, isEmpty, reason: 'secret patterns in: $hits');
  });

  test('JobsRepository / JobsController implement no server-only logic', () {
    final repo = File('lib/api/jobs_repository.dart').readAsStringSync();
    final controller = File('lib/jobs/jobs_controller.dart').readAsStringSync();
    final export = File('lib/jobs/export_controller.dart').readAsStringSync();

    for (final source in [repo, controller, export]) {
      expect(source.contains('estimateCost'), isFalse);
      expect(source.contains('reserve('), isFalse);
      expect(source.contains('mintUpload'), isFalse);
      expect(source.contains('decidePersonLink'), isFalse);
      expect(source.contains('TaggingProvider'), isFalse);
      expect(source.contains('GEMINI_API_KEY'), isFalse);
    }
  });
}
