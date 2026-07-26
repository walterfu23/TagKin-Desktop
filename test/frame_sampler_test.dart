import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/prepass/frame_sampler.dart';

void main() {
  group('sampleIntervalForPeriodMs', () {
    test('short periods densify to min interval', () {
      expect(
        sampleIntervalForPeriodMs(2000, minIntervalMs: 1000, maxIntervalMs: 15000),
        1000,
      );
    });

    test('long periods stretch to max interval', () {
      expect(
        sampleIntervalForPeriodMs(120000, minIntervalMs: 1000, maxIntervalMs: 15000),
        15000,
      );
    });
  });

  group('planSampleTimestamps (adaptive intervals)', () {
    test('short key periods each get a midpoint sample', () {
      final plan = planSampleTimestamps(
        keyPeriods: const [
          PrePassKeyPeriodInput(startMs: 0, endMs: 1000),
          PrePassKeyPeriodInput(startMs: 1000, endMs: 3000),
        ],
      );
      expect(plan, hasLength(2));
      expect(plan[0].timestampMs, 500);
      expect(plan[0].keyPeriodIndex, 0);
      expect(plan[1].timestampMs, 2000);
      expect(plan[1].keyPeriodIndex, 1);
    });

    test('long static period samples at ~maxInterval, not one midpoint only', () {
      // 10 minutes of one key period — must not collapse to a single frame.
      final plan = planSampleTimestamps(
        keyPeriods: const [
          PrePassKeyPeriodInput(startMs: 0, endMs: 600000),
        ],
        minIntervalMs: 1000,
        maxIntervalMs: 15000,
      );
      expect(plan.length, greaterThan(10));
      expect(plan.length, lessThanOrEqualTo(50));
      for (final entry in plan) {
        expect(entry.timestampMs, inInclusiveRange(0, 600000));
      }
    });

    test('many quick cuts get denser coverage than a flat 20-cap would allow', () {
      final many = List.generate(
        80,
        (i) => PrePassKeyPeriodInput(startMs: i * 800, endMs: (i + 1) * 800),
      );
      final plan = planSampleTimestamps(keyPeriods: many, maxFrames: 500);
      // One sample per short period → well above the old hard 20.
      expect(plan.length, greaterThan(20));
      expect(plan.length, lessThanOrEqualTo(80));
    });

    test('soft budget thins when plan exceeds maxFrames', () {
      final many = List.generate(
        200,
        (i) => PrePassKeyPeriodInput(startMs: i * 500, endMs: (i + 1) * 500),
      );
      final plan = planSampleTimestamps(keyPeriods: many, maxFrames: 40);
      expect(plan.length, lessThanOrEqualTo(40));
    });

    test('empty key periods → empty plan (no fixed FPS)', () {
      expect(planSampleTimestamps(keyPeriods: const []), isEmpty);
      expect(
        planSampleTimestamps(
          keyPeriods: const [PrePassKeyPeriodInput(startMs: 0, endMs: 5000)],
          maxFrames: 0,
        ),
        isEmpty,
      );
    });

    test('two-hour video is not starved to ~1 frame/minute', () {
      // Single long period 120 minutes with maxInterval 15s → many samples,
      // soft budget ~4/min * 120 = 480, clamped by soft max 500.
      final plan = planSampleTimestamps(
        keyPeriods: const [
          PrePassKeyPeriodInput(startMs: 0, endMs: 120 * 60 * 1000),
        ],
        maxFrames: 500,
        maxIntervalMs: 15000,
      );
      expect(plan.length, greaterThan(120)); // better than 1/min
    });
  });
}
