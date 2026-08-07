import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/undo/undo_controller.dart';
import 'package:tagkin_desktop/undo/undoable_action.dart';

void main() {
  group('UndoController', () {
    test('push / undo / redo LIFO order', () async {
      final log = <String>[];
      final c = UndoController();
      c.push(_act('a', log));
      c.push(_act('b', log));
      expect(c.undoDepth, 2);
      expect(c.canRedo, isFalse);

      await c.undo();
      expect(log, ['undo:b']);
      expect(c.undoDepth, 1);
      expect(c.canRedo, isTrue);

      await c.redo();
      expect(log, ['undo:b', 'redo:b']);
      expect(c.undoDepth, 2);
      expect(c.canRedo, isFalse);
    });

    test('new push after undo clears redo', () async {
      final log = <String>[];
      final c = UndoController();
      c.push(_act('a', log));
      c.push(_act('b', log));
      await c.undo();
      expect(c.canRedo, isTrue);
      c.push(_act('c', log));
      expect(c.canRedo, isFalse);
      expect(c.undoDepth, 2);
    });

    test('clear empties both stacks', () {
      final c = UndoController();
      c.push(_act('a', []));
      c.clear();
      expect(c.undoDepth, 0);
      expect(c.canRedo, isFalse);
    });

    test('maxDepth drops oldest', () {
      final c = UndoController(maxDepth: 2);
      c.push(_act('a', []));
      c.push(_act('b', []));
      c.push(_act('c', []));
      expect(c.undoDepth, 2);
    });

    test('failed undo keeps action on stack', () async {
      final c = UndoController();
      c.push(
        CallbackUndoableAction(
          label: 'fail',
          onUndo: () async => throw StateError('boom'),
          onRedo: () async {},
        ),
      );
      await expectLater(c.undo(), throwsA(isA<StateError>()));
      expect(c.undoDepth, 1);
      expect(c.canRedo, isFalse);
      expect(c.lastError, isA<StateError>());
    });
  });
}

UndoableAction _act(String id, List<String> log) {
  return CallbackUndoableAction(
    label: id,
    onUndo: () async => log.add('undo:$id'),
    onRedo: () async => log.add('redo:$id'),
  );
}
