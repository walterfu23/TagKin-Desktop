import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/items_repository.dart';
import 'package:tagkin_desktop/app_shell.dart' show itemsRepositoryProvider;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/batch_ingest_controller.dart';
import 'package:tagkin_desktop/prepass/face_embedder.dart';
import 'package:tagkin_desktop/prepass/frame_sampler.dart';
import 'package:tagkin_desktop/prepass/prepass_payload_builder.dart';

/// Lifecycle phase of a client pre-pass run (D4).
enum PrePassPhase { idle, running, done, error }

/// One item's outcome after [PrePassController.run].
class PrePassOutcome {
  const PrePassOutcome({
    required this.itemId,
    required this.path,
    this.response,
    this.frameSamples = const [],
    this.error,
  });

  final String itemId;
  final String path;
  final PrePassResultResponse? response;
  final List<FrameSample> frameSamples;
  final Object? error;

  bool get succeeded => response != null && error == null;
}

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
  });

  final ItemsRepository itemsRepository;
  final FaceEmbedder? faceEmbedder;
  final Future<PrePassBuildResult> Function({
    required String path,
    required ItemType type,
    FaceEmbedder? faceEmbedder,
    bool skipFaces,
    int maxFrames,
  }) buildPayload;

  PrePassPhase phase = PrePassPhase.idle;
  Object? error;
  List<PrePassOutcome> outcomes = const [];

  /// Frame samples keyed by item id — the hook D5 will consume (not uploaded
  /// by D4).
  final Map<String, List<FrameSample>> frameSamplesByItemId =
      <String, List<FrameSample>>{};

  /// Runs pre-pass for every succeeded ingest outcome. Continues past
  /// individual failures so one bad file doesn't abort the batch.
  Future<void> run(List<IngestOutcome> ingestOutcomes) async {
    final succeeded = ingestOutcomes
        .where((o) => o.succeeded && o.item != null)
        .toList();
    if (succeeded.isEmpty) {
      phase = PrePassPhase.done;
      outcomes = const [];
      notifyListeners();
      return;
    }

    phase = PrePassPhase.running;
    error = null;
    final newOutcomes = <PrePassOutcome>[];
    frameSamplesByItemId.clear();
    notifyListeners();

    for (final ingest in succeeded) {
      final item = ingest.item!;
      try {
        final built = await buildPayload(
          path: ingest.path,
          type: item.type,
          faceEmbedder: faceEmbedder,
          skipFaces: false,
          maxFrames: kDefaultMaxFramesPerItem,
        );
        final response = await itemsRepository.recordPrePassResult(
          item.id,
          built.payload,
        );
        frameSamplesByItemId[item.id] = built.frameSamples;
        newOutcomes.add(
          PrePassOutcome(
            itemId: item.id,
            path: ingest.path,
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
    );
    ref.onDispose(controller.dispose);
    return controller;
  },
  dependencies: [itemsRepositoryProvider],
);
