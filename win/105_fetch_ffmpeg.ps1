# 105_fetch_ffmpeg.ps1 — place static ffmpeg+ffprobe into
# third_party/ffmpeg/windows/ so the Windows build ships them next to the
# exe (end users never winget/choco-install ffmpeg).
$ErrorActionPreference = 'Stop'
$winDir = Split-Path -Parent $PSCommandPath
. (Join-Path $winDir '_env.ps1')

$dest = Join-Path $global:TagKinDesktopRoot 'third_party\ffmpeg\windows'
New-Item -ItemType Directory -Force -Path $dest | Out-Null

Write-Host '==> fetching ffmpeg/ffprobe into third_party/ffmpeg/windows/'

$tmp = Join-Path $env:TEMP ("tagkin_ffmpeg_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
  # Static-ish win64 GPL build (single bin/ with ffmpeg + ffprobe).
  $url = 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip'
  $zip = Join-Path $tmp 'ffmpeg.zip'
  Write-Host "==> downloading $url"
  Invoke-WebRequest -Uri $url -OutFile $zip

  Expand-Archive -Path $zip -DestinationPath $tmp -Force
  $binDir = Get-ChildItem -Path $tmp -Recurse -Directory -Filter 'bin' |
    Select-Object -First 1
  if (-not $binDir) {
    throw 'ffmpeg zip did not contain a bin/ directory'
  }

  Copy-Item (Join-Path $binDir.FullName 'ffmpeg.exe') (Join-Path $dest 'ffmpeg.exe') -Force
  Copy-Item (Join-Path $binDir.FullName 'ffprobe.exe') (Join-Path $dest 'ffprobe.exe') -Force

  Write-Host '==> installed:'
  Get-ChildItem $dest | ForEach-Object { Write-Host $_.FullName }
  & (Join-Path $dest 'ffmpeg.exe') -version | Select-Object -First 1
  & (Join-Path $dest 'ffprobe.exe') -version | Select-Object -First 1
  Write-Host '==> fetch complete — rebuild the Windows app to copy next to the exe'
}
finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
