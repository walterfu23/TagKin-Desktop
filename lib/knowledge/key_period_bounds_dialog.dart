import 'package:flutter/material.dart';
import 'package:tagkin_desktop/contract/contract.dart';

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
