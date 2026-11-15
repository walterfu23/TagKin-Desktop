import 'package:flutter/material.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/persons/who_face_crop_thumb.dart';

/// One face in the name-conflict chooser.
class ConflictFace {
  const ConflictFace({
    required this.itemId,
    required this.tagId,
    required this.name,
    this.number,
    this.knowledge,
    this.region,
  });

  final String itemId;
  final String tagId;

  /// Person currently on this face; null or empty reads as Unassigned.
  final String? name;

  /// Folders Edit face number, when the surface numbers its faces.
  final int? number;
  final ItemKnowledge? knowledge;
  final TagRegion? region;

  String get label {
    final n = name?.trim();
    final who = n == null || n.isEmpty ? 'Unassigned' : n;
    return number == null ? who : '$number $who';
  }
}

/// A person can be on one face per photo (or key period). Lets the user pick
/// which face keeps [personName]. Returns true when [target] is chosen (it
/// takes the name and [holder] is left Unassigned); false for [holder] or
/// Cancel.
Future<bool> showFaceNameConflictDialog(
  BuildContext context, {
  required String personName,
  required ConflictFace target,
  required ConflictFace holder,
}) async {
  final chosen = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('face-name-conflict-dialog'),
      title: Text('$personName is already on another face'),
      content: SelectionArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Choose the face that is $personName.'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ConflictTile(
                  face: target,
                  onTap: () => Navigator.of(ctx).pop(true),
                ),
                _ConflictTile(
                  face: holder,
                  onTap: () => Navigator.of(ctx).pop(false),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('face-name-conflict-cancel'),
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
  return chosen ?? false;
}

class _ConflictTile extends StatelessWidget {
  const _ConflictTile({required this.face, required this.onTap});

  final ConflictFace face;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('face-name-conflict-pick-${face.tagId}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            WhoFaceCropThumb(
              itemId: face.itemId,
              tagId: face.tagId,
              knowledge: face.knowledge,
              region: face.region,
              size: 72,
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                face.label,
                key: Key('face-name-conflict-label-${face.tagId}'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
