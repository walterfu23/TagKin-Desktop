import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// D6 §5 / R8: no long-lived provider key or secret in D6-owned source.
void main() {
  test('usage lib sources contain no provider key / secret patterns (R8)', () {
    final roots = [
      Directory('lib/usage'),
      Directory('lib/api'),
    ];
    final pattern = RegExp(
      r'sk_test_|sk_live_|CLERK_SECRET_KEY|GEMINI_API_KEY|AIza[0-9A-Za-z_-]{20,}',
    );
    final hits = <String>[];
    for (final root in roots) {
      if (!root.existsSync()) continue;
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final text = entity.readAsStringSync();
        if (pattern.hasMatch(text)) {
          hits.add(entity.path);
        }
      }
    }
    expect(hits, isEmpty, reason: 'secret patterns in: $hits');
  });

  test('UsageRepository / UsageGate implement no server-only cost logic', () {
    final gate = File('lib/usage/usage_gate.dart').readAsStringSync();
    final repo = File('lib/api/usage_repository.dart').readAsStringSync();
    // Client must not estimate frames × model tier or mint grants.
    expect(gate.contains('estimateCost'), isFalse);
    expect(gate.contains('reserve('), isFalse);
    expect(repo.contains('estimateCost'), isFalse);
    expect(repo.contains('mintUpload'), isFalse);
  });
}
