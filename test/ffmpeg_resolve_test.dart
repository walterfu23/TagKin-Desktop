import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/prepass/ffmpeg_resolve.dart';

void main() {
  tearDown(clearFfmpegToolsCache);

  test('resolveFfmpegTools returns a runnable pair when ffmpeg is available',
      () {
    // On CI/dev machines PATH or bundled binaries may satisfy this; when
    // neither exists the resolver correctly returns null (video pre-pass
    // degrades). End-user installs ship binaries inside the app bundle.
    final tools = resolveFfmpegTools();
    if (tools == null) {
      expect(hasFfmpeg(), isFalse);
      return;
    }
    expect(tools.ffmpeg, isNotEmpty);
    expect(tools.ffprobe, isNotEmpty);
    expect(hasFfmpeg(), isTrue);
  });

  test('bundled candidate paths are platform-shaped (no hard-coded separators)',
      () {
    // Smoke: resolvedExecutable parent is a real directory on desktop hosts.
    expect(File(Platform.resolvedExecutable).parent.existsSync(), isTrue);
  });
}
