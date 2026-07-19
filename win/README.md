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
| [`101_setup.ps1`](./101_setup.ps1) | First clone (or after a toolchain change): `flutter pub get` + contract codegen. |
| [`102_codegen.ps1`](./102_codegen.ps1) | After the shared `@tagkin/contract` OpenAPI changes — regenerate Dart models. |
| [`103_clerk-env.ps1`](./103_clerk-env.ps1) | Interactive Clerk publishable-key + API URL into `.env` (D1; never secret key). |
| [`104_analyze.ps1`](./104_analyze.ps1) | Static analysis bar (`flutter analyze`). |
| [`11_dev.ps1`](./11_dev.ps1) | Run the app on Windows (`flutter run -d windows`). |
| [`51_test_all.ps1`](./51_test_all.ps1) | All completed desktop subsystem bars in order (`106_test_d0`, `107_test_d1`, …). Before a PR. |
| [`106_test_d0.ps1`](./106_test_d0.ps1) | D0 Foundation regression bar alone. |
| [`107_test_d1.ps1`](./107_test_d1.ps1) | D1 Auth & Account regression bar alone. |
