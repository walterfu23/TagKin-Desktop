import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// D8 §5 / R8: no long-lived provider key or server-only logic in review sources.
/// Also asserts no media bytes are posted to tagkin-api from review code (R1/R5).
void main() {
  test('review lib sources contain no provider key / secret patterns (R8)', () {
    final root = Directory('lib/review');
    final pattern = RegExp(
      r'sk_test_|sk_live_|CLERK_SECRET_KEY|GEMINI_API_KEY|AIza[0-9A-Za-z_-]{20,}',
    );
    final hits = <String>[];
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      if (pattern.hasMatch(text)) {
        hits.add(entity.path);
      }
    }
    expect(hits, isEmpty, reason: 'secret patterns in: $hits');
  });

  test('review code implements no server-only logic (R8/§4)', () {
    final root = Directory('lib/review');
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      expect(source.contains('estimateCost'), isFalse);
      expect(source.contains('reserve('), isFalse);
      expect(source.contains('mintUpload'), isFalse);
      expect(source.contains('decidePersonLink'), isFalse);
      expect(source.contains('TaggingProvider'), isFalse);
      expect(source.contains('GEMINI_API_KEY'), isFalse);
    }
  });

  test('review code never posts media bytes to tagkin-api (R1/R5/R7)', () {
    final root = Directory('lib/review');
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      // Knowledge fetch is GET-only; no multipart / byte upload helpers.
      expect(source.contains('multipart'), isFalse);
      expect(source.contains('FormData'), isFalse);
      expect(source.contains('putBytes'), isFalse);
      expect(source.contains('uploadUrl'), isFalse);
      // Must not target tagkin-api with file bodies.
      expect(
        RegExp(r"post\([^)]*bytes", caseSensitive: false).hasMatch(source),
        isFalse,
      );
    }
  });

  test('review UI uses canonical domain terms (R2); no browse/search', () {
    final reviewUi = File('lib/review/knowledge_view.dart').readAsStringSync();
    final scrubber =
        File('lib/review/key_period_scrubber.dart').readAsStringSync();
    final page = File('lib/review/item_review_page.dart').readAsStringSync();
    final combined = '$reviewUi\n$scrubber\n$page';

    expect(combined.contains('Key period'), isTrue);
    expect(combined.toLowerCase().contains('annotation'), isFalse);
    expect(combined.toLowerCase().contains('chapter'), isFalse);
    expect(combined.toLowerCase().contains('key point'), isFalse);
    expect(combined.contains('Search'), isFalse);
    expect(combined.contains('Filter'), isFalse);
    expect(combined.contains('Browse'), isFalse);
  });
}
