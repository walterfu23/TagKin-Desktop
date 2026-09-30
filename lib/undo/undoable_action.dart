/// One reversible gesture on a screen's LIFO undo/redo stack (D12).
abstract class UndoableAction {
  const UndoableAction({required this.label, this.draft = false});

  /// Short label for diagnostics / optional UI.
  final String label;

  /// Item-detail drafts (assign / exclude before Save). Save and Discard
  /// drop these and keep committed entries such as Hide item.
  final bool draft;

  Future<void> undo();
  Future<void> redo();
}

/// Simple callback-backed action (API or local draft).
class CallbackUndoableAction extends UndoableAction {
  CallbackUndoableAction({
    required super.label,
    super.draft,
    required this.onUndo,
    required this.onRedo,
  });

  final Future<void> Function() onUndo;
  final Future<void> Function() onRedo;

  @override
  Future<void> undo() => onUndo();

  @override
  Future<void> redo() => onRedo();
}
