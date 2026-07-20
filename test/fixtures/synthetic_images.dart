// Procedurally-generated (never committed) PNG fixtures for the D3
// perceptual-hash regression — owned/synthetic media only, no real user
// media bytes.
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A flat single-color square.
Uint8List solidImagePng({
  int r = 10,
  int g = 10,
  int b = 10,
  int size = 32,
}) {
  final image = img.Image(width: size, height: size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

/// A monotonic left-to-right greyscale gradient (ascending by default,
/// [descending] flips the direction so it hashes very differently),
/// optionally perturbed by small deterministic per-pixel noise (simulating
/// a re-save / re-compression of the "same" photo) that should still hash
/// as a near-duplicate of the un-perturbed original.
Uint8List gradientImagePng({
  int size = 32,
  int noiseAmplitude = 0,
  bool descending = false,
}) {
  final image = img.Image(width: size, height: size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final ratio = descending ? (1 - x / size) : (x / size);
      final base = (ratio * 255).round();
      final noise = noiseAmplitude == 0
          ? 0
          : (((x * 7 + y * 13) % (2 * noiseAmplitude + 1)) - noiseAmplitude);
      final value = (base + noise).clamp(0, 255);
      image.setPixelRgb(x, y, value, value, value);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}
