import 'package:flutter/material.dart';

/// Shared "Remove person?" confirmation used by Faces trays and person detail.
Future<bool> confirmRemovePerson({
  required BuildContext context,
  required Key confirmKey,
  required String body,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Remove person?'),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: confirmKey,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  return confirmed == true;
}
