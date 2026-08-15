import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/undo/active_undo_controller.dart';
import 'package:tagkin_desktop/undo/undo_controller.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

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

const Map<ShortcutActivator, Intent> kScreenUndoShortcuts = {
  SingleActivator(LogicalKeyboardKey.keyZ, meta: true): ScreenUndoIntent(),
  SingleActivator(LogicalKeyboardKey.keyZ, control: true): ScreenUndoIntent(),
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
  // macOS Cmd+Y and Windows/Linux Ctrl+Y
  SingleActivator(LogicalKeyboardKey.keyY, meta: true): ScreenRedoIntent(),
  SingleActivator(LogicalKeyboardKey.keyY, control: true): ScreenRedoIntent(),
};

/// App-level Cmd/Ctrl+Z host — must sit **above** [SelectableScope] so
/// shortcuts still fire when primary focus is on the app-wide SelectionArea.
///
/// Dispatches to [activeScreenUndoControllerProvider]. Consumes the shortcut
/// (no macOS beep) even when the stack is empty; does not steal EditableText
/// undo. Does not install its own autofocus [Focus].
class ActiveUndoShortcuts extends ConsumerWidget {
  const ActiveUndoShortcuts({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(activeScreenUndoControllerProvider);
    return Shortcuts(
      shortcuts: kScreenUndoShortcuts,
      child: Actions(
        actions: {
          ScreenUndoIntent: CallbackAction<ScreenUndoIntent>(
            onInvoke: (_) {
              if (focusIsInEditableText(context)) return null;
              final c = ref.read(activeScreenUndoControllerProvider);
              if (c == null || !c.canUndo) return null;
              final messenger = ScaffoldMessenger.maybeOf(context);
              c.undo().catchError((Object e) {
                messenger?.showSnackBar(SnackBar(content: Text('$e')));
              });
              return null;
            },
          ),
          ScreenRedoIntent: CallbackAction<ScreenRedoIntent>(
            onInvoke: (_) {
              if (focusIsInEditableText(context)) return null;
              final c = ref.read(activeScreenUndoControllerProvider);
              if (c == null || !c.canRedo) return null;
              final messenger = ScaffoldMessenger.maybeOf(context);
              c.redo().catchError((Object e) {
                messenger?.showSnackBar(SnackBar(content: Text('$e')));
              });
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }
}

/// Registers [controller] as the active D12 undo host while [active] is true.
class ActiveUndoHost extends ConsumerStatefulWidget {
  const ActiveUndoHost({
    super.key,
    required this.controller,
    required this.child,
    this.active = true,
  });

  final UndoController controller;
  final Widget child;
  final bool active;

  @override
  ConsumerState<ActiveUndoHost> createState() => _ActiveUndoHostState();
}

class _ActiveUndoHostState extends ConsumerState<ActiveUndoHost> {
  ProviderContainer? _container;

  ActiveUndoHostStack get _stack {
    final container = _container ?? ProviderScope.containerOf(context);
    return container.read(activeScreenUndoControllerProvider.notifier);
  }

  void _push(UndoController controller) {
    _container ??= ProviderScope.containerOf(context);
    _stack.push(controller);
  }

  void _remove(UndoController controller) {
    final container = _container;
    if (container == null) return;
    try {
      container
          .read(activeScreenUndoControllerProvider.notifier)
          .remove(controller);
    } on StateError {
      // ProviderContainer already disposed (test teardown / app shutdown).
    }
  }

  void _sync() {
    if (widget.active) {
      _push(widget.controller);
    } else {
      _remove(widget.controller);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _container = ProviderScope.containerOf(context);
      _sync();
    });
  }

  @override
  void didUpdateWidget(covariant ActiveUndoHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active ||
        !identical(oldWidget.controller, widget.controller)) {
      if (oldWidget.active) {
        _remove(oldWidget.controller);
      }
      _sync();
    }
  }

  @override
  void dispose() {
    _remove(widget.controller);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Local-screen Cmd/Ctrl+Z wrapper (routes pushed under Overlay).
///
/// Prefer pairing with [ActiveUndoHost] so the app-level [ActiveUndoShortcuts]
/// also reaches this stack when SelectionArea holds focus. Does not steal
/// shortcuts when focus is inside an [EditableText].
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
          shortcuts: kScreenUndoShortcuts,
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
        final base = DefaultTextStyle.of(context).style;
        return Text(
          '$depth',
          key: const Key('undo-depth'),
          style: base.copyWith(
            color: (base.color ??
                    Theme.of(context).colorScheme.onSurfaceVariant)
                .withValues(alpha: 0.65),
          ),
        );
      },
    );
  }
}

/// Pushed-route chrome: Cmd/Ctrl+Z sits above [SelectableScope]
/// (same order as app home).
class UndoSelectableRoute extends StatelessWidget {
  const UndoSelectableRoute({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ActiveUndoShortcuts(
      child: SelectableScope(child: child),
    );
  }
}
