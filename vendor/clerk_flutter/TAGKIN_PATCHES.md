# TagKin patches on clerk_flutter 0.0.18-beta

This directory is a pin of upstream `clerk_flutter` `0.0.18-beta` with UX edits for desktop auth:

1. **`lib/src/widgets/authentication/clerk_sign_in_panel.dart`** — after email, Enter prefers `emailCode` (when Clerk supports it) over password, and auto-advances that factor when it appears in the factor list so a code is sent without an extra strategy-button tap.
2. **`lib/src/widgets/ui/strategy_button.dart`** — strategy rows (“Email code to …”) use `ClerkMaterialButtonStyle.light` (background + dark label), height 48 for two-line labels — not filled accent.
3. **`lib/src/widgets/ui/clerk_control_buttons.dart`** — Back uses `ClerkMaterialButtonStyle.light` (secondary). Continue stays dark/primary.
4. **`lib/src/clerk_auth_state.dart`** — `_SsoWebViewOverlay` guards `setBackgroundColor` with `try`/`on UnimplementedError` so Google (and other) SSO WebViews do not crash on macOS (`opaque is not implemented on macOS`).
5. **`lib/src/clerk_auth_state.dart`** — SSO `showDialog` builders wrap `_SsoWebViewOverlay` in `ClerkAuth(authState: this)` so root-navigator dialogs still resolve `ClerkAuth` when the app nests `ClerkAuth` under `MaterialApp.home` (avoids `No ClerkAuth found in context`).

When upgrading Clerk, re-copy the upstream package and re-apply these edits.
