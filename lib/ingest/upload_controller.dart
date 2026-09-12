import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:tagkin_desktop/api/items_repository.dart';
import 'package:tagkin_desktop/app_shell.dart' show itemsRepositoryProvider;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/model_host_uploader.dart';
import 'package:tagkin_desktop/ingest/model_upload_image.dart';
import 'package:tagkin_desktop/prepass/frame_sampler.dart';
import 'package:tagkin_desktop/prepass/prepass_controller.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';

/// Lifecycle phase of a D5 upload run.
enum UploadPhase { idle, running, done, error }

/// One item's outcome after [UploadController.run] / [uploadItemFromLocal].
class UploadOutcome {
  const UploadOutcome({
    required this.itemId,
    this.analysisRef,
    this.item,
    this.error,
  });

  final String itemId;
  final String? analysisRef;
  final Item? item;
  final Object? error;

  bool get succeeded => analysisRef != null && error == null;
}

/// Injected direct-upload function (overridable in tests).
typedef ModelHostPut = Future<ModelHostUploadResult> Function({
  required String uploadUrl,
  required List<int> bytes,
  required String mimeType,
  http.Client? httpClient,
});

/// Prepares path bytes for model-host PUT (overridable in tests).
typedef PrepareModelUpload = Future<ModelUploadPayload> Function({
  required String path,
  required ItemType type,
  required List<int> rawBytes,
});

/// Orchestrates D5: for each succeeded D4 [PrePassOutcome], mint a grant,
/// PUT bytes to the model host, and record `analysisRef`.
///
/// - Photo: uploads the local still (sharpened JPEG when auto-fix ran;
///   HEIC/HEIF → JPEG first; JPEG EXIF Orientation 2–8 baked upright).
///   The original file is never overwritten.
/// - Video: uploads one D4 representative JPEG per key period (never the
///   source clip); skips when no samples exist.
///
/// Bytes never enter tagkin-api (R1/R5); grant is URL-only (R8); owner is
/// never sent (R10).
class UploadController extends ChangeNotifier {
  UploadController({
    required this.itemsRepository,
    this.putBytes = putBytesToUploadUrl,
    this.readBytes,
    this.prepareUpload = prepareModelUploadBytes,
  });

  final ItemsRepository itemsRepository;
  final ModelHostPut putBytes;
  final PrepareModelUpload prepareUpload;

  /// Override local file reads in tests (defaults to [File.readAsBytes]).
  final Future<List<int>> Function(String path)? readBytes;
  UploadPhase phase = UploadPhase.idle;
  Object? error;
  List<UploadOutcome> outcomes = const [];

  Future<List<int>> _read(String path) {
    final override = readBytes;
    if (override != null) return override(path);
    return File(path).readAsBytes();
  }

  /// Uploads one existing library photo from its local `sourceRef` to the
  /// model host and records a fresh `analysisRef` (no new item / no re-import).
  ///
  /// Used for re-analyze after Gemini Files TTL and for expired refs.
  Future<UploadOutcome> uploadItemFromLocal(
    Item item, {
    Future<LocalMediaResolution> Function(Item item)? resolveMedia,
  }) async {
    if (item.type != ItemType.photo) {
      return UploadOutcome(
        itemId: item.id,
        error: StateError(
          'Re-upload is photo-only in v1 (sample-frame tagging).',
        ),
      );
    }

    phase = UploadPhase.running;
    error = null;
    notifyListeners();

    try {
      final resolution =
          await (resolveMedia ?? resolveLocalMedia)(item);
      if (!resolution.isAvailable || resolution.file == null) {
        final message = switch (resolution.status) {
          LocalMediaStatus.missing =>
            'Local media not found.',
          LocalMediaStatus.accessDenied =>
            'macOS blocked access to this file. Re-select the folder (bookmark).',
          LocalMediaStatus.hashMismatch =>
            'This file does not match the library record.',
          _ => 'Local media is not available for re-upload.',
        };
        final outcome = UploadOutcome(
          itemId: item.id,
          error: StateError(message),
        );
        outcomes = [outcome];
        phase = UploadPhase.error;
        error = outcome.error;
        notifyListeners();
        return outcome;
      }

      final path = resolution.file!.path;
      final rawBytes = await _read(path);
      final prepared = await prepareUpload(
        path: path,
        type: item.type,
        rawBytes: rawBytes,
      );

      final grant = await itemsRepository.createUploadGrant(
        item.id,
        CreateUploadGrant(mimeType: prepared.mimeType),
      );

      String? analysisRef;
      try {
        analysisRef = await _putWithExpiryRetry(
          itemId: item.id,
          grant: grant,
          bytes: prepared.bytes,
          mimeType: prepared.mimeType,
        );
      } catch (e) {
        final outcome = UploadOutcome(itemId: item.id, error: e);
        outcomes = [outcome];
        phase = UploadPhase.error;
        error = e;
        notifyListeners();
        return outcome;
      }

      analysisRef ??= _synthesizeAnalysisRef(item.id, grant.uploadUrl);

      final recorded = await itemsRepository.recordAnalysisRef(
        item.id,
        RecordAnalysisRef(analysisRef: analysisRef),
      );

      final outcome = UploadOutcome(
        itemId: item.id,
        analysisRef: recorded.analysisRef ?? analysisRef,
        item: recorded,
      );
      outcomes = [outcome];
      phase = UploadPhase.done;
      notifyListeners();
      return outcome;
    } catch (e) {
      final outcome = UploadOutcome(itemId: item.id, error: e);
      outcomes = [outcome];
      phase = UploadPhase.error;
      error = e;
      notifyListeners();
      return outcome;
    }
  }

  /// Runs upload for every succeeded pre-pass outcome. Continues past
  /// individual failures so one bad file doesn't abort the batch.
  ///
  /// When [append] is true, keeps prior [outcomes] so a per-item pipeline
  /// can accumulate results across calls.
  Future<void> run(
    List<PrePassOutcome> prePassOutcomes,
    Map<String, List<FrameSample>> frameSamplesByItemId, {
    bool append = false,
  }) async {
    final succeeded =
        prePassOutcomes.where((o) => o.succeeded).toList();
    if (succeeded.isEmpty) {
      phase = UploadPhase.done;
      if (!append) {
        outcomes = const [];
      }
      notifyListeners();
      return;
    }

    phase = UploadPhase.running;
    error = null;
    final newOutcomes =
        append ? List<UploadOutcome>.from(outcomes) : <UploadOutcome>[];
    notifyListeners();

    for (final prePass in succeeded) {
      try {
        final outcome = await _uploadOne(
          prePass,
          frameSamplesByItemId[prePass.itemId] ?? const [],
        );
        if (outcome != null) {
          newOutcomes.add(outcome);
        }
      } catch (e) {
        newOutcomes.add(
          UploadOutcome(itemId: prePass.itemId, error: e),
        );
      }
      outcomes = List.unmodifiable(newOutcomes);
      notifyListeners();
    }

    phase = UploadPhase.done;
    notifyListeners();
  }

  /// Returns null when the item is skipped (e.g. video with no frames).
  Future<UploadOutcome?> _uploadOne(
    PrePassOutcome prePass,
    List<FrameSample> frameSamples,
  ) async {
    final item = prePass.response!.item;
    if (item.type == ItemType.video) {
      return _uploadVideoFrames(item, prePass.response!, frameSamples);
    }

    final rawBytes = await _read(prePass.uploadPath);
    final prepared = await prepareUpload(
      path: prePass.uploadPath,
      type: item.type,
      rawBytes: rawBytes,
    );

    final grant = await itemsRepository.createUploadGrant(
      item.id,
      CreateUploadGrant(mimeType: prepared.mimeType),
    );

    String? analysisRef;
    try {
      analysisRef = await _putWithExpiryRetry(
        itemId: item.id,
        grant: grant,
        bytes: prepared.bytes,
        mimeType: prepared.mimeType,
      );
    } catch (e) {
      return UploadOutcome(itemId: item.id, error: e);
    }
    analysisRef ??= _synthesizeAnalysisRef(item.id, grant.uploadUrl);

    final recorded = await itemsRepository.recordAnalysisRef(
      item.id,
      RecordAnalysisRef(analysisRef: analysisRef),
    );

    return UploadOutcome(
      itemId: item.id,
      analysisRef: recorded.analysisRef ?? analysisRef,
    );
  }

  Future<UploadOutcome?> _uploadVideoFrames(
    Item item,
    PrePassResultResponse response,
    List<FrameSample> frameSamples,
  ) async {
    final periodIds = response.keyPeriodIds;
    final picked = pickRepresentativeFramesPerKeyPeriod(
      samples: frameSamples,
      keyPeriodCount: periodIds.length,
    );
    if (picked.isEmpty) return null;

    final refs = <KeyPeriodAnalysisRef>[];
    String? firstRef;
    for (final sample in picked) {
      if (sample.keyPeriodIndex < 0 ||
          sample.keyPeriodIndex >= periodIds.length) {
        continue;
      }
      final rawBytes = await _read(sample.path);
      final prepared = await prepareUpload(
        path: sample.path,
        type: ItemType.video,
        rawBytes: rawBytes,
      );
      final grant = await itemsRepository.createUploadGrant(
        item.id,
        CreateUploadGrant(mimeType: prepared.mimeType),
      );
      String? analysisRef;
      try {
        analysisRef = await _putWithExpiryRetry(
          itemId: item.id,
          grant: grant,
          bytes: prepared.bytes,
          mimeType: prepared.mimeType,
        );
      } catch (e) {
        return UploadOutcome(itemId: item.id, error: e);
      }
      analysisRef ??= _synthesizeAnalysisRef(
        '${item.id}-${sample.keyPeriodIndex}',
        grant.uploadUrl,
      );
      firstRef ??= analysisRef;
      refs.add(
        KeyPeriodAnalysisRef(
          keyPeriodId: periodIds[sample.keyPeriodIndex],
          analysisRef: analysisRef,
          sampleTimestampMs: sample.timestampMs,
        ),
      );
    }
    if (refs.isEmpty || firstRef == null) return null;

    final recorded = await itemsRepository.recordAnalysisRef(
      item.id,
      RecordAnalysisRef(
        analysisRef: firstRef,
        keyPeriodRefs: refs,
      ),
    );
    return UploadOutcome(
      itemId: item.id,
      analysisRef: recorded.analysisRef ?? firstRef,
    );
  }

  /// One fresh-grant retry on model-host failure / expired grant, then fail.
  ///
  /// Only [ModelHostUploadException] triggers a retry — other errors (I/O,
  /// test failures, programming bugs) propagate without minting a second grant.
  Future<String?> _putWithExpiryRetry({
    required String itemId,
    required UploadGrant grant,
    required List<int> bytes,
    required String mimeType,
  }) async {
    try {
      if (_isExpired(grant.expiresAt)) {
        throw ModelHostUploadException(
          statusCode: 403,
          message: 'Upload grant expired',
        );
      }
      final result = await putBytes(
        uploadUrl: grant.uploadUrl,
        bytes: bytes,
        mimeType: mimeType,
      );
      return result.analysisRef;
    } on ModelHostUploadException {
      // Fresh grant once, then fail.
      final fresh = await itemsRepository.createUploadGrant(
        itemId,
        CreateUploadGrant(mimeType: mimeType),
      );
      final result = await putBytes(
        uploadUrl: fresh.uploadUrl,
        bytes: bytes,
        mimeType: mimeType,
      );
      return result.analysisRef;
    }
  }

  static bool _isExpired(String expiresAt) {
    try {
      return DateTime.parse(expiresAt).isBefore(DateTime.now());
    } on FormatException {
      return false;
    }
  }

  /// Stub / unparseable host response — synthesize a deterministic ref
  /// (mirrors tagkin-web's `stub://files/<id>` / `files/tagkin-<id>`).
  static String _synthesizeAnalysisRef(String itemId, String uploadUrl) {
    if (uploadUrl.contains('stub.tagkin.test')) {
      return 'stub://files/$itemId';
    }
    return 'files/tagkin-$itemId';
  }

  void reset() {
    phase = UploadPhase.idle;
    error = null;
    outcomes = const [];
    notifyListeners();
  }
}

final uploadControllerProvider = Provider.autoDispose<UploadController>(
  (ref) {
    final controller = UploadController(
      itemsRepository: ref.watch(itemsRepositoryProvider),
    );
    ref.onDispose(controller.dispose);
    return controller;
  },
  dependencies: [itemsRepositoryProvider],
);
