import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/persons/who_face_linker.dart';

/// Shared decode-once/crop-many + LRU cache for Faces tray crop thumbnails.
///
/// Without this, every face thumb independently re-reads and re-decodes the
/// full-resolution source photo — a photo with 5 faces was hashed, read, and
/// fully decoded 5 separate times, on every mount. Requests for the same
/// `(itemId, contentHash)` arriving in the same build pass (siblings on one
/// photo) are coalesced into a single file read + one background-isolate
/// decode; results are cached per crop region so repeat mounts are instant.
class FaceCropCache {
  FaceCropCache._();

  static final FaceCropCache instance = FaceCropCache._();

  /// Bounded so long Faces sessions don't grow memory unbounded.
  static const int maxEntries = 400;

  /// Cap on concurrent file decodes — many faces mounting at once (e.g. a
  /// non-lazy tray grid) must not spawn hundreds of simultaneous isolate
  /// decodes / file reads.
  static const int maxConcurrentBatches = 6;

  final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();
  final Map<String, _FileBatch> _pendingFileBatches = {};
  final Queue<_FileBatch> _queuedBatches = Queue();
  int _runningBatches = 0;

  static String _fileKey(String itemId, String? contentHash) =>
      '$itemId:${contentHash ?? ''}';

  static String _regionKey(TagRegion r) =>
      '${r.yMin.toStringAsFixed(5)},${r.xMin.toStringAsFixed(5)},'
      '${r.yMax.toStringAsFixed(5)},${r.xMax.toStringAsFixed(5)}';

  static String _cropKey(String fileKey, TagRegion region) =>
      '$fileKey|${_regionKey(region)}';

  /// Already-decoded crop, if any — synchronous, safe to call from `build()`.
  Uint8List? peek({
    required String itemId,
    required String? contentHash,
    required TagRegion region,
  }) => _cache[_cropKey(_fileKey(itemId, contentHash), region)];

  /// Resolves a face crop, coalescing concurrent requests for the same photo
  /// (by `itemId` + `contentHash`) into one file read + one decode.
  ///
  /// [loadFileBytes] is only invoked for the first request that starts a new
  /// batch for that file — later joiners reuse its result.
  Future<Uint8List?> getOrCropFace({
    required String itemId,
    required String? contentHash,
    required TagRegion region,
    required Future<Uint8List> Function() loadFileBytes,
  }) {
    final fileKey = _fileKey(itemId, contentHash);
    final cropKey = _cropKey(fileKey, region);
    final cached = _cache.remove(cropKey);
    if (cached != null) {
      _cache[cropKey] = cached; // move to MRU position
      return Future.value(cached);
    }

    var batch = _pendingFileBatches[fileKey];
    final isNewBatch = batch == null;
    batch ??= _FileBatch(fileKey: fileKey, loadFileBytes: loadFileBytes);
    _pendingFileBatches[fileKey] = batch;
    final completer = Completer<Uint8List?>();
    batch.requests.add(_PendingCrop(region, completer));

    if (isNewBatch) {
      // Let same-turn sibling requests (other faces on this photo) join the
      // batch before it fires — Flutter builds a frame's widgets synchronously,
      // so sibling thumb loaders call in before the first microtask runs.
      scheduleMicrotask(() => _enqueue(batch!));
    }
    return completer.future;
  }

  void _enqueue(_FileBatch batch) {
    _pendingFileBatches.remove(batch.fileKey);
    _queuedBatches.add(batch);
    _pumpQueue();
  }

  void _pumpQueue() {
    while (_runningBatches < maxConcurrentBatches &&
        _queuedBatches.isNotEmpty) {
      final batch = _queuedBatches.removeFirst();
      _runningBatches++;
      unawaited(
        _runBatch(batch).whenComplete(() {
          _runningBatches--;
          _pumpQueue();
        }),
      );
    }
  }

  Future<void> _runBatch(_FileBatch batch) async {
    final requests = batch.requests;
    try {
      final bytes = await batch.loadFileBytes();
      var crops = await compute(
        cropManyWhoFacesJpeg,
        FaceCropBatchRequest(
          imageBytes: bytes,
          regions: [for (final r in requests) r.region],
        ),
      );
      if (crops.every((c) => c == null)) {
        // package:image couldn't decode this file at all (e.g. HEIC) — retry
        // once on the main isolate via the Flutter engine codec.
        crops = await cropManyWhoFacesJpegAsync(bytes, [
          for (final r in requests) r.region,
        ]);
      }
      for (var i = 0; i < requests.length; i++) {
        final crop = crops[i];
        if (crop != null) {
          _store(_cropKey(batch.fileKey, requests[i].region), crop);
        }
        if (!requests[i].completer.isCompleted) {
          requests[i].completer.complete(crop);
        }
      }
    } catch (e, st) {
      for (final r in requests) {
        if (!r.completer.isCompleted) r.completer.completeError(e, st);
      }
    }
  }

  void _store(String key, Uint8List bytes) {
    _cache[key] = bytes;
    if (_cache.length > maxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Test/debug hook — clears cached crops and drops in-flight coalescing
  /// state (in-flight requests still resolve normally).
  void clear() {
    _cache.clear();
  }
}

class _PendingCrop {
  _PendingCrop(this.region, this.completer);

  final TagRegion region;
  final Completer<Uint8List?> completer;
}

class _FileBatch {
  _FileBatch({required this.fileKey, required this.loadFileBytes});

  final String fileKey;
  final Future<Uint8List> Function() loadFileBytes;
  final List<_PendingCrop> requests = [];
}
