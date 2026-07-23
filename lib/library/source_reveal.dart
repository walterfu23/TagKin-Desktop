import 'dart:io';

import 'package:tagkin_desktop/review/local_media_resolver.dart';

/// Reveals [sourceRef] in the OS file manager (Finder / Explorer).
///
/// Returns false when the path cannot be resolved or the reveal command fails.
Future<bool> revealSourceRef(String? sourceRef) async {
  final path = localPathFromSourceRef(sourceRef);
  if (path == null || path.isEmpty) return false;
  return revealLocalPath(path);
}

/// Reveals an absolute [path] in Finder (macOS) or Explorer (Windows).
Future<bool> revealLocalPath(String path) async {
  try {
    if (Platform.isMacOS) {
      final result = await Process.run('open', ['-R', path]);
      return result.exitCode == 0;
    }
    if (Platform.isWindows) {
      // explorer /select,<path> — comma is part of the switch syntax.
      final result = await Process.run('explorer', ['/select,$path']);
      // Explorer often returns non-zero even on success; treat spawn as ok.
      return result.exitCode == 0 || result.exitCode == 1;
    }
    // Linux / other: open containing directory.
    final parent = File(path).parent.path;
    final result = await Process.run('xdg-open', [parent]);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}
