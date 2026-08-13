# 12_person_link_loop.ps1 — Delete suggested persons, re-analyze N photos, check
# Persons consolidation; repeat up to TAGKIN_LOOP_MAX (default 20).
# Mirror of mac/12_person_link_loop.sh.
#
# Required env:
#   TAGKIN_API_TOKEN       Bearer JWT from a logged-in desktop/API session
#   TAGKIN_LOOP_ITEM_IDS   comma-separated photo item UUIDs (typically 3)
#
# Optional:
#   TAGKIN_API_URL                    default http://localhost:8787
#   TAGKIN_LOOP_MAX                   default 20
#
# Prerequisites: API stack up, Gemini configured, face ONNX via 119_fetch_face_models.ps1.
# Does not confirm persons (R6). Never commits tokens.
$ErrorActionPreference = 'Stop'
$winDir = Split-Path -Parent $PSCommandPath
. (Join-Path $winDir '_env.ps1')

if (-not $env:TAGKIN_API_TOKEN) {
  Write-Error 'TAGKIN_API_TOKEN is required (Bearer JWT).'
}
if (-not $env:TAGKIN_LOOP_ITEM_IDS) {
  Write-Error 'TAGKIN_LOOP_ITEM_IDS is required (comma-separated item UUIDs).'
}

if (-not $env:TAGKIN_API_URL) { $env:TAGKIN_API_URL = 'http://localhost:8787' }
$max = if ($env:TAGKIN_LOOP_MAX) { [int]$env:TAGKIN_LOOP_MAX } else { 20 }

Write-Host "==> person link loop (max $max iterations)"
Write-Host "    API=$($env:TAGKIN_API_URL)"
Write-Host "    items=$($env:TAGKIN_LOOP_ITEM_IDS)"
Write-Host "    success=cross-item person covering all items"

for ($i = 1; $i -le $max; $i++) {
  Write-Host ""
  Write-Host "======== iteration $i / $max ========"
  $log = Join-Path $env:TEMP ("tagkin_person_link_loop_log_" + [guid]::NewGuid().ToString() + ".txt")
  $flutterEc = 0
  try {
    flutter run -d windows -t tool/person_link_loop.dart --quiet 2>&1 |
      Tee-Object -FilePath $log
    $flutterEc = $LASTEXITCODE
  } catch {
    $flutterEc = 1
  }

  $status = 'missing-status'
  if (Test-Path $log) {
    $text = Get-Content $log -Raw
    if ($text -match 'PERSON_LINK_LOOP_RESULT:ok') {
      $status = ([regex]::Matches($text, 'PERSON_LINK_LOOP_RESULT:ok.*') | Select-Object -Last 1).Value
    } elseif ($text -match 'PERSON_LINK_LOOP_RESULT:fail') {
      $status = ([regex]::Matches($text, 'PERSON_LINK_LOOP_RESULT:fail.*') | Select-Object -Last 1).Value
    } elseif ($text -match 'PERSON_LINK_LOOP_RESULT:error') {
      $status = ([regex]::Matches($text, 'PERSON_LINK_LOOP_RESULT:error.*') | Select-Object -Last 1).Value
    }
    Remove-Item $log -ErrorAction SilentlyContinue
  }

  Write-Host "    status: $status (flutter_exit=$flutterEc)"

  if ($status -like 'PERSON_LINK_LOOP_RESULT:ok*' -or $status -like 'ok*') {
    Write-Host "==> SUCCESS on iteration $i"
    exit 0
  }

  if ($status -like 'PERSON_LINK_LOOP_RESULT:error*' -or $status -like 'error*' -or $status -eq 'missing-status') {
    Write-Error @"
hard error on iteration $i — stopping
    tip: token expires ~60s — re-export TAGKIN_API_TOKEN, re-run.
"@
  }

  Write-Host "==> iteration $i did not consolidate — continuing"
  Write-Host "    tip: if the next iter 401s, refresh TAGKIN_API_TOKEN first."
}

Write-Error "gave up after $max iterations"
