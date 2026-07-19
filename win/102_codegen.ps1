# 102_codegen.ps1 — regenerate Dart contract models from the shared @tagkin/contract OpenAPI.
# The OpenAPI document is the single source of truth (R2); Dart models are generated, not hand-written.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSCommandPath) '_env.ps1')

# Sibling tagkin repo holds the canonical contract (see System_Design §2).
$openapi = Join-Path $global:TagKinDesktopRoot '..\TagKin\packages\contract\openapi\openapi.yaml'
if (-not (Test-Path $openapi)) {
  Write-Error "contract OpenAPI not found at $openapi. Ensure the sibling tagkin repo is checked out next to tagkin-desktop."
}
$openapi = (Resolve-Path $openapi).Path
Write-Host "==> using contract: $openapi"

# Deterministic Dart model generator (tool/gen_contract.dart) reads the contract
# directly and emits lib/contract/contract.dart. Output is stable so 106_test_d0
# can gate drift via git-diff.
$env:TAGKIN_OPENAPI = $openapi
Write-Host '==> dart run tool/gen_contract.dart'
dart run tool/gen_contract.dart
Write-Host '==> codegen complete'
