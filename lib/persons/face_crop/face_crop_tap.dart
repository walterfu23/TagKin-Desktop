import 'package:flutter/gestures.dart';

/// Resolves Finder-style single vs double click without [GestureDetector.onDoubleTap]
/// (that delays [onTap] and breaks [WidgetTester.pumpAndSettle] / immediate select chrome).
class FaceCropTapTracker {
  String? _lastId;
  DateTime? _lastAt;

  /// Returns true if this tap is the second click of a double-click on [id].
  bool registerTap(String id) {
    final now = DateTime.now();
    if (_lastId == id &&
        _lastAt != null &&
        now.difference(_lastAt!) < kDoubleTapTimeout) {
      _lastId = null;
      _lastAt = null;
      return true;
    }
    _lastId = id;
    _lastAt = now;
    return false;
  }

  void clear() {
    _lastId = null;
    _lastAt = null;
  }
}
