import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

/// OverlayEntry-based prompt (no ModalRoute, outside SelectionArea).
///
/// Inserted as a sibling of the home route in the root Overlay so gesture
/// recognizers from [SelectionArea] do not compete with Cancel / Save /
/// Discard after the prompt closes.
Future<DirtyPromptChoice> showDirtyLeaveOverlayPrompt(
  BuildContext context,
) {
  final completer = Completer<DirtyPromptChoice>();
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    return Future.value(DirtyPromptChoice.cancel);
  }
  late OverlayEntry entry;
  void finish(DirtyPromptChoice choice) {
    if (!completer.isCompleted) {
      entry.remove();
      completer.complete(choice);
    }
  }

  entry = OverlayEntry(
    builder: (ctx) => Stack(
      fit: StackFit.expand,
      children: [
        const ModalBarrier(dismissible: false, color: Color(0x80000000)),
        Center(
          child: Material(
            type: MaterialType.transparency,
            // Overlay content sits outside main.dart's app-wide
            // SelectableScope — wrap here so the dialog text stays
            // selectable too.
            child: SelectableScope(
              child: DirtyLeaveAlertDialog(onChoice: finish),
            ),
          ),
        ),
      ],
    ),
  );
  overlay.insert(entry);
  return completer.future;
}

/// Shared unsaved-collection dialog chrome (keys match prior showDialog).
class DirtyLeaveAlertDialog extends StatelessWidget {
  const DirtyLeaveAlertDialog({super.key, required this.onChoice});

  final ValueChanged<DirtyPromptChoice> onChoice;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('collection-dirty-dialog'),
      title: const Text('Unsaved collection'),
      content: const Text(
        'This collection has unsaved changes. Save before continuing?',
      ),
      actions: [
        TextButton(
          key: const Key('collection-dirty-cancel'),
          onPressed: () => onChoice(DirtyPromptChoice.cancel),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('collection-dirty-discard'),
          onPressed: () => onChoice(DirtyPromptChoice.discard),
          child: const Text('Discard'),
        ),
        FilledButton(
          key: const Key('collection-dirty-save'),
          onPressed: () => onChoice(DirtyPromptChoice.save),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
