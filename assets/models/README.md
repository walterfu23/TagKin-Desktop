# Face ONNX models (not committed — large binaries)

Run from `TagKin-Desktop/mac/`:

```bash
./117_fetch_face_models.sh
```

(Windows: `TagKin-Desktop/win/117_fetch_face_models.ps1`.)

Then **fully rebuild** the app (`./11_dev.sh` / quit + relaunch) so Flutter
bundles the weights. Hot reload/restart is **not** enough after a first fetch.

Installs InsightFace `buffalo_l` into `assets/models/`:

- `w600k_r50.onnx` — ArcFace recognizer (declared in `pubspec.yaml` assets)
- `det_10g.onnx` — optional detector

At runtime the app loads via `createSessionFromAsset` (works under macOS App
Sandbox). On-disk / Application Support paths remain a fallback.

Console success line: `OnnxFaceEmbedder: loaded asset assets/models/w600k_r50.onnx`

Without models → stub → who-linking skipped → empty Persons list.

**License:** InsightFace model zoo — review before redistributing weights.
