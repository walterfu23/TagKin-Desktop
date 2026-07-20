import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/prepass/ffmpeg_resolve.dart';

/// Default global hard cap on sample frames per item (R9 — no fixed 1 FPS).
const int kDefaultMaxFramesPerItem = 20;

/// One locally-extracted sample frame for later D5 upload.
///
/// Bytes stay on local disk; this is a path + timestamp only (R1/R5).
class FrameSample {
  const FrameSample({
    required this.path,
    required this.timestampMs,
    required this.keyPeriodIndex,
  });

  /// Absolute path to a JPEG extracted into a temp directory.
  final String path;
  final int timestampMs;
  final int keyPeriodIndex;
}

/// Pure planning of sample timestamps — no I/O.
///
/// Adaptive policy (R9): **1 midpoint frame per key period**, clipped to
/// [maxFrames] across the whole item. Never uses fixed FPS.
List<({int keyPeriodIndex, int timestampMs})> planSampleTimestamps({
  required List<PrePassKeyPeriodInput> keyPeriods,
  int maxFrames = kDefaultMaxFramesPerItem,
}) {
  if (keyPeriods.isEmpty || maxFrames <= 0) return const [];

  final planned = <({int keyPeriodIndex, int timestampMs})>[];
  final limit = keyPeriods.length < maxFrames ? keyPeriods.length : maxFrames;
  for (var i = 0; i < limit; i++) {
    final kp = keyPeriods[i];
    final mid = kp.startMs + ((kp.endMs - kp.startMs) ~/ 2);
    planned.add((keyPeriodIndex: i, timestampMs: mid));
  }
  return planned;
}

/// Extract planned frames from [videoPath] via app-bundled (or PATH) `ffmpeg`.
///
/// Writes JPEGs under a new temp directory and returns their [FrameSample]
/// manifests. Callers own cleanup of the returned temp directory (or leave
/// for OS temp cleanup). Returns an empty list when ffmpeg fails.
Future<List<FrameSample>> sampleFrames({
  required String videoPath,
  required List<PrePassKeyPeriodInput> keyPeriods,
  int maxFrames = kDefaultMaxFramesPerItem,
  Directory? tempRoot,
}) async {
  final plan = planSampleTimestamps(
    keyPeriods: keyPeriods,
    maxFrames: maxFrames,
  );
  if (plan.isEmpty) return const [];

  final tools = resolveFfmpegTools();
  if (tools == null) return const [];

  final root =
      tempRoot ?? await Directory.systemTemp.createTemp('tagkin_frames_');
  final samples = <FrameSample>[];
  final ctx = p.context;

  for (var i = 0; i < plan.length; i++) {
    final entry = plan[i];
    final outPath =
        ctx.join(root.path, 'frame_${i.toString().padLeft(4, '0')}.jpg');
    final seconds = entry.timestampMs / 1000.0;
    try {
      final result = await Process.run(
        tools.ffmpeg,
        [
          '-y',
          '-ss',
          seconds.toStringAsFixed(3),
          '-i',
          videoPath,
          '-frames:v',
          '1',
          outPath,
        ],
        runInShell: false,
      );
      if (result.exitCode != 0 || !File(outPath).existsSync()) {
        continue;
      }
      samples.add(
        FrameSample(
          path: outPath,
          timestampMs: entry.timestampMs,
          keyPeriodIndex: entry.keyPeriodIndex,
        ),
      );
    } catch (_) {
      // Missing ffmpeg or extract failure — skip this frame.
    }
  }
  return samples;
}
