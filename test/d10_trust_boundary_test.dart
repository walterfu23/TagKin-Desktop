import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// D10 §5 / R8: no long-lived provider key or server-only logic in
/// corrections/comments sources. Also asserts no media bytes (R1).
void main() {
  test('knowledge lib sources contain no provider key / secret patterns (R8)',
      () {
    final roots = [
      Directory('lib/knowledge'),
      Directory('lib/api'),
      Directory('lib/review'),
    ];
    final pattern = RegExp(
      r'sk_test_|sk_live_|CLERK_SECRET_KEY|GEMINI_API_KEY|AIza[0-9A-Za-z_-]{20,}',
    );
    final hits = <String>[];
    for (final root in roots) {
      if (!root.existsSync()) continue;
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.contains('lib/api/') &&
            !entity.path.endsWith('corrections_repository.dart') &&
            !entity.path.endsWith('comments_repository.dart') &&
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

  test('corrections/comments code implements no server-only logic (R8/§4)', () {
    final files = [
      File('lib/api/corrections_repository.dart'),
      File('lib/api/comments_repository.dart'),
      File('lib/knowledge/corrections_history_view.dart'),
      File('lib/knowledge/comments_view.dart'),
      File('lib/knowledge/tag_edit_dialog.dart'),
      File('lib/review/review_controller.dart'),
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
    }
  });

  test('corrections/comments never post media bytes to tagkin-api (R1/R5/R7)',
      () {
    final files = [
      File('lib/api/corrections_repository.dart'),
      File('lib/api/comments_repository.dart'),
      File('lib/knowledge/corrections_history_view.dart'),
      File('lib/knowledge/comments_view.dart'),
      File('lib/knowledge/tag_edit_dialog.dart'),
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

  test('corrections/comments UI uses canonical domain terms (R2)', () {
    final history =
        File('lib/knowledge/corrections_history_view.dart').readAsStringSync();
    final comments =
        File('lib/knowledge/comments_view.dart').readAsStringSync();
    final knowledge =
        File('lib/review/knowledge_view.dart').readAsStringSync();
    final combined = '$history\n$comments\n$knowledge';
    expect(combined.contains('tag') || combined.contains('Tag'), isTrue);
    expect(combined.contains('comment') || combined.contains('Comment'), isTrue);
    expect(combined.contains('Correction'), isTrue);
    expect(combined.toLowerCase().contains('annotation'), isFalse);
    expect(combined.toLowerCase().contains('chapter'), isFalse);
  });
}
