# TagKin Desktop

Flutter/Dart desktop client for **TagKin** (Windows, macOS).

TagKin is a multi-user orchestration service for family photos and videos that auto-tags and links people **without ever reading or storing user media**. This desktop app handles local-first work: folder enumeration, batch ingest, local → user-cloud copy, client → model-host upload, local viewing, and heavy video key-period review.

## Canonical documentation

Product specs, hard rules, tech choices, and system architecture live in the **`tagkin`** repo under `Docs/` (single source of truth):

- Rules (hard constraints) — `tagkin/Docs/Rules.md`
- Product specs — `tagkin/Docs/Specs_Initial.md`
- Tech solutions — `tagkin/Docs/Tech_Solutions.md`
- Client strategy — `tagkin/Docs/web_and_client_considerations.md`
- System design (projects, repos, data flow) — `tagkin/Docs/System_Design.md`

Do not duplicate product docs here. This README covers **desktop-specific** setup only.

## Key constraints (see `tagkin/Docs/Rules.md`)

- **R1** — never read or store user media bytes on TagKin servers.
- **R2** — UI terms ≡ code terms; domain models are generated from the shared API contract (`@tagkin/contract`) so Dart names match the TypeScript/DB names.
- **R5** — media moves client → model host / client → user cloud, never through TagKin.
- **R6** — person likeness links require human confirmation and correction.

## Prerequisites

- Flutter SDK (stable channel)
- Desktop tooling: Visual Studio (Windows) / Xcode (macOS)

## Getting started

```bash
flutter pub get
flutter run -d windows   # or: flutter run -d macos
```

## Build

```bash
flutter build windows
flutter build macos
```
