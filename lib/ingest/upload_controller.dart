import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:tagkin_desktop/api/items_repository.dart';
import 'package:tagkin_desktop/app_shell.dart' show itemsRepositoryProvider;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/model_host_uploader.dart';
import 'package:tagkin_desktop/ingest/upload_mime.dart';
import 'package:tagkin_desktop/prepass/frame_sampler.dart';
import 'package:tagkin_desktop/prepass/prepass_controller.dart';

/// Lifecycle phase of a D5 upload run.
enum UploadPhase { idle, running, done, error }

/// One item's outcome after [UploadController.run].
class UploadOutcome {
  const UploadOutcome({
    required this.itemId,
    this.analysisRef,
    this.error,
  });

  final String itemId;
  final String? analysisRef;
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

/// Orchestrates D5: for each succeeded D4 [PrePassOutcome], mint a grant,
/// PUT primary-frame bytes to the model host, and record `analysisRef`.
///
/// - Photo: uploads the whole original local file.
/// - Video: uploads one D4-sampled representative frame (first sample);
///   skips when no samples exist.
///
/// Bytes never enter tagkin-api (R1/R5); grant is URL-only (R8); owner is
/// never sent (R10).
class UploadController extends ChangeNotifier {
  UploadController({
    required this.itemsRepository,
    this.putBytes = putBytesToUploadUrl,
    this.readBytes,
  });

  final ItemsRepository itemsRepository;
  final ModelHostPut putBytes;

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

  /// Runs upload for every succeeded pre-pass outcome. Continues past
  /// individual failures so one bad file doesn't abort the batch.
  Future<void> run(
    List<PrePassOutcome> prePassOutcomes,
    Map<String, List<FrameSample>> frameSamplesByItemId,
  ) async {
    final succeeded =
        prePassOutcomes.where((o) => o.succeeded).toList();
    if (succeeded.isEmpty) {
      phase = UploadPhase.done;
      outcomes = const [];
      notifyListeners();
      return;
    }

    phase = UploadPhase.running;
    error = null;
    final newOutcomes = <UploadOutcome>[];
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
    final primaryPath = _primaryUploadPath(
      item: item,
      sourcePath: prePass.path,
      frameSamples: frameSamples,
    );
    if (primaryPath == null) {
      // Video with no sampled frames — skip rather than invent bytes.
      return null;
    }

    final mimeType = mimeTypeForPath(primaryPath, item.type);
    final bytes = await _read(primaryPath);

    final grant = await itemsRepository.createUploadGrant(
      item.id,
      CreateUploadGrant(mimeType: mimeType),
    );

    String? analysisRef;
    try {
      analysisRef = await _putWithExpiryRetry(
        itemId: item.id,
        grant: grant,
        bytes: bytes,
        mimeType: mimeType,
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

  /// One fresh-grant retry on model-host failure / expired grant, then fail.
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
    } catch (_) {
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

  /// Photo → whole original file; video → first D4 sample (or null to skip).
  static String? _primaryUploadPath({
    required Item item,
    required String sourcePath,
    required List<FrameSample> frameSamples,
  }) {
    if (item.type == ItemType.photo) return sourcePath;
    if (frameSamples.isEmpty) return null;
    return frameSamples.first.path;
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
