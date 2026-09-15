import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/item_lists/item_list_mp4_filter.dart';
import 'package:tagkin_desktop/item_lists/item_list_nle.dart';
import 'package:tagkin_desktop/prepass/ffmpeg_resolve.dart';

class ItemListMp4RenderException implements Exception {
  ItemListMp4RenderException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// True when bundled/PATH ffmpeg can encode H.264 and AAC.
Future<bool> itemListMp4EncodersAvailable() async {
  final tools = resolveFfmpegTools();
  if (tools == null) return false;
  final result = await Process.run(
    tools.ffmpeg,
    ['-hide_banner', '-encoders'],
    runInShell: false,
  );
  if (result.exitCode != 0) return false;
  final text = '${result.stdout}\n${result.stderr}';
  return text.contains('libx264') &&
      (text.contains('aac') || text.contains('libfdk_aac'));
}

/// Render [timeline] + [audioPath] to [outputPath] (H.264 / AAC).
Future<void> itemListRenderMp4({
  required ItemListNleTimeline timeline,
  required String audioPath,
  required String outputPath,
  required int sequenceWidth,
  required int sequenceHeight,
  required bool scaleToFit,
  double audioFadeOutSeconds = 2,
}) async {
  final tools = resolveFfmpegTools();
  if (tools == null) {
    throw ItemListMp4RenderException(
      'ffmpeg is not available. MP4 export needs the bundled encoder.',
    );
  }
  if (!await itemListMp4EncodersAvailable()) {
    throw ItemListMp4RenderException(
      'This ffmpeg build cannot encode H.264/AAC. MP4 export cannot run.',
    );
  }
  if (!File(audioPath).existsSync()) {
    throw ItemListMp4RenderException('Generated music file is missing.');
  }

  final plan = itemListMp4Plan(
    timeline: timeline,
    sequenceWidth: sequenceWidth,
    sequenceHeight: sequenceHeight,
    scaleToFit: scaleToFit,
    audioFadeOutSeconds: audioFadeOutSeconds,
  );

  final args = <String>['-y', '-hide_banner', '-loglevel', 'error'];
  for (final input in plan.inputs) {
    if (input.isStill) {
      args.addAll([
        '-loop',
        '1',
        '-t',
        input.durationSeconds.toStringAsFixed(3),
        '-i',
        input.path,
      ]);
    } else {
      args.addAll([
        '-ss',
        input.sourceStartSeconds.toStringAsFixed(3),
        '-t',
        input.durationSeconds.toStringAsFixed(3),
        '-i',
        input.path,
      ]);
    }
  }
  args.addAll(['-stream_loop', '-1', '-i', audioPath]);
  args.addAll([
    '-filter_complex',
    plan.filterComplex,
    '-map',
    '[vout]',
    '-map',
    '[aout]',
    '-c:v',
    'libx264',
    '-pix_fmt',
    'yuv420p',
    '-c:a',
    'aac',
    '-shortest',
    outputPath,
  ]);

  final result = await Process.run(tools.ffmpeg, args, runInShell: false);
  if (result.exitCode != 0) {
    final err = (result.stderr as String).trim();
    throw ItemListMp4RenderException(
      err.isEmpty ? 'ffmpeg failed to render MP4' : err,
    );
  }
}

/// Probe duration of a media file in seconds (ffprobe).
Future<double?> itemListMp4ProbeDurationSeconds(String path) async {
  final tools = resolveFfmpegTools();
  if (tools == null) return null;
  final result = await Process.run(
    tools.ffprobe,
    [
      '-v',
      'error',
      '-show_entries',
      'format=duration',
      '-of',
      'default=noprint_wrappers=1:nokey=1',
      path,
    ],
    runInShell: false,
  );
  if (result.exitCode != 0) return null;
  return double.tryParse((result.stdout as String).trim());
}

String itemListMp4TempOutputPath() {
  final dir = Directory.systemTemp.createTempSync('tagkin-mp4-');
  return p.join(dir.path, 'item-list.mp4');
}
