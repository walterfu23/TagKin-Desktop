import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/undo/undo_controller.dart';

/// LIFO of screen undo hosts (D12). Nested routes (Settings, Review, Person
/// detail) push on top of a tab host (Faces); popping restores the prior host.
class ActiveUndoHostStack extends Notifier<UndoController?> {
  final List<UndoController> _hosts = [];

  @override
  UndoController? build() => _hosts.isEmpty ? null : _hosts.last;

  void push(UndoController controller) {
    _hosts.remove(controller);
    _hosts.add(controller);
    state = controller;
  }

  void remove(UndoController controller) {
    if (!_hosts.contains(controller)) return;
    _hosts.remove(controller);
    state = _hosts.isEmpty ? null : _hosts.last;
  }
}

final activeScreenUndoControllerProvider =
    NotifierProvider<ActiveUndoHostStack, UndoController?>(
  ActiveUndoHostStack.new,
);
