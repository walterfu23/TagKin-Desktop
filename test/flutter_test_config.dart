import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/persons/face_crop_cache.dart';
import 'package:tagkin_desktop/persons/who_face_crop_thumb.dart';

/// Widget tests render face thumbs with no local media on purpose; skip the
/// per-thumb "media missing" line so real failures stand out in the log.
/// The person-face memo is a process-wide singleton, so clear it per test or a
/// later test paints (and fetches) an earlier test's fixture face.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  logMediaUnavailable = false;
  setUp(PersonAppearanceMemo.instance.clear);
  await testMain();
}
