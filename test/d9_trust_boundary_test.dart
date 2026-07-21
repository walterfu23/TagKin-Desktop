import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// D9 §5 / R8: no long-lived provider key or server-only logic in person
/// sources. Also asserts no media bytes / embedding vectors (R1).
void main() {
  test('persons lib sources contain no provider key / secret patterns (R8)',
      () {
    final roots = [
      Directory('lib/persons'),
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
        // Only scan D9-owned files under lib/api.
        if (entity.path.contains('lib/api/') &&
            !entity.path.endsWith('persons_repository.dart') &&
            !entity.path.endsWith('items_repository.dart')) {
          continue;
        }
        final text = entity.readAsStringSync();
        if (pattern.hasMatch(text)) {
          hits.add(entity.path);
        }
      }
    }
    expect(hits, isEmpty, reason: 'secret patterns in: $hits');
  });

  test('persons code implements no server-only logic (R8/§4)', () {
    final files = [
      File('lib/persons/person_detail_controller.dart'),
      File('lib/persons/person_detail_page.dart'),
      File('lib/persons/persons_list_page.dart'),
      File('lib/persons/link_state_view.dart'),
      File('lib/api/persons_repository.dart'),
    ];
    for (final file in files) {
      final source = file.readAsStringSync();
      expect(source.contains('estimateCost'), isFalse, reason: file.path);
      expect(source.contains('reserve('), isFalse, reason: file.path);
      expect(source.contains('mintUpload'), isFalse, reason: file.path);
      expect(source.contains('decidePersonLink'), isFalse, reason: file.path);
      expect(source.contains('TaggingProvider'), isFalse, reason: file.path);
      expect(source.contains('GEMINI_API_KEY'), isFalse, reason: file.path);
      expect(source.contains('pgvector'), isFalse, reason: file.path);
      expect(source.contains('cosine'), isFalse, reason: file.path);
    }
  });

  test('persons code never posts media bytes to tagkin-api (R1/R5/R7)', () {
    final files = [
      File('lib/persons/person_detail_controller.dart'),
      File('lib/persons/person_detail_page.dart'),
      File('lib/persons/persons_list_page.dart'),
      File('lib/api/persons_repository.dart'),
    ];
    for (final file in files) {
      final source = file.readAsStringSync();
      expect(source.contains('multipart'), isFalse, reason: file.path);
      expect(source.contains('FormData'), isFalse, reason: file.path);
      expect(source.contains('putBytes'), isFalse, reason: file.path);
      expect(source.contains('uploadUrl'), isFalse, reason: file.path);
      expect(
        RegExp(r"post\([^)]*bytes", caseSensitive: false).hasMatch(source),
        isFalse,
        reason: file.path,
      );
    }
  });

  test('persons UI never requests or displays raw embedding vectors (R1)', () {
    final root = Directory('lib/persons');
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      expect(
        source.toLowerCase().contains('embedding'),
        isFalse,
        reason: entity.path,
      );
      expect(
        RegExp(r'\bvector\b', caseSensitive: false).hasMatch(source),
        isFalse,
        reason: entity.path,
      );
    }
    // Repository may mention "embedding" only in comments about never
    // returning them — assert no field access / deserialization of vectors.
    final repo = File('lib/api/persons_repository.dart').readAsStringSync();
    expect(repo.contains("['embedding']"), isFalse);
    expect(repo.contains('"embedding"'), isFalse);
    expect(repo.contains('.embedding'), isFalse);
  });

  test('persons UI uses canonical domain terms (R2)', () {
    final list = File('lib/persons/persons_list_page.dart').readAsStringSync();
    final detail =
        File('lib/persons/person_detail_page.dart').readAsStringSync();
    final combined = '$list\n$detail';
    expect(combined.contains('Person'), isTrue);
    expect(combined.contains('appearance'), isTrue);
    expect(combined.toLowerCase().contains('annotation'), isFalse);
    expect(combined.toLowerCase().contains('face cluster'), isFalse);
    expect(combined.contains('Search'), isFalse);
    expect(combined.contains('Filter'), isFalse);
    expect(combined.contains('Browse'), isFalse);
  });
}
