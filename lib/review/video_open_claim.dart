/// Tracks which local media path currently owns video-open for this review
/// section, so overlapping open attempts for the same item (e.g. repeated
/// `ListenableBuilder` rebuilds while media_kit is still initializing) don't
/// each spin up their own `Player` — the loser would otherwise never be
/// disposed and would keep decoding/playing audio after the winner is bound
/// to the visible `Video` widget (D8).
class VideoOpenClaim {
  String? _current;

  /// Claims [path] for a new open attempt. Returns false (no-op) when
  /// [path] is already the active claim.
  bool claim(String path) {
    if (path == _current) return false;
    _current = path;
    return true;
  }

  /// Whether [path] is still the active claim (false if a later claim for a
  /// different path superseded it while this attempt was still opening).
  bool isCurrent(String path) => path == _current;

  void clear() => _current = null;
}
