import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/review/key_period_offsets.dart';

void main() {
  test('keyPeriodMsToSeek maps milliseconds to Duration', () {
    expect(keyPeriodMsToSeek(0), Duration.zero);
    expect(keyPeriodMsToSeek(1500), const Duration(milliseconds: 1500));
    expect(keyPeriodMsToSeek(-10), Duration.zero);
  });

  test('clampSeekToDuration stays within media bounds', () {
    const duration = Duration(seconds: 10);
    expect(
      clampSeekToDuration(const Duration(seconds: 3), duration),
      const Duration(seconds: 3),
    );
    expect(
      clampSeekToDuration(const Duration(seconds: 99), duration),
      duration,
    );
    expect(
      clampSeekToDuration(const Duration(seconds: -1), duration),
      Duration.zero,
    );
  });

  test('positionInKeyPeriod inclusive start/end', () {
    expect(
      positionInKeyPeriod(
        position: const Duration(milliseconds: 1000),
        startMs: 1000,
        endMs: 2000,
      ),
      isTrue,
    );
    expect(
      positionInKeyPeriod(
        position: const Duration(milliseconds: 2000),
        startMs: 1000,
        endMs: 2000,
      ),
      isTrue,
    );
    expect(
      positionInKeyPeriod(
        position: const Duration(milliseconds: 999),
        startMs: 1000,
        endMs: 2000,
      ),
      isFalse,
    );
  });
}
