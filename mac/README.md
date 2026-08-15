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

Subsystem regression entry points use **`NNN_test_dN.sh`** (`d0`, `d1`, … `d12`) in the **101+** band, matching the desktop subsystems in [`../../TagKin/Docs/Desktop_Subsystems_v1.md`](../../TagKin/Docs/Desktop_Subsystems_v1.md). Keep the `mac/*.sh` and `win/*.ps1` sets at identical numbers. Examples: `106_test_d0.sh`, `107_test_d1.sh`, `117_test_d12.sh`. D11 (packaging/signing) has no bar yet.

Do **not** reuse the API `sN` ids (those are the `tagkin` repo's `TagKin/mac/`); desktop bars are `dN`.

## Scripts

| Script | When |
|--------|------|
| [`101_setup.sh`](./101_setup.sh) | First clone (or after a toolchain change): `flutter pub get` + contract codegen + fetch bundled ffmpeg. |
| [`102_codegen.sh`](./102_codegen.sh) | After the shared `@tagkin/contract` OpenAPI changes — regenerate Dart models. |
| [`119_fetch_face_models.sh`](./119_fetch_face_models.sh) | Download InsightFace ONNX weights for cross-photo person linking (optional; large). |
| [`103_clerk-env.sh`](./103_clerk-env.sh) | Interactive Clerk publishable-key + API URL into `.env` (D1; never secret key). |
| [`104_analyze.sh`](./104_analyze.sh) | Static analysis bar (`flutter analyze`). |
| [`105_fetch_ffmpeg.sh`](./105_fetch_ffmpeg.sh) | Download/copy ffmpeg+ffprobe into `third_party/ffmpeg/macos/` for embedding in the `.app` (D4; end users never install ffmpeg). |
| [`118_clear_secure_store.sh`](./118_clear_secure_store.sh) | Wipe Keychain items for `tagkin.desktop.secure` (D1; force clean sign-in / stop repeat access prompts). |
| [`122_wipe_Devtime.sh`](./122_wipe_Devtime.sh) | **Devtime only.** Wipe collections, prefs, bookmarks, and Keychain session (`CONFIRM=1`). Pair with `TagKin/mac/122_wipe_Devtime.sh` for Postgres. Does not delete media or face models. |
| [`11_dev.sh`](./11_dev.sh) | Clear secure store, lsregister the debug app (Safari Allow for `tagkindesktop://`), then run on macOS. |
| [`12_person_link_loop.sh`](./12_person_link_loop.sh) | Ops: delete suggested persons → re-analyze item ids → who-face link; repeat until Persons consolidate (max 20). Needs `TAGKIN_API_TOKEN` + `TAGKIN_LOOP_ITEM_IDS`. |
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
| [`117_test_d12.sh`](./117_test_d12.sh) | D12 Per-screen Undo/Redo regression bar alone. |

## Pick up a code change

After an agent or local edit, load the new code before verifying in the UI:

| What changed | What to do |
|--------------|------------|
| Dart/UI only, and `./11_dev.sh` is already running | In that Flutter terminal, press **`R`** (hot restart). `r` (hot reload) is often enough for small widget tweaks; prefer **`R`** after controller/navigation/label changes. |
| App not running, or native / plugin / asset / `.env` change | `./11_dev.sh` (full relaunch). |
| Shared OpenAPI / `@tagkin/contract` | `./102_codegen.sh`, then hot restart or `./11_dev.sh`. |
| API / DB (in `tagkin`) | Restart the API stack from `TagKin/mac/` (`./11_dev-stack.sh`, which calls `./12` first), then pick up desktop as above. |

## Example flows

**First clone:** `101_setup.sh` → `103_clerk-env.sh` (live sign-in) → `51_test_all.sh` → `11_dev.sh`.

**After a contract change:** `102_codegen.sh` → `106_test_d0.sh` (codegen determinism + parity) → `51_test_all.sh`.

**Auth only:** `107_test_d1.sh` (mocked; no live Clerk required).

**Library only:** `108_test_d2.sh` (mocked items API; no live network required).
**Person-link consolidation loop** (API up, face models fetched, 3 photo item ids):

```bash
export TAGKIN_API_TOKEN='…'   # Bearer from a signed-in session — do not commit
export TAGKIN_LOOP_ITEM_IDS='uuid1,uuid2,uuid3'
./12_person_link_loop.sh
```
