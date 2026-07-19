#!/usr/bin/env bash
# 102_codegen.sh — regenerate Dart contract models from the shared @tagkin/contract OpenAPI.
# The OpenAPI document is the single source of truth (R2); Dart models are generated, not hand-written.
set -euo pipefail
# shellcheck source=_env.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_env.sh"

# Sibling tagkin repo holds the canonical contract (see System_Design §2).
OPENAPI="${TAGKIN_DESKTOP_ROOT}/../TagKin/packages/contract/openapi/openapi.yaml"
if [[ ! -f "${OPENAPI}" ]]; then
  echo "error: contract OpenAPI not found at ${OPENAPI}" >&2
  echo "       Ensure the sibling tagkin repo is checked out next to tagkin-desktop." >&2
  exit 1
fi
echo "==> using contract: ${OPENAPI}"

# Deterministic Dart model generator (tool/gen_contract.dart) reads the contract
# directly and emits lib/contract/contract.dart. Output is stable so 106_test_d0
# can gate drift via git-diff.
export TAGKIN_OPENAPI="${OPENAPI}"
echo "==> dart run tool/gen_contract.dart"
dart run tool/gen_contract.dart
echo "==> codegen complete"
