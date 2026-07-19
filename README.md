# TagKin Desktop

Flutter/Dart desktop client for **TagKin** (Windows, macOS).

TagKin is a multi-user orchestration service for family photos and videos that auto-tags and links people **without ever reading or storing user media**. This desktop app handles local-first work: folder enumeration, batch ingest, local → user-cloud copy, client → model-host upload of **individual sample frames**, local viewing, and key-period review.

## Canonical documentation

Product specs, hard rules, tech choices, and system architecture live in the **`tagkin`** repo under `Docs/` (single source of truth):

- Rules (hard constraints) — `tagkin/Docs/Rules.md`
- Product specs — `tagkin/Docs/Specs_Initial.md`
- Tech solutions — `tagkin/Docs/Tech_Solutions.md`
- System design (projects, repos, client strategy, data flow) — `tagkin/Docs/System_Design.md`

Do not duplicate product docs here. This README covers **desktop-specific** setup only.

## Key constraints (see `tagkin/Docs/Rules.md`)

- **R1** — never read or store user media bytes on TagKin servers.
- **R2** — UI terms ≡ code terms; domain models are generated from the shared API contract (`@tagkin/contract`) so Dart names match the TypeScript/DB names.
- **R5** — media moves client → model host / client → user cloud, never through TagKin.
- **R6** — human authority over generated knowledge: person links and all other dimensions (activities, places, times, key periods) are confirmable/correctable with provenance and undo.
- **R9** — analysis uses individual sample frames (no video model) on a cloud vendor today; the provider stays pluggable to swap in a self-hosted model later.
- **R10** — records are account-scoped; export and delete are explicit behavior.

## Prerequisites

- Flutter SDK (stable channel)
- Desktop tooling: Visual Studio (Windows) / Xcode (macOS)
- The sibling **`tagkin`** repo checked out next to this one (the shared `@tagkin/contract` OpenAPI is read for Dart model codegen).

## Getting started

Convenience scripts live in [`mac/`](./mac/) (bash) and [`win/`](./win/) (PowerShell); prefer running from those directories for tab-completion.

```bash
# macOS
cd mac && ./101_setup.sh          # flutter pub get + contract codegen
./11_dev.sh                       # flutter run -d macos
```

```powershell
# Windows
cd win; ./101_setup.ps1           # flutter pub get + contract codegen
./11_dev.ps1                      # flutter run -d windows
```

Raw equivalents: `flutter pub get && dart run tool/gen_contract.dart` then `flutter run -d macos` (or `-d windows`).

## Subsystems (build order)

The desktop client is built subsystem-by-subsystem (**D0-D11**), each with its own regression bar. The canonical decomposition, responsibilities, and per-subsystem regression sets live in the `tagkin` repo: **`tagkin/Docs/Desktop_Subsystems_v1.md`**. Build in dependency order (D0 → D1 → D2 → …); each subsystem lands a `NNN_test_dN` bar that must stay green on macOS and Windows.

- **D0 Foundation** — this scaffold: Flutter (macOS+Windows), Riverpod, Dart contract codegen (`tool/gen_contract.dart` → `lib/contract/contract.dart`), terminology parity (R2), test harness, CI. Bar: `106_test_d0`.
- **D1-D11** — auth, library, local folder ingest, pre-pass, upload/grants, cost surface, tagging/jobs, review UI, person linking, corrections/comments, packaging. See the doc above.

## Testing

```bash
cd mac && ./106_test_d0.sh        # a single subsystem bar (D0)
./51_test_all.sh                  # every completed D-series bar, in order
```

`104_analyze.sh` / `104_analyze.ps1` run `flutter analyze` alone. Windows uses the identical `win/*.ps1` numbers.

## Debug profiles (Cursor / VS Code)

Flutter debug configurations for both OSes are in [`.vscode/launch.json`](./.vscode/launch.json) (via the Dart/Flutter extension): "Flutter (macOS · debug)", "Flutter (Windows · debug)", profile variants, and integration-test runners. Open the multi-root `TagKin.code-workspace` at the workspace root to debug this app alongside the API.

## Build (release)

```bash
flutter build windows
flutter build macos
```

Packaging/signing/update is subsystem **D11**.
