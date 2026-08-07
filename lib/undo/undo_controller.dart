import 'package:flutter/foundation.dart';
import 'package:tagkin_desktop/undo/undoable_action.dart';

/// Per-screen LIFO undo/redo stack (D12).
///
/// One instance per screen (page or tab). Not a singleton — never share across
/// screens. Max depth silently drops the oldest undoable action.
class UndoController extends ChangeNotifier {
  UndoController({this.maxDepth = 50});

  final int maxDepth;

  final List<UndoableAction> _undo = [];
  final List<UndoableAction> _redo = [];
  bool _busy = false;
  Object? lastError;

  bool get canUndo => _undo.isNotEmpty && !_busy;
  bool get canRedo => _redo.isNotEmpty && !_busy;
  bool get isBusy => _busy;

  /// Current undo-stack depth (subtle edit count).
  int get undoDepth => _undo.length;

  int get redoDepth => _redo.length;

  /// Push a completed forward gesture. Clears the redo stack.
  void push(UndoableAction action) {
    _undo.add(action);
    while (_undo.length > maxDepth) {
      _undo.removeAt(0);
    }
    _redo.clear();
    lastError = null;
    notifyListeners();
  }

  /// Clear both stacks (e.g. Settings Save/Discard).
  void clear() {
    _undo.clear();
    _redo.clear();
    lastError = null;
    notifyListeners();
  }

  Future<void> undo() async {
    if (!canUndo) return;
    final action = _undo.removeLast();
    _busy = true;
    lastError = null;
    notifyListeners();
    try {
      await action.undo();
      _redo.add(action);
    } catch (e) {
      // Keep the action undoable so the user can retry.
      _undo.add(action);
      lastError = e;
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> redo() async {
    if (!canRedo) return;
    final action = _redo.removeLast();
    _busy = true;
    lastError = null;
    notifyListeners();
    try {
      await action.redo();
      _undo.add(action);
      while (_undo.length > maxDepth) {
        _undo.removeAt(0);
      }
    } catch (e) {
      _redo.add(action);
      lastError = e;
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
