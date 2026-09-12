import 'package:tagkin_desktop/contract/contract.dart';

/// True when Hide blurry should drop this photo.
///
/// Stored pre-pass [Item.sharpness] only (not a live auto-fixed still).
/// Videos and unknown (null) scores stay visible.
bool isHiddenBlurryPhoto({
  required Item item,
  required double threshold,
}) {
  if (item.type != ItemType.photo) return false;
  final stored = item.sharpness;
  if (stored == null) return false;
  return stored < threshold;
}
