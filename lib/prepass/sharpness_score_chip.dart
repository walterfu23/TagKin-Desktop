import 'package:flutter/material.dart';
import 'package:tagkin_desktop/contract/contract.dart';

/// Compact stored pre-pass sharpness on a photo thumb or still
/// (Folders / Export / item detail).
///
/// Videos are skipped. Null stored scores show an em dash.
class SharpnessScoreChip extends StatelessWidget {
  const SharpnessScoreChip({
    super.key,
    required this.item,
  });

  final Item item;

  static String format(double? sharpness) {
    if (sharpness == null) return '—';
    return sharpness.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    if (item.type != ItemType.photo) return const SizedBox.shrink();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text(
          format(item.sharpness),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}
