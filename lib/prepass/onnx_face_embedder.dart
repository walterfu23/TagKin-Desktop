import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/prepass/face_align.dart';
import 'package:tagkin_desktop/prepass/face_embedder.dart';
import 'package:tagkin_desktop/prepass/scrfd.dart';

/// Stable id for the bundled ArcFace-class recognizer (never reuse stub id).
/// Bumped when preprocess changes (letterbox / align / normalize) so old vectors don't mix.
const String kOnnxArcfaceEmbeddingModelId = 'onnx-arcface-w600k-r50-v5';

/// Pad [src] to a square canvas (mid-gray) preserving aspect ratio — no stretch.
@visibleForTesting
img.Image letterboxToSquare(img.Image src, {int padValue = 127}) {
  final w = src.width;
  final h = src.height;
  if (w <= 0 || h <= 0) return src;
  if (w == h) return src;

  final side = math.max(w, h);
  final out = img.Image(width: side, height: side);
  img.fill(out, color: img.ColorRgb8(padValue, padValue, padValue));
  final dx = ((side - w) / 2).floor();
  final dy = ((side - h) / 2).floor();
  img.compositeImage(out, src, dstX: dx, dstY: dy);
  return out;
}

void _agentLog(String hypothesisId, String location, String message, Map<String, Object?> data) {
  // #region agent log
  debugPrint('OnnxFaceEmbedder[$hypothesisId] $message $data');
  try {
    final payload = jsonEncode({
      'sessionId': '242c65',
      'runId': 'post-align',
      'hypothesisId': hypothesisId,
      'location': location,
      'message': message,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    // Sandboxed macOS app cannot write the workspace debug file — POST instead.
    final client = HttpClient();
    client
        .postUrl(
          Uri.parse(
            'http://127.0.0.1:7354/ingest/6b694349-3b46-4da2-bf90-b5c14f959906',
          ),
        )
        .then((req) {
          req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
          req.headers.set('X-Debug-Session-Id', '242c65');
          req.add(utf8.encode(payload));
          return req.close();
        })
        .then((res) => res.drain<void>())
        .catchError((_) {})
        .whenComplete(() => client.close(force: true));
  } catch (_) {}
  // #endregion
}

/// Resolves on-disk paths for face ONNX weights (R1 — local only).
class FaceModelPaths {
  const FaceModelPaths({this.recogPath, this.detPath});

  final String? recogPath;
  final String? detPath;

  bool get hasRecog => recogPath != null && File(recogPath!).existsSync();

  static const recogFileName = 'w600k_r50.onnx';
  static const detFileName = 'det_10g.onnx';
  static const _minRecogBytes = 1_000_000;

  /// Search order: env → app-support → cwd → walk up from executable (debug .app).
  static Future<FaceModelPaths> resolve() async {
    final envRecog = Platform.environment['TAGKIN_FACE_RECOG_MODEL'];
    final envDet = Platform.environment['TAGKIN_FACE_DET_MODEL'];

    final candidatesRecog = <String>[
      if (envRecog != null && envRecog.isNotEmpty) envRecog,
      ...defaultModelCandidates(
        fileName: recogFileName,
        executablePath: Platform.resolvedExecutable,
      ),
    ];
    final candidatesDet = <String>[
      if (envDet != null && envDet.isNotEmpty) envDet,
      ...defaultModelCandidates(
        fileName: detFileName,
        executablePath: Platform.resolvedExecutable,
      ),
    ];

    String? recog;
    for (final c in candidatesRecog) {
      if (File(c).existsSync()) {
        recog = c;
        break;
      }
    }
    String? det;
    for (final c in candidatesDet) {
      if (File(c).existsSync()) {
        det = c;
        break;
      }
    }
    return FaceModelPaths(recogPath: recog, detPath: det);
  }

  /// Copy discovered weights into the sandboxed app support dir, then return
  /// those paths. ONNX Runtime cannot open repo/host paths under App Sandbox
  /// (EPERM / system error 1); the container support dir is writable + readable.
  static Future<FaceModelPaths> resolveForOrtSession() async {
    final support = await getApplicationSupportDirectory();
    final modelsDir = Directory(p.join(support.path, 'models'));
    await modelsDir.create(recursive: true);
    final recogDest = File(p.join(modelsDir.path, recogFileName));
    final detDest = File(p.join(modelsDir.path, detFileName));

    final sourced = await resolve();
    if (sourced.recogPath == null) {
      return FaceModelPaths(
        recogPath: _usableModelFile(recogDest) ? recogDest.path : null,
        detPath: _usableModelFile(detDest) ? detDest.path : null,
      );
    }

    if (!_usableModelFile(recogDest) ||
        !_sameLength(File(sourced.recogPath!), recogDest)) {
      final ok = await _copyModel(File(sourced.recogPath!), recogDest);
      if (!ok) {
        debugPrint(
          'FaceModelPaths: could not copy recognizer into app support '
          '(sandbox). Source=${sourced.recogPath}',
        );
        return const FaceModelPaths();
      }
    }

    if (sourced.detPath != null) {
      final srcDet = File(sourced.detPath!);
      if (!_usableModelFile(detDest) || !_sameLength(srcDet, detDest)) {
        await _copyModel(srcDet, detDest);
      }
    }

    return FaceModelPaths(
      recogPath: _usableModelFile(recogDest) ? recogDest.path : null,
      detPath: _usableModelFile(detDest) ? detDest.path : null,
    );
  }

  static bool _usableModelFile(File f) =>
      f.existsSync() && f.lengthSync() >= _minRecogBytes;

  static bool _sameLength(File a, File b) {
    try {
      return a.existsSync() &&
          b.existsSync() &&
          a.lengthSync() == b.lengthSync();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _copyModel(File src, File dest) async {
    try {
      await src.copy(dest.path);
      return _usableModelFile(dest);
    } catch (e) {
      debugPrint('FaceModelPaths: File.copy failed ($e); trying read/write');
      try {
        final bytes = await src.readAsBytes();
        await dest.writeAsBytes(bytes, flush: true);
        return _usableModelFile(dest);
      } catch (e2) {
        debugPrint('FaceModelPaths: read/write copy failed: $e2');
        return false;
      }
    }
  }

  /// Whether recognizer weights look available (file candidates or bundled asset
  /// after a fetch — UI uses this as a soft hint; asset presence is confirmed at load).
  static bool recogModelAvailable() {
    for (final c in defaultModelCandidates(
      fileName: recogFileName,
      executablePath: Platform.resolvedExecutable,
    )) {
      if (File(c).existsSync()) return true;
    }
    final env = Platform.environment['TAGKIN_FACE_RECOG_MODEL'];
    return env != null && env.isNotEmpty && File(env).existsSync();
  }

  /// Candidate absolute paths for a model file (testable).
  @visibleForTesting
  static List<String> defaultModelCandidates({
    required String fileName,
    String? home,
    String? currentDir,
    String? executablePath,
    int maxWalkUp = 12,
  }) {
    final resolvedHome = home ??
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    final cwd = currentDir ?? Directory.current.path;
    final out = <String>[
      p.join(resolvedHome, 'Library', 'Application Support', 'tagkin', 'models',
          fileName),
      p.join(resolvedHome, 'AppData', 'Roaming', 'tagkin', 'models', fileName),
      p.join(cwd, 'assets', 'models', fileName),
      p.join('assets', 'models', fileName),
      ...walkUpForAssetsModels(
        executablePath ?? Platform.resolvedExecutable,
        fileName: fileName,
        maxLevels: maxWalkUp,
      ),
    ];
    return out;
  }

  /// Walk parent directories from [startPath] looking for `assets/models/[fileName]`.
  @visibleForTesting
  static List<String> walkUpForAssetsModels(
    String startPath, {
    String fileName = recogFileName,
    int maxLevels = 12,
  }) {
    if (startPath.isEmpty) return const [];
    var dir = startPath;
    try {
      final asFile = File(startPath);
      if (asFile.existsSync()) {
        dir = p.dirname(startPath);
      }
    } catch (_) {
      // Non-file path (tests) — treat as directory.
    }
    final out = <String>[];
    for (var i = 0; i < maxLevels; i++) {
      out.add(p.join(dir, 'assets', 'models', fileName));
      final parent = p.dirname(dir);
      if (parent == dir) break;
      dir = parent;
    }
    return out;
  }
}

/// ONNX Runtime face recognizer + optional SCRFD detector. Outputs 512-d L2 vectors.
class OnnxFaceEmbedder implements FaceEmbedder {
  OnnxFaceEmbedder._({
    required this._recog,
    this._det,
    required this.modelId,
  });

  final OrtSession _recog;
  final OrtSession? _det;
  final String modelId;

  /// SCRFD score floor; updated from [DesktopPrefs.facesDetectScoreThreshold].
  static double defaultDetectScoreThreshold = 0.2;

  static const int _inputSize = 112;
  static const int _detSize = 640;
  static const recogAssetKey = 'assets/models/w600k_r50.onnx';
  static const detAssetKey = 'assets/models/det_10g.onnx';

  /// Returns null when recognition weights are missing (caller may use stub).
  ///
  /// Prefers [OnnxRuntime.createSessionFromAsset] (sandbox-safe on macOS).
  /// Falls back to on-disk paths when assets are not bundled.
  static Future<OnnxFaceEmbedder?> tryCreate() async {
    if (kIsWeb) return null;
    try {
      final fromAsset = await _tryCreateFromAsset();
      if (fromAsset != null) return fromAsset;

      final paths = await FaceModelPaths.resolveForOrtSession();
      if (!paths.hasRecog) return null;
      final ort = OnnxRuntime();
      final recog = await ort.createSession(paths.recogPath!);
      OrtSession? det;
      if (paths.detPath != null && File(paths.detPath!).existsSync()) {
        try {
          det = await ort.createSession(paths.detPath!);
          debugPrint('OnnxFaceEmbedder: loaded det file ${paths.detPath}');
        } catch (e) {
          debugPrint('OnnxFaceEmbedder: det load failed: $e');
        }
      }
      debugPrint('OnnxFaceEmbedder: loaded file ${paths.recogPath}');
      return OnnxFaceEmbedder._(
        recog: recog,
        det: det,
        modelId: kOnnxArcfaceEmbeddingModelId,
      );
    } catch (e, st) {
      debugPrint('OnnxFaceEmbedder: tryCreate failed: $e\n$st');
      return null;
    }
  }

  static Future<OnnxFaceEmbedder?> _tryCreateFromAsset() async {
    try {
      final ort = OnnxRuntime();
      final recog = await ort.createSessionFromAsset(recogAssetKey);
      debugPrint('OnnxFaceEmbedder: loaded asset $recogAssetKey');
      OrtSession? det;
      try {
        det = await ort.createSessionFromAsset(detAssetKey);
        debugPrint('OnnxFaceEmbedder: loaded asset $detAssetKey');
      } catch (e) {
        debugPrint(
          'OnnxFaceEmbedder: det asset load failed ($detAssetKey): $e — '
          'align fallback to letterbox',
        );
      }
      return OnnxFaceEmbedder._(
        recog: recog,
        det: det,
        modelId: kOnnxArcfaceEmbeddingModelId,
      );
    } catch (e) {
      debugPrint(
        'OnnxFaceEmbedder: asset load failed ($recogAssetKey): $e — '
        'trying on-disk paths',
      );
      return null;
    }
  }

  @override
  Future<List<FaceAppearance>> embed(Uint8List bytes) async {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return const [];
    final aligned = await _tryAlignWithScrfd(decoded);
    if (aligned == null) {
      // #region agent log
      _agentLog('A', 'onnx_face_embedder.dart:embed', 'skip — no SCRFD face', {
        'cropW': decoded.width,
        'cropH': decoded.height,
        'modelId': modelId,
        'hasDet': _det != null,
      });
      // #endregion
      return const [];
    }
    return _embedAligned(aligned, alignMode: 'scrfd', src: decoded);
  }

  /// Full-frame SCRFD, constrained to the who [region], then ArcFace.
  ///
  /// Large VLM who-boxes are often torso/body; crop-level SCRFD misses and
  /// pseudo-align polluted the embedding space. Prefer full-image detection
  /// whose face center lies in the who region; fall back to crop SCRFD;
  /// never invent an embedding without a real face.
  Future<List<FaceAppearance>> embedWhoRegion(
    Uint8List fullImageBytes,
    TagRegion region,
  ) async {
    final decoded = img.decodeImage(fullImageBytes);
    if (decoded == null) return const [];

    final refined = TagRegion(
      yMin: region.yMin,
      xMin: region.xMin,
      yMax: region.yMax,
      xMax: region.xMax,
    );
    // Match who_face_linker light inset via caller — region already refined.

    img.Image? face112;
    var alignMode = 'none';

    final fullFaces = await _detectFaces(decoded);
    final inRegion = bestScrfdFaceInRegion(
      fullFaces,
      yMin: refined.yMin,
      xMin: refined.xMin,
      yMax: refined.yMax,
      xMax: refined.xMax,
      imgW: decoded.width,
      imgH: decoded.height,
    );
    if (inRegion != null) {
      face112 = normCropArcFace(decoded, inRegion.landmarks);
      alignMode = 'scrfd-full';
      // #region agent log
      _agentLog('B', 'onnx_face_embedder.dart:embedWhoRegion', 'full-frame', {
        'score': inRegion.score,
        'imgW': decoded.width,
        'imgH': decoded.height,
        'facesInFrame': fullFaces.length,
      });
      // #endregion
    } else {
      // Crop fallback (tight boxes where full-frame may miss tiny faces).
      final crop = _cropRegion(decoded, refined);
      if (crop != null) {
        final cropAligned = await _tryAlignWithScrfd(crop);
        if (cropAligned != null) {
          face112 = cropAligned;
          alignMode = 'scrfd-crop';
        }
      }
      // #region agent log
      _agentLog('B', 'onnx_face_embedder.dart:embedWhoRegion', 'no full-frame', {
        'facesInFrame': fullFaces.length,
        'cropFallback': face112 != null,
        'imgW': decoded.width,
        'imgH': decoded.height,
      });
      // #endregion
    }

    if (face112 == null) {
      // #region agent log
      _agentLog(
        'A',
        'onnx_face_embedder.dart:embedWhoRegion',
        'skip — no SCRFD face in who region',
        {
          'imgW': decoded.width,
          'imgH': decoded.height,
          'modelId': modelId,
        },
      );
      // #endregion
      return const [];
    }
    return _embedAligned(face112, alignMode: alignMode, src: decoded);
  }

  Future<List<FaceAppearance>> _embedAligned(
    img.Image face112, {
    required String alignMode,
    required img.Image src,
  }) async {
    // #region agent log
    _agentLog('A', 'onnx_face_embedder.dart:_embedAligned', 'preprocess', {
      'srcW': src.width,
      'srcH': src.height,
      'alignMode': alignMode,
      'modelId': modelId,
      'hasDet': _det != null,
    });
    // #endregion

    final input = _toNchwFloat(face112);
    final inputName = _recog.inputNames.isNotEmpty
        ? _recog.inputNames.first
        : 'data';
    final tensor = await OrtValue.fromList(
      input.toList(),
      [1, 3, _inputSize, _inputSize],
    );
    final outputs = await _recog.run({inputName: tensor});
    await tensor.dispose();

    final outName = _recog.outputNames.isNotEmpty
        ? _recog.outputNames.first
        : outputs.keys.first;
    final out = outputs[outName];
    if (out == null) return const [];
    final list = await out.asList();
    await out.dispose();

    final flat = <double>[];
    void flatten(dynamic v) {
      if (v is num) {
        flat.add(v.toDouble());
      } else if (v is List) {
        for (final e in v) {
          flatten(e);
        }
      }
    }

    flatten(list);
    if (flat.length < kFaceEmbeddingDim) {
      debugPrint(
        'OnnxFaceEmbedder: expected $kFaceEmbeddingDim-d, got ${flat.length}',
      );
      return const [];
    }
    final embedding = flat.sublist(0, kFaceEmbeddingDim);
    _l2Normalize(embedding);
    return [
      FaceAppearance(embedding: embedding, embeddingModelId: modelId),
    ];
  }

  static img.Image? _cropRegion(img.Image decoded, TagRegion region) {
    final w = decoded.width;
    final h = decoded.height;
    if (w <= 0 || h <= 0) return null;
    var left = (region.xMin * w).floor();
    var top = (region.yMin * h).floor();
    var right = (region.xMax * w).ceil();
    var bottom = (region.yMax * h).ceil();
    left = left.clamp(0, w - 1);
    top = top.clamp(0, h - 1);
    right = right.clamp(left + 1, w);
    bottom = bottom.clamp(top + 1, h);
    final cropW = right - left;
    final cropH = bottom - top;
    if (cropW < 8 || cropH < 8) return null;
    return img.copyCrop(
      decoded,
      x: left,
      y: top,
      width: cropW,
      height: cropH,
    );
  }

  Future<img.Image?> _tryAlignWithScrfd(img.Image crop) async {
    final faces = await _detectFaces(crop);
    final best = bestScrfdFace(faces);
    if (best == null) {
      // #region agent log
      _agentLog('B', 'onnx_face_embedder.dart:_tryAlignWithScrfd', 'no face', {
        'cropW': crop.width,
        'cropH': crop.height,
      });
      // #endregion
      return null;
    }
    // #region agent log
    _agentLog('B', 'onnx_face_embedder.dart:_tryAlignWithScrfd', 'aligned', {
      'score': best.score,
      'cropW': crop.width,
      'cropH': crop.height,
    });
    // #endregion
    return normCropArcFace(crop, best.landmarks);
  }

  Future<List<ScrfdFace>> _detectFaces(img.Image image) async {
    final det = _det;
    if (det == null) return const [];
    try {
      final packed = letterboxForScrfd(image, detSize: _detSize);
      final blob = scrfdBlobNchw(packed.detImg);
      final inputName =
          det.inputNames.isNotEmpty ? det.inputNames.first : 'input.1';
      final tensor = await OrtValue.fromList(
        blob.toList(),
        [1, 3, _detSize, _detSize],
      );
      final outputs = await det.run({inputName: tensor});
      await tensor.dispose();

      final raw = <({Float32List data, List<int> shape})>[];
      final names = det.outputNames;
      for (final name in names) {
        final v = outputs[name];
        if (v == null) {
          for (final o in outputs.values) {
            await o.dispose();
          }
          return const [];
        }
        raw.add(await _ortToFloat32Shaped(v));
        await v.dispose();
      }

      // #region agent log
      _agentLog('D', 'onnx_face_embedder.dart:_detectFaces', 'det outs', {
        'names': names,
        'shapes': [for (final r in raw) r.shape.join('x')],
        'imgW': image.width,
        'imgH': image.height,
      });
      // #endregion

      final ordered = orderScrfdOutputsByShape(raw, detSize: _detSize);
      if (ordered == null) {
        debugPrint(
          'OnnxFaceEmbedder: could not classify det outputs by shape '
          '(names=$names shapes=${[for (final r in raw) r.shape]})',
        );
        return const [];
      }

      return decodeScrfdOutputs(
        netOuts: ordered,
        inputHeight: _detSize,
        inputWidth: _detSize,
        detScale: packed.detScale,
        threshold: defaultDetectScoreThreshold,
      );
    } catch (e, st) {
      debugPrint('OnnxFaceEmbedder: SCRFD detect failed: $e\n$st');
      return const [];
    }
  }

  static Future<({Float32List data, List<int> shape})> _ortToFloat32Shaped(
    OrtValue v,
  ) async {
    final list = await v.asList();
    final shape = _inferListShape(list);
    final flat = <double>[];
    void flatten(dynamic x) {
      if (x is num) {
        flat.add(x.toDouble());
      } else if (x is List) {
        for (final e in x) {
          flatten(e);
        }
      }
    }

    flatten(list);
    return (data: Float32List.fromList(flat), shape: shape);
  }

  static List<int> _inferListShape(dynamic list) {
    if (list is! List) return const [];
    if (list.isEmpty) return const [0];
    if (list.first is num) return [list.length];
    if (list.first is List) {
      return [list.length, ..._inferListShape(list.first)];
    }
    return [list.length];
  }

  /// InsightFace buffalo_l: (x − 127.5) / 127.5, NCHW RGB.
  static Float32List _toNchwFloat(img.Image image) {
    const mean = 127.5;
    const std = 127.5;
    final out = Float32List(3 * _inputSize * _inputSize);
    var i = 0;
    for (var y = 0; y < _inputSize; y++) {
      for (var x = 0; x < _inputSize; x++) {
        final pixel = image.getPixel(x, y);
        out[i] = (pixel.r - mean) / std;
        out[i + _inputSize * _inputSize] = (pixel.g - mean) / std;
        out[i + 2 * _inputSize * _inputSize] = (pixel.b - mean) / std;
        i++;
      }
    }
    return out;
  }

  static void _l2Normalize(List<double> v) {
    var sum = 0.0;
    for (final x in v) {
      sum += x * x;
    }
    final norm = math.sqrt(sum);
    if (norm == 0) return;
    for (var i = 0; i < v.length; i++) {
      v[i] = v[i] / norm;
    }
  }

  Future<void> dispose() async {
    await _recog.close();
    await _det?.close();
  }
}

/// Tries ONNX once, then falls back to [StubFaceEmbedder] when weights missing.
class LazyOnnxOrStubFaceEmbedder implements FaceEmbedder {
  FaceEmbedder? _inner;
  Future<FaceEmbedder>? _loading;

  /// Resolve the concrete embedder (ONNX or stub). Used by who-face linking
  /// so it can call [OnnxFaceEmbedder.embedWhoRegion] when available.
  Future<FaceEmbedder> ensureLoaded() => _ensure();

  Future<FaceEmbedder> _ensure() {
    if (_inner != null) return Future.value(_inner!);
    return _loading ??= () async {
      try {
        final onnx = await OnnxFaceEmbedder.tryCreate();
        _inner = onnx ?? StubFaceEmbedder();
        if (onnx == null) {
          markFaceEmbedderStubFallback();
          debugPrint(
            'FaceEmbedder: ONNX unavailable (missing models or sandbox load '
            'failed) — using stub. Run mac/117_fetch_face_models.sh, fully '
            'restart the app, then re-analyze.',
          );
        }
      } catch (e, st) {
        debugPrint('FaceEmbedder: ONNX init failed, using stub: $e\n$st');
        markFaceEmbedderStubFallback();
        _inner = StubFaceEmbedder();
      }
      return _inner!;
    }();
  }

  @override
  Future<List<FaceAppearance>> embed(Uint8List bytes) async {
    final inner = await _ensure();
    return inner.embed(bytes);
  }
}
