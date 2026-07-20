import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/ingest/content_hash.dart';

void main() {
  group('computeContentHash', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('d3_content_hash_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('identical bytes produce identical hash', () async {
      final a = File('${tempDir.path}/a.bin')
        ..writeAsBytesSync([1, 2, 3, 4, 5]);
      final b = File('${tempDir.path}/b.bin')
        ..writeAsBytesSync([1, 2, 3, 4, 5]);

      final hashA = await computeContentHash(a.path);
      final hashB = await computeContentHash(b.path);
      expect(hashA, hashB);
    });

    test('a single differing byte changes the hash', () async {
      final a = File('${tempDir.path}/a.bin')
        ..writeAsBytesSync([1, 2, 3, 4, 5]);
      final b = File('${tempDir.path}/b.bin')
        ..writeAsBytesSync([1, 2, 3, 4, 6]);

      final hashA = await computeContentHash(a.path);
      final hashB = await computeContentHash(b.path);
      expect(hashA, isNot(hashB));
    });

    test('hash is a 64-character lowercase hex string (SHA-256)', () async {
      final file = File('${tempDir.path}/c.bin')
        ..writeAsBytesSync([9, 9, 9]);
      final hash = await computeContentHash(file.path);
      expect(hash, matches(RegExp(r'^[0-9a-f]{64}$')));
    });
  });
}
