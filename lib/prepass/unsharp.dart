import 'package:image/image.dart' as img;

/// Config/data id for the local unsharp-mask method (not a vendor name).
const String kLocalUnsharpMethodId = 'local-unsharp-v1';

/// Unsharp mask: add [amount] × (original − gaussian blur) per channel.
img.Image unsharpMask(
  img.Image src, {
  int radius = 2,
  double amount = 1.5,
}) {
  if (src.width < 3 || src.height < 3) return src.clone();
  final blurred = img.gaussianBlur(src.clone(), radius: radius);
  final out = src.clone();
  for (var y = 0; y < out.height; y++) {
    for (var x = 0; x < out.width; x++) {
      final o = src.getPixel(x, y);
      final b = blurred.getPixel(x, y);
      out.setPixelRgba(
        x,
        y,
        _mix(o.r, b.r, amount),
        _mix(o.g, b.g, amount),
        _mix(o.b, b.b, amount),
        o.a.toInt(),
      );
    }
  }
  return out;
}

int _mix(num orig, num blur, double amount) {
  final v = orig + amount * (orig - blur);
  if (v < 0) return 0;
  if (v > 255) return 255;
  return v.round();
}
