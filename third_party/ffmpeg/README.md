# Bundled FFmpeg for tagkin-desktop (D4)

End users **never** install ffmpeg themselves. Release and local app builds
ship self-contained `ffmpeg` + `ffprobe` inside the app bundle; Dart resolves
them via [`lib/prepass/ffmpeg_resolve.dart`](../lib/prepass/ffmpeg_resolve.dart).

## Layout (after fetch)

```text
third_party/ffmpeg/
  macos/ffmpeg
  macos/ffprobe
  windows/ffmpeg.exe
  windows/ffprobe.exe
```

Binaries are **gitignored** (large). Fetch them with:

```bash
# macOS (from TagKin-Desktop/mac/)
./105_fetch_ffmpeg.sh

# Windows (from TagKin-Desktop/win/)
./105_fetch_ffmpeg.ps1
```

`101_setup` runs the fetch automatically. Binaries must be **static /
redistributable** (not Homebrew bottle copies — those link `/opt/homebrew`
and will not run on user machines).

## How they get into the app

| OS | Mechanism |
|----|-----------|
| macOS | Xcode “Bundle FFmpeg” script copies `third_party/ffmpeg/macos/*` → `Contents/Resources/ffmpeg/` |
| Windows | CMake `install` copies `third_party/ffmpeg/windows/*` → `<exe>/ffmpeg/` |

## Dev / CI

- Preferred: run `105_fetch_ffmpeg` once so `flutter run` / release builds embed the same binaries end users get.
- PATH ffmpeg remains a last-resort fallback for CI machines that already have it; it is **not** a product or end-user requirement.
