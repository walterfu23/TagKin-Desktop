# TagKin patches on clerk_flutter 0.0.18-beta

This directory is a pin of upstream `clerk_flutter` `0.0.18-beta` with two UX edits for desktop 2FA:

1. **`lib/src/widgets/ui/strategy_button.dart`** — strategy rows (“Email code to …”) use `ClerkMaterialButton` dark (filled accent + white label), height 48 for two-line labels.
2. **`lib/src/widgets/ui/clerk_control_buttons.dart`** — Back uses `ClerkMaterialButtonStyle.light` (secondary). Continue stays dark/primary.

When upgrading Clerk, re-copy the upstream package and re-apply these two edits.
