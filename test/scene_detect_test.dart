import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/prepass/scene_detect.dart';

void main() {
  group('scene detection', () {
    test('hasFfmpeg returns a bool without throwing', () {
      expect(hasFfmpeg(), anyOf(isTrue, isFalse));
    });
  });

  group('scene detection (ffmpeg)', () {
    test(
      'yields key periods within duration bounds',
      () async {
        final dir = await Directory.systemTemp.createTemp('tagkin_scene_');
        final path = '${dir.path}/clip.mp4';
        addTearDown(() => dir.deleteSync(recursive: true));

        final gen = await Process.run(
          'ffmpeg',
          [
            '-y',
            '-f',
            'lavfi',
            '-i',
            'color=c=blue:s=64x64:d=2',
            '-c:v',
            'libx264',
            '-pix_fmt',
            'yuv420p',
            '-t',
            '2',
            path,
          ],
          runInShell: false,
        );
        expect(gen.exitCode, 0, reason: gen.stderr.toString());

        final result = await detectSceneKeyPeriods(path);
        expect(result.durationMs, greaterThan(0));
        expect(result.keyPeriods, isNotEmpty);
        for (final kp in result.keyPeriods) {
          expect(kp.startMs, greaterThanOrEqualTo(0));
          expect(kp.endMs, lessThanOrEqualTo(result.durationMs + 1));
          expect(kp.endMs, greaterThan(kp.startMs));
        }
      },
      skip: hasFfmpeg() ? false : 'ffprobe/ffmpeg not on PATH',
    );
  });
}
