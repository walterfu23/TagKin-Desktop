import 'package:flutter/material.dart';

/// Asks the user to name a newly discovered / unnamed person (D9 / R6).
///
/// Returns trimmed non-empty name, or `null` when skipped/cancelled.
Future<String?> showPersonNameDialog(
  BuildContext context, {
  String? initialName,
  String title = 'Name this person',
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _PersonNameDialog(
      initialName: initialName ?? '',
      title: title,
    ),
  );
}

class _PersonNameDialog extends StatefulWidget {
  const _PersonNameDialog({
    required this.initialName,
    required this.title,
  });

  final String initialName;
  final String title;

  @override
  State<_PersonNameDialog> createState() => _PersonNameDialogState();
}

class _PersonNameDialogState extends State<_PersonNameDialog> {
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
      key: const Key('person-name-dialog'),
      title: Text(widget.title),
      content: TextField(
        key: const Key('person-name-field'),
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Person name',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          key: const Key('person-name-skip'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Skip'),
        ),
        FilledButton(
          key: const Key('person-name-save'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
