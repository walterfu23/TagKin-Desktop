import 'dart:io';

import 'package:flutter/foundation.dart';

/// Runtime config for D1+ (Clerk publishable key + tagkin-api base URL).
///
/// Loads from (later overrides earlier): compile-time `--dart-define`, optional
/// `.env` next to the process cwd, then [Platform.environment]. Never holds a
/// Clerk secret key (R8) — only the publishable `pk_` key is allowed client-side.
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
    final fileValues = _readDotEnv(envFilePath ?? '.env');
    String? lookup(String key) {
      const defines = <String, String>{
        'CLERK_PUBLISHABLE_KEY': String.fromEnvironment('CLERK_PUBLISHABLE_KEY'),
        'TAGKIN_API_URL': String.fromEnvironment('TAGKIN_API_URL'),
      };
      final fromDefine = defines[key];
      if (fromDefine != null && fromDefine.isNotEmpty) return fromDefine;
      final fromFile = fileValues[key];
      if (fromFile != null && fromFile.isNotEmpty) return fromFile;
      final fromPlatform = Platform.environment[key];
      if (fromPlatform != null && fromPlatform.isNotEmpty) return fromPlatform;
      return null;
    }

    final rawUrl = lookup('TAGKIN_API_URL') ?? defaultApiUrl;
    return AppConfig(
      apiUrl: rawUrl.replaceAll(RegExp(r'/+$'), ''),
      clerkPublishableKey: lookup('CLERK_PUBLISHABLE_KEY'),
    );
  }
}

Map<String, String> _readDotEnv(String path) {
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
}
