# Mac routine scripts (`tagkin-desktop`)

Thin wrappers for common Flutter operations on macOS. Each script ensures the Flutter SDK is on `PATH` and `cd`s to the desktop repo root via `_env.sh`. A parallel PowerShell set for Windows lives in [`../win/`](../win/) at identical numbers.

**Prefer running from this directory** (`TagKin-Desktop/mac/`) so tab-completion finds scripts quickly:

```bash
cd /path/to/TagKin-Desktop/mac
./101_setup.sh
```

Do **not** run `_env.sh` — it is sourced by the numbered scripts.

## Numbering bands

| Band | Purpose |
|------|---------|
| **11-49** | All-inclusive **ops** (run the app, multi-step helpers) |
| **51-99** | All-inclusive **tests** |
| **101+** | Regular single-purpose scripts (setup, codegen, analyze, per-subsystem bars) |

## Naming: subsystem test scripts

Subsystem regression entry points use **`NNN_test_dN.sh`** (`d0`, `d1`, … `d11`) in the **101+** band, matching the desktop subsystems in [`../../TagKin/Docs/Desktop_Subsystems_v1.md`](../../TagKin/Docs/Desktop_Subsystems_v1.md). Keep the `mac/*.sh` and `win/*.ps1` sets at identical numbers. Examples: `106_test_d0.sh`, `107_test_d1.sh`.

Do **not** reuse the API `sN` ids (those are the `tagkin` repo's `TagKin/mac/`); desktop bars are `dN`.

## Scripts

| Script | When |
|--------|------|
| [`101_setup.sh`](./101_setup.sh) | First clone (or after a toolchain change): `flutter pub get` + contract codegen + fetch bundled ffmpeg. |
| [`102_codegen.sh`](./102_codegen.sh) | After the shared `@tagkin/contract` OpenAPI changes — regenerate Dart models. |
| [`103_clerk-env.sh`](./103_clerk-env.sh) | Interactive Clerk publishable-key + API URL into `.env` (D1; never secret key). |
| [`104_analyze.sh`](./104_analyze.sh) | Static analysis bar (`flutter analyze`). |
| [`105_fetch_ffmpeg.sh`](./105_fetch_ffmpeg.sh) | Download/copy ffmpeg+ffprobe into `third_party/ffmpeg/macos/` for embedding in the `.app` (D4; end users never install ffmpeg). |
| [`111_clear_secure_store.sh`](./111_clear_secure_store.sh) | Wipe Keychain items for `tagkin.desktop.secure` (D1; force clean sign-in / stop repeat access prompts). |
| [`11_dev.sh`](./11_dev.sh) | Clear secure store, then run the app on macOS (`flutter run -d macos`). |
| [`51_test_all.sh`](./51_test_all.sh) | All completed desktop subsystem bars in order (`106_test_d0`, `107_test_d1`, `108_test_d2`, …). Before a PR. |
| [`106_test_d0.sh`](./106_test_d0.sh) | D0 Foundation regression bar alone. |
| [`107_test_d1.sh`](./107_test_d1.sh) | D1 Auth & Account regression bar alone. |
| [`108_test_d2.sh`](./108_test_d2.sh) | D2 Library & Item Registry regression bar alone. |
| [`109_test_d3.sh`](./109_test_d3.sh) | D3 Local Folder Ingest & Batch regression bar alone. |
| [`110_test_d4.sh`](./110_test_d4.sh) | D4 Client Pre-pass regression bar alone. |
| [`111_test_d6.sh`](./111_test_d6.sh) | D6 Cost & Usage Surface regression bar alone. |
| [`112_test_d5.sh`](./112_test_d5.sh) | D5 Ingest Upload & Grants regression bar alone. |
| [`113_test_d7.sh`](./113_test_d7.sh) | D7 Tagging & Jobs Lifecycle regression bar alone. |
| [`114_test_d8.sh`](./114_test_d8.sh) | D8 Review UI (item detail + key-period scrub) regression bar alone. |
| [`115_test_d9.sh`](./115_test_d9.sh) | D9 Person Linking UI regression bar alone. |
| [`116_test_d10.sh`](./116_test_d10.sh) | D10 Knowledge Corrections & Comments UI regression bar alone. |

## Example flows

**First clone:** `101_setup.sh` → `103_clerk-env.sh` (live sign-in) → `51_test_all.sh` → `11_dev.sh`.

**After a contract change:** `102_codegen.sh` → `106_test_d0.sh` (codegen determinism + parity) → `51_test_all.sh`.

**Auth only:** `107_test_d1.sh` (mocked; no live Clerk required).

**Library only:** `108_test_d2.sh` (mocked items API; no live network required).