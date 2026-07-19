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
| [`101_setup.sh`](./101_setup.sh) | First clone (or after a toolchain change): `flutter pub get` + contract codegen. |
| [`102_codegen.sh`](./102_codegen.sh) | After the shared `@tagkin/contract` OpenAPI changes — regenerate Dart models. |
| [`104_analyze.sh`](./104_analyze.sh) | Static analysis bar (`flutter analyze`). |
| [`11_dev.sh`](./11_dev.sh) | Run the app on macOS (`flutter run -d macos`). |
| [`51_test_all.sh`](./51_test_all.sh) | All completed desktop subsystem bars in order (`106_test_d0`, …). Before a PR. |
| [`106_test_d0.sh`](./106_test_d0.sh) | D0 Foundation regression bar alone. |

## Example flows

**First clone:** `101_setup.sh` → `51_test_all.sh` → `11_dev.sh`.

**After a contract change:** `102_codegen.sh` → `106_test_d0.sh` (codegen determinism + parity) → `51_test_all.sh`.
