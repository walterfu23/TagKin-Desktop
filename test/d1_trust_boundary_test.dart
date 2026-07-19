import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// D1 §5 mandatory assertion 3 + R8: no long-lived secret / Clerk secret key
/// in client source. Publishable `pk_` keys are allowed; `sk_` are not.
void main() {
  test('lib/ never embeds CLERK_SECRET_KEY or sk_test_/sk_live_ (R8)', () {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue);

    final offenders = <String>[];
    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains('CLERK_SECRET_KEY') ||
          source.contains('sk_test_') ||
          source.contains('sk_live_') ||
          source.contains('GEMINI_API_KEY') ||
          RegExp(r'AIza[0-9A-Za-z\-_]{20,}').hasMatch(source)) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty, reason: 'secret patterns in: $offenders');
  });

  test('SecureStoragePersistor is the session store — no SharedPreferences token path',
      () {
    final lib = Directory('lib');
    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      expect(
        source.contains('SharedPreferences'),
        isFalse,
        reason: '${entity.path} must not use SharedPreferences for auth',
      );
      expect(
        source.contains('DefaultPersistor'),
        isFalse,
        reason: '${entity.path} must not use plaintext DefaultPersistor',
      );
    }
  });
}
