import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/items_repository.dart';
import 'package:tagkin_desktop/app_shell.dart' show itemsRepositoryProvider;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/content_hash.dart';
import 'package:tagkin_desktop/ingest/dedup.dart';
import 'package:tagkin_desktop/ingest/folder_picker.dart';
import 'package:tagkin_desktop/ingest/media_enumerator.dart';
import 'package:tagkin_desktop/ingest/perceptual_hash.dart';

/// Lifecycle phase of a folder-ingest run.
enum BatchIngestPhase { idle, scanning, reviewing, ingesting, done, error }

/// One representative's outcome after [BatchIngestController.confirmIngest].
class IngestOutcome {
  const IngestOutcome({required this.path, this.item, this.error});

  final String path;
  final Item? item;
  final Object? error;

  bool get succeeded => item != null;
}

/// Orchestrates D3: pick folder → enumerate → hash (content + perceptual) →
/// dedup (incl. the account's existing library) → user-reviewed batch
/// selection → `POST /items` per selection.
///
/// Sends only refs/hashes to `tagkin-api`, never bytes (R1/R5/R7); never
/// invents an owner/scope field (R10) — [ItemsRepository] derives that from
/// the bearer token.
class BatchIngestController extends ChangeNotifier {
  BatchIngestController({
    required this.itemsRepository,
    required this.folderPicker,
    this.enumerateFolder = enumerateMedia,
    this.contentHasher = computeContentHash,
    this.perceptualHasher = computePerceptualHashFromFile,
    this.nearDuplicateHammingThreshold = kDefaultNearDuplicateThreshold,
  });

  final ItemsRepository itemsRepository;
  final FolderPicker folderPicker;
  final Future<List<MediaCandidate>> Function(String path) enumerateFolder;
  final Future<String> Function(String path) contentHasher;
  final Future<String?> Function(String path) perceptualHasher;
  final int nearDuplicateHammingThreshold;

  BatchIngestPhase phase = BatchIngestPhase.idle;
  String? folderPath;
  Object? error;

  DedupResult? dedupResult;
  final Set<String> selectedPaths = <String>{};

  List<IngestOutcome> outcomes = const [];

  int get totalFound =>
      (dedupResult?.representatives.length ?? 0) +
      (dedupResult?.skipped.length ?? 0);

  /// Opens the folder picker; on selection, runs enumerate → hash → dedup.
  /// A cancelled dialog (`null`) leaves [phase] at [BatchIngestPhase.idle].
  /// Picker failures (e.g. missing macOS sandbox entitlements) surface as
  /// [BatchIngestPhase.error] instead of appearing to do nothing.
  Future<void> pickAndScan() async {
    try {
      final picked = await folderPicker();
      if (picked == null) return;
      await scanFolder(picked);
    } catch (e) {
      error = e;
      phase = BatchIngestPhase.error;
      notifyListeners();
    }
  }

  /// Runs enumerate → hash → dedup for a known [path] directly — used by
  /// [pickAndScan] and by tests/integration to bypass the native dialog.
  Future<void> scanFolder(String path) async {
    folderPath = path;
    phase = BatchIngestPhase.scanning;
    error = null;
    notifyListeners();

    try {
      final candidates = await enumerateFolder(path);
      final hashed = <HashedCandidate>[];
      for (final candidate in candidates) {
        final contentHash = await contentHasher(candidate.path);
        // Perceptual near-dup grouping is photo-only in D3; video near-dup
        // needs frame sampling (D4).
        final perceptualHash = candidate.type == ItemType.photo
            ? await perceptualHasher(candidate.path)
            : null;
        hashed.add(
          HashedCandidate(
            candidate: candidate,
            contentHash: contentHash,
            perceptualHash: perceptualHash,
          ),
        );
      }

      final existingItems = await itemsRepository.listItems();
      final existingHashes = existingItems
          .map((item) => item.contentHash)
          .whereType<String>()
          .toSet();

      final result = dedupCandidates(
        candidates: hashed,
        existingContentHashes: existingHashes,
        nearDuplicateHammingThreshold: nearDuplicateHammingThreshold,
      );

      dedupResult = result;
      selectedPaths
        ..clear()
        ..addAll(result.representatives.map((r) => r.candidate.path));
      phase = BatchIngestPhase.reviewing;
    } catch (e) {
      error = e;
      phase = BatchIngestPhase.error;
    }
    notifyListeners();
  }

  void toggleSelection(String path) {
    if (!selectedPaths.remove(path)) {
      selectedPaths.add(path);
    }
    notifyListeners();
  }

  /// Creates one item per currently-selected representative via
  /// `POST /items` — metadata/refs only (R1/R7); continues past individual
  /// create failures so one bad file doesn't abort the whole batch.
  Future<void> confirmIngest() async {
    final result = dedupResult;
    if (result == null) return;
    phase = BatchIngestPhase.ingesting;
    final newOutcomes = <IngestOutcome>[];
    notifyListeners();

    for (final candidate in result.representatives) {
      final path = candidate.candidate.path;
      if (!selectedPaths.contains(path)) continue;
      try {
        final item = await itemsRepository.createItem(
          CreateItem(
            type: candidate.candidate.type,
            sourceType: SourceType.local,
            sourceRef: Uri.file(path).toString(),
            contentHash: candidate.contentHash,
            capturedAt: candidate.candidate.modifiedAt.toIso8601String(),
          ),
        );
        newOutcomes.add(IngestOutcome(path: path, item: item));
      } catch (e) {
        newOutcomes.add(IngestOutcome(path: path, error: e));
      }
      outcomes = List.unmodifiable(newOutcomes);
      notifyListeners();
    }

    phase = BatchIngestPhase.done;
    notifyListeners();
  }

  /// Returns to [BatchIngestPhase.idle] (e.g. "ingest another folder").
  void reset() {
    phase = BatchIngestPhase.idle;
    folderPath = null;
    error = null;
    dedupResult = null;
    selectedPaths.clear();
    outcomes = const [];
    notifyListeners();
  }
}

/// Real folder enumeration — overridable in widget tests so `testWidgets`
/// never drives real `dart:io` filesystem calls through the pumped frame
/// loop (a real hang risk under `AutomatedTestWidgetsFlutterBinding`; plain
/// `test()` fixtures in `media_enumerator_test.dart` / `batch_ingest_
/// controller_test.dart` still use it directly and are unaffected).
final mediaEnumeratorProvider =
    Provider<Future<List<MediaCandidate>> Function(String)>(
  (ref) => enumerateMedia,
);

/// Overridable in widget tests for the same reason as [mediaEnumeratorProvider].
final contentHasherProvider = Provider<Future<String> Function(String)>(
  (ref) => computeContentHash,
);

/// Overridable in widget tests for the same reason as [mediaEnumeratorProvider].
final perceptualHasherProvider = Provider<Future<String?> Function(String)>(
  (ref) => computePerceptualHashFromFile,
);

/// Fresh controller per ingest session; disposed when the owning page/scope
/// is disposed.
final batchIngestControllerProvider =
    Provider.autoDispose<BatchIngestController>(
  (ref) {
    final controller = BatchIngestController(
      itemsRepository: ref.watch(itemsRepositoryProvider),
      folderPicker: ref.watch(folderPickerProvider),
      enumerateFolder: ref.watch(mediaEnumeratorProvider),
      contentHasher: ref.watch(contentHasherProvider),
      perceptualHasher: ref.watch(perceptualHasherProvider),
    );
    ref.onDispose(controller.dispose);
    return controller;
  },
  dependencies: [
    itemsRepositoryProvider,
    folderPickerProvider,
    mediaEnumeratorProvider,
    contentHasherProvider,
    perceptualHasherProvider,
  ],
);
