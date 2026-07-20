import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Difference hash (dHash): 9×8 greyscale → 64-bit hex.
///
/// Mirrors the TS `@tagkin/prepass` algorithm
/// (`TagKin/packages/prepass/src/phash.ts`) so desktop and API stay
/// conceptually aligned ahead of D4. Near-duplicates share a low
/// [hammingDistance]. Photos only — video near-dup needs frame sampling,
/// which is D4's job, not D3's.
///
/// Returns `null` when [bytes] cannot be decoded as an image (e.g. an
/// unsupported/corrupt file); callers fall back to exact `contentHash`
/// dedup only in that case.
String? computePerceptualHash(Uint8List bytes) {
  img.Image? source;
  try {
    source = img.decodeImage(bytes);
  } catch (_) {
    // Malformed/truncated input the decoder's format sniffing chokes on —
    // treat exactly like "not an image" rather than crashing the batch.
    return null;
  }
  if (source == null) return null;

  final resized = img.copyResize(source, width: 9, height: 8);
  final grey = img.grayscale(resized);

  var bits = BigInt.zero;
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      final left = grey.getPixel(x, y).r;
      final right = grey.getPixel(x + 1, y).r;
      bits = (bits << 1) | (left > right ? BigInt.one : BigInt.zero);
    }
  }
  return bits.toRadixString(16).padLeft(16, '0');
}

/// Reads and decodes [path] from local disk only, then computes
/// [computePerceptualHash]. Never sends bytes anywhere (R1/R5).
Future<String?> computePerceptualHashFromFile(String path) async {
  final bytes = await File(path).readAsBytes();
  return computePerceptualHash(bytes);
}

/// Hamming distance between two hex dHash strings (bit count of XOR).
/// Lower distance ⇒ more visually similar.
int hammingDistance(String a, String b) {
  final ha = BigInt.parse(a, radix: 16);
  final hb = BigInt.parse(b, radix: 16);
  var x = ha ^ hb;
  var count = 0;
  while (x > BigInt.zero) {
    if (x & BigInt.one == BigInt.one) count++;
    x >>= 1;
  }
  return count;
}
