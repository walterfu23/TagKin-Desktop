import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/prepass/ffmpeg_resolve.dart';

/// Minimum spacing between samples inside a key period when scenes change
/// quickly (short periods / densify). Not a fixed FPS baseline (R9).
const int kDefaultMinSampleIntervalMs = 1000;

/// Maximum spacing inside a long/static key period (stretch when similar).
const int kDefaultMaxSampleIntervalMs = 15000;

/// Soft ceiling so a multi-hour static clip does not explode cost/UX.
/// Busy scene-cut videos naturally get more frames via short periods.
const int kDefaultSoftMaxFramesPerItem = 500;

/// @Deprecated('Use soft max + adaptive intervals; kept for call-site compat')
const int kDefaultMaxFramesPerItem = kDefaultSoftMaxFramesPerItem;

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

/// Interval inside a key period: short periods densify, long periods stretch.
int sampleIntervalForPeriodMs(
  int periodDurationMs, {
  int minIntervalMs = kDefaultMinSampleIntervalMs,
  int maxIntervalMs = kDefaultMaxSampleIntervalMs,
}) {
  if (periodDurationMs <= 0) return minIntervalMs;
  // Short key period (quick scene change) → min interval.
  // Long key period (static stretch) → max interval.
  const shortMs = 3000;
  const longMs = 60000;
  if (periodDurationMs <= shortMs) return minIntervalMs;
  if (periodDurationMs >= longMs) return maxIntervalMs;
  final t = (periodDurationMs - shortMs) / (longMs - shortMs);
  return (minIntervalMs + (maxIntervalMs - minIntervalMs) * t).round();
}

/// Soft frame budget from total timeline length (not a flat starve-cap).
/// Roughly up to ~4 samples/minute of content, floored at 30, soft at [softMax].
int softMaxFramesForDurationMs(
  int totalDurationMs, {
  int softMax = kDefaultSoftMaxFramesPerItem,
}) {
  if (totalDurationMs <= 0) return softMax.clamp(1, softMax);
  final perMinute = 4;
  final minutes = totalDurationMs / 60000.0;
  final budget = math.max(30, (minutes * perMinute).ceil());
  return budget.clamp(1, softMax);
}

/// Pure planning of sample timestamps — no I/O.
///
/// Adaptive policy (R9): dynamic spacing from key-period length (proxy for
/// scene-change rate). Quick cuts → short intervals; static stretches → long
/// intervals. Soft max scales with total duration — never "1 frame per minute"
/// on a 2-hour clip just because of a flat 120 cap.
List<({int keyPeriodIndex, int timestampMs})> planSampleTimestamps({
  required List<PrePassKeyPeriodInput> keyPeriods,
  int maxFrames = kDefaultSoftMaxFramesPerItem,
  int minIntervalMs = kDefaultMinSampleIntervalMs,
  int maxIntervalMs = kDefaultMaxSampleIntervalMs,
}) {
  if (keyPeriods.isEmpty || maxFrames <= 0) return const [];

  var totalDurationMs = 0;
  for (final kp in keyPeriods) {
    totalDurationMs = math.max(totalDurationMs, kp.endMs);
  }
  final budget = math.min(
    maxFrames,
    softMaxFramesForDurationMs(totalDurationMs, softMax: maxFrames),
  );

  final planned = <({int keyPeriodIndex, int timestampMs})>[];
  for (var i = 0; i < keyPeriods.length; i++) {
    final kp = keyPeriods[i];
    final duration = kp.endMs - kp.startMs;
    if (duration <= 0) continue;

    final interval = sampleIntervalForPeriodMs(
      duration,
      minIntervalMs: minIntervalMs,
      maxIntervalMs: maxIntervalMs,
    );

    // Very short / quick-cut periods: one representative midpoint.
    if (duration <= minIntervalMs * 2) {
      final mid = kp.startMs + (duration ~/ 2);
      planned.add((keyPeriodIndex: i, timestampMs: mid));
      continue;
    }

    // First sample near start+interval/2, then step by interval.
    var t = kp.startMs + (interval ~/ 2);
    if (t >= kp.endMs) t = kp.startMs + (duration ~/ 2);
    while (t < kp.endMs) {
      planned.add((keyPeriodIndex: i, timestampMs: t));
      t += interval;
    }
    // Ensure the period contributes at least one sample.
    if (planned.isEmpty || planned.last.keyPeriodIndex != i) {
      planned.add((
        keyPeriodIndex: i,
        timestampMs: kp.startMs + (duration ~/ 2),
      ));
    }
  }

  if (planned.length <= budget) return planned;

  // Over budget: keep samples spread evenly across the plan (prefer coverage
  // of early busy cuts and late content alike).
  final thinned = <({int keyPeriodIndex, int timestampMs})>[];
  for (var i = 0; i < budget; i++) {
    final idx = ((i + 0.5) * planned.length / budget).floor();
    thinned.add(planned[idx.clamp(0, planned.length - 1)]);
  }
  // Dedupe identical timestamps from rounding.
  final seen = <String>{};
  return thinned.where((e) {
    final key = '${e.keyPeriodIndex}:${e.timestampMs}';
    return seen.add(key);
  }).toList();
}

/// Extract planned frames from [videoPath] via app-bundled (or PATH) `ffmpeg`.
///
/// Writes JPEGs under a new temp directory and returns their [FrameSample]
/// manifests. Callers own cleanup of the returned temp directory (or leave
/// for OS temp cleanup). Returns an empty list when ffmpeg fails.
Future<List<FrameSample>> sampleFrames({
  required String videoPath,
  required List<PrePassKeyPeriodInput> keyPeriods,
  int maxFrames = kDefaultSoftMaxFramesPerItem,
  int minIntervalMs = kDefaultMinSampleIntervalMs,
  int maxIntervalMs = kDefaultMaxSampleIntervalMs,
  Directory? tempRoot,
}) async {
  final plan = planSampleTimestamps(
    keyPeriods: keyPeriods,
    maxFrames: maxFrames,
    minIntervalMs: minIntervalMs,
    maxIntervalMs: maxIntervalMs,
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
