import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Runtime identity sent as `X-TagKin-Client`.
///
/// Version comes from the installed bundle (`package_info_plus`) so it still
/// matches after Sparkle/MSIX replaces the binary. Not a security boundary.
@immutable
class ClientIdentity {
  const ClientIdentity({
    required this.version,
    required this.platform,
  });

  /// Semver from the bundle, including `+build` when present (`1.0.0+1`).
  final String version;

  /// `macos` / `windows` / `test`.
  final String platform;

  static const testFallback = ClientIdentity(
    version: '1.0.0+1',
    platform: 'test',
  );

  String get headerValue => 'tagkin-desktop/$version ($platform)';

  static Future<ClientIdentity> fromPlatform() async {
    final info = await PackageInfo.fromPlatform();
    final build = info.buildNumber.trim();
    final version =
        build.isEmpty ? info.version : '${info.version}+$build';
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      _ => defaultTargetPlatform.name.toLowerCase(),
    };
    return ClientIdentity(version: version, platform: platform);
  }
}
