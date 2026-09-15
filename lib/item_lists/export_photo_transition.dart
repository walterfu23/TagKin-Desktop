/// Photo-to-photo transition on FCP7 XML / FCPXML export.
enum ExportPhotoTransition {
  none,
  crossDissolve,
  dipToBlack,
  dipToWhite;

  String get wire => name;

  String get settingsLabel => switch (this) {
        ExportPhotoTransition.none => 'None',
        ExportPhotoTransition.crossDissolve => 'Cross dissolve',
        ExportPhotoTransition.dipToBlack => 'Dip to black',
        ExportPhotoTransition.dipToWhite => 'Dip to white',
      };

  static ExportPhotoTransition parse(Object? value) {
    final s = value is String ? value : null;
    return ExportPhotoTransition.values
            .where((f) => f.wire == s)
            .firstOrNull ??
        ExportPhotoTransition.crossDissolve;
  }
}
