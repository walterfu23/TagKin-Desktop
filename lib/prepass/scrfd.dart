import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// One SCRFD face: axis-aligned box + 5 landmarks (image pixel coords).
class ScrfdFace {
  const ScrfdFace({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.score,
    required this.landmarks,
  });

  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double score;

  /// 5×[x,y] — left eye, right eye, nose, left mouth, right mouth.
  final List<List<double>> landmarks;
}

/// Reorder raw det tensors into InsightFace layout: score×3, bbox×3, kps×3.
///
/// Flutter ONNX may return outputs alphabetically by name (`448`,`451`,…) which
/// interleaves score/bbox/kps and breaks decode. Classify by trailing dim instead.
List<Float32List>? orderScrfdOutputsByShape(
  List<({Float32List data, List<int> shape})> raw, {
  int detSize = 640,
}) {
  if (raw.length != 9) return null;
  const strides = [8, 16, 32];
  final expectN = [
    for (final s in strides) (detSize ~/ s) * (detSize ~/ s) * 2,
  ];

  final scores = List<Float32List?>.filled(3, null);
  final bboxes = List<Float32List?>.filled(3, null);
  final kps = List<Float32List?>.filled(3, null);

  for (final t in raw) {
    final parsed = _scrfdOutLayout(t.shape);
    if (parsed == null) continue;
    final idx = expectN.indexOf(parsed.rows);
    if (idx < 0) continue;
    switch (parsed.channels) {
      case 1:
        scores[idx] = t.data;
      case 4:
        bboxes[idx] = t.data;
      case 10:
        kps[idx] = t.data;
    }
  }

  if (scores.any((e) => e == null) ||
      bboxes.any((e) => e == null) ||
      kps.any((e) => e == null)) {
    return null;
  }
  return [
    scores[0]!,
    scores[1]!,
    scores[2]!,
    bboxes[0]!,
    bboxes[1]!,
    bboxes[2]!,
    kps[0]!,
    kps[1]!,
    kps[2]!,
  ];
}

({int rows, int channels})? _scrfdOutLayout(List<int> shape) {
  if (shape.isEmpty) return null;
  if (shape.length == 1) {
    return (rows: shape[0], channels: 1);
  }
  if (shape.length == 2) {
    return (rows: shape[0], channels: shape[1]);
  }
  // Batched: [1, N, C]
  if (shape.length == 3 && shape[0] == 1) {
    return (rows: shape[1], channels: shape[2]);
  }
  return null;
}

/// Max score across the three score maps (for debug when decode finds nothing).
@visibleForTesting
double maxScrfdScore(List<Float32List> orderedScores3) {
  var m = 0.0;
  for (final s in orderedScores3) {
    for (final v in s) {
      if (v > m) m = v;
    }
  }
  return m;
}

/// Decode InsightFace buffalo_l `det_10g` outputs (9 tensors, strides 8/16/32).
///
/// [netOuts] must be in order: score×3, bbox×3, kps×3 (see [orderScrfdOutputsByShape]).
List<ScrfdFace> decodeScrfdOutputs({
  required List<Float32List> netOuts,
  required int inputHeight,
  required int inputWidth,
  required double detScale,
  double threshold = 0.5,
  double nmsThresh = 0.4,
}) {
  assert(netOuts.length == 9);
  const strides = [8, 16, 32];
  const fmc = 3;
  const numAnchors = 2;

  final scoresAll = <double>[];
  final boxesAll = <List<double>>[];
  final kpsAll = <List<List<double>>>[];

  for (var idx = 0; idx < strides.length; idx++) {
    final stride = strides[idx];
    final scores = _asNx1(netOuts[idx]);
    final bboxPreds = _asNxC(netOuts[idx + fmc], 4);
    final kpsPreds = _asNxC(netOuts[idx + fmc * 2], 10);

    final height = inputHeight ~/ stride;
    final width = inputWidth ~/ stride;
    final anchors = _anchorCenters(height, width, stride, numAnchors);
    if (anchors.length != scores.length) {
      continue;
    }

    for (var i = 0; i < scores.length; i++) {
      final s = scores[i];
      if (s < threshold) continue;
      final bp = bboxPreds[i];
      final ax = anchors[i][0];
      final ay = anchors[i][1];
      final x1 = ax - bp[0] * stride;
      final y1 = ay - bp[1] * stride;
      final x2 = ax + bp[2] * stride;
      final y2 = ay + bp[3] * stride;
      final kp = kpsPreds[i];
      final landmarks = <List<double>>[];
      for (var k = 0; k < 5; k++) {
        landmarks.add([
          ax + kp[k * 2] * stride,
          ay + kp[k * 2 + 1] * stride,
        ]);
      }
      scoresAll.add(s);
      boxesAll.add([x1, y1, x2, y2]);
      kpsAll.add(landmarks);
    }
  }

  if (scoresAll.isEmpty) return const [];

  final order = List<int>.generate(scoresAll.length, (i) => i)
    ..sort((a, b) => scoresAll[b].compareTo(scoresAll[a]));

  final kept = <int>[];
  final suppressed = List<bool>.filled(order.length, false);
  for (var oi = 0; oi < order.length; oi++) {
    if (suppressed[oi]) continue;
    final i = order[oi];
    kept.add(i);
    final bi = boxesAll[i];
    final areaI =
        (bi[2] - bi[0] + 1) * (bi[3] - bi[1] + 1);
    for (var oj = oi + 1; oj < order.length; oj++) {
      if (suppressed[oj]) continue;
      final j = order[oj];
      final bj = boxesAll[j];
      final xx1 = math.max(bi[0], bj[0]);
      final yy1 = math.max(bi[1], bj[1]);
      final xx2 = math.min(bi[2], bj[2]);
      final yy2 = math.min(bi[3], bj[3]);
      final w = math.max(0.0, xx2 - xx1 + 1);
      final h = math.max(0.0, yy2 - yy1 + 1);
      final inter = w * h;
      final areaJ =
          (bj[2] - bj[0] + 1) * (bj[3] - bj[1] + 1);
      final ovr = inter / (areaI + areaJ - inter);
      if (ovr > nmsThresh) suppressed[oj] = true;
    }
  }

  return [
    for (final i in kept)
      ScrfdFace(
        x1: boxesAll[i][0] / detScale,
        y1: boxesAll[i][1] / detScale,
        x2: boxesAll[i][2] / detScale,
        y2: boxesAll[i][3] / detScale,
        score: scoresAll[i],
        landmarks: [
          for (final p in kpsAll[i]) [p[0] / detScale, p[1] / detScale],
        ],
      ),
  ];
}

/// Letterbox [src] into [detSize]² (top-left), return pad image + scale
/// (resized_h / src_h). Matches InsightFace SCRFD preprocess.
({img.Image detImg, double detScale, int newW, int newH}) letterboxForScrfd(
  img.Image src, {
  int detSize = 640,
}) {
  final imRatio = src.height / src.width;
  final modelRatio = 1.0;
  late int newW;
  late int newH;
  if (imRatio > modelRatio) {
    newH = detSize;
    newW = (newH / imRatio).round();
  } else {
    newW = detSize;
    newH = (newW * imRatio).round();
  }
  if (newW < 1) newW = 1;
  if (newH < 1) newH = 1;
  final detScale = newH / src.height;
  final resized = img.copyResize(
    src,
    width: newW,
    height: newH,
    interpolation: img.Interpolation.linear,
  );
  final detImg = img.Image(width: detSize, height: detSize);
  img.fill(detImg, color: img.ColorRgb8(0, 0, 0));
  img.compositeImage(detImg, resized, dstX: 0, dstY: 0);
  return (detImg: detImg, detScale: detScale, newW: newW, newH: newH);
}

/// NCHW float blob: (x − 127.5) / 128 — InsightFace SCRFD (RGB, no BGR swap).
Float32List scrfdBlobNchw(img.Image image) {
  const mean = 127.5;
  const std = 128.0;
  final h = image.height;
  final w = image.width;
  final out = Float32List(3 * h * w);
  var i = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = image.getPixel(x, y);
      out[i] = (p.r - mean) / std;
      out[i + h * w] = (p.g - mean) / std;
      out[i + 2 * h * w] = (p.b - mean) / std;
      i++;
    }
  }
  return out;
}

List<double> _asNx1(Float32List t) {
  // Flatten; last dim is 1.
  return [for (var i = 0; i < t.length; i++) t[i]];
}

List<List<double>> _asNxC(Float32List t, int c) {
  final n = t.length ~/ c;
  return [
    for (var i = 0; i < n; i++)
      [for (var j = 0; j < c; j++) t[i * c + j]],
  ];
}

List<List<double>> _anchorCenters(
  int height,
  int width,
  int stride,
  int numAnchors,
) {
  final out = <List<double>>[];
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final cx = x * stride.toDouble();
      final cy = y * stride.toDouble();
      for (var a = 0; a < numAnchors; a++) {
        out.add([cx, cy]);
      }
    }
  }
  return out;
}

/// Pick the highest-score face (who-crop usually has one).
ScrfdFace? bestScrfdFace(List<ScrfdFace> faces) {
  if (faces.isEmpty) return null;
  return faces.reduce((a, b) => a.score >= b.score ? a : b);
}

/// Highest-score face whose center lies inside a normalized region of an
/// image of size [imgW]×[imgH]. Used when the who-box is body-sized and
/// crop-level SCRFD finds nothing.
ScrfdFace? bestScrfdFaceInRegion(
  List<ScrfdFace> faces, {
  required double yMin,
  required double xMin,
  required double yMax,
  required double xMax,
  required int imgW,
  required int imgH,
}) {
  if (faces.isEmpty || imgW <= 0 || imgH <= 0) return null;
  final x0 = xMin * imgW;
  final y0 = yMin * imgH;
  final x1 = xMax * imgW;
  final y1 = yMax * imgH;
  ScrfdFace? best;
  for (final f in faces) {
    final cx = (f.x1 + f.x2) / 2;
    final cy = (f.y1 + f.y2) / 2;
    if (cx < x0 || cx > x1 || cy < y0 || cy > y1) continue;
    if (best == null || f.score > best.score) best = f;
  }
  return best;
}
