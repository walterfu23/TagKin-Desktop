import 'package:flutter/material.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/persons/dirty_leave_prompt.dart';
import 'package:tagkin_desktop/shell/app_navigator.dart';

/// Asks for a collection name. Returns trimmed non-empty name, or null.
Future<String?> showCollectionNameDialog(
  BuildContext context, {
  String? initialName,
  String title = 'New collection',
  String confirmLabel = 'Create',
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _CollectionNameDialog(
      initialName: initialName ?? '',
      title: title,
      confirmLabel: confirmLabel,
    ),
  );
}

class _CollectionNameDialog extends StatefulWidget {
  const _CollectionNameDialog({
    required this.initialName,
    required this.title,
    required this.confirmLabel,
  });

  final String initialName;
  final String title;
  final String confirmLabel;

  @override
  State<_CollectionNameDialog> createState() => _CollectionNameDialogState();
}

class _CollectionNameDialogState extends State<_CollectionNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) return;
    Navigator.of(context).pop(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('collection-name-dialog'),
      title: Text(widget.title),
      content: TextField(
        key: const Key('collection-name-field'),
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Collection name',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          key: const Key('collection-name-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('collection-name-confirm'),
          onPressed: _save,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Save / Discard / Cancel when leaving a dirty collection.
///
/// Uses a root [OverlayEntry] (sibling of home, outside [SelectionArea]) so
/// Cancel does not leave Sign out / chrome taps dead.
Future<DirtyPromptChoice> showCollectionDirtyPrompt(BuildContext context) {
  final dialogContext = tagkinRootNavigatorKey.currentContext ?? context;
  return showDirtyLeaveOverlayPrompt(dialogContext);
}

/// Pick one saved collection from [collections]. Returns id or null.
Future<String?> showOpenCollectionDialog(
  BuildContext context, {
  required List<({String id, String name})> collections,
}) {
  if (collections.isEmpty) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('collection-open-empty-dialog'),
        title: const Text('Open collection'),
        content: const Text('No saved collections yet.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
  return showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      key: const Key('collection-open-dialog'),
      title: const Text('Open collection'),
      children: [
        for (final c in collections)
          SimpleDialogOption(
            key: Key('collection-open-option-${c.id}'),
            onPressed: () => Navigator.of(ctx).pop(c.id),
            child: Text(c.name),
          ),
      ],
    ),
  );
}

/// Confirm deleting the current collection.
Future<bool> showDeleteCollectionDialog(
  BuildContext context, {
  required String name,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('collection-delete-dialog'),
      title: const Text('Delete collection'),
      content: Text(
        'Delete "$name"? Folders and faces are not removed — '
        'only this saved set.',
      ),
      actions: [
        TextButton(
          key: const Key('collection-delete-cancel'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('collection-delete-confirm'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
