import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// D13 §5 / R8: no long-lived provider key or server-only filter logic.
void main() {
  test('item-list lib sources contain no provider key / secret patterns (R8)',
      () {
    final roots = <FileSystemEntity>[
      Directory('lib/item_lists'),
      File('lib/api/item_lists_repository.dart'),
    ];
    final pattern = RegExp(
      r'sk_test_|sk_live_|CLERK_SECRET_KEY|GEMINI_API_KEY|AIza[0-9A-Za-z_-]{20,}',
    );
    final hits = <String>[];
    for (final root in roots) {
      final files = <File>[];
      if (root is File) {
        files.add(root);
      } else if (root is Directory && root.existsSync()) {
        for (final entity in root.listSync(recursive: true)) {
          if (entity is File && entity.path.endsWith('.dart')) {
            files.add(entity);
          }
        }
      }
      for (final file in files) {
        if (pattern.hasMatch(file.readAsStringSync())) {
          hits.add(file.path);
        }
      }
    }
    expect(hits, isEmpty, reason: 'secret patterns in: $hits');
  });

  test('item-list client implements no server-only logic (R8/§4)', () {
    final files = [
      File('lib/api/item_lists_repository.dart'),
      File('lib/item_lists/item_list_export_controller.dart'),
      File('lib/item_lists/item_list_export_page.dart'),
      File('lib/item_lists/item_list_csv.dart'),
    ];
    for (final file in files) {
      final source = file.readAsStringSync();
      expect(source.contains('estimateCost'), isFalse);
      expect(source.contains('reserve('), isFalse);
      expect(source.contains('mintUpload'), isFalse);
      expect(source.contains('decidePersonLink'), isFalse);
      expect(source.contains('TaggingProvider'), isFalse);
      expect(source.contains('GEMINI_API_KEY'), isFalse);
      expect(source.contains('prisma'), isFalse);
    }
  });

  test('item-list client never posts media bytes to tagkin-api (R1/R5/R7)', () {
    final files = [
      File('lib/api/item_lists_repository.dart'),
      File('lib/item_lists/item_list_export_controller.dart'),
    ];
    for (final file in files) {
      final source = file.readAsStringSync();
      expect(source.contains('multipart'), isFalse);
      expect(source.contains('FormData'), isFalse);
      expect(source.contains('putBytes'), isFalse);
      expect(
        RegExp(r'ownerUserId').hasMatch(source),
        isFalse,
        reason: '${file.path} must not send ownerUserId',
      );
    }
  });

  test('item-list UI uses canonical domain terms (R2)', () {
    final page =
        File('lib/item_lists/item_list_export_page.dart').readAsStringSync();
    final csv =
        File('lib/item_lists/item_list_csv.dart').readAsStringSync();
    final combined = '$page\n$csv';
    expect(combined.contains('Item list'), isTrue);
    expect(combined.contains('Key period'), isTrue);
    expect(combined.toLowerCase().contains('annotation'), isFalse);
    expect(combined.toLowerCase().contains('chapter'), isFalse);
    expect(combined.toLowerCase().contains('playlist'), isFalse);
  });
}
