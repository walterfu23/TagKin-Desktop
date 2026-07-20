import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves `ffmpeg` / `ffprobe` for D4 video pre-pass.
///
/// **Installed apps** must ship these binaries inside the bundle — end users
/// are never asked to install ffmpeg via Homebrew/winget/etc.
///
/// Lookup order:
/// 1. App-bundled paths next to / relative to [Platform.resolvedExecutable]
/// 2. PATH (`ffmpeg` / `ffprobe`) — local `flutter run` / CI only
class FfmpegTools {
  const FfmpegTools({required this.ffmpeg, required this.ffprobe});

  final String ffmpeg;
  final String ffprobe;
}

/// Cached resolution (process lifetime).
FfmpegTools? _cached;

/// Clears the cache (tests only).
void clearFfmpegToolsCache() => _cached = null;

/// True when both tools resolve and respond to `-version`.
bool hasFfmpeg() {
  final tools = resolveFfmpegTools();
  if (tools == null) return false;
  return _versionOk(tools.ffprobe) && _versionOk(tools.ffmpeg);
}

/// Returns bundled/PATH tools, or `null` when neither is available.
FfmpegTools? resolveFfmpegTools() {
  final cached = _cached;
  if (cached != null) return cached;

  final ffmpeg = _resolveBinary('ffmpeg');
  final ffprobe = _resolveBinary('ffprobe');
  if (ffmpeg == null || ffprobe == null) return null;

  final tools = FfmpegTools(ffmpeg: ffmpeg, ffprobe: ffprobe);
  _cached = tools;
  return tools;
}

String? _resolveBinary(String name) {
  final exeName = Platform.isWindows ? '$name.exe' : name;
  for (final candidate in _bundledCandidates(exeName)) {
    if (_isRunnable(candidate)) return candidate;
  }
  // Dev/CI fallback only — never required of end users.
  if (_versionOk(name)) return name;
  return null;
}

/// Locations inside a packaged macOS `.app` or Windows install dir.
List<String> _bundledCandidates(String exeName) {
  final exe = File(Platform.resolvedExecutable);
  final exeDir = exe.parent.path;
  final ctx = p.context;
  final out = <String>[];

  // Next to the executable (Windows layout; also macOS Contents/MacOS).
  out.add(ctx.join(exeDir, exeName));
  out.add(ctx.join(exeDir, 'ffmpeg', exeName));

  if (Platform.isMacOS) {
    // tagkin_desktop.app/Contents/MacOS/… → Contents/Resources/ffmpeg/…
    final contents = ctx.normalize(ctx.join(exeDir, '..'));
    out.add(ctx.join(contents, 'Resources', 'ffmpeg', exeName));
    out.add(ctx.join(contents, 'Helpers', exeName));
  }

  if (Platform.isWindows) {
    out.add(ctx.join(exeDir, 'data', 'ffmpeg', exeName));
  }

  return out;
}

bool _isRunnable(String path) {
  try {
    final f = File(path);
    if (!f.existsSync()) return false;
    return _versionOk(path);
  } catch (_) {
    return false;
  }
}

bool _versionOk(String executable) {
  try {
    final result = Process.runSync(
      executable,
      ['-version'],
      runInShell: false,
    );
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}
