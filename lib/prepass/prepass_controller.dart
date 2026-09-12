import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/items_repository.dart';
import 'package:tagkin_desktop/app_shell.dart' show itemsRepositoryProvider;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/ingest_outcome.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';
import 'package:tagkin_desktop/prepass/auto_fix_blurry.dart';
import 'package:tagkin_desktop/prepass/face_embedder.dart';
import 'package:tagkin_desktop/prepass/frame_sampler.dart';
import 'package:tagkin_desktop/prepass/prepass_payload_builder.dart';
import 'package:tagkin_desktop/prepass/unsharp.dart';

/// Lifecycle phase of a client pre-pass run (D4).
enum PrePassPhase { idle, running, done, error }

/// One item's outcome after [PrePassController.run].
class PrePassOutcome {
  const PrePassOutcome({
    required this.itemId,
    required this.path,
    this.stillPath,
    this.response,
    this.frameSamples = const [],
    this.error,
  });

  final String itemId;
  /// Original local source path (who-face crops stay on this until retarget).
  final String path;
  /// Sharpened JPEG for thumbs/upload when auto-fix ran; else [path].
  final String? stillPath;
  final PrePassResultResponse? response;
  final List<FrameSample> frameSamples;
  final Object? error;

  bool get succeeded => response != null && error == null;

  String get uploadPath => stillPath ?? path;
}

typedef PrePassPayloadBuilder = Future<PrePassBuildResult> Function({
  required String path,
  required ItemType type,
  FaceEmbedder? faceEmbedder,
  bool skipFaces,
  int maxFrames,
  int minIntervalMs,
  int maxIntervalMs,
  double sceneCutThreshold,
});

/// Orchestrates D4: for each D3 [IngestOutcome], build a contract-shaped
/// pre-pass payload from local media and `POST /items/{id}/pre-pass-result`.
///
/// Sends only vectors/metadata/text — never media bytes (R1/R5); never invents
/// owner/scope (R10). Frame samples stay local for D5.
class PrePassController extends ChangeNotifier {
  PrePassController({
    required this.itemsRepository,
    this.faceEmbedder,
    this.buildPayload = buildPrePassPayload,
    DesktopPrefs? samplingPrefs,
    this.deblurCacheDir,
  }) : _samplingPrefs = samplingPrefs ?? DesktopPrefs.defaults;

  final ItemsRepository itemsRepository;
  final FaceEmbedder? faceEmbedder;
  final PrePassPayloadBuilder buildPayload;
  DesktopPrefs _samplingPrefs;
  /// Override app-support deblur cache (tests).
  final Directory? deblurCacheDir;

  /// Refresh video/face sampling knobs from Settings without recreating.
  void applySamplingPrefs(DesktopPrefs prefs) {
    _samplingPrefs = prefs;
  }

  PrePassPhase phase = PrePassPhase.idle;
  Object? error;
  List<PrePassOutcome> outcomes = const [];

  /// Frame samples keyed by item id — the hook D5 will consume (not uploaded
  /// by D4).
  final Map<String, List<FrameSample>> frameSamplesByItemId =
      <String, List<FrameSample>>{};

  /// Runs pre-pass for every succeeded ingest outcome. Continues past
  /// individual failures so one bad file doesn't abort the batch.
  ///
  /// When [append] is true, keeps prior [outcomes] and frame samples so a
  /// per-item pipeline can accumulate results across calls.
  Future<void> run(
    List<IngestOutcome> ingestOutcomes, {
    bool append = false,
  }) async {
    final succeeded = ingestOutcomes
        .where((o) => o.succeeded && o.item != null)
        .toList();
    if (succeeded.isEmpty) {
      phase = PrePassPhase.done;
      if (!append) {
        outcomes = const [];
      }
      notifyListeners();
      return;
    }

    phase = PrePassPhase.running;
    error = null;
    final newOutcomes =
        append ? List<PrePassOutcome>.from(outcomes) : <PrePassOutcome>[];
    if (!append) {
      frameSamplesByItemId.clear();
    }
    notifyListeners();

    final prefs = _samplingPrefs;
    for (final ingest in succeeded) {
      final item = ingest.item!;
      try {
        final built = await buildPayload(
          path: ingest.path,
          type: item.type,
          faceEmbedder: faceEmbedder,
          // Who-face crops (WhoFaceLinker) own identity linking — not
          // full-image pre-pass embeddings (avoids duplicate suggested persons).
          skipFaces: true,
          maxFrames: prefs.softMaxFramesPerItem,
          minIntervalMs: prefs.sampleMinIntervalMs,
          maxIntervalMs: prefs.sampleMaxIntervalMs,
          sceneCutThreshold: prefs.sceneCutThreshold,
        );
        var payload = built.payload;
        String? stillPath;
        if (item.type == ItemType.photo) {
          stillPath = await _maybeAutoFix(
            originalPath: ingest.path,
            payload: payload,
            prefs: prefs,
          );
          if (stillPath != null) {
            payload = PrePassResult(
              contentHash: payload.contentHash,
              perceptualHash: payload.perceptualHash,
              sharpness: payload.sharpness,
              capturedAt: payload.capturedAt,
              where: payload.where,
              durationMs: payload.durationMs,
              keyPeriods: payload.keyPeriods,
              appearances: payload.appearances,
              deblur: const PrePassDeblur(
                applied: true,
                methodId: kLocalUnsharpMethodId,
              ),
            );
          }
        }
        final response = await itemsRepository.recordPrePassResult(
          item.id,
          payload,
        );
        frameSamplesByItemId[item.id] = built.frameSamples;
        newOutcomes.add(
          PrePassOutcome(
            itemId: item.id,
            path: ingest.path,
            stillPath: stillPath,
            response: response,
            frameSamples: built.frameSamples,
          ),
        );
      } catch (e) {
        newOutcomes.add(
          PrePassOutcome(
            itemId: item.id,
            path: ingest.path,
            error: e,
          ),
        );
      }
      outcomes = List.unmodifiable(newOutcomes);
      notifyListeners();
    }

    phase = PrePassPhase.done;
    notifyListeners();
  }

  Future<String?> _maybeAutoFix({
    required String originalPath,
    required PrePassResult payload,
    required DesktopPrefs prefs,
  }) async {
    if (!prefs.autoFixBlurryPhotos) return null;
    final hash = payload.contentHash;
    if (hash == null || hash.isEmpty) return null;
    try {
      final bytes = await File(originalPath).readAsBytes();
      Directory cacheDir;
      try {
        cacheDir = deblurCacheDir ?? await defaultDeblurCacheDir();
      } catch (_) {
        return null;
      }
      final fixed = await autoFixBlurryPhoto(
        originalPath: originalPath,
        originalBytes: Uint8List.fromList(bytes),
        sharpness: payload.sharpness,
        contentHash: hash,
        prefs: prefs,
        cacheDir: cacheDir,
      );
      return fixed?.cachePath;
    } catch (e) {
      debugPrint('PrePassController: auto-fix skipped for $originalPath: $e');
      return null;
    }
  }

  void reset() {
    phase = PrePassPhase.idle;
    error = null;
    outcomes = const [];
    frameSamplesByItemId.clear();
    notifyListeners();
  }
}

final prePassControllerProvider = Provider.autoDispose<PrePassController>(
  (ref) {
    final controller = PrePassController(
      itemsRepository: ref.watch(itemsRepositoryProvider),
      samplingPrefs: ref.watch(desktopPrefsProvider),
    );
    ref.onDispose(controller.dispose);
    return controller;
  },
  dependencies: [itemsRepositoryProvider, desktopPrefsProvider],
);
