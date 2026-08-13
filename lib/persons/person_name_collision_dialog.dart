import 'package:flutter/material.dart';

enum PersonNameCollisionChoice { merge, otherName }

/// Taken name: merge into the existing person, or pick a different name.
Future<PersonNameCollisionChoice?> showPersonNameCollisionDialog(
  BuildContext context, {
  required String existingName,
  required String mergeLabel,
}) {
  return showDialog<PersonNameCollisionChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('face-crop-rename-collision'),
      title: Text('$existingName already exists'),
      content: Text(
        'A person named $existingName already exists in this account. '
        '$mergeLabel, or use a different name.',
      ),
      actions: [
        TextButton(
          key: const Key('face-crop-rename-collision-cancel'),
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('face-crop-rename-collision-other-name'),
          onPressed: () =>
              Navigator.of(ctx).pop(PersonNameCollisionChoice.otherName),
          child: const Text('Different name'),
        ),
        FilledButton(
          key: const Key('face-crop-rename-collision-merge'),
          onPressed: () =>
              Navigator.of(ctx).pop(PersonNameCollisionChoice.merge),
          child: const Text('Merge'),
        ),
      ],
    ),
  );
}
