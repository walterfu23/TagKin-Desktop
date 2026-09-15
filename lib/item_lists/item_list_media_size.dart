import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tagkin_desktop/ingest/model_upload_image.dart';
import 'package:tagkin_desktop/item_lists/export_sequence_size.dart';
import 'package:tagkin_desktop/prepass/ffmpeg_resolve.dart';

/// Pixel size of a still or video file used on an NLE timeline.
class ItemListPixelSize {
  const ItemListPixelSize(this.width, this.height);

  final int width;
  final int height;

  bool get isValid => width >= 1 && height >= 1;

  @override
  bool operator ==(Object other) =>
      other is ItemListPixelSize &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}

const kItemListNle1080p = ItemListPixelSize(1920, 1080);
const kItemListNle4k = ItemListPixelSize(3840, 2160);

typedef ItemListMediaSizeProbe = Future<ItemListPixelSize?> Function(
  String path, {
  required bool isStill,
});

/// Sequence canvas from [ExportSequenceSize] and probed file sizes.
ItemListPixelSize itemListNleSequencePixelSize({
  required ExportSequenceSize mode,
  required Iterable<ItemListPixelSize> probed,
}) {
  switch (mode) {
    case ExportSequenceSize.p1080:
      return kItemListNle1080p;
    case ExportSequenceSize.p4k:
      return kItemListNle4k;
    case ExportSequenceSize.matchSmallest:
      var w = 1 << 30;
      var h = 1 << 30;
      for (final s in probed) {
        if (!s.isValid) continue;
        if (s.width < w) w = s.width;
        if (s.height < h) h = s.height;
      }
      if (w == 1 << 30 || h == 1 << 30) return kItemListNle1080p;
      return ItemListPixelSize(w, h);
    case ExportSequenceSize.matchLargest:
      var w = 0;
      var h = 0;
      for (final s in probed) {
        if (!s.isValid) continue;
        if (s.width > w) w = s.width;
        if (s.height > h) h = s.height;
      }
      if (w < 1 || h < 1) return kItemListNle1080p;
      return ItemListPixelSize(w, h);
  }
}

/// Scale percent (100 = native) to fit [file] in [sequence], aspect preserved.
double itemListNleFitScalePercent({
  required int fileWidth,
  required int fileHeight,
  required int sequenceWidth,
  required int sequenceHeight,
}) {
  if (fileWidth < 1 ||
      fileHeight < 1 ||
      sequenceWidth < 1 ||
      sequenceHeight < 1) {
    return 100;
  }
  final sx = sequenceWidth / fileWidth;
  final sy = sequenceHeight / fileHeight;
  final fit = sx < sy ? sx : sy;
  return (fit * 100000).round() / 1000;
}

bool itemListNleNeedsFitScale(double percent) => (percent - 100).abs() > 0.05;

String itemListNleScaleXmlValue(double percent) {
  if (percent == percent.roundToDouble()) return '${percent.round()}';
  return percent.toString();
}

/// First JPEG SOF0/SOF1/SOF2 size. Skips APPn (EXIF thumbnails) and stops
/// before a trailing gain-map / motion-photo JPEG.
ItemListPixelSize? itemListNleJpegSofSize(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xff || bytes[1] != 0xd8) return null;
  var i = 2;
  while (i < bytes.length) {
    if (bytes[i] != 0xff) {
      i++;
      continue;
    }
    while (i < bytes.length && bytes[i] == 0xff) {
      i++;
    }
    if (i >= bytes.length) return null;
    final marker = bytes[i];
    i++;
    if (marker == 0xd8) continue;
    if (marker == 0xd9 || marker == 0xda) return null;
    if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
    if (i + 1 >= bytes.length) return null;
    final len = (bytes[i] << 8) | bytes[i + 1];
    if (len < 2 || i + len > bytes.length) return null;
    if (marker == 0xc0 || marker == 0xc1 || marker == 0xc2) {
      if (len < 7) return null;
      final h = (bytes[i + 3] << 8) | bytes[i + 4];
      final w = (bytes[i + 5] << 8) | bytes[i + 6];
      if (w < 1 || h < 1) return null;
      return ItemListPixelSize(w, h);
    }
    i += len;
  }
  return null;
}

/// Header-only still size; EXIF orientation 5–8 swaps width/height.
ItemListPixelSize? itemListNleStillSizeFromBytes(Uint8List bytes) {
  final jpeg = itemListNleJpegSofSize(bytes);
  if (jpeg != null) {
    try {
      final orientation = jpegExifOrientation(bytes);
      if (orientation != null && orientation >= 5 && orientation <= 8) {
        return ItemListPixelSize(jpeg.height, jpeg.width);
      }
    } catch (_) {
      return jpeg;
    }
    return jpeg;
  }
  final decoder = img.findDecoderForData(bytes);
  if (decoder == null) return null;
  final info = decoder.startDecode(bytes);
  if (info == null || info.width < 1 || info.height < 1) return null;
  return ItemListPixelSize(info.width, info.height);
}

ItemListPixelSize? itemListNleVideoSizeFromFfprobe(String stdout) {
  final text = stdout.trim();
  if (text.isEmpty) return null;
  final lines = text.split(RegExp(r'[\s,x]+')).where((s) => s.isNotEmpty);
  final nums = <int>[];
  for (final part in lines) {
    final n = int.tryParse(part);
    if (n != null) nums.add(n);
  }
  if (nums.length < 2 || nums[0] < 1 || nums[1] < 1) return null;
  var w = nums[0];
  var h = nums[1];
  if (nums.length >= 3) {
    final rot = nums[2].abs() % 360;
    if (rot == 90 || rot == 270) {
      final swap = w;
      w = h;
      h = swap;
    }
  }
  return ItemListPixelSize(w, h);
}

Future<ItemListPixelSize?> probeItemListMediaSize(
  String path, {
  required bool isStill,
}) async {
  try {
    if (isStill) {
      final file = File(path);
      if (!file.existsSync()) return null;
      final bytes = await file.readAsBytes();
      final fromBytes = itemListNleStillSizeFromBytes(bytes);
      if (fromBytes != null && fromBytes.isValid) return fromBytes;
    }
    return _ffprobeMediaSize(path);
  } catch (_) {
    return null;
  }
}

Future<ItemListPixelSize?> _ffprobeMediaSize(String path) async {
  final tools = resolveFfmpegTools();
  if (tools == null) return null;
  final result = await Process.run(
    tools.ffprobe,
    [
      '-v',
      'error',
      '-select_streams',
      'v:0',
      '-show_entries',
      'stream=width,height,rotation',
      '-of',
      'csv=p=0',
      path,
    ],
    runInShell: false,
  );
  if (result.exitCode != 0) return null;
  return itemListNleVideoSizeFromFfprobe('${result.stdout}');
}
