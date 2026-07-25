/// User display / library preferences for tagkin-desktop.
class DesktopPrefs {
  const DesktopPrefs({
    this.showCountryWhenSameCountry = false,
    this.showStateWhenSameState = false,
    this.multiColumnSort = false,
    this.showFaceOverlays = true,
    this.homeState = '',
  });

  /// When true, include country even if place country matches device locale.
  final bool showCountryWhenSameCountry;

  /// When true, include state/province even if it matches [homeState].
  final bool showStateWhenSameState;

  /// When true, header clicks build a multi-key sort stack (Cliptorium-style).
  final bool multiColumnSort;

  /// When true (default), draw who-face boxes on the review photo.
  final bool showFaceOverlays;

  /// User home state/province for same-state where-label comparison.
  final String homeState;

  static const defaults = DesktopPrefs();

  DesktopPrefs copyWith({
    bool? showCountryWhenSameCountry,
    bool? showStateWhenSameState,
    bool? multiColumnSort,
    bool? showFaceOverlays,
    String? homeState,
  }) {
    return DesktopPrefs(
      showCountryWhenSameCountry:
          showCountryWhenSameCountry ?? this.showCountryWhenSameCountry,
      showStateWhenSameState:
          showStateWhenSameState ?? this.showStateWhenSameState,
      multiColumnSort: multiColumnSort ?? this.multiColumnSort,
      showFaceOverlays: showFaceOverlays ?? this.showFaceOverlays,
      homeState: homeState ?? this.homeState,
    );
  }

  Map<String, Object?> toJson() => {
        'where.showCountryWhenSameCountry': showCountryWhenSameCountry,
        'where.showStateWhenSameState': showStateWhenSameState,
        'ui.multiColumnSort': multiColumnSort,
        'ui.showFaceOverlays': showFaceOverlays,
        'where.homeState': homeState,
      };

  factory DesktopPrefs.fromJson(Map<String, dynamic> json) {
    bool flag(String key, {required bool fallback}) {
      final v = json[key];
      if (v is bool) return v;
      if (v is String) return v == 'true' || v == '1';
      return fallback;
    }

    final home = json['where.homeState'];
    return DesktopPrefs(
      showCountryWhenSameCountry: flag(
        'where.showCountryWhenSameCountry',
        fallback: false,
      ),
      showStateWhenSameState: flag(
        'where.showStateWhenSameState',
        fallback: false,
      ),
      multiColumnSort: flag('ui.multiColumnSort', fallback: false),
      showFaceOverlays: flag('ui.showFaceOverlays', fallback: true),
      homeState: home is String ? home : '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DesktopPrefs &&
      other.showCountryWhenSameCountry == showCountryWhenSameCountry &&
      other.showStateWhenSameState == showStateWhenSameState &&
      other.multiColumnSort == multiColumnSort &&
      other.showFaceOverlays == showFaceOverlays &&
      other.homeState == homeState;

  @override
  int get hashCode => Object.hash(
        showCountryWhenSameCountry,
        showStateWhenSameState,
        multiColumnSort,
        showFaceOverlays,
        homeState,
      );
}
