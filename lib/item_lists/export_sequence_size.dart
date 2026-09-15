/// Sequence frame size for FCP7 XML / FCPXML export.
enum ExportSequenceSize {
  matchSmallest,
  p1080,
  p4k,
  matchLargest;

  String get wire => switch (this) {
        ExportSequenceSize.matchSmallest => 'matchSmallest',
        ExportSequenceSize.p1080 => '1080p',
        ExportSequenceSize.p4k => '4k',
        ExportSequenceSize.matchLargest => 'matchLargest',
      };

  String get settingsLabel => switch (this) {
        ExportSequenceSize.matchSmallest => 'Match smallest',
        ExportSequenceSize.p1080 => '1080p',
        ExportSequenceSize.p4k => '4K',
        ExportSequenceSize.matchLargest => 'Match largest',
      };

  bool get scaleToFit => this != ExportSequenceSize.matchLargest;

  static ExportSequenceSize parse(Object? value) {
    final s = value is String ? value : null;
    return ExportSequenceSize.values.where((f) => f.wire == s).firstOrNull ??
        ExportSequenceSize.matchSmallest;
  }
}
