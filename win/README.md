# Windows routine scripts (`tagkin-desktop`)

PowerShell wrappers for common Flutter operations on Windows — the mirror of [`../mac/`](../mac/) at identical numbers. Each script dot-sources `_env.ps1`, which ensures the Flutter SDK is on `PATH` and `cd`s to the desktop repo root.

**Prefer running from this directory** (`TagKin-Desktop\win\`):

```powershell
cd C:\path\to\TagKin-Desktop\win
./101_setup.ps1
```

If scripts are blocked by execution policy, run once per session:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Do **not** run `_env.ps1` — it is dot-sourced by the numbered scripts.

## Numbering bands

| Band | Purpose |
|------|---------|
| **11-49** | All-inclusive **ops** (run the app, multi-step helpers) |
| **51-99** | All-inclusive **tests** |
| **101+** | Regular single-purpose scripts (setup, codegen, analyze, per-subsystem bars) |

## Naming: subsystem test scripts

Subsystem regression entry points use **`NNN_test_dN.ps1`** (`d0`, `d1`, … `d11`) in the **101+** band, matching the desktop subsystems in [`../../TagKin/Docs/Desktop_Subsystems_v1.md`](../../TagKin/Docs/Desktop_Subsystems_v1.md). Keep the `win/*.ps1` and `mac/*.sh` sets at identical numbers. Examples: `106_test_d0.ps1`, `107_test_d1.ps1`.

## Scripts

| Script | When |
|--------|------|
| [`101_setup.ps1`](./101_setup.ps1) | First clone (or after a toolchain change): `flutter pub get` + contract codegen + fetch bundled ffmpeg. |
| [`102_codegen.ps1`](./102_codegen.ps1) | After the shared `@tagkin/contract` OpenAPI changes — regenerate Dart models. |
| [`103_clerk-env.ps1`](./103_clerk-env.ps1) | Interactive Clerk publishable-key + API URL into `.env` (D1; never secret key). |
| [`104_analyze.ps1`](./104_analyze.ps1) | Static analysis bar (`flutter analyze`). |
| [`105_fetch_ffmpeg.ps1`](./105_fetch_ffmpeg.ps1) | Download ffmpeg+ffprobe into `third_party/ffmpeg/windows/` for embedding next to the exe (D4; end users never install ffmpeg). |
| [`111_clear_secure_store.ps1`](./111_clear_secure_store.ps1) | Wipe Credential Manager entries for `tagkin.desktop.secure` (D1; force clean sign-in). |
| [`11_dev.ps1`](./11_dev.ps1) | Run the app on Windows (`flutter run -d windows`). |
| [`51_test_all.ps1`](./51_test_all.ps1) | All completed desktop subsystem bars in order (`106_test_d0`, `107_test_d1`, `108_test_d2`, …). Before a PR. |
| [`106_test_d0.ps1`](./106_test_d0.ps1) | D0 Foundation regression bar alone. |
| [`107_test_d1.ps1`](./107_test_d1.ps1) | D1 Auth & Account regression bar alone. |
| [`108_test_d2.ps1`](./108_test_d2.ps1) | D2 Library & Item Registry regression bar alone. |
| [`109_test_d3.ps1`](./109_test_d3.ps1) | D3 Local Folder Ingest & Batch regression bar alone. |
| [`110_test_d4.ps1`](./110_test_d4.ps1) | D4 Client Pre-pass regression bar alone. |
| [`111_test_d6.ps1`](./111_test_d6.ps1) | D6 Cost & Usage Surface regression bar alone. |
| [`112_test_d5.ps1`](./112_test_d5.ps1) | D5 Ingest Upload & Grants regression bar alone. |
| [`113_test_d7.ps1`](./113_test_d7.ps1) | D7 Tagging & Jobs Lifecycle regression bar alone. |
| [`114_test_d8.ps1`](./114_test_d8.ps1) | D8 Review UI (item detail + key-period scrub) regression bar alone. |
| [`115_test_d9.ps1`](./115_test_d9.ps1) | D9 Person Linking UI regression bar alone. |
| [`116_test_d10.ps1`](./116_test_d10.ps1) | D10 Knowledge Corrections & Comments UI regression bar alone. |
