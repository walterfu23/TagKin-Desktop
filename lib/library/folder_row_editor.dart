import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/comments_repository.dart';
import 'package:tagkin_desktop/api/corrections_repository.dart';
import 'package:tagkin_desktop/api/items_repository.dart';
import 'package:tagkin_desktop/app_shell.dart'
    show
        commentsRepositoryProvider,
        correctionsRepositoryProvider,
        itemsRepositoryProvider;
import 'package:tagkin_desktop/library/folders_undo_recorder.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';
import 'package:tagkin_desktop/review/review_controller.dart';
import 'package:tagkin_desktop/undo/undo_controller.dart';

/// One [ReviewController] per item for Folders edit mode.
///
/// Not auto-dispose: undo closures keep calling the same controller after the
/// field loses focus. Media is not resolved; Folders already has the thumbnail.
class FolderRowEditor {
  FolderRowEditor({
    required this.itemsRepository,
    required this.correctionsRepository,
    required this.commentsRepository,
    required this.undoStack,
    required this.onCommitted,
  });

  final ItemsRepository itemsRepository;
  final CorrectionsRepository correctionsRepository;
  final CommentsRepository commentsRepository;
  final UndoController undoStack;
  final Future<void> Function(String itemId, ReviewController review) onCommitted;

  final Map<String, ReviewController> _byItem = {};

  ReviewController controllerFor(String itemId) {
    return _byItem.putIfAbsent(itemId, () {
      final controller = ReviewController(
        itemId: itemId,
        itemsRepository: itemsRepository,
        correctionsRepository: correctionsRepository,
        commentsRepository: commentsRepository,
        undoStack: undoStack,
        resolveMedia: (_) async => const LocalMediaResolution(
          status: LocalMediaStatus.unsupported,
        ),
      );
      controller.afterCommit = () => onCommitted(itemId, controller);
      return controller;
    });
  }

  /// Fresh `/knowledge` and comments so tag and comment ids are current.
  Future<ReviewController> open(String itemId) async {
    final controller = controllerFor(itemId);
    await controller.load();
    return controller;
  }

  void dispose() {
    for (final controller in _byItem.values) {
      controller.dispose();
    }
    _byItem.clear();
  }
}

final folderRowEditorProvider = Provider<FolderRowEditor>((ref) {
  final editor = FolderRowEditor(
    itemsRepository: ref.watch(itemsRepositoryProvider),
    correctionsRepository: ref.watch(correctionsRepositoryProvider),
    commentsRepository: ref.watch(commentsRepositoryProvider),
    undoStack: ref.watch(foldersUndoProvider).stack,
    onCommitted: (itemId, review) {
      final table = ref.read(libraryTableControllerProvider);
      table.adoptRowDetails(
        itemId,
        knowledge: review.knowledge,
        comments: review.comments,
      );
      return table.refreshRowCellsQuiet([itemId]);
    },
  );
  ref.onDispose(editor.dispose);
  return editor;
}, dependencies: [
  itemsRepositoryProvider,
  correctionsRepositoryProvider,
  commentsRepositoryProvider,
  foldersUndoProvider,
  libraryTableControllerProvider,
]);
