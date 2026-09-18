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

/// Cap on parallel `libx264` clip encodes (hardware encoders stay sequential).
const kItemListMp4MaxClipConcurrency = 4;

String get itemListMp4TempDumpDir =>
    p.join(Directory.systemTemp.path, 'tagkin-mp4-last');

/// H.264 encoder used for clip and assemble phases.
enum ItemListMp4EncoderKind {
  libx264,
  videotoolbox,
  mediaFoundation,
}

extension ItemListMp4EncoderKindX on ItemListMp4EncoderKind {
  String get codecName => switch (this) {
        ItemListMp4EncoderKind.libx264 => 'libx264',
        ItemListMp4EncoderKind.videotoolbox => 'h264_videotoolbox',
        ItemListMp4EncoderKind.mediaFoundation => 'h264_mf',
      };

  bool get isHardware => this != ItemListMp4EncoderKind.libx264;
}

typedef ItemListMp4EncoderResolver = Future<ItemListMp4EncoderKind> Function(
  String ffmpeg,
);

typedef ItemListMp4FfmpegRunner = Future<({int exitCode, String stderr})>
    Function({
  required String ffmpeg,
  required List<String> args,
  required StringBuffer log,
  required String label,
});

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

ItemListMp4EncoderKind? _cachedEncoder;

/// Clears the encoder probe cache (tests only).
void clearItemListMp4VideoEncoderCache() => _cachedEncoder = null;

/// Probe a tiny trial encode; cache the result for the process lifetime.
Future<ItemListMp4EncoderKind> resolveItemListMp4VideoEncoder(
  String ffmpeg,
) async {
  final cached = _cachedEncoder;
  if (cached != null) return cached;
  final candidate = Platform.isMacOS
      ? ItemListMp4EncoderKind.videotoolbox
      : Platform.isWindows
          ? ItemListMp4EncoderKind.mediaFoundation
          : ItemListMp4EncoderKind.libx264;
  if (!candidate.isHardware ||
      !await itemListMp4ProbeHardwareEncoder(ffmpeg, candidate)) {
    _cachedEncoder = ItemListMp4EncoderKind.libx264;
    return ItemListMp4EncoderKind.libx264;
  }
  _cachedEncoder = candidate;
  return candidate;
}

/// Trial-encode 2 frames with [encoder]. Hardware-only (`-allow_sw 0` on VT).
Future<bool> itemListMp4ProbeHardwareEncoder(
  String ffmpeg,
  ItemListMp4EncoderKind encoder,
) async {
  if (!encoder.isHardware) return false;
  final tmp = Directory.systemTemp.createTempSync('tagkin-mp4-probe-');
  try {
    final out = p.join(tmp.path, 'probe.mp4');
    final args = <String>[
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',
      '-f',
      'lavfi',
      '-i',
      'color=c=black:s=64x64:r=30',
      '-frames:v',
      '2',
      ...itemListMp4VideoEncoderArgs(
        encoder: encoder,
        sequenceWidth: 64,
        sequenceHeight: 64,
        assemble: false,
      ),
      '-an',
      out,
    ];
    final result = await Process.run(ffmpeg, args, runInShell: false);
    final file = File(out);
    return result.exitCode == 0 && file.existsSync() && file.lengthSync() > 0;
  } catch (_) {
    return false;
  } finally {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  }
}

/// Parallel clip workers when software-encoding; 1 when using hardware.
int itemListMp4ClipConcurrency({
  required ItemListMp4EncoderKind encoder,
  int? processorCount,
}) {
  if (encoder.isHardware) return 1;
  final n = processorCount ?? Platform.numberOfProcessors;
  return n.clamp(1, kItemListMp4MaxClipConcurrency);
}

/// Run [count] tasks with at most [maxConcurrent] in flight. Results stay
/// in index order.
Future<List<T>> itemListMp4RunWithConcurrency<T>({
  required int count,
  required int maxConcurrent,
  required Future<T> Function(int index) run,
}) async {
  if (count <= 0) return <T>[];
  final results = List<T?>.filled(count, null);
  var next = 0;
  Future<void> worker() async {
    while (true) {
      final i = next;
      next += 1;
      if (i >= count) return;
      results[i] = await run(i);
    }
  }

  final workers = maxConcurrent.clamp(1, count);
  await Future.wait(List.generate(workers, (_) => worker()));
  return [for (final r in results) r as T];
}

bool itemListMp4OutputOk(int exitCode, String path) {
  if (exitCode != 0) return false;
  final file = File(path);
  return file.existsSync() && file.lengthSync() > 0;
}

/// Run [args]; if a hardware encoder fails, retry once with [softwareArgs].
Future<({int exitCode, String stderr})> itemListMp4RunEncodeWithFallback({
  required String ffmpeg,
  required List<String> args,
  required List<String> softwareArgs,
  required ItemListMp4EncoderKind encoder,
  required String outputPath,
  required StringBuffer log,
  required String label,
  required ItemListMp4FfmpegRunner run,
}) async {
  var ran = await run(
    ffmpeg: ffmpeg,
    args: args,
    log: log,
    label: label,
  );
  if (itemListMp4OutputOk(ran.exitCode, outputPath)) return ran;
  if (!encoder.isHardware) return ran;
  return run(
    ffmpeg: ffmpeg,
    args: softwareArgs,
    log: log,
    label: '$label-libx264',
  );
}

/// Target bitrate (Mbps) for hardware H.264 (no CRF).
int itemListMp4HardwareBitrateMbps({
  required int sequenceWidth,
  required int sequenceHeight,
}) {
  final pixels = sequenceWidth * sequenceHeight;
  if (pixels <= 1280 * 720) return 4;
  if (pixels <= 1920 * 1080) return 8;
  return 16;
}

/// `-c:v` through `-tag:v` for [encoder]. Clip uses `ultrafast`; assemble
/// uses `veryfast` (libx264 only).
List<String> itemListMp4VideoEncoderArgs({
  required ItemListMp4EncoderKind encoder,
  required int sequenceWidth,
  required int sequenceHeight,
  required bool assemble,
}) {
  final args = <String>['-c:v', encoder.codecName];
  switch (encoder) {
    case ItemListMp4EncoderKind.libx264:
      args.addAll([
        '-preset',
        assemble ? 'veryfast' : 'ultrafast',
      ]);
    case ItemListMp4EncoderKind.videotoolbox:
      args.addAll(['-allow_sw', '0', '-realtime', '0']);
    case ItemListMp4EncoderKind.mediaFoundation:
      break;
  }
  if (encoder.isHardware) {
    final mbps = itemListMp4HardwareBitrateMbps(
      sequenceWidth: sequenceWidth,
      sequenceHeight: sequenceHeight,
    );
    args.addAll([
      '-b:v',
      '${mbps}M',
      '-maxrate',
      '${mbps}M',
      '-bufsize',
      '${mbps * 2}M',
    ]);
  }
  args.addAll([
    '-profile:v',
    'high',
    '-level',
    '4.1',
    '-pix_fmt',
    'yuv420p',
    '-tag:v',
    'avc1',
  ]);
  return args;
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
///
/// Stills have no audio (`-an`). Key periods keep source audio as AAC, or a
/// silent stereo bed when [hasAudio] is false so assemble can still duck.
List<String> itemListMp4ClipEncodeArgs({
  required ItemListMp4Input input,
  required String outputPath,
  required int sequenceWidth,
  required int sequenceHeight,
  required bool scaleToFit,
  bool hasAudio = false,
  ItemListMp4EncoderKind encoder = ItemListMp4EncoderKind.libx264,
}) {
  final scale = _scaleFilter(
    sequenceWidth: sequenceWidth,
    sequenceHeight: sequenceHeight,
    scaleToFit: scaleToFit,
  );
  final args = <String>['-y', '-hide_banner', '-loglevel', 'warning'];
  final duration = input.durationSeconds.toStringAsFixed(3);
  if (input.isStill) {
    args.addAll([
      '-framerate',
      '$kItemListNleTimebase',
      '-loop',
      '1',
      '-i',
      input.path,
      '-t',
      duration,
    ]);
  } else {
    args.addAll([
      '-ss',
      input.sourceStartSeconds.toStringAsFixed(3),
      '-t',
      duration,
      '-i',
      input.path,
    ]);
    if (!hasAudio) {
      args.addAll([
        '-f',
        'lavfi',
        '-t',
        duration,
        '-i',
        'anullsrc=r=44100:cl=stereo',
      ]);
    }
  }
  args.addAll([
    if (input.isStill) '-an',
    if (!input.isStill && !hasAudio) ...['-map', '0:v:0', '-map', '1:a:0'],
    '-vf',
    '$scale,fps=$kItemListNleTimebase,format=yuv420p',
    ...itemListMp4VideoEncoderArgs(
      encoder: encoder,
      sequenceWidth: sequenceWidth,
      sequenceHeight: sequenceHeight,
      assemble: false,
    ),
    if (!input.isStill) ...[
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
    ],
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
  ItemListMp4EncoderKind encoder = ItemListMp4EncoderKind.libx264,
  int sequenceWidth = 1920,
  int sequenceHeight = 1080,
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
    ...itemListMp4VideoEncoderArgs(
      encoder: encoder,
      sequenceWidth: sequenceWidth,
      sequenceHeight: sequenceHeight,
      assemble: true,
    ),
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
/// Each still/key period is encoded to `clip-N.mp4` first (key periods keep
/// audio), then those clips are xfade/concat'd with the WAV soundtrack
/// ducked under video spans. The workspace is copied to [kItemListMp4DumpDir]
/// for inspection.
Future<void> itemListRenderMp4({
  required ItemListNleTimeline timeline,
  required String audioPath,
  required String outputPath,
  required int sequenceWidth,
  required int sequenceHeight,
  required bool scaleToFit,
  double audioFadeOutSeconds = 2,
  double soundtrackDuck = kItemListMp4SoundtrackDuckDefault,
  bool useMacSavePanel = true,
  String? dumpDir,
  ItemListMp4EncoderResolver? resolveEncoder,
  ItemListMp4FfmpegRunner? runFfmpeg,
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
  final run = runFfmpeg ?? _runFfmpegLogged;
  var ok = false;
  try {
    final encoder =
        await (resolveEncoder ?? resolveItemListMp4VideoEncoder)(tools.ffmpeg);
    log.writeln('encoder: ${encoder.codecName}');
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
      soundtrackDuck: soundtrackDuck,
    );
    final wavPath = p.join(tempDir.path, 'soundtrack.wav');
    await itemListMp4DecodeSoundtrackWav(
      ffmpeg: tools.ffmpeg,
      audioPath: audioPath,
      destPath: wavPath,
    );

    final hasAudioFlags = <bool>[];
    for (final input in sourcePlan.inputs) {
      hasAudioFlags.add(
        !input.isStill &&
            await itemListMp4HasAudioStream(tools.ffprobe, input.path),
      );
    }
    final clipPaths = List<String>.generate(
      sourcePlan.inputs.length,
      (i) => p.join(tempDir.path, 'clip-$i.mp4'),
    );
    await itemListMp4RunWithConcurrency(
      count: sourcePlan.inputs.length,
      maxConcurrent: itemListMp4ClipConcurrency(encoder: encoder),
      run: (i) async {
        final clipOut = clipPaths[i];
        final clipArgs = itemListMp4ClipEncodeArgs(
          input: sourcePlan.inputs[i],
          outputPath: clipOut,
          sequenceWidth: sequenceWidth,
          sequenceHeight: sequenceHeight,
          scaleToFit: scaleToFit,
          hasAudio: hasAudioFlags[i],
          encoder: encoder,
        );
        final softwareArgs = encoder.isHardware
            ? itemListMp4ClipEncodeArgs(
                input: sourcePlan.inputs[i],
                outputPath: clipOut,
                sequenceWidth: sequenceWidth,
                sequenceHeight: sequenceHeight,
                scaleToFit: scaleToFit,
                hasAudio: hasAudioFlags[i],
              )
            : clipArgs;
        final ran = await itemListMp4RunEncodeWithFallback(
          ffmpeg: tools.ffmpeg,
          args: clipArgs,
          softwareArgs: softwareArgs,
          encoder: encoder,
          outputPath: clipOut,
          log: log,
          label: 'clip-$i',
          run: run,
        );
        if (!itemListMp4OutputOk(ran.exitCode, clipOut)) {
          throw ItemListMp4RenderException(
            ran.stderr.isEmpty
                ? 'ffmpeg wrote an empty clip-$i.mp4. Log: $kItemListMp4DumpDir or $itemListMp4TempDumpDir'
                : '${ran.stderr}\nLog: $kItemListMp4DumpDir or $itemListMp4TempDumpDir',
          );
        }
        return clipOut;
      },
    );

    final assembleTimeline = itemListMp4TimelineWithClipVideos(staged, clipPaths);
    final assemblePlan = itemListMp4Plan(
      timeline: assembleTimeline,
      sequenceWidth: sequenceWidth,
      sequenceHeight: sequenceHeight,
      scaleToFit: scaleToFit,
      audioFadeOutSeconds: audioFadeOutSeconds,
      soundtrackDuck: soundtrackDuck,
    );
    final args = itemListMp4AssembleArgs(
      plan: assemblePlan,
      audioPath: wavPath,
      outputPath: tempOut,
      encoder: encoder,
      sequenceWidth: sequenceWidth,
      sequenceHeight: sequenceHeight,
    );
    final softwareAssemble = encoder.isHardware
        ? itemListMp4AssembleArgs(
            plan: assemblePlan,
            audioPath: wavPath,
            outputPath: tempOut,
            sequenceWidth: sequenceWidth,
            sequenceHeight: sequenceHeight,
          )
        : args;
    await File(p.join(tempDir.path, 'argv.txt')).writeAsString(
      '${tools.ffmpeg}\nencoder=${encoder.codecName}\n${args.join(' ')}\n\n'
      'filter_complex:\n${assemblePlan.filterComplex}\n',
    );
    final ran = await itemListMp4RunEncodeWithFallback(
      ffmpeg: tools.ffmpeg,
      args: args,
      softwareArgs: softwareAssemble,
      encoder: encoder,
      outputPath: tempOut,
      log: log,
      label: 'assemble',
      run: run,
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

/// True when [path] has at least one audio stream.
Future<bool> itemListMp4HasAudioStream(String ffprobe, String path) async {
  final result = await Process.run(
    ffprobe,
    [
      '-v',
      'error',
      '-select_streams',
      'a:0',
      '-show_entries',
      'stream=codec_type',
      '-of',
      'csv=p=0',
      path,
    ],
    runInShell: false,
  );
  if (result.exitCode != 0) return false;
  return (result.stdout as String).trim().isNotEmpty;
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
