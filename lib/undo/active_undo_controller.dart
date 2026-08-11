import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/undo/undo_controller.dart';

/// LIFO of screen undo hosts (D12). Nested routes (Settings, Review, Person
/// detail) push on top of a tab host (Faces); popping restores the prior host.
class ActiveUndoHostStack extends Notifier<UndoController?> {
  final List<UndoController> _hosts = [];
  var _publishScheduled = false;

  @override
  UndoController? build() => _hosts.isEmpty ? null : _hosts.last;

  void push(UndoController controller) {
    _hosts.remove(controller);
    _hosts.add(controller);
    _publish();
  }

  void remove(UndoController controller) {
    if (!_hosts.contains(controller)) return;
    _hosts.remove(controller);
    _publish();
  }

  /// Publish [state] now when safe; otherwise after the current frame.
  /// Hosts call [push]/[remove] from [State.didUpdateWidget] while the tree
  /// is still rebuilding (e.g. Faces tab `active` flip), and Riverpod forbids
  /// notifying listeners mid-build.
  void _publish() {
    final next = _hosts.isEmpty ? null : _hosts.last;
    if (identical(state, next)) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      state = next;
      return;
    }
    if (_publishScheduled) return;
    _publishScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _publishScheduled = false;
      final latest = _hosts.isEmpty ? null : _hosts.last;
      if (!identical(state, latest)) {
        state = latest;
      }
    });
  }
}

final activeScreenUndoControllerProvider =
    NotifierProvider<ActiveUndoHostStack, UndoController?>(
  ActiveUndoHostStack.new,
);
