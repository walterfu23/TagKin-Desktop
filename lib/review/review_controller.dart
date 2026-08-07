import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/comments_repository.dart';
import 'package:tagkin_desktop/api/corrections_repository.dart';
import 'package:tagkin_desktop/api/items_repository.dart';
import 'package:tagkin_desktop/app_shell.dart'
    show
        commentsRepositoryProvider,
        correctionsRepositoryProvider,
        itemsRepositoryProvider;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';
import 'package:tagkin_desktop/undo/undo_controller.dart';
import 'package:tagkin_desktop/undo/undoable_action.dart';

/// Lifecycle of a per-item knowledge review load (D8) + corrections (D10).
enum ReviewPhase { idle, loading, ready, busy, error }

/// Loads approved [ItemKnowledge], resolves local media, and owns D10
/// corrections / comments with optimistic UI reconciled via `/knowledge`.
///
/// Never sends `ownerUserId` (R10). Never uploads media bytes (R1/R5/R7).
/// Person confirm/correct controls live in D9.
///
/// Optional [undoStack] records successful mutations for per-screen LIFO
/// undo/redo (D12). Stack undo/redo calls do not re-push.
class ReviewController extends ChangeNotifier {
  ReviewController({
    required this.itemId,
    required this.itemsRepository,
    required this.correctionsRepository,
    required this.commentsRepository,
    this.resolveMedia = resolveLocalMedia,
    this.undoStack,
  });

  final String itemId;
  final ItemsRepository itemsRepository;
  final CorrectionsRepository correctionsRepository;
  final CommentsRepository commentsRepository;
  final Future<LocalMediaResolution> Function(Item item) resolveMedia;

  /// Per-screen undo/redo stack (owned by the Review page).
  UndoController? undoStack;

  ReviewPhase phase = ReviewPhase.idle;
  ItemKnowledge? knowledge;
  LocalMediaResolution? media;
  List<Comment> comments = const [];
  Object? error;
  Object? mutationError;

  bool get isBusy => phase == ReviewPhase.busy;
  bool get canMutate => knowledge != null && !isBusy;

  /// Fetches `/knowledge` then resolves local media for the returned item.
  Future<void> load() async {
    phase = ReviewPhase.loading;
    error = null;
    mutationError = null;
    notifyListeners();

    try {
      final result = await itemsRepository.getKnowledge(itemId);
      if (_disposed) return;
      knowledge = result;
      try {
        media = await resolveMedia(result.item);
      } catch (e) {
        // Knowledge still renders when local media cannot be opened (sandbox).
        media = LocalMediaResolution(
          status: LocalMediaStatus.accessDenied,
          path: localPathFromSourceRef(result.item.sourceRef),
        );
      }
      if (_disposed) return;
      try {
        comments = await commentsRepository.listItemComments(itemId);
      } catch (_) {
        // Comments are additive; knowledge still renders if list fails.
        comments = const [];
      }
      if (_disposed) return;
      phase = ReviewPhase.ready;
      notifyListeners();
    } catch (e) {
      if (_disposed) return;
      error = e;
      knowledge = null;
      media = null;
      comments = const [];
      phase = ReviewPhase.error;
      notifyListeners();
    }
  }

  /// Human-add a tag; optimistic insert then reconcile against `/knowledge`.
  Future<void> addTag({
    required String dimension,
    required String value,
    String? keyPeriodId,
  }) async {
    if (!canMutate) return;
    final snapshot = knowledge!;
    final optimistic = Tag(
      id: 'optimistic_${DateTime.now().microsecondsSinceEpoch}',
      itemId: keyPeriodId == null ? itemId : null,
      keyPeriodId: keyPeriodId,
      dimension: dimension,
      value: value,
      source: KnowledgeSource.human,
      status: TagStatus.active,
      schemaVersion: 1,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    knowledge = _withTagAdded(snapshot, optimistic, keyPeriodId);
    phase = ReviewPhase.busy;
    mutationError = null;
    notifyListeners();

    try {
      final result = await correctionsRepository.addTag(
        itemId,
        AddTag(dimension: dimension, value: value, keyPeriodId: keyPeriodId),
      );
      if (_disposed) return;
      await _reconcileKnowledge();
      _recordCorrectionUndo('Add tag', result.correction.id);
    } catch (e) {
      if (_disposed) return;
      knowledge = snapshot;
      mutationError = e;
      phase = ReviewPhase.ready;
      notifyListeners();
    }
  }

  /// Non-destructive edit: optimistic value swap then reconcile.
  Future<void> editTag(String tagId, String value) async {
    if (!canMutate) return;
    final snapshot = knowledge!;
    knowledge = _withTagValue(snapshot, tagId, value);
    phase = ReviewPhase.busy;
    mutationError = null;
    notifyListeners();

    try {
      final result =
          await correctionsRepository.editTag(tagId, EditTag(value: value));
      if (_disposed) return;
      await _reconcileKnowledge();
      _recordCorrectionUndo('Edit tag', result.correction.id);
    } catch (e) {
      if (_disposed) return;
      knowledge = snapshot;
      mutationError = e;
      phase = ReviewPhase.ready;
      notifyListeners();
    }
  }

  /// Soft-remove a tag; optimistic drop then reconcile.
  Future<void> removeTag(String tagId) async {
    if (!canMutate) return;
    final snapshot = knowledge!;
    knowledge = _withoutTag(snapshot, tagId);
    phase = ReviewPhase.busy;
    mutationError = null;
    notifyListeners();

    try {
      final result = await correctionsRepository.removeTag(tagId);
      if (_disposed) return;
      await _reconcileKnowledge();
      _recordCorrectionUndo('Remove tag', result.correction.id);
    } catch (e) {
      if (_disposed) return;
      knowledge = snapshot;
      mutationError = e;
      phase = ReviewPhase.ready;
      notifyListeners();
    }
  }

  /// Durable exclude who face from this photo (survives re-analyze).
  Future<void> excludeWhoFace(String tagId) async {
    if (!canMutate) return;
    final snapshot = knowledge!;
    knowledge = _withoutTag(snapshot, tagId);
    phase = ReviewPhase.busy;
    mutationError = null;
    notifyListeners();

    try {
      final exclusion =
          await itemsRepository.createWhoExclusion(itemId, tagId);
      if (_disposed) return;
      await _reconcileKnowledge();
      _recordWhoExcludeUndo(
        tagId: tagId,
        exclusionId: exclusion.exclusion.id,
      );
    } catch (e) {
      if (_disposed) return;
      knowledge = snapshot;
      mutationError = e;
      phase = ReviewPhase.ready;
      notifyListeners();
    }
  }

  /// Undo a who-face exclusion (R6). Re-analyze may recreate the box later.
  Future<void> undoWhoExclusion(String exclusionId) async {
    if (!canMutate) return;
    final snapshot = knowledge!;
    knowledge = ItemKnowledge(
      item: snapshot.item,
      tags: snapshot.tags,
      keyPeriods: snapshot.keyPeriods,
      appearances: snapshot.appearances,
      corrections: snapshot.corrections,
      whoExclusions: snapshot.whoExclusions
          .where((e) => e.id != exclusionId)
          .toList(),
    );
    phase = ReviewPhase.busy;
    mutationError = null;
    notifyListeners();

    try {
      await itemsRepository.undoWhoExclusion(itemId, exclusionId);
      if (_disposed) return;
      await _reconcileKnowledge();
    } catch (e) {
      if (_disposed) return;
      knowledge = snapshot;
      mutationError = e;
      phase = ReviewPhase.ready;
      notifyListeners();
    }
  }

  /// Correct [Item.capturedAt]; optimistic update then reconcile.
  Future<void> correctCapturedAt(String? capturedAt) async {
    if (!canMutate) return;
    final snapshot = knowledge!;
    final item = snapshot.item;
    knowledge = ItemKnowledge(
      item: Item(
        id: item.id,
        type: item.type,
        sourceType: item.sourceType,
        sourceRef: item.sourceRef,
        analysisRef: item.analysisRef,
        analysisRefState: item.analysisRefState,
        contentHash: item.contentHash,
        perceptualHash: item.perceptualHash,
        dedupOfItemId: item.dedupOfItemId,
        capturedAt: capturedAt,
        processingStatus: item.processingStatus,
        schemaVersion: item.schemaVersion,
        createdAt: item.createdAt,
      ),
      tags: snapshot.tags,
      keyPeriods: snapshot.keyPeriods,
      appearances: snapshot.appearances,
      corrections: snapshot.corrections,
      whoExclusions: snapshot.whoExclusions,
    );
    phase = ReviewPhase.busy;
    mutationError = null;
    notifyListeners();

    try {
      final result = await correctionsRepository.correctCapturedAt(
        itemId,
        CorrectCapturedAt(capturedAt: capturedAt),
      );
      if (_disposed) return;
      await _reconcileKnowledge();
      _recordCorrectionUndo('Edit capturedAt', result.correction.id);
    } catch (e) {
      if (_disposed) return;
      knowledge = snapshot;
      mutationError = e;
      phase = ReviewPhase.ready;
      notifyListeners();
    }
  }

  /// Correct key-period bounds; optimistic update then reconcile.
  Future<void> correctKeyPeriodBounds({
    required String keyPeriodId,
    required int startMs,
    required int endMs,
  }) async {
    if (!canMutate) return;
    final snapshot = knowledge!;
    knowledge = ItemKnowledge(
      item: snapshot.item,
      tags: snapshot.tags,
      keyPeriods: [
        for (final kp in snapshot.keyPeriods)
          if (kp.id == keyPeriodId)
            KeyPeriodKnowledge(
              id: kp.id,
              itemId: kp.itemId,
              startMs: startMs,
              endMs: endMs,
              tags: kp.tags,
            )
          else
            kp,
      ],
      appearances: snapshot.appearances,
      corrections: snapshot.corrections,
      whoExclusions: snapshot.whoExclusions,
    );
    phase = ReviewPhase.busy;
    mutationError = null;
    notifyListeners();

    try {
      final result = await correctionsRepository.correctKeyPeriodBounds(
        keyPeriodId,
        CorrectKeyPeriodBounds(startMs: startMs, endMs: endMs),
      );
      if (_disposed) return;
      await _reconcileKnowledge();
      _recordCorrectionUndo('Edit key period', result.correction.id);
    } catch (e) {
      if (_disposed) return;
      knowledge = snapshot;
      mutationError = e;
      phase = ReviewPhase.ready;
      notifyListeners();
    }
  }

  /// Undo a prior correction; busy then reconcile via `/knowledge`.
  /// Does not push onto [undoStack] (stack undo already owns the action).
  Future<void> undoCorrection(String correctionId) async {
    if (!canMutate) return;
    phase = ReviewPhase.busy;
    mutationError = null;
    notifyListeners();

    try {
      await correctionsRepository.undoCorrection(correctionId);
      if (_disposed) return;
      await _reconcileKnowledge();
    } catch (e) {
      if (_disposed) return;
      mutationError = e;
      phase = ReviewPhase.ready;
      notifyListeners();
    }
  }

  /// Redo a prior correction after undo (S8 / D12).
  Future<void> redoCorrection(String correctionId) async {
    if (!canMutate) return;
    phase = ReviewPhase.busy;
    mutationError = null;
    notifyListeners();

    try {
      await correctionsRepository.redoCorrection(correctionId);
      if (_disposed) return;
      await _reconcileKnowledge();
    } catch (e) {
      if (_disposed) return;
      mutationError = e;
      phase = ReviewPhase.ready;
      notifyListeners();
    }
  }

  void _recordCorrectionUndo(String label, String correctionId) {
    final stack = undoStack;
    if (stack == null || !_recordUndo) return;
    stack.push(
      CallbackUndoableAction(
        label: label,
        onUndo: () => _withoutRecording(() => undoCorrection(correctionId)),
        onRedo: () => _withoutRecording(() => redoCorrection(correctionId)),
      ),
    );
  }

  void _recordWhoExcludeUndo({
    required String tagId,
    required String exclusionId,
  }) {
    final stack = undoStack;
    if (stack == null || !_recordUndo) return;
    stack.push(
      CallbackUndoableAction(
        label: 'Exclude face',
        onUndo: () => _withoutRecording(() => undoWhoExclusion(exclusionId)),
        onRedo: () => _withoutRecording(() async {
          if (!canMutate) return;
          phase = ReviewPhase.busy;
          mutationError = null;
          notifyListeners();
          try {
            await itemsRepository.createWhoExclusion(itemId, tagId);
            if (_disposed) return;
            await _reconcileKnowledge();
          } catch (e) {
            if (_disposed) return;
            mutationError = e;
            phase = ReviewPhase.ready;
            notifyListeners();
            rethrow;
          }
        }),
      ),
    );
  }

  void _recordCommentAdd(String commentId, String body) {
    final stack = undoStack;
    if (stack == null || !_recordUndo) return;
    stack.push(
      CallbackUndoableAction(
        label: 'Add comment',
        onUndo: () => _withoutRecording(() => deleteComment(commentId)),
        onRedo: () => _withoutRecording(() => addItemComment(body)),
      ),
    );
  }

  void _recordCommentEdit(String commentId, String prior, String next) {
    final stack = undoStack;
    if (stack == null || !_recordUndo) return;
    stack.push(
      CallbackUndoableAction(
        label: 'Edit comment',
        onUndo: () => _withoutRecording(() => editComment(commentId, prior)),
        onRedo: () => _withoutRecording(() => editComment(commentId, next)),
      ),
    );
  }

  /// Create an item-level comment; optimistic insert, splice server result.
  Future<void> addItemComment(String body) async {
    if (!canMutate) return;
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;
    final snapshot = List<Comment>.from(comments);
    final optimistic = Comment(
      id: 'optimistic_${DateTime.now().microsecondsSinceEpoch}',
      itemId: itemId,
      authorUserId: 'pending',
      body: trimmed,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    comments = [...comments, optimistic];
    phase = ReviewPhase.busy;
    mutationError = null;
    notifyListeners();

    try {
      final created = await commentsRepository.createItemComment(
        itemId,
        CreateComment(body: trimmed),
      );
      if (_disposed) return;
      comments = [
        for (final c in comments)
          if (c.id == optimistic.id) created else c,
      ];
      phase = ReviewPhase.ready;
      notifyListeners();
      _recordCommentAdd(created.id, trimmed);
    } catch (e) {
      if (_disposed) return;
      comments = snapshot;
      mutationError = e;
      phase = ReviewPhase.ready;
      notifyListeners();
    }
  }

  /// Create a key-period comment; optimistic insert, splice server result.
  Future<void> addKeyPeriodComment(String keyPeriodId, String body) async {
    if (!canMutate) return;
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;
    final snapshot = List<Comment>.from(comments);
    final optimistic = Comment(
      id: 'optimistic_${DateTime.now().microsecondsSinceEpoch}',
      itemId: itemId,
      keyPeriodId: keyPeriodId,
      authorUserId: 'pending',
      body: trimmed,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    comments = [...comments, optimistic];
    phase = ReviewPhase.busy;
    mutationError = null;
    notifyListeners();

    try {
      final created = await commentsRepository.createKeyPeriodComment(
        keyPeriodId,
        CreateComment(body: trimmed),
      );
      if (_disposed) return;
      comments = [
        for (final c in comments)
          if (c.id == optimistic.id) created else c,
      ];
      phase = ReviewPhase.ready;
      notifyListeners();
      _recordCommentAdd(created.id, trimmed);
    } catch (e) {
      if (_disposed) return;
      comments = snapshot;
      mutationError = e;
      phase = ReviewPhase.ready;
      notifyListeners();
    }
  }

  /// Edit comment body; optimistic then splice server result.
  Future<void> editComment(String commentId, String body) async {
    if (!canMutate) return;
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;
    final prior = comments.where((c) => c.id == commentId).firstOrNull?.body;
    final snapshot = List<Comment>.from(comments);
    comments = [
      for (final c in comments)
        if (c.id == commentId)
          Comment(
            id: c.id,
            itemId: c.itemId,
            keyPeriodId: c.keyPeriodId,
            authorUserId: c.authorUserId,
            body: trimmed,
            deletedAt: c.deletedAt,
            createdAt: c.createdAt,
            updatedAt: DateTime.now().toUtc().toIso8601String(),
          )
        else
          c,
    ];
    phase = ReviewPhase.busy;
    mutationError = null;
    notifyListeners();

    try {
      final updated = await commentsRepository.editComment(
        commentId,
        EditComment(body: trimmed),
      );
      if (_disposed) return;
      comments = [
        for (final c in comments)
          if (c.id == commentId) updated else c,
      ];
      phase = ReviewPhase.ready;
      notifyListeners();
      if (prior != null) {
        _recordCommentEdit(commentId, prior, trimmed);
      }
    } catch (e) {
      if (_disposed) return;
      comments = snapshot;
      mutationError = e;
      phase = ReviewPhase.ready;
      notifyListeners();
    }
  }

  /// Soft-delete a comment; optimistic drop then confirm via server.
  Future<void> deleteComment(String commentId) async {
    if (!canMutate) return;
    final snapshot = List<Comment>.from(comments);
    comments = comments.where((c) => c.id != commentId).toList();
    phase = ReviewPhase.busy;
    mutationError = null;
    notifyListeners();

    try {
      await commentsRepository.deleteComment(commentId);
      if (_disposed) return;
      phase = ReviewPhase.ready;
      notifyListeners();
    } catch (e) {
      if (_disposed) return;
      comments = snapshot;
      mutationError = e;
      phase = ReviewPhase.ready;
      notifyListeners();
    }
  }

  /// Active item-level comments (no keyPeriodId).
  List<Comment> get itemComments =>
      comments.where((c) => c.keyPeriodId == null && c.deletedAt == null).toList();

  /// Active comments for a key period.
  List<Comment> commentsForKeyPeriod(String keyPeriodId) => comments
      .where((c) => c.keyPeriodId == keyPeriodId && c.deletedAt == null)
      .toList();

  Future<void> _reconcileKnowledge() async {
    final result = await itemsRepository.getKnowledge(itemId);
    if (_disposed) return;
    knowledge = result;
    // Keep media resolution; only refresh if item identity changed.
    media ??= await resolveMedia(result.item);
    phase = ReviewPhase.ready;
    notifyListeners();
  }

  static ItemKnowledge _withTagAdded(
    ItemKnowledge base,
    Tag tag,
    String? keyPeriodId,
  ) {
    if (keyPeriodId == null) {
      return ItemKnowledge(
        item: base.item,
        tags: [...base.tags, tag],
        keyPeriods: base.keyPeriods,
        appearances: base.appearances,
        corrections: base.corrections,
        whoExclusions: base.whoExclusions,
      );
    }
    return ItemKnowledge(
      item: base.item,
      tags: base.tags,
      keyPeriods: [
        for (final kp in base.keyPeriods)
          if (kp.id == keyPeriodId)
            KeyPeriodKnowledge(
              id: kp.id,
              itemId: kp.itemId,
              startMs: kp.startMs,
              endMs: kp.endMs,
              tags: [...kp.tags, tag],
            )
          else
            kp,
      ],
      appearances: base.appearances,
      corrections: base.corrections,
      whoExclusions: base.whoExclusions,
    );
  }

  static ItemKnowledge _withTagValue(
    ItemKnowledge base,
    String tagId,
    String value,
  ) {
    Tag mapTag(Tag t) => t.id == tagId
        ? Tag(
            id: t.id,
            itemId: t.itemId,
            keyPeriodId: t.keyPeriodId,
            dimension: t.dimension,
            value: value,
            source: KnowledgeSource.human,
            status: t.status,
            correctedFromTagId: t.correctedFromTagId,
            confidence: t.confidence,
            provider: t.provider,
            modelId: t.modelId,
            schemaVersion: t.schemaVersion,
            createdAt: t.createdAt,
          )
        : t;
    return ItemKnowledge(
      item: base.item,
      tags: base.tags.map(mapTag).toList(),
      keyPeriods: [
        for (final kp in base.keyPeriods)
          KeyPeriodKnowledge(
            id: kp.id,
            itemId: kp.itemId,
            startMs: kp.startMs,
            endMs: kp.endMs,
            tags: kp.tags.map(mapTag).toList(),
          ),
      ],
      appearances: base.appearances,
      corrections: base.corrections,
      whoExclusions: base.whoExclusions,
    );
  }

  static ItemKnowledge _withoutTag(ItemKnowledge base, String tagId) {
    return ItemKnowledge(
      item: base.item,
      tags: base.tags.where((t) => t.id != tagId).toList(),
      keyPeriods: [
        for (final kp in base.keyPeriods)
          KeyPeriodKnowledge(
            id: kp.id,
            itemId: kp.itemId,
            startMs: kp.startMs,
            endMs: kp.endMs,
            tags: kp.tags.where((t) => t.id != tagId).toList(),
          ),
      ],
      appearances: base.appearances,
      corrections: base.corrections,
      whoExclusions: base.whoExclusions,
    );
  }

  bool _disposed = false;

  /// When false, successful mutations do not push onto [undoStack]
  /// (used while executing a stack undo/redo).
  bool _recordUndo = true;

  Future<void> _withoutRecording(Future<void> Function() run) async {
    final prev = _recordUndo;
    _recordUndo = false;
    try {
      await run();
    } finally {
      _recordUndo = prev;
    }
  }

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
      correctionsRepository: ref.watch(correctionsRepositoryProvider),
      commentsRepository: ref.watch(commentsRepositoryProvider),
    );
    ref.onDispose(controller.dispose);
    return controller;
  },
  dependencies: [
    itemsRepositoryProvider,
    correctionsRepositoryProvider,
    commentsRepositoryProvider,
  ],
);
