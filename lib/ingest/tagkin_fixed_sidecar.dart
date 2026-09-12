import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/media_enumerator.dart';

/// Suffix for a JPEG written next to a blurry original (`Holiday.jpg` →
/// `Holiday.tagkin-fixed.jpg`). Never used as an overwrite of the original.
const String kTagkinFixedSidecarSuffix = '.tagkin-fixed.jpg';

/// True when [path] is a TagKin sharpened sidecar JPEG.
bool isTagkinFixedSidecar(String path, {p.Context? context}) {
  final base = (context ?? p.context).basename(path).toLowerCase();
  return base.endsWith(kTagkinFixedSidecarSuffix);
}

/// Album path for the sidecar JPEG next to [originalPath] (any photo ext).
String tagkinFixedSidecarPath(String originalPath, {p.Context? context}) {
  final ctx = context ?? p.context;
  final dir = ctx.dirname(originalPath);
  final stem = ctx.basenameWithoutExtension(originalPath);
  return ctx.join(dir, '$stem$kTagkinFixedSidecarSuffix');
}

/// Stem of a sidecar (`Holiday.tagkin-fixed.jpg` → `Holiday`), or null.
String? stemForTagkinFixedSidecar(String sidecarPath, {p.Context? context}) {
  final ctx = context ?? p.context;
  final base = ctx.basename(sidecarPath);
  final lower = base.toLowerCase();
  if (!lower.endsWith(kTagkinFixedSidecarSuffix)) return null;
  return base.substring(0, base.length - kTagkinFixedSidecarSuffix.length);
}

/// Possible original photo paths that pair with [sidecarPath] by directory + stem.
List<String> originalPathsForTagkinFixedSidecar(
  String sidecarPath, {
  p.Context? context,
}) {
  final ctx = context ?? p.context;
  final stem = stemForTagkinFixedSidecar(sidecarPath, context: ctx);
  if (stem == null || stem.isEmpty) return const [];
  final dir = ctx.dirname(sidecarPath);
  return [
    for (final ext in kPhotoExtensions) ctx.join(dir, '$stem.$ext'),
  ];
}

/// When a sidecar JPEG sits next to its original, keep the sidecar and drop
/// the blurry original so a later folder ingest does not mint a second item.
List<MediaCandidate> preferTagkinFixedSidecars(
  List<MediaCandidate> candidates, {
  p.Context? context,
}) {
  final ctx = context ?? p.context;
  final sidecarKeys = <String>{
    for (final c in candidates)
      if (c.type == ItemType.photo &&
          isTagkinFixedSidecar(c.path, context: ctx))
        ctx.normalize(c.path),
  };
  if (sidecarKeys.isEmpty) return candidates;

  return [
    for (final c in candidates)
      if (c.type != ItemType.photo ||
          isTagkinFixedSidecar(c.path, context: ctx) ||
          !sidecarKeys.contains(
            ctx.normalize(tagkinFixedSidecarPath(c.path, context: ctx)),
          ))
        c,
  ];
}
