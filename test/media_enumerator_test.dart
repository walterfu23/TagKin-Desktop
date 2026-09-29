import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/media_enumerator.dart';

void main() {
  group('MediaEnumerator (real fixture folder — synthetic bytes only)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('d3_enumerator_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    Future<File> writeFixture(String relativePath) async {
      final file = File(p.join(tempDir.path, relativePath));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(const [0]);
      return file;
    }

    test('lists supported photo/video files, skips unsupported and hidden',
        () async {
      await writeFixture('photo.jpg');
      await writeFixture('clip.mp4');
      await writeFixture('nested/deep.png');
      await writeFixture('notes.txt'); // unsupported extension
      await writeFixture('.DS_Store'); // OS-generated, always skipped
      await writeFixture('.hidden.jpg'); // dotfile — skipped regardless of ext

      final results = await MediaEnumerator().enumerate(tempDir.path);
      final names = results.map((c) => p.basename(c.path)).toSet();

      expect(names, {'photo.jpg', 'clip.mp4', 'deep.png'});
      final typeByName = {
        for (final c in results) p.basename(c.path): c.type,
      };
      expect(typeByName['photo.jpg'], ItemType.photo);
      expect(typeByName['clip.mp4'], ItemType.video);
      expect(typeByName['deep.png'], ItemType.photo);
    });

    test('throws for a non-existent root folder', () async {
      await expectLater(
        MediaEnumerator().enumerate(p.join(tempDir.path, 'does-not-exist')),
        throwsArgumentError,
      );
    });

    test('a symlinked directory is not recursed into (loop-safe)', () async {
      final looped = Directory(p.join(tempDir.path, 'looped'))..createSync();
      await writeFixture('looped/photo.jpg');
      try {
        Link(p.join(looped.path, 'back-to-root')).createSync(tempDir.path);
      } on FileSystemException {
        return; // symlink creation unavailable in this environment; skip
      }

      final results = await MediaEnumerator()
          .enumerate(tempDir.path)
          .timeout(const Duration(seconds: 5));
      final names = results.map((c) => p.basename(c.path)).toList();
      // Found once via the real path; never re-discovered through the
      // symlinked path back to the root (would otherwise loop forever).
      expect(names.where((n) => n == 'photo.jpg').length, 1);
    });
  });

  group('classifyByExtension / isIgnoredName (pure, cross-OS)', () {
    test('classifies Windows-style paths correctly, even off Windows', () {
      final windows = p.Context(style: p.Style.windows);
      expect(
        classifyByExtension(r'C:\Users\me\Pictures\trip.JPG', context: windows),
        ItemType.photo,
      );
      expect(
        classifyByExtension(r'C:\Users\me\Videos\clip.mov', context: windows),
        ItemType.video,
      );
      expect(
        classifyByExtension(r'C:\Users\me\Docs\notes.txt', context: windows),
        isNull,
      );
    });

    test('classifies POSIX-style (macOS) paths correctly', () {
      final posix = p.Context(style: p.Style.posix);
      expect(
        classifyByExtension('/Users/me/Pictures/trip.jpeg', context: posix),
        ItemType.photo,
      );
      expect(
        classifyByExtension('/Users/me/Videos/clip.mkv', context: posix),
        ItemType.video,
      );
      expect(
        classifyByExtension('/Users/me/Docs/notes.txt', context: posix),
        isNull,
      );
    });

    test('isIgnoredName flags dotfiles and known OS system files', () {
      expect(isIgnoredName('.DS_Store'), isTrue);
      expect(isIgnoredName('Thumbs.db'), isTrue);
      expect(isIgnoredName('desktop.ini'), isTrue);
      expect(isIgnoredName('.hidden.jpg'), isTrue);
      expect(isIgnoredName('photo.jpg'), isFalse);
    });
  });
}
