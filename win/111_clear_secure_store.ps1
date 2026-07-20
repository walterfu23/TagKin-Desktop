# 111_clear_secure_store.ps1 — wipe D1 Windows Credential Manager entries
# written by FlutterSecureStorage (service / target name containing
# tagkin.desktop.secure). Mirror of mac/111_clear_secure_store.sh.
$ErrorActionPreference = 'Stop'
$winDir = Split-Path -Parent $PSCommandPath
. (Join-Path $winDir '_env.ps1')

$needle = 'tagkin.desktop.secure'
Write-Host "==> scanning Credential Manager for '$needle'"

# cmdkey lists persisted credentials; filter TagKin secure-store targets.
$listed = cmdkey /list 2>&1 | Out-String
$targets = [regex]::Matches($listed, '(?m)^\s*Target:\s*(.+)$') |
  ForEach-Object { $_.Groups[1].Value.Trim() } |
  Where-Object { $_ -like "*$needle*" -or $_ -like '*tagkin.clerk*' }

if (-not $targets) {
  Write-Host '==> nothing to delete'
  exit 0
}

$deleted = 0
foreach ($t in $targets) {
  Write-Host "    deleting $t"
  cmdkey /delete:$t | Out-Null
  $deleted++
}
Write-Host "==> deleted $deleted"
Write-Host '==> quit tagkin_desktop fully, then relaunch'
