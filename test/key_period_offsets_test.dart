import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
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

  test('positionInKeyPeriod is half-open [start, end)', () {
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
      isFalse,
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

  test('periodClipOnPosition is half-open; abutting windows are disjoint', () {
    const firstStart = Duration.zero;
    const cut = Duration(milliseconds: 1800);
    const secondEnd = Duration(milliseconds: 9000);

    expect(
      periodClipOnPosition(
        position: const Duration(milliseconds: 1799),
        start: firstStart,
        stopAt: cut,
      ),
      PeriodClipAction.inside,
    );
    expect(
      periodClipOnPosition(
        position: cut,
        start: firstStart,
        stopAt: cut,
      ),
      PeriodClipAction.loopAtEnd,
    );
    expect(
      periodClipOnPosition(
        position: cut,
        start: cut,
        stopAt: secondEnd,
      ),
      PeriodClipAction.inside,
    );
    expect(
      periodClipOnPosition(
        position: const Duration(milliseconds: 1000),
        start: cut,
        stopAt: secondEnd,
      ),
      PeriodClipAction.holdBeforeStart,
    );
    expect(
      periodClipOnPosition(
        position: cut,
        start: firstStart,
        stopAt: cut,
      ),
      isNot(PeriodClipAction.inside),
    );
    expect(
      periodClipOnPosition(
        position: cut,
        start: cut,
        stopAt: secondEnd,
      ),
      isNot(
        periodClipOnPosition(
          position: cut,
          start: firstStart,
          stopAt: cut,
        ),
      ),
    );
  });

  test('foldersKeyPeriodTiles is empty unless there are two or more', () {
    expect(foldersKeyPeriodTiles(const []), isEmpty);
    expect(
      foldersKeyPeriodTiles([
        const KeyPeriodKnowledge(
          id: 'a',
          itemId: 'v',
          startMs: 0,
          endMs: 1000,
          tags: [],
        ),
      ]),
      isEmpty,
    );
    final tiles = foldersKeyPeriodTiles([
      const KeyPeriodKnowledge(
        id: 'late',
        itemId: 'v',
        startMs: 4000,
        endMs: 8000,
        tags: [],
      ),
      const KeyPeriodKnowledge(
        id: 'early',
        itemId: 'v',
        startMs: 1000,
        endMs: 3000,
        tags: [],
      ),
    ]);
    expect(tiles.map((p) => p.id), ['early', 'late']);
  });

  test('foldersRowScopeId suffixes a period id', () {
    expect(foldersRowScopeId('v', null), 'v');
    expect(
      foldersRowScopeId(
        'v',
        const KeyPeriodKnowledge(
          id: 'kp1',
          itemId: 'v',
          startMs: 0,
          endMs: 1000,
          tags: [],
        ),
      ),
      'v-kp-kp1',
    );
  });

  test('keyPeriodThumbTimestampMs prefers sample then start', () {
    expect(
      keyPeriodThumbTimestampMs(
        const KeyPeriodKnowledge(
          id: 'a',
          itemId: 'v',
          startMs: 1500,
          endMs: 3000,
          tags: [],
        ),
      ),
      1500,
    );
    expect(
      keyPeriodThumbTimestampMs(
        const KeyPeriodKnowledge(
          id: 'a',
          itemId: 'v',
          startMs: 1500,
          endMs: 3000,
          sampleTimestampMs: 1800,
          tags: [],
        ),
      ),
      1800,
    );
    expect(
      keyPeriodThumbTimestampMs(
        const KeyPeriodKnowledge(
          id: 'a',
          itemId: 'v',
          startMs: -5,
          endMs: 1000,
          tags: [],
        ),
      ),
      0,
    );
  });
}
