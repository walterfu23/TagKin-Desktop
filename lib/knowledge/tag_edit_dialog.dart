import 'package:flutter/material.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/review/knowledge_grouping.dart';

/// Dialog to add or edit a tag value (D10).
Future<({String dimension, String value})?> showTagEditDialog(
  BuildContext context, {
  String? initialDimension,
  String? initialValue,
  bool lockDimension = false,
}) {
  return showDialog<({String dimension, String value})>(
    context: context,
    builder: (ctx) => _TagEditDialog(
      initialDimension: initialDimension ?? kKnowledgeDimensions.first,
      initialValue: initialValue ?? '',
      lockDimension: lockDimension,
    ),
  );
}

class _TagEditDialog extends StatefulWidget {
  const _TagEditDialog({
    required this.initialDimension,
    required this.initialValue,
    required this.lockDimension,
  });

  final String initialDimension;
  final String initialValue;
  final bool lockDimension;

  @override
  State<_TagEditDialog> createState() => _TagEditDialogState();
}

class _TagEditDialogState extends State<_TagEditDialog> {
  late String _dimension = widget.initialDimension;
  late final TextEditingController _value =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('tag-edit-dialog'),
      title: Text(widget.lockDimension ? 'Edit tag' : 'Add tag'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!widget.lockDimension)
            DropdownButtonFormField<String>(
              key: const Key('tag-dimension'),
              // ignore: deprecated_member_use
              value: _dimension,
              items: [
                for (final d in kKnowledgeDimensions)
                  DropdownMenuItem(value: d, child: Text(d)),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _dimension = v);
              },
              decoration: const InputDecoration(labelText: 'dimension'),
            )
          else
            Text('dimension: $_dimension', key: const Key('tag-dimension-locked')),
          const SizedBox(height: 12),
          TextField(
            key: const Key('tag-value-field'),
            controller: _value,
            decoration: const InputDecoration(labelText: 'value'),
            autofocus: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('tag-edit-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('tag-edit-save'),
          onPressed: () {
            final value = _value.text.trim();
            if (value.isEmpty) return;
            Navigator.of(context).pop((dimension: _dimension, value: value));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Dialog to correct key-period start/end bounds in milliseconds (D10).
Future<CorrectKeyPeriodBounds?> showKeyPeriodBoundsDialog(
  BuildContext context, {
  required int startMs,
  required int endMs,
}) {
  return showDialog<CorrectKeyPeriodBounds>(
    context: context,
    builder: (ctx) => _KeyPeriodBoundsDialog(startMs: startMs, endMs: endMs),
  );
}

class _KeyPeriodBoundsDialog extends StatefulWidget {
  const _KeyPeriodBoundsDialog({
    required this.startMs,
    required this.endMs,
  });

  final int startMs;
  final int endMs;

  @override
  State<_KeyPeriodBoundsDialog> createState() => _KeyPeriodBoundsDialogState();
}

class _KeyPeriodBoundsDialogState extends State<_KeyPeriodBoundsDialog> {
  late final TextEditingController _start =
      TextEditingController(text: '${widget.startMs}');
  late final TextEditingController _end =
      TextEditingController(text: '${widget.endMs}');

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('key-period-bounds-dialog'),
      title: const Text('Edit key period bounds'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('key-period-start-ms'),
            controller: _start,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'startMs'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('key-period-end-ms'),
            controller: _end,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'endMs'),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('key-period-bounds-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('key-period-bounds-save'),
          onPressed: () {
            final start = int.tryParse(_start.text.trim());
            final end = int.tryParse(_end.text.trim());
            if (start == null || end == null || end < start) return;
            Navigator.of(context).pop(
              CorrectKeyPeriodBounds(startMs: start, endMs: end),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
