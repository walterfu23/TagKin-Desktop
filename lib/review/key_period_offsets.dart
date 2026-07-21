/// Pure mapping helpers for video key-period scrub (D8).
///
/// Contract stores ranges as milliseconds (`startMs` / `endMs`); media_kit
/// seeks use [Duration]. Keep this file free of Flutter / native plugins so
/// unit tests can assert offsets without a player.
library;

/// Converts a key-period bound in milliseconds to a seek [Duration].
Duration keyPeriodMsToSeek(int ms) {
  if (ms < 0) return Duration.zero;
  return Duration(milliseconds: ms);
}

/// Clamps a seek target so it stays within [0, duration].
Duration clampSeekToDuration(Duration seek, Duration duration) {
  if (duration <= Duration.zero) return Duration.zero;
  if (seek < Duration.zero) return Duration.zero;
  if (seek > duration) return duration;
  return seek;
}

/// Whether [position] falls inside the inclusive [startMs]–[endMs] range.
bool positionInKeyPeriod({
  required Duration position,
  required int startMs,
  required int endMs,
}) {
  final ms = position.inMilliseconds;
  return ms >= startMs && ms <= endMs;
}
