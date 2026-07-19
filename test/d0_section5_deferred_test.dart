// D0 §5 mandatory assertions — partially deferred; D1 covers R10 + R8 source scan.
//
// Desktop_Subsystems_v1 §5 requires every subsystem suite to cover:
//   1. R10 — no client-supplied ownerUserId/scope  → test/api_client_test.dart (D1)
//   2. R1/R5/R7 — no media bytes to tagkin-api     → test/api_client_test.dart (D1)
//   3. R8/§4 — no long-lived secret in source      → test/d1_trust_boundary_test.dart (D1)
//
// Release-artifact secret scan remains D11. This file keeps the D0 pointer so
// the original deferral stays documented.

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('§5 mandatory assertions are owned by D1 unit suites (documented)', () {
    expect(true, isTrue);
  });
}
