import 'dart:io';

import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/prepass/ffmpeg_resolve.dart';

export 'package:tagkin_desktop/prepass/ffmpeg_resolve.dart' show hasFfmpeg;

/// Probe video duration in milliseconds via app-bundled (or PATH) `ffprobe`.
Future<int> probeDurationMs(String videoPath) async {
  final tools = resolveFfmpegTools();
  if (tools == null) {
    throw StateError('ffprobe not available (not bundled and not on PATH)');
  }
  final result = await Process.run(
    tools.ffprobe,
    [
      '-v',
      'error',
      '-show_entries',
      'format=duration',
      '-of',
      'default=noprint_wrappers=1:nokey=1',
      videoPath,
    ],
    runInShell: false,
  );
  final stdout = (result.stdout as String).trim();
  final seconds = double.tryParse(stdout);
  if (seconds == null || !seconds.isFinite || seconds < 0) {
    throw StateError('ffprobe returned invalid duration: $stdout');
  }
  return (seconds * 1000).round();
}

/// Scene-cut detection via FFmpeg `select` filter.
///
/// Returns key periods within `[0, durationMs]`. Falls back to a single
/// whole-item period when no cuts are found. Throws when ffmpeg tools
/// cannot run — callers should catch and degrade.
Future<({int durationMs, List<PrePassKeyPeriodInput> keyPeriods})>
    detectSceneKeyPeriods(
  String videoPath, {
  double threshold = 0.3,
}) async {
  final tools = resolveFfmpegTools();
  if (tools == null) {
    throw StateError('ffmpeg not available (not bundled and not on PATH)');
  }

  final durationMs = await probeDurationMs(videoPath);

  String stderr = '';
  try {
    final result = await Process.run(
      tools.ffmpeg,
      [
        '-i',
        videoPath,
        '-filter:v',
        "select='gt(scene,$threshold)',showinfo",
        '-f',
        'null',
        '-',
      ],
      runInShell: false,
    );
    stderr = result.stderr as String;
  } catch (err) {
    // ffmpeg writes showinfo to stderr and may exit non-zero with -f null.
    if (err is ProcessException) {
      rethrow;
    }
    stderr = err.toString();
  }

  final cutMs = <int>[0];
  final re = RegExp(r'pts_time:([\d.]+)');
  for (final match in re.allMatches(stderr)) {
    final t = (double.parse(match.group(1)!) * 1000).round();
    if (t > 0 && t < durationMs) {
      cutMs.add(t);
    }
  }
  cutMs.add(durationMs);
  cutMs.sort();

  final keyPeriods = <PrePassKeyPeriodInput>[];
  for (var i = 0; i < cutMs.length - 1; i++) {
    final startMs = cutMs[i];
    final endMs = cutMs[i + 1];
    if (endMs > startMs) {
      keyPeriods.add(PrePassKeyPeriodInput(startMs: startMs, endMs: endMs));
    }
  }

  if (keyPeriods.isEmpty && durationMs > 0) {
    keyPeriods.add(PrePassKeyPeriodInput(startMs: 0, endMs: durationMs));
  }

  return (durationMs: durationMs, keyPeriods: keyPeriods);
}
