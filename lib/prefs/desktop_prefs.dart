import 'package:tagkin_desktop/where/where_place_label.dart';

/// User preferences for tagkin-desktop (app-wide Settings).
///
/// Under development — not shipped. Collection page look stays on the
/// collection; these knobs are global.
class DesktopPrefs {
  const DesktopPrefs({
    this.showCountryWhenSameCountry = false,
    this.showStateWhenSameState = false,
    this.multiColumnSort = false,
    this.showFaceOverlays = true,
    this.familiarRegions = '',
    this.libraryPageSize = 50,
    this.recentCollectionsLimit = 20,
    this.nearDuplicateThreshold = 4,
    this.sampleMinIntervalMs = 1000,
    this.sampleMaxIntervalMs = 15000,
    this.softMaxFramesPerItem = 500,
    this.sceneCutThreshold = 0.3,
    this.facesDetectScoreThreshold = 0.2,
    this.facesTrayPageLimit = 500,
    this.jobsPollIntervalSeconds = 2,
  });

  /// When true, include country even if place country matches device locale.
  final bool showCountryWhenSameCountry;

  /// When true, include state/province even if it matches [familiarRegions].
  final bool showStateWhenSameState;

  /// When true, header clicks build a multi-key sort stack (Cliptorium-style).
  final bool multiColumnSort;

  /// When true (default), draw who-face boxes on the review photo.
  final bool showFaceOverlays;

  /// CSV of familiar regions (states/provinces) for Where-label shortening.
  /// GUI label: Familiar state/province.
  final String familiarRegions;

  /// Rows per page in the Folders table.
  final int libraryPageSize;

  /// Max entries in Open Recent / start-gate Recents.
  final int recentCollectionsLimit;

  /// Hamming distance ≤ this → near-duplicate at ingest.
  final int nearDuplicateThreshold;

  /// Min spacing (ms) between video sample frames in a short key period.
  final int sampleMinIntervalMs;

  /// Max spacing (ms) between video sample frames in a long key period.
  final int sampleMaxIntervalMs;

  /// Soft ceiling on sample frames per video item.
  final int softMaxFramesPerItem;

  /// FFmpeg scene-cut sensitivity (lower → more cuts).
  final double sceneCutThreshold;

  /// SCRFD face-detect score floor used by the local ONNX embedder.
  final double facesDetectScoreThreshold;

  /// Appearances / exclusions list page size on Faces trays.
  final int facesTrayPageLimit;

  /// Job status poll interval while analyze/upload runs.
  final int jobsPollIntervalSeconds;

  static const defaults = DesktopPrefs();

  // Slider / clamp ranges (UI and fromJson share these).
  static const libraryPageSizeMin = 2;
  static const libraryPageSizeMax = 200;
  static const libraryPageSizeStep = 1;

  static const recentCollectionsLimitMin = 1;
  static const recentCollectionsLimitMax = 100;
  static const recentCollectionsLimitStep = 1;

  static const nearDuplicateThresholdMin = 0;
  static const nearDuplicateThresholdMax = 64;
  static const nearDuplicateThresholdStep = 1;

  static const sampleMinIntervalMsMin = 100;
  static const sampleMinIntervalMsMax = 60000;
  static const sampleMinIntervalMsStep = 100;

  static const sampleMaxIntervalMsMin = 500;
  static const sampleMaxIntervalMsMax = 120000;
  static const sampleMaxIntervalMsStep = 500;

  static const softMaxFramesPerItemMin = 10;
  static const softMaxFramesPerItemMax = 2000;
  static const softMaxFramesPerItemStep = 10;

  static const sceneCutThresholdMin = 0.05;
  static const sceneCutThresholdMax = 0.9;
  static const sceneCutThresholdStep = 0.05;

  static const facesDetectScoreThresholdMin = 0.05;
  static const facesDetectScoreThresholdMax = 0.95;
  static const facesDetectScoreThresholdStep = 0.05;

  static const facesTrayPageLimitMin = 50;
  static const facesTrayPageLimitMax = 500;
  static const facesTrayPageLimitStep = 10;

  static const jobsPollIntervalSecondsMin = 1;
  static const jobsPollIntervalSecondsMax = 30;
  static const jobsPollIntervalSecondsStep = 1;

  DesktopPrefs copyWith({
    bool? showCountryWhenSameCountry,
    bool? showStateWhenSameState,
    bool? multiColumnSort,
    bool? showFaceOverlays,
    String? familiarRegions,
    int? libraryPageSize,
    int? recentCollectionsLimit,
    int? nearDuplicateThreshold,
    int? sampleMinIntervalMs,
    int? sampleMaxIntervalMs,
    int? softMaxFramesPerItem,
    double? sceneCutThreshold,
    double? facesDetectScoreThreshold,
    int? facesTrayPageLimit,
    int? jobsPollIntervalSeconds,
  }) {
    return DesktopPrefs(
      showCountryWhenSameCountry:
          showCountryWhenSameCountry ?? this.showCountryWhenSameCountry,
      showStateWhenSameState:
          showStateWhenSameState ?? this.showStateWhenSameState,
      multiColumnSort: multiColumnSort ?? this.multiColumnSort,
      showFaceOverlays: showFaceOverlays ?? this.showFaceOverlays,
      familiarRegions: familiarRegions ?? this.familiarRegions,
      libraryPageSize: libraryPageSize ?? this.libraryPageSize,
      recentCollectionsLimit:
          recentCollectionsLimit ?? this.recentCollectionsLimit,
      nearDuplicateThreshold:
          nearDuplicateThreshold ?? this.nearDuplicateThreshold,
      sampleMinIntervalMs: sampleMinIntervalMs ?? this.sampleMinIntervalMs,
      sampleMaxIntervalMs: sampleMaxIntervalMs ?? this.sampleMaxIntervalMs,
      softMaxFramesPerItem: softMaxFramesPerItem ?? this.softMaxFramesPerItem,
      sceneCutThreshold: sceneCutThreshold ?? this.sceneCutThreshold,
      facesDetectScoreThreshold:
          facesDetectScoreThreshold ?? this.facesDetectScoreThreshold,
      facesTrayPageLimit: facesTrayPageLimit ?? this.facesTrayPageLimit,
      jobsPollIntervalSeconds:
          jobsPollIntervalSeconds ?? this.jobsPollIntervalSeconds,
    );
  }

  Map<String, Object?> toJson() => {
        'where.showCountryWhenSameCountry': showCountryWhenSameCountry,
        'where.showStateWhenSameState': showStateWhenSameState,
        'ui.multiColumnSort': multiColumnSort,
        'ui.showFaceOverlays': showFaceOverlays,
        'where.familiarRegions': familiarRegions,
        'ui.libraryPageSize': libraryPageSize,
        'ui.recentCollectionsLimit': recentCollectionsLimit,
        'ingest.nearDuplicateThreshold': nearDuplicateThreshold,
        'video.sampleMinIntervalMs': sampleMinIntervalMs,
        'video.sampleMaxIntervalMs': sampleMaxIntervalMs,
        'video.softMaxFramesPerItem': softMaxFramesPerItem,
        'video.sceneCutThreshold': sceneCutThreshold,
        'faces.detectScoreThreshold': facesDetectScoreThreshold,
        'faces.trayPageLimit': facesTrayPageLimit,
        'jobs.pollIntervalSeconds': jobsPollIntervalSeconds,
      };

  factory DesktopPrefs.fromJson(Map<String, dynamic> json) {
    bool flag(String key, {required bool fallback}) {
      final v = json[key];
      if (v is bool) return v;
      if (v is String) return v == 'true' || v == '1';
      return fallback;
    }

    int intVal(String key, int fallback, {int min = 1, int max = 100000}) {
      final v = json[key];
      int? n;
      if (v is int) n = v;
      if (v is num) n = v.round();
      if (v is String) n = int.tryParse(v);
      if (n == null) return fallback;
      return n.clamp(min, max);
    }

    double doubleVal(
      String key,
      double fallback, {
      double min = 0,
      double max = 1,
    }) {
      final v = json[key];
      double? n;
      if (v is num) n = v.toDouble();
      if (v is String) n = double.tryParse(v);
      if (n == null) return fallback;
      return n.clamp(min, max);
    }

    final familiar = json['where.familiarRegions'];
    final legacyHome = json['where.homeState'];
    final familiarCsv = normalizeFamiliarRegionsCsv(
      familiar is String && familiar.isNotEmpty
          ? familiar
          : (legacyHome is String ? legacyHome : ''),
    );
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
      familiarRegions: familiarCsv,
      libraryPageSize: intVal(
        'ui.libraryPageSize',
        50,
        min: libraryPageSizeMin,
        max: libraryPageSizeMax,
      ),
      recentCollectionsLimit: intVal(
        'ui.recentCollectionsLimit',
        20,
        min: recentCollectionsLimitMin,
        max: recentCollectionsLimitMax,
      ),
      nearDuplicateThreshold: intVal(
        'ingest.nearDuplicateThreshold',
        4,
        min: nearDuplicateThresholdMin,
        max: nearDuplicateThresholdMax,
      ),
      sampleMinIntervalMs: intVal(
        'video.sampleMinIntervalMs',
        1000,
        min: sampleMinIntervalMsMin,
        max: sampleMinIntervalMsMax,
      ),
      sampleMaxIntervalMs: intVal(
        'video.sampleMaxIntervalMs',
        15000,
        min: sampleMaxIntervalMsMin,
        max: sampleMaxIntervalMsMax,
      ),
      softMaxFramesPerItem: intVal(
        'video.softMaxFramesPerItem',
        500,
        min: softMaxFramesPerItemMin,
        max: softMaxFramesPerItemMax,
      ),
      sceneCutThreshold: doubleVal(
        'video.sceneCutThreshold',
        0.3,
        min: sceneCutThresholdMin,
        max: sceneCutThresholdMax,
      ),
      facesDetectScoreThreshold: doubleVal(
        'faces.detectScoreThreshold',
        0.2,
        min: facesDetectScoreThresholdMin,
        max: facesDetectScoreThresholdMax,
      ),
      facesTrayPageLimit: intVal(
        'faces.trayPageLimit',
        500,
        min: facesTrayPageLimitMin,
        max: facesTrayPageLimitMax,
      ),
      jobsPollIntervalSeconds: intVal(
        'jobs.pollIntervalSeconds',
        2,
        min: jobsPollIntervalSecondsMin,
        max: jobsPollIntervalSecondsMax,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DesktopPrefs &&
      other.showCountryWhenSameCountry == showCountryWhenSameCountry &&
      other.showStateWhenSameState == showStateWhenSameState &&
      other.multiColumnSort == multiColumnSort &&
      other.showFaceOverlays == showFaceOverlays &&
      other.familiarRegions == familiarRegions &&
      other.libraryPageSize == libraryPageSize &&
      other.recentCollectionsLimit == recentCollectionsLimit &&
      other.nearDuplicateThreshold == nearDuplicateThreshold &&
      other.sampleMinIntervalMs == sampleMinIntervalMs &&
      other.sampleMaxIntervalMs == sampleMaxIntervalMs &&
      other.softMaxFramesPerItem == softMaxFramesPerItem &&
      other.sceneCutThreshold == sceneCutThreshold &&
      other.facesDetectScoreThreshold == facesDetectScoreThreshold &&
      other.facesTrayPageLimit == facesTrayPageLimit &&
      other.jobsPollIntervalSeconds == jobsPollIntervalSeconds;

  @override
  int get hashCode => Object.hash(
        showCountryWhenSameCountry,
        showStateWhenSameState,
        multiColumnSort,
        showFaceOverlays,
        familiarRegions,
        libraryPageSize,
        recentCollectionsLimit,
        nearDuplicateThreshold,
        sampleMinIntervalMs,
        sampleMaxIntervalMs,
        softMaxFramesPerItem,
        sceneCutThreshold,
        facesDetectScoreThreshold,
        facesTrayPageLimit,
        jobsPollIntervalSeconds,
      );
}
