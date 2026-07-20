import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/contract/contract.dart';

/// Extension → MIME map for D5 upload-grant `mimeType` (image/* or video/*).
///
/// D4 frame samples are always `.jpg` → `image/jpeg`. Falls back to a
/// type-default when the extension is unknown.
String mimeTypeForPath(String path, ItemType type) {
  final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'heic':
      return 'image/heic';
    case 'heif':
      return 'image/heif';
    case 'webp':
      return 'image/webp';
    case 'bmp':
      return 'image/bmp';
    case 'tif':
    case 'tiff':
      return 'image/tiff';
    case 'mp4':
      return 'video/mp4';
    case 'mov':
      return 'video/quicktime';
    case 'm4v':
      return 'video/x-m4v';
    case 'avi':
      return 'video/x-msvideo';
    case 'mkv':
      return 'video/x-matroska';
    case 'webm':
      return 'video/webm';
  }
  return type == ItemType.video ? 'video/mp4' : 'image/jpeg';
}
