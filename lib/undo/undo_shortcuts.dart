import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tagkin_desktop/undo/undo_controller.dart';

/// Intent for screen-level Undo (D12).
class ScreenUndoIntent extends Intent {
  const ScreenUndoIntent();
}

/// Intent for screen-level Redo (D12).
class ScreenRedoIntent extends Intent {
  const ScreenRedoIntent();
}

bool focusIsInEditableText(BuildContext context) {
  final primary = FocusManager.instance.primaryFocus;
  if (primary == null) return false;
  final ctx = primary.context;
  if (ctx == null) return false;
  return ctx.widget is EditableText ||
      ctx.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// Wraps [child] with Cmd/Ctrl+Z / Cmd/Ctrl+Shift+Z bound to [controller].
///
/// Does not steal shortcuts when focus is inside an [EditableText].
class UndoShortcuts extends StatelessWidget {
  const UndoShortcuts({
    super.key,
    required this.controller,
    required this.child,
    this.onError,
  });

  final UndoController controller;
  final Widget child;
  final void Function(Object error)? onError;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
                ScreenUndoIntent(),
            SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                ScreenUndoIntent(),
            SingleActivator(
              LogicalKeyboardKey.keyZ,
              meta: true,
              shift: true,
            ): ScreenRedoIntent(),
            SingleActivator(
              LogicalKeyboardKey.keyZ,
              control: true,
              shift: true,
            ): ScreenRedoIntent(),
            SingleActivator(LogicalKeyboardKey.keyY, control: true):
                ScreenRedoIntent(),
          },
          child: Actions(
            actions: {
              ScreenUndoIntent: CallbackAction<ScreenUndoIntent>(
                onInvoke: (_) {
                  if (focusIsInEditableText(context)) return null;
                  if (!controller.canUndo) return null;
                  controller.undo().catchError((Object e) {
                    onError?.call(e);
                  });
                  return null;
                },
              ),
              ScreenRedoIntent: CallbackAction<ScreenRedoIntent>(
                onInvoke: (_) {
                  if (focusIsInEditableText(context)) return null;
                  if (!controller.canRedo) return null;
                  controller.redo().catchError((Object e) {
                    onError?.call(e);
                  });
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Subtle undo-depth indicator for a screen.
class UndoDepthBadge extends StatelessWidget {
  const UndoDepthBadge({
    super.key,
    required this.controller,
  });

  final UndoController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final depth = controller.undoDepth;
        if (depth == 0) return const SizedBox.shrink();
        final style = Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            );
        return Text(
          '$depth',
          key: const Key('undo-depth'),
          style: style,
        );
      },
    );
  }
}
