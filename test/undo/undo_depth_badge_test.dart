import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/undo/undo_controller.dart';
import 'package:tagkin_desktop/undo/undo_shortcuts.dart';
import 'package:tagkin_desktop/undo/undoable_action.dart';

void main() {
  testWidgets('undo depth badge is smaller than the AppBar title', (
    tester,
  ) async {
    final undo = UndoController();
    undo.push(
      CallbackUndoableAction(
        label: 'step',
        onUndo: () async {},
        onRedo: () async {},
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                const Text('Faces'),
                const SizedBox(width: 8),
                UndoDepthBadge(controller: undo),
              ],
            ),
          ),
        ),
      ),
    );

    final badge = tester.widget<Text>(find.byKey(const Key('undo-depth')));
    final titleSize =
        Theme.of(tester.element(find.text('Faces')))
            .textTheme
            .titleLarge
            ?.fontSize ??
        22;
    expect(badge.style!.fontSize!, lessThan(titleSize));
  });
}
