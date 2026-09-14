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
  BuildContext context, {
  Key dialogKey = const Key('collection-dirty-dialog'),
  String title = 'Unsaved collection',
  String body = 'This collection has unsaved changes. Save before continuing?',
  Key cancelKey = const Key('collection-dirty-cancel'),
  Key discardKey = const Key('collection-dirty-discard'),
  Key saveKey = const Key('collection-dirty-save'),
}) {
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
              child: DirtyLeaveAlertDialog(
                onChoice: finish,
                dialogKey: dialogKey,
                title: title,
                body: body,
                cancelKey: cancelKey,
                discardKey: discardKey,
                saveKey: saveKey,
              ),
            ),
          ),
        ),
      ],
    ),
  );
  overlay.insert(entry);
  return completer.future;
}

Future<DirtyPromptChoice> showViewDirtyLeaveOverlayPrompt(
  BuildContext context,
) {
  return showDirtyLeaveOverlayPrompt(
    context,
    dialogKey: const Key('view-dirty-dialog'),
    title: 'Unsaved view',
    body: 'This view has unsaved changes. Save before leaving?',
    cancelKey: const Key('view-dirty-cancel'),
    discardKey: const Key('view-dirty-discard'),
    saveKey: const Key('view-dirty-save'),
  );
}

/// Shared unsaved-collection dialog chrome (keys match prior showDialog).
class DirtyLeaveAlertDialog extends StatelessWidget {
  const DirtyLeaveAlertDialog({
    super.key,
    required this.onChoice,
    this.dialogKey = const Key('collection-dirty-dialog'),
    this.title = 'Unsaved collection',
    this.body = 'This collection has unsaved changes. Save before continuing?',
    this.cancelKey = const Key('collection-dirty-cancel'),
    this.discardKey = const Key('collection-dirty-discard'),
    this.saveKey = const Key('collection-dirty-save'),
  });

  final ValueChanged<DirtyPromptChoice> onChoice;
  final Key dialogKey;
  final String title;
  final String body;
  final Key cancelKey;
  final Key discardKey;
  final Key saveKey;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: dialogKey,
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          key: cancelKey,
          onPressed: () => onChoice(DirtyPromptChoice.cancel),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: discardKey,
          onPressed: () => onChoice(DirtyPromptChoice.discard),
          child: const Text('Discard'),
        ),
        FilledButton(
          key: saveKey,
          onPressed: () => onChoice(DirtyPromptChoice.save),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
