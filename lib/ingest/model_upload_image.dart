import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/upload_mime.dart';

/// Bytes + MIME for the model-host upload (D5).
///
/// HEIC/HEIF are decoded (Flutter codec on macOS) and re-encoded as JPEG so
/// Gemini analyze always sees `image/jpeg` bytes — matching [runTagging]'s
/// JPEG assumption and avoiding HEIC mime mismatches.
typedef ModelUploadPayload = ({List<int> bytes, String mimeType});

/// Prepares local file bytes for model-host PUT.
Future<ModelUploadPayload> prepareModelUploadBytes({
  required String path,
  required ItemType type,
  required List<int> rawBytes,
}) async {
  final mime = mimeTypeForPath(path, type);
  if (mime != 'image/heic' && mime != 'image/heif') {
    return (bytes: rawBytes, mimeType: mime);
  }

  final jpeg = await convertHeicLikeToJpeg(Uint8List.fromList(rawBytes));
  if (jpeg == null) {
    throw StateError(
      'Could not decode HEIC/HEIF for model upload ($path).',
    );
  }
  return (bytes: jpeg, mimeType: 'image/jpeg');
}

/// Decode HEIC/HEIF (or any Flutter-supported still) to JPEG bytes.
Future<Uint8List?> convertHeicLikeToJpeg(Uint8List imageBytes) async {
  final viaPackage = img.decodeImage(imageBytes);
  if (viaPackage != null) {
    return Uint8List.fromList(img.encodeJpg(viaPackage, quality: 92));
  }
  final viaFlutter = await _decodeWithFlutterCodec(imageBytes);
  if (viaFlutter == null) return null;
  return Uint8List.fromList(img.encodeJpg(viaFlutter, quality: 92));
}

Future<img.Image?> _decodeWithFlutterCodec(Uint8List imageBytes) async {
  ui.Codec? codec;
  ui.Image? frameImage;
  try {
    codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    frameImage = frame.image;
    final byteData =
        await frameImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return null;
    final rgba = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    return img.Image.fromBytes(
      width: frameImage.width,
      height: frameImage.height,
      bytes: rgba.buffer,
      bytesOffset: rgba.offsetInBytes,
      rowStride: frameImage.width * 4,
      order: img.ChannelOrder.rgba,
    );
  } catch (_) {
    return null;
  } finally {
    frameImage?.dispose();
    codec?.dispose();
  }
}
