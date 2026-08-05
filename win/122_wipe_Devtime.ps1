# 122_wipe_Devtime.ps1 — DEVELOPMENT ONLY. Wipe desktop residuals so the next
# launch starts from scratch: Credential Manager session, collections
# (collections.json), prefs, and folder bookmarks under %APPDATA%\tagkin_desktop.
#
# Does NOT delete: user media files, third_party/, face models, or API/Postgres
# data (run TagKin/mac/122_wipe_Devtime.sh for the server wipe).
#
# Quit tagkin_desktop fully before running.
#
# Usage:
#   $env:CONFIRM='1'; .\122_wipe_Devtime.ps1
$ErrorActionPreference = 'Stop'
$winDir = Split-Path -Parent $PSCommandPath
. (Join-Path $winDir '_env.ps1')

$supportDir = Join-Path $env:APPDATA 'tagkin_desktop'
$needle = 'tagkin.desktop.secure'

Write-Host '==> 122_wipe_Devtime (desktop) — DEVELOPMENT ONLY'
Write-Host '    Wipes:'
Write-Host "      - Credential Manager targets matching '$needle'"
Write-Host "      - $supportDir (collections.json, prefs, bookmarks, …)"
Write-Host '    Does not delete original media or face models.'
Write-Host '    API/Postgres: TagKin/mac/122_wipe_Devtime.sh'
Write-Host ''
Write-Host '    Quit tagkin_desktop fully before continuing.'
Write-Host ''

if ($env:CONFIRM -ne '1') {
  $ans = Read-Host 'Type y to wipe desktop collections/session/prefs'
  if ($ans -ne 'y' -and $ans -ne 'Y') {
    Write-Host '==> aborted'
    exit 1
  }
}

Write-Host "==> clearing Credential Manager for '$needle'"
$listed = cmdkey /list 2>&1 | Out-String
$targets = [regex]::Matches($listed, '(?m)^\s*Target:\s*(.+)$') |
  ForEach-Object { $_.Groups[1].Value.Trim() } |
  Where-Object { $_ -like "*$needle*" -or $_ -like '*tagkin.clerk*' }

$deleted = 0
foreach ($t in $targets) {
  Write-Host "    deleting $t"
  cmdkey /delete:$t | Out-Null
  $deleted++
}
Write-Host "    deleted $deleted credential target(s)"

if (Test-Path -LiteralPath $supportDir) {
  Write-Host "==> removing $supportDir"
  Remove-Item -LiteralPath $supportDir -Recurse -Force
} else {
  Write-Host "==> no APPDATA dir at $supportDir"
}
New-Item -ItemType Directory -Path $supportDir -Force | Out-Null

Write-Host '==> 122_wipe_Devtime (desktop) complete'
Write-Host '    Next: restart API stack if wiped, then .\11_dev.ps1'
