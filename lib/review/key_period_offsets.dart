/// Pure mapping helpers for video key-period scrub (D8) and Folders thumbs.
///
/// Contract stores ranges as milliseconds (`startMs` / `endMs`); media_kit
/// seeks use [Duration]. Keep this file free of Flutter / native plugins so
/// unit tests can assert offsets without a player.
library;

import 'package:tagkin_desktop/contract/contract.dart';

/// Converts a key-period bound in milliseconds to a seek [Duration].
Duration keyPeriodMsToSeek(int ms) {
  if (ms < 0) return Duration.zero;
  return Duration(milliseconds: ms);
}

/// Periods to show as Folders thumbs: every period when there are 2+, else none
/// (the row keeps the single item poster).
List<KeyPeriodKnowledge> foldersKeyPeriodTiles(
  List<KeyPeriodKnowledge> keyPeriods,
) {
  if (keyPeriods.length < 2) return const [];
  final sorted = List<KeyPeriodKnowledge>.from(keyPeriods)
    ..sort((a, b) => a.startMs.compareTo(b.startMs));
  return sorted;
}

/// Representative-frame timestamp for a key-period still (`sampleTimestampMs`,
/// else `startMs`).
int keyPeriodThumbTimestampMs(KeyPeriodKnowledge period) {
  final ms = period.sampleTimestampMs ?? period.startMs;
  return ms < 0 ? 0 : ms;
}

/// Folders widget-key suffix: item id, or `$itemId-kp-$periodId` for a period
/// row.
String foldersRowScopeId(String itemId, KeyPeriodKnowledge? period) {
  if (period == null) return itemId;
  return '$itemId-kp-${period.id}';
}

/// Clamps a seek target so it stays within [0, duration].
Duration clampSeekToDuration(Duration seek, Duration duration) {
  if (duration <= Duration.zero) return Duration.zero;
  if (seek < Duration.zero) return Duration.zero;
  if (seek > duration) return duration;
  return seek;
}

/// Whether [position] falls in the half-open `[startMs, endMs)` span.
///
/// Adjacent periods that share a cut (`endMs` of A == `startMs` of B) cannot
/// both contain the same tick.
bool positionInKeyPeriod({
  required Duration position,
  required int startMs,
  required int endMs,
}) {
  final ms = position.inMilliseconds;
  return ms >= startMs && ms < endMs;
}

/// How a half-open `[start, stopAt)` clip relates to [position].
enum PeriodClipAction {
  /// Playhead is inside the clip.
  inside,

  /// Playhead is before [start].
  holdBeforeStart,

  /// Playhead is at or past exclusive [stopAt].
  loopAtEnd,
}

/// Classifies [position] for a half-open `[start, stopAt)` clip.
PeriodClipAction periodClipOnPosition({
  required Duration position,
  required Duration start,
  required Duration stopAt,
}) {
  if (stopAt <= start) return PeriodClipAction.inside;
  if (position < start) return PeriodClipAction.holdBeforeStart;
  if (position >= stopAt) return PeriodClipAction.loopAtEnd;
  return PeriodClipAction.inside;
}
