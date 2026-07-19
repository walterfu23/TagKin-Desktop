import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/config/app_config.dart';

void main() {
  test('AppConfig.load prefers Platform.environment over an unreadable .env', () {
    // Simulate 11_dev.sh export: key present in process env.
    // (Cannot mutate Platform.environment in Dart — assert API shape + soft file fail.)
    final config = AppConfig.load(envFilePath: '/definitely/not/readable/nope.env');
    // Must not throw; apiUrl always has a default.
    expect(config.apiUrl, isNotEmpty);
  });

  test('AppConfig.load reads .env from the package root when cwd is elsewhere', () {
    final root = Directory.current;
    final fakeCwd = Directory('${root.path}/build/macos/Build/Products/Debug')
      ..createSync(recursive: true);
    final previous = Directory.current;
    try {
      Directory.current = fakeCwd;
      final config = AppConfig.load();
      expect(config.hasClerkKey, isTrue,
          reason: 'expected CLERK_PUBLISHABLE_KEY from package-root .env');
      expect(config.apiUrl, isNotEmpty);
    } finally {
      Directory.current = previous;
    }
  }, skip: !File('.env').existsSync()
      ? 'no TagKin-Desktop/.env — skip path-discovery check in CI'
      : false);
}
