import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// InsightFace ArcFace 112 template (left eye, right eye, nose, left mouth, right mouth).
@visibleForTesting
const List<List<double>> kArcFaceTemplate112 = [
  [38.2946, 51.6963],
  [73.5318, 51.5014],
  [56.0252, 71.7366],
  [41.5493, 92.3655],
  [70.7299, 92.2041],
];

/// 2×3 similarity matrix mapping [src] → ArcFace template, then warp to [imageSize]².
@visibleForTesting
Float64List estimateNormSimilarity(
  List<List<double>> landmarks, {
  int imageSize = 112,
}) {
  assert(landmarks.length == 5);
  final ratio = imageSize / 112.0;
  final dst = [
    for (final p in kArcFaceTemplate112) [p[0] * ratio, p[1] * ratio],
  ];
  return estimateSimilarityTransform(landmarks, dst);
}

/// Least-squares similarity (Umeyama / skimage SimilarityTransform) src→dst → 2×3.
@visibleForTesting
Float64List estimateSimilarityTransform(
  List<List<double>> src,
  List<List<double>> dst,
) {
  assert(src.length == dst.length && src.length >= 2);
  final n = src.length;
  var srcCx = 0.0, srcCy = 0.0, dstCx = 0.0, dstCy = 0.0;
  for (var i = 0; i < n; i++) {
    srcCx += src[i][0];
    srcCy += src[i][1];
    dstCx += dst[i][0];
    dstCy += dst[i][1];
  }
  srcCx /= n;
  srcCy /= n;
  dstCx /= n;
  dstCy /= n;

  // A = dst_demean^T @ src_demean / n  (2×2)
  var a00 = 0.0, a01 = 0.0, a10 = 0.0, a11 = 0.0;
  var srcVar = 0.0; // sum of per-dim population variances of src_demean
  for (var i = 0; i < n; i++) {
    final sx = src[i][0] - srcCx;
    final sy = src[i][1] - srcCy;
    final dx = dst[i][0] - dstCx;
    final dy = dst[i][1] - dstCy;
    a00 += dx * sx;
    a01 += dx * sy;
    a10 += dy * sx;
    a11 += dy * sy;
    srcVar += sx * sx + sy * sy;
  }
  a00 /= n;
  a01 /= n;
  a10 /= n;
  a11 /= n;
  srcVar /= n; // == src_demean.var(axis=0).sum() with ddof=0

  final detA = a00 * a11 - a01 * a10;
  final svd = _svd2x2(a00, a01, a10, a11);
  final d1 = 1.0;
  final d2 = detA < 0 ? -1.0 : 1.0;

  // R = U @ diag(d) @ V  (V from SVD of A is V^T in numpy; here V rows are V^T)
  // numpy: U, S, Vt = svd(A); R = U @ diag(d) @ Vt
  final u00 = svd.u00, u01 = svd.u01, u10 = svd.u10, u11 = svd.u11;
  final vt00 = svd.vt00, vt01 = svd.vt01, vt10 = svd.vt10, vt11 = svd.vt11;
  final ud00 = u00 * d1;
  final ud01 = u01 * d2;
  final ud10 = u10 * d1;
  final ud11 = u11 * d2;
  final r00 = ud00 * vt00 + ud01 * vt10;
  final r01 = ud00 * vt01 + ud01 * vt11;
  final r10 = ud10 * vt00 + ud11 * vt10;
  final r11 = ud10 * vt01 + ud11 * vt11;

  final scale =
      srcVar > 1e-12 ? (svd.s0 * d1 + svd.s1 * d2) / srcVar : 1.0;

  final m00 = scale * r00;
  final m01 = scale * r01;
  final m10 = scale * r10;
  final m11 = scale * r11;
  final tx = dstCx - (m00 * srcCx + m01 * srcCy);
  final ty = dstCy - (m10 * srcCx + m11 * srcCy);

  return Float64List.fromList([m00, m01, tx, m10, m11, ty]);
}

/// Thin SVD of 2×2 matrix [[a,b],[c,d]] → U, S, Vt (numpy-compatible).
({
  double u00,
  double u01,
  double u10,
  double u11,
  double s0,
  double s1,
  double vt00,
  double vt01,
  double vt10,
  double vt11,
}) _svd2x2(double a, double b, double c, double d) {
  // Use numpy via Jacobi-ish closed form: A^T A eigendecomposition for V, etc.
  // AtA = [[a,b],[c,d]]^T [[a,b],[c,d]]
  final ata00 = a * a + c * c;
  final ata01 = a * b + c * d;
  final ata11 = b * b + d * d;
  final halfTrace = 0.5 * (ata00 + ata11);
  final diff = 0.5 * (ata00 - ata11);
  final disc = math.sqrt(diff * diff + ata01 * ata01);
  final ev0 = halfTrace + disc;
  final ev1 = halfTrace - disc;
  var v0x = 1.0, v0y = 0.0, v1x = 0.0, v1y = 1.0;
  if (ata01.abs() > 1e-15 || diff.abs() > 1e-15) {
    if ((ev0 - ata11).abs() > 1e-15 || ata01.abs() > 1e-15) {
      v0x = ev0 - ata11;
      v0y = ata01;
    } else {
      v0x = ata01;
      v0y = ev0 - ata00;
    }
    final n0 = math.sqrt(v0x * v0x + v0y * v0y);
    v0x /= n0;
    v0y /= n0;
    v1x = -v0y;
    v1y = v0x;
  }
  final s0 = math.sqrt(math.max(0.0, ev0));
  final s1 = math.sqrt(math.max(0.0, ev1));
  // U columns = A @ v / s
  double u0x = a * v0x + b * v0y;
  double u0y = c * v0x + d * v0y;
  double u1x = a * v1x + b * v1y;
  double u1y = c * v1x + d * v1y;
  if (s0 > 1e-15) {
    u0x /= s0;
    u0y /= s0;
  }
  if (s1 > 1e-15) {
    u1x /= s1;
    u1y /= s1;
  } else {
    // orthonormalize
    u1x = -u0y;
    u1y = u0x;
  }
  // Ensure right-handed U (det >= 0) like numpy often does for this path
  if (u0x * u1y - u0y * u1x < 0) {
    u1x = -u1x;
    u1y = -u1y;
    // and flip corresponding V row sign for Vt
    v1x = -v1x;
    v1y = -v1y;
  }
  // Vt rows are V^T: row0 = v0, row1 = v1
  return (
    u00: u0x,
    u01: u1x,
    u10: u0y,
    u11: u1y,
    s0: s0,
    s1: s1,
    vt00: v0x,
    vt01: v0y,
    vt10: v1x,
    vt11: v1y,
  );
}

/// Warp [src] with 2×3 forward matrix (src→dst) into [outSize]×[outSize].
@visibleForTesting
img.Image warpAffine(
  img.Image src,
  Float64List m23, {
  int outSize = 112,
  int border = 0,
}) {
  final a = m23[0], b = m23[1], tx = m23[2];
  final c = m23[3], d = m23[4], ty = m23[5];
  final det = a * d - b * c;
  final out = img.Image(width: outSize, height: outSize);
  img.fill(out, color: img.ColorRgb8(border, border, border));
  if (det.abs() < 1e-12) return out;

  final inv00 = d / det;
  final inv01 = -b / det;
  final inv10 = -c / det;
  final inv11 = a / det;

  for (var y = 0; y < outSize; y++) {
    for (var x = 0; x < outSize; x++) {
      final dx = x - tx;
      final dy = y - ty;
      final sx = inv00 * dx + inv01 * dy;
      final sy = inv10 * dx + inv11 * dy;
      if (sx < -1 || sy < -1 || sx >= src.width || sy >= src.height) {
        continue;
      }
      final pixel = src.getPixelInterpolate(
        sx,
        sy,
        interpolation: img.Interpolation.linear,
      );
      out.setPixel(x, y, pixel);
    }
  }
  return out;
}

/// Align face crop to ArcFace 112×112 using 5 landmarks in source image coords.
img.Image normCropArcFace(img.Image src, List<List<double>> landmarks5) {
  final m = estimateNormSimilarity(landmarks5, imageSize: 112);
  return warpAffine(src, m, outSize: 112, border: 0);
}

/// When SCRFD finds no face, map the ArcFace template onto the who-crop so the
/// recognizer still sees an "aligned" 112² — never mix raw letterbox warps with
/// SCRFD-aligned vectors (runtime: letterbox↔scrfd distances were 0.8–0.9).
@visibleForTesting
List<List<double>> templateLandmarksForCrop(int width, int height) {
  return [
    for (final p in kArcFaceTemplate112)
      [p[0] / 112.0 * width, p[1] / 112.0 * height],
  ];
}

img.Image pseudoAlignWhoCrop(img.Image crop) {
  return normCropArcFace(
    crop,
    templateLandmarksForCrop(crop.width, crop.height),
  );
}
