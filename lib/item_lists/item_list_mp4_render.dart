import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/ingest/folder_bookmark_store.dart';
import 'package:tagkin_desktop/item_lists/item_list_mp4_filter.dart';
import 'package:tagkin_desktop/item_lists/item_list_mp4_materialize.dart';
import 'package:tagkin_desktop/item_lists/item_list_nle.dart';
import 'package:tagkin_desktop/prepass/ffmpeg_resolve.dart';

export 'item_list_mp4_materialize.dart' show ItemListMp4RenderException;

/// Last encode workspace (stills, clips, argv, ffmpeg.log). Overwritten each Export.
const kItemListMp4DumpDir = '/Users/w/test/out/tagkin-mp4-last';

String get itemListMp4TempDumpDir =>
    p.join(Directory.systemTemp.path, 'tagkin-mp4-last');

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

String _scaleFilter({
  required int sequenceWidth,
  required int sequenceHeight,
  required bool scaleToFit,
}) {
  final w = sequenceWidth < 2 ? 2 : sequenceWidth - (sequenceWidth % 2);
  final h = sequenceHeight < 2 ? 2 : sequenceHeight - (sequenceHeight % 2);
  return scaleToFit
      ? 'scale=$w:$h:force_original_aspect_ratio=decrease,'
          'pad=$w:$h:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1'
      : 'scale=$w:$h:force_original_aspect_ratio=increase,'
          'crop=$w:$h,setsar=1';
}

/// ffmpeg argv: one still or key period → finite H.264 `clip-N.mp4`.
List<String> itemListMp4ClipEncodeArgs({
  required ItemListMp4Input input,
  required String outputPath,
  required int sequenceWidth,
  required int sequenceHeight,
  required bool scaleToFit,
}) {
  final scale = _scaleFilter(
    sequenceWidth: sequenceWidth,
    sequenceHeight: sequenceHeight,
    scaleToFit: scaleToFit,
  );
  final args = <String>['-y', '-hide_banner', '-loglevel', 'warning'];
  if (input.isStill) {
    args.addAll([
      '-framerate',
      '$kItemListNleTimebase',
      '-loop',
      '1',
      '-i',
      input.path,
      '-t',
      input.durationSeconds.toStringAsFixed(3),
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
  args.addAll([
    '-an',
    '-vf',
    '$scale,fps=$kItemListNleTimebase,format=yuv420p',
    '-c:v',
    'libx264',
    '-profile:v',
    'high',
    '-level',
    '4.1',
    '-pix_fmt',
    'yuv420p',
    '-tag:v',
    'avc1',
    '-r',
    '$kItemListNleTimebase',
    outputPath,
  ]);
  return args;
}

/// ffmpeg argv: assembled H.264 clips + WAV → QuickTime MP4.
List<String> itemListMp4AssembleArgs({
  required ItemListMp4Plan plan,
  required String audioPath,
  required String outputPath,
}) {
  final args = <String>['-y', '-hide_banner', '-loglevel', 'warning'];
  for (final input in plan.inputs) {
    args.addAll(['-i', input.path]);
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
    '-profile:v',
    'high',
    '-level',
    '4.1',
    '-pix_fmt',
    'yuv420p',
    '-tag:v',
    'avc1',
    '-c:a',
    'aac',
    '-profile:a',
    'aac_low',
    '-ar',
    '44100',
    '-ac',
    '2',
    '-b:a',
    '192k',
    '-movflags',
    '+faststart',
    '-t',
    plan.videoDurationSeconds.toStringAsFixed(3),
    outputPath,
  ]);
  return args;
}

/// Decode [audioPath] to stereo 44.1 kHz PCM WAV so `-stream_loop` is reliable.
Future<void> itemListMp4DecodeSoundtrackWav({
  required String ffmpeg,
  required String audioPath,
  required String destPath,
}) async {
  final staged =
      p.join(p.dirname(destPath), 'soundtrack-src${p.extension(audioPath)}');
  try {
    await File(audioPath).copy(staged);
  } catch (e) {
    throw ItemListMp4RenderException(
      'Could not read the soundtrack for MP4 export: $e',
    );
  }
  final result = await Process.run(
    ffmpeg,
    [
      '-y',
      '-hide_banner',
      '-loglevel',
      'warning',
      '-i',
      staged,
      '-ac',
      '2',
      '-ar',
      '44100',
      destPath,
    ],
    runInShell: false,
  );
  final wav = File(destPath);
  if (result.exitCode != 0 || !wav.existsSync() || wav.lengthSync() == 0) {
    final err = (result.stderr as String).trim();
    throw ItemListMp4RenderException(
      err.isEmpty ? 'Could not decode the soundtrack for MP4 export.' : err,
    );
  }
}

Future<void> _copyDumpDir(String fromDir, String toDir) async {
  final dest = Directory(toDir);
  if (dest.existsSync()) {
    dest.deleteSync(recursive: true);
  }
  dest.createSync(recursive: true);
  final src = Directory(fromDir);
  if (!src.existsSync()) return;
  for (final entity in src.listSync(recursive: true)) {
    if (entity is! File) continue;
    final rel = p.relative(entity.path, from: fromDir);
    final out = File(p.join(toDir, rel));
    out.parent.createSync(recursive: true);
    entity.copySync(out.path);
  }
}

/// Copy [tempDir] to the inspectable dump paths and write [log].
Future<void> itemListMp4WriteDump({
  required String tempDir,
  required String log,
  String? dumpDir,
}) async {
  final primary = dumpDir ?? kItemListMp4DumpDir;
  try {
    await _copyDumpDir(tempDir, primary);
    await File(p.join(primary, 'ffmpeg.log')).writeAsString(log);
  } catch (_) {}
  try {
    await _copyDumpDir(tempDir, itemListMp4TempDumpDir);
    await File(p.join(itemListMp4TempDumpDir, 'ffmpeg.log')).writeAsString(log);
  } catch (_) {}
}

Future<({int exitCode, String stderr})> _runFfmpegLogged({
  required String ffmpeg,
  required List<String> args,
  required StringBuffer log,
  required String label,
}) async {
  log.writeln('==> $label');
  log.writeln('$ffmpeg ${args.join(' ')}');
  log.writeln('filter_complex:');
  final fc = args.indexOf('-filter_complex');
  if (fc >= 0 && fc + 1 < args.length) {
    log.writeln(args[fc + 1]);
  }
  final result = await Process.run(ffmpeg, args, runInShell: false);
  final err = (result.stderr as String).trim();
  final out = (result.stdout as String).trim();
  log.writeln('exit ${result.exitCode}');
  if (out.isNotEmpty) log.writeln(out);
  if (err.isNotEmpty) log.writeln(err);
  log.writeln('');
  return (exitCode: result.exitCode, stderr: err);
}

/// Render [timeline] + [audioPath] to [outputPath] (H.264 / AAC).
///
/// Each still/key period is encoded to `clip-N.mp4` first, then those clips
/// are xfade/concat'd with the WAV soundtrack. The workspace is copied to
/// [kItemListMp4DumpDir] for inspection.
Future<void> itemListRenderMp4({
  required ItemListNleTimeline timeline,
  required String audioPath,
  required String outputPath,
  required int sequenceWidth,
  required int sequenceHeight,
  required bool scaleToFit,
  double audioFadeOutSeconds = 2,
  bool useMacSavePanel = true,
  String? dumpDir,
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

  final tempDir = Directory.systemTemp.createTempSync('tagkin-mp4-');
  final tempOut = p.join(tempDir.path, 'item-list.mp4');
  final log = StringBuffer();
  var ok = false;
  try {
    final byOriginal = await itemListMaterializeMp4Inputs(
      clips: timeline.clips,
      destDir: tempDir.path,
    );
    final staged = itemListMp4TimelineWithMaterializedPaths(timeline, byOriginal);
    final sourcePlan = itemListMp4Plan(
      timeline: staged,
      sequenceWidth: sequenceWidth,
      sequenceHeight: sequenceHeight,
      scaleToFit: scaleToFit,
      audioFadeOutSeconds: audioFadeOutSeconds,
    );
    final wavPath = p.join(tempDir.path, 'soundtrack.wav');
    await itemListMp4DecodeSoundtrackWav(
      ffmpeg: tools.ffmpeg,
      audioPath: audioPath,
      destPath: wavPath,
    );

    final clipPaths = <String>[];
    for (var i = 0; i < sourcePlan.inputs.length; i++) {
      final clipOut = p.join(tempDir.path, 'clip-$i.mp4');
      final clipArgs = itemListMp4ClipEncodeArgs(
        input: sourcePlan.inputs[i],
        outputPath: clipOut,
        sequenceWidth: sequenceWidth,
        sequenceHeight: sequenceHeight,
        scaleToFit: scaleToFit,
      );
      final ran = await _runFfmpegLogged(
        ffmpeg: tools.ffmpeg,
        args: clipArgs,
        log: log,
        label: 'clip-$i',
      );
      final clip = File(clipOut);
      if (ran.exitCode != 0 || !clip.existsSync() || clip.lengthSync() == 0) {
        throw ItemListMp4RenderException(
          ran.stderr.isEmpty
              ? 'ffmpeg wrote an empty clip-$i.mp4. Log: $kItemListMp4DumpDir or $itemListMp4TempDumpDir'
              : '${ran.stderr}\nLog: $kItemListMp4DumpDir or $itemListMp4TempDumpDir',
        );
      }
      clipPaths.add(clipOut);
    }

    final assembleTimeline = itemListMp4TimelineWithClipVideos(staged, clipPaths);
    final assemblePlan = itemListMp4Plan(
      timeline: assembleTimeline,
      sequenceWidth: sequenceWidth,
      sequenceHeight: sequenceHeight,
      scaleToFit: scaleToFit,
      audioFadeOutSeconds: audioFadeOutSeconds,
    );
    final args = itemListMp4AssembleArgs(
      plan: assemblePlan,
      audioPath: wavPath,
      outputPath: tempOut,
    );
    await File(p.join(tempDir.path, 'argv.txt')).writeAsString(
      '${tools.ffmpeg}\n${args.join(' ')}\n\nfilter_complex:\n'
      '${assemblePlan.filterComplex}\n',
    );
    final ran = await _runFfmpegLogged(
      ffmpeg: tools.ffmpeg,
      args: args,
      log: log,
      label: 'assemble',
    );
    if (ran.exitCode != 0) {
      throw ItemListMp4RenderException(
        ran.stderr.isEmpty
            ? 'ffmpeg failed to render MP4. Log: $kItemListMp4DumpDir or $itemListMp4TempDumpDir'
            : '${ran.stderr}\nLog: $kItemListMp4DumpDir or $itemListMp4TempDumpDir',
      );
    }
    final encoded = File(tempOut);
    if (!encoded.existsSync() || encoded.lengthSync() == 0) {
      throw ItemListMp4RenderException(
        'ffmpeg wrote an empty MP4. Log: $kItemListMp4DumpDir or $itemListMp4TempDumpDir',
      );
    }
    final macSave =
        useMacSavePanel && SecurityScopedBookmarks.isSupported;
    if (macSave) {
      final n = await SecurityScopedBookmarks.installSaveFile(tempOut);
      if (n <= 0) {
        throw ItemListMp4RenderException(
          'The exported MP4 was empty. Save As again and keep it in a folder TagKin can write.',
        );
      }
    } else {
      await encoded.copy(outputPath);
      final dest = File(outputPath);
      if (!dest.existsSync() || dest.lengthSync() == 0) {
        throw ItemListMp4RenderException(
          'The exported MP4 was empty. Save As again and keep it in a folder TagKin can write.',
        );
      }
    }
    ok = true;
  } finally {
    try {
      await itemListMp4WriteDump(
        tempDir: tempDir.path,
        log: log.toString(),
        dumpDir: dumpDir,
      );
    } catch (_) {}
    if (ok) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
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
