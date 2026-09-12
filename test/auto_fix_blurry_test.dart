import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/prefs/desktop_prefs.dart';
import 'package:tagkin_desktop/prepass/auto_fix_blurry.dart';
import 'package:tagkin_desktop/prepass/unsharp.dart';

Uint8List _grayJpeg() {
  final flat = img.Image(width: 32, height: 32);
  img.fill(flat, color: img.ColorRgb8(120, 120, 120));
  return Uint8List.fromList(img.encodeJpg(flat, quality: 95));
}

void main() {
  test('unsharpMask preserves dimensions', () {
    final src = img.Image(width: 16, height: 12);
    img.fill(src, color: img.ColorRgb8(10, 20, 30));
    final out = unsharpMask(src);
    expect(out.width, 16);
    expect(out.height, 12);
  });

  test('auto-fix off or unknown sharpness does not write files', () async {
    final dir = await Directory.systemTemp.createTemp('autofix_off_');
    addTearDown(() => dir.delete(recursive: true));
    final original = File(p.join(dir.path, 'Holiday.jpg'));
    await original.writeAsBytes(_grayJpeg());
    final cache = Directory(p.join(dir.path, 'cache'));

    expect(
      await autoFixBlurryPhoto(
        originalPath: original.path,
        originalBytes: await original.readAsBytes(),
        sharpness: 1,
        contentHash: 'hash1',
        prefs: const DesktopPrefs(autoFixBlurryPhotos: false),
        cacheDir: cache,
      ),
      isNull,
    );
    expect(
      await autoFixBlurryPhoto(
        originalPath: original.path,
        originalBytes: await original.readAsBytes(),
        sharpness: null,
        contentHash: 'hash1',
        prefs: const DesktopPrefs(autoFixBlurryPhotos: true),
        cacheDir: cache,
      ),
      isNull,
    );
    expect(await cache.exists(), isFalse);
    expect(File(p.join(dir.path, 'Holiday.tagkin-fixed.jpg')).existsSync(), isFalse);
  });

  test('auto-fix writes cache JPEG and optional album sidecar, never overwrites original',
      () async {
    final dir = await Directory.systemTemp.createTemp('autofix_on_');
    addTearDown(() => dir.delete(recursive: true));
    final original = File(p.join(dir.path, 'Holiday.jpg'));
    final originalBytes = _grayJpeg();
    await original.writeAsBytes(originalBytes);
    final cache = Directory(p.join(dir.path, 'cache'));

    final fixed = await autoFixBlurryPhoto(
      originalPath: original.path,
      originalBytes: originalBytes,
      sharpness: 1,
      contentHash: 'abc',
      prefs: const DesktopPrefs(
        autoFixBlurryPhotos: true,
        saveFixedPhotoInFolder: true,
      ),
      cacheDir: cache,
    );
    expect(fixed, isNotNull);
    expect(File(fixed!.cachePath).existsSync(), isTrue);
    expect(fixed.sidecarPath, p.join(dir.path, 'Holiday.tagkin-fixed.jpg'));
    expect(File(fixed.sidecarPath!).existsSync(), isTrue);
    expect(await original.readAsBytes(), originalBytes);
  });
}
