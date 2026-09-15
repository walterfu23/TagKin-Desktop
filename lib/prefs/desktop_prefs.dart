import 'package:tagkin_desktop/item_lists/export_photo_transition.dart';
import 'package:tagkin_desktop/item_lists/export_sequence_size.dart';
import 'package:tagkin_desktop/ui/format_local_datetime.dart';
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
    this.recentViewsLimit = 10,
    this.nearDuplicateThreshold = 4,
    this.sampleMinIntervalMs = 1000,
    this.sampleMaxIntervalMs = 15000,
    this.softMaxFramesPerItem = 50,
    this.sceneCutThreshold = 0.3,
    this.facesDetectScoreThreshold = 0.2,
    this.facesTrayPageLimit = 500,
    this.personsListColumns = 5,
    this.autoConfirmHighConfidencePersonMatches = true,
    this.autoConfirmMinConfidencePercent = 95,
    this.jobsPollIntervalSeconds = 2,
    this.dateTimeFormat = DateTimeDisplayFormat.local,
    this.itemListBlurrySharpnessThreshold = 80,
    this.autoFixBlurryPhotos = true,
    this.saveFixedPhotoInFolder = true,
    this.hideBlurryPhotos = false,
    this.showSharpnessScores = true,
    this.exportPhotoStillDurationSeconds = 2.5,
    this.exportPhotoTransition = ExportPhotoTransition.crossDissolve,
    this.exportPhotoTransitionSeconds = 1.0,
    this.exportSequenceSize = ExportSequenceSize.matchSmallest,
    this.exportMusicPrompt = '',
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

  /// Max collections listed under Open Recent and on the start gate.
  final int recentCollectionsLimit;

  /// Max recent saved Folders views listed in the Views menu (per collection).
  final int recentViewsLimit;

  /// Hamming distance ≤ this → near-duplicate at ingest.
  final int nearDuplicateThreshold;

  /// Min spacing (ms) between video sample frames in a short key period.
  final int sampleMinIntervalMs;

  /// Max spacing (ms) between video sample frames in a long key period.
  final int sampleMaxIntervalMs;

  /// Soft ceiling on sample frames per video item (Settings max 50).
  final int softMaxFramesPerItem;

  /// FFmpeg scene-cut sensitivity (lower → more cuts).
  final double sceneCutThreshold;

  /// SCRFD face-detect score floor used by the local ONNX embedder.
  final double facesDetectScoreThreshold;

  /// Appearances / exclusions list page size on Faces trays.
  final int facesTrayPageLimit;

  /// Face-crop columns on the Persons list page.
  final int personsListColumns;

  /// When true, WhoFaceLinker sends [autoConfirmMinConfidencePercent] so the
  /// API may auto-confirm high-confidence named-person matches.
  final bool autoConfirmHighConfidencePersonMatches;

  /// Minimum likeness confidence % for auto-confirm (0–100). Used only when
  /// [autoConfirmHighConfidencePersonMatches] is true.
  final int autoConfirmMinConfidencePercent;

  /// Job status poll interval while analyze/upload runs.
  final int jobsPollIntervalSeconds;

  /// How Captured / Added / When / comment timestamps are shown.
  final DateTimeDisplayFormat dateTimeFormat;

  /// Variance-of-Laplacian bar for Hide blurry / ingest auto-fix (0–50000).
  /// Default matches [kBlurrySharpnessThreshold] (80). Real photo stills
  /// often score in the thousands; raise the bar after reading on-thumb scores.
  final int itemListBlurrySharpnessThreshold;

  /// When true, ingest locally unsharps photos below the bar (0 credits).
  final bool autoFixBlurryPhotos;

  /// When true and [autoFixBlurryPhotos] is on, write `*.tagkin-fixed.jpg`
  /// next to the original. Never overwrites the original.
  final bool saveFixedPhotoInFolder;

  /// Hide blurry toggle (shared across Folders and Export list). When true,
  /// photos whose stored pre-pass sharpness is below
  /// [itemListBlurrySharpnessThreshold] are hidden from view and excluded
  /// from Export list's JSON. Persisted; not gated behind Settings Save.
  final bool hideBlurryPhotos;

  /// When true (default), show stored pre-pass sharpness on photo thumbs
  /// (Folders, Export list, and item detail) so the blurry bar can be
  /// chosen from real scores.
  final bool showSharpnessScores;

  /// How long each photo still lasts on an FCP7 XML / FCPXML timeline.
  /// JSON export is unaffected.
  final double exportPhotoStillDurationSeconds;

  /// Photo-to-photo transition on FCP7 XML / FCPXML. Hard cut into/out of
  /// video key periods. JSON export is unaffected.
  final ExportPhotoTransition exportPhotoTransition;

  /// Overlap length for [exportPhotoTransition] when it is not None.
  final double exportPhotoTransitionSeconds;

  /// Sequence frame size for FCP7 XML / FCPXML. JSON export is unaffected.
  final ExportSequenceSize exportSequenceSize;

  /// Default music-style prompt for MP4 export. Free text, not a vendor id.
  final String exportMusicPrompt;

  /// [dateTimeFormat] with a hot-reload fallback (new non-null fields read
  /// as null on instances created before the field existed).
  DateTimeDisplayFormat get dateTimeFormatOrLocal {
    try {
      return dateTimeFormat;
    } on TypeError {
      return DateTimeDisplayFormat.local;
    }
  }

  /// [exportPhotoTransition] with a hot-reload fallback.
  ExportPhotoTransition get exportPhotoTransitionOrDefault {
    try {
      return exportPhotoTransition;
    } on TypeError {
      return ExportPhotoTransition.crossDissolve;
    }
  }

  /// [exportPhotoStillDurationSeconds] with a hot-reload fallback.
  double get exportPhotoStillDurationSecondsOrDefault {
    try {
      return exportPhotoStillDurationSeconds;
    } on TypeError {
      return 2.5;
    }
  }

  /// [exportPhotoTransitionSeconds] with a hot-reload fallback.
  double get exportPhotoTransitionSecondsOrDefault {
    try {
      return exportPhotoTransitionSeconds;
    } on TypeError {
      return 1.0;
    }
  }

  /// [exportSequenceSize] with a hot-reload fallback.
  ExportSequenceSize get exportSequenceSizeOrDefault {
    try {
      return exportSequenceSize;
    } on TypeError {
      return ExportSequenceSize.matchSmallest;
    }
  }

  /// [exportMusicPrompt] with a hot-reload fallback.
  String get exportMusicPromptOrDefault {
    try {
      return exportMusicPrompt;
    } on TypeError {
      return '';
    }
  }

  static const defaults = DesktopPrefs();

  // Slider / clamp ranges (UI and fromJson share these).
  static const libraryPageSizeMin = 2;
  static const libraryPageSizeMax = 200;
  static const libraryPageSizeStep = 1;

  static const recentCollectionsLimitMin = 1;
  static const recentCollectionsLimitMax = 100;
  static const recentCollectionsLimitStep = 1;

  static const recentViewsLimitMin = 1;
  static const recentViewsLimitMax = 100;
  static const recentViewsLimitStep = 1;

  static const nearDuplicateThresholdMin = 0;
  static const nearDuplicateThresholdMax = 64;
  static const nearDuplicateThresholdStep = 1;

  static const sampleMinIntervalMsMin = 100;
  static const sampleMinIntervalMsMax = 60000;
  static const sampleMinIntervalMsStep = 100;

  static const sampleMaxIntervalMsMin = 500;
  static const sampleMaxIntervalMsMax = 60000;
  static const sampleMaxIntervalMsStep = 500;

  static const softMaxFramesPerItemMin = 10;
  static const softMaxFramesPerItemMax = 50;
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

  static const personsListColumnsMin = 1;
  static const personsListColumnsMax = 10;
  static const personsListColumnsStep = 1;

  static const autoConfirmMinConfidencePercentMin = 0;
  static const autoConfirmMinConfidencePercentMax = 100;
  static const autoConfirmMinConfidencePercentStep = 1;

  static const jobsPollIntervalSecondsMin = 1;
  static const jobsPollIntervalSecondsMax = 30;
  static const jobsPollIntervalSecondsStep = 1;

  static const itemListBlurrySharpnessThresholdMin = 0;
  static const itemListBlurrySharpnessThresholdMax = 50000;
  /// Step 10 keeps the default 80 on the slider grid (step 100 would snap
  /// it to 100). Typical stills are in the thousands.
  static const itemListBlurrySharpnessThresholdStep = 10;

  static const exportPhotoStillDurationSecondsMin = 0.5;
  static const exportPhotoStillDurationSecondsMax = 10.0;
  static const exportPhotoStillDurationSecondsStep = 0.5;

  static const exportPhotoTransitionSecondsMin = 0.1;
  static const exportPhotoTransitionSecondsMax = 2.0;
  static const exportPhotoTransitionSecondsStep = 0.1;

  DesktopPrefs copyWith({
    bool? showCountryWhenSameCountry,
    bool? showStateWhenSameState,
    bool? multiColumnSort,
    bool? showFaceOverlays,
    String? familiarRegions,
    int? libraryPageSize,
    int? recentCollectionsLimit,
    int? recentViewsLimit,
    int? nearDuplicateThreshold,
    int? sampleMinIntervalMs,
    int? sampleMaxIntervalMs,
    int? softMaxFramesPerItem,
    double? sceneCutThreshold,
    double? facesDetectScoreThreshold,
    int? facesTrayPageLimit,
    int? personsListColumns,
    bool? autoConfirmHighConfidencePersonMatches,
    int? autoConfirmMinConfidencePercent,
    int? jobsPollIntervalSeconds,
    DateTimeDisplayFormat? dateTimeFormat,
    int? itemListBlurrySharpnessThreshold,
    bool? autoFixBlurryPhotos,
    bool? saveFixedPhotoInFolder,
    bool? hideBlurryPhotos,
    bool? showSharpnessScores,
    double? exportPhotoStillDurationSeconds,
    ExportPhotoTransition? exportPhotoTransition,
    double? exportPhotoTransitionSeconds,
    ExportSequenceSize? exportSequenceSize,
    String? exportMusicPrompt,
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
      recentViewsLimit: recentViewsLimit ?? this.recentViewsLimit,
      nearDuplicateThreshold:
          nearDuplicateThreshold ?? this.nearDuplicateThreshold,
      sampleMinIntervalMs: sampleMinIntervalMs ?? this.sampleMinIntervalMs,
      sampleMaxIntervalMs: sampleMaxIntervalMs ?? this.sampleMaxIntervalMs,
      softMaxFramesPerItem: softMaxFramesPerItem ?? this.softMaxFramesPerItem,
      sceneCutThreshold: sceneCutThreshold ?? this.sceneCutThreshold,
      facesDetectScoreThreshold:
          facesDetectScoreThreshold ?? this.facesDetectScoreThreshold,
      facesTrayPageLimit: facesTrayPageLimit ?? this.facesTrayPageLimit,
      personsListColumns: personsListColumns ?? this.personsListColumns,
      autoConfirmHighConfidencePersonMatches:
          autoConfirmHighConfidencePersonMatches ??
              this.autoConfirmHighConfidencePersonMatches,
      autoConfirmMinConfidencePercent: autoConfirmMinConfidencePercent ??
          this.autoConfirmMinConfidencePercent,
      jobsPollIntervalSeconds:
          jobsPollIntervalSeconds ?? this.jobsPollIntervalSeconds,
      dateTimeFormat: dateTimeFormat ?? dateTimeFormatOrLocal,
      itemListBlurrySharpnessThreshold: itemListBlurrySharpnessThreshold ??
          this.itemListBlurrySharpnessThreshold,
      autoFixBlurryPhotos: autoFixBlurryPhotos ?? this.autoFixBlurryPhotos,
      saveFixedPhotoInFolder:
          saveFixedPhotoInFolder ?? this.saveFixedPhotoInFolder,
      hideBlurryPhotos: hideBlurryPhotos ?? this.hideBlurryPhotos,
      showSharpnessScores: showSharpnessScores ?? this.showSharpnessScores,
      exportPhotoStillDurationSeconds: exportPhotoStillDurationSeconds ??
          exportPhotoStillDurationSecondsOrDefault,
      exportPhotoTransition:
          exportPhotoTransition ?? exportPhotoTransitionOrDefault,
      exportPhotoTransitionSeconds: exportPhotoTransitionSeconds ??
          exportPhotoTransitionSecondsOrDefault,
      exportSequenceSize: exportSequenceSize ?? exportSequenceSizeOrDefault,
      exportMusicPrompt: exportMusicPrompt ?? exportMusicPromptOrDefault,
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
        'ui.recentViewsLimit': recentViewsLimit,
        'ingest.nearDuplicateThreshold': nearDuplicateThreshold,
        'video.sampleMinIntervalMs': sampleMinIntervalMs,
        'video.sampleMaxIntervalMs': sampleMaxIntervalMs,
        'video.softMaxFramesPerItem': softMaxFramesPerItem,
        'video.sceneCutThreshold': sceneCutThreshold,
        'faces.detectScoreThreshold': facesDetectScoreThreshold,
        'faces.trayPageLimit': facesTrayPageLimit,
        'ui.personsListColumns': personsListColumns,
        'faces.autoConfirmHighConfidencePersonMatches':
            autoConfirmHighConfidencePersonMatches,
        'faces.autoConfirmMinConfidencePercent':
            autoConfirmMinConfidencePercent,
        'jobs.pollIntervalSeconds': jobsPollIntervalSeconds,
        'ui.dateTimeFormat': dateTimeFormatOrLocal.wire,
        'export.blurrySharpnessThreshold': itemListBlurrySharpnessThreshold,
        'export.autoFixBlurryPhotos': autoFixBlurryPhotos,
        'export.saveFixedPhotoInFolder': saveFixedPhotoInFolder,
        'export.hideBlurryPhotos': hideBlurryPhotos,
        'export.showSharpnessScores': showSharpnessScores,
        'export.photoStillDurationSeconds':
            exportPhotoStillDurationSecondsOrDefault,
        'export.photoTransition': exportPhotoTransitionOrDefault.wire,
        'export.photoTransitionSeconds':
            exportPhotoTransitionSecondsOrDefault,
        'export.sequenceSize': exportSequenceSizeOrDefault.wire,
        'export.musicPrompt': exportMusicPromptOrDefault,
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
      recentViewsLimit: intVal(
        'ui.recentViewsLimit',
        10,
        min: recentViewsLimitMin,
        max: recentViewsLimitMax,
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
        50,
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
      personsListColumns: intVal(
        'ui.personsListColumns',
        5,
        min: personsListColumnsMin,
        max: personsListColumnsMax,
      ),
      autoConfirmHighConfidencePersonMatches: flag(
        'faces.autoConfirmHighConfidencePersonMatches',
        fallback: true,
      ),
      autoConfirmMinConfidencePercent: intVal(
        'faces.autoConfirmMinConfidencePercent',
        95,
        min: autoConfirmMinConfidencePercentMin,
        max: autoConfirmMinConfidencePercentMax,
      ),
      jobsPollIntervalSeconds: intVal(
        'jobs.pollIntervalSeconds',
        2,
        min: jobsPollIntervalSecondsMin,
        max: jobsPollIntervalSecondsMax,
      ),
      dateTimeFormat: DateTimeDisplayFormat.parse(json['ui.dateTimeFormat']),
      itemListBlurrySharpnessThreshold: intVal(
        'export.blurrySharpnessThreshold',
        80,
        min: itemListBlurrySharpnessThresholdMin,
        max: itemListBlurrySharpnessThresholdMax,
      ),
      autoFixBlurryPhotos: flag(
        'export.autoFixBlurryPhotos',
        fallback: true,
      ),
      saveFixedPhotoInFolder: flag(
        'export.saveFixedPhotoInFolder',
        fallback: true,
      ),
      hideBlurryPhotos: flag(
        'export.hideBlurryPhotos',
        fallback: false,
      ),
      showSharpnessScores: flag(
        'export.showSharpnessScores',
        fallback: true,
      ),
      exportPhotoStillDurationSeconds: doubleVal(
        'export.photoStillDurationSeconds',
        2.5,
        min: exportPhotoStillDurationSecondsMin,
        max: exportPhotoStillDurationSecondsMax,
      ),
      exportPhotoTransition: ExportPhotoTransition.parse(
        json['export.photoTransition'],
      ),
      exportPhotoTransitionSeconds: doubleVal(
        'export.photoTransitionSeconds',
        1.0,
        min: exportPhotoTransitionSecondsMin,
        max: exportPhotoTransitionSecondsMax,
      ),
      exportSequenceSize: ExportSequenceSize.parse(
        json['export.sequenceSize'],
      ),
      exportMusicPrompt: () {
        final v = json['export.musicPrompt'];
        return v is String ? v : '';
      }(),
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
      other.recentViewsLimit == recentViewsLimit &&
      other.nearDuplicateThreshold == nearDuplicateThreshold &&
      other.sampleMinIntervalMs == sampleMinIntervalMs &&
      other.sampleMaxIntervalMs == sampleMaxIntervalMs &&
      other.softMaxFramesPerItem == softMaxFramesPerItem &&
      other.sceneCutThreshold == sceneCutThreshold &&
      other.facesDetectScoreThreshold == facesDetectScoreThreshold &&
      other.facesTrayPageLimit == facesTrayPageLimit &&
      other.personsListColumns == personsListColumns &&
      other.autoConfirmHighConfidencePersonMatches ==
          autoConfirmHighConfidencePersonMatches &&
      other.autoConfirmMinConfidencePercent ==
          autoConfirmMinConfidencePercent &&
      other.jobsPollIntervalSeconds == jobsPollIntervalSeconds &&
      other.dateTimeFormatOrLocal == dateTimeFormatOrLocal &&
      other.itemListBlurrySharpnessThreshold ==
          itemListBlurrySharpnessThreshold &&
      other.autoFixBlurryPhotos == autoFixBlurryPhotos &&
      other.saveFixedPhotoInFolder == saveFixedPhotoInFolder &&
      other.hideBlurryPhotos == hideBlurryPhotos &&
      other.showSharpnessScores == showSharpnessScores &&
      other.exportPhotoStillDurationSecondsOrDefault ==
          exportPhotoStillDurationSecondsOrDefault &&
      other.exportPhotoTransitionOrDefault ==
          exportPhotoTransitionOrDefault &&
      other.exportPhotoTransitionSecondsOrDefault ==
          exportPhotoTransitionSecondsOrDefault &&
      other.exportSequenceSizeOrDefault == exportSequenceSizeOrDefault &&
      other.exportMusicPromptOrDefault == exportMusicPromptOrDefault;

  @override
  int get hashCode => Object.hashAll([
        showCountryWhenSameCountry,
        showStateWhenSameState,
        multiColumnSort,
        showFaceOverlays,
        familiarRegions,
        libraryPageSize,
        recentCollectionsLimit,
        recentViewsLimit,
        nearDuplicateThreshold,
        sampleMinIntervalMs,
        sampleMaxIntervalMs,
        softMaxFramesPerItem,
        sceneCutThreshold,
        facesDetectScoreThreshold,
        facesTrayPageLimit,
        personsListColumns,
        autoConfirmHighConfidencePersonMatches,
        autoConfirmMinConfidencePercent,
        jobsPollIntervalSeconds,
        dateTimeFormatOrLocal,
        itemListBlurrySharpnessThreshold,
        autoFixBlurryPhotos,
        saveFixedPhotoInFolder,
        hideBlurryPhotos,
        showSharpnessScores,
        exportPhotoStillDurationSecondsOrDefault,
        exportPhotoTransitionOrDefault,
        exportPhotoTransitionSecondsOrDefault,
        exportSequenceSizeOrDefault,
        exportMusicPromptOrDefault,
      ]);
}
