import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/items_repository.dart';
import 'package:tagkin_desktop/app_shell.dart' show itemsRepositoryProvider;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';

/// Lifecycle of a per-item knowledge review load (D8).
enum ReviewPhase { idle, loading, ready, error }

/// Loads approved [ItemKnowledge] and resolves authorized local media.
///
/// Never sends `ownerUserId` (R10). Never uploads media bytes (R1/R5/R7).
/// Displays provenance only — corrections live in D10. Person confirm/correct
/// controls live in D9 (linked from appearance rows + Find person matches).
class ReviewController extends ChangeNotifier {
  ReviewController({
    required this.itemId,
    required this.itemsRepository,
    this.resolveMedia = resolveLocalMedia,
  });

  final String itemId;
  final ItemsRepository itemsRepository;
  final Future<LocalMediaResolution> Function(Item item) resolveMedia;

  ReviewPhase phase = ReviewPhase.idle;
  ItemKnowledge? knowledge;
  LocalMediaResolution? media;
  Object? error;

  /// Fetches `/knowledge` then resolves local media for the returned item.
  Future<void> load() async {
    phase = ReviewPhase.loading;
    error = null;
    notifyListeners();

    try {
      final result = await itemsRepository.getKnowledge(itemId);
      if (_disposed) return;
      knowledge = result;
      media = await resolveMedia(result.item);
      if (_disposed) return;
      phase = ReviewPhase.ready;
      notifyListeners();
    } catch (e) {
      if (_disposed) return;
      error = e;
      knowledge = null;
      media = null;
      phase = ReviewPhase.error;
      notifyListeners();
    }
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final reviewControllerProvider =
    Provider.autoDispose.family<ReviewController, String>(
  (ref, itemId) {
    final controller = ReviewController(
      itemId: itemId,
      itemsRepository: ref.watch(itemsRepositoryProvider),
    );
    ref.onDispose(controller.dispose);
    return controller;
  },
  dependencies: [itemsRepositoryProvider],
);
