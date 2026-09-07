# 120_branding.ps1 — regenerate user-facing name + icons from branding/.
# Native icons need a full relaunch (not hot restart).
$ErrorActionPreference = 'Stop'
$winDir = Split-Path -Parent $PSCommandPath
. (Join-Path $winDir '_env.ps1')

$oldCmake = Join-Path $global:TagKinDesktopRoot 'windows\runner\branding.g.cmake'
$oldName = $null
if (Test-Path $oldCmake) {
  $m = Select-String -Path $oldCmake -Pattern 'set\(BINARY_NAME "([^"]+)"\)'
  if ($m) { $oldName = $m.Matches[0].Groups[1].Value }
}

Write-Host '==> dart run tool/gen_branding.dart'
dart run tool/gen_branding.dart

$newName = $oldName
if (Test-Path $oldCmake) {
  $m = Select-String -Path $oldCmake -Pattern 'set\(BINARY_NAME "([^"]+)"\)'
  if ($m) { $newName = $m.Matches[0].Groups[1].Value }
}

$winBuild = Join-Path $global:TagKinDesktopRoot 'build\windows'
if ($oldName -and $newName -and $oldName -ne $newName -and (Test-Path $winBuild)) {
  Write-Host "==> exe filename changed ($oldName → $newName); clearing build/windows"
  Remove-Item -Recurse -Force $winBuild
}

Write-Host "==> branding complete ($newName.exe)"
Write-Host '    Pickup: quit the app, then from TagKin-Desktop/win/ run ./11_dev.ps1'
Write-Host '    (full relaunch; hot restart does not refresh the taskbar icon).'
