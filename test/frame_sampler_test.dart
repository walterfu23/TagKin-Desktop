import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/prepass/frame_sampler.dart';

void main() {
  group('planSampleTimestamps (adaptive, hard cap)', () {
    test('one midpoint frame per key period', () {
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

    test('respects global hard cap (never exceeds maxFrames)', () {
      final many = List.generate(
        50,
        (i) => PrePassKeyPeriodInput(startMs: i * 1000, endMs: (i + 1) * 1000),
      );
      final plan = planSampleTimestamps(keyPeriods: many, maxFrames: 20);
      expect(plan.length, lessThanOrEqualTo(20));
      expect(plan, hasLength(20));
      for (final entry in plan) {
        final kp = many[entry.keyPeriodIndex];
        expect(entry.timestampMs, greaterThanOrEqualTo(kp.startMs));
        expect(entry.timestampMs, lessThanOrEqualTo(kp.endMs));
      }
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
  });
}
