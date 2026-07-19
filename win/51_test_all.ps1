# 51_test_all.ps1 — Run every completed desktop subsystem regression bar (NNN_test_dN.ps1) in order.
# New NNN_test_dN.ps1 scripts are picked up automatically. Band 51-99 = all-inclusive test orchestrators.
$ErrorActionPreference = 'Stop'
$winDir = Split-Path -Parent $PSCommandPath
. (Join-Path $winDir '_env.ps1')

# Three-digit subsystem bars only (101+) — excludes this 51_test_all.ps1 orchestrator.
$bars = Get-ChildItem -Path $winDir -Filter '???_test_d*.ps1' | Sort-Object Name
if ($bars.Count -eq 0) {
  Write-Error "no NNN_test_dN.ps1 scripts found in $winDir"
}

Write-Host "==> all desktop subsystem regressions ($($bars.Count) bar(s))"
foreach ($bar in $bars) {
  Write-Host ''
  Write-Host "==> $($bar.Name)"
  & $bar.FullName
}

Write-Host ''
Write-Host '==> all desktop subsystem regressions complete'
