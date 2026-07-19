import 'dart:io';

import 'package:flutter/foundation.dart';

/// Runtime config for D1+ (Clerk publishable key + tagkin-api base URL).
///
/// Load order: `--dart-define` → [Platform.environment] → optional `.env` file.
/// Process env is preferred because a sandboxed macOS `.app` cannot read the
/// repo-root `.env` (PathAccessException). `mac/11_dev.sh` / `win/11_dev.ps1`
/// export the keys before `flutter run`. Never holds a Clerk secret (R8).
@immutable
class AppConfig {
  const AppConfig({
    required this.apiUrl,
    this.clerkPublishableKey,
  });

  /// tagkin-api base URL (no trailing slash).
  final String apiUrl;

  /// Clerk publishable key (`pk_test_…` / `pk_live_…`). Null when unset.
  final String? clerkPublishableKey;

  bool get hasClerkKey =>
      clerkPublishableKey != null && clerkPublishableKey!.trim().isNotEmpty;

  static const String defaultApiUrl = 'http://localhost:8787';

  /// Load config for the running process.
  factory AppConfig.load({String? envFilePath}) {
    // File read is best-effort: sandboxed macOS builds cannot open the repo
    // `.env` and must not crash (see PathAccessException).
    final fileValues = _readDotEnvSafe(envFilePath ?? _discoverEnvPath());

    String? lookup(String key) {
      const defines = <String, String>{
        'CLERK_PUBLISHABLE_KEY': String.fromEnvironment('CLERK_PUBLISHABLE_KEY'),
        'TAGKIN_API_URL': String.fromEnvironment('TAGKIN_API_URL'),
      };
      final fromDefine = defines[key];
      if (fromDefine != null && fromDefine.isNotEmpty) return fromDefine;

      // Prefer process env over file — works under App Sandbox when 11_dev exports.
      final fromPlatform = Platform.environment[key];
      if (fromPlatform != null && fromPlatform.isNotEmpty) return fromPlatform;

      final fromFile = fileValues[key];
      if (fromFile != null && fromFile.isNotEmpty) return fromFile;
      return null;
    }

    final rawUrl = lookup('TAGKIN_API_URL') ?? defaultApiUrl;
    return AppConfig(
      apiUrl: rawUrl.replaceAll(RegExp(r'/+$'), ''),
      clerkPublishableKey: lookup('CLERK_PUBLISHABLE_KEY'),
    );
  }
}

/// Prefer an explicit `.env` next to `pubspec.yaml` (package root).
String? _discoverEnvPath() {
  try {
    for (final start in <Directory>[
      Directory.current,
      File(Platform.resolvedExecutable).parent,
    ]) {
      var dir = start;
      for (var i = 0; i < 12; i++) {
        final env = File('${dir.path}${Platform.pathSeparator}.env');
        final pubspec = File('${dir.path}${Platform.pathSeparator}pubspec.yaml');
        try {
          if (env.existsSync() && pubspec.existsSync()) {
            return env.path;
          }
          if (env.existsSync()) {
            return env.path;
          }
        } on FileSystemException {
          // Sandbox / permission — keep walking or give up.
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }
    final fallback = File('.env');
    if (fallback.existsSync()) return fallback.path;
  } on FileSystemException {
    return null;
  }
  return null;
}

Map<String, String> _readDotEnvSafe(String? path) {
  if (path == null) return const {};
  try {
    final file = File(path);
    if (!file.existsSync()) return const {};
    final out = <String, String>{};
    for (final raw in file.readAsLinesSync()) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final key = line.substring(0, eq).trim();
      var value = line.substring(eq + 1).trim();
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }
      out[key] = value;
    }
    return out;
  } on FileSystemException {
    return const {};
  }
}
