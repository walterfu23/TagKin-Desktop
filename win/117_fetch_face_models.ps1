# Fetch InsightFace buffalo_l ONNX weights for on-device face embed (R1).
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Dest = if ($env:TAGKIN_FACE_MODELS_DIR) { $env:TAGKIN_FACE_MODELS_DIR } else { Join-Path $Root "assets\models" }
New-Item -ItemType Directory -Force -Path $Dest | Out-Null

# Runtime lookup (packaged app cwd is not the repo) — always install here too.
$AppDataModels = Join-Path $env:APPDATA "tagkin\models"
New-Item -ItemType Directory -Force -Path $AppDataModels | Out-Null

$ZipUrl = if ($env:TAGKIN_BUFFALO_URL) { $env:TAGKIN_BUFFALO_URL } else { "https://github.com/deepinsight/insightface/releases/download/v0.7/buffalo_l.zip" }
$Tmp = Join-Path $env:TEMP ("tagkin_buffalo_" + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null
try {
  Write-Host "==> Downloading buffalo_l models -> $Dest"
  $ZipPath = Join-Path $Tmp "buffalo_l.zip"
  Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipPath
  Expand-Archive -Path $ZipPath -DestinationPath (Join-Path $Tmp "buffalo") -Force
  Get-ChildItem -Path (Join-Path $Tmp "buffalo") -Recurse -Filter "w600k_r50.onnx" | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $Dest "w600k_r50.onnx") -Force
  }
  Get-ChildItem -Path (Join-Path $Tmp "buffalo") -Recurse -Filter "det_10g.onnx" | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $Dest "det_10g.onnx") -Force
  }
  if (-not (Test-Path (Join-Path $Dest "w600k_r50.onnx"))) {
    throw "w600k_r50.onnx not found in archive"
  }
  Copy-Item (Join-Path $Dest "w600k_r50.onnx") (Join-Path $AppDataModels "w600k_r50.onnx") -Force
  if (Test-Path (Join-Path $Dest "det_10g.onnx")) {
    Copy-Item (Join-Path $Dest "det_10g.onnx") (Join-Path $AppDataModels "det_10g.onnx") -Force
  }
  Write-Host "==> Installed (repo):"
  Get-ChildItem (Join-Path $Dest "*.onnx") | Format-Table Name, Length
  Write-Host "==> Installed (runtime): $AppDataModels"
  Get-ChildItem (Join-Path $AppDataModels "*.onnx") | Format-Table Name, Length
  Write-Host ""
  Write-Host "Next: fully quit the app and re-run the win/macos start script so Flutter"
  Write-Host "bundles assets/models/*.onnx. Hot reload is not enough after a first fetch."
  Write-Host "Look for: OnnxFaceEmbedder: loaded asset assets/models/w600k_r50.onnx"
  Write-Host "Optional: TAGKIN_FACE_RECOG_MODEL / TAGKIN_FACE_DET_MODEL for custom paths."
  Write-Host "License: InsightFace model zoo — review before redistribution."
}
finally {
  Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}
