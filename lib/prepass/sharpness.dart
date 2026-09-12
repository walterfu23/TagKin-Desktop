import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Variance-of-Laplacian below this is treated as blurry for opt-in Remove
/// blurry. Scored on grayscale downscaled to a [kSharpnessLongEdge] long edge.
/// Uniform / heavily smoothed stills land near 0; a high-contrast checkerboard
/// is well above this. Null stored scores are unknown — never auto-dropped.
const double kBlurrySharpnessThreshold = 80.0;

const int kSharpnessLongEdge = 64;

/// Variance of a 4-neighbor Laplacian on [bytes]. Null if the image cannot be
/// decoded. Metadata only — never uploaded (R1).
double? sharpnessFromJpeg(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    return sharpnessFromImage(decoded);
  } catch (_) {
    return null;
  }
}

/// Variance of a 4-neighbor Laplacian on [src] (photos or face crops).
double sharpnessFromImage(img.Image src) {
  if (src.width < 3 || src.height < 3) return 0;
  var work = src.numChannels == 1 ? src : img.grayscale(src);
  final long = math.max(work.width, work.height);
  if (long > kSharpnessLongEdge) {
    final scale = kSharpnessLongEdge / long;
    work = img.copyResize(
      work,
      width: math.max(3, (work.width * scale).round()),
      height: math.max(3, (work.height * scale).round()),
      interpolation: img.Interpolation.linear,
    );
  }
  if (work.width < 3 || work.height < 3) return 0;

  double luma(int x, int y) => work.getPixel(x, y).luminance.toDouble();

  final values = <double>[];
  for (var y = 1; y < work.height - 1; y++) {
    for (var x = 1; x < work.width - 1; x++) {
      values.add(
        luma(x, y - 1) +
            luma(x - 1, y) +
            luma(x + 1, y) +
            luma(x, y + 1) -
            4 * luma(x, y),
      );
    }
  }
  if (values.isEmpty) return 0;
  var sum = 0.0;
  for (final v in values) {
    sum += v;
  }
  final mean = sum / values.length;
  var acc = 0.0;
  for (final v in values) {
    final d = v - mean;
    acc += d * d;
  }
  return acc / values.length;
}
